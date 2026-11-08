#!/usr/bin/env node
// Runs LNReader plugins (the compiled .js files from lnreader-plugins' .dist) for the novel server.
//
// Talks to novel_server over stdin/stdout, one JSON object per line:
//   python -> host   {id, op: "call", plugin, method, args}      run a plugin method
//                    {id, op: "meta", plugin}                    name, site, filters, ...
//                    {id, op: "unload", plugin}                  forget a plugin (reinstalled/removed)
//   host -> python   {id, ok: true, result} | {id, ok: false, error}
//   host -> python   {hid, op: "http", url, method, headers, body}   a plugin's fetch, done by python
//   python -> host   {hid, status, statusText, headers, body, url} | {hid, error}   (body is base64)
//
// Plugin fetches go through python so they use the same curl_cffi session (browser TLS fingerprint)
// as the other sources; plain Node fetch gets turned away by most Cloudflare-fronted sites.
//
// Usage: node lnreader_host.js --plugins <dir of <id>.js files> --modules <dir with node_modules>
'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { createRequire } = require('module');

const argv = process.argv.slice(2);
function arg(name, fallback) {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}
const PLUGINS_DIR = arg('plugins', path.join(process.cwd(), 'plugins'));
const MODULES_DIR = arg('modules', process.cwd());

// stdout is the protocol channel: anything a plugin prints goes to stderr instead.
for (const level of ['log', 'info', 'debug', 'warn']) {
  console[level] = (...a) => process.stderr.write('[plugin] ' + a.map(String).join(' ') + '\n');
}

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// ── fetch, done by python ──────────────────────────────────────────────────

let nextHid = 1;
const pendingHttp = new Map();

function headersToObject(h) {
  const out = {};
  if (!h) return out;
  if (typeof h.forEach === 'function' && !Array.isArray(h)) {
    h.forEach((v, k) => { out[k] = v; });
  } else if (Array.isArray(h)) {
    for (const [k, v] of h) out[k] = v;
  } else {
    for (const k of Object.keys(h)) out[k] = h[k];
  }
  return out;
}

function encodeBody(init, headers) {
  const body = init.body;
  if (body == null) return null;
  if (typeof body === 'string') return Buffer.from(body, 'utf8').toString('base64');
  if (body instanceof URLSearchParams) {
    if (!Object.keys(headers).some(k => k.toLowerCase() === 'content-type')) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return Buffer.from(body.toString(), 'utf8').toString('base64');
  }
  if (Buffer.isBuffer(body) || body instanceof Uint8Array) return Buffer.from(body).toString('base64');
  if (typeof FormData !== 'undefined' && body instanceof FormData) {
    // multipart: let Node build the boundary and body
    const req = new Request('http://x.invalid/', { method: 'POST', body });
    headers['Content-Type'] = req.headers.get('content-type');
    return req.arrayBuffer().then(b => Buffer.from(b).toString('base64'));
  }
  return Buffer.from(String(body), 'utf8').toString('base64');
}

async function fetchApi(url, init) {
  init = init || {};
  const headers = headersToObject(init.headers);
  const body = await encodeBody(init, headers);
  const hid = nextHid++;
  const reply = await new Promise((resolve, reject) => {
    pendingHttp.set(hid, { resolve, reject });
    send({
      hid, op: 'http', url: String(url),
      method: String(init.method || 'GET').toUpperCase(), headers, body,
    });
  });
  const buf = Buffer.from(reply.body || '', 'base64');
  const noBody = [101, 204, 205, 304].includes(reply.status);
  const res = new Response(noBody ? null : buf, {
    status: reply.status,
    statusText: reply.statusText || '',
    headers: reply.headers || {},
  });
  Object.defineProperty(res, 'url', { value: reply.url || String(url) });
  return res;
}

async function fetchText(url, init, encoding) {
  const res = await fetchApi(url, init);
  if (!encoding || /^utf-?8$/i.test(encoding)) return res.text();
  return new TextDecoder(encoding).decode(await res.arrayBuffer());
}

async function fetchFile(url, init) {
  const res = await fetchApi(url, init);
  return Buffer.from(await res.arrayBuffer()).toString('base64');
}

// ── the modules a plugin may require ───────────────────────────────────────

const FilterTypes = {
  TextInput: 'Text',
  Picker: 'Picker',
  CheckboxGroup: 'Checkbox',
  Switch: 'Switch',
  ExcludableCheckboxGroup: 'XCheckbox',
};

const NovelStatus = {
  Unknown: 'Unknown',
  Ongoing: 'Ongoing',
  Completed: 'Completed',
  Licensed: 'Licensed',
  PublishingFinished: 'Publishing Finished',
  Cancelled: 'Cancelled',
  OnHiatus: 'On Hiatus',
};

function memoryStore() {
  const m = new Map();
  return {
    get: k => (m.has(k) ? m.get(k) : undefined),
    set: (k, v) => { m.set(k, v); },
    delete: k => { m.delete(k); },
    getAllKeys: () => Array.from(m.keys()),
    clearAll: () => m.clear(),
    getItem: k => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => { m.set(k, String(v)); },
    removeItem: k => { m.delete(k); },
  };
}
const sharedStore = memoryStore();

