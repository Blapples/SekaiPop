.pragma library

// The maths behind the kinetic lyrics (modules/sekai/desktopWidgets/LyricsKinetic.qml): where
// each word of a line goes on the WHOLE screen, how it slams in when it is sung, how the line
// leaves, and how the camera moves. No QML in here, so tests/lyrics-test/kinetic_unit.js can
// run it with node.
//
// Everything is a pure function of the lyrics clock `t` (seconds) and the line, never of
// "what happened last frame", so a pause freezes the picture and a seek lands in the right
// place, like LyricsMath.js.
//
// Words are described by LyricsMath.tokens(): { s, gap, adlib? }. Their times come from
// LyricsMath.spansFor(): { from, to }.

// ===== a little deterministic noise =====
// The same line always gets the same layout (no Math.random: a reload, a seek back and a
// second monitor all see the same picture).
function hash(n) {
    var x = Math.sin(n * 127.1 + 311.7) * 43758.5453
    return x - Math.floor(x)
}

function clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v)
}

function lerp(a, b, u) {
    return a + (b - a) * u
}

// ===== how wide a word is =====
// The widths are guessed before anything is drawn (a layout has to be known before the words
// are built), from a rough width of each letter in the shell's extra bold font, in ems.
// Words are placed by their MIDDLE, so a guess that is a little off only changes the spacing.
var NARROW = "il.,;:'!|ijtf\u2019\u2018I"
var MID = "rJ()-\u2014"
var WIDE = "mwMW@%"

function charEm(c) {
    var code = c.charCodeAt(0)
    // Japanese, Chinese and Korean letters are square.
    if ((code >= 0x3040 && code <= 0x30ff) || (code >= 0x3400 && code <= 0x9fff)
            || (code >= 0xac00 && code <= 0xd7af) || (code >= 0xff00 && code <= 0xffef))
        return 1.0
    if (NARROW.indexOf(c) >= 0)
        return 0.36
    if (MID.indexOf(c) >= 0)
        return 0.5
    if (WIDE.indexOf(c) >= 0)
        return 0.98
    if (c >= "0" && c <= "9")
        return 0.64
    if (c >= "A" && c <= "Z")
        return 0.74
    return 0.6
}

// A word's width in ems (a word 1 px tall is this many px wide), with the room the sticker's
// outline and hard shadow take on its two sides (0.2 em).
function wordEm(s) {
    var w = 0
    for (var i = 0; i < s.length; i++)
        w += charEm(s.charAt(i))
    return Math.max(0.5, w * 1.05 + 0.2)
}

// Word boxes are this much taller than the font size (the sticker's outline and shadow).
var BOX_H = 1.22
var GAP_EM = 0.3

// ===== which word matters most =====
// Longer words and the last word of the tune are drawn bigger; ad libs are small.
function weights(toks) {
    var w = []
    var longest = -1
    var most = 0
    var last = -1
    for (var i = 0; i < toks.length; i++) {
        if (toks[i].adlib)
            continue
        last = i
        if (toks[i].s.length >= most) {
            most = toks[i].s.length
            longest = i
        }
    }
    for (var k = 0; k < toks.length; k++) {
        if (toks[k].adlib) {
            w.push(0.42)
            continue
        }
        var n = Math.min(1, toks[k].s.length / 7)
        var v = 0.78 + 0.42 * n
        if (k === longest)
            v *= 1.18
        if (k === last)
            v *= 1.12
        w.push(v)
    }
    return w
}

function mainIndexes(toks) {
    var out = []
    for (var i = 0; i < toks.length; i++) {
        if (!toks[i].adlib)
            out.push(i)
    }
    return out
}

function longestOf(toks, idx) {
    var best = idx.length > 0 ? idx[0] : 0
    for (var i = 0; i < idx.length; i++) {
        if (toks[idx[i]].s.length >= toks[best].s.length)
            best = idx[i]
    }
    return best
}

