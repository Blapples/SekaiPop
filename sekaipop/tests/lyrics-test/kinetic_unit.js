// The maths behind the whole-screen kinetic lyrics (modules/common/functions/KineticMath.js)
// and a static look at the three QML files that use it. The lines are made up for the test.
// Run: node kinetic_unit.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const root = path.join(__dirname, "..", "..")
function load(rel, extra) {
    const src = fs.readFileSync(path.join(root, rel), "utf8")
    const names = [...src.matchAll(/^function (\w+)/gm)].map(m => m[1])
    return { fns: new Function(src.replace(".pragma library", "") + "\nreturn { " + names.concat(extra || []).join(", ") + " }")(), names }
}
const LMload = load("modules/common/functions/LyricsMath.js")
const KMload = load("modules/common/functions/KineticMath.js", ["BOX_H", "GAP_EM", "ENTER_S", "LEAVE_S", "LEAVE_STAGGER", "STYLE_LISTS"])
const LM = LMload.fns
const KM = KMload.fns
const near = (a, b, e = 1e-6) => assert.ok(Math.abs(a - b) <= e, a + " vs " + b)

// ---------- noise ----------
for (let i = 0; i < 200; i++) {
    const v = KM.hash(i * 1.37)
    assert.ok(v >= 0 && v < 1, "hash is in [0, 1)")
    assert.strictEqual(v, KM.hash(i * 1.37), "hash is deterministic")
}
assert.notStrictEqual(KM.hash(1), KM.hash(2))
near(KM.clamp(5, 0, 1), 1); near(KM.clamp(-5, 0, 1), 0); near(KM.lerp(2, 4, 0.5), 3)

// ---------- widths ----------
assert.ok(KM.wordEm("iii") < KM.wordEm("mmm"), "narrow letters are narrower")
assert.ok(KM.wordEm("hello") < KM.wordEm("hello there"), "longer is wider")
assert.ok(KM.wordEm("\u591c\u306b\u99c6") > KM.wordEm("abc"), "square letters are wide")
assert.ok(KM.wordEm("a") >= 0.5)

// ---------- layouts: on the screen, not on top of each other ----------
const sizes = [[1920, 1080], [2560, 1440], [3840, 2160], [1366, 768], [1280, 1024], [2560, 1080]]
const lines = [
    "hello", "I love you", "hold me closer tonight", "we were young and we were reckless",
    "sing it loud for me (oh oh)", "dancing in the dark with you", "a b c d e f g h i j k l",
    "supercalifragilisticexpialidocious", "yeah", "run run run away from here tonight baby",
    "\u591c\u306b\u99c6\u3051\u308b \u541b\u3068\u4e8c\u4eba\u3067", "i'm walking on sunshine and don't it feel good",
    "(ooh) (ooh)", "oh", "la la la la la la la la la la la la la la la la"
]
let checked = 0
for (const [W, H] of sizes) {
    for (let idx = 0; idx < 40; idx++) {
        for (const text of lines) {
            const toks = LM.tokens(text)
            const p = KM.plan(toks, idx, W, H)
            assert.strictEqual(p.words.length, toks.length, "one place per word")
            assert.ok(["giant", "stack", "slash", "burst", "flow", "arc"].includes(p.style))
            const bs = p.words.map((w, i) => KM.bounds({ x: w.x, y: w.y, size: w.size, rot: w.rot }, toks, i))
            for (let i = 0; i < bs.length; i++) {
                const b = bs[i], tag = W + "x" + H + " " + p.style + " #" + idx + " '" + text + "' word " + i
                assert.ok(b.l >= -1 && b.t >= -1 && b.r <= W + 1 && b.b <= H + 1, "on the screen: " + tag + " " + JSON.stringify(b))
                assert.ok(p.words[i].size >= 10, "readable size")
                for (const k of ["enter", "leave"]) {
                    assert.ok(isFinite(p.words[i][k].s0 ?? p.words[i][k].s1), tag)
                }
                for (let j = i + 1; j < bs.length; j++)
                    assert.ok(!KM.overlap(bs[i], bs[j], 0.8), "apart: " + tag + " vs " + j)
                checked++
            }
            // the same line is always laid out the same way
            assert.deepStrictEqual(KM.plan(toks, idx, W, H), p, "deterministic")
        }
    }
}
assert.ok(checked > 10000)

// a long-ish line is still big enough to read (not a speck on the screen)
for (let idx = 0; idx < 40; idx++) {
    const toks = LM.tokens("we were young and we were reckless")
    const p = KM.plan(toks, idx, 1920, 1080)
    const smallest = Math.min(...p.words.map(w => w.size))
    assert.ok(smallest >= 1080 * 0.03, "smallest word " + smallest + " in style " + p.style)
}

// one word is the whole screen
{
    const toks = LM.tokens("yeah")
    const p = KM.plan(toks, 0, 1920, 1080)
    assert.ok(["giant", "burst"].includes(p.style))
    assert.ok(p.words[0].size > 1080 * 0.2, "a lone word is big")
}

