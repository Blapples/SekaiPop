.pragma library

// The palette tool's colour maths (modules/sekai/palette/*), as plain numbers and
// strings so it can be unit-tested without a Quickshell runtime
// (tests/palette-test/palette_unit.js).
//
// A palette is five "#rrggbb" strings. Nothing here touches the theme: `toShell`
// only RETURNS the shell palette a set of five colours would make. The preview
// draws with it, and ThemeService wears it only after an explicit Apply, so what
// you see in the preview is exactly what Apply gives.

var SLOTS = 5

// ===== hex / rgb / hsl =====
function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v) }

// "#abc", "abc", "AABBCC", "#AABBCC" -> "#aabbcc", or "" when it is not a colour.
function norm(s) {
    var t = String(s === undefined || s === null ? "" : s).trim().toLowerCase()
    if (t.charAt(0) === "#") t = t.slice(1)
    if (/^[0-9a-f]{3}$/.test(t)) t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2)
    return /^[0-9a-f]{6}$/.test(t) ? "#" + t : ""
}

function toRgb(hex) {
    var h = norm(hex) || "#000000"
    return { r: parseInt(h.substr(1, 2), 16), g: parseInt(h.substr(3, 2), 16), b: parseInt(h.substr(5, 2), 16) }
}

function fromRgb(r, g, b) {
    function p(v) {
        var n = Math.round(clamp(Number(v) || 0, 0, 255)).toString(16)
        return n.length < 2 ? "0" + n : n
    }
    return "#" + p(r) + p(g) + p(b)
}

// Qt colour values (r, g, b in 0..1) -> hex.
function fromQt(c) { return fromRgb(c.r * 255, c.g * 255, c.b * 255) }

function toHsl(hex) {
    var c = toRgb(hex)
    var r = c.r / 255, g = c.g / 255, b = c.b / 255
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b)
    var l = (mx + mn) / 2, h = 0, s = 0
    var d = mx - mn
    if (d > 0) {
        s = d / (1 - Math.abs(2 * l - 1))
        if (mx === r) h = ((g - b) / d) % 6
        else if (mx === g) h = (b - r) / d + 2
        else h = (r - g) / d + 4
        h *= 60
        if (h < 0) h += 360
    }
    return { h: h, s: clamp(s, 0, 1), l: l }
}

function fromHsl(h, s, l) {
    h = ((h % 360) + 360) % 360
    s = clamp(s, 0, 1)
    l = clamp(l, 0, 1)
    var c = (1 - Math.abs(2 * l - 1)) * s
    var x = c * (1 - Math.abs((h / 60) % 2 - 1))
    var m = l - c / 2
    var r = 0, g = 0, b = 0
    if (h < 60) { r = c; g = x }
    else if (h < 120) { r = x; g = c }
    else if (h < 180) { g = c; b = x }
    else if (h < 240) { g = x; b = c }
    else if (h < 300) { r = x; b = c }
    else { r = c; b = x }
    return fromRgb((r + m) * 255, (g + m) * 255, (b + m) * 255)
}

// Straight blend in sRGB: t = 0 is a, t = 1 is b.
function mix(a, b, t) {
    var x = toRgb(a), y = toRgb(b)
    return fromRgb(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t)
}

