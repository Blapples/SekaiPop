// Presets keep the to-do's SIZE and every Custom Image FRAME (and wear them back).
// Quickshell can't run here, so the functions are cut out of the .qml text and run
// against fakes, as preset_images_unit.js does; the wiring is checked from source.
const fs = require("fs"), assert = require("assert"), path = require("path")
const base = path.join(__dirname, "..", "..")
const svcSrc = fs.readFileSync(path.join(base, "services", "DesktopPresetService.qml"), "utf8")
const imgSrc = fs.readFileSync(path.join(base, "services", "ImageService.qml"), "utf8")

function grab(src, name) {
    const start = src.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    const end = src.indexOf("\n    }\n", start)
    return src.slice(start, end + 7).replace(/^    function /, "function ")
}

// ---- fakes
const IM = {
    normalize(r) { return r && typeof r.path === "string" ? Object.assign({}, r) : null }
}
const forgot = []
const ImageService = {
    loaded: true, shown: true, items: [], committed: null, saved: 0,
    commit(list, structural) { this.items = list; this.committed = structural },
    saveNow() { this.saved++ },
    forget(p) { forgot.push(p) }
}
ImageService.wearFrames = eval("(" + grab(imgSrc, "wearFrames") + ")").bind(ImageService)
// wearFrames calls root.* -> the same object
const rootI = ImageService
const wf = grab(imgSrc, "wearFrames").replace(/root\./g, "ImageService.")
ImageService.wearFrames = eval("(" + wf + ")")

// The widgets go through the REAL registry (services/PresetWidgets.qml) against fake services.
const PP = require("../lib/presetparts")
const reg = require("../lib/registry")
const snapService = state => ({
    state, get shown() { return this.state.shown }, persisted: 0,
    snapshot() { return JSON.stringify(this.state) },
    restore(t) { Object.assign(this.state, JSON.parse(t)) },
    persist() { this.persisted++ },
    setShown(v) { this.state.shown = v }
})
const TodoService = { posX: 1, posY: 2, posScale: 1, shown: true, size: "2x2", setShown(v) { this.shown = v }, setSize(v) { this.size = v }, setPosition(x, y, sc) { this.posX = x; this.posY = y; this.posScale = sc } }
const NotesService = { shown: false, setShown(v) { this.shown = v } }
const root = { script: "/s/preset-state.sh" }
for (const n of ["stable", "digestOf", "isCurrent", "variantKey", "digestsOf", "framePaths", "imagesPart", "baseName"])
    root[n] = eval("(" + grab(svcSrc, n).replace(/root\./g, "root.") + ")")
const PresetWidgets = {
    list: reg.load({
        ClockService: snapService({ x: 1, y: 2, shown: true, design: 0, use24h: false }),
        UserCardService: snapService({ x: 3, y: 4, shown: true }),
        WeatherCardService: snapService({ x: 5, y: 6, shown: true, style: "classic" }),
        VisualizerService: snapService({ x: 7, y: 8, shown: true, vertical: false, bandX: -1, perf: 1 }),
        CalendarCardService: snapService({ x: 9, y: 9, shown: false, size: "full", events: [] }),
        PaletteService: snapService({ x: 1, y: 1, shown: false, size: "full", colors: [] }),
        TodoService, NotesService, ImageService, DesktopPresetService: root
    })
}
const settings = { "quick.flat": false, "panel.hotEdge": true, "panel.hotDwell": 140, "panel.hotPeek": false, "panel.typeToSearch": true,
    "overview.style": "board", "overview.position": "center", "overview.workspaces": 5,
    "overview.layout": "", "overview.scale": 0, "overview.gap": -1, "lock.style": "gacha" }
let applied = 0
const ScrollOverviewService = { applyConfig() { applied++ } }
const SettingsService = {
    flag: k => !!settings[k], get: k => settings[k],
    set(k, v) { if (k in settings) settings[k] = v }
}
for (const n of ["phonePart", "wearPhone", "overviewPart", "wearOverview", "lockPart", "wearLock"]) root[n] = eval("(" + grab(svcSrc, n) + ")")

