// Undoing a preset (wearing one, deleting one): preset-state.sh's undo slots and trash run
// for real in a temp folder, DesktopPresetService's and NotesService's undo functions are
// cut out of the .qml and run against fakes, and the board's wiring is checked as text
// (Quickshell can't run here).
const fs = require("fs"), os = require("os"), path = require("path"), assert = require("assert")
const { spawnSync } = require("child_process")
const top = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(require("../lib/locate")(f), "utf8")

// ---------- the script ----------
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "presets-"))
try {
const env = Object.assign({}, process.env, { XDG_CONFIG_HOME: path.join(tmp, "config"), XDG_STATE_HOME: path.join(tmp, "state"), XDG_DATA_HOME: path.join(tmp, "data") })
const dir = path.join(tmp, "config", "sekaipop", "presets")
const sh = (...a) => spawnSync("sh", [path.join(top, "scripts", "state", "preset-state.sh"), ...a], { env, encoding: "utf8" })
const png = path.join(tmp, "a.png"); fs.writeFileSync(png, "x")
const json = (n, extra) => JSON.stringify(Object.assign({ _meta: { name: n, v: 1 }, theme: { group: n } }, extra || {}))
const listed = () => sh("all").stdout.split("\n").filter(l => l !== "").map(l => l.slice(0, l.indexOf("\t")))

assert.strictEqual(sh("save", "Night", json("Night"), png, "-").status, 0)
assert.strictEqual(sh("save", "Day", json("Day")).status, 0)

// the undo slot: saved like a preset, pictures included, listed after the presets
let r = sh("save", ".previous", json("", { theme: { group: "before" } }), png, "-")
assert.strictEqual(r.status, 0, r.stderr)
assert.ok(fs.existsSync(path.join(dir, ".previous.images", "avatar.png")), "the slot keeps its own pictures")
assert.deepStrictEqual(listed(), ["Day", "Night", ".previous"], "the slot is listed last, under its dotted name")
assert.strictEqual(sh("save", ".hid", json("x")).status, 2, "other dotted names are still refused")
assert.strictEqual(sh("save", "..", json("x")).status, 2)

// undoWear's jobs: .previous -> .undone, then a new .previous beside it
assert.strictEqual(sh("delete", ".undone").status, 0, "deleting a slot that isn't there is fine")
r = sh("rename", ".previous", ".undone", json("", { theme: { group: "before" } }))
assert.strictEqual(r.status, 0, r.stderr)
assert.ok(fs.existsSync(path.join(dir, ".undone.images", "avatar.png")), "the pictures move with it")
assert.strictEqual(sh("save", ".previous", json("", { theme: { group: "after" } })).status, 0)
assert.ok(!fs.existsSync(path.join(dir, ".previous.images")), "the new look had no pictures: none left from the old one")
assert.deepStrictEqual(listed(), ["Day", "Night", ".previous"], ".undone is never listed")
const data = path.join(tmp, "data", "sekaipop")
r = sh("restore", ".undone", "avatar", "avatar.png", "avatar-7.png")
assert.strictEqual(r.status, 0); assert.ok(fs.existsSync(path.join(data, "avatar-7.png")), "the undone look's pictures are worn from .undone")

// the trash: one deep, notes kept, back again
r = sh("trash", "Night", JSON.stringify({ worn: false, shown: true, notes: [] }))
assert.strictEqual(r.status, 0, r.stderr)
assert.ok(!fs.existsSync(path.join(dir, "Night.json")) && !fs.existsSync(path.join(dir, "Night.images")), "gone from the presets")
assert.ok(fs.existsSync(path.join(dir, ".trash", "Night.images", "avatar.png")), "pictures in the trash")
assert.deepStrictEqual(listed(), ["Day", ".previous", ".trash/Night", ".trash/.notes", ".trash/.at"])
const at = Number(fs.readFileSync(path.join(dir, ".trash", ".at"), "utf8"))
assert.ok(Math.abs(at - Date.now() / 1000) < 5, "the time it was deleted")
assert.strictEqual(sh("purge-trash", "600").status, 0)
assert.ok(fs.existsSync(path.join(dir, ".trash", "Night.json")), "not yet ten minutes: kept")
assert.strictEqual(sh("purge-trash", "x").status, 2, "bad age refused")
assert.strictEqual(sh("trash", "Nope").status, 1, "no such preset")
assert.strictEqual(sh("trash", "Day").status, 0, "a second delete")
assert.ok(!fs.existsSync(path.join(dir, ".trash", "Night.json")), "only the last one deleted is kept")
assert.ok(!fs.existsSync(path.join(dir, ".trash", ".notes")), "and not the notes of the one before")
assert.strictEqual(sh("save", "Day", json("Day")).status, 0, "a new preset with the deleted one's name")
assert.strictEqual(sh("untrash", "Day").status, 3, "name taken -> exit 3")
assert.ok(fs.existsSync(path.join(dir, ".trash", "Day.json")), "and the trash is left as it was")
assert.strictEqual(sh("delete", "Day").status, 0)
assert.strictEqual(sh("untrash", "Day").status, 0)
assert.ok(fs.existsSync(path.join(dir, "Day.json")) && !fs.existsSync(path.join(dir, ".trash")), "back, trash emptied")
assert.strictEqual(sh("untrash", "Day").status, 1, "nothing in the trash")
assert.ok(!fs.readdirSync(dir).some(f => f.endsWith(".tmp")), "no temp files left")

// a preset called "notes" is not mistaken for the trash's notes
assert.strictEqual(sh("save", "notes", json("notes")).status, 0)
assert.strictEqual(sh("trash", "notes").status, 0)
assert.deepStrictEqual(listed(), ["Day", ".previous", ".trash/notes", ".trash/.at"])
fs.writeFileSync(path.join(dir, ".trash", ".at"), String(Math.floor(Date.now() / 1000) - 601))
assert.strictEqual(sh("purge-trash", "600").status, 0)
assert.ok(!fs.existsSync(path.join(dir, ".trash")), "ten minutes on: gone for good")
assert.strictEqual(sh("purge-trash", "600").status, 0, "no trash: fine")
fs.mkdirSync(path.join(dir, ".trash")); fs.writeFileSync(path.join(dir, ".trash", "Old.json"), "{}")
assert.strictEqual(sh("purge-trash", "600").status, 0)
assert.ok(!fs.existsSync(path.join(dir, ".trash")), "no time written: counts as old")
} finally {
fs.rmSync(tmp, { recursive: true, force: true })
}

