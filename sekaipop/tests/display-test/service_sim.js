// node tests/display-test/service_sim.js   (run from the sekaipop folder)
// Runs the real function bodies of services/DisplayService.qml against a mock `root`
// (no Qt), with hyprctl's JSON for a laptop panel that is off and an HDMI screen on.
const fs = require("fs")
const locate = require("../lib/locate.js")
const dmSrc = fs.readFileSync(locate("modules/common/functions/DisplayMath.js"), "utf8").replace(".pragma library", "")
const DM = new Function(dmSrc + "; return { SCALES, parseModes, matchMode, modeById, logicalSize, placeOf, positions, spec, resolutions, currentRes, rates, modeForRes, overlaps, snap, separate, dock, reflow, normalize, touches, unlinked, view, parseKnown, mergeKnown, mismatched }")()
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
    get enabledCount() { return this.draft.filter(d => d.on).length } }
const runner = { exec: c => calls.push(c) }
const countdown = { restart() {}, stop() {} }
const readAgain = { restart() {} }
root.script = "displays.sh"
const names = ["mergeLive", "checkApplied", "resetDraft", "item", "edit", "sizeOf", "rects", "settle", "resized", "setOn", "setMain", "setResolution", "setMode", "setScale", "setPosition", "setPlace", "unlinkedNames", "draftSpecs", "liveSpecs", "apply", "keep", "revert", "discard"]
const body = names.map(grab).join("\n")
// the methods are written as "name(args) {...}", so an object literal takes them as they are
const methods = new Function("root", "DM", "runner", "countdown", "readAgain",
    "return {\n" + names.map(n => grab(n)).join(",\n") + "\n}")(root, DM, runner, countdown, readAgain)
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

// ---- a screen Hyprland does not list (switched off in monitors.lua, then restarted) ----
calls.length = 0
root.checking = false; root.tries = 0; root.problem = ""; root.confirming = false; root.dirty = false
root.known = DM.parseKnown("eDP-1|1920x1080\nHDMI-A-1|1920x1080")
root.hyprLive = [{ name: "eDP-1", desc: "Laptop", on: true, w: 1920, h: 1080, hz: 60, x: 0, y: 0, scale: 1, transform: 0, modes: modesLaptop }]
root.mergeLive()
eq(root.names, ["eDP-1", "HDMI-A-1"], "the unlisted screen still gets a card")
eq(root.item("HDMI-A-1").on, false, "and it is off")
eq(root.sizeOf(root.item("HDMI-A-1")), { w: 1920, h: 1080 }, "drawn at the panel size")
eq(root.item("HDMI-A-1").modeId, "preferred", "turned on with the screen's preferred mode")
root.setOn("HDMI-A-1", true)
eq(root.draftSpecs()[1], "HDMI-A-1|on|preferred|1920|0|1.00", "switching it on")
// Apply did not take: try again twice, then say so
root.checking = true; root.tries = 0
root.mergeLive()
eq(calls.length, 1, "one more try")
eq(calls[0].slice(0, 3), ["sh", "displays.sh", "force"], "with force")
eq(calls[0][3], "HDMI-A-1|on|preferred|1920|0|1.00", "for the screen that did not change")
root.mergeLive(); root.mergeLive()
eq(calls.length, 2, "two tries at most")
eq(root.problem.indexOf("HDMI-A-1") >= 0, true, "then it says which screen")
eq(root.checking, false, "and stops looking")
// Hyprland did it
root.hyprLive = root.hyprLive.concat([{ name: "HDMI-A-1", desc: "", on: true, w: 1920, h: 1080, hz: 60, x: 1920, y: 0, scale: 1, transform: 0, modes: modesHdmi }])
root.checking = true; root.tries = 0; root.problem = ""; calls.length = 0
root.mergeLive()
eq(calls.length, 0, "nothing to retry when it took")
eq(root.checking, false, "done checking")

console.log(fails === 0 ? "service simulation: all passed" : fails + " failed")
process.exit(fails ? 1 : 0)