// ---- imagesPart / framePaths
const A = { id: "a", path: "/home/u/.local/share/sekaipop/custom-images/img-1-1.png", x: 10, y: 20, w: 300, h: 200 }
const B = { id: "b", path: "", x: 5, y: 5, w: 320, h: 240 }              // an empty frame
const C = { id: "c", path: A.path, x: 50, y: 60, w: 100, h: 100 }        // same picture, 2nd frame
ImageService.items = [A, B, C]
let part = root.imagesPart()
assert.strictEqual(part.items.length, 3)
assert.deepStrictEqual(part.items[0], A)
assert.notStrictEqual(part.items[0], A)                                    // a copy, not the live record
ImageService.loaded = false
assert.strictEqual("items" in root.imagesPart(), false)                    // never a preset with no frames by accident
ImageService.loaded = true
assert.deepStrictEqual(root.framePaths({ widgets: { images: part } }), [A.path])   // no repeats, no empty frame
assert.deepStrictEqual(root.framePaths({ widgets: { images: { shown: true } } }), [])
assert.deepStrictEqual(root.framePaths({}), [])

// ---- ImageService.wearFrames
ImageService.items = [{ id: "old", path: "/d/img-9-9.png" }]
ImageService.wearFrames(part.items, { "img-1-1.png": "/other/home/custom-images/img-1-1.png" })
assert.deepStrictEqual(ImageService.items.map(r => r.id), ["a", "b", "c"])
assert.strictEqual(ImageService.items[0].path, "/other/home/custom-images/img-1-1.png")  // the copy's path now
assert.strictEqual(ImageService.items[1].path, "")                                        // empty frame stays empty
assert.strictEqual(ImageService.committed, true)
assert.ok(ImageService.saved >= 1)
assert.deepStrictEqual(forgot, ["/d/img-9-9.png"])                                        // the old picture's file goes
// a picture that could not be put back: its frame is left out, the rest are worn
ImageService.wearFrames(part.items, {})
assert.deepStrictEqual(ImageService.items.map(r => r.id), ["b"])
// nothing worn before the saved frames have been read
ImageService.loaded = false; ImageService.items = [A]
ImageService.wearFrames(part.items, {})
assert.deepStrictEqual(ImageService.items, [A])
ImageService.loaded = true

// ---- the tick
// refreshLive() without capture(): the service's own digestsOf()
const liveDigests = now => root.digestsOf(now)
// The service walks `all` (the list plus the desktop widget plugins); no plugins here.
PresetWidgets.all = PresetWidgets.list
const now = () => ({ theme: { g: "x" }, widgets: PP.capture(PresetWidgets.list) })
ImageService.items = [A, B]
root.liveDigests = liveDigests(now())
const saved = JSON.parse(JSON.stringify(now()))
assert.strictEqual(root.isCurrent(saved), true)                            // just saved = current
ImageService.items = [A, Object.assign({}, B, { w: 400 })]                 // resized an image frame
root.liveDigests = liveDigests(now())
assert.strictEqual(root.isCurrent(saved), false)                           // tick goes
ImageService.items = [A, B]; root.liveDigests = liveDigests(now())
assert.strictEqual(root.isCurrent(saved), true)
TodoService.size = "full"; root.liveDigests = liveDigests(now())
assert.strictEqual(root.isCurrent(saved), false)                           // to-do size is part of the look
TodoService.size = "2x2"; root.liveDigests = liveDigests(now())
// a preset from before frames were part of one: on / off for pictures, no items
const noFrames = JSON.parse(JSON.stringify(saved)); noFrames.widgets.images = { shown: true }
assert.strictEqual(root.isCurrent(noFrames), true)
ImageService.items = [A]; root.liveDigests = liveDigests(now())
assert.strictEqual(root.isCurrent(noFrames), true)                         // your frames never mattered to it
// a preset from before the to-do's size: the size never mattered to it
const noSize = JSON.parse(JSON.stringify(saved)); delete noSize.widgets.todo.size
TodoService.size = "full"; ImageService.items = [A, B]; root.liveDigests = liveDigests(now())
assert.strictEqual(root.isCurrent(noSize), true)

