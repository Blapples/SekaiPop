// Favourite presets: DesktopPresetService's functions are cut out of the .qml and
// run against fakes, preset-state.sh's `rename` (same name = rewrite in place) runs
// for real in a temp folder, and the board's wiring is checked as text (Quickshell
// can't run here).
const fs = require("fs"), os = require("os"), path = require("path"), assert = require("assert")
const { spawnSync } = require("child_process")
const top = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(require("../lib/locate")(f), "utf8")
const src = read("services/DesktopPresetService.qml")
function grab(name) {
    const start = src.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    return src.slice(start, src.indexOf("\n    }\n", start) + 7).replace(/^    function /, "function ")
}

// ---------- the service ----------
// Saving a preset hands the sticky notes on the desktop to it (NotesService.adoptSet).
const noteCalls = []
const NotesService = { adoptSet: n => noteCalls.push(["adopt", n]), renameSet: () => {}, dropSet: () => {} }
const mk = (n, fav) => ({ name: n, data: { theme: { g: n }, _meta: Object.assign({ name: n, saved: 5, v: 1 }, fav ? { favorite: true } : {}) } })
const jobs = []
const root = { presets: [mk("Day"), mk("Night"), mk("Zed")], lastName: "", script: "/s.sh", enqueue: a => jobs.push(a), refreshLive() {}, capture: () => ({ theme: { g: "cap" } }) }
for (const n of ["find", "byName", "isFavorite", "setFavorite", "toggleFavorite", "stable", "digestOf", "write", "framePaths", "wornPictures"])
    root[n] = eval("(" + grab(n) + ")")
const names = () => root.presets.map(p => p.name)

// no favourites: by name, as before
assert.deepStrictEqual(names(), ["Day", "Night", "Zed"])
assert.strictEqual(root.isFavorite(root.find("Zed")), false)
assert.strictEqual(root.isFavorite(null), false)

// pin Zed: it stands first, nothing else moves, one job rewrites its file
const before = root.presets[2].data
assert.strictEqual(root.toggleFavorite("Zed"), true)
assert.deepStrictEqual(names(), ["Zed", "Day", "Night"])
assert.strictEqual(jobs.length, 1)
assert.deepStrictEqual(jobs[0].slice(0, 5), ["sh", "/s.sh", "rename", "Zed", "Zed"], "same name = rewrite in place")
const sent = JSON.parse(jobs[0][5])
assert.strictEqual(sent._meta.favorite, true); assert.strictEqual(sent._meta.saved, 5, "saved time kept"); assert.deepStrictEqual(sent.theme, { g: "Zed" })
assert.strictEqual(before._meta.favorite, undefined, "the old data object isn't edited in place")

// two favourites: each group by name
root.setFavorite("Night", true)
assert.deepStrictEqual(names(), ["Night", "Zed", "Day"])

// asking for what it already is does nothing; unknown names do nothing
const n = jobs.length
assert.strictEqual(root.setFavorite("Night", true), true); assert.strictEqual(jobs.length, n)
assert.strictEqual(root.setFavorite("Nope", true), false); assert.strictEqual(jobs.length, n)
assert.strictEqual(root.toggleFavorite("Nope"), false)

// unpin: the flag is removed (not left false), and it goes back to its place by name
assert.strictEqual(root.toggleFavorite("Zed"), false)
assert.deepStrictEqual(names(), ["Night", "Day", "Zed"])
assert.ok(!("favorite" in JSON.parse(jobs[jobs.length - 1][5])._meta))

// saving over a favourite keeps it; saving over a plain one doesn't invent it
jobs.length = 0
root.write("Night")
assert.strictEqual(JSON.parse(jobs[0][4])._meta.favorite, true, "Night is still a favourite after SAVE OVER")
root.write("Day")
assert.strictEqual(JSON.parse(jobs[1][4])._meta.favorite, undefined)
assert.deepStrictEqual(noteCalls, [["adopt", "Night"], ["adopt", "Day"]], "saving a preset gives it the desktop's notes")

// it is not part of the look: the tick doesn't care
const a = { theme: { g: "x" }, _meta: { name: "A", saved: 1 } }
const b = { theme: { g: "x" }, _meta: { name: "A", saved: 9, favorite: true } }
assert.strictEqual(root.digestOf(a), root.digestOf(b))

// ---------- the script: rewrite in place keeps the pictures ----------
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "presets-fav-"))
const env = Object.assign({}, process.env, { XDG_CONFIG_HOME: path.join(tmp, "config"), XDG_STATE_HOME: path.join(tmp, "state"), XDG_DATA_HOME: path.join(tmp, "data") })
const dir = path.join(tmp, "config", "sekaipop", "presets")
const sh = (...x) => spawnSync("sh", [path.join(top, "scripts", "state", "preset-state.sh"), ...x], { env, encoding: "utf8" })
const png = path.join(tmp, "a.png"); fs.writeFileSync(png, "x")
const json = fav => JSON.stringify({ _meta: Object.assign({ name: "Night", v: 1 }, fav ? { favorite: true } : {}), theme: { group: "g" } })
assert.strictEqual(sh("save", "Night", json(false), png, "-").status, 0)
const r = sh("rename", "Night", "Night", json(true))
assert.strictEqual(r.status, 0, r.stderr)
assert.strictEqual(JSON.parse(fs.readFileSync(path.join(dir, "Night.json"), "utf8"))._meta.favorite, true)
assert.ok(fs.existsSync(path.join(dir, "Night.images", "avatar.png")), "pictures stay")
assert.ok(sh("all").stdout.includes('"favorite": true') || sh("all").stdout.includes('"favorite":true'), "listed with the flag")
assert.ok(!fs.readdirSync(dir).some(f => f.endsWith(".tmp")), "no temp files left")
fs.rmSync(tmp, { recursive: true, force: true })

// ---------- the wiring ----------
assert.ok(src.includes("function favorite(name: string): string") && src.includes("presets favorite"), "ipc favorite")
const board = read("EditPresetBoard.qml")
for (const t of ["id: starBtn", "id: starArea", "DesktopPresetService.toggleFavorite(tile.entry.name)",
                 "readonly property bool favorite: DesktopPresetService.isFavorite(tile.entry)"])
    assert.ok(board.includes(t), "board: " + t)
console.log("favorite_unit: all checks passed")