// ---------- the service ----------
const src = read("services/DesktopPresetService.qml")
const grabFrom = (text, name) => {
    const start = text.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    return text.slice(start, text.indexOf("\n    }\n", start) + 7).replace(/^    function /, "function ")
}
const make = (names, ctx) => {
    const root = ctx.root
    const keys = Object.keys(ctx), vals = keys.map(k => ctx[k])
    for (const n of names) root[n] = new Function(...keys, "return (" + grabFrom(src, n) + ")")(...vals)
    return root
}

// the listing: dotted lines are slots, not presets
{
    const root = {}
    make(["byName", "parseList", "parseSlots"], { root })
    const text = [
        "Day\t" + JSON.stringify({ theme: 1 }),
        ".previous\t" + JSON.stringify({ theme: 2, _meta: { last: "Day" } }),
        ".trash/Night\t" + JSON.stringify({ theme: 3 }),
        ".trash/.notes\t" + JSON.stringify({ worn: false, notes: [] }),
        ".trash/.at\t1700000000",
        ".trash/\t{}",
        ".bogus\tnot json"
    ].join("\n")
    assert.deepStrictEqual(root.parseList(text).map(p => p.name), ["Day"], "slots are not presets")
    const s = root.parseSlots(text)
    assert.strictEqual(s.previous.theme, 2)
    assert.deepStrictEqual(s.trashed, { name: "Night", data: { theme: 3 }, notes: { worn: false, notes: [] }, at: 1700000000000 })
    assert.strictEqual(root.parseSlots(".trash/X\t{}").trashed.at, 0, "no time: old")
    assert.deepStrictEqual(root.parseSlots("Day\t{}"), { previous: null, trashed: null })
}

// delete -> trash -> undelete
{
    const jobs = [], notes = []
    const NotesService = {
        setPart: n => (notes.push(["part", n]), { worn: false, shown: true, notes: [{ id: "a" }] }),
        dropSet: n => notes.push(["drop", n]),
        restoreSet: (n, p) => notes.push(["restore", n, p])
    }
    const root = { presets: [{ name: "Day", data: { d: 1 } }, { name: "Night", data: { n: 1 } }], lastName: "Night", trashed: null, script: "/s.sh",
                   enqueue: a => jobs.push(a) }
    make(["find", "has", "byName", "remove", "undoRemove"], { root, NotesService })
    root.remove("Nope"); assert.strictEqual(jobs.length, 0)
    root.remove("Night")
    assert.deepStrictEqual(root.presets.map(p => p.name), ["Day"], "the tile goes at once")
    assert.strictEqual(root.lastName, "")
    assert.deepStrictEqual(jobs[0].slice(0, 4), ["sh", "/s.sh", "trash", "Night"])
    assert.deepStrictEqual(JSON.parse(jobs[0][4]).notes, [{ id: "a" }], "its notes go with it")
    assert.deepStrictEqual(notes.slice(0, 2), [["part", "Night"], ["drop", "Night"]], "notes read before they are dropped")
    assert.strictEqual(root.trashed.name, "Night")
    assert.ok(Math.abs(root.trashed.at - Date.now()) < 1000, "when it was deleted")

    root.presets = root.presets.concat([{ name: "night", data: {} }])
    assert.strictEqual(root.undoRemove(), "", "a preset of that name (any capitals) was saved since")
    root.presets = root.presets.filter(p => p.name !== "night")
    assert.strictEqual(root.undoRemove(), "Night")
    assert.deepStrictEqual(root.presets.map(p => p.name), ["Day", "Night"])
    assert.deepStrictEqual(jobs[1], ["sh", "/s.sh", "untrash", "Night"])
    assert.deepStrictEqual(notes[2][0], "restore"); assert.strictEqual(notes[2][1], "Night")
    assert.strictEqual(root.trashed, null); assert.strictEqual(root.undoRemove(), "", "only once")
}

