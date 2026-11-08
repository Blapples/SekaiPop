"""
LNReader provider: the novel reader's sources are LNReader plugins.

LNReader (https://github.com/LNReader/lnreader) gets every site from a small JavaScript plugin
(https://github.com/LNReader/lnreader-plugins). This provider downloads those compiled plugins,
runs them in a Node process (lnreader_host.js, which stands in for the app's plugin runtime) and
maps their five calls onto the reader's endpoints:

    popularNovels(page, {showLatestNovels})   hot() / latest(page)
    searchNovels(term, page)                  search()
    parseNovel(path) [+ parsePage]            info()
    parseChapter(path)                        chapter()

One plugin at a time is "the source" (the Source key in the Browse view); several can be installed.

IDs (raw, before the registry puts "lnreader:" in front). They hold no ":" and no "/" apart from
the one between novel and chapter, because the downloads folder is named from them:
  novel    "<plugin>~<quoted novel path>"                    e.g. "novelfull~%2Fshadow-slave.html"
  chapter  "<plugin>~<quoted novel path>/<quoted chapter path>"

Files, under ~/.local/share/sekaipop/readers/lnreader/ (SEKAIPOP_LNREADER_DIR overrides it):
  plugins/<id>.js   the installed plugins        state.json   repo address, installed list, active source
  node_modules/     cheerio, htmlparser2, dayjs, urlencode (npm install runs by itself on first start)
"""

import base64
import html as _html
import json
import os
import re
import shutil
import subprocess
import threading
import time
from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from urllib.parse import quote, unquote, urlsplit

from .base import NovelProvider
from . import utils
from .utils import cached

DATA_DIR = os.environ.get("SEKAIPOP_LNREADER_DIR") or os.path.expanduser(
    "~/.local/share/sekaipop/readers/lnreader")
PLUGINS_DIR = os.path.join(DATA_DIR, "plugins")
STATE_FILE = os.path.join(DATA_DIR, "state.json")
CATALOG_FILE = os.path.join(DATA_DIR, "catalog.json")
HOST_SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lnreader_host.js")

# The official plugin list sits on the repo's "plugins" branch, in one folder per release tag:
#   https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/<tag>/.dist/plugins.min.json
# With no address set, the newest tag folder is looked up through GitHub's contents API.
OFFICIAL_REPO = "LNReader/lnreader-plugins"
# The official list in the repositories list (its address changes with every release folder)
OFFICIAL_MARK = "official"
OFFICIAL_NAME = "LNReader official list"
# Suggested with one tap on the Repositories tab (while they are not in the list)
SUGGESTED_REPOS = [{"name": OFFICIAL_NAME, "url": OFFICIAL_MARK}]
TAGS_API = f"https://api.github.com/repos/{OFFICIAL_REPO}/contents?ref=plugins"
TAG_REPO = ("https://raw.githubusercontent.com/" + OFFICIAL_REPO
            + "/plugins/{tag}/.dist/plugins.min.json")
# Used when the tag lookup fails (GitHub's API allows 60 requests an hour per address without a token).
FALLBACK_TAG = "v3.0.0"

# Versions the plugins were built against (the plugin repo's own pins; adjust here if a plugin
# complains about a missing export).
NPM_PACKAGES = ["cheerio@1.0.0-rc.12", "htmlparser2@9", "dayjs@1", "urlencode@1"]

TTL_LIST = 300
TTL_INFO = 1800
TTL_CHAP = 86400
CATALOG_TTL = 6 * 3600
CALL_TIMEOUT = 90
MAX_CHAPTER_PAGES = 120

_ID_RE = re.compile(r"^[\w.\-]+$")


# ── Chapter html -> paragraphs ─────────────────────────────────────────────

_BLOCK = {"p", "div", "br", "hr", "li", "ul", "ol", "blockquote", "section", "article", "tr",
          "h1", "h2", "h3", "h4", "h5", "h6", "pre", "table", "header", "footer"}
_SKIP = {"script", "style", "noscript", "iframe", "svg", "head"}


