// node tests/display-test/display_unit.js   (run from the sekaipop folder)
const fs = require("fs")
const locate = require("../lib/locate.js")
const src = fs.readFileSync(locate("modules/common/functions/DisplayMath.js"), "utf8").replace(".pragma library", "")
const D = new Function(src + "; return { SCALES, parseModes, matchMode, modeById, logicalSize, placeOf, positions, spec, resolutions, currentRes, rates, modeForRes, overlaps, snap, separate, dock, reflow, normalize, touches, unlinked, view, parseKnown, mergeKnown, mismatched }")()

let fails = 0
function eq(a, b, msg) {
    const x = JSON.stringify(a), y = JSON.stringify(b)
    if (x !== y) { fails++; console.log("FAIL " + msg + "\n   got  " + x + "\n   want " + y) }
}

// modes
const modes = D.parseModes(["1920x1080@144.00Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz", "junk"])
eq(modes.length, 3, "junk line skipped")
eq(modes[0], { w: 1920, h: 1080, hz: 144, id: "1920x1080@144.00" }, "first mode")
eq(D.matchMode(modes, 1920, 1080, 143.981), "1920x1080@144.00", "143.981 matches 144.00")
eq(D.matchMode(modes, 1920, 1080, 60.0), "1920x1080@60.00", "60 matches 60")
eq(D.matchMode(modes, 0, 0, 0), "1920x1080@144.00", "an off screen takes the first listed mode")
eq(D.matchMode([], 0, 0, 0), "preferred", "no modes -> preferred")
eq(D.matchMode([], 1366, 768, 60), "1366x768@60.00", "no list, known size")
eq(D.modeById(modes, "1280x720@60.00").h, 720, "mode by id")
eq(D.modeById([], "800x600@75.00").w, 800, "mode by id when not listed")

// sizes
eq(D.logicalSize(1920, 1080, 1.5, 0), { w: 1280, h: 720 }, "scaled")
eq(D.logicalSize(1920, 1080, 1, 1), { w: 1080, h: 1920 }, "rotated 90")
eq(D.logicalSize(1920, 1080, 0, 0), { w: 1920, h: 1080 }, "a zero scale reads as 1")

// where a screen is
eq(D.placeOf(1920, 0, 1280, 720, 1920, 1080), "right", "right")
eq(D.placeOf(-1280, 0, 1280, 720, 1920, 1080), "left", "left")
eq(D.placeOf(0, 1080, 1280, 720, 1920, 1080), "below", "below")
eq(D.placeOf(0, -720, 1280, 720, 1920, 1080), "above", "above")
eq(D.placeOf(300, 300, 1280, 720, 1920, 1080), "right", "overlap -> right")

// layout
const A = { name: "A", on: true, w: 1920, h: 1080, scale: 1, transform: 0, place: "right" }
const B = { name: "B", on: true, w: 1920, h: 1080, scale: 1.5, transform: 0, place: "right" }
const C = { name: "C", on: true, w: 1280, h: 1024, scale: 1, transform: 0, place: "left" }
const OFF = { name: "OFF", on: false, w: 0, h: 0, scale: 1, transform: 0, place: "right" }
eq(D.positions([A], "A"), { A: [0, 0] }, "one screen at the origin")
eq(D.positions([A, B], "A"), { A: [0, 0], B: [1920, 0] }, "B right of A")
eq(D.positions([A, { ...B, place: "left" }], "A"), { A: [1280, 0], B: [0, 0] }, "B left of A, shifted to 0")
eq(D.positions([A, { ...B, place: "below" }], "A"), { A: [0, 0], B: [0, 1080] }, "B below A")
eq(D.positions([A, { ...B, place: "above" }], "A"), { A: [0, 720], B: [0, 0] }, "B above A, shifted to 0")
eq(D.positions([A, B, C], "A"), { A: [1280, 0], B: [3200, 0], C: [0, 0] }, "left and right of main")
eq(D.positions([A, { ...B, name: "B2" }, B], "A").B2, [1920, 0], "first on the right")
eq(D.positions([A, { ...B, name: "B2" }, B], "A").B, [3200, 0], "second on the right goes next to it")
eq(D.positions([A, B], "B"), { B: [0, 0], A: [1280, 0] }, "B as main: A on its right")
eq(D.positions([A, OFF], "A"), { A: [0, 0] }, "off screens are not placed")
eq(D.positions([OFF], "x"), {}, "nothing on")
eq(D.positions([A, { ...B, transform: 1 }], "A").B, [1920, 0], "rotated B still starts at A's edge")