// ===== the styles =====
// `giant`  one word fills the screen and the rest sit small above and below it
// `stack`  one word a row, left or right, staggered
// `slash`  along a tilted line
// `burst`  the big word in the middle, the rest thrown round it
// `flow`   a few rows, like a poster block, a little crooked
// `arc`    along a rainbow
var STYLE_LISTS = {
    1: ["giant", "burst"],
    2: ["giant", "stack", "burst", "slash"],
    3: ["stack", "slash", "burst", "giant", "arc"],
    4: ["slash", "stack", "arc", "burst", "flow", "giant"],
    5: ["flow", "stack", "slash", "arc", "burst", "giant"],
    6: ["flow", "slash", "stack", "burst"],
    7: ["flow", "burst", "slash"]
}

function styleFor(idx, nMain) {
    var n = Math.max(1, nMain)
    var list = n > 7 ? ["flow"] : STYLE_LISTS[n]
    // Neighbouring lines walk along the list, so two in a row are never the same style (while
    // the list is the same), and the order is not the same every verse.
    var i = Math.max(0, idx)
    var pick = (i + Math.floor(i / list.length)) % list.length
    return list[pick]
}

// A word's box before it is placed: its middle, size (font px), tilt.
function box(x, y, size, rot) {
    return { x: x, y: y, size: size, rot: rot || 0 }
}

// Width of word i at font size `size`.
function widthOf(toks, i, size) {
    return wordEm(toks[i].s) * size
}

// ----- giant -----
function layGiant(toks, idx, W, H, k, out) {
    var hero = longestOf(toks, idx)
    var sizeH = Math.min(H * 0.34, (W * 0.84) / wordEm(toks[hero].s))
    var cy = H * 0.5
    var before = []
    var after = []
    for (var i = 0; i < idx.length; i++) {
        if (idx[i] < hero)
            before.push(idx[i])
        else if (idx[i] > hero)
            after.push(idx[i])
    }
    var hasBefore = before.length > 0
    var hasAfter = after.length > 0
    // The hero sits a little off the middle when only one side has words.
    var heroY = cy + (hasBefore && !hasAfter ? H * 0.07 : (!hasBefore && hasAfter ? -H * 0.07 : 0))
    out[hero] = box(W / 2, heroY, sizeH, (hash(k + 1) - 0.5) * 6)
    function row(list, y, dir) {
        if (list.length === 0)
            return
        var em = 0
        for (var a = 0; a < list.length; a++)
            em += wordEm(toks[list[a]].s) + (a > 0 ? GAP_EM : 0)
        var s = Math.min(sizeH * 0.34, H * 0.12, (W * 0.78) / em)
        var x = W / 2 - (em * s) / 2
        for (var b = 0; b < list.length; b++) {
            var wd = wordEm(toks[list[b]].s) * s
            out[list[b]] = box(x + wd / 2, y + (b % 2 === 0 ? 0 : s * 0.12), s, dir * 3 + (hash(k + b * 3) - 0.5) * 4)
            x += wd + GAP_EM * s
        }
    }
    row(before, heroY - sizeH * 0.5 - H * 0.075, -1)
    row(after, heroY + sizeH * 0.5 + H * 0.075, 1)
}

// ----- stack -----
function layStack(toks, idx, W, H, k, out) {
    var w = weights(toks)
    var left = (k % 2) === 0
    var sumH = 0
    var maxEm = 0
    for (var i = 0; i < idx.length; i++) {
        sumH += w[idx[i]] * 0.96
        maxEm = Math.max(maxEm, w[idx[i]] * wordEm(toks[idx[i]].s))
    }
    var S = Math.min(H * 0.34, (H * 0.74) / sumH, (W * 0.72) / maxEm)
    var y = H / 2 - (sumH * S) / 2
    var mx = W * 0.09
    var stag = Math.min(W * 0.05, S * 0.35)
    for (var j = 0; j < idx.length; j++) {
        var t = idx[j]
        var s = S * w[t]
        var wd = wordEm(toks[t].s) * s
        var h = s * 0.96
        var off = (j % 2 === 0 ? 0 : stag) + (hash(k * 5 + j) - 0.5) * stag * 0.4
        var x = left ? mx + off + wd / 2 : W - mx - off - wd / 2
        out[t] = box(x, y + h / 2, s, (left ? -1 : 1) * (2 + hash(k + j) * 2.5))
        y += h
    }
}