const hostRequire = createRequire(path.join(MODULES_DIR, 'noop.js'));
const DEFAULT_COVER = 'https://github.com/LNReader/lnreader-plugins/blob/master/public/static/coverNotAvailable.webp?raw=true';
const b64 = {
  utf8ToBase64: t => Buffer.from(String(t), 'utf8').toString('base64'),
  base64ToUtf8: t => Buffer.from(String(t), 'base64').toString('utf8'),
};
const builtins = {
  '@libs/fetch': { fetchApi, fetchText, fetchFile },
  '@libs/filterInputs': { FilterTypes },
  '@libs/novelStatus': { NovelStatus },
  '@libs/defaultCover': { defaultCover: DEFAULT_COVER },
  '@libs/isAbsoluteUrl': { isUrlAbsolute: u => /^(?:[a-z][a-z0-9+.-]*:)?\/\//i.test(String(u)) },
  '@libs/storage': { storage: sharedStore, localStorage: memoryStore(), sessionStorage: memoryStore() },
  '@libs/showToast': { showToast: () => {} },
  '@libs/utils': { ...b64 },
  // The plugin repo's own "@/" alias (src/types): compiled plugins require these too. The
  // type-only ones (plugin, ...) have nothing at runtime, so they resolve to an empty module.
  '@/types/constants': { NovelStatus, defaultCover: DEFAULT_COVER },
  '@/types/filters': { FilterTypes },
  '@/types/plugin': {},
  '@/types/index': {},
};
const npmModules = new Set(['cheerio', 'htmlparser2', 'dayjs', 'urlencode', 'qs']);

function pluginRequire(id) {
  if (Object.prototype.hasOwnProperty.call(builtins, id)) return builtins[id];
  if (npmModules.has(id)) {
    try {
      return hostRequire(id);
    } catch (e) {
      throw new Error(`the plugin needs "${id}", which is not installed in ${MODULES_DIR}/node_modules`);
    }
  }
  if (id.startsWith('@/types/')) return {};   // an unlisted type-only module of the plugin repo
  throw new Error(`the plugin needs "${id}", which the SekaiPop LNReader host does not provide`);
}

// ── plugins ────────────────────────────────────────────────────────────────

const loaded = new Map(); // id -> { mtime, plugin }

function loadPlugin(id) {
  if (!/^[\w.\-]+$/.test(id)) throw new Error('bad plugin id: ' + id);
  const file = path.join(PLUGINS_DIR, id + '.js');
  let stat;
  try {
    stat = fs.statSync(file);
  } catch (e) {
    throw new Error(`plugin "${id}" is not installed`);
  }
  const hit = loaded.get(id);
  if (hit && hit.mtime === stat.mtimeMs) return hit.plugin;

  const code = fs.readFileSync(file, 'utf8');
  const module_ = { exports: {} };
  new Function('require', 'module', 'exports', code)(pluginRequire, module_, module_.exports);
  let plugin = module_.exports && module_.exports.default ? module_.exports.default : module_.exports;
  if (typeof plugin === 'function') plugin = new plugin();
  if (!plugin || typeof plugin.parseNovel !== 'function') {
    throw new Error(`"${id}.js" is not an LNReader plugin (no parseNovel)`);
  }
  loaded.set(id, { mtime: stat.mtimeMs, plugin });
  return plugin;
}

// What the app hands popularNovels: every filter at its default value.
function defaultFilters(plugin) {
  const out = {};
  const defs = plugin.filters || {};
  for (const key of Object.keys(defs)) {
    out[key] = { type: defs[key].type, value: defs[key].value };
  }
  return out;
}

const METHODS = {
  popularNovels: (p, [page, showLatest, filters]) =>
    p.popularNovels(page || 1, {
      showLatestNovels: !!showLatest,
      filters: filters || defaultFilters(p),
    }),
  searchNovels: (p, [term, page]) => p.searchNovels(term, page || 1),
  parseNovel: (p, [novelPath]) => p.parseNovel(novelPath),
  parsePage: (p, [novelPath, page]) => {
    if (typeof p.parsePage !== 'function') throw new Error('this plugin has no paged chapter list');
    return p.parsePage(novelPath, String(page));
  },
  parseChapter: (p, [chapterPath]) => p.parseChapter(chapterPath),
};

async function handle(msg) {
  const plugin = msg.op === 'unload' ? null : loadPlugin(msg.plugin);
  if (msg.op === 'unload') {
    loaded.delete(msg.plugin);
    return true;
  }
  if (msg.op === 'meta') {
    return {
      id: plugin.id || msg.plugin,
      name: plugin.name || msg.plugin,
      site: plugin.site || '',
      version: plugin.version || '',
      filters: plugin.filters || null,
      hasParsePage: typeof plugin.parsePage === 'function',
      imageRequestInit: plugin.imageRequestInit || null,
    };
  }
  if (msg.op === 'call') {
    const fn = METHODS[msg.method];
    if (!fn) throw new Error('unknown method ' + msg.method);
    return fn(plugin, msg.args || []);
  }
  throw new Error('unknown op ' + msg.op);
}

const rl = readline.createInterface({ input: process.stdin });
rl.on('line', line => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (e) {
    return;
  }
  if (msg.hid !== undefined) {
    const p = pendingHttp.get(msg.hid);
    if (!p) return;
    pendingHttp.delete(msg.hid);
    if (msg.error) p.reject(new Error(msg.error));
    else p.resolve(msg);
    return;
  }
  Promise.resolve()
    .then(() => handle(msg))
    .then(result => send({ id: msg.id, ok: true, result: result === undefined ? null : result }))
    .catch(e => send({ id: msg.id, ok: false, error: String((e && e.message) || e) }));
});
rl.on('close', () => process.exit(0));

send({ ready: true, node: process.version });
