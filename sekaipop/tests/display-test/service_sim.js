// node tests/display-test/service_sim.js   (run from the sekaipop folder)
// Runs the real function bodies of services/DisplayService.qml against a mock `root`
// (no Qt), with hyprctl's JSON for a laptop panel that is off and an HDMI screen on.
const fs = require("fs")
const locate = require("../lib/locate.js")
const dmSrc = fs.readFileSync(locate("modules/common/functions/DisplayMath.js"), "utf8").replace(".pragma library", "")
const DM = new Function(dmSrc + "; return { SCALES, parseModes, matchMode, modeById, logicalSize, placeOf, positions, spec, resolutions, currentRes, rates, modeForRes, overlaps, snap, separate, dock, reflow, normalize, touches, unlinked, view }")()
const hmSrc = fs.readFileSync(locate("modules/common/functions/HyprmonMath.js"), "utf8").replace(".pragma library", "")
const HM = new Function(hmSrc + "; return { hardwareId, hardwareIds, resolve, matchProfile, setKey, chooseProfile, bitDepthOf, COLOR_MODES, isHdr, extras, mirrorLoops, toProfileMonitor, mergeMonitors, findMonitor, summary, validName }")()
const qml = fs.readFileSync(locate("services/DisplayService.qml"), "utf8")

function grab(name) {
    const i = qml.indexOf("    function " + name + "(")
    if (i < 0) throw new Error("no function " + name)
    let depth = 0, j = qml.indexOf("{", i)
    const start = j
    for (; j < qml.length; j++) {
        if (qml[j] === "{") depth++
        else if (qml[j] === "}" && --depth === 0) break
    }
    const head = qml.slice(i, start).replace("function ", "").trim()
    return head + " " + qml.slice(start, j + 1)
}

const calls = []
const root = { live: [], draft: [], mainName: "", names: [], dirty: false, confirming: false, previous: [], secondsLeft: 0, confirmSeconds: 15,
    hyprmon: false, saveTarget: "",
    get enabledCount() { return this.draft.filter(d => d.on).length } }
const runner = { exec: c => calls.push(c) }
const countdown = { restart() {}, stop() {} }
const readAgain = { restart() {} }
root.script = "displays.sh"
// HyprmonService as the card sees it: one profile, and what was saved into it
const saved = []
const HyprmonService = { active: "Desk", profile: n => n === "Desk" ? { name: "Desk", monitors: [{ name: "HDMI-A-1", hardware_id: "Acme/Mon/7", Active: true, VRR: 2, alias: "Big one" }] } : null,
    saveProfile: (n, m) => { saved.push([n, m]); return true } }
const names = ["resetDraft", "item", "edit", "sizeOf", "rects", "settle", "resized", "setOn", "setMain", "setResolution", "setMode", "setScale", "setPosition", "setPlace", "unlinkedNames", "draftSpecs", "liveSpecs", "apply", "keep", "revert", "discard",
    "setTransform", "setVrr", "setBitDepth", "setColorMode", "setSdr", "setMirror", "mirrorSources", "hyprmonMonitors"]
const body = names.map(grab).join("\n")
// the methods are written as "name(args) {...}", so an object literal takes them as they are
const methods = new Function("root", "DM", "HM", "HyprmonService", "runner", "countdown", "readAgain",
    "return {\n" + names.map(n => grab(n)).join(",\n") + "\n}")(root, DM, HM, HyprmonService, runner, countdown, readAgain)
Object.assign(root, methods)

let fails = 0
function eq(a, b, msg) {
    const x = JSON.stringify(a), y = JSON.stringify(b)
    if (x !== y) { fails++; console.log("FAIL " + msg + "\n   got  " + x + "\n   want " + y) }
}

