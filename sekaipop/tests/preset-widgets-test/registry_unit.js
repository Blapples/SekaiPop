// The widget registry (services/PresetWidgets.qml) and the rule it runs on
// (modules/common/functions/PresetParts.js):
//
//   a preset wears what it holds;
//   a widget a preset saved BEFORE it existed has no part for is switched OFF, and an
//   option (a style, a size, a direction) it has no value for is worn as the entry's
//   `before` says, whatever the widget is set to now.
//
// Quickshell can't run here, so the real PresetParts.js runs in node, the real widget
// list is read out of PresetWidgets.qml and run against fake services, and the shell's
// own files are read as text to catch a widget that was made but never registered.
// Run: node registry_unit.js
const fs = require("fs"), assert = require("assert")
const locate = require("../lib/locate")
const PP = require("../lib/presetparts")
const reg = require("../lib/registry")
const read = f => fs.readFileSync(locate(f), "utf8")

// ---------- fakes ----------
const log = []
const snap = (name, state) => ({
    name, state, get shown() { return this.state.shown }, persisted: 0,
    snapshot() { return JSON.stringify(this.state) },
    restore(t) { log.push(name + ".restore"); this.state = JSON.parse(t) },
    persist() { this.persisted++ },
    setShown(v) { log.push(name + ".setShown(" + v + ")"); this.state.shown = v }
})
function world() {
    const w = {
        ClockService: snap("clock", { x: 1, y: 2, shown: true, design: 0, use24h: true }),
        UserCardService: snap("usercard", { x: 3, y: 4, shown: true, size: "2x2" }),
        WeatherCardService: snap("weathercard", { x: 5, y: 6, shown: true, style: "classic", size: "2x2" }),
        VisualizerService: snap("visualizer", { x: 7, y: 8, shown: true, style: "bars", vertical: false, bandX: -1, perf: 2 }),
        CalendarCardService: snap("calendarcard", { x: 9, y: 9, shown: true, size: "full", events: ["mine"] }),
        PaletteService: snap("palettecard", { x: 1, y: 1, shown: true, size: "full", colors: ["#fff"], scheme: "x" }),
        WaterTankService: snap("watertank", { x: 4, y: 4, shown: true, size: "1x1", goal: 10, glassMl: 300, glasses: 5, day: "2026-10-27", history: { "2026-10-26": 7 } }),
        DownloaderService: snap("downloader", { x: 6, y: 6, shown: true, size: "2x2", engine: "cobalt", mode: "audio", quality: "720", audioFormat: "opus", folder: "/d", cobaltUrl: "https://c.example", cobaltKey: "secret", notify: false, done: [{ id: 1, file: "/d/a.mp3" }] }),
        LyricsService: snap("lyrics", { x: 2, y: 3, shown: true, syncMs: 250, offsets: { "a|b|1": 300 } }),
        TodoService: { posX: 1, posY: 2, posScale: 1, shown: true, size: "2x2",
            setShown(v) { log.push("todo.setShown(" + v + ")"); this.shown = v },
            setSize(v) { this.size = v }, setPosition(x, y, s) { this.posX = x; this.posY = y; this.posScale = s } },
        NotesService: { shown: true, setShown(v) { log.push("notes.setShown(" + v + ")"); this.shown = v } },
        ImageService: { shown: true, loaded: true, items: [{ id: "a", path: "/d/a.png" }],
            setShown(v) { log.push("images.setShown(" + v + ")"); this.shown = v } }
    }
    w.DesktopPresetService = { imagesPart: () => ({ shown: w.ImageService.shown, items: w.ImageService.items.map(r => Object.assign({}, r)) }) }
    return w
}
const frames = []
const ctx = { name: "P", wearFrames: items => frames.push(items) }