// ---- the phone's style and settings
const phoneKeys = () => Object.fromEntries(Object.entries(settings).filter(([k]) => !k.startsWith("overview.") && k !== "lock.style"))
assert.deepStrictEqual(root.phonePart(), { flat: false, hotEdge: true, hotDwell: 140, hotPeek: false, typeToSearch: true })
root.wearPhone({ flat: true, hotEdge: false, hotDwell: 5000, hotPeek: true, typeToSearch: false })
assert.deepStrictEqual(phoneKeys(), { "quick.flat": true, "panel.hotEdge": false, "panel.hotDwell": 800, "panel.hotPeek": true, "panel.typeToSearch": false })  // delay clamped to 40..800
root.wearPhone(undefined); root.wearPhone({ flat: "yes", hotDwell: "9", hotPeek: 1 })      // a preset without the part, or junk, changes nothing
assert.deepStrictEqual(phoneKeys(), { "quick.flat": true, "panel.hotEdge": false, "panel.hotDwell": 800, "panel.hotPeek": true, "panel.typeToSearch": false })
root.wearPhone({ hotDwell: 10 }); assert.strictEqual(settings["panel.hotDwell"], 40)
const nowP = () => Object.assign(now(), { phone: root.phonePart() })
root.liveDigests = liveDigests(nowP())
const savedP = JSON.parse(JSON.stringify(nowP()))
assert.strictEqual(root.isCurrent(savedP), true)
settings["quick.flat"] = false; root.liveDigests = liveDigests(nowP())
assert.strictEqual(root.isCurrent(savedP), false)                          // 2.5D <-> 2D is part of the look: tick goes
const beforePhone = JSON.parse(JSON.stringify(savedP)); delete beforePhone.phone
assert.strictEqual(root.isCurrent(beforePhone), true)                      // a preset from before it: the phone never mattered to it

// ---- the lockscreen's style
assert.deepStrictEqual(root.lockPart(), { style: "gacha" })
root.wearLock({ style: "calendar" }); assert.strictEqual(settings["lock.style"], "calendar")
root.wearLock(undefined); root.wearLock({ style: "neon" }); root.wearLock({ style: 3 })       // no part, or junk: nothing changes
assert.strictEqual(settings["lock.style"], "calendar")
const nowL = () => Object.assign(now(), { lock: root.lockPart() })
root.liveDigests = liveDigests(nowL())
const savedL = JSON.parse(JSON.stringify(nowL()))
assert.strictEqual(root.isCurrent(savedL), true)
settings["lock.style"] = "gacha"; root.liveDigests = liveDigests(nowL())
assert.strictEqual(root.isCurrent(savedL), false)                          // the lockscreen style is part of the look: tick goes
const beforeLock = JSON.parse(JSON.stringify(savedL)); delete beforeLock.lock
assert.strictEqual(root.isCurrent(beforeLock), true)                       // a preset from before it: the lockscreen never mattered to it