// specs
eq(D.spec("A", true, "1920x1080@144.00", 0, 0, 1), "A|on|1920x1080@144.00|0|0|1.00", "on spec")
eq(D.spec("A", false), "A|off", "off spec")

// choices
eq(D.resolutions(modes, "1920x1080@144.00", 10), [{ id: "1920x1080", label: "1920x1080" }, { id: "1280x720", label: "1280x720" }], "resolutions")
eq(D.resolutions(modes, "1920x1080@144.00", 1).map(r => r.id), ["1920x1080"], "limit keeps the biggest")
eq(D.resolutions(modes, "1280x720@60.00", 1).map(r => r.id), ["1920x1080", "1280x720"], "the one in use is always kept")
eq(D.rates(modes, "1920x1080"), [{ id: "1920x1080@144.00", label: "144 Hz" }, { id: "1920x1080@60.00", label: "60 Hz" }], "rates")
eq(D.rates(D.parseModes(["1920x1080@59.94Hz"]), "1920x1080")[0].label, "59.94 Hz", "fractional rate")
eq(D.modeForRes(modes, "1920x1080", 60), "1920x1080@60.00", "keeps the rate")
eq(D.modeForRes(modes, "1280x720", 144), "1280x720@60.00", "closest rate when there is none")
eq(D.modeForRes(modes, "640x480", 60), "", "unknown resolution")