const modesHdmi = DM.parseModes(["1920x1080@144.00Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"])
const modesLaptop = DM.parseModes(["1920x1080@60.00Hz", "1366x768@60.00Hz"])
root.live = [
    { name: "eDP-1", desc: "Laptop", on: false, w: 0, h: 0, hz: 0, x: 0, y: 0, scale: 1, transform: 0, modes: modesLaptop },
    { name: "HDMI-A-1", desc: "Monitor", on: true, w: 1920, h: 1080, hz: 143.981, x: 0, y: 0, scale: 1, transform: 0, modes: modesHdmi }
]
root.resetDraft()
eq(root.mainName, "HDMI-A-1", "the screen at the origin is main")
eq(root.names, ["eDP-1", "HDMI-A-1"], "names")
eq(root.draft[1].modeId, "1920x1080@144.00", "current mode matched")
eq(root.draft[0].modeId, "1920x1080@60.00", "an off screen defaults to its first mode")
eq(root.draft[0].place, "right", "an off screen is placed on the right by default")
eq(root.draftSpecs(), ["eDP-1|off|1920|0", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00"], "untouched draft = what it is now, the off screen parked past the right edge")
eq(root.liveSpecs(), ["eDP-1|off", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00"], "live specs")

// never turn the last screen off
root.setOn("HDMI-A-1", false)
eq(root.item("HDMI-A-1").on, true, "last screen stays on")
eq(root.dirty, false, "and nothing is dirty")

// turn the laptop panel on, 125 %, left of the monitor
root.setOn("eDP-1", true)
root.setScale("eDP-1", "1.25")
root.setPlace("eDP-1", "left")
eq(root.dirty, true, "dirty")
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|0|0|1.25", "HDMI-A-1|on|1920x1080@144.00|1536|0|1.00"], "laptop left of the monitor, shifted to 0")

// resolution keeps the refresh rate as near as it can
root.setResolution("HDMI-A-1", "1280x720")
eq(root.item("HDMI-A-1").modeId, "1280x720@60.00", "resolution change")
root.setResolution("HDMI-A-1", "1920x1080")
eq(root.item("HDMI-A-1").modeId, "1920x1080@60.00", "back to 1080p picks the nearest rate to the current one (60)")
root.setMode("HDMI-A-1", "1920x1080@144.00")

// main moves, and the placement follows
root.setMain("eDP-1")
root.setPlace("HDMI-A-1", "right")
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|0|0|1.25", "HDMI-A-1|on|1920x1080@144.00|1536|0|1.00"], "laptop main, monitor on its right")

// turning the main screen off hands main to another one
root.setOn("eDP-1", false)
eq(root.mainName, "HDMI-A-1", "main moves to a screen that is on")

// apply -> confirm -> keep / revert
root.setOn("eDP-1", true)
root.apply()
eq(calls.length, 1, "apply ran once")
eq(calls[0][2], "apply", "apply command")
eq(calls[0].slice(3), root.draftSpecs(), "with the draft")
eq(root.previous, ["eDP-1|off", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00"], "the way back is what it was")
eq(root.confirming, true, "waiting for an answer")
root.keep()
eq(calls[1][2], "save", "keep saves")
eq(root.confirming, false, "no longer waiting")
root.setScale("HDMI-A-1", "2")
root.apply()
root.revert()
eq(calls[calls.length - 1].slice(2), ["apply"].concat(root.previous), "revert re-applies the old screens")

// discard
root.confirming = false
root.dirty = false
root.setScale("HDMI-A-1", "1.5")
root.discard()
eq(root.item("HDMI-A-1").scale, 1, "discard puts the live values back")
eq(root.dirty, false, "clean again")

// ===== free placement =====
// Fresh state: monitor (1920x1080, main) and the laptop panel on at 1.25 (1536x864), docked right.
root.confirming = false
root.dirty = false
root.live = [
    { name: "eDP-1", desc: "Laptop", on: true, w: 1920, h: 1080, hz: 60, x: 1920, y: 0, scale: 1.25, transform: 0, modes: modesLaptop },
    { name: "HDMI-A-1", desc: "Monitor", on: true, w: 1920, h: 1080, hz: 143.981, x: 0, y: 0, scale: 1, transform: 0, modes: modesHdmi }
]
root.resetDraft()
eq(root.item("eDP-1").place, "right", "read as on the right")
eq([root.item("eDP-1").x, root.item("eDP-1").y], [1920, 0], "its position is read")

// drag the laptop panel under the monitor, a little to the right (the card sends the snapped spot)
root.setPosition("eDP-1", 300, 1080)
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|300|1080|1.25", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00"], "dragged below, exact spot kept")
eq(root.item("eDP-1").place, "below", "and read as below")
eq(root.dirty, true, "dragging makes it dirty")

// dropped on top of the monitor: slid out the short way
root.setPosition("eDP-1", 1000, 900)
const lap = root.item("eDP-1"), mon = root.item("HDMI-A-1")
const lr = { x: lap.x, y: lap.y, w: 1536, h: 864 }, mr = { x: mon.x, y: mon.y, w: 1920, h: 1080 }
eq(DM.overlaps(lr, mr), false, "never left on top of the other screen")

// left of the monitor and higher: the layout is shifted so it starts at 0,0
root.setPosition("eDP-1", -1536, -200)
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|0|0|1.25", "HDMI-A-1|on|1920x1080@144.00|1536|200|1.00"], "negative positions shifted to 0")
eq(root.item("eDP-1").place, "left", "read as left")

// the Placed keys still work, from wherever it is
root.setPlace("eDP-1", "above")
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|0|0|1.25", "HDMI-A-1|on|1920x1080@144.00|0|864|1.00"], "above the monitor");
root.setPlace("eDP-1", "right")
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|1920|0|1.25", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00"], "right of the monitor")

// a neighbour grows: what was past it moves by the difference
root.setScale("HDMI-A-1", "1")
root.setResolution("HDMI-A-1", "1280x720")
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|1280|0|1.25", "HDMI-A-1|on|1280x720@60.00|0|0|1.00"], "monitor got smaller: the laptop panel follows its edge")
root.setResolution("HDMI-A-1", "1920x1080")
eq(root.draftSpecs()[0], "eDP-1|on|1920x1080@60.00|1920|0|1.25", "and follows it back out")
root.setScale("eDP-1", "2")
eq(root.draftSpecs()[0], "eDP-1|on|1920x1080@60.00|1920|0|2.00", "its own scale does not move it")

// not reachable by the pointer
root.setPosition("eDP-1", 5000, 0)
eq(root.unlinkedNames(), ["eDP-1"], "a gap between the screens is reported")
root.setPosition("eDP-1", 1920, 300)
eq(root.unlinkedNames(), [], "next to the monitor again: one piece")

// a screen that was off joins on the right of the others, level with the top
root.live = [
    { name: "eDP-1", desc: "Laptop", on: false, w: 0, h: 0, hz: 0, x: 0, y: 0, scale: 1, transform: 0, modes: modesLaptop },
    { name: "HDMI-A-1", desc: "Monitor", on: true, w: 1920, h: 1080, hz: 143.981, x: 0, y: 0, scale: 1, transform: 0, modes: modesHdmi }
]
root.dirty = false
root.resetDraft()
root.setOn("eDP-1", true)
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|1920|0|1.00", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00"], "turned on: right of the monitor")

