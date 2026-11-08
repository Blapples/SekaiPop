.pragma library

// The maths of the lockscreen editor (modules/sekai/lockEditor), kept free of QML so
// tests/lock-edit-test/lock_edit_unit.js can run it under node.
//
// The editor shows the lockscreen as a framed card, the same way Edit Desktop shows the
// desktop: the card is the whole screen drawn at a smaller scale, so a widget is exactly as
// big on it, relative to the screen, as it will be when locked. Everything below works in
// SCREEN pixels (the lock's own pixels), not card pixels: the editor turns a pointer
// position on the card into screen pixels first.
//
//   cardFit(areaW, areaH, screenW, screenH)    the card's scale and place in a room
//   placeAxis(frac, size, scale, total)        same rule as the canvas (LockCanvasModel.js)
//   keepOn(frac, size, scale, total)           a centre fraction, pulled back onto the screen
//   snapAxis(center, drawn, lines, threshold)  pull a widget onto a guide line
//   linesOf(others, total)                     the guide lines the other widgets give
//   scaleFromDrag(start, d0, d1, lo, hi)       the size handle
//   stepScale(scale, dir, step, lo, hi)        the wheel / + and - keys
//   percent(scale)                             "120%"
//   History: emptyHistory / record / undo / redo
//   cycle(ids, current, dir)                   Tab through what can be selected
//   optionLabel(key) / valueLabel(value)       words for the options panel

var SNAP_PX = 10
var SCALE_SNAP = 0.04
// The size range of a widget: the same numbers LockCanvasModel.js clamps to (a test checks).
var SCALE_LO = 0.5
var SCALE_HI = 2.5
var HISTORY_CAP = 60

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v))
}

// ===== the card =====

// The biggest card of the screen's shape that fits a room, centred in it. `k` is how much
// smaller than the screen it is; x and y are where its top-left corner sits in the room.
function cardFit(areaW, areaH, screenW, screenH) {
    if (!(areaW > 0) || !(areaH > 0) || !(screenW > 0) || !(screenH > 0))
        return { k: 1, w: Math.max(0, screenW || 0), h: Math.max(0, screenH || 0), x: 0, y: 0 }
    var k = Math.min(areaW / screenW, areaH / screenH)
    var w = screenW * k
    var h = screenH * k
    return { k: k, w: w, h: h, x: (areaW - w) / 2, y: (areaH - h) / 2 }
}

// ===== placing =====

// Where the widget's own x (or y) goes: LockCanvasModel.placeAxis, word for word, so a
// widget lands on the editor's card where it lands on the lock. The unit test checks they
// agree.
function placeAxis(frac, size, scale, total) {
    var drawn = size * scale
    var left = frac * total - drawn / 2
    left = Math.min(left, total - drawn)
    left = Math.max(left, 0)
    return left + drawn / 2 - size / 2
}

// A centre fraction that keeps the drawn widget fully on the screen (what the canvas would
// show, as a number the editor can save).
function keepOn(frac, size, scale, total) {
    if (!(total > 0))
        return 0.5
    return clamp((placeAxis(frac, size, scale, total) + size / 2) / total, 0, 1)
}

// ===== snapping =====

// The guide lines the other widgets give along one axis: the screen's middle, and for each
// of them its middle and both its edges. `others` is a list of { c, d }: the widget's centre
// and drawn length along that axis, in screen pixels.
function linesOf(others, total) {
    var out = [total / 2]
    for (var i = 0; i < others.length; i++) {
        var o = others[i]
        out.push(o.c, o.c - o.d / 2, o.c + o.d / 2)
    }
    return out
}

// Pulls a widget onto a guide line. The widget has three places that can line up: its
// near edge, its middle and its far edge. Returns { delta, line }: how far to move it (px)
// and the line it landed on, or { delta: 0, line: null } when nothing is close enough.
function snapAxis(center, drawn, lines, threshold) {
    var t = typeof threshold === "number" ? threshold : SNAP_PX
    var anchors = [center - drawn / 2, center, center + drawn / 2]
    var best = null
    for (var i = 0; i < lines.length; i++) {
        for (var j = 0; j < anchors.length; j++) {
            var d = lines[i] - anchors[j]
            if (Math.abs(d) <= t && (best === null || Math.abs(d) < Math.abs(best.delta)))
                best = { delta: d, line: lines[i] }
        }
    }
    return best === null ? { delta: 0, line: null } : best
}