// ad libs are small and kept out of the way of the tune
{
    const toks = LM.tokens("sing it loud (oh oh)")
    const p = KM.plan(toks, 3, 1920, 1080)
    const ad = toks.map((t, i) => t.adlib ? i : -1).filter(i => i >= 0)
    const main = toks.map((t, i) => t.adlib ? -1 : i).filter(i => i >= 0)
    assert.strictEqual(ad.length, 2)
    const biggestAd = Math.max(...ad.map(i => p.words[i].size))
    const smallestMain = Math.min(...main.map(i => p.words[i].size))
    assert.ok(biggestAd < smallestMain, "an ad lib is smaller than the words of the tune")
}

// two lines in a row do not get the same composition (same number of words)
for (let n = 1; n <= 7; n++) {
    const list = KM.STYLE_LISTS[n]
    if (list.length < 3)
        continue
    for (let idx = 0; idx < 120; idx++)
        assert.notStrictEqual(KM.styleFor(idx, n), KM.styleFor(idx + 1, n), n + " words, line " + idx)
}
// ...and over a song every style of the list turns up
{
    const seen = new Set()
    for (let idx = 0; idx < 60; idx++)
        seen.add(KM.styleFor(idx, 4))
    assert.strictEqual(seen.size, KM.STYLE_LISTS[4].length, "all styles are used")
}
// a very long line is a poster block
assert.strictEqual(KM.styleFor(5, 12), "flow")

// ---------- the ease ----------
near(KM.backOut(0, 1.9), 0); near(KM.backOut(1, 1.9), 1)
assert.ok(Math.max(...Array.from({ length: 50 }, (_, i) => KM.backOut(i / 49, 1.9))) > 1.05, "it overshoots")
near(KM.backOut(-3, 1.9), 0); near(KM.backOut(9, 1.9), 1)

// ---------- one word in time ----------
{
    const motion = { enter: { ox: 400, oy: -100, s0: 3, r0: 20 }, leave: { dx: 600, dy: 0, s1: 2, r1: -30 } }
    const from = 10, to = 10.8, leaveAt = 14
    const at = t => KM.wordAt(t, from, to, motion, leaveAt, 2, 5, false)
    let w = at(9.9)
    assert.strictEqual(w.started, false); near(w.op, 0); near(w.sung, 0)
    w = at(10)
    assert.strictEqual(w.started, true)
    near(w.ox, 400); near(w.s, 3); near(w.hit, 1); near(w.ring, 0)
    w = at(10.02)
    assert.ok(w.op > 0 && w.op < 1, "it comes in over 50 ms")
    w = at(10.5)
    assert.ok(Math.abs(w.ox) < 25 && Math.abs(w.s - 1) < 0.2, "nearly landed")
    near(w.hit, 0); assert.ok(w.sung > 0.6 && w.sung < 0.7)
    w = at(11)
    near(w.ox, 0, 1e-9); near(w.oy, 0, 1e-9); near(w.s, 1, 1e-9); near(w.rot, 0, 1e-9); near(w.op, 1); near(w.sung, 1)
    // it stays put until the line leaves
    assert.deepStrictEqual(at(12), at(13.9))
    w = at(leaveAt + 0.2)
    assert.ok(w.ox > 0 && w.s > 1 && w.op < 1 && w.op > 0, "it flies off")
    w = at(leaveAt + 3)
    near(w.op, 0); assert.strictEqual(w.gone, true)
    // a word that was never sung when its line was cut off is shown full and goes too
    w = KM.wordAt(14.1, 20, 21, motion, 14, 0, 3, false)
    assert.strictEqual(w.started, true); near(w.sung, 1)
    // word by word off: it fills in a flash
    w = KM.wordAt(10.09, 10, 10.2, motion, 14, 0, 3, true)
    near(w.sung, 0.5)
    // a word with no length
    w = KM.wordAt(10.5, 10, 10, motion, 14, 0, 3, false)
    near(w.sung, 1)
}

// ---------- when a line leaves ----------
{
    // plenty of room: shortly after it is sung
    near(KM.leaveStart(10, 12, 20, false), 12.22)
    near(KM.leaveStart(10, 12, 20, true), 12.35)
    // the next line is right behind: it leaves before it
    const l = KM.leaveStart(10, 12, 12.3, false)
    assert.ok(l < 12.3 - 0.1, "gone before the next line starts: " + l)
    // never before it has begun
    assert.ok(KM.leaveStart(10, 10.1, 10.2, false) >= 10.35)
    // the last line lingers
    near(KM.leaveStart(10, 12, Infinity, false), 13.1)
}