// ===== contrast / distance =====
function lum(hex) {
    var c = toRgb(hex)
    function ch(v) {
        v /= 255
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
}

function contrast(a, b) {
    var x = lum(a), y = lum(b)
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

// Dark ink or white, whichever reads better on `hex` (labels on a swatch).
function textOn(hex) {
    return contrast(hex, "#ffffff") >= contrast(hex, "#1b1a2b") ? "#ffffff" : "#1b1a2b"
}

function lab(hex) {
    var c = toRgb(hex)
    function lin(v) {
        v /= 255
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    }
    var r = lin(c.r), g = lin(c.g), b = lin(c.b)
    var x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    var y = (r * 0.2126 + g * 0.7152 + b * 0.0722)
    var z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
    function f(t) { return t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116 }
    return { L: 116 * f(y) - 16, a: 500 * (f(x) - f(y)), b: 200 * (f(y) - f(z)) }
}

// How different two colours look (CIE76 delta E; ~2 is "just noticeable").
function dist(a, b) {
    var x = lab(a), y = lab(b)
    return Math.sqrt((x.L - y.L) * (x.L - y.L) + (x.a - y.a) * (x.a - y.a) + (x.b - y.b) * (x.b - y.b))
}

// ===== picking five from what the image gave =====
// `list` is whatever a colour quantizer returned (hex strings, any number of them,
// duplicates and rubbish allowed). Returns exactly `count` hex colours, dark to light:
// the most vivid one first, then each next colour is the one furthest from those
// already chosen (a plain greys-only picture still gets a spread of lightnesses).
// Fewer distinct colours than `count` -> the missing ones are lighter / darker
// variants of what there is, so the strip is never short.
function pick(list, count) {
    count = count || SLOTS
    var seen = []
    for (var i = 0; i < (list || []).length; i++) {
        var h = norm(list[i])
        if (h === "") continue
        var dup = false
        for (var j = 0; j < seen.length; j++)
            if (dist(h, seen[j]) < 6) { dup = true; break }
        if (!dup) seen.push(h)
    }
    if (seen.length === 0) seen.push("#6e6d94")

    function score(h) {
        var l = lab(h)
        var chroma = Math.sqrt(l.a * l.a + l.b * l.b) / 100
        return chroma * 0.7 + (1 - Math.abs(l.L - 55) / 55) * 0.3
    }

    var chosen = []
    var best = 0
    for (var k = 1; k < seen.length; k++)
        if (score(seen[k]) > score(seen[best])) best = k
    chosen.push(seen.splice(best, 1)[0])

    while (chosen.length < count && seen.length > 0) {
        var bi = 0, bv = -1
        for (var m = 0; m < seen.length; m++) {
            var near = 1e9
            for (var n = 0; n < chosen.length; n++) near = Math.min(near, dist(seen[m], chosen[n]))
            var v = near * (0.6 + score(seen[m]))
            if (v > bv) { bv = v; bi = m }
        }
        chosen.push(seen.splice(bi, 1)[0])
    }

    // Too few distinct colours: stretch the lightness of what there is.
    var seed = chosen.slice()
    var step = 0
    while (chosen.length < count) {
        var base = toHsl(seed[step % seed.length])
        var up = (Math.floor(step / seed.length) % 2 === 0)
        var rounds = Math.floor(step / seed.length) + 1
        var l2 = clamp(base.l + (up ? 1 : -1) * 0.16 * rounds, 0.08, 0.93)
        var cand = fromHsl(base.h, base.s, l2)
        var clash = false
        for (var q = 0; q < chosen.length; q++)
            if (dist(cand, chosen[q]) < 4) { clash = true; break }
        if (!clash || step > 40) chosen.push(cand)
        step++
    }

    chosen.sort(function (a, b) { return toHsl(a).l - toHsl(b).l })
    return chosen
}

// ===== random palettes =====
var SCHEMES = {
    analogous:     [0, -28, 28, -56, 56],
    complementary: [0, 12, 180, 192, -12],
    split:         [0, 150, 210, 20, 180],
    triadic:       [0, 120, 240, 20, 140],
    tetradic:      [0, 90, 180, 270, 45],
    mono:          [0, 6, -6, 12, -12]
}
var SCHEME_NAMES = ["analogous", "complementary", "split", "triadic", "tetradic", "mono"]

// A small seedable generator, so a test (or a bug report) can replay a palette.
function makeRng(seed) {
    var s = (seed >>> 0) || 1
    return function () {
        s = (s + 0x6D2B79F5) >>> 0
        var t = s
        t = Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

// opts: { rng, scheme, locked }. `locked` is five entries, a hex (kept as it is) or
// "" / null (made new). The harmony is built around the first locked colour's hue, so
// the new colours go with the ones you kept. Returns { colors, scheme }.
function random(opts) {
    opts = opts || {}
    var rng = opts.rng || Math.random
    var locked = opts.locked || []
    var scheme = SCHEMES[opts.scheme] ? opts.scheme : SCHEME_NAMES[Math.floor(rng() * SCHEME_NAMES.length)]
    var offs = SCHEMES[scheme]

    var hue = rng() * 360
    for (var i = 0; i < SLOTS; i++)
        if (norm(locked[i]) !== "") { hue = toHsl(locked[i]).h; break }

    // One colour per rung of a lightness ladder, dealt out in random order, so every
    // palette has darks to be the outline and lights to be the accents.
    var ladder = [0.26, 0.40, 0.56, 0.70, 0.84]
    for (var a = ladder.length - 1; a > 0; a--) {
        var b = Math.floor(rng() * (a + 1))
        var t = ladder[a]; ladder[a] = ladder[b]; ladder[b] = t
    }

    var out = []
    for (var k = 0; k < SLOTS; k++) {
        var kept = norm(locked[k])
        if (kept !== "") { out.push(kept); continue }
        var h = hue + offs[k] + (rng() - 0.5) * 14
        var s = scheme === "mono" ? 0.35 + rng() * 0.35 : 0.5 + rng() * 0.4
        var l = clamp(ladder[k] + (rng() - 0.5) * 0.08, 0.12, 0.92)
        out.push(fromHsl(h, s, l))
    }
    return { colors: out, scheme: scheme }
}

// New colours from `list` (e.g. what an image gave) into the slots that are not
// locked; locked slots keep their colour. `list` is already `pick`ed.
function fill(current, list, locked) {
    var out = []
    var free = []
    for (var i = 0; i < SLOTS; i++) {
        if (locked && locked[i] && norm(current[i]) !== "") out.push(norm(current[i]))
        else out.push("")
    }
    for (var j = 0; j < list.length; j++) {
        var dup = false
        for (var k = 0; k < SLOTS; k++)
            if (out[k] !== "" && locked && locked[k] && dist(out[k], list[j]) < 6) { dup = true; break }
        if (!dup) free.push(list[j])
    }
    var n = 0
    for (var m = 0; m < SLOTS; m++)
        if (out[m] === "") out[m] = free[n] !== undefined ? free[n++] : norm(current[m]) || list[m % list.length]
    return out
}

// ===== the shell palette five colours make =====
// ThemeService's groups carry { border, A, B, deep, hoverTint, divider, boardBg,
// boardDot, rimHi, bezel, wallLight, wallMid, wallDark, hardware, lens, glint }.
// The shell is a white-pill UI with dark ink on light accents, so:
//   border  the darkest colour, held between lightness .20 and .36 (outline, shadow,
//           the ink on every light surface)
//   A, B    the two most vivid / distinct colours, lifted until the border's ink
//           reads on them (contrast >= 4.5)
//   the rest are tints and shades of those, laid out like the hand-made groups.
function lift(hex, border, minContrast) {
    var c = toHsl(hex)
    var s = Math.max(c.s, 0.35)
    var l = clamp(c.l, 0.55, 0.82)
    var out = fromHsl(c.h, s, l)
    var guard = 0
    while (contrast(border, out) < minContrast && l < 0.97 && guard++ < 40) {
        l += 0.02
        out = fromHsl(c.h, s, l)
    }
    return out
}

function vivid(hex) {
    var c = toHsl(hex)
    return c.s * (0.5 + 0.5 * (1 - Math.abs(c.l - 0.6) / 0.6))
}

function toShell(colors) {
    var list = []
    for (var i = 0; i < SLOTS; i++) list.push(norm((colors || [])[i]) || "#6e6d94")

    // darkest = the outline's hue
    var di = 0
    for (var a = 1; a < list.length; a++)
        if (toHsl(list[a]).l < toHsl(list[di]).l) di = a
    var d = toHsl(list[di])
    var bs = clamp(d.s, 0.15, 0.55)
    var bl = clamp(d.l, 0.20, 0.36)
    var border = fromHsl(d.h, bs, bl)
    // a yellow or green "dark" is still bright to the eye: darken until white ink reads on it
    var gd = 0
    while (contrast("#ffffff", border) < 5.2 && bl > 0.08 && gd++ < 40) {
        bl -= 0.01
        border = fromHsl(d.h, bs, bl)
    }
    var bh = toHsl(border)

    // the two accents
    var ai = 0
    for (var b = 1; b < list.length; b++)
        if (vivid(list[b]) > vivid(list[ai])) ai = b
    var bi = -1, bv = -1
    for (var c = 0; c < list.length; c++) {
        if (c === ai) continue
        var v = dist(list[c], list[ai]) * 0.6 + vivid(list[c]) * 100 * 0.4
        if (v > bv) { bv = v; bi = c }
    }
    var A = lift(list[ai], border, 4.5)
    var B = lift(list[bi], border, 4.5)
    // two accents that are the same colour make a flat gradient: nudge B along the wheel
    if (dist(A, B) < 12) {
        var ah = toHsl(A)
        B = lift(fromHsl(ah.h + 38, ah.s, ah.l), border, 4.5)
    }
    var ha = toHsl(A)

    var deep = fromHsl(bh.h, bh.s * 0.9, clamp(bh.l * 0.45, 0.08, 0.17))
    var dl = toHsl(deep).l
    return {
        border: border,
        A: A,
        B: B,
        deep: deep,
        hoverTint: mix(A, "#ffffff", 0.88),
        divider: mix(border, "#ffffff", 0.9),
        boardBg: mix(A, "#ffffff", 0.94),
        boardDot: mix(mix(A, border, 0.35), "#ffffff", 0.78),
        rimHi: fromHsl(bh.h, clamp(bh.s, 0.12, 0.4), 0.65),
        bezel: fromHsl(bh.h, bh.s, bh.l * 0.76),
        wallLight: fromHsl(bh.h, clamp(bh.s, 0.15, 0.45), 0.77),
        wallMid: fromHsl(bh.h, clamp(bh.s + 0.08, 0.2, 0.55), 0.49),
        wallDark: fromHsl(bh.h, bh.s, bh.l * 0.88),
        hardware: fromHsl(bh.h, bh.s * 0.9, dl * 0.75),
        lens: fromHsl(ha.h, clamp(ha.s, 0.4, 0.7), 0.38),
        glint: fromHsl(ha.h, clamp(ha.s, 0.4, 0.9), 0.82)
    }
}

// ===== saving / listing =====
// The five colours as one string, "aabbcc-ddeeff-...": the key a favourite is known
// by, and the line ThemeService keeps for an applied palette (comma separated there).
function key(colors) {
    var out = []
    for (var i = 0; i < SLOTS; i++) out.push(norm((colors || [])[i]).slice(1))
    return out.join("-")
}

// Five valid colours from an array or a "a,b,c,d,e" string, else null.
function parse(v) {
    var arr = typeof v === "string" ? v.split(/[\s,;-]+/).filter(function (x) { return x !== "" }) : (v || [])
    if (arr.length !== SLOTS) return null
    var out = []
    for (var i = 0; i < SLOTS; i++) {
        var h = norm(arr[i])
        if (h === "") return null
        out.push(h)
    }
    return out
}

function sameColors(a, b) {
    var x = parse(a), y = parse(b)
    return !!x && !!y && key(x) === key(y)
}

// A new list with `colors` at the front (an existing copy moves to the front instead of
// doubling up), at most `max` long.
function addFavorite(list, colors, source, max) {
    var c = parse(colors)
    if (!c) return list
    var out = [{ colors: c, source: source || "random" }]
    for (var i = 0; i < (list || []).length; i++)
        if (key(list[i].colors) !== key(c)) out.push(list[i])
    return out.slice(0, max || 48)
}

function removeFavorite(list, colors) {
    var k = key(colors)
    var out = []
    for (var i = 0; i < (list || []).length; i++)
        if (key(list[i].colors) !== k) out.push(list[i])
    return out
}

function isFavorite(list, colors) {
    var k = key(colors)
    for (var i = 0; i < (list || []).length; i++)
        if (key(list[i].colors) === k) return true
    return false
}

// What the saved JSON becomes: bad entries are dropped, never thrown.
function cleanFavorites(list) {
    var out = []
    var src = ["wallpaper", "music", "random"]
    for (var i = 0; i < (list || []).length; i++) {
        var c = parse(list[i] && list[i].colors)
        if (c && !isFavorite(out, c)) out.push({ colors: c, source: src.indexOf(list[i].source) >= 0 ? list[i].source : "random" })
    }
    return out.slice(0, 48)
}

// A preset holds the custom palette's five colours only when it wears the "custom" theme
// (a preset on another theme must not carry, or later overwrite, the custom colours).
// presetCustom: what to save, [five #rrggbb] or null. wearCustom: what to put back from a
// saved preset, or null (an older preset has no colours: it keeps the current ones).
function presetCustom(group, colors) {
    return group === "custom" ? parse(colors) : null
}

function wearCustom(group, saved) {
    return group === "custom" ? parse(saved) : null
}