// ----- slash -----
function laySlash(toks, idx, W, H, k, out) {
    var ang = (7 + hash(k * 3.3) * 7) * (k % 2 === 0 ? -1 : 1)
    var th = ang * Math.PI / 180
    var c = Math.cos(th)
    var sn = Math.sin(th)
    var w = weights(toks)
    // One row if it can be big, two when the line is long.
    var rows = idx.length > 4 ? 2 : 1
    var groups = rows === 1 ? [idx] : [idx.slice(0, Math.ceil(idx.length / 2)), idx.slice(Math.ceil(idx.length / 2))]
    var S = H * 0.2
    for (var g = 0; g < groups.length; g++) {
        var em = 0
        for (var a = 0; a < groups[g].length; a++)
            em += w[groups[g][a]] * wordEm(toks[groups[g][a]].s) + (a > 0 ? GAP_EM : 0)
        S = Math.min(S, (W * 0.86) / (em * c))
    }
    for (var r = 0; r < groups.length; r++) {
        var list = groups[r]
        var total = 0
        for (var b = 0; b < list.length; b++)
            total += w[list[b]] * wordEm(toks[list[b]].s) * S + (b > 0 ? GAP_EM * S : 0)
        // the row's middle, with the second row down the page and a little along it
        var perp = (r - (groups.length - 1) / 2) * S * 1.18
        var mx = W / 2 - sn * perp + (r === 1 ? S * 0.35 : 0)
        var my = H / 2 + c * perp
        var pos = -total / 2
        for (var d = 0; d < list.length; d++) {
            var t = list[d]
            var s = S * w[t]
            var wd = wordEm(toks[t].s) * s
            var along = pos + wd / 2
            out[t] = box(mx + c * along, my + sn * along, s, ang + (hash(k + d * 2) - 0.5) * 3)
            pos += wd + GAP_EM * S
        }
    }
}

// ----- burst -----
function layBurst(toks, idx, W, H, k, out) {
    var hero = longestOf(toks, idx)
    var sizeH = Math.min(H * 0.3, (W * 0.42) / wordEm(toks[hero].s))
    out[hero] = box(W / 2, H / 2, sizeH, (hash(k + 4) - 0.5) * 10)
    var others = []
    for (var i = 0; i < idx.length; i++) {
        if (idx[i] !== hero)
            others.push(idx[i])
    }
    var n = others.length
    var a0 = hash(k * 2.1) * Math.PI * 2
    for (var j = 0; j < n; j++) {
        var t = others[j]
        var ang = a0 + (j + 0.5) * (Math.PI * 2) / Math.max(1, n)
        var s = Math.min(sizeH * (0.4 + 0.2 * hash(k + j * 7)), H * 0.15, (W * 0.2) / wordEm(toks[t].s))
        var rx = W * 0.5 - s * 0.7 - W * 0.07
        var ry = H * 0.5 - s * 0.7 - H * 0.06
        out[t] = box(W / 2 + Math.cos(ang) * rx * 0.96, H / 2 + Math.sin(ang) * ry * 0.96, s, (hash(k + j * 3) - 0.5) * 30)
    }
}