class _Paragraphs(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self._buf, self._skip = [], [], 0

    def _flush(self):
        text = re.sub(r"\s+", " ", "".join(self._buf)).strip()
        self._buf = []
        if text:
            self.out.append(text)

    def handle_starttag(self, tag, attrs):
        if tag in _SKIP:
            self._skip += 1
        elif tag in _BLOCK:
            self._flush()

    def handle_startendtag(self, tag, attrs):
        if tag in _BLOCK:
            self._flush()

    def handle_endtag(self, tag):
        if tag in _SKIP:
            self._skip = max(0, self._skip - 1)
        elif tag in _BLOCK:
            self._flush()

    def handle_data(self, data):
        if not self._skip:
            self._buf.append(data)


def html_to_paragraphs(src) -> list:
    """A plugin's chapter (html, or plain text with newlines) as the reader's list of paragraphs."""
    src = src if isinstance(src, str) else ("" if src is None else str(src))
    if "<" not in src:
        lines = [re.sub(r"\s+", " ", _html.unescape(l)).strip() for l in src.splitlines()]
        return [l for l in lines if l]
    parser = _Paragraphs()
    parser.feed(src)
    parser.close()
    parser._flush()
    return parser.out


# ── The Node host ──────────────────────────────────────────────────────────

class _NodeSetup:
    """Whether Node and the libraries the plugins load are in place; npm install runs in the background."""

    def __init__(self):
        self.state = "unknown"      # unknown | ready | installing | missing-node | missing-npm | error
        self.message = ""
        self._lock = threading.Lock()

    @staticmethod
    def node_bin():
        return os.environ.get("SEKAIPOP_NODE") or shutil.which("node")

    @staticmethod
    def modules_ready():
        return all(os.path.isdir(os.path.join(DATA_DIR, "node_modules", m.split("@")[0]))
                   for m in NPM_PACKAGES)

    def start(self):
        with self._lock:
            if self.state in ("ready", "installing"):
                return
            if not self.node_bin():
                self.state, self.message = "missing-node", (
                    "Node.js is not installed (LNReader sources run on it): pacman -S nodejs npm")
                return
            if self.modules_ready():
                self.state, self.message = "ready", ""
                return
            if not shutil.which("npm"):
                self.state, self.message = "missing-npm", (
                    "npm is not installed, it fetches the libraries the sources use: pacman -S npm")
                return
            self.state, self.message = "installing", "Installing the libraries the sources use (npm)…"
        threading.Thread(target=self._install, daemon=True).start()

    def _install(self):
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            pkg = os.path.join(DATA_DIR, "package.json")
            if not os.path.exists(pkg):
                with open(pkg, "w") as f:
                    json.dump({"name": "sekaipop-lnreader", "private": True}, f)
            r = subprocess.run(
                ["npm", "install", "--prefix", DATA_DIR, "--no-audit", "--no-fund",
                 "--loglevel=error", *NPM_PACKAGES],
                capture_output=True, text=True, timeout=600)
            if r.returncode != 0 or not self.modules_ready():
                raise RuntimeError((r.stderr or r.stdout or "npm install failed").strip()[-400:])
            with self._lock:
                self.state, self.message = "ready", ""
            print("[lnreader] libraries installed")
        except Exception as e:
            with self._lock:
                self.state, self.message = "error", f"npm install failed: {e}"
            print(f"[lnreader] {self.message}")

    def require_ready(self):
        self.start()
        if self.state != "ready":
            raise RuntimeError(self.message or "the LNReader host is not ready yet")


SETUP = _NodeSetup()


class _Host:
    """One long-lived node process; calls are matched to replies by id, so many can be in flight."""

    def __init__(self):
        self._proc = None
        self._lock = threading.Lock()
        self._write_lock = threading.Lock()
        self._pending = {}
        self._next_id = 1
        self._http_pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix="lnreader-http")

    # -- process

    def _ensure(self):
        with self._lock:
            if self._proc is not None and self._proc.poll() is None:
                return
            SETUP.require_ready()
            os.makedirs(PLUGINS_DIR, exist_ok=True)
            self._proc = subprocess.Popen(
                [_NodeSetup.node_bin(), HOST_SCRIPT, "--plugins", PLUGINS_DIR, "--modules", DATA_DIR],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None, bufsize=0)
            threading.Thread(target=self._read_loop, args=(self._proc,), daemon=True).start()
            print("[lnreader] host started")

    def _read_loop(self, proc):
        buf = b""
        while True:
            chunk = proc.stdout.read(65536)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if line.strip():
                    self._on_line(line)
        with self._lock:
            pending, self._pending = self._pending, {}
        for slot in pending.values():
            slot["reply"] = {"ok": False, "error": "the LNReader host exited"}
            slot["event"].set()
        print("[lnreader] host exited")

    def _on_line(self, line):
        try:
            msg = json.loads(line)
        except ValueError:
            return
        if msg.get("op") == "http":
            self._http_pool.submit(self._do_http, msg)
        elif "id" in msg:
            with self._lock:
                slot = self._pending.pop(msg["id"], None)
            if slot:
                slot["reply"] = msg
                slot["event"].set()

    def _write(self, obj):
        data = (json.dumps(obj) + "\n").encode()
        with self._write_lock:
            self._proc.stdin.write(data)
            self._proc.stdin.flush()

    # -- a plugin's fetch

    def _do_http(self, msg):
        try:
            body = base64.b64decode(msg["body"]) if msg.get("body") else None
            status, headers, content, final = utils.request(
                msg.get("method", "GET"), msg["url"], msg.get("headers"), body)
            reply = {"hid": msg["hid"], "status": status, "statusText": "", "headers": headers,
                     "body": base64.b64encode(content).decode(), "url": final}
        except Exception as e:
            reply = {"hid": msg["hid"], "error": f"{type(e).__name__}: {e}"}
        try:
            self._write(reply)
        except Exception:
            pass

    # -- calls

    def request(self, payload, timeout=CALL_TIMEOUT):
        self._ensure()
        slot = {"event": threading.Event(), "reply": None}
        with self._lock:
            rid = self._next_id
            self._next_id += 1
            self._pending[rid] = slot
        try:
            self._write({"id": rid, **payload})
        except Exception as e:
            with self._lock:
                self._pending.pop(rid, None)
            raise RuntimeError(f"could not reach the LNReader host: {e}")
        if not slot["event"].wait(timeout):
            with self._lock:
                self._pending.pop(rid, None)
            raise RuntimeError("the source took too long to answer")
        reply = slot["reply"]
        if not reply.get("ok"):
            raise RuntimeError(reply.get("error") or "the source failed")
        return reply.get("result")

    def call(self, plugin, method, *args):
        return self.request({"op": "call", "plugin": plugin, "method": method, "args": list(args)})

    def meta(self, plugin):
        return self.request({"op": "meta", "plugin": plugin})

    def unload(self, plugin):
        if self._proc is not None and self._proc.poll() is None:
            self.request({"op": "unload", "plugin": plugin})

    def stop(self):
        with self._lock:
            proc, self._proc = self._proc, None
        if proc is not None and proc.poll() is None:
            proc.kill()