// ---------- 1. the registry file itself ----------
let w = world()
let list = reg.load(w)
assert.deepStrictEqual(reg.ids, ["clock", "usercard", "weathercard", "visualizer", "todo", "calendarcard", "palettecard", "watertank", "downloader", "lyrics", "notes", "images"])
assert.deepStrictEqual(PP.problems(list), [], "the real list has no problems: " + JSON.stringify(PP.problems(list)))
// problems() says what is wrong with a half-made entry
assert.ok(PP.problems([{ id: "x" }]).some(m => m.includes("no service")))
assert.ok(PP.problems([{ id: "x", service: { shown: true } }]).some(m => m.includes("setShown")))
assert.ok(PP.problems([{ id: "x", service: { shown: true, setShown() {} } }]).some(m => m.includes("snapshot")))
assert.ok(PP.problems([{ id: "x", service: { shown: true, setShown() {} }, capture() {}, wear() {} }]).length === 0, "capture + wear need no snapshot()")
assert.ok(PP.problems([{ id: "x", service: w.ClockService }, { id: "x", service: w.ClockService }]).some(m => m.includes("twice")))
assert.ok(PP.problems([{ service: w.ClockService }]).some(m => m.includes("no id")))
assert.ok(PP.problems([{ id: "x", service: w.ClockService, skip: "use24h" }]).some(m => m.includes("skip")))

// ---------- 2. capture: every widget, without what is yours ----------
const saved = JSON.parse(JSON.stringify(PP.capture(list)))
assert.deepStrictEqual(Object.keys(saved).sort(), [...reg.ids].sort())
assert.strictEqual("use24h" in saved.clock, false, "the clock's 24-hour format is yours")
assert.strictEqual("events" in saved.calendarcard, false, "the calendar's events are yours")
assert.strictEqual("colors" in saved.palettecard, false, "the palette's colours are yours")
for (const k of ["goal", "glassMl", "glasses", "day", "history"])
    assert.strictEqual(k in saved.watertank, false, "the water tank's " + k + " is yours, not the look's")
assert.deepStrictEqual(saved.watertank, { x: 4, y: 4, shown: true, size: "1x1" })
for (const k of ["engine", "mode", "quality", "audioFormat", "folder", "cobaltUrl", "cobaltKey", "notify", "done"])
    assert.strictEqual(k in saved.downloader, false, "the downloader's " + k + " is yours, not the look's (the cobalt key above all)")
assert.deepStrictEqual(saved.downloader, { x: 6, y: 6, shown: true, size: "2x2" })
assert.strictEqual("syncMs" in saved.lyrics, false, "the lyrics' sync nudge is your player's, not the look's")
assert.strictEqual("offsets" in saved.lyrics, false, "and so are the nudges of single songs")
assert.strictEqual("perf" in saved.visualizer, false, "the visualizer's performance switch is the machine's")
assert.deepStrictEqual(saved.todo, { x: 1, y: 2, scale: 1, shown: true, size: "2x2" })
assert.deepStrictEqual(saved.notes, { shown: true })
assert.strictEqual(saved.images.items.length, 1)
// a widget that throws on capture holds {} and doesn't stop the save
const quiet = console.warn; console.warn = () => {}
const broken = [{ id: "bad", service: { snapshot() { throw new Error("x") }, restore() {}, persist() {}, setShown() {}, shown: true }, capture() { throw new Error("boom") } }, list[0]]
const got = PP.capture(broken)
console.warn = quiet
assert.deepStrictEqual(got.bad, {}); assert.ok("clock" in got)

// ---------- 3. THE RULE: an old preset switches a newer widget off ----------
// A preset saved before the calendar card, palette card, notes and images existed:
const old = JSON.parse(JSON.stringify(saved))
for (const id of ["calendarcard", "palettecard", "watertank", "downloader", "lyrics", "notes", "images"]) delete old[id]
w = world(); list = reg.load(w); log.length = 0
PP.wear(list, old, ctx)
for (const id of ["calendarcard", "palettecard", "watertank", "downloader", "lyrics", "notes", "images"])
    assert.ok(log.includes(id + ".setShown(false)"), id + " must be switched OFF by a preset that predates it")
assert.deepStrictEqual(frames, [], "no frames are touched for a preset that holds none")
for (const id of ["clock", "usercard", "weathercard", "visualizer", "todo"])
    assert.ok(!log.includes(id + ".setShown(false)"), id + " is in the preset and is worn, not switched off")
assert.strictEqual(w.CalendarCardService.state.shown, false)
assert.strictEqual(w.ClockService.state.shown, true)