// ---------- the camera ----------
{
    // lines take turns drifting in and out, and a line starts where the one before it
    // stopped, so the picture does not jump when the next line begins
    for (let idx = 0; idx < 8; idx++) {
        const a = KM.camera(20, 10, 20, idx, 1920)
        const b = KM.camera(30, 30, 40, idx + 1, 1920)
        near(a.scale, b.scale, 1e-9); near(a.rot, b.rot, 1e-9); near(a.dx, b.dx, 1e-9)
    }
    // it holds still after the line has left
    assert.deepStrictEqual(KM.camera(25, 10, 20, 0, 1920), KM.camera(99, 10, 20, 0, 1920))
    // it is slow and small: no word beats the screen (the camera takes no word's time at all)
    assert.strictEqual(KM.camera.length, 5, "camera(t, lineStart, leaveAt, idx, W): no per-word punch")
    for (let t = 0; t < 30; t += 0.5) {
        const c = KM.camera(t, 5, 25, 3, 1920)
        assert.ok(Math.abs(c.rot) <= 0.21 && c.scale >= 1 && c.scale <= 1.031, "gentle")
    }
    // two readings a frame apart are almost the same picture
    const f1 = KM.camera(10.00, 5, 25, 2, 1920), f2 = KM.camera(10.02, 5, 25, 2, 1920)
    assert.ok(Math.abs(f1.scale - f2.scale) < 0.0001)
}