// wear: snapshot first; undo: slot moved, then the new snapshot, then the wear from .undone
{
    const jobs = [], started = []
    const NotesService = { lookPart: () => ({ setName: "Day", shown: true, notes: [] }) }
    const PanelImages = { avatarPath: "/d/avatar-1.png", bannerPath: "", phonePath: "/d/phone-2.png", pathOf(k) { return this[k + "Path"] || "" } }
    let current = false
    const root = {
        presets: [{ name: "Day", data: { theme: "day" } }], lastName: "Day", previous: null, script: "/s.sh",
        enqueue: a => jobs.push(a), refreshLive: () => {}, isCurrent: () => current, busy: () => false,
        capture: () => ({ theme: "now", images: {} }), framePaths: () => ["/f/img-1.png"],
        start: (d, n, b) => started.push([d, n, b])
    }
    make(["find", "keepPrevious", "apply", "undoWear", "wornPictures"], { root, NotesService, PanelImages })

    current = true; root.apply("Day")
    assert.strictEqual(jobs.length, 0, "wearing what is already worn keeps the undo there is")
    assert.strictEqual(started.length, 1, "...and still wears it")

    current = false; root.apply("Day")
    assert.deepStrictEqual(jobs[0].slice(0, 4), ["sh", "/s.sh", "save", ".previous"])
    assert.deepStrictEqual(jobs[0].slice(5), ["/d/avatar-1.png", "-", "/d/phone-2.png", "/f/img-1.png"], "pictures (avatar, banner, phone) and frames copied in")
    const saved = JSON.parse(jobs[0][4])
    assert.strictEqual(saved.theme, "now"); assert.strictEqual(saved._meta.last, "Day")
    assert.deepStrictEqual(saved._meta.notes, { setName: "Day", shown: true, notes: [] }, "the notes themselves are kept")
    assert.strictEqual(root.previous._meta.last, "Day")

    jobs.length = 0; started.length = 0
    const prev = root.previous
    root.lastName = "Other"
    root.undoWear()
    assert.deepStrictEqual(jobs.map(j => j.slice(2, 5)), [["delete", ".undone"], ["rename", ".previous", ".undone"], ["save", ".previous", jobs[2][4]]],
        "slot moved aside before the look being undone takes it")
    assert.strictEqual(JSON.parse(jobs[2][4])._meta.last, "Other", "Undo again goes back to the preset worn now")
    assert.strictEqual(JSON.parse(jobs[2][4])._meta.undone, true, "...and is a redo")
    assert.strictEqual(saved._meta.undone, undefined, "a plain wear saves an undo, not a redo")
    assert.strictEqual(started[0][0], prev); assert.strictEqual(started[0][1], ".undone")
    assert.deepStrictEqual(started[0][2], { notes: prev._meta.notes, set: "Day", last: "Day" })

    // a preset deleted since: no tick name, notes belong to nobody
    root.previous = { theme: "x", _meta: { last: "Gone", notes: { setName: "Gone", notes: [] } } }
    root.undoWear()
    assert.deepStrictEqual(started[1][2], { notes: { setName: "Gone", notes: [] }, set: "", last: "" })
    root.previous = null; const n = started.length; root.undoWear(); assert.strictEqual(started.length, n, "nothing to undo")

    // redo: the look it redoes away from is an undo again (the tile flips back to UNDO)
    jobs.length = 0
    root.previous = { theme: "y", _meta: { last: "Day", undone: true } }
    root.undoWear()
    assert.strictEqual(JSON.parse(jobs[2][4])._meta.undone, undefined, "after a redo: UNDO")
}

