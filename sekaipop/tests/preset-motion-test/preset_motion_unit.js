// The motion of wearing a preset (services/DesktopPresetService.qml +
// PresetMotion.qml + Bar.qml / Dock.qml / the widgets). Quickshell can't run
// here, so: the planning functions are cut out of the .qml and run against
// fakes, and the other files are checked as text.
const fs = require("fs"), path = require("path"), assert = require("assert")
const top = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(require("../lib/locate")(f), "utf8")
const src = read("services/DesktopPresetService.qml")

function grab(name) {
    const start = src.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    const end = src.indexOf("\n    }\n", start)
    return src.slice(start, end + 7).replace(/^    function /, "function ")
}

// ---- motionPlan: only what a preset really changes slides ----
let live = null, begun = null, worn = null, swapStarted = false
// motionPlan reads the registry's `before` the same way wearing a preset does
const PP = require("../lib/presetparts")
const PresetWidgets = { list: require("../lib/registry").load({}) }
// The service walks `all` (the list plus the desktop widget plugins); no plugins here.
PresetWidgets.all = PresetWidgets.list
// The bar pills the preset knows (wornSettings): this desktop has no newer ones.
const BarLayoutService = { builtinModules: [{ id: "clock" }], legacyModules: ["clock"] }
const SettingsService = { defaults: { "bar.clock": true } }
const root = { keeps: k => k === "dock.filesCommand", capture: () => live }
root.stable = eval("(" + grab("stable") + ")")
root.wornSettings = eval("(" + grab("wornSettings") + ")")
root.motionPlan = eval("(" + grab("motionPlan") + ")")
const base = () => ({
    settings: { "bar.clock": true, "dock.iconSize": 40, "dock.position": "bottom", "dock.filesCommand": "a", "ui.x": 1 },
    bar: { style: "float", position: "top", layout: { l: [1], r: [2] } },
    widgets: {
        clock: { x: 10, y: 20, shown: true, design: 3 },
        visualizer: { x: 5, y: 6, shown: true, style: "bars", colors: 0, size: 1, vertical: false },
        usercard: { x: 1, y: 2, shown: true },
        weathercard: { x: 3, y: 4, shown: true, style: "classic" },
        todo: { x: 7, y: 8, shown: true }
    }
})
const plan = d => root.motionPlan(d)