// ...and a widget that ONLY THE FUTURE knows is handled the same way, with no code here:
const future = snap("hologram", { x: 0, y: 0, shown: true })
w = world(); list = reg.load(w).concat([{ id: "hologram", service: future }]); log.length = 0
PP.wear(list, old, ctx)
assert.ok(log.includes("hologram.setShown(false)"), "a brand-new registry entry follows the same rule")
assert.strictEqual(future.state.shown, false)
// and a preset saved WITH it wears it (shown restored, your own keys kept)
const withFuture = JSON.parse(JSON.stringify(PP.capture(list))); withFuture.hologram.shown = true; withFuture.hologram.x = 77
future.state.shown = false; future.state.x = 0
PP.wear(list, withFuture, ctx)
assert.deepStrictEqual([future.state.shown, future.state.x], [true, 77])

// a preset with no `widgets` at all leaves every widget alone
w = world(); list = reg.load(w); log.length = 0
PP.wear(list, undefined, ctx); PP.wear(list, null, ctx); PP.wear(list, [], ctx)
assert.deepStrictEqual(log, [])

// ---------- 4. wearing what the preset holds ----------
w = world(); list = reg.load(w); log.length = 0; frames.length = 0
const p2 = JSON.parse(JSON.stringify(saved))
p2.clock.design = 4; p2.clock.x = 500; p2.visualizer.style = "ring"; p2.calendarcard.shown = false
p2.todo = { x: 40, y: 50, scale: 2, shown: false, size: "full" }
p2.notes.shown = false
p2.images = { shown: true, items: [{ id: "z", path: "/p/z.png" }] }
PP.wear(list, p2, ctx)
assert.strictEqual(w.ClockService.state.design, 4); assert.strictEqual(w.ClockService.state.x, 500)
assert.strictEqual(w.ClockService.state.use24h, true, "a key the preset never carries keeps your value")
assert.strictEqual(w.VisualizerService.state.style, "ring"); assert.strictEqual(w.VisualizerService.state.perf, 2)
assert.deepStrictEqual(w.CalendarCardService.state.events, ["mine"])
assert.strictEqual(w.CalendarCardService.state.shown, false)
assert.ok(w.ClockService.persisted >= 1, "each widget saves itself after a restore")
assert.deepStrictEqual([w.TodoService.posX, w.TodoService.posY, w.TodoService.posScale, w.TodoService.shown, w.TodoService.size], [40, 50, 2, false, "full"])
assert.strictEqual(w.NotesService.shown, false)
assert.deepStrictEqual(frames, [[{ id: "z", path: "/p/z.png" }]])
// a key a newer build added to the clock, which this preset never held, keeps its value
w.ClockService.state.newOption = "mine"
PP.wear(list, p2, ctx)
assert.strictEqual(w.ClockService.state.newOption, "mine")
// images on / off only (a preset from before frames): frames left alone
frames.length = 0; log.length = 0
const noFrames = JSON.parse(JSON.stringify(saved)); noFrames.images = { shown: true }
PP.wear(list, noFrames, ctx)
assert.deepStrictEqual(frames, []); assert.ok(log.includes("images.setShown(true)"))
// a preset saved before the visualizer could stand up means "a band along the bottom"
w = world(); list = reg.load(w); w.VisualizerService.state.vertical = true; w.VisualizerService.state.bandX = 300
const oldViz = JSON.parse(JSON.stringify(saved)); delete oldViz.visualizer.vertical; delete oldViz.visualizer.bandX
PP.wear(list, oldViz, ctx)
assert.deepStrictEqual([w.VisualizerService.state.vertical, w.VisualizerService.state.bandX], [false, -1])
// a preset saved before the to-do's size existed has the card as it always was: "full",
// whatever size it is on now
w = world(); list = reg.load(w); w.TodoService.size = "2x2"
const noSize = JSON.parse(JSON.stringify(saved)); delete noSize.todo.size
PP.wear(list, noSize, ctx)
assert.strictEqual(w.TodoService.size, "full", "an old preset wears the to-do as it always was")
w.TodoService.size = "full"; const small = JSON.parse(JSON.stringify(saved)); small.todo.size = "2x2"
PP.wear(list, small, ctx)
assert.strictEqual(w.TodoService.size, "2x2", "a preset saved with 2x2 wears 2x2")
// one widget that throws doesn't stop the rest from being worn
w = world(); list = reg.load(w)
w.ClockService.restore = () => { throw new Error("nope") }
console.warn = () => {}
PP.wear(list, p2, ctx)
console.warn = quiet
assert.strictEqual(w.UserCardService.state.shown, true); assert.strictEqual(w.TodoService.size, "full"); assert.strictEqual(w.NotesService.shown, false)