// ---------- the notes ----------
{
    const nsrc = read("services/NotesService.qml")
    const listModel = { items: [], get count() { return this.items.length } }
    const root = { loaded: true, setName: "", shown: true, sets: {}, freshId: "x", commits: 0,
                   currentNotes: () => listModel.items.slice(), fill: a => { listModel.items = a.slice() },
                   recount: () => {}, commit: () => root.commits++ }
    const NM = { cleanNotes: a => a.filter(x => x && typeof x === "object") }
    const keys = ["root", "listModel", "NM"], vals = [root, listModel, NM]
    for (const n of ["stashCurrent", "lookPart", "wearLook", "setPart", "restoreSet"])
        root[n] = new Function(...keys, "return (" + grabFrom(nsrc, n) + ")")(...vals)

    // unsaved notes, a preset worn over them, undo: they come back
    listModel.items = [{ id: "mine" }]
    const look = root.lookPart()
    assert.deepStrictEqual(look, { setName: "", shown: true, notes: [{ id: "mine" }] })
    root.setName = "B"; listModel.items = [{ id: "b" }]
    root.wearLook(look, "")
    assert.deepStrictEqual(listModel.items, [{ id: "mine" }], "notes that belonged to no preset are back")
    assert.strictEqual(root.setName, "")
    assert.deepStrictEqual(root.sets.B, { shown: true, notes: [{ id: "b" }] }, "B's notes went to B first")

    // back to a preset's own notes: its set is taken out (they are on the desktop now)
    root.sets = { A: { shown: true, notes: [{ id: "old-a" }] } }
    root.wearLook({ setName: "A", shown: false, notes: [{ id: "a" }, null] }, "A")
    assert.deepStrictEqual(listModel.items, [{ id: "a" }], "cleaned like a file read")
    assert.strictEqual(root.setName, "A"); assert.strictEqual(root.shown, false); assert.ok(!("A" in root.sets))
    root.wearLook(null, ""); assert.strictEqual(root.setName, "A", "no notes part: left alone")

    // delete / undelete
    assert.deepStrictEqual(root.setPart("A"), { worn: true, shown: false, notes: [{ id: "a" }] })
    root.sets = { C: { shown: true, notes: [{ id: "c" }] } }
    assert.deepStrictEqual(root.setPart("C"), { worn: false, shown: true, notes: [{ id: "c" }] })
    assert.strictEqual(root.setPart("Z"), null)
    root.setName = ""
    root.restoreSet("A", { worn: true, notes: [{ id: "a" }] })
    assert.strictEqual(root.setName, "A", "still on the desktop, owned again")
    root.restoreSet("D", { worn: false, shown: true, notes: [{ id: "d" }] })
    assert.deepStrictEqual(root.sets.D, { shown: true, notes: [{ id: "d" }] })
    root.restoreSet("C", { worn: false, notes: [] }); assert.deepStrictEqual(root.sets.C.notes, [{ id: "c" }], "notes it has are kept")
    root.restoreSet("E", { worn: true, shown: true, notes: [{ id: "e" }] })
    assert.deepStrictEqual(root.sets.E, { shown: true, notes: [{ id: "e" }] }, "worn, but the desktop has another preset's notes now: the copy")
    root.loaded = false; assert.strictEqual(root.lookPart(), null, "nothing before the notes are read")
}

// ---------- the wiring ----------
assert.ok(/onTriggered: \{\n\s*root\.trashed = null\n\s*root\.enqueue\(\["sh", root\.script, "purge-trash", String\(root\.trashMinutes \* 60\)\]\)/.test(src), "the timer purges")
assert.ok(src.includes("readonly property int trashMinutes: 10"))
assert.ok(src.includes("function undo(): void") && src.includes("function undelete(): string"), "ipc undo / undelete")
assert.ok(/function apply\(name\)[\s\S]*?root\.keepPrevious\(p\.data\)\n\s*root\.start\(/.test(src), "apply saves the look first")
assert.ok(/if \(back\)\n\s*NotesService\.wearLook\(back\.notes, back\.set\)\n\s*else\n\s*NotesService\.switchSet\(name\)/.test(src), "wear: notes from the undo slot")
assert.ok(src.includes("root.lastName = back ? back.last : name"))
assert.ok(/if \(root\.waiting\)\n\s*root\.proceed\(\)/.test(src), "the wear waits for the queue")
const board = read("EditPresetBoard.qml")
for (const t of ["component UndoTile", "title: redo ? \"REDO\" : \"UNDO\"", "DesktopPresetService.undoWear()", "DesktopPresetService.undoRemove()", "readonly property bool unsaved", "\"NOT SAVED\""])
    assert.ok(board.includes(t), "board: " + t)
console.log("undo_unit: all checks passed")
