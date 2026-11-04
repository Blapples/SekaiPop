// AppSource.qml and Quickshell's rescans (issue #128).
//
// Quickshell rescans the application folders whenever a file changes in them or in any
// folder above them (~ included), and updates its model row by row, one `valuesChanged`
// per row. A binding on `DesktopEntries.applications.values` rebuilt the whole list on
// every one of them, which froze the shell. This runs the REAL `sameApps`, `refresh`,
// `sync` and `buildEntries` out of AppSource.qml against fake DesktopEntry objects that
// count every field read (each one is a trip into C++ in the shell), and checks the
// wiring from the source, since node cannot load QML.
//   node tests/launcher-test/app_source_rescan_test.js   (run from the sekaipop folder)
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "..", "services", "AppSource.qml"), "utf8")

function grab(name) {
    const i = src.indexOf("function " + name + "(")
    if (i < 0)
        throw new Error("no " + name)
    let k = src.indexOf("{", i), d = 0
    for (; k < src.length; k++) {
        if (src[k] === "{") d++
        else if (src[k] === "}" && --d === 0) break
    }
    return src.slice(i, k + 1)
}

// ----- the wiring -----
assert.ok(!/property var entries:\s*\{[\s\S]*?DesktopEntries\.applications\.values/.test(src),
    "entries is not a binding on the model's values")
assert.ok(!/onValuesChanged/.test(src), "nothing runs per row of a rescan")
assert.ok(/target:\s*DesktopEntries\s*\n[\s\S]*?function onApplicationsChanged\(\)\s*\{\s*root\.refresh\(\)/.test(src),
    "a finished scan refreshes the list, straight away")
assert.ok(/Component\.onCompleted:\s*root\.refresh\(\)/.test(src), "the list is built at start")
assert.ok(/readonly property var entries:\s*root\._entries/.test(src), "entries stays read-only outside")

// ----- fake Quickshell -----
let reads = 0
function app(id, name, extra) {
    const f = Object.assign({ name: name, genericName: "", icon: "ic-" + id, comment: "", keywords: [] }, extra || {})
    const o = { id: id, _f: f }
    for (const k of Object.keys(f))
        Object.defineProperty(o, k, { get() { reads++; return this._f[k] }, enumerable: true })
    return o
}
const DesktopEntries = { applications: { values: [] } }
const root = { _cache: { rankKey: "", rankVal: [], usage: {}, usageDirty: false }, _usageRev: 0 }
let assigned = 0
Object.defineProperty(root, "_entries", {
    get() { return this.__entries || [] },
    set(v) { assigned++; this.__entries = v }
})
eval(["sameApps", "refresh", "sync", "buildEntries"].map(grab).join("\n")
    + "\nroot.sameApps = sameApps; root.refresh = refresh; root.sync = sync; root.buildEntries = buildEntries;")

const names = list => list.map(e => e.name)

// ----- the first build -----
const apps = [app("vlc", "VLC"), app("kitty", "kitty"), app("firefox", "Firefox"), app("gimp", "GIMP"), app("btop", "btop++")]
DesktopEntries.applications.values = apps.slice()
root.refresh()
const first = root._entries
assert.deepStrictEqual(names(first), ["btop++", "Firefox", "GIMP", "kitty", "VLC"], "name-sorted")
assert.deepStrictEqual(first.map(e => e.idx), [0, 1, 2, 3, 4])
assert.strictEqual(assigned, 1)

// ----- a rescan that changed nothing -----
root.refresh()
assert.strictEqual(root._entries, first, "same apps, same array")
assert.strictEqual(assigned, 1, "nothing downstream re-runs")

// The model in another order (it comes out of a hash): still nothing.
DesktopEntries.applications.values = apps.slice().reverse()
root.refresh()
assert.strictEqual(root._entries, first, "order alone changes nothing")

// ----- the Apps screen opening, nothing new -----
reads = 0
root.sync()
assert.strictEqual(reads, 0, "sync() reads no app field when the apps are the same")
assert.strictEqual(root._entries, first)

// ----- a rescan that replaced one DesktopEntry (an app in two data folders) -----
const kitty2 = app("kitty", "kitty")
DesktopEntries.applications.values = apps.map(a => a.id === "kitty" ? kitty2 : a)
root.refresh()
const second = root._entries
assert.notStrictEqual(second, first, "a replaced object is a change")
assert.strictEqual(second.find(e => e.key === "kitty").app, kitty2, "the entry points at the live object")
for (const e of second)
    if (e.key !== "kitty")
        assert.strictEqual(e, first.find(f => f.key === e.key), e.key + " keeps its entry object")

// ----- a .desktop file edited in place (same object, new name) -----
apps[0]._f.name = "Aardvark Player"   // vlc
root.refresh()
const third = root._entries
assert.notStrictEqual(third, second)
assert.deepStrictEqual(names(third), ["Aardvark Player", "btop++", "Firefox", "GIMP", "kitty"], "re-sorted")
assert.strictEqual(third[0].nameL, "aardvark player", "the search field follows")
assert.deepStrictEqual(third.map(e => e.idx), [0, 1, 2, 3, 4], "reused entries get their new place")
assert.strictEqual(third[1], second.find(e => e.key === "btop"))

// ----- an app installed while the shell runs, seen when the Apps screen opens -----
const obs = app("obs", "OBS Studio", { keywords: ["record", "stream"] })
DesktopEntries.applications.values = DesktopEntries.applications.values.concat([obs])
root.sync()
assert.ok(root._entries.some(e => e.app === obs), "a new app shows up")
assert.strictEqual(root._entries.find(e => e.app === obs).keywordsL, "record\nstream\n")

// ----- an app removed -----
DesktopEntries.applications.values = DesktopEntries.applications.values.filter(a => a !== obs)
root.refresh()
assert.ok(!root._entries.some(e => e.app === obs), "a removed app goes")

// ----- usage still moves on when the Apps screen opens -----
root._cache.usageDirty = true
const rev = root._usageRev
root.sync()
assert.strictEqual(root._usageRev, rev + 1)
assert.strictEqual(root._cache.usageDirty, false)

console.log("app_source_rescan_test: ok")