// ===== free placement =====
const rc = (name, x, y, w, h) => ({ name, x, y, w, h })
const M = rc("M", 0, 0, 1920, 1080)
// snap: left edge to the main's right edge, tops level
eq(D.snap(rc("S", 1930, 12, 1280, 720), [M], 20), { x: 1920, y: 0 }, "snaps to the right edge and the top")
eq(D.snap(rc("S", 1990, 60, 1280, 720), [M], 20), { x: 1990, y: 60 }, "out of reach: stays")
eq(D.snap(rc("S", -1290, 1070, 1280, 720), [M], 20), { x: -1280, y: 1080 }, "snaps to the left edge (right to left) and below")
eq(D.snap(rc("S", 100, 1085, 1280, 720), [M], 20), { x: 100, y: 1080 }, "below: only y snaps")
eq(D.snap(rc("S", 1500, 1085, 1280, 720), [M], 20).x, 1500, "x free while y snaps")
// overlap
eq(D.overlaps(M, rc("S", 1920, 0, 100, 100)), false, "touching is not overlapping")
eq(D.overlaps(M, rc("S", 1900, 0, 100, 100)), true, "20 px in is overlapping")
// separate
eq(D.separate(rc("S", 1800, 0, 1280, 720), [M]), { x: 1920, y: 0 }, "pushed out the short way (right)")
eq(D.separate(rc("S", 0, 1000, 1280, 720), [M]), { x: 0, y: 1080 }, "pushed out below")
eq(D.overlaps(rc("S", D.separate(rc("S", 500, 100, 800, 600), [M]).x, D.separate(rc("S", 500, 100, 800, 600), [M]).y, 800, 600), M), false, "fully inside still gets out")
eq(D.separate(rc("S", 3000, 0, 100, 100), [M]), { x: 3000, y: 0 }, "clear screens do not move")
const crowd = [M, rc("T", 2900, 0, 500, 500)]
const out = D.separate(rc("S", 1900, 0, 1000, 500), crowd)
eq(crowd.some(o => D.overlaps(rc("S", out.x, out.y, 1000, 500), o)), false, "a third screen in the way is cleared too")
eq(out, { x: 1900, y: -500 }, "and it is the nearest clear spot (above)")
eq(D.separate(rc("S", 100, 100, 5000, 5000), [M]), { x: 100, y: 1080 }, "a big screen still finds the nearest clear side (below)")
// dock
eq(D.dock({ w: 1280, h: 720 }, M, "right", []), { x: 1920, y: 0 }, "dock right")
eq(D.dock({ w: 1280, h: 720 }, M, "left", []), { x: -1280, y: 0 }, "dock left")
eq(D.dock({ w: 1280, h: 720 }, M, "above", []), { x: 0, y: -720 }, "dock above")
eq(D.dock({ w: 1280, h: 720 }, M, "below", []), { x: 0, y: 1080 }, "dock below")
eq(D.dock({ w: 1280, h: 720 }, M, "right", [rc("T", 1920, 0, 1000, 800)]), { x: 2920, y: 0 }, "dock right, past a screen already there")
// reflow: a screen grows, the ones past it move
const R = [rc("A", 0, 0, 1920, 1080), rc("B", 1920, 0, 1280, 720), rc("C", 0, 1080, 1280, 720)]
const R2 = D.reflow([rc("A", 0, 0, 2560, 1440), R[1], R[2]], "A", 1920, 1080)
eq([R2[1].x, R2[1].y, R2[2].x, R2[2].y], [2560, 0, 0, 1440], "B moves right and C moves down by the growth")
eq(D.reflow(R, "nobody", 1, 1), R, "unknown name: untouched")
const R3 = D.reflow([rc("A", 0, 0, 1280, 720), R[1], R[2]], "A", 1920, 1080)
eq([R3[1].x, R3[2].y], [1280, 720], "shrinking pulls the neighbours in")
// normalize
eq(D.normalize({ A: [-1280, 40], B: [0, 40] }), { A: [0, 0], B: [1280, 0] }, "smallest x and y become 0")
eq(D.normalize({ A: [0.4, 0.6] }), { A: [0, 0] }, "one screen at the origin")
eq(D.normalize({}), {}, "nothing")
// touches / unlinked
eq(D.touches(M, rc("S", 1920, 500, 100, 100)), true, "side by side with some shared edge")
eq(D.touches(M, rc("S", 1920, 1080, 100, 100)), false, "corner to corner is not a crossing")
eq(D.touches(M, rc("S", 2000, 0, 100, 100)), false, "a gap")
eq(D.unlinked([M]), [], "one screen is one piece")
eq(D.unlinked([M, rc("S", 1920, 0, 100, 100), rc("T", 2020, 50, 100, 100)]), [], "a chain is one piece")
eq(D.unlinked([M, rc("S", 1920, 0, 100, 100), rc("T", 3000, 0, 100, 100)]), ["T"], "a far screen is cut off")
// view
const V = D.view([M, rc("S", 1920, 0, 1280, 720)], 600, 200)
eq(V.scale > 0 && V.scale <= 200 / 1080, true, "scale fits the box")
eq(Math.round(V.ox + 0 * V.scale) >= 0 && Math.round(V.ox + 3200 * V.scale) <= 600, true, "the screens sit inside the box")
eq(D.view([], 100, 100), { scale: 1, ox: 0, oy: 0 }, "no screens")

// screens Hyprland does not list
eq(D.parseKnown("HDMI-A-1|1920x1080\neDP-1|\n\nbad name|1x1\n"), [{ name: "HDMI-A-1", w: 1920, h: 1080 }, { name: "eDP-1", w: 0, h: 0 }], "known screens")
const hy = [{ name: "eDP-1", on: true, modes: [] }]
const mg = D.mergeKnown(hy, D.parseKnown("eDP-1|1920x1080\nHDMI-A-1|1920x1080"))
eq(mg.map(m => m.name), ["eDP-1", "HDMI-A-1"], "a screen Hyprland does not list is added")
eq(mg[1].on, false, "added as off")
eq(mg[1].hint, { w: 1920, h: 1080 }, "with the panel size to draw it by")
eq(mg[0].hint, undefined, "a listed screen is left alone")
eq(D.mergeKnown(hy, []).length, 1, "nothing known, nothing added")
eq(D.mismatched([{ name: "A", on: false }, { name: "B", on: true }], [{ name: "A", on: true }, { name: "B", on: true }]).map(d => d.name), ["A"], "off wanted, still on")
eq(D.mismatched([{ name: "A", on: true }], [{ name: "A", on: true }]), [], "as wanted")
eq(D.mismatched([{ name: "A", on: true }], []), [], "not listed: nothing to compare")

console.log(fails === 0 ? "display tests: all passed" : fails + " failed")
process.exit(fails ? 1 : 0)