// ---------- 5. "is this the preset I'm wearing": the tick ----------
const stable = v => Array.isArray(v) ? "[" + v.map(stable).join(",") + "]"
    : v !== null && typeof v === "object" ? "{" + Object.keys(v).sort().map(k => JSON.stringify(k) + ":" + stable(v[k])).join(",") + "}"
    : String(JSON.stringify(v))
const same = (lst, preset) => stable(PP.digestWidgets(lst, preset)) === stable(PP.capture(lst))
w = world(); list = reg.load(w)
const mine = JSON.parse(JSON.stringify(PP.capture(list)))
assert.strictEqual(same(list, mine), true, "just saved = current")
w.ClockService.state.design = 9
assert.strictEqual(same(list, mine), false, "changing a look takes the tick away")
w.ClockService.state.design = 0
assert.strictEqual(same(list, mine), true)
// a key the clock gains in a later build doesn't take the tick from older presets
w.ClockService.state.newOption = 1
assert.strictEqual(same(list, mine), true, "a newer option the preset can't hold never takes the tick")
// a preset from before the calendar card: it ticks once the card is off, not while it shows
w = world(); list = reg.load(w)
const oldP = JSON.parse(JSON.stringify(PP.capture(list))); delete oldP.calendarcard; delete oldP.notes; delete oldP.images
assert.strictEqual(same(list, oldP), false, "a newer widget is showing: this old preset is not what you see")
w.CalendarCardService.state.shown = false; w.NotesService.shown = false
assert.strictEqual(PP.digestWidgets(list, oldP).images.shown, false)
// (images are compared on on / off only for a preset that holds no frames: see DesktopPresetService.isCurrent)
const live = PP.capture(list); live.images = { shown: live.images.shown }
w.ImageService.shown = false; live.images = { shown: false }
const dig = PP.digestWidgets(list, oldP)
assert.strictEqual(stable(dig.images), stable(live.images))
assert.strictEqual(stable(dig.calendarcard), stable(PP.capture(list).calendarcard))
// the weather card's style: a preset saved before Minimal existed holds no `style`, and it was
// saved with the only style there was. It wears classic and is compared as classic.
w = world(); list = reg.load(w)
w.WeatherCardService.state.style = "minimal"
const noLook = JSON.parse(JSON.stringify(PP.capture(list))); delete noLook.weathercard.style
assert.strictEqual(same(list, noLook), false, "a Minimal card is not what an old preset (classic) shows")
log.length = 0; PP.wear(list, noLook, ctx)
assert.strictEqual(w.WeatherCardService.state.style, "classic", "wearing an old preset puts the card back on classic")
assert.strictEqual(same(list, noLook), true, "...and then it is the one you are wearing")
const minimalP = JSON.parse(JSON.stringify(PP.capture(list))); minimalP.weathercard.style = "minimal"
PP.wear(list, minimalP, ctx)
assert.strictEqual(w.WeatherCardService.state.style, "minimal", "a preset saved with Minimal wears Minimal")
assert.strictEqual(same(list, minimalP), true)
assert.strictEqual(same(list, noLook), false)
// "full" was classic's old name: a preset that says it wears, and ticks as, classic
w = world(); list = reg.load(w); w.WeatherCardService.state.style = "minimal"
const namedFull = JSON.parse(JSON.stringify(PP.capture(list))); namedFull.weathercard.style = "full"
PP.wear(list, namedFull, ctx)
assert.strictEqual(w.WeatherCardService.state.style, "classic", 'a preset that says "full" wears classic')
assert.strictEqual(same(list, namedFull), true, 'and ticks as classic')

