.pragma library

// The maths of the two other looks of the whole-screen lyrics (the first, the poster, is
// KineticMath.js): the WALL (every line of the song is one giant block of type on one huge
// wall; the camera flies from WORD to word, the wall is tilted a few degrees and the lines
// further from the one that is on are smaller and blurrier) and the MARQUEE (one big HERO row
// in the middle that follows the voice, solid in one clear colour as it is sung, between rows
// of smaller, hollow, faint type sliding past).
// No QML in here, so tests/lyrics-test/kinetic_unit.js can run it with node.
//
// As in KineticMath.js everything is a pure function of the lyrics clock `t` (seconds), never
// of "what happened last frame": a pause freezes the picture and a seek lands in the right place.
//
// The words come from LyricsMath.tokens(), their widths in ems from KineticMath.wordEm() (the
// callers pass them in, `ems`, so this file needs no import), and their times from
// LyricsMath.spansFor().

// ===== small things =====
function clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v)
}

function lerp(a, b, u) {
    return a + (b - a) * u
}

// The same line always gets the same picture (no Math.random).
function hash(n) {
    var x = Math.sin(n * 127.1 + 311.7) * 43758.5453
    return x - Math.floor(x)
}

function easeOut(u) {
    var v = 1 - clamp(u, 0, 1)
    return 1 - v * v * v
}