// fractional logical sizes round up, so a neighbour never sits on top (1920 / 1.75 = 1097.14)
root.live = [
    { name: "A", desc: "", on: true, w: 1920, h: 1080, hz: 60, x: 0, y: 0, scale: 1.75, transform: 0, modes: modesHdmi },
    { name: "B", desc: "", on: true, w: 1920, h: 1080, hz: 60, x: 1098, y: 0, scale: 1, transform: 0, modes: modesHdmi }
]
root.dirty = false
root.resetDraft()
eq(root.sizeOf(root.item("A")), { w: 1098, h: 618 }, "175 % rounds up")
root.setPlace("B", "below")
root.setPlace("B", "right")
eq(root.draftSpecs()[1].split("|").slice(3, 5), ["1098", "0"], "flush right of a fractional screen lands past its edge")

// ===== hyprmon as the handler =====
const extra = { make: "", model: "", serial: "", bitDepth: 8, cm: "srgb", sdrBrightness: 1, sdrSaturation: 1, vrr: 0, mirror: "" }
root.hyprmon = true
root.live = [
    Object.assign({ name: "eDP-1", desc: "Laptop", on: true, w: 1920, h: 1080, hz: 60, x: 1920, y: 0, scale: 1, transform: 0, modes: modesLaptop }, extra, { make: "LG", model: "Panel" }),
    Object.assign({ name: "HDMI-A-1", desc: "Monitor", on: true, w: 1920, h: 1080, hz: 143.981, x: 0, y: 0, scale: 1, transform: 0, modes: modesHdmi }, extra,
                  { make: "Acme", model: "Mon", serial: "7", vrr: 1, cm: "hdr", sdrBrightness: 1.2, bitDepth: 10 })
]
root.dirty = false; root.confirming = false
root.resetDraft()
eq(root.item("HDMI-A-1").vrr, 2, "VRR read as on, the profile in use says fullscreen only")
eq(root.item("HDMI-A-1").cm, "hdr", "colour mode carried into the draft")
eq(root.draftSpecs(), ["eDP-1|on|1920x1080@60.00|1920|0|1.00|", "HDMI-A-1|on|1920x1080@144.00|0|0|1.00|vrr=2,bitdepth=10,cm=hdr,sdrbrightness=1.20"],
   "hyprmon specs carry the extras")