// ---- the Overview's style and options
const ov0 = { style: "board", position: "center", workspaces: 5, layout: "", scale: 0, gap: -1 }
assert.deepStrictEqual(root.overviewPart(), ov0)
root.wearOverview({ style: "scroll", position: "left", workspaces: 8, layout: "horizontal", scale: 0.456, gap: 40.4 })
assert.deepStrictEqual(root.overviewPart(), { style: "scroll", position: "left", workspaces: 8, layout: "horizontal", scale: 0.46, gap: 40 })
assert.strictEqual(applied, 1)                                              // the plugin gets its options at once
root.wearOverview({ workspaces: 99, scale: 5, gap: 9999 })
assert.deepStrictEqual([settings["overview.workspaces"], settings["overview.scale"], settings["overview.gap"]], [10, 0.9, 300])   // clamped
root.wearOverview({ workspaces: 0, scale: 0.01 })
assert.deepStrictEqual([settings["overview.workspaces"], settings["overview.scale"]], [1, 0.1])
root.wearOverview({ layout: "", scale: 0, gap: -5 })                         // "not set here" is worn as that
assert.deepStrictEqual([settings["overview.layout"], settings["overview.scale"], settings["overview.gap"]], ["", 0, -1])
const keep = Object.assign({}, settings)
root.wearOverview({ style: "grid", position: "up", layout: "diagonal", workspaces: "3", scale: "x" })   // junk: nothing changes
assert.deepStrictEqual(settings, keep)
root.wearOverview(undefined)                                                // a preset without the part
assert.deepStrictEqual(settings, keep)
settings["overview.style"] = "board"
const nowO = () => Object.assign(nowP(), { overview: root.overviewPart() })
root.liveDigests = liveDigests(nowO())
const savedO = JSON.parse(JSON.stringify(nowO()))
assert.strictEqual(root.isCurrent(savedO), true)
settings["overview.style"] = "scroll"; root.liveDigests = liveDigests(nowO())
assert.strictEqual(root.isCurrent(savedO), false)                           // another overview: tick goes
const beforeOv = JSON.parse(JSON.stringify(savedO)); delete beforeOv.overview
assert.strictEqual(root.isCurrent(beforeOv), true)                          // saved before it: the overview never mattered to it

// ---- wiring read from source
assert.ok(/phone:\s*root\.phonePart\(\)/.test(svcSrc), "capture must hold the phone part")
assert.ok(svcSrc.includes("root.wearPhone(d.phone)"), "wear must put the phone part back")
assert.ok(/overview:\s*root\.overviewPart\(\)/.test(svcSrc), "capture must hold the overview part")
assert.ok(svcSrc.includes("root.wearOverview(d.overview)"), "wear must put the overview part back")
assert.ok(svcSrc.slice(svcSrc.indexOf("readonly property var keepPrefix"), svcSrc.indexOf("// True for a Settings Panel key")).includes('"overview."'),
    "overview. must stay in keepPrefix (the overview part carries it)")
const keepBlock = svcSrc.slice(svcSrc.indexOf("readonly property var keepExact"), svcSrc.indexOf("readonly property var keepPrefix"))
for (const k of ["quick.flat", "panel.hotEdge", "panel.hotDwell", "panel.typeToSearch", "lock.style"])
    assert.ok(keepBlock.includes('"' + k + '"'), k + " must stay in keepExact (the phone part carries it)")
const regText = reg.text
assert.ok(/size:\s*TodoService\.size/.test(regText), "the to-do's entry must capture its size")
assert.ok(regText.includes("TodoService.setSize(part.size)"), "the to-do's entry must put its size back")
assert.ok(regText.includes("ctx.wearFrames(part.items)") && /wearFrames:\s*items\s*=>\s*root\.wearFrames\(name, items\)/.test(svcSrc), "wear must put the frames back")
assert.ok(/\.concat\(root\.framePaths\(data\)\)/.test(svcSrc), "save must hand the frame pictures to the script")
assert.ok(/checker\.running \|\| imager\.running \|\| framer\.running/.test(svcSrc), "apply must wait for the frame copy")
const sh = fs.readFileSync(path.join(base, "scripts", "state", "preset-state.sh"), "utf8")
for (const needle of ["restore-frames)", "keep_frames", "$2.frames", "$3.frames"])
    assert.ok(sh.includes(needle), "preset-state.sh: missing " + needle)
console.log("frames_unit: all checks passed")