// ----- flow -----
function layFlow(toks, idx, W, H, k, out) {
    var w = weights(toks)
    var maxW = W * 0.84
    var S = H * 0.2
    var rows = []
    for (; S > H * 0.05; S *= 0.92) {
        rows = []
        var cur = []
        var curW = 0
        for (var i = 0; i < idx.length; i++) {
            var wd = w[idx[i]] * wordEm(toks[idx[i]].s) * S
            var add = (cur.length > 0 ? GAP_EM * S : 0) + wd
            if (cur.length > 0 && curW + add > maxW) {
                rows.push(cur)
                cur = []
                curW = 0
                add = wd
            }
            cur.push(idx[i])
            curW += add
        }
        if (cur.length > 0)
            rows.push(cur)
        // Wide enough to be a poster, in at most three rows (more for a long line), and short
        // enough to fit.
        var tall = rows.length * S * 1.02
        var maxRows = idx.length > 9 ? 4 : 3
        if (rows.length <= maxRows && tall <= H * 0.74)
            break
    }
    var tallAll = rows.length * S * 1.02
    var y = H / 2 - tallAll / 2
    for (var r = 0; r < rows.length; r++) {
        var list = rows[r]
        var total = 0
        for (var b = 0; b < list.length; b++)
            total += w[list[b]] * wordEm(toks[list[b]].s) * S + (b > 0 ? GAP_EM * S : 0)
        var shift = (r % 2 === 0 ? -1 : 1) * Math.min(W * 0.04, (W - total) / 2 * 0.5) * (k % 2 === 0 ? 1 : -1)
        var x = W / 2 - total / 2 + shift
        var tilt = (r % 2 === 0 ? -1 : 1) * (1.5 + hash(k + r) * 2) * (k % 2 === 0 ? 1 : -1)
        for (var d = 0; d < list.length; d++) {
            var t = list[d]
            var s = S * w[t]
            var wd2 = wordEm(toks[t].s) * s
            out[t] = box(x + wd2 / 2, y + S * 0.51 + (hash(k * 3 + d + r) - 0.5) * S * 0.1, s, tilt + (hash(k + d * 5) - 0.5) * 5)
            x += wd2 + GAP_EM * S
        }
        y += S * 1.02
    }
}

// ----- arc -----
function layArc(toks, idx, W, H, k, out) {
    var w = weights(toks)
    var flip = (k % 2) === 1
    var R = Math.min(H * 0.58, W * 0.33)
    var em = 0
    for (var i = 0; i < idx.length; i++)
        em += w[idx[i]] * wordEm(toks[idx[i]].s) + (i > 0 ? GAP_EM : 0)
    // The arc may span about 150 degrees.
    var S = Math.min(H * 0.2, (R * 2.6) / em)
    var span = (em * S) / R
    var cx = W / 2
    var cy = flip ? H * 0.5 - R * 0.62 : H * 0.5 + R * 0.62
    var pos = -span / 2
    for (var j = 0; j < idx.length; j++) {
        var t = idx[j]
        var s = S * w[t]
        var wd = wordEm(toks[t].s) * s
        var mid = pos + wd / R / 2
        // 0 = straight up (or down when flipped)
        var x = cx + Math.sin(mid) * R
        var y = flip ? cy + Math.cos(mid) * R : cy - Math.cos(mid) * R
        out[t] = box(x, y, s, flip ? -mid * 180 / Math.PI : mid * 180 / Math.PI)
        pos += (wd + GAP_EM * S) / R
    }
}

// ===== ad libs and a second voice =====
// Small, in the corners the line leaves free.
function layAdlibs(toks, W, H, k, out) {
    var n = 0
    for (var i = 0; i < toks.length; i++) {
        if (!toks[i].adlib)
            continue
        var s = Math.min(H * 0.075, (W * 0.2) / wordEm(toks[i].s))
        var right = (n + k) % 2 === 0
        var top = (Math.floor((n + k) / 2)) % 2 === 0
        var x = right ? W - W * 0.09 - (wordEm(toks[i].s) * s) / 2 : W * 0.09 + (wordEm(toks[i].s) * s) / 2
        var y = top ? H * 0.12 : H * 0.88
        out[i] = box(x, y, s, (right ? 1 : -1) * (5 + hash(k + n) * 5))
        n++
    }
}

