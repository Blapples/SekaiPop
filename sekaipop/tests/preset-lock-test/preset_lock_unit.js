// node tests/preset-lock-test/preset_lock_unit.js   (run from the sekaipop folder)
// The Custom lockscreen's layout is part of a desktop preset, and a preset never shows a
// lockscreen widget that did not exist when it was saved:
//   - LockCanvasModel.presetPart / wornModel / keepKinds / legacyKinds   (the real file)
//   - LockCanvasService.wearPreset, DesktopPresetService.canvasDigestOf / isCurrent
//     (cut out of the .qml text and run against fakes, as preset_frames does)
//   - the wiring, read from source
const assert = require("assert"), fs = require("fs")
const locate = require("../lib/locate.js")
const read = p => fs.readFileSync(locate(p), "utf8")
let n = 0
const ok = (c, m) => { assert.ok(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

const mSrc = read("modules/common/functions/LockCanvasModel.js").replace(/^\.pragma library/m, "")
const names = ["kinds", "known", "cleanBoard", "defaultBoard", "defaultModel", "withBoard", "addItem", "removeItem",
    "presetPart", "wornModel", "keepKinds", "legacyKinds", "stringify", "parse", "boardFor", "SHARED"]
const LM = new Function(mSrc + ";return {" + names.map(x => x + ":" + x).join(",") + "}")()

const svc = read("services/LockCanvasService.qml")
const pre = read("services/DesktopPresetService.qml")
function grab(src, name) {
    const start = src.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    const end = src.indexOf("\n    }\n", start)
    return src.slice(start, end + 7).replace(/^    function /, "function ")
}

const NEWER = ["greeting", "sun", "timer", "notifications", "event", "todo", "countdown"]
const kindsOf = model => Object.values(model.boards).flatMap(b => b.items.map(i => i.kind))

// ---- the fixed list of what existed before presets held a layout
const legacy = LM.legacyKinds()
for (const k of legacy) ok(LM.known(k), "legacy " + k + " is still a widget")
for (const k of NEWER) {
    ok(LM.known(k), k + " is a widget")
    ok(legacy.indexOf(k) < 0, k + " is newer than presets: not in the legacy list")
}
legacy.push("zzz")
ok(LM.legacyKinds().indexOf("zzz") < 0, "legacyKinds() is a copy")

// a board with every widget, a monitor board, and a core position
let full = LM.cleanBoard({ core: { x: 0.4, y: 0.8 }, items: [] })
for (const k of LM.kinds()) full = LM.addItem(full, k, 0.3, 0.3).board
let mon = LM.addItem(LM.cleanBoard({ items: [] }), "timer", 0.1, 0.1).board
mon = LM.addItem(mon, "clock", 0.6, 0.6).board
const model = LM.withBoard(LM.withBoard(LM.defaultModel(), "*", full), "DP-1", mon)
ok(kindsOf(model).indexOf("timer") >= 0 && kindsOf(model).indexOf("todo") >= 0, "the test layout has the newer widgets")

// ---- presetPart: every board and the list of widgets, clean, JSON-safe
const part = LM.presetPart(model)
eq(Object.keys(part.boards).sort(), ["*", "DP-1"], "every board is held")
eq(part.kinds, LM.kinds().slice().sort(), "the list is every widget this build has, sorted")
eq(JSON.parse(JSON.stringify(part)), part, "it is plain data")
eq(LM.presetPart(null).boards["*"], LM.defaultBoard(), "no model: the first layout is held")
const junkKey = LM.presetPart({ boards: { "*": full, "bad key!": mon, "DP-2": mon } })
eq(Object.keys(junkKey.boards).sort(), ["*", "DP-2"], "a key that is not a monitor name is not held")

// ---- wornModel: a preset with a layout gives exactly that layout
const worn = LM.wornModel(JSON.parse(JSON.stringify(part)))
eq(worn.boards, model.boards, "held then worn: the same boards, core and monitor board included")
eq(worn.v, 1, "a model with a version")
ok(LM.wornModel({ boards: {} }) === null && LM.wornModel(null) === null && LM.wornModel("x") === null
    && LM.wornModel({}) === null && LM.wornModel({ boards: { "DP-1": full } }) === null,
    "no shared board / no layout: null, wearing changes nothing")

// a widget that is not in the preset's list is not shown, even when a board has it
const early = JSON.parse(JSON.stringify(part))
early.kinds = LM.legacyKinds()
const wornEarly = LM.wornModel(early)
ok(kindsOf(wornEarly).every(k => LM.legacyKinds().indexOf(k) >= 0), "a widget the preset did not know is left out")
ok(kindsOf(wornEarly).indexOf("clock") >= 0, "the ones it knew stay")
eq(wornEarly.boards["*"].core, { x: 0.4, y: 0.8 }, "the password block position stays")
eq(wornEarly.boards["DP-1"].items.map(i => i.kind), ["clock"], "the monitor board is trimmed too")
const noKinds = JSON.parse(JSON.stringify(part)); delete noKinds.kinds
eq(LM.wornModel(noKinds).boards, model.boards, "a part that lists no widgets keeps what its boards hold")

// hand-edited junk is cleaned like a saved file
const evil = LM.wornModel({ boards: { "*": { core: { x: 9, y: -4 }, items: [{ kind: "rm -rf", x: 1 }, { kind: "clock", x: 7, scale: 99 }] } }, kinds: ["clock", "rm -rf"] })
eq(evil.boards["*"].items.length, 1, "unknown widgets are dropped")
ok(evil.boards["*"].items[0].x === 1 && evil.boards["*"].items[0].scale === 2.5, "numbers are clamped")
ok(evil.boards["*"].core.x <= 0.72 && evil.boards["*"].core.y >= 0.5, "the password block stays in its range")

// ---- keepKinds
const only = LM.keepKinds(model, ["clock"])
eq(kindsOf(only).filter(k => k !== "clock"), [], "only the named widgets stay")
ok(only.boards["*"].core.x === 0.4, "the core is untouched")
eq(Object.keys(LM.keepKinds(null, ["clock"]).boards), ["*"], "no model: the first layout, trimmed")
eq(kindsOf(LM.keepKinds(model, undefined)), [], "no list: nothing stays")
eq(model.boards["*"].items.length, full.items.length, "the model it was given is not changed")

// ---- LockCanvasService.wearPreset (the real function, fake service)
function service(loaded, m) {
    const root = { loaded, model: m, persisted: 0, replaced: 0, persist() { this.persisted++ }, replacedSignal() { this.replaced++ } }
    const src = grab(svc, "wearPreset").replace("root.replaced()", "root.replacedSignal()")
    root.wearPreset = eval("(" + src + ")")
    return root
}
// a preset saved before layouts were part of one: no part
let s = service(true, model)
s.wearPreset(undefined)
ok(kindsOf(s.model).every(k => LM.legacyKinds().indexOf(k) >= 0), "an old preset: the newer widgets are not shown")
ok(kindsOf(s.model).indexOf("clock") >= 0 && s.model.boards["*"].core.x === 0.4, "...the rest of the layout is left as it was")
ok(s.persisted === 1 && s.replaced === 1, "...saved, and the editor told")
s.wearPreset({})   // a part that is there but holds no layout
ok(kindsOf(s.model).every(k => LM.legacyKinds().indexOf(k) >= 0), "a part without a layout counts as none")
// a preset with its own layout
s = service(true, LM.defaultModel())
s.wearPreset(JSON.parse(JSON.stringify(part)))
eq(s.model.boards, model.boards, "a preset with a layout puts exactly it on (the newer widgets it holds included)")
// ...and another preset gives another one: each has its own
const partB = LM.presetPart(LM.withBoard(LM.defaultModel(), "*", LM.addItem(LM.cleanBoard({ items: [] }), "text", 0.5, 0.5).board))
s.wearPreset(JSON.parse(JSON.stringify(partB)))
eq(kindsOf(s.model), ["text"], "preset B: its own layout")
ok(!("DP-1" in s.model.boards), "...and the monitor board of the one before is gone")
s.wearPreset(JSON.parse(JSON.stringify(part)))
eq(s.model.boards, model.boards, "back to preset A: its layout is back")
// a preset saved by an older build that listed fewer widgets
s.wearPreset(early)
ok(kindsOf(s.model).every(k => LM.legacyKinds().indexOf(k) >= 0), "a preset that did not list a widget does not show it")
// nothing before the saved layout is read
s = service(false, LM.defaultModel())
s.wearPreset(JSON.parse(JSON.stringify(part)))
ok(s.persisted === 0 && s.replaced === 0 && s.model === s.model && kindsOf(s.model).length === 6, "not read yet: nothing changes, nothing is saved")

// ---- the tick (DesktopPresetService)
const R = { liveCanvasDigest: "" }
for (const f of ["stable", "canvasDigestOf", "variantKey", "isCurrent"])
    R[f] = eval("(" + grab(pre, f).replace(/root\./g, "R.") + ")")
const wornFn = new Function("LM", "R", "return " + grab(pre, "canvasDigestOf").replace(/root\./g, "R."))
R.canvasDigestOf = (d) => wornFn(LM, R)(d)
R.digestOf = () => "same"      // everything else already agrees: only the layout is asked
R.liveDigests = { [R.variantKey(false, false, false, false, false, false)]: "same",
    [R.variantKey(true, true, true, true, true, true)]: "same" }
const dataFull = { images: {}, dock: {}, widgets: { images: { items: [] } }, phone: {}, overview: {}, lock: {}, lockCanvas: JSON.parse(JSON.stringify(part)) }
R.liveCanvasDigest = R.canvasDigestOf({ lockCanvas: part })
ok(R.liveCanvasDigest !== "", "the live layout has a digest")
ok(R.isCurrent(dataFull) === true, "just saved: it is the one worn")
const changed = JSON.parse(JSON.stringify(dataFull))
changed.lockCanvas.boards["*"].items[0].x = 0.99
ok(R.isCurrent(changed) === false, "moved a widget on the lockscreen: the tick goes")
const dataOld = JSON.parse(JSON.stringify(dataFull)); delete dataOld.lockCanvas
ok(R.isCurrent(dataOld) === true, "a preset from before layouts: the layout never mattered to it")
R.liveCanvasDigest = ""
ok(R.isCurrent(dataFull) === false, "layout not read yet: no tick for a preset that holds one")
ok(R.isCurrent(dataOld) === true, "...but one that holds none is unaffected")
// a preset that does not list a widget the layout has: wearing it would leave it out, so it is not "current"
R.liveCanvasDigest = R.canvasDigestOf({ lockCanvas: part })
const dataEarly = JSON.parse(JSON.stringify(dataFull)); dataEarly.lockCanvas.kinds = LM.legacyKinds()
ok(R.isCurrent(dataEarly) === false, "the layout has widgets the preset would leave out: not the one worn")

// ---- editing the lockscreen writes into the preset you are in (DesktopPresetService.adoptLock)
function adoptEnv(inName, presets) {
    const jobs = []
    const root = { script: "/s/preset-state.sh", waiting: false, pendingData: null, presets, live: 0,
        byName: (a, b) => a.name < b.name ? -1 : 1,
        find(nm) { return this.presets.find(p => p.name === nm) || null },
        enqueue(a) { jobs.push(a) }, refreshLive() { this.live++ } }
    const NotesService = { setName: inName }
    const LockCanvasService = { loaded: true, presetPart: () => LM.presetPart(model) }
    root.adoptLock = eval("(" + grab(pre, "adoptLock").replace(/root\./g, "root.") + ")")
    return { root, jobs, NotesService, LockCanvasService }
}
function runAdopt(env) {
    const f = new Function("root", "NotesService", "LockCanvasService", "return " + grab(pre, "adoptLock"))
    return f(env.root, env.NotesService, env.LockCanvasService)()
}
const presetA = { name: "A", data: { _meta: { name: "A" }, theme: { g: 1 } } }
const presetB = { name: "B", data: { _meta: { name: "B" }, lockCanvas: LM.presetPart(LM.defaultModel()) } }
let env = adoptEnv("A", [presetA, presetB])
runAdopt(env)
eq(env.jobs.length, 1, "an edit in preset A is saved into A's file")
eq(env.jobs[0].slice(0, 5), ["sh", "/s/preset-state.sh", "rename", "A", "A"], "through the rename job with the same name (its pictures stay)")
const written = JSON.parse(env.jobs[0][5])
eq(written.lockCanvas, JSON.parse(JSON.stringify(LM.presetPart(model))), "the file now holds the layout as it is (positions, widgets on and off)")
eq(written.theme, { g: 1 }, "the rest of the preset is untouched")
eq(env.root.presets.find(p => p.name === "A").data.lockCanvas, written.lockCanvas, "the list in memory has it, so the tick stays true")
eq(env.root.presets.find(p => p.name === "B").data.lockCanvas, LM.presetPart(LM.defaultModel()), "another preset is not touched")
ok(env.root.live === 1, "the tick is looked at again")
env = adoptEnv("", [presetA]); runAdopt(env); eq(env.jobs, [], "in no preset: nothing is written")
env = adoptEnv("gone", [presetA]); runAdopt(env); eq(env.jobs, [], "the preset was deleted: nothing is written")
env = adoptEnv("A", [presetA]); env.LockCanvasService.loaded = false; runAdopt(env); eq(env.jobs, [], "layout not read yet: nothing is written")
env = adoptEnv("A", [presetA]); env.root.waiting = true; runAdopt(env); eq(env.jobs, [], "a preset is being put on: nothing is written over it")

// ---- wiring
const cut = t => t.replace(/\/\/.*$/gm, "")
const preC = cut(pre), svcC = cut(svc), editC = cut(read("services/LockEditService.qml"))
ok(/if \(LockCanvasService\.loaded\)\s*\n\s*out\.lockCanvas = LockCanvasService\.presetPart\(\)/.test(preC), "capture holds the layout, not before it is read")
ok(/root\.wearLock\(d\.lock\)\s*\n\s*LockCanvasService\.wearPreset\(d\.lockCanvas\)/.test(preC), "wearing a preset puts the layout on (an old one: the widgets newer than it come off)")
ok(/k === "lockCanvas"\)\s*\n\s*continue/.test(preC), "the live comparison leaves the layout to its own digest")
ok(/k !== "_meta" && k !== "lockCanvas"/.test(preC), "so does the preset's")
ok(/root\.liveCanvasDigest = root\.canvasDigestOf\(now\)/.test(preC), "the live layout digest is refreshed with the rest")
ok(/import "\.\.\/modules\/common\/functions\/LockCanvasModel\.js" as LM/.test(pre), "the preset service reads the model")
ok(/signal replaced/.test(svcC) && /root\.replaced\(\)/.test(svcC), "the canvas service says when a preset replaced the boards")
ok(!/LockEdit/.test(svcC), "the canvas service still does not depend on the editor")
ok(/target: LockCanvasService[\s\S]*onReplaced\(\)[\s\S]*root\.gesture = ""\s*\n\s*root\.close\(\)/.test(editC), "the editor lets go of a drag and closes when a preset replaces the layout")
ok(/signal edited/.test(svcC) && (svcC.match(/root\.edited\(\)/g) || []).length === 3, "setBoard, dropBoard and reset say the layout was edited")
ok(!/function wearPreset[\s\S]*?root\.edited\(\)[\s\S]*?\n    }\n/.test(svcC.slice(svcC.indexOf("function wearPreset"), svcC.indexOf("function wearPreset") + 600).split("\n    }\n")[0] + "\n    }\n") , "wearing a preset is not an edit (it would write the preset into itself)")
ok(/target: LockCanvasService\s*\n\s*function onEdited\(\) \{\s*\n\s*lockAdopt\.restart\(\)/.test(preC) && /onTriggered: root\.adoptLock\(\)/.test(preC), "the preset service listens, a moment after the last edit")
ok(/const name = NotesService\.setName/.test(preC), "the preset you are in is the one the sticky notes follow (kept across restarts)")
const docs = fs.readFileSync(require("path").join(__dirname, "..", "..", "..", "docs", "LOCKCANVAS.md"), "utf8")
ok(/saved into the preset you are in/.test(docs), "the docs say edits go into the preset you are in")
ok(/## Presets/.test(docs) && !/- Layouts inside presets \(a preset can wear/.test(docs), "the docs say how presets hold the layout and no longer list it as not done")

console.log("preset_lock_unit: " + n + " checks passed")