_HOST = _Host()


# ── Id helpers ─────────────────────────────────────────────────────────────

def make_nid(plugin: str, novel_path: str) -> str:
    return f"{plugin}~{quote(novel_path, safe='')}"


def make_cid(plugin: str, novel_path: str, chapter_path: str) -> str:
    return f"{make_nid(plugin, novel_path)}/{quote(chapter_path, safe='')}"


def parse_nid(raw: str) -> tuple:
    plugin, sep, rest = raw.partition("~")
    if not sep or not _ID_RE.match(plugin):
        raise ValueError(f"not an LNReader novel id: {raw!r}")
    return plugin, unquote(rest)


def parse_cid(raw: str) -> tuple:
    novel, sep, chapter = raw.partition("/")
    if not sep:
        raise ValueError(f"not an LNReader chapter id: {raw!r}")
    plugin, novel_path = parse_nid(novel)
    return plugin, novel_path, unquote(chapter)


# ── The provider ───────────────────────────────────────────────────────────

# ── Chapter dates ────────────────────────────────────────────────────────────
# A plugin gives each chapter a `releaseTime` string in whatever the site printed: ISO, "May 12, 2024",
# "5 days ago", a unix stamp... parse_release() turns what it can be sure of into an ISO stamp (noon UTC
# for a date with no time, so every timezone shows the same day) and otherwise keeps the site's own words,
# so the list shows what the source says rather than a wrong date.