function strip0(t) { return t.replace(/\/\/.*$/gm, "") }
// ---------- the QML only asks for what exists ----------
for (const file of ["KineticWord.qml", "KineticLine.qml", "LyricsKinetic.qml"]) {
    const qml = fs.readFileSync(path.join(root, "modules", "sekai", "desktopWidgets", file), "utf8")
    for (const m of qml.matchAll(/\bKM\.(\w+)/g))
        assert.ok(KMload.names.includes(m[1]) || ["STYLE_LISTS", "BOX_H", "GAP_EM"].includes(m[1]), file + " calls KM." + m[1] + ", which does not exist")
    for (const m of qml.matchAll(/\bLM\.(\w+)/g))
        assert.ok(LMload.names.includes(m[1]), file + " calls LM." + m[1] + ", which does not exist")
    // QML refuses a property whose name starts with a capital letter ("W", "Height")
    for (const m of strip0(qml).matchAll(/\bproperty\s+(?:[\w.<>]+\s+)([A-Z]\w*)\s*:/g))
        assert.fail(file + ": property name `" + m[1] + "` starts with a capital letter")
    // the repo's own QML checker: no id or member twice, balanced
    assert.deepStrictEqual(require("../lib/qmlcheck.js")(qml, file), [], file)
    // balanced braces: a quick guard against a broken edit
    const strip = qml.replace(/\/\/.*$/gm, "").replace(/"(?:[^"\\]|\\.)*"/g, '""')
    assert.strictEqual((strip.match(/\{/g) || []).length, (strip.match(/\}/g) || []).length, file + ": braces are balanced")
    assert.strictEqual((strip.match(/\(/g) || []).length, (strip.match(/\)/g) || []).length, file + ": parentheses are balanced")
}
// the service keeps the two new settings
{
    const svc = fs.readFileSync(path.join(root, "services", "LyricsService.qml"), "utf8")
    for (const needle of ["property bool kinetic", "property real kineticDim", "function setKinetic", "function setKineticDim", "function setKineticColors", "function setKineticCamera", "kineticCamera: root.kineticCamera", "kineticColors: root.kineticColors", "kinetic: root.kinetic", "kineticDim: root.kineticDim", "root.kinetic = s.kinetic"])
        assert.ok(svc.includes(needle), "LyricsService has `" + needle + "`")
}
// the window takes its colours from one palette that follows the theme
{
    const w = fs.readFileSync(path.join(root, "modules", "sekai", "desktopWidgets", "LyricsKinetic.qml"), "utf8")
    assert.ok(w.includes("kineticCamera") && !/punch/.test(w), "the window has a Still camera and no punch")
    assert.ok(w.includes("readonly property var palette") && w.includes("m.capLitSoft") && w.includes("palette: win.palette"))
    assert.ok(!/attributeColors\[/.test(w), "no colour is fixed to the pastels any more")
    const l = fs.readFileSync(path.join(root, "modules", "sekai", "desktopWidgets", "KineticLine.qml"), "utf8")
    assert.ok(l.includes("line.palette") && !l.includes("line.mt.attributeColors"))
}
// presets hold the kinetic look, and a preset saved before it wears the card
{
    const pw = fs.readFileSync(path.join(root, "services", "PresetWidgets.qml"), "utf8")
    assert.ok(/id: "lyrics"[\s\S]*?before: \{ kinetic: false, kineticDim: 0\.45, kineticColors: "theme", kineticCamera: "drift", kineticStyle: "poster" \}/.test(pw), "the lyrics entry has the kinetic `before`")
    assert.ok(!/skip: \[[^\]]*kinetic/.test(pw), "the kinetic keys are not skipped")
}
// the sung colour is not cut at the string's advance width (an s or y tail stayed white)
{
    const lw = fs.readFileSync(path.join(root, "modules", "sekai", "desktopWidgets", "LyricsWord.qml"), "utf8")
    assert.ok(lw.includes("id: fillClip") && lw.includes("box.width + 2 * fillClip.pad"), "a sung word is coloured right to the end of its ink")
}
// shell.qml builds the window and offers the ipc
{
    const sh = fs.readFileSync(path.join(root, "shell.qml"), "utf8")
    for (const needle of ["LyricsKinetic {", "function kinetic(on: bool)", "function kineticToggle()", "function dim(amount: real)", "function colors(mode: string)", "function camera(mode: string)", "!LyricsService.kinetic"])
        assert.ok(sh.includes(needle), "shell.qml has `" + needle + "`")
}

// ====================================================================================
// The Wall and the Marquee (modules/common/functions/KineticStyles.js)
// ====================================================================================
const KSload = load("modules/common/functions/KineticStyles.js", ["STYLES", "DRIFT", "WALL_COLUMN", "WALL_Z_MIN", "WALL_Z_MAX", "WALL_LEAD", "WALL_MOVE", "WALL_GAP_EM", "WALL_ADLIB", "MARQ_GAP_EM", "MARQ_SEP_EM", "MARQ_ADLIB", "WALL_WLEAD", "WALL_WMOVE", "WALL_TILT", "WALL_ROLL_MAX"])
const KS = KSload.fns

// ---------- the looks ----------
assert.deepStrictEqual(KS.STYLES, ["poster", "wall", "marquee"])
assert.ok(KS.isStyle("wall") && KS.isStyle("marquee") && KS.isStyle("poster") && !KS.isStyle("nope") && !KS.isStyle(undefined))
assert.strictEqual(KS.nextStyle("poster"), "wall"); assert.strictEqual(KS.nextStyle("wall"), "marquee")
assert.strictEqual(KS.nextStyle("marquee"), "poster", "the cycle comes round"); assert.strictEqual(KS.nextStyle("???"), "poster")

// made-up songs: the words' widths come from KineticMath.wordEm, as in the QML
function describeLine(text, adlibFrom) {
    const toks = text.split(/\s+/).filter(Boolean)
    return { blank: toks.length === 0, ems: toks.map(s => Math.max(0.3, KM.wordEm(s) - 0.2)), adlib: toks.map((s, i) => adlibFrom !== undefined && i >= adlibFrom) }
}
const song = lines.concat(["", "oh oh oh", "x"]).map((t, i) => describeLine(t, i === 4 ? 4 : undefined))
const starts = song.map((_, i) => 4 + i * 3.2)

// ---------- the wall: every block on the wall, in order, no overlap ----------
for (const [W, H] of sizes) {
    const plan = KS.wallPlan(song, W, H)
    assert.strictEqual(plan.lines.length, song.length)
    let prevBottom = -Infinity
    plan.lines.forEach((b, i) => {
        assert.ok(b.y0 >= prevBottom - 1e-6, "wall block " + i + " starts below the one before it (" + W + "x" + H + ")")
        prevBottom = b.y0 + b.h
        assert.ok(b.x0 >= -1e-6 && b.x0 + b.w <= plan.width + 1e-6, "wall block " + i + " is inside the column (" + W + "x" + H + ")")
        assert.ok(b.zoom >= KS.WALL_Z_MIN - 1e-9 && b.zoom <= KS.WALL_Z_MAX + 1e-9, "the zoom is kept in range")
        near(b.cx, b.x0 + b.w / 2); near(b.cy, b.y0 + b.h / 2)
        if (!b.blank) {
            // every word is in exactly one row
            const seen = b.rows.flat().sort((a, c) => a - c)
            assert.deepStrictEqual(seen, song[i].ems.map((_, k) => k), "every word of line " + i + " is in a row, once")
            b.words.forEach(wd => {
                assert.ok(wd && wd.x >= -1e-6 && wd.x <= b.w + 1e-6 && wd.y >= 0 && wd.y <= b.h, "a word is inside its block")
            })
            // the line that is on fills most of the screen's width, never more than it
            assert.ok(b.w * b.zoom <= W * 0.84 + 1e-6 || b.zoom === KS.WALL_Z_MIN, "the line that is on fits the screen")
        }
    })
    assert.ok(Math.abs(plan.height - (prevBottom)) < 1e-6, "the wall's height is where the last block ends")
    // the same song gives the same wall
    assert.deepStrictEqual(KS.wallPlan(song, W, H), plan, "the wall is deterministic")
}

// a blank line (an intro / instrumental) is a small block, not a hole in the maths
{
    const b = KS.wallPlan([describeLine("")], 1920, 1080).lines[0]
    assert.ok(b.blank && b.w > 0 && b.h > 0)
}

// ---------- the camera ----------
const plan = KS.wallPlan(song, 1920, 1080)
// well after a line's move it is on that line's middle, at that line's zoom
for (let i = 0; i < song.length - 1; i++) {
    const c = KS.wallCamera(plan, starts, starts[i] + 1.5, false)
    near(c.x, plan.lines[i].cx, 1e-6); near(c.y, plan.lines[i].cy, 1e-6); near(c.z, plan.lines[i].zoom, 1e-6)
}
// before the first line it rests on the first block
{
    const c = KS.wallCamera(plan, starts, 0, false)
    near(c.x, plan.lines[0].cx); near(c.y, plan.lines[0].cy)
}
// it never jumps: sample the whole song at 60 fps, the step is small and the path is continuous
{
    let prev = null, worst = 0
    for (let t = 0; t < starts[starts.length - 1] + 5; t += 1 / 60) {
        const c = KS.wallCamera(plan, starts, t, true)
        assert.ok(isFinite(c.x) && isFinite(c.y) && c.z > 0, "the camera is a real number")
        if (prev) worst = Math.max(worst, Math.hypot(c.x - prev.x, c.y - prev.y) / Math.max(1, plan.lines[0].w))
        prev = c
    }
    assert.ok(worst < 1.2, "the camera never teleports (biggest step " + worst.toFixed(2) + " widths in one frame)")
}
// a line that starts before the last move has finished bends the path instead of jumping
{
    const fast = [0, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.2].slice(0, song.length)
    while (fast.length < song.length) fast.push(fast[fast.length - 1] + 0.3)
    let prev = null, worst = 0
    for (let t = -1; t < 8; t += 1 / 120) {
        const c = KS.wallCamera(plan, fast, t, false)
        if (prev) worst = Math.max(worst, Math.hypot(c.x - prev.x, c.y - prev.y))
        prev = c
    }
    assert.ok(worst < plan.height / 10, "fast lines still move the camera smoothly")
}
// a seek lands in the right place: the camera is a pure function of the clock
{
    const a = KS.wallCamera(plan, starts, 17.3, true)
    KS.wallCamera(plan, starts, 40, true)
    assert.deepStrictEqual(KS.wallCamera(plan, starts, 17.3, true), a, "the same time gives the same camera, whatever came before")
}
// not enough starts for the lines: it holds still instead of throwing
assert.deepStrictEqual(KS.wallCamera(plan, [1, 2], 3, true), { x: 0, y: 0, z: 1 })
assert.deepStrictEqual(KS.wallCamera({ lines: [] }, [], 3, true), { x: 0, y: 0, z: 1 })
// Still (no drift) is the same flight without the slow zoom
{
    const t = starts[3] + 1.5
    near(KS.wallCamera(plan, starts, t, false).x, KS.wallCamera(plan, starts, t, true).x)
    assert.ok(Math.abs(KS.wallCamera(plan, starts, t, true).z / KS.wallCamera(plan, starts, t, false).z - 1) <= KS.DRIFT + 1e-9, "drift is a hair")
}

// ---------- the light ----------
for (let t = 0; t < 12; t += 0.05) {
    const f = KS.wallFocus(t, 3, 7)
    assert.ok(f >= -1e-9 && f <= 1 + 1e-9, "focus is 0 .. 1")
}
assert.ok(KS.wallFocus(0, 3, 7) < 0.01 && KS.wallFocus(5, 3, 7) > 0.99 && KS.wallFocus(12, 3, 7) < 0.01, "a line lights up, stays on, then dims")
assert.ok(KS.wallFocus(5, 3, Infinity) > 0.99 && KS.wallFocus(500, 3, Infinity) > 0.99, "the last line stays on")
for (let d = -8; d <= 8; d++) for (const f of [0, 0.5, 1]) {
    const s = KS.wallShade(d, f)
    assert.ok(s >= 0.1 - 1e-9 && s <= 1 + 1e-9, "shade is 0.1 .. 1")
}
near(KS.wallShade(0, 1), 1)
assert.ok(KS.wallShade(1, 0) > KS.wallShade(5, 0) && KS.wallShade(-1, 0) > KS.wallShade(-5, 0), "the further from the line that is on, the dimmer")
assert.ok(KS.wallShade(0, 1) > KS.wallShade(1, 0) + 0.4, "the line that is on stands out")

// ---------- the slow drift ----------
near(KS.drift([], 5), 1); near(KS.drift([2, 6], 1), 1)
for (let t = 0; t < 12; t += 0.1) {
    const d = KS.drift([2, 6, 10], t)
    assert.ok(d >= 1 - 1e-9 && d <= 1 + KS.DRIFT + 1e-9, "drift stays within a hair")
}
near(KS.drift([2, 6, 10], 6), KS.drift([2, 6, 10], 5.999999), 1e-4)   // a line starts where the one before stopped: no jump

// ---------- the marquee: rows ----------
for (const [W, H] of sizes) {
    const rows = KS.marqueeRows(W, H)
    assert.ok(rows.length === 3 || rows.length === 5, "three or five rows")
    assert.strictEqual(rows.length, H < 600 ? 3 : 5)
    near(rows[0].y, 0)
    const mid = (rows.length - 1) / 2
    assert.strictEqual(rows.filter(r => r.hero).length, 1, "one hero row")
    assert.ok(rows[mid].hero, "the hero is the one in the middle")
    rows.forEach((r, i) => {
        near(r.y + r.rowH, i + 1 < rows.length ? rows[i + 1].y : H, 1e-6)
        assert.strictEqual(r.dir, Math.abs(i - mid) % 2 === 0 ? -1 : 1, "the rows above and below go the other way")
        assert.ok(r.px > 0 && r.px < r.rowH, "the type fits its row")
        assert.ok(r.seed >= 0 && r.seed < 1 && r.alpha > 0 && r.alpha <= 1)
        if (!r.hero) {
            assert.ok(r.speed > 0, "the texture rows slide")
            assert.ok(r.px < rows[mid].px && r.alpha < 1, "texture rows are smaller and fainter than the hero")
        } else {
            assert.ok(r.speed === 0 && r.alpha === 1, "the hero does not scroll on its own")
        }
    })
    // the further from the hero the smaller and the fainter
    for (let i = 0; i < mid; i++) assert.ok(rows[i].px < rows[i + 1].px && rows[i].alpha <= rows[i + 1].alpha, "smaller towards the edges")
    near(rows[0].px, rows[rows.length - 1].px, 1)
    // the hero is big: at least a quarter of the screen's height for the type
    if (H >= 600) assert.ok(rows[mid].px >= H * 0.24, "the hero type is big")
}

// ---------- the hero row follows the voice ----------
{
    const froms = [10, 11, 12.5, 14], mids = [100, 400, 900, 1500]
    near(KS.voiceFollow(froms, mids, 0), 100); near(KS.voiceFollow(froms, mids, 10), 100)
    near(KS.voiceFollow(froms, mids, 14), 1500); near(KS.voiceFollow(froms, mids, 99), 1500)
    near(KS.voiceFollow(froms, mids, 11), 400); near(KS.voiceFollow(froms, mids, 12.5), 900)
    // in between it is between the two words, and it never goes backwards
    let last = -Infinity
    for (let t = 9; t < 15; t += 0.01) {
        const f = KS.voiceFollow(froms, mids, t)
        assert.ok(f >= last - 1e-9 && f >= 100 - 1e-9 && f <= 1500 + 1e-9, "the voice only moves forward, inside the line")
        last = f
    }
    assert.ok(KS.voiceFollow(froms, mids, 10.5) > 100 && KS.voiceFollow(froms, mids, 10.5) < 400)
    assert.strictEqual(KS.voiceFollow([], [], 3), 0)
    assert.strictEqual(KS.voiceFollow([1], [250], 5), 250)
    // heroX: the point lands where it should, in any repeat, kept within one period of the left edge
    for (const period of [500, 1234.5, 3000]) for (const target of [-4000, -700, -1, 0, 1, 333, 960, 5000]) {
        const x = KS.heroX(target, period)
        assert.ok(x >= -period - 1e-6 && x < 1e-6, "heroX is within one period")
        near(((x - target) % period + period) % period, 0, 1e-6)
        // the point is the same place in the picture, whichever repeat it is
    }
    // the picture does not jump when the voice crosses from one repeat to the next
    near(KS.heroX(960 - 0.001, 1000), KS.heroX(960 + 1000 - 0.001, 1000), 1e-6)
}

// ---------- the marquee: the strip ----------
for (const dir of [-1, 1]) for (const period of [300, 777.7, 2400]) {
    for (let t = -20; t < 400; t += 0.37) {
        const x = KS.marqueeX(t, 90, 0.4, dir, period)
        assert.ok(x > -period - 1e-6 && x <= 1e-6, "the strip's left end stays within one period (dir " + dir + ")")
    }
    // it loops with no seam: one period later it is where it was
    near(KS.marqueeX(5, 90, 0.4, dir, period) , KS.marqueeX(5 + period / 90, 90, 0.4, dir, period), 1e-6)
    // and it really moves, the way it should
    const x0 = KS.marqueeX(10, 90, 0, dir, period), x1 = KS.marqueeX(10.1, 90, 0, dir, period)
    assert.ok(dir < 0 ? x1 < x0 : x1 > x0, "the strip moves " + (dir < 0 ? "left" : "right"))
}
assert.ok(isFinite(KS.marqueeX(0, 0, 0, -1, 0)), "a zero period does not divide by zero")

// a strip always covers the screen: even if the real period is 15 % longer than the guess,
// or the line is a single short word
for (const [W] of sizes) {
    for (const t of ["x", "oh oh", "hold me closer tonight", "we were young and we were reckless and free"]) {
        const d = describeLine(t)
        const px = 150
        const guess = KS.marqueePeriod(d.ems, d.adlib, px)
        const units = KS.marqueeUnits(guess, W)
        assert.ok(units >= 2 && units <= 30)
        for (const real of [guess * 0.85, guess, guess * 1.0]) {
            if (units < 30) assert.ok(units * real >= W + real - 1e-6, "the strip covers " + W + " px for \"" + t + "\" (" + units + " repeats)")
        }
    }
}

// ---------- the marquee: a line coming and going ----------
for (const dir of [-1, 1]) for (let r = 0; r < 8; r++) {
    let lastOp = -1
    for (let t = 9.9; t < 10.8; t += 0.01) {      // coming in: more and more there
        const a = KS.marqueeAt(t, 10, 20, r, dir, 1920)
        assert.ok(a.op >= -1e-9 && a.op <= 1 + 1e-9)
        assert.ok(a.op >= lastOp - 1e-9, "a row only fades in while it comes in")
        lastOp = a.op
    }
    const mid = KS.marqueeAt(15, 10, 20, r, dir, 1920)
    near(mid.ox, 0, 1e-6); near(mid.op, 1, 1e-6)
    const before = KS.marqueeAt(5, 10, 20, r, dir, 1920)
    assert.ok(before.op === 0 && Math.sign(before.ox) === -dir, "before it starts a row waits at the side its strip is moving away from")
    const after = KS.marqueeAt(30, 10, 20, r, dir, 1920)
    assert.ok(after.op <= 1e-6 && Math.sign(after.ox) === dir, "after it has left it is gone off the side it moves toward")
}

// ---------- the wall: the camera follows the word ----------
{
    // made-up waypoints: a few words each of three lines
    const pts = []
    let tt = 4
    for (let li = 0; li < 3; li++) for (let k = 0; k < 5; k++) {
        pts.push({ t: tt, x: li * 900 + k * 260, y: li * 400 + (k % 2) * 40, lz: Math.log(1 + 0.15 * k) })
        tt += 0.45
    }
    const LEAD = KS.WALL_WLEAD, MOVE = KS.WALL_WMOVE
    // long after a word nothing else comes: the camera is exactly on it
    {
        const c = KS.wallFollow(pts.slice(0, 3), pts[2].t + 3, LEAD, MOVE)
        near(c.x, pts[2].x); near(c.y, pts[2].y); near(c.z, Math.exp(pts[2].lz))
    }
    // before the first word it waits on it
    near(KS.wallFollow(pts, 0, LEAD, MOVE).x, pts[0].x)
    // it never teleports and it always ends up on the last word
    let prev = null, worst = 0
    for (let t = 0; t < tt + 3; t += 1 / 120) {
        const c = KS.wallFollow(pts, t, LEAD, MOVE)
        assert.ok(isFinite(c.x) && isFinite(c.y) && c.z > 0)
        if (prev) worst = Math.max(worst, Math.hypot(c.x - prev.x, c.y - prev.y))
        prev = c
    }
    assert.ok(worst < 40, "the camera glides (biggest step " + worst.toFixed(1) + " px in 1/120 s)")
    near(prev.x, pts[pts.length - 1].x, 1e-6)
    // the same time gives the same camera, whatever came before (a seek)
    const a = KS.wallFollow(pts, 7.7, LEAD, MOVE); KS.wallFollow(pts, 30, LEAD, MOVE)
    assert.deepStrictEqual(KS.wallFollow(pts, 7.7, LEAD, MOVE), a)
    assert.deepStrictEqual(KS.wallFollow([], 3, LEAD, MOVE), { x: 0, y: 0, z: 1 })
}
// how far it pushes in on a word
for (const lineZoom of [0.6, 1, 1.4]) for (const w of [60, 300, 800, 2000, 6000]) {
    const z = KS.wallWordZoom(w, lineZoom, 1920)
    assert.ok(z >= Math.max(KS.WALL_Z_MIN, lineZoom * 0.9) - 1e-9 && z <= Math.min(3.2, lineZoom * 1.9) + 1e-9, "the word zoom stays near the line's")
}
assert.ok(KS.wallWordZoom(200, 1, 1920) > KS.wallWordZoom(1500, 1, 1920) - 1e-9, "a short word is pushed in on harder")
// the swing
near(KS.wallRoll(0), 0)
assert.ok(KS.wallRoll(1e6) <= KS.WALL_ROLL_MAX + 1e-9 && KS.wallRoll(-1e6) >= -KS.WALL_ROLL_MAX - 1e-9, "the swing is kept small")
assert.ok(KS.wallRoll(800) > 0 && KS.wallRoll(-800) < 0)
assert.ok(Math.abs(KS.WALL_TILT) <= 5, "the tilt is a few degrees")
// word light
{
    near(KS.wordGlow(5, 6, 0), 0); near(KS.wordGlow(5, 6, 5.5), 1); near(KS.wordGlow(5, 6, 5), 1)
    assert.ok(KS.wordGlow(5, 6, 20) < 1e-9, "it settles")
    let l = -1
    for (let t = 4.5; t <= 5; t += 0.005) { const g = KS.wordGlow(5, 6, t); assert.ok(g >= l - 1e-9 && g >= -1e-9 && g <= 1 + 1e-9); l = g }
    assert.ok(KS.wordGlow(5, 5, 5.2) >= 0, "a word with no length does not break it")
}
// depth: the further the smaller and the blurrier, the one that is on is sharp and full size
{
    near(KS.wallDepth(0).scale, 1); near(KS.wallDepth(0).blur, 0)
    for (let d = 1; d < 8; d++) {
        const a = KS.wallDepth(d), b = KS.wallDepth(d + 1), c = KS.wallDepth(-d)
        assert.ok(a.scale <= KS.wallDepth(d - 1).scale + 1e-9 && b.blur >= a.blur - 1e-9, "further is smaller and blurrier")
        assert.ok(a.scale >= 0.72 - 1e-9 && a.blur > 0 && a.blur <= 1 + 1e-9)
        assert.deepStrictEqual(a, c, "before and after are the same")
    }
}

// ---------- no QML file declares a property that Item already has ----------
// (Quickshell refuses to load a file that redeclares a FINAL property of Item, e.g. `focus`:
// "Cannot override FINAL property"; plain node cannot see that, so the names are listed here)
{
    const ITEM_FINAL = ["focus", "activeFocus", "activeFocusOnTab", "enabled", "visible", "x", "y", "z", "width", "height",
        "opacity", "scale", "rotation", "clip", "state", "states", "transitions", "parent", "children", "data", "resources",
        "transform", "smooth", "antialiasing", "baselineOffset", "implicitWidth", "implicitHeight", "transformOrigin",
        "anchors", "layer", "containmentMask", "objectName", "visibleChildren", "childrenRect", "focusPolicy"]
    const dir = path.join(root, "modules", "sekai", "desktopWidgets")
    for (const f of fs.readdirSync(dir).filter(n => /Kinetic/.test(n) && n.endsWith(".qml"))) {
        const q = fs.readFileSync(path.join(dir, f), "utf8")
        for (const m of q.matchAll(/^\s*(?:readonly\s+)?property\s+(?:alias\s+)?[\w.<>]+\s+(\w+)\s*[:\n]/gm))
            assert.ok(!ITEM_FINAL.includes(m[1]), f + " declares `" + m[1] + "`, which Item already has")
        for (const m of q.matchAll(/^\s*(?:readonly\s+)?property\s+alias\s+(\w+)\s*:/gm))
            assert.ok(!ITEM_FINAL.includes(m[1]), f + " declares the alias `" + m[1] + "`, which Item already has")
    }
}

// ---------- the QML files are wired ----------
{
    const dw = path.join(root, "modules", "sekai", "desktopWidgets")
    const rd = f => fs.readFileSync(path.join(dw, f), "utf8")
    for (const f of ["KineticFillWord.qml", "KineticWall.qml", "KineticWallLine.qml", "KineticMarquee.qml", "KineticMarqueeLine.qml", "KineticMarqueeRow.qml"])
        assert.ok(fs.existsSync(path.join(dw, f)), f + " exists")
    const win = rd("LyricsKinetic.qml")
    const wallQ = rd("KineticWall.qml"), lineQ = rd("KineticWallLine.qml"), rowQ = rd("KineticMarqueeRow.qml")
    for (const needle of ["KS.wallFollow(", "KS.WALL_TILT", "KS.wallRoll(", "function waypoints()", "it.center(k)", "KS.wallWordZoom("])
        assert.ok(wallQ.includes(needle), "KineticWall.qml has `" + needle + "`")
    for (const needle of ["KS.wallDepth(", "KS.wordGlow(", "function center(k)", "line.cells[cell.k] = cell", "MultiEffect"])
        assert.ok(lineQ.includes(needle), "KineticWallLine.qml has `" + needle + "`")
    for (const needle of ["KS.voiceFollow(", "KS.heroX(", "row.spec.hero", "property alias cells: cellsRep", "row.spec.alpha"])
        assert.ok(rowQ.includes(needle), "KineticMarqueeRow.qml has `" + needle + "`")
    for (const needle of ["KineticWall {", "KineticMarquee {", 'active: win.style === "wall"', 'active: win.style === "marquee"', "readonly property bool poster", "visible: win.poster && opacity > 0.002", "active: win.poster && Math.abs(slot.index - win.curIndex) <= 1", "lineStarts", "lineEnds", "lineBgEnds"])
        assert.ok(win.includes(needle), "LyricsKinetic.qml has `" + needle + "`")
    // every QML file that names a function of the math files finds it there
    const fnOf = { LM: LMload.names, KM: KMload.names, KS: KSload.names }
    for (const f of ["KineticWall.qml", "KineticWallLine.qml", "KineticMarquee.qml", "KineticMarqueeLine.qml", "KineticMarqueeRow.qml"]) {
        const q = rd(f)
        for (const m of q.matchAll(/\b(LM|KM|KS)\.(\w+)\(/g))
            assert.ok(fnOf[m[1]].includes(m[2]), f + " calls " + m[1] + "." + m[2] + "(), which exists")
        for (const m of q.matchAll(/\bKS\.([A-Z][A-Z_]+)\b/g))
            assert.ok(new RegExp("^var " + m[1] + "\\b", "m").test(fs.readFileSync(path.join(root, "modules/common/functions/KineticStyles.js"), "utf8")), f + " uses KS." + m[1] + ", which exists")
    }
    const svc = fs.readFileSync(path.join(root, "services", "LyricsService.qml"), "utf8")
    for (const needle of ['property string kineticStyle: "poster"', "function setKineticStyle(mode)", "function cycleKineticStyle()", "kineticStyle: root.kineticStyle,", "root.kineticStyle = s.kineticStyle"])
        assert.ok(svc.includes(needle), "LyricsService.qml has `" + needle + "`")
    const sh2 = fs.readFileSync(path.join(root, "shell.qml"), "utf8")
    for (const needle of ["function style(mode: string)", "function styleCycle()"])
        assert.ok(sh2.includes(needle), "shell.qml has `" + needle + "`")
    const st = fs.readFileSync(path.join(root, "modules", "sekai", "settings", "SettingsPageDesktop.qml"), "utf8")
    assert.ok(st.includes('label: "Whole screen style"') && st.includes("LyricsService.setKineticStyle(id)"), "the settings page has the style picker")
}

console.log("kinetic lyrics: all good (" + checked + " words laid out)")