// ---------- 5b. THE ONE RULE FOR A NEW OPTION: `before` ----------
// a preset saved before an option existed wears what it was before, not what it is now,
// for every widget that lists it, and the same for the tick. The same line works for a
// widget and an option this test has never heard of:
const gadget = snap("gadget", { x: 0, y: 0, shown: true, style: "minimal", size: "3x2", own: "mine" })
const gadgetEntry = { id: "gadget", service: gadget, skip: ["own"], before: { style: "classic", size: "2x2" } }
w = world(); list = reg.load(w).concat([gadgetEntry])
const holdsGadget = JSON.parse(JSON.stringify(PP.capture(list)))
delete holdsGadget.gadget.style; delete holdsGadget.gadget.size       // saved before both existed
PP.wear(list, holdsGadget, ctx)
assert.deepStrictEqual([gadget.state.style, gadget.state.size], ["classic", "2x2"], "an old preset wears each new option as it was before")
assert.strictEqual(gadget.state.own, "mine", "what is yours is still yours")
assert.strictEqual(same(list, holdsGadget), true, "...and then it is the one you are wearing")
gadget.state.style = "minimal"
assert.strictEqual(same(list, holdsGadget), false, "a different style is not what that old preset shows")
// only the missing option is filled: one the preset holds is worn as saved
const holdsSize = JSON.parse(JSON.stringify(holdsGadget)); holdsSize.gadget.size = "1x1"
PP.wear(list, holdsSize, ctx)
assert.deepStrictEqual([gadget.state.style, gadget.state.size], ["classic", "1x1"], "a saved value wins over `before`")
// fillBefore on its own: never touches what is there, and hands back the same object when there is nothing to fill
const part = { style: "minimal" }
assert.strictEqual(PP.fillBefore({ before: { style: "classic" } }, part), part)
assert.deepStrictEqual(PP.fillBefore({ before: { style: "classic", size: "2x2" } }, part), { style: "minimal", size: "2x2" })
assert.deepStrictEqual(part, { style: "minimal" }, "the preset's own object is not changed")
assert.strictEqual(PP.fillBefore({}, part), part)
// the registry check catches a `before` that can't work
assert.deepStrictEqual(PP.problems(list), [], JSON.stringify(PP.problems(list)))
assert.ok(PP.problems([{ id: "x", service: gadget, before: "classic" }]).some(m => m.includes("before must be an object")))
assert.ok(PP.problems([{ id: "x", service: gadget, before: { stlye: "classic" } }]).some(m => m.includes("stlye")), "a typo in `before` is reported")
// and the real list: each widget's `before` names things it really saves
for (const id of ["weathercard", "visualizer", "todo"]) {
    const e = list.find(x => x.id === id)
    assert.ok(e.before && Object.keys(e.before).length, id + " lists what it was before")
}
assert.deepStrictEqual(list.find(x => x.id === "weathercard").before, { style: "classic", size: "2x2" })
assert.deepStrictEqual(list.find(x => x.id === "usercard").before, { size: "2x2" })
assert.deepStrictEqual(list.find(x => x.id === "todo").before, { size: "full" })
// a preset saved before the 1x1 size existed wears the user and weather cards as they always were
w = world(); list = reg.load(w); w.UserCardService.state.size = "1x1"; w.WeatherCardService.state.size = "1x1"
const noTinySize = JSON.parse(JSON.stringify(PP.capture(list))); delete noTinySize.usercard.size; delete noTinySize.weathercard.size
PP.wear(list, noTinySize, ctx)
assert.deepStrictEqual([w.UserCardService.state.size, w.WeatherCardService.state.size], ["2x2", "2x2"], "an old preset puts the user and weather cards back to 2x2")
// ... and one saved with 1x1 wears 1x1
w = world(); list = reg.load(w); w.UserCardService.state.size = "1x1"
const tinyP = JSON.parse(JSON.stringify(PP.capture(list))); w.UserCardService.state.size = "2x2"
PP.wear(list, tinyP, ctx)
assert.strictEqual(w.UserCardService.state.size, "1x1", "a preset saved with 1x1 wears 1x1")
// every card with a 2x2 / full size wears an old preset as "full"
for (const id of ["calendarcard", "palettecard"])
    assert.deepStrictEqual(list.find(x => x.id === id).before, { size: "full" }, id + ": an old preset wears the card as it always was")