// ===== keeping every word on the screen and apart =====
// Rotated boxes are measured by their outline on the screen.
function bounds(b, toks, i) {
    var wd = wordEm(toks[i].s) * b.size
    var h = b.size * BOX_H
    var r = Math.abs(b.rot) * Math.PI / 180
    var bw = wd * Math.cos(r) + h * Math.sin(r)
    var bh = wd * Math.sin(r) + h * Math.cos(r)
    return { l: b.x - bw / 2, r: b.x + bw / 2, t: b.y - bh / 2, b: b.y + bh / 2, w: bw, h: bh }
}

function overlap(a, b, shrink) {
    // `shrink` < 1 is a tolerance: sticker words may kiss, not cover each other
    var ax = (a.l + a.r) / 2, ay = (a.t + a.b) / 2
    var bx = (b.l + b.r) / 2, by = (b.t + b.b) / 2
    var ox = (a.w + b.w) / 2 * shrink - Math.abs(ax - bx)
    var oy = (a.h + b.h) / 2 * shrink - Math.abs(ay - by)
    return (ox > 0 && oy > 0) ? { ox: ox, oy: oy } : null
}

function settle(words, toks, W, H) {
    // (the camera pushes in by up to 9 per cent, so the words keep clear of the edge)
    var mx = W * 0.055
    var my = H * 0.07
    var shown = []
    for (var i = 0; i < toks.length; i++) {
        if (words[i])
            shown.push(i)
    }
    for (var pass = 0; pass < 24; pass++) {
        var moved = false
        // keep on the screen: shrink a word that is too big for it, then shift it back in
        for (var a = 0; a < shown.length; a++) {
            var i2 = shown[a]
            var bx = bounds(words[i2], toks, i2)
            if (bx.w > W - 2 * mx || bx.h > H - 2 * my) {
                words[i2].size *= Math.min((W - 2 * mx) / bx.w, (H - 2 * my) / bx.h) * 0.98
                bx = bounds(words[i2], toks, i2)
                moved = true
            }
            var dx = 0
            var dy = 0
            if (bx.l < mx) dx = mx - bx.l
            else if (bx.r > W - mx) dx = W - mx - bx.r
            if (bx.t < my) dy = my - bx.t
            else if (bx.b > H - my) dy = H - my - bx.b
            if (dx !== 0 || dy !== 0) {
                words[i2].x += dx
                words[i2].y += dy
                moved = true
            }
        }
        // keep apart: the smaller of two words that cover each other gives way
        for (var p = 0; p < shown.length; p++) {
            for (var q = p + 1; q < shown.length; q++) {
                var bp = bounds(words[shown[p]], toks, shown[p])
                var bq = bounds(words[shown[q]], toks, shown[q])
                var ov = overlap(bp, bq, 0.86)
                if (!ov)
                    continue
                var small = words[shown[p]].size <= words[shown[q]].size ? words[shown[p]] : words[shown[q]]
                var big = small === words[shown[p]] ? words[shown[q]] : words[shown[p]]
                small.size *= 0.93
                // and a nudge away from the big one along the shorter way out
                if (ov.oy < ov.ox)
                    small.y += (small.y >= big.y ? 1 : -1) * ov.oy * 0.5
                else
                    small.x += (small.x >= big.x ? 1 : -1) * ov.ox * 0.5
                moved = true
            }
        }
        if (!moved)
            break
    }
}