_MONTHS = {m: i + 1 for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"])}
_UNIT_SECONDS = {"second": 1, "sec": 1, "minute": 60, "min": 60, "hour": 3600, "hr": 3600, "day": 86400}


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _day(y: int, m: int, d: int) -> str:
    return _iso(datetime(y, m, d, 12, 0, 0, tzinfo=timezone.utc))


def parse_release(value, now=None) -> tuple:
    """-> (iso, text). `iso` is "" when the date cannot be told for sure; `text` is the site's own words,
    kept only when there is no iso ("3 months ago", an ambiguous 04/05/2024)."""
    now = now or datetime.now(timezone.utc)
    if value is None or isinstance(value, bool):
        return "", ""
    raw = str(value).strip()
    if not raw or raw.lower() in ("null", "none", "unknown", "n/a", "-") or not re.search(r"[1-9]|[a-z]", raw, re.I):
        return "", ""                                         # nothing, or only zeros ("0", "0000-00-00")
    try:
        # unix stamps: seconds or milliseconds
        if re.fullmatch(r"\d{9,13}(\.\d+)?", raw):
            n = float(raw)
            n = n / 1000 if n >= 1e11 else n
            return _iso(datetime.fromtimestamp(n, timezone.utc)), ""
        text = re.sub(r"\s+", " ", raw)
        low = text.lower()

        # ISO 8601 and "2024-05-12 10:00:00"
        m = re.fullmatch(r"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?\s*(Z|[+-]\d{2}:?\d{2})?)?", text, re.I)
        if m:
            y, mo, d = int(m[1]), int(m[2]), int(m[3])
            if m[4] is None:
                return _day(y, mo, d), ""
            tz = timezone.utc
            if m[7] and m[7].upper() != "Z":
                sign = 1 if m[7][0] == "+" else -1
                digits = m[7][1:].replace(":", "")
                tz = timezone(sign * timedelta(hours=int(digits[:2]), minutes=int(digits[2:])))
            return _iso(datetime(y, mo, d, int(m[4]), int(m[5]), int(m[6] or 0), tzinfo=tz)), ""

        # "May 12, 2024" / "May 12th 2024" / "12 May 2024" / "12 May, 2024" / "Sept 3, 2024"
        m = re.fullmatch(r"([a-z]{3,9})\.? (\d{1,2})(?:st|nd|rd|th)?,? (\d{4})", low)
        if m and m[1][:3] in _MONTHS:
            return _day(int(m[3]), _MONTHS[m[1][:3]], int(m[2])), ""
        m = re.fullmatch(r"(\d{1,2})(?:st|nd|rd|th)? ([a-z]{3,9})\.?,? (\d{4})", low)
        if m and m[2][:3] in _MONTHS:
            return _day(int(m[3]), _MONTHS[m[2][:3]], int(m[1])), ""

        # 12/05/2024: day first or month first only when one of the two numbers says so
        m = re.fullmatch(r"(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})", text)
        if m:
            a, b, y = int(m[1]), int(m[2]), int(m[3])
            if a > 12 >= b:
                return _day(y, b, a), ""
            if b > 12 >= a:
                return _day(y, a, b), ""
            if a == b and a <= 12:
                return _day(y, a, b), ""
            return "", text                                   # 04/05/2024: which is the month?

        # "just now", "yesterday", "5 days ago", "an hour ago": exact enough for hours and days
        if low in ("just now", "now", "moments ago"):
            return _iso(now), ""
        if low == "yesterday":
            return _iso(now - timedelta(days=1)), ""
        if low == "today":
            return _iso(now), ""
        m = re.fullmatch(r"(an?|\d+) (second|sec|minute|min|hour|hr|day)s? ago", low)
        if m:
            n = 1 if m[1] in ("a", "an") else int(m[1])
            ago = n * _UNIT_SECONDS[m[2]]
            if ago < 7 * 86400:
                return _iso(now - timedelta(seconds=ago)), ""
        # weeks, months and years ago are too loose to turn into a date: the site's words stay
        if re.fullmatch(r"(an?|\d+) (week|month|year)s? ago", low):
            return "", text
    except (ValueError, OverflowError, OSError):
        pass
    return "", (raw if len(raw) <= 40 else "")


# "Volume 2", "Vol. 2": a row that is a whole volume, not a chapter of one
_VOLUME_ONLY = re.compile(r"^\s*(?:volume|vol)\.?\s*(\d+(?:\.\d+)?)\s*$", re.I)
# "Volume 1 - Chapter 10: ...", "Vol.3 Ch.4": the volume a chapter sits in
_VOLUME_LEAD = re.compile(r"^\s*(?:volume|vol)\.?\s*(\d+(?:\.\d+)?)\b", re.I)


def volume_info(name: str) -> tuple:
    """-> (kind, volume): kind is "volume" for a row that is a whole volume, else "chapter"; volume is the
    number the name says it belongs to ("" when it names none)."""
    m = _VOLUME_ONLY.match(name or "")
    if m:
        return "volume", m[1]
    m = _VOLUME_LEAD.match(name or "")
    return "chapter", (m[1] if m else "")


class LNReaderProvider(NovelProvider):
    name = "lnreader"
    label = "LNReader"

    _instance = None
    _instance_lock = threading.Lock()

    def __new__(cls):
        # one instance: the installed list, the host process and the caches are shared
        with cls._instance_lock:
            if cls._instance is None:
                inst = super().__new__(cls)
                inst._init()
                cls._instance = inst
            return cls._instance

    def __init__(self):
        pass

    def _init(self):
        self._state_lock = threading.Lock()
        self._state = self._load_state()
        self._catalog = None            # (fetched_at, [entries])
        self._catalog_warnings = []     # repositories that could not be read in the last round
        self._index = {}                # novel id -> [(chapter id, title)] from the last info()
        self._seen = {}                 # paging guard, see _page_items
        self._meta_cache = {}

    # ── state ─────────────────────────────────────────────────────────────

    @staticmethod
    def _load_state() -> dict:
        try:
            with open(STATE_FILE) as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        data.setdefault("active", "")
        data.setdefault("installed", {})
        # Several repositories now (the Repositories tab); an older state.json kept one address in
        # "repo" ("" = the official list), which becomes the one entry.
        repos = data.get("repos")
        if not isinstance(repos, list):
            old = str(data.get("repo") or "").strip()
            repos = [old] if old else [OFFICIAL_MARK]
        data["repos"] = [r for r in dict.fromkeys(str(r).strip() for r in repos)
                         if r == OFFICIAL_MARK or re.match(r"^https?://", r)]
        data["repo"] = LNReaderProvider._legacy_repo(data["repos"])
        return data

    @staticmethod
    def _legacy_repo(repos: list) -> str:
        """The single address older callers know: the first one of the user's own, else \"\"."""
        return next((r for r in repos if r != OFFICIAL_MARK), "")

    def _save_state(self):
        os.makedirs(DATA_DIR, exist_ok=True)
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self._state, f, indent=2)
        os.replace(tmp, STATE_FILE)

    def bootstrap(self):
        """Called once when the server starts: get Node's libraries in place without blocking it."""
        SETUP.start()

    # ── sources (installed plugins) ───────────────────────────────────────

    def sources(self) -> dict:
        with self._state_lock:
            installed = self._state["installed"]
            out = [{"id": pid, **meta, "iconUrl": self._proxy(meta.get("iconUrl", ""))}
                   for pid, meta in sorted(installed.items(), key=lambda kv: kv[1].get("name", "").lower())]
            return {"active": self._state["active"] if self._state["active"] in installed else "",
                    "sources": out}

    def status(self) -> dict:
        s = self.sources()
        return {"node": {"state": SETUP.state, "message": SETUP.message},
                "repo": self._state["repo"], "repos": list(self._state["repos"]),
                "active": s["active"], "sources": s["sources"]}

    def select(self, plugin_id: str) -> dict:
        with self._state_lock:
            if plugin_id not in self._state["installed"]:
                raise ValueError(f"source {plugin_id!r} is not installed")
            self._state["active"] = plugin_id
            self._save_state()
        return {"ok": True, "active": plugin_id}

    @staticmethod
    def _clean_repo(url: str) -> str:
        url = (url or "").strip()
        if url == OFFICIAL_MARK:
            return url
        if not re.match(r"^https?://", url):
            raise ValueError("the repository address must start with http:// or https://")
        return url

    def set_repo(self, url: str) -> dict:
        """The older single-address call: that one address alone (\"\" = the official list alone)."""
        url = (url or "").strip()
        if url:
            url = self._clean_repo(url)
        with self._state_lock:
            self._state["repos"] = [url or OFFICIAL_MARK]
            self._state["repo"] = self._legacy_repo(self._state["repos"])
            self._save_state()
        self._catalog = None
        return {"ok": True, "repo": url}

    # ── the repositories (where the sources come from) ────────────────────

    def repos(self) -> dict:
        with self._state_lock:
            have = list(self._state["repos"])
        return {"repos": [{"id": r, "name": OFFICIAL_NAME if r == OFFICIAL_MARK else r,
                           "official": r == OFFICIAL_MARK} for r in have],
                "suggested": [x for x in SUGGESTED_REPOS if x["url"] not in have]}

    def change_repos(self, add: str = "", remove: str = "") -> dict:
        """Add one repository (at the end) or remove one; the lists are read again next time."""
        add = (add or "").strip()
        remove = (remove or "").strip()
        if add:
            add = self._clean_repo(add)
        with self._state_lock:
            repos = list(self._state["repos"])
            if remove:
                repos = [r for r in repos if r != remove]
            if add and add not in repos:
                repos.append(add)
            self._state["repos"] = repos
            self._state["repo"] = self._legacy_repo(repos)
            self._save_state()
        self._catalog = None
        return {"ok": True, **self.repos()}

    # ── the catalog (lnreader-plugins' plugins.min.json) ──────────────────

    def _official_url(self) -> str:
        tags = []
        try:
            listing = utils.fetch_json(TAGS_API)
            for entry in listing if isinstance(listing, list) else []:
                m = re.match(r"^v?(\d+(?:\.\d+)*)$", str(entry.get("name", "")))
                if m and entry.get("type", "dir") == "dir":
                    tags.append((tuple(int(x) for x in m.group(1).split(".")), entry["name"]))
        except Exception as e:
            print(f"[lnreader] could not list the plugin list's release folders ({e}); using {FALLBACK_TAG}")
        return TAG_REPO.format(tag=max(tags)[1] if tags else FALLBACK_TAG)

    def _repo_url(self, repo: str = "") -> str:
        """The address to read: the repository's own, or for the official list the newest release folder."""
        repo = repo or (self._state["repos"][0] if self._state["repos"] else OFFICIAL_MARK)
        return self._official_url() if repo == OFFICIAL_MARK else repo

    def _read_repo(self, repo: str) -> list:
        """One repository's plugin list, as normalised entries. The official list falls back to the copy
        saved by the last good read when the network is down."""
        url = self._repo_url(repo)
        try:
            raw = utils.fetch_json(url)
        except Exception as e:
            if repo == OFFICIAL_MARK and os.path.exists(CATALOG_FILE):
                with open(CATALOG_FILE) as f:
                    raw = json.load(f)
            else:
                raise RuntimeError(f"could not load the plugin list ({url}): {e}")
        else:
            if repo == OFFICIAL_MARK:
                try:
                    os.makedirs(DATA_DIR, exist_ok=True)
                    with open(CATALOG_FILE, "w") as f:
                        json.dump(raw, f)
                except OSError:
                    pass
        if not isinstance(raw, list):
            raise RuntimeError(f"{url} is not a plugin list")
        return [self._norm_entry(e, repo) for e in raw if isinstance(e, dict) and e.get("id") and e.get("url")]

    def catalog(self, refresh: bool = False) -> dict:
        now = time.time()
        with self._state_lock:
            repos = list(self._state["repos"])
        if not refresh and self._catalog and now - self._catalog[0] < CATALOG_TTL:
            entries, warnings = self._catalog[1], self._catalog_warnings
        else:
            entries, warnings, seen, first_error = [], [], set(), None
            for repo in repos:
                try:
                    got = self._read_repo(repo)
                except Exception as e:
                    first_error = first_error or e
                    warnings.append(str(e))
                    continue
                for e in got:
                    if e["id"] not in seen:          # two repositories with one id: the earlier one wins
                        seen.add(e["id"])
                        entries.append(e)
            if repos and not entries and first_error is not None:
                raise RuntimeError(str(first_error))
            self._catalog = (now, entries)
            self._catalog_warnings = warnings
        with self._state_lock:
            installed = dict(self._state["installed"])
        out = []
        for e in entries:
            have = installed.get(e["id"])
            out.append({**e, "iconUrl": self._proxy(e["iconUrl"]),
                        "installed": have is not None,
                        "installedVersion": have.get("version", "") if have else "",
                        "update": bool(have) and have.get("version", "") != e["version"]})
        out.sort(key=lambda e: (e["lang"].lower(), e["name"].lower()))
        return {"repo": self._state["repo"], "repos": repos, "total": len(out), "plugins": out,
                "warnings": warnings}

    @staticmethod
    def _norm_entry(e: dict, repo: str = "") -> dict:
        return {"id": str(e["id"]), "name": str(e.get("name") or e["id"]), "site": str(e.get("site") or ""),
                "lang": str(e.get("lang") or ""), "version": str(e.get("version") or ""),
                "url": str(e["url"]), "iconUrl": str(e.get("iconUrl") or ""), "repo": repo}

    def update_all(self) -> dict:
        """Update every installed source that has a newer version in its list."""
        todo = [p["id"] for p in self.catalog()["plugins"] if p["installed"] and p["update"]]
        done, failed = [], []
        for pid in todo:
            try:
                self.install(pid)
                done.append(pid)
            except Exception as e:
                failed.append({"id": pid, "error": str(e)})
        return {"ok": not failed, "updated": len(done), "failed": failed}

    def install(self, plugin_id: str) -> dict:
        if not _ID_RE.match(plugin_id or ""):
            raise ValueError("bad source id")
        self.catalog()
        entry = next((e for e in self._catalog[1] if e["id"] == plugin_id), None)
        if entry is None:
            raise ValueError(f"source {plugin_id!r} is not in the plugin list")
        code = utils.fetch(entry["url"], {"Accept": "*/*"}, timeout=60)
        if "parseNovel" not in code:
            raise RuntimeError(f"{entry['url']} does not look like an LNReader plugin")
        os.makedirs(PLUGINS_DIR, exist_ok=True)
        path = os.path.join(PLUGINS_DIR, plugin_id + ".js")
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write(code)
        os.replace(path + ".tmp", path)
        try:
            _HOST.unload(plugin_id)
        except Exception:
            pass
        self._meta_cache.pop(plugin_id, None)
        with self._state_lock:
            self._state["installed"][plugin_id] = {k: entry[k] for k in ("name", "site", "lang", "version", "iconUrl")}
            if not self._state["active"]:
                self._state["active"] = plugin_id
            self._save_state()
        return {"ok": True, "id": plugin_id, "active": self._state["active"]}

    def uninstall(self, plugin_id: str) -> dict:
        with self._state_lock:
            self._state["installed"].pop(plugin_id, None)
            if self._state["active"] == plugin_id:
                rest = sorted(self._state["installed"])
                self._state["active"] = rest[0] if rest else ""
            self._save_state()
        try:
            os.remove(os.path.join(PLUGINS_DIR, plugin_id + ".js"))
        except OSError:
            pass
        try:
            _HOST.unload(plugin_id)
        except Exception:
            pass
        return {"ok": True, "active": self._state["active"]}

    # ── helpers for the browse calls ──────────────────────────────────────

    def _active(self) -> str:
        with self._state_lock:
            pid = self._state["active"]
            if pid not in self._state["installed"]:
                raise ValueError("No source yet: pick one with the Source key (Add sources).")
            return pid

    def _site(self, plugin: str) -> str:
        with self._state_lock:
            return (self._state["installed"].get(plugin) or {}).get("site", "")

    @staticmethod
    def _proxy(url: str, port: int = 5151) -> str:
        if not url:
            return ""
        return f"http://127.0.0.1:{port}/image?url={quote(url, safe='')}"

    def _abs(self, plugin: str, url: str) -> str:
        url = (url or "").strip()
        if not url:
            return ""
        if url.startswith("//"):
            return "https:" + url
        if re.match(r"^[a-z][a-z0-9+.-]*://", url, re.I):
            return url
        site = self._site(plugin).rstrip("/")
        return site + (url if url.startswith("/") else "/" + url) if site else url

    def _cards(self, plugin: str, items) -> list:
        out = []
        for it in items if isinstance(items, list) else []:
            path = it.get("path") or it.get("url") or ""
            if not path:
                continue
            out.append({"id": make_nid(plugin, path), "title": str(it.get("name") or "").strip(),
                        "image": self._proxy(self._abs(plugin, it.get("cover") or "")),
                        "author": "", "latestChapter": ""})
        return out

    def _page_items(self, kind: str, plugin: str, query: str, page: int, items: list) -> dict:
        """Plugins do not say when a list ends (the app just asks until a page comes back empty), and
        some ignore the page number altogether: a page with nothing new ends the list here."""
        key = (kind, plugin, query)
        if page <= 1:
            self._seen[key] = set()
        seen = self._seen.setdefault(key, set())
        fresh = [c for c in items if c["id"] not in seen]
        seen.update(c["id"] for c in items)
        if len(self._seen) > 200:
            self._seen.pop(next(iter(self._seen)))
        more = bool(fresh) and page < 200
        return {"results": fresh, "hasMore": more, "nextPage": page + 1}

    def _listing(self, kind: str, page: int, latest: bool, query: str = "") -> dict:
        plugin = self._active()

        def run():
            if kind == "search":
                raw = _HOST.call(plugin, "searchNovels", query, page)
            else:
                raw = _HOST.call(plugin, "popularNovels", page, latest)
            return self._cards(plugin, raw)

        items = cached(f"lnreader:{kind}:{plugin}:{query}:{page}", TTL_LIST, run)
        return self._page_items(kind, plugin, query, page, items)

    # ── NovelProvider interface ───────────────────────────────────────────

    def hot_page(self, page: int = 1) -> dict:
        return self._listing("hot", page, False)

    def hot(self) -> list:
        return self.hot_page(1)["results"]

    def latest(self, page: int = 1) -> dict:
        return self._listing("latest", page, True)

    def search(self, query, genre=None, status="All", page=1) -> dict:
        # LNReader's search takes a term and a page; the genre and status of the old sources do not exist
        return self._listing("search", page, False, query)

    def _plugin_meta(self, plugin: str) -> dict:
        meta = self._meta_cache.get(plugin)
        if meta is None:
            meta = self._meta_cache[plugin] = _HOST.meta(plugin)
        return meta

    @staticmethod
    def _status(s) -> str:
        s = str(s or "").strip()
        return "" if s.lower() in ("", "unknown") else s

    @staticmethod
    def _genres(g) -> list:
        if isinstance(g, list):
            parts = g
        else:
            parts = re.split(r"[,;]", str(g or ""))
        return [str(p).strip() for p in parts if str(p).strip()]

    def _chapter_rows(self, plugin: str, novel_path: str, raw_chapters) -> list:
        rows = []
        for ch in raw_chapters if isinstance(raw_chapters, list) else []:
            path = ch.get("path") or ch.get("url") or ""
            if not path:
                continue
            rows.append((path, str(ch.get("name") or "").strip(), ch.get("chapterNumber"),
                         ch.get("releaseTime")))
        return rows

    def _info(self, raw_id: str) -> dict:
        plugin, novel_path = parse_nid(raw_id)
        novel = _HOST.call(plugin, "parseNovel", novel_path) or {}
        raw_chapters = list(novel.get("chapters") or [])
        partial = False

        pages = int(novel.get("totalPages") or 0)
        if pages > 1 and self._plugin_meta(plugin).get("hasParsePage"):
            last = min(pages, MAX_CHAPTER_PAGES)
            partial = pages > MAX_CHAPTER_PAGES

            def one(p):
                got = _HOST.call(plugin, "parsePage", novel_path, p) or {}
                return p, list(got.get("chapters") or [])

            with ThreadPoolExecutor(max_workers=4) as ex:
                for _, chs in sorted(ex.map(one, range(2, last + 1)), key=lambda t: t[0]):
                    raw_chapters.extend(chs)

        chapters, seen = [], set()
        now = datetime.now(timezone.utc)
        for path, name, number, released in self._chapter_rows(plugin, novel_path, raw_chapters):
            if path in seen:
                continue
            seen.add(path)
            idx = len(chapters) + 1
            num = number if isinstance(number, (int, float)) and number else idx
            publish_at, released_text = parse_release(released, now)
            kind, volume = volume_info(name)
            chapters.append({"id": make_cid(plugin, novel_path, path),
                             "title": name or f"Chapter {idx}",
                             "chapter": str(int(num)) if float(num).is_integer() else str(num),
                             "index": idx,                    # the source's own order, whatever the numbers say
                             "kind": kind,
                             "volume": volume,
                             "publishAt": publish_at,         # ISO, "" when the date is not certain
                             "releasedText": released_text})  # the site's words when it is not
        self._index[raw_id] = [(c["id"], c["title"]) for c in chapters]
        if len(self._index) > 100:
            self._index.pop(next(iter(self._index)))

        author = str(novel.get("author") or "").strip()
        artist = str(novel.get("artist") or "").strip()
        return {
            "id": raw_id,
            "title": str(novel.get("name") or "").strip(),
            "description": "\n".join(html_to_paragraphs(novel.get("summary") or "")),
            "status": self._status(novel.get("status")),
            "author": author if not artist or artist == author else f"{author} / {artist}".strip(" /"),
            "image": self._proxy(self._abs(plugin, novel.get("cover") or "")),
            "genres": self._genres(novel.get("genres")),
            "chapters": chapters,
            "partial": partial,
        }

    def info(self, novel_id: str) -> dict:
        return cached(f"lnreader:info:{novel_id}", TTL_INFO, lambda: self._info(novel_id))

    def _chapter(self, raw_id: str) -> dict:
        plugin, novel_path, chapter_path = parse_cid(raw_id)
        body = _HOST.call(plugin, "parseChapter", chapter_path)
        paragraphs = html_to_paragraphs(body)
        novel_id = make_nid(plugin, novel_path)
        rows = self._index.get(novel_id) or []
        ids = [r[0] for r in rows]
        title, prev_id, next_id = "", "", ""
        if raw_id in ids:
            i = ids.index(raw_id)
            title = rows[i][1]
            prev_id = ids[i - 1] if i > 0 else ""
            next_id = ids[i + 1] if i + 1 < len(ids) else ""
        return {"id": raw_id, "title": title, "paragraphs": paragraphs,
                "wordCount": sum(len(p.split()) for p in paragraphs),
                "prevId": prev_id, "nextId": next_id}

    def chapter(self, chapter_id: str) -> dict:
        data = cached(f"lnreader:chapter:{chapter_id}", TTL_CHAP, lambda: self._chapter(chapter_id))
        if not data["paragraphs"]:
            raise RuntimeError("the source returned an empty chapter")
        return data

    def fetch_image(self, url: str) -> tuple:
        host = urlsplit(url).netloc
        referer = ""
        with self._state_lock:
            for meta in self._state["installed"].values():
                site = meta.get("site", "")
                if site and urlsplit(site).netloc == host:
                    referer = site.rstrip("/") + "/"
                    break
        headers = {"Accept": "image/avif,image/webp,image/*,*/*;q=0.8", "Sec-Fetch-Dest": "image",
                   "Sec-Fetch-Mode": "no-cors", "Sec-Fetch-Site": "cross-site"}
        if referer:
            headers["Referer"] = referer
        status, hdrs, body, _ = utils.request("GET", url, headers, None, timeout=30)
        if status >= 400:
            raise RuntimeError(f"image request failed: HTTP {status}")
        return body, hdrs.get("content-type", "image/jpeg")