eq(root.liveSpecs()[1], "HDMI-A-1|on|1920x1080@144.00|0|0|1.00|vrr=1,bitdepth=10,cm=hdr,sdrbrightness=1.20", "live specs too (to go back to)")

root.setTransform("eDP-1", 1)
eq(root.draftSpecs()[0], "eDP-1|on|1920x1080@60.00|1920|0|1.00|transform=1", "rotated")
eq(root.sizeOf(root.item("eDP-1")), { w: 1080, h: 1920 }, "a rotated screen takes the room on its side")
root.setTransform("eDP-1", 9)
eq(root.item("eDP-1").transform, 1, "transform past 7 refused")
root.setVrr("eDP-1", 3); root.setBitDepth("eDP-1", 12); root.setColorMode("eDP-1", "neon")
eq([root.item("eDP-1").vrr, root.item("eDP-1").bitDepth, root.item("eDP-1").cm], [0, 8, "srgb"], "bad values refused")
root.setSdr("HDMI-A-1", "saturation", 0.9)
eq(root.item("HDMI-A-1").sdrSaturation, 0.9, "SDR saturation")

// mirroring
eq(root.mirrorSources("eDP-1"), ["HDMI-A-1"], "what the laptop may mirror")
eq(root.setMirror("eDP-1", "HDMI-A-1"), true, "laptop mirrors the monitor")
eq(root.rects().map(r => r.name), ["HDMI-A-1"], "a mirror takes no room in the layout")
eq(root.draftSpecs()[0].split("|").slice(-1)[0], "mirror=HDMI-A-1", "a mirror says only that")
eq(root.setMirror("HDMI-A-1", "eDP-1"), false, "a circle is refused")
eq(root.mirrorSources("HDMI-A-1"), [], "and not offered")
eq(root.setMirror("eDP-1", ""), true, "own picture again")
eq(root.rects().map(r => r.name).sort(), ["HDMI-A-1", "eDP-1"], "back in the layout")
root.setMirror("eDP-1", "HDMI-A-1")
root.setOn("HDMI-A-1", false)
eq([root.item("HDMI-A-1").on, root.item("eDP-1").mirror, root.rects().map(r => r.name)], [false, "", ["eDP-1"]],
   "the mirrored screen goes off: its mirror shows its own picture again, so a screen stays on")

// keep -> saved into the profile picked, in hyprmon's shape
root.resetDraft(); root.dirty = false
root.setScale("HDMI-A-1", "1.25")
calls.length = 0
root.apply()
eq(HyprmonService.held, true, "no auto-switch while the countdown runs")
root.saveTarget = "Desk"
root.keep()
eq(HyprmonService.held, false, "released by Keep")
eq(calls.filter(c => c[2] === "save").length, 0, "monitors.lua is not written with hyprmon")
eq(saved.length, 1, "saved once")
eq(saved[0][0], "Desk", "into the profile picked")
const mHdmi = saved[0][1].find(m => m.name === "HDMI-A-1")
eq([mHdmi.hardware_id, mHdmi.alias, mHdmi.Scale, mHdmi.VRR, mHdmi.ColorMode, mHdmi.BitDepth, mHdmi.X, mHdmi.Y],
   ["Acme/Mon/7", "Big one", 1.25, 2, "hdr", 10, 0, 0], "monitor saved with its id, alias kept, settings")
eq(saved[0][1].find(m => m.name === "eDP-1").hardware_id, "LG/Panel", "the laptop by its id")
// no profile picked: the screens stay, nothing saved
root.setScale("HDMI-A-1", "1")
root.apply(); root.saveTarget = ""; root.keep()
root.setScale("HDMI-A-1", "1.25"); root.apply(); root.revert()
eq(HyprmonService.held, false, "released by Go back")
eq(saved.length, 1, "nothing saved without a profile")
root.hyprmon = false

console.log(fails === 0 ? "service simulation: all passed" : fails + " failed")
process.exit(fails ? 1 : 0)
