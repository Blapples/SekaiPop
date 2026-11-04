// node tests/launcher-test/rank_unit.js
//
// AppSource.qml's search was rewritten to rank pre-lower-cased, stable entry objects
// instead of reading every DesktopEntry on every key. This runs the REAL functions out
// of AppSource.qml next to the old ranking (kept below, word for word) over a few
// hundred fake apps and many queries, and checks both give the same apps in the same
// order, that asking twice (the memo) changes nothing, and that every entry's key is
// unique (the grid's model tells tiles apart by it).
const fs = require('fs');
const path = require('path');
const OLD_SRC = `function rank(q) {
        const needle = q.toLowerCase().trim()
        if (needle === "")
            return []
        const scored = []
        for (const app of root.allApps) {
            const score = root.scoreApp(app, needle)
            if (score > 0)
                scored.push({ app: app, score: score })
        }
        scored.sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name))
        return scored.map(s => s.app)
    }
function scoreApp(app, needle) {
        const name = (app.name || "").toLowerCase()
        if (name === needle)
            return 100
        if (name.startsWith(needle))
            return 80
        if (name.includes(needle))
            return 60

        const generic = (app.genericName || "").toLowerCase()
        if (generic.startsWith(needle))
            return 45
        if (generic.includes(needle))
            return 35

        const keywords = app.keywords || []
        for (const kw of keywords) {
            if (kw.toLowerCase().includes(needle))
                return 25
        }

        const comment = (app.comment || "").toLowerCase()
        if (comment.includes(needle))
            return 10

        return 0
    }`;
function grab(src, name) {
  const i = src.indexOf('function ' + name + '(');
  if (i < 0) throw new Error('no ' + name);
  let j = src.indexOf('{', i), d = 0, k = j;
  for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (d === 0) break; } }
  return src.slice(i, k + 1);
}
const oldSrc = OLD_SRC;
const newSrc = fs.readFileSync(path.join(__dirname, '..', '..', 'services', 'AppSource.qml'), 'utf8');

// ---- old ----
const oldRoot = { allApps: [] };
const oldFns = ['rank', 'scoreApp'].map(n => grab(oldSrc, n).replace(/root\./g, 'oldRoot.'));
eval(oldFns.join('\n') + '\noldRoot.rank = rank; oldRoot.scoreApp = scoreApp;');

// ---- new ----
const newRoot = { query: '' };
const names = ['buildEntries', 'rankEntries', 'rank', 'scoreEntry'];
const newFns = names.map(n => grab(newSrc, n).replace(/root\./g, 'newRoot.'));
eval(newFns.join('\n') + '\nnewRoot.buildEntries = buildEntries; newRoot.rankEntries = rankEntries; newRoot.rank = rank; newRoot.scoreEntry = scoreEntry;');

// ---- fake apps ----
let seed = 12345; const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
const words = ['fire','fox','web','browser','term','kitty','foot','code','studio','vim','neo','mail','thunder','bird','music','spot','ify','video','vlc','player','krita','gimp','paint','ink','scape','office','writer','calc','draw','impress','file','manager','dolphin','nautilus','settings','system','monitor','btop','htop','steam','game','discord','vesktop','chat','Ünïcode','Åpp','zoom','télé','edit','photo','shop','blender','3d','obs','record','stream'];
const pick = a => a[Math.floor(rnd() * a.length)];
const mk = i => {
  const n = 1 + Math.floor(rnd() * 3);
  const name = Array.from({ length: n }, () => pick(words)).join(rnd() < .5 ? ' ' : '');
  return {
    id: 'app' + i + '.desktop', name: name[0].toUpperCase() + name.slice(1),
    genericName: rnd() < .6 ? pick(words) + ' ' + pick(words) : '',
    keywords: rnd() < .5 ? [pick(words), pick(words) + ' ' + pick(words)] : [],
    comment: rnd() < .7 ? 'A ' + pick(words) + ' for your ' + pick(words) : '', icon: 'ic' + i
  };
};
const apps = Array.from({ length: 400 }, (_, i) => mk(i));
// a few exact duplicates in name to exercise tie-breaks
apps.push({ ...apps[3], id: 'dup1.desktop' }, { ...apps[3], id: 'dup2.desktop' });
oldRoot.allApps = apps.slice().sort((a, b) => a.name.localeCompare(b.name));
newRoot._cache = { rankKey: '', rankVal: [], iconSrc: null, icons: {} };
newRoot.entries = newRoot.buildEntries(apps);

let bad = 0, total = 0, nonEmpty = 0;
const queries = new Set(words.concat(['f', 'fi', 'fir', 'fire', 'fire ', ' Fire', 'a', 'e', 'for your', 'a ', 'x', 'zzzz', '']));
for (let i = 0; i < 400; i++) { const w = pick(words); queries.add(w.slice(0, 1 + Math.floor(rnd() * w.length))); queries.add(pick(words) + ' ' + pick(words)); }
for (const q of queries) {
  const a = oldRoot.rank(q).map(x => x.id);
  const b = newRoot.rank(q).map(x => x.id);
  const c = newRoot.rank(q).map(x => x.id); // second call hits the memo
  total++; if (a.length) nonEmpty++;
  if (JSON.stringify(a) !== JSON.stringify(b) || JSON.stringify(b) !== JSON.stringify(c)) {
    bad++; if (bad < 4) console.log('MISMATCH for', JSON.stringify(q), a.slice(0, 6), b.slice(0, 6));
  }
}
const keys = new Set(newRoot.entries.map(e => e.key));
console.log(`queries: ${total} (${nonEmpty} with matches), mismatches: ${bad}, apps: ${apps.length}, unique keys: ${keys.size}`);
process.exit(bad || keys.size !== newRoot.entries.length ? 1 : 0);