// The index of the last entry of the sorted list `v` that is <= t (-1 if none).
function indexAt(v, t) {
    var lo = 0
    var hi = v.length - 1
    var ans = -1
    while (lo <= hi) {
        var mid = (lo + hi) >> 1
        if (v[mid] <= t) {
            ans = mid
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return ans
}

// ===== the looks =====
var STYLES = ["poster", "wall", "marquee"]

function isStyle(s) {
    return STYLES.indexOf(s) >= 0
}

// The look after `s` (for a key that cycles through them); an unknown one goes to the first.
function nextStyle(s) {
    return STYLES[(STYLES.indexOf(s) + 1) % STYLES.length]
}

// ===== the slow drift both looks share =====
// A hair of zoom over one line and back over the next, like the poster's camera, and a line
// starts where the one before it stopped so nothing jumps. `starts`: when each line starts.
var DRIFT = 0.035

function drift(starts, t) {
    var i = indexAt(starts, t)
    if (i < 0)
        return 1
    var span = i + 1 < starts.length ? starts[i + 1] - starts[i] : 6
    var p = clamp((t - starts[i]) / Math.max(0.05, span), 0, 1)
    return (i % 2 === 0) ? 1 + DRIFT * p : 1 + DRIFT - DRIFT * p
}

// ===================================================================== WALL =====
// The wall is one world, in pixels: line i is a block of type at (x0, y0) of size (w, h), the
// lines stacked top to bottom with a little air between, each against the left, the right or
// the middle of a column. The camera looks at one block at a time.
var WALL_SIZE = 0.15      // the type of a line, of the screen's height (each line is 0.8 - 1.5 of it)
var WALL_COLUMN = 0.92    // the widest a block gets, of the screen's width
var WALL_FIT_W = 0.84     // the line that is on fills this much of the screen's width...
var WALL_FIT_H = 0.6      // ...but never more than this much of its height
var WALL_Z_MIN = 0.5
var WALL_Z_MAX = 1.7
var WALL_GAP_EM = 0.3     // between words, in ems of the line's type
var WALL_ADLIB = 0.6      // an ad lib is this much of the line's type
var WALL_LEAD = 0.2       // the camera sets off this long before a line starts...
var WALL_MOVE = 0.7       // ...and takes this long to get there
var WALL_FOCUS = 0.35     // how long a line takes to light up / dim

// One line's block. `line`: { blank, ems: [em width of each word], adlib: [bool each] }.
function wallBlock(line, idx, W, H) {
    var base = H * WALL_SIZE
    var colW = W * WALL_COLUMN
    if (line.blank) {
        var s = base * 0.8
        return { blank: true, size: s, rowH: s * 1.1, w: s * 3.6, h: s * 1.1, align: 2, rows: [], rowW: [], words: [], zoom: 1.25 }
    }
    var n = line.ems.length
    var size = base * (0.8 + 0.7 * hash(idx * 3.1 + 0.7))
    function wpx(k, sz) {
        return line.ems[k] * (line.adlib[k] ? WALL_ADLIB : 1) * sz
    }
    function natural(sz) {
        var w = 0
        for (var k = 0; k < n; k++)
            w += wpx(k, sz)
        return w + Math.max(0, n - 1) * WALL_GAP_EM * sz
    }
    // one word is never wider than the column (a very long word is set smaller, not off the wall)
    var widestEm = 0
    for (var e = 0; e < n; e++)
        widestEm = Math.max(widestEm, line.ems[e] * (line.adlib[e] ? WALL_ADLIB : 1))
    if (widestEm * size > colW)
        size = colW / widestEm
    var nat = natural(size)
    var r = Math.max(1, Math.ceil(nat / colW))
    // a long line is set smaller so it takes two rows, not four
    if (r > 2) {
        size *= Math.max(0.6, 2 / r)
        nat = natural(size)
        r = Math.max(1, Math.ceil(nat / colW))
    }
    var gap = WALL_GAP_EM * size
    var widest = 0
    for (var q = 0; q < n; q++)
        widest = Math.max(widest, wpx(q, size))
    var limit = r === 1 ? colW : Math.min(colW, Math.max(widest, nat / r * 1.12))
    var rows = [[]]
    var rowW = [0]
    for (var k2 = 0; k2 < n; k2++) {
        var cur = rows.length - 1
        var add = (rows[cur].length > 0 ? gap : 0) + wpx(k2, size)
        if (rows[cur].length > 0 && rowW[cur] + add > limit) {
            rows.push([])
            rowW.push(0)
            cur++
            add = wpx(k2, size)
        }
        rows[cur].push(k2)
        rowW[cur] += add
    }
    var w = 0
    for (var m = 0; m < rowW.length; m++)
        w = Math.max(w, rowW[m])
    var rowH = size * 1.04
    var align = Math.floor(hash(idx * 5.3 + 2.1) * 3)
    // where each word's middle is, inside the block (the QML lays a row out from the words'
    // real widths; this is the same picture from the guessed ones)
    var words = []
    for (var a = 0; a < n; a++)
        words.push(null)
    for (var rr = 0; rr < rows.length; rr++) {
        var x = align === 0 ? 0 : (align === 1 ? w - rowW[rr] : (w - rowW[rr]) / 2)
        for (var c = 0; c < rows[rr].length; c++) {
            var kk = rows[rr][c]
            var ww = wpx(kk, size)
            words[kk] = { x: x + ww / 2, y: rr * rowH + rowH / 2, size: size * (line.adlib[kk] ? WALL_ADLIB : 1) }
            x += ww + gap
        }
    }
    var h = rows.length * rowH
    var zoom = clamp(Math.min(W * WALL_FIT_W / w, H * WALL_FIT_H / h), WALL_Z_MIN, WALL_Z_MAX)
    return { blank: false, size: size, rowH: rowH, w: w, h: h, align: align, rows: rows, rowW: rowW, words: words, zoom: zoom }
}

// The whole wall. `lines`: one { blank, ems, adlib } per line of the song. Returns
// { lines: [block + x0 y0 cx cy], width, height }.
function wallPlan(lines, W, H) {
    var out = []
    var colW = W * WALL_COLUMN
    var y = 0
    var air = H * WALL_SIZE * 0.3
    for (var i = 0; i < lines.length; i++) {
        var b = wallBlock(lines[i], i, W, H)
        b.x0 = b.align === 0 ? 0 : (b.align === 1 ? colW - b.w : (colW - b.w) / 2)
        b.y0 = y
        b.cx = b.x0 + b.w / 2
        b.cy = b.y0 + b.h / 2
        y += b.h + air
        out.push(b)
    }
    return { lines: out, width: colW, height: Math.max(0, y - air) }
}

// Where the camera is at time t: the world point on the middle of the screen and the zoom.
// Each line moves the camera from the one before it to itself over WALL_MOVE seconds, starting
// WALL_LEAD before it is sung, and the moves ADD UP (never "from where the camera was"), so
// a line that starts before the last move has finished bends the path instead of jumping.
// `drift` false: no slow zoom on top (the moves between lines are the look).
function wallCamera(plan, starts, t, withDrift) {
    var cams = plan.lines
    var n = cams.length
    if (n === 0 || starts.length < n)
        return { x: 0, y: 0, z: 1 }
    // the last line whose move has begun / has finished
    var k = indexAt(starts, t + WALL_LEAD)
    var j = Math.max(0, indexAt(starts, t + WALL_LEAD - WALL_MOVE))
    k = Math.max(k, j)
    var x = cams[j].cx
    var y = cams[j].cy
    var lz = Math.log(cams[j].zoom)
    for (var i = j + 1; i <= k; i++) {
        var s = easeOut((t - (starts[i] - WALL_LEAD)) / WALL_MOVE)
        x += s * (cams[i].cx - cams[i - 1].cx)
        y += s * (cams[i].cy - cams[i - 1].cy)
        lz += s * (Math.log(cams[i].zoom) - Math.log(cams[i - 1].zoom))
    }
    return { x: x, y: y, z: Math.exp(lz) * (withDrift ? drift(starts, t) : 1) }
}

// 0 .. 1: how much a line is "the one that is on": it lights up as the camera arrives and dims
// when the next line takes over.
function wallFocus(t, start, nextStart) {
    var a = easeOut((t - (start - WALL_LEAD * 0.5)) / WALL_FOCUS)
    var b = isFinite(nextStart) ? easeOut((t - (nextStart - WALL_LEAD * 0.5)) / WALL_FOCUS) : 0
    return a * (1 - b)
}

// How bright a line is. `d`: its place against the line that is on (-1 the one before...);
// `focus`: wallFocus(). The lines nearby are dim, the ones further off dimmer, the one that
// is on is full.
function wallShade(d, focus) {
    var rest = d < 0 ? Math.max(0.1, 0.34 - 0.07 * (-d - 1)) : (d > 0 ? Math.max(0.1, 0.3 - 0.06 * (d - 1)) : 0.34)
    return rest + (1 - rest) * clamp(focus, 0, 1)
}

// ----- the camera follows the WORD that is sung -----
var WALL_TILT = -2.2      // the wall is turned this many degrees...
var WALL_ROLL_MAX = 2.4   // ...and swings up to this much more while the camera is moving
var WALL_WLEAD = 0.12     // the camera sets off this long before a word is sung...
var WALL_WMOVE = 0.6      // ...and glides this long (moves add up, so words in a row blend)

// How far the camera pushes in on one word: it fills about half of the screen's width, but stays
// within 0.9 .. 1.9 times what the whole line needs (so a short word does not zoom to the moon).
function wallWordZoom(wordW, lineZoom, W) {
    var z = W * 0.5 / Math.max(1, wordW)
    return clamp(clamp(z, lineZoom * 0.9, lineZoom * 1.9), WALL_Z_MIN, 3.2)
}

// The camera over a list of waypoints `pts` ([{ t, x, y, lz }], sorted by t; lz is the log of
// the zoom): the world point on the middle of the screen and the zoom at time t. As in
// wallCamera the moves ADD UP (a waypoint's move is the step from the one before it), so a word
// that comes before the last move has finished bends the path instead of jumping.
function wallFollow(pts, t, lead, move) {
    var n = pts.length
    if (n === 0)
        return { x: 0, y: 0, z: 1 }
    var ts = []
    for (var q = 0; q < n; q++)
        ts.push(pts[q].t)
    var k = indexAt(ts, t + lead)
    var j = Math.max(0, indexAt(ts, t + lead - move))
    k = Math.max(k, j)
    var x = pts[j].x
    var y = pts[j].y
    var lz = pts[j].lz
    for (var i = j + 1; i <= k; i++) {
        var s = easeOut((t - (ts[i] - lead)) / move)
        x += s * (pts[i].x - pts[i - 1].x)
        y += s * (pts[i].y - pts[i - 1].y)
        lz += s * (pts[i].lz - pts[i - 1].lz)
    }
    return { x: x, y: y, z: Math.exp(lz) }
}

// How much the wall swings while the camera moves: `vx` is the camera's speed across the screen
// in pixels per second. Zero when it rests.
function wallRoll(vx) {
    return clamp(vx * 0.0011, -WALL_ROLL_MAX, WALL_ROLL_MAX)
}

// 0 .. 1: how lit a word is. It comes on just before it is sung, holds while it is sung and
// settles after (the caller keeps a sung word a little brighter than one still to come).
function wordGlow(from, to, t) {
    var up = clamp((t - (from - 0.12)) / 0.12, 0, 1)
    var down = clamp((t - Math.max(from, to)) / 0.5, 0, 1)
    return up * (1 - easeOut(down))
}

// The depth of a line: `d` lines away from the one that is on, it is smaller and blurrier.
// { scale, blur } (blur 0 .. 1; 0 = none).
function wallDepth(d) {
    var a = Math.abs(d)
    return { scale: Math.max(0.72, 1 - 0.09 * a), blur: a === 0 ? 0 : Math.min(1, 0.3 + 0.2 * a) }
}

// ================================================================== MARQUEE =====
// The marquee is a few rows over the whole height, each a strip of the line's words and a
// diamond, repeated end to end, scrolling one way and the next row the other.
var MARQ_GAP_EM = 0.3     // between words, in ems of the row's type
var MARQ_SEP_EM = 0.5     // the room the diamond between two repeats takes, in ems
var MARQ_ADLIB = 0.6

// The rows: one big HERO row in the middle (it follows the voice and carries the sung word) between
// smaller rows of texture (hollow, faint, sliding past), the biggest in the middle and the
// smallest at the top and bottom. Returns [{ y (top), rowH, px (type size), dir (-1 left, 1 right),
// speed (px/s, 0 for the hero), seed, hero, alpha (how visible the whole row is), kind }].
function marqueeRows(W, H) {
    var weights = H < 600 ? [0.25, 0.5, 0.25] : [0.13, 0.19, 0.36, 0.19, 0.13]
    var n = weights.length
    var mid = (n - 1) / 2
    var rows = []
    var y = 0
    for (var r = 0; r < n; r++) {
        var rh = r === n - 1 ? H - y : H * weights[r]
        var d = Math.abs(r - mid)
        rows.push({
            y: y,
            rowH: rh,
            px: Math.round(rh * 0.74),
            dir: d % 2 === 0 ? -1 : 1,
            speed: d === 0 ? 0 : W * (d === 1 ? 0.03 : 0.02),
            seed: hash(r * 2.7 + 1.3),
            hero: d === 0,
            alpha: d === 0 ? 1 : (d === 1 ? 0.5 : 0.3),
            kind: d === 0 ? 1 : 0
        })
        y += rh
    }
    return rows
}

// What one repeat of the line (its words, the gaps and the diamond) is wide, guessed, plus the
// gap before the next repeat. `ems` / `adlib` as in wallBlock.
function marqueePeriod(ems, adlib, px) {
    var w = 0
    for (var k = 0; k < ems.length; k++)
        w += ems[k] * (adlib[k] ? MARQ_ADLIB : 1) * px
    return w + (ems.length + 1) * MARQ_GAP_EM * px + MARQ_SEP_EM * px
}

// How many repeats a strip is built with so it covers the screen while it slides by one
// repeat. The period is a guess, so it is taken a fifth short (more repeats, never gaps).
function marqueeUnits(period, W) {
    return clamp(Math.ceil(W / Math.max(1, period * 0.8)) + 1, 2, 30)
}

// Where the strip's left end is, in pixels (-period .. 0 going left, -period .. 0 going right
// too, taken from the other end), at time t. `period`: the real width of one repeat.
function marqueeX(t, speed, seed, dir, period) {
    var p = Math.max(1, period)
    var ph = (((t * speed + seed * p) % p) + p) % p
    return dir < 0 ? -ph : ph - p
}

// How a row of the line comes and goes. Each row comes in from the side its strip is
// moving away from and leaves the way it moves, one row after another. { ox, op }
function marqueeAt(t, lineStart, leaveAt, r, dir, W) {
    var u = clamp((t - lineStart - r * 0.045) / 0.5, 0, 1)
    var e = easeOut(u)
    var lu = clamp((t - leaveAt - r * 0.04) / 0.38, 0, 1)
    var q = lu * lu
    return {
        ox: -dir * W * 0.45 * (1 - e) + dir * W * 0.5 * q,
        op: clamp(u * 2.5, 0, 1) * (1 - Math.pow(lu, 1.4))
    }
}

// ===== the hero row follows the voice =====
// Where the strip should be centred: `froms` is when each word of the line starts to be sung and
// `mids` where each word's middle is along the strip (px). The point glides from word to word,
// easing in and out, so the word that is sung sits in the middle of the screen.
function voiceFollow(froms, mids, t) {
    var n = Math.min(froms.length, mids.length)
    if (n === 0)
        return 0
    var k = -1
    for (var i = 0; i < n; i++) {
        if (froms[i] <= t)
            k = i
    }
    if (k < 0)
        return mids[0]
    if (k >= n - 1)
        return mids[n - 1]
    var span = Math.max(0.05, froms[k + 1] - froms[k])
    var u = clamp((t - froms[k]) / span, 0, 1)
    var e = u * u * (3 - 2 * u)
    return mids[k] + (mids[k + 1] - mids[k]) * e
}

// The strip's left end when the point `target` (screen x) should be where the voice is: the strip
// repeats every `period`, so any repeat will do and it is kept within one period of 0.
function heroX(target, period) {
    var p = Math.max(1, period)
    return (((target % p) + p) % p) - p
}
