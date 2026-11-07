// node tests/palette-test/palette_unit.js   (run from the sekaipop folder)
const fs = require("fs")
const locate = require("../lib/locate.js")
const src = fs.readFileSync(locate("modules/common/functions/PaletteMath.js"), "utf8").replace(".pragma library", "")
const P = new Function(src + "; return { SLOTS, norm, toRgb, fromRgb, toHsl, fromHsl, mix, lum, contrast, textOn, dist, pick, random, makeRng, fill, toShell, key, parse, sameColors, addFavorite, removeFavorite, isFavorite, cleanFavorites, SCHEME_NAMES, presetCustom, wearCustom }")()

let fails = 0
const eq = (a, b, m) => { const x = JSON.stringify(a), y = JSON.stringify(b); if (x !== y) { fails++; console.log("FAIL " + m + "\n   got  " + x + "\n   want " + y) } }
const ok = (c, m) => { if (!c) { fails++; console.log("FAIL " + m) } }
const HEX = /^#[0-9a-f]{6}$/

// hex / hsl
eq(P.norm("ABC"), "#aabbcc", "short hex"); eq(P.norm(" #A1b2C3 "), "#a1b2c3", "trim + case"); eq(P.norm("#12345"), "", "bad length"); eq(P.norm("zzzzzz"), "", "not hex"); eq(P.norm(null), "", "null")
for (const h of ["#000000", "#ffffff", "#ff0000", "#04feee", "#555473", "#123456", "#fedcba"])
    ok(P.dist(P.fromHsl(P.toHsl(h).h, P.toHsl(h).s, P.toHsl(h).l), h) < 1.5, "hsl round trip " + h)
eq(P.mix("#000000", "#ffffff", 0.5), "#808080", "mix")
ok(P.contrast("#000000", "#ffffff") > 20.9 && P.contrast("#000000", "#ffffff") < 21.1, "contrast black/white")
eq(P.textOn("#ffffff"), "#1b1a2b", "dark ink on white"); eq(P.textOn("#10101a"), "#ffffff", "white on dark")