// ===== how words come and go =====
// `in`: where a word starts from when it slams in { ox, oy } (px from its place), the scale it
// starts at and the tilt it starts with. `out`: where it ends up when the line leaves.
function motionFor(style, b, W, H, k, i, n) {
    var side = (k % 2 === 0) ? -1 : 1
    var rnd = hash(k * 11 + i * 3)
    var enter
    var leave
    var cx = W / 2
    var cy = H / 2
    switch (style) {
    case "stack":
        enter = { ox: side * W * (0.3 + 0.12 * rnd), oy: 0, s0: 1.0, r0: side * 4 }
        leave = { dx: -side * W * 0.7, dy: 0, s1: 1.0, r1: -side * 6 }
        break
    case "slash": {
        var th = b.rot * Math.PI / 180
        enter = { ox: -Math.cos(th) * W * 0.3, oy: -Math.sin(th) * W * 0.3, s0: 0.6, r0: 0 }
        leave = { dx: Math.cos(th) * W * 0.6, dy: Math.sin(th) * W * 0.6, s1: 0.7, r1: 0 }
        break
    }
    case "burst":
        enter = { ox: 0, oy: 0, s0: 3.0 + rnd, r0: (rnd - 0.5) * 50 }
        leave = { dx: (b.x - cx) * 1.5, dy: (b.y - cy) * 1.5, s1: 1.9, r1: (rnd - 0.5) * 90 }
        break
    case "giant":
        if (b.size > H * 0.2) {
            enter = { ox: 0, oy: 0, s0: 0.12, r0: side * 10 }
            leave = { dx: 0, dy: 0, s1: 4.2, r1: side * -4 }
        } else {
            enter = { ox: 0, oy: (b.y < cy ? -1 : 1) * H * 0.22, s0: 0.7, r0: 0 }
            leave = { dx: 0, dy: (b.y < cy ? -1 : 1) * H * 0.4, s1: 0.8, r1: 0 }
        }
        break
    case "arc":
        enter = { ox: (b.x - cx) * 0.55, oy: (b.y - cy) * 0.55, s0: 0.4, r0: side * 30 }
        leave = { dx: (b.x - cx) * 1.1, dy: (b.y - cy) * 1.1, s1: 1.4, r1: side * 40 }
        break
    default: // flow
        enter = { ox: 0, oy: H * (0.26 + 0.1 * rnd), s0: 0.9, r0: (rnd - 0.5) * 44 }
        leave = { dx: (rnd - 0.5) * W * 0.12, dy: H * 0.5, s1: 0.9, r1: (rnd - 0.5) * 60 }
    }
    return { enter: enter, leave: leave }
}

// The whole plan for a line: [{ x, y, size, rot, enter, leave }] per token, and its style.
function plan(toks, idx, W, H) {
    var out = new Array(toks.length)
    var main = mainIndexes(toks)
    var style = styleFor(idx, main.length)
    // (a line that is nothing but ad libs is laid out as a line of its own)
    var laidOut = main
    if (main.length === 0) {
        laidOut = []
        for (var q = 0; q < toks.length; q++)
            laidOut.push(q)
        style = "flow"
    }
    var asMain = toks
    if (main.length === 0) {
        asMain = toks.map(function (t) { return { s: t.s, gap: t.gap } })
    }
    switch (style) {
    case "giant": layGiant(asMain, laidOut, W, H, idx, out); break
    case "stack": layStack(asMain, laidOut, W, H, idx, out); break
    case "slash": laySlash(asMain, laidOut, W, H, idx, out); break
    case "burst": layBurst(asMain, laidOut, W, H, idx, out); break
    case "arc": layArc(asMain, laidOut, W, H, idx, out); break
    default: layFlow(asMain, laidOut, W, H, idx, out)
    }
    if (main.length > 0)
        layAdlibs(toks, W, H, idx, out)
    settle(out, toks, W, H)
    var words = []
    for (var i = 0; i < toks.length; i++) {
        var b = out[i] || box(W / 2, H / 2, H * 0.1, 0)
        var m = motionFor(style, b, W, H, idx, i, toks.length)
        words.push({ x: b.x, y: b.y, size: Math.max(10, Math.round(b.size)), rot: b.rot, enter: m.enter, leave: m.leave })
    }
    return { style: style, words: words }
}