// ===== size =====

// The size handle: the scale follows how far the pointer is from the widget's centre, so
// dragging the corner out grows it. `d0` is that distance when the drag began (at scale
// `start`), `d1` now. Close to 100 % it sticks there.
function scaleFromDrag(start, d0, d1, lo, hi) {
    lo = typeof lo === "number" ? lo : SCALE_LO
    hi = typeof hi === "number" ? hi : SCALE_HI
    if (!(d0 > 1))
        return clamp(start, lo, hi)
    var s = clamp(start * d1 / d0, lo, hi)
    if (Math.abs(s - 1) < SCALE_SNAP && lo <= 1 && hi >= 1)
        s = 1
    return Math.round(s * 100) / 100
}

// One notch of the wheel (or the + / - key): `dir` is 1 or -1.
function stepScale(scale, dir, step, lo, hi) {
    lo = typeof lo === "number" ? lo : SCALE_LO
    hi = typeof hi === "number" ? hi : SCALE_HI
    var st = typeof step === "number" ? step : 0.05
    return Math.round(clamp(scale + (dir > 0 ? st : -st), lo, hi) * 100) / 100
}

function percent(scale) {
    return Math.round(scale * 100) + "%"
}

// ===== undo / redo =====
// A history is { undo: [json, ...], redo: [json, ...] } of boards saved as text: text
// compares with ===, and nothing in it can be changed behind the editor's back. Every
// function returns a new history and never changes the one it was given.

function emptyHistory() {
    return { undo: [], redo: [] }
}

// `before` is the board as it was before an edit. Making an edit clears what could be redone.
function record(h, before) {
    var u = h.undo.concat([JSON.stringify(before)])
    if (u.length > HISTORY_CAP)
        u = u.slice(u.length - HISTORY_CAP)
    return { undo: u, redo: [] }
}

// Steps back: { h, board } (board is the one to show), or null when there is nothing to undo.
function undo(h, current) {
    if (h.undo.length === 0)
        return null
    var board = JSON.parse(h.undo[h.undo.length - 1])
    return {
        h: { undo: h.undo.slice(0, -1), redo: h.redo.concat([JSON.stringify(current)]) },
        board: board
    }
}

function redo(h, current) {
    if (h.redo.length === 0)
        return null
    var board = JSON.parse(h.redo[h.redo.length - 1])
    return {
        h: { undo: h.undo.concat([JSON.stringify(current)]), redo: h.redo.slice(0, -1) },
        board: board
    }
}

function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
}

// ===== selection =====

// Tab / Shift+Tab: the next thing to select out of `ids` (every widget's uid, then "core"),
// wrapping round. With nothing selected, Tab picks the first and Shift+Tab the last.
function cycle(ids, current, dir) {
    if (ids.length === 0)
        return ""
    var i = ids.indexOf(current)
    if (i < 0)
        return dir > 0 ? ids[0] : ids[ids.length - 1]
    return ids[(i + (dir > 0 ? 1 : ids.length - 1)) % ids.length]
}

// ===== words =====

var LABELS = {
    format: "Format", style: "Style", since: "Locked since", place: "City", condition: "Condition",
    percent: "Percentage", controls: "Keys", lyrics: "Lyrics", text: "Words", size: "Size",
    path: "Picture", shape: "Shape", name: "Name", label: "Label", details: "Details", date: "Date (YYYY-MM-DD)"
}

function optionLabel(key) {
    if (LABELS[key])
        return LABELS[key]
    return key.length > 0 ? key.charAt(0).toUpperCase() + key.slice(1) : key
}

// An option's value as it is written on a key: "auto" -> "Auto", true -> "On".
function valueLabel(v) {
    if (v === true)
        return "On"
    if (v === false)
        return "Off"
    var s = String(v)
    return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s
}