// pick: always five, dark to light, valid, whatever came in
const inputs = [
    [], ["#ffffff"], ["#000000", "#000000"], ["#808080", "#818181", "#7f7f7f"],
    ["#ff0000", "#00ff00", "#0000ff"], ["#ff0000", "#fe0101", "#ff0202", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff"],
    ["junk", null, undefined, 5, "#abc"]
]
for (const inp of inputs) {
    const o = P.pick(inp, 5)
    eq(o.length, 5, "pick gives five for " + JSON.stringify(inp)); ok(o.every(h => HEX.test(h)), "pick valid hex " + JSON.stringify(inp))
    const ls = o.map(h => P.toHsl(h).l); ok(ls.every((v, i) => i === 0 || v >= ls[i - 1] - 1e-9), "pick sorted dark to light " + JSON.stringify(inp))
}
const o8 = P.pick(["#ff0000", "#fe0101", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#808080"], 5)
for (let i = 0; i < 5; i++) for (let j = i + 1; j < 5; j++) ok(P.dist(o8[i], o8[j]) > 6, "picked colours differ " + i + "/" + j)
ok(!o8.includes("#fe0101") || !o8.includes("#ff0000"), "near duplicates collapse")

// random: seeded = repeatable; locked slots kept; every scheme works
const r1 = P.random({ rng: P.makeRng(7), scheme: "triadic" }), r2 = P.random({ rng: P.makeRng(7), scheme: "triadic" })
eq(r1, r2, "same seed, same palette"); eq(r1.colors.length, 5, "five colours"); ok(r1.colors.every(h => HEX.test(h)), "random valid")
for (const s of P.SCHEME_NAMES) { const r = P.random({ rng: P.makeRng(3), scheme: s }); eq(r.scheme, s, "scheme " + s); ok(r.colors.every(h => HEX.test(h)), "valid " + s) }
const locked = ["#112233", "", "#445566", null, ""]
const rl = P.random({ rng: P.makeRng(11), locked })
eq([rl.colors[0], rl.colors[2]], ["#112233", "#445566"], "locked slots survive a shuffle")
ok(rl.colors[1] !== "" && rl.colors[3] !== "" && HEX.test(rl.colors[4]), "unlocked slots are refilled")
const differ = new Set(); for (let i = 1; i <= 30; i++) differ.add(P.key(P.random({ rng: P.makeRng(i) }).colors)); ok(differ.size >= 28, "different seeds give different palettes")

// fill: locked slots stay, the others take the new colours
const cur = ["#111111", "#222222", "#333333", "#444444", "#555555"]
const f = P.fill(cur, ["#ff0000", "#00ff00", "#0000ff", "#ffff00", "#00ffff"], [true, false, false, false, true])
eq([f[0], f[4]], ["#111111", "#555555"], "fill keeps locked"); ok(f.every(h => HEX.test(h)), "fill valid")
eq(P.fill(cur, ["#ff0000"], [false, false, false, false, false]).every(h => HEX.test(h)), true, "fill with a short list still five valid colours")

// toShell: the shell's contract, for a lot of palettes including awkward ones
const KEYS = ["border", "A", "B", "deep", "hoverTint", "divider", "boardBg", "boardDot", "rimHi", "bezel", "wallLight", "wallMid", "wallDark", "hardware", "lens", "glint"]
const sets = [
    ["#000000", "#000000", "#000000", "#000000", "#000000"], ["#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff"],
    ["#808080", "#808080", "#808080", "#808080", "#808080"], ["#ff0000", "#ff0000", "#ff0000", "#ff0000", "#ff0000"],
    ["#04feee", "#00ffcb", "#555473", "#232235", "#d9fff6"], ["#fff200", "#ffee00", "#fff700", "#fffa00", "#fffc00"],
    ["#001133", "#002255", "#003377", "#004499", "#0055bb"], ["bad", "bad", "bad", "bad", "bad"], [], null
]
for (let i = 1; i <= 400; i++) sets.push(P.random({ rng: P.makeRng(i * 31) }).colors)
for (let i = 1; i <= 100; i++) { const rng = P.makeRng(i); sets.push([0, 1, 2, 3, 4].map(() => P.fromRgb(rng() * 255, rng() * 255, rng() * 255))) }
let worstA = 99, worstB = 99, worstW = 99
sets.forEach((s, i) => {
    const p = P.toShell(s)
    ok(KEYS.every(k => HEX.test(p[k])), "toShell has every key as hex (set " + i + ")")
    const cA = P.contrast(p.border, p.A), cB = P.contrast(p.border, p.B), cW = P.contrast("#ffffff", p.border)
    worstA = Math.min(worstA, cA); worstB = Math.min(worstB, cB); worstW = Math.min(worstW, cW)
    ok(cA >= 4.5, "border ink reads on A, set " + i + " (" + cA.toFixed(2) + ")")
    ok(cB >= 4.5, "border ink reads on B, set " + i + " (" + cB.toFixed(2) + ")")
    ok(cW >= 4.5, "white reads on the border, set " + i + " (" + cW.toFixed(2) + ")")
    ok(P.toHsl(p.deep).l < P.toHsl(p.border).l, "deep is darker than border, set " + i)
    ok(P.toHsl(p.hardware).l <= P.toHsl(p.deep).l, "hardware is not lighter than deep, set " + i)
    eq(P.toShell(s), p, "toShell is deterministic, set " + i)
})
// A and B must not be one flat colour (the accent gradient) when the palette had two to give
const g = P.toShell(["#ff0000", "#ff0000", "#ff0000", "#ff0000", "#220000"]); ok(P.dist(g.A, g.B) >= 12, "A and B are told apart")
// a real palette lands near its source: the cyan group's accent stays cyan
const vs = P.toShell(["#555473", "#232235", "#04feee", "#00ffcb", "#d9fff6"]); ok(Math.abs(P.toHsl(vs.A).h - P.toHsl("#04feee").h) < 12, "A keeps its hue")
console.log("toShell worst contrast  A:" + worstA.toFixed(2) + "  B:" + worstB.toFixed(2) + "  white/border:" + worstW.toFixed(2))

// favourites
const L1 = P.addFavorite([], ["#111111", "#222222", "#333333", "#444444", "#555555"], "wallpaper")
eq(L1.length, 1, "one favourite"); eq(L1[0].source, "wallpaper", "keeps its source")
const L2 = P.addFavorite(L1, ["#aaa", "#bbb", "#ccc", "#ddd", "#eee"], "music")
eq(L2.length, 2, "two favourites"); eq(L2[0].colors[0], "#aaaaaa", "newest first")
const L3 = P.addFavorite(L2, ["#111111", "#222222", "#333333", "#444444", "#555555"], "random")
eq(L3.length, 2, "same colours do not double up"); eq(L3[0].source, "random", "...and the copy moves to the front")
eq(P.addFavorite(L3, ["#111111"], "random"), L3, "five colours or nothing")
ok(P.isFavorite(L3, ["#AAA", "#BBB", "#CCC", "#DDD", "#EEE"]), "isFavorite ignores case / short form")
eq(P.removeFavorite(L3, ["#111111", "#222222", "#333333", "#444444", "#555555"]).length, 1, "remove")
let big = []; for (let i = 0; i < 60; i++) big = P.addFavorite(big, P.random({ rng: P.makeRng(i + 1) }).colors, "random", 48); eq(big.length, 48, "capped at 48")
eq(P.cleanFavorites([{ colors: ["#111111", "#222222", "#333333", "#444444", "#555555"], source: "bogus" }, { colors: ["x"] }, null, 5]).map(f => f.source), ["random"], "cleanFavorites drops rubbish")
eq(P.parse("#111111,#222222,#333333,#444444,#555555"), ["#111111", "#222222", "#333333", "#444444", "#555555"], "parse csv")
eq(P.parse("#111111,#222222"), null, "parse needs five"); eq(P.parse(["#111111", "#222222", "#333333", "#444444", "nope"]), null, "parse rejects a bad entry")
eq(P.sameColors("#111111,#222222,#333333,#444444,#555555", ["#111", "#222", "#333", "#444", "#555"]), true, "sameColors")

// a preset keeps its own custom palette
const five = ["#112233", "#445566", "#778899", "#aabbcc", "#ddeeff"]
eq(P.presetCustom("custom", five), five, "a preset on the custom theme saves its colours")
eq(P.presetCustom("custom", five.join(",")), five, "also from the saved text")
eq(P.presetCustom("vs", five), null, "a preset on another theme carries none")
eq(P.presetCustom("custom", null), null, "no custom colours yet, nothing to save")
eq(P.wearCustom("custom", five), five, "worn back")
eq(P.wearCustom("custom", undefined), null, "an older preset has none: current colours stay")
eq(P.wearCustom("custom", ["#112233"]), null, "not five colours: ignored")
eq(P.wearCustom("vs", five), null, "another theme never touches the custom colours")

console.log(fails === 0 ? "palette_unit: all checks passed" : "palette_unit: " + fails + " FAILED")
process.exit(fails === 0 ? 0 : 1)