// ===== time =====
var ENTER_S = 0.3
var LEAVE_S = 0.34
var LEAVE_STAGGER = 0.035

// An overshooting ease: 0 -> 1 with a bounce past 1 on the way (k = how much).
function backOut(u, k) {
    var v = clamp(u, 0, 1)
    var c3 = k + 1
    return 1 + c3 * Math.pow(v - 1, 3) + k * Math.pow(v - 1, 2)
}

// When a line starts to leave: a moment after it has been sung, but before the next line
// starts (the next one takes the screen when it starts, and a line that is still being sung
// then is cut off rather than being left under it).
function leaveStart(lineStart, lineEnd, nextStart, nextIsGap) {
    var want = lineEnd + (nextIsGap ? 0.35 : 0.22)
    if (!isFinite(nextStart))
        return lineEnd + 1.1
    var cap = nextStart - LEAVE_S * 0.55
    return Math.max(lineStart + 0.35, Math.min(want, cap))
}

// One word at time t. `from` / `to`: when it is sung. `leaveAt`: when its line starts to
// leave. `order` / `count`: its place in the line, for the leaving stagger.
//   started  it has been sung (or the line is leaving)
//   ox oy    where it is, as an offset from its place (px)
//   s        scale, rot extra tilt in degrees, op opacity
//   hit      1 the moment it is sung, 0 a moment later (the squash)
//   ring     0 the moment it is sung, 1 half a second later (the shockwave ring round it)
//   sung     0 .. 1 how far the colour has filled it
function wordAt(t, from, to, motion, leaveAt, order, count, lineOnly) {
    var leaving = t >= leaveAt
    var started = t >= from || leaving
    var u = clamp((t - from) / ENTER_S, 0, 1)
    var e = started ? backOut(u, 1.9) : 0
    var en = motion.enter
    var ox = en.ox * (1 - e)
    var oy = en.oy * (1 - e)
    var s = lerp(en.s0, 1, e)
    var rot = en.r0 * (1 - e)
    var op = started ? clamp((t - from) / 0.05 + (leaving ? 1 : 0), 0, 1) : 0
    var hit = (started && !leaving) ? Math.max(0, 1 - (t - from) / 0.24) : 0
    var ring = (started && !leaving) ? clamp((t - from) / 0.55, 0, 1) : 1
    var sung = lineOnly ? clamp((t - from) / 0.18, 0, 1) : (to > from ? clamp((t - from) / (to - from), 0, 1) : (t >= to ? 1 : 0))
    if (leaving) {
        sung = 1
        var lu = clamp((t - leaveAt - order * LEAVE_STAGGER) / LEAVE_S, 0, 1)
        var q = lu * lu
        var lv = motion.leave
        ox += lv.dx * q
        oy += lv.dy * q
        s = lerp(1, lv.s1, q) * (u >= 1 ? 1 : s)
        rot += lv.r1 * q
        op = 1 - Math.pow(lu, 1.6)
    }
    return { started: started, ox: ox, oy: oy, s: s, rot: rot, op: op, hit: hit, ring: ring, sung: sung, gone: leaving && op <= 0.001 }
}

// ===== the camera =====
// It drifts in (or out) slowly over a line and tilts a hair, and that is all: nothing on the
// screen pulses with the beat of a word (the words move, the screen does not). A line starts
// where the one before it stopped, so the picture never jumps. `LyricsService.kineticCamera`
// = "still" ignores this and keeps the camera fixed.
function camera(t, lineStart, leaveAt, idx, W) {
    var span = Math.max(0.5, leaveAt - lineStart)
    var p = clamp((t - lineStart) / span, 0, 1)
    var dir = (idx % 2 === 0) ? 1 : -1
    return {
        scale: dir > 0 ? 1 + 0.03 * p : 1.03 - 0.03 * p,
        rot: dir * 0.4 * (p - 0.5),
        dx: -dir * W * 0.008 * (p - 0.5)
    }
}