live = base()
assert.deepStrictEqual(plan(base()), { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "same desktop: nothing moves")

let d = base(); d.bar.position = "left"
assert.deepStrictEqual(plan(d), { bar: true, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "another bar edge")
d = base(); d.bar.layout = { l: [2], r: [1] }
assert.deepStrictEqual(plan(d), { bar: true, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "another bar layout")
d = base(); d.settings["bar.clock"] = false
assert.deepStrictEqual(plan(d), { bar: true, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "a bar switch")
d = base(); d.settings["dock.position"] = "left"
assert.deepStrictEqual(plan(d), { bar: false, dock: true, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "another dock edge")
d = base(); d.settings["dock.iconSize"] = 52
assert.deepStrictEqual(plan(d), { bar: false, dock: true, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "a dock size")
d = base(); d.settings["dock.filesCommand"] = "other"
assert.deepStrictEqual(plan(d), { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "a key presets never touch is ignored")
d = base(); d.settings["ui.x"] = 99
assert.deepStrictEqual(plan(d), { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "other settings don't move bar or dock")
d = base(); delete d.bar
assert.deepStrictEqual(plan(d), { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "a preset with no bar part")
d = { bar: base().bar }
assert.deepStrictEqual(plan(d), { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "a preset with no settings part")
// ---- widget variants ----
const only = (c, v, u = false, w = false, t = false) => ({ bar: false, dock: false, clock: c, visualizer: v, usercard: u, weathercard: w, todo: t })
d = base(); d.widgets.clock.design = 0
assert.deepStrictEqual(plan(d), only(true, false), "another clock design")
d = base(); d.widgets.clock.x = 999; d.widgets.visualizer.y = 999
assert.deepStrictEqual(plan(d), only(false, false), "a moved widget glides, it does not swap")
d = base(); d.widgets.visualizer.style = "ring"
assert.deepStrictEqual(plan(d), only(false, true), "another visualizer style")
d = base(); d.widgets.visualizer.colors = 2
assert.deepStrictEqual(plan(d), only(false, true), "other visualizer colours")
d = base(); d.widgets.visualizer.size = 3
assert.deepStrictEqual(plan(d), only(false, true), "another visualizer size")
d = base(); d.widgets.visualizer.vertical = true
assert.deepStrictEqual(plan(d), only(false, true), "a band that stands up")
d = base(); delete d.widgets.visualizer.vertical
assert.deepStrictEqual(plan(d), only(false, false), "an older preset without the direction")
// ...which is a band along the bottom, so a band that stands up swaps back to it
live = base(); live.widgets.visualizer.vertical = true; d = base(); delete d.widgets.visualizer.vertical
assert.deepStrictEqual(plan(d), only(false, true), "an older preset without the direction, on a standing band")
live = base()
d = base(); d.widgets.clock.design = 0; d.widgets.visualizer.style = "ring"
assert.deepStrictEqual(plan(d), only(true, true), "both at once")
d = base(); d.widgets.clock.design = 0; d.widgets.clock.shown = false
assert.deepStrictEqual(plan(d), only(true, false), "switched off by the preset: it shrinks away with the rest")
d = base(); d.widgets.usercard.shown = false
assert.deepStrictEqual(plan(d), only(false, false, true), "the user card switched off")
d = base(); d.widgets.weathercard.shown = false
assert.deepStrictEqual(plan(d), only(false, false, false, true), "the weather card switched off")
// the weather card's style: a preset that changes it swaps the card (shrink away, pop back in)
live = base(); live.widgets.weathercard.style = "classic"; d = base(); d.widgets.weathercard.style = "minimal"
assert.deepStrictEqual(plan(d), only(false, false, false, true), "another weather card style")
live = base(); live.widgets.weathercard.style = "minimal"; d = base(); d.widgets.weathercard.style = "minimal"
assert.deepStrictEqual(plan(d), only(false, false), "the same weather card style")
live = base(); live.widgets.weathercard.style = "minimal"; d = base(); delete d.widgets.weathercard.style
assert.deepStrictEqual(plan(d), only(false, false, false, true), "an older preset without the style wears classic: a Minimal card swaps")
live = base(); live.widgets.weathercard.style = "classic"; d = base(); delete d.widgets.weathercard.style
assert.deepStrictEqual(plan(d), only(false, false), "an older preset without the style, on a classic card: nothing swaps")
live = base(); live.widgets.weathercard.style = "classic"; d = base(); d.widgets.weathercard.style = "minimal"; d.widgets.weathercard.shown = false
assert.deepStrictEqual(plan(d), only(false, false, false, true), "style changed but switched off: it just shrinks away")
live = base(); live.widgets.weathercard.style = "classic"; live.widgets.weathercard.shown = false; d = base(); d.widgets.weathercard.style = "minimal"
assert.deepStrictEqual(plan(d), only(false, false), "hidden now: the pop in covers it")
live = base()
d = base(); d.widgets.todo.shown = false
assert.deepStrictEqual(plan(d), only(false, false, false, false, true), "the to-do switched off")
d = base(); d.widgets.visualizer.shown = false
assert.deepStrictEqual(plan(d), only(false, true), "the visualizer switched off")
d = base(); d.widgets.usercard.shown = false; d.widgets.todo.shown = false; d.widgets.clock.design = 0
assert.deepStrictEqual(plan(d), only(true, false, true, false, true), "several at once")
live = base(); live.widgets.usercard.shown = false; d = base()
assert.deepStrictEqual(plan(d), only(false, false), "switched ON: it keeps its pop in")
live = base(); live.widgets.usercard.shown = false; d = base(); d.widgets.usercard.shown = false
assert.deepStrictEqual(plan(d), only(false, false), "off before and after: nothing to shrink")
live = base()
d = base(); delete d.widgets.todo
assert.deepStrictEqual(plan(d), only(false, false), "a preset that says nothing about the to-do")
live = base(); live.widgets.clock.shown = false; d = base(); d.widgets.clock.design = 0
assert.deepStrictEqual(plan(d), only(false, false), "hidden now: the pop in covers it")
live = base(); d = base(); delete d.widgets.clock.design
assert.deepStrictEqual(plan(d), only(false, false), "an older preset without the key")
d = base(); delete d.widgets
assert.deepStrictEqual(plan(d), only(false, false), "a preset with no widgets part")
live = base()

live = null; root.capture = () => { throw new Error("boom") }
assert.deepStrictEqual(plan(base()), { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }, "a failing capture never blocks wearing")

// ---- finishApply: slide away first, then wear; or just wear ----
const PresetMotion = { begin(p) { begun = p } }
const swap = { restart() { swapStarted = true } }
const r2 = { pendingData: null, pendingName: "", swapData: null, swapName: "", swapFound: null,
    wear(d, n, f) { worn = [d, n, f] }, motionPlan: () => nextPlan }
let nextPlan = { bar: false, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }
r2.finishApply = eval("(" + grab("finishApply").replace(/root\./g, "r2.") + ")")
const found = { "/w.png": true }
r2.pendingData = { a: 1 }; r2.pendingName = "P"; r2.finishApply(found)
assert.deepStrictEqual(worn, [{ a: 1 }, "P", found], "nothing to slide: worn at once")
assert.strictEqual(begun, null); assert.strictEqual(swapStarted, false)

worn = null; nextPlan = { bar: true, dock: false, clock: false, visualizer: false, usercard: false, weathercard: false, todo: false }
r2.pendingData = { a: 2 }; r2.pendingName = "Q"; r2.finishApply(found)
assert.strictEqual(worn, null, "bar changes: not worn until it is away")
assert.deepStrictEqual(begun, nextPlan); assert.strictEqual(swapStarted, true)
assert.deepStrictEqual(r2.swapData, { a: 2 }); assert.strictEqual(r2.swapName, "Q"); assert.strictEqual(r2.swapFound, found)
assert.strictEqual(r2.pendingData, null)

// ---- the wiring, as text ----
assert.ok(/pragma Singleton/.test(read("PresetMotion.qml")))
for (const n of ["barOut", "dockOut", "barBusy", "dockBusy", "clockOut", "visualizerOut", "usercardOut", "weathercardOut", "todoOut", "function begin", "function release"])
    assert.ok(read("PresetMotion.qml").includes(n), "PresetMotion: " + n)
assert.ok(src.includes("PresetMotion.release()") && src.includes("swap.running"), "service releases and guards")
const bar = read("Bar.qml")
assert.ok(bar.includes("onBarOutChanged") && bar.includes("PresetMotion.barBusy") && bar.includes("slideBy"))
assert.strictEqual((bar.match(/\+ slideBy|- slideBy/g) || []).length, 4, "Bar: all four edges are pushed by slideBy")
const dock = read("Dock.qml")
assert.ok(dock.includes("onDockOutChanged") && dock.includes("PresetMotion.dockBusy"))
for (const side of ["bottom", "top", "left", "right"])
    assert.ok(dock.includes("anchors." + side + "Margin: dockWindow.position === \"" + side + "\" ? dockWindow.innerGap - dockWindow.pullOffset : 0"), "Dock " + side + " margin uses pullOffset")
for (const [f, sig] of [["ClockWidget.qml", "onClockOutChanged"], ["VisualizerWidget.qml", "onVisualizerOutChanged"],
                         ["UserCardWidget.qml", "onUsercardOutChanged"], ["WeatherCardWidget.qml", "onWeathercardOutChanged"],
                         ["TodoWidget.qml", "onTodoOutChanged"]]) {
    const w = read(f)
    assert.ok(w.includes(sig) && w.includes("id: swapOut") && w.includes("id: swapIn"), f + ": variant swap animations")
    assert.ok(/scale:[^\n]*win\.swapK/.test(w) && /opacity:[^\n]*win\.swapK/.test(w), f + ": card scale and opacity follow swapK")
    assert.ok(w.includes("id: swapRest") && w.includes("} else if (win.want) {"), f + ": a card that is off stays away until its swallow is over")
}
for (const f of ["ClockWidget.qml", "UserCardWidget.qml", "WeatherCardWidget.qml", "VisualizerWidget.qml", "TodoWidget.qml"]) {
    const w = read(f)
    assert.ok(w.includes("!win.gliding"), f + ": compact window yields while gliding")
    assert.strictEqual((w.match(/Behavior on [xy] \{\s*enabled: win\.glideOn/g) || []).length, 2, f + ": x and y glide")
    assert.ok(w.includes("id: glideStart") && w.includes("id: glideEnd"), f + ": glide timers")
}
console.log("preset_motion_unit: all checks passed")