w = world(); list = reg.load(w); w.CalendarCardService.state.size = "2x2"; w.PaletteService.state.size = "2x2"
const noCardSize = JSON.parse(JSON.stringify(PP.capture(list))); delete noCardSize.calendarcard.size; delete noCardSize.palettecard.size
PP.wear(list, noCardSize, ctx)
assert.deepStrictEqual([w.CalendarCardService.state.size, w.PaletteService.state.size], ["full", "full"], "an old preset puts both cards back to full")
assert.deepStrictEqual(w.CalendarCardService.state.events, ["mine"], "...and the events are still yours")
assert.deepStrictEqual(list.find(x => x.id === "visualizer").before, { vertical: false, bandX: -1 })

// widgets this build doesn't know are left out of the comparison (it never wears them)
const fromTheFuture = JSON.parse(JSON.stringify(mine)); fromTheFuture.hologram = { shown: true }
assert.strictEqual("hologram" in PP.digestWidgets(list, fromTheFuture), false)

// ---------- 6. nothing gets made without being registered ----------
// every widget the shell loads has an entry (or is named here, with the reason)
const NOT_IN_PRESETS = {}               // id -> why. Empty on purpose: add here only if a widget must NOT follow presets.
const shell = read("shell.qml")
const gated = [...shell.matchAll(/widgetId:\s*"([^"]+)"/g)].map(m => m[1])
assert.ok(gated.length >= 8, "shell.qml: couldn't find the widget gates")
for (const id of gated)
    assert.ok(reg.ids.includes(id) || id in NOT_IN_PRESETS,
        'shell.qml loads a widget "' + id + '" that PresetWidgets.qml has no entry for: old presets would leave it on (add an entry, see the top of PresetWidgets.qml)')
// every widget in Edit Desktop's shelf too ("image" is the maker of frames; its widget is "images")
const edit = read("services/EditMode.qml")
const shelf = [...edit.slice(edit.indexOf("readonly property var widgetList"), edit.indexOf("function homeScreen")).matchAll(/\{ id: "([^"]+)"/g)].map(m => m[1])
for (const id of shelf) {
    const reg_id = id === "image" ? "images" : id
    assert.ok(reg.ids.includes(reg_id) || reg_id in NOT_IN_PRESETS, 'EditMode.widgetList has "' + id + '" with no entry in PresetWidgets.qml')
}
// and every entry's service really has what the registry relies on
for (const { id, service } of reg.entries) {
    const f = locate("services/" + service + ".qml")
    const src = fs.readFileSync(f, "utf8")
    assert.ok(/property\s+bool\s+shown\b/.test(src), service + ": no `property bool shown`")
    assert.ok(/function\s+setShown\s*\(/.test(src), service + ": no setShown()")
    const e = reg.src.slice(reg.src.indexOf('id: "' + id + '"'))
    const own = e.slice(0, e.search(/\n        \{|\n        \}|\n    \]/) > 0 ? e.search(/\n        \{|\n        \}|\n    \]/) : e.length)
    if (!/capture:/.test(own) || !/wear:/.test(own))
        for (const fn of ["snapshot", "restore", "persist"])
            assert.ok(new RegExp("function\\s+" + fn + "\\s*\\(").test(src), service + ": no " + fn + "() (the entry for \"" + id + "\" relies on it)")
}
// DesktopPresetService goes through the registry and keeps no list of its own
const svc = read("services/DesktopPresetService.qml")
// (`all` is `list` plus the desktop widget plugins, services/PluginService.qml.)
for (const needle of ["PP.capture(PresetWidgets.all)", "PP.digestWidgets(PresetWidgets.all", "PP.wear(PresetWidgets.all", "PP.problems(PresetWidgets.all)"])
    assert.ok(svc.includes(needle), "DesktopPresetService must call " + needle)
assert.ok(!/PresetWidgets\.list\b(?!\.qml)/.test(svc.replace(/\/\/.*$/gm, "")), "DesktopPresetService must walk PresetWidgets.all, not .list (or the plugins are left out of presets)")
assert.ok(/readonly property var all:\s*root\.list\.concat\(PluginService\.presetEntries\)/.test(reg.text), "PresetWidgets.all is the list plus the plugins")
for (const gone of ["laterWidgets", "widgetSkip", "restoreWidget", "laterWidgetNow"])
    assert.ok(!svc.includes(gone), "DesktopPresetService still has its own " + gone + " (the registry owns it now)")
assert.ok(svc.includes('import "../modules/common/functions/PresetParts.js" as PP'))

console.log("registry_unit: all checks passed")
