// Which lyric words are set in Pretendard JP Black (modules/common/functions/LyricsFont.js),
// and that the four lyric text components ask for it.
// Run: node lyrics_font_unit.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const root = path.join(__dirname, "..", "..")
const src = fs.readFileSync(path.join(root, "modules/common/functions/LyricsFont.js"), "utf8")
const LF = new Function(src.replace(".pragma library", "") + "\nreturn { cjk, family, weight, style, FAMILY, STYLE }")()

for (const w of ["사랑해", "ㅋㅋ", "あいうえお", "カタカナ", "君の名前", "ｶﾀｶﾅ", "K-팝", "Hello 世界"])
    assert.ok(LF.cjk(w), w + " should be Pretendard")
for (const w of ["hello", "don't", "ça va", "Привет", "123", "(ooh)", "", null, undefined])
    assert.ok(!LF.cjk(w), String(w) + " should keep the theme font")

assert.strictEqual(LF.family("사랑", "Google Sans Flex"), "Pretendard")
assert.strictEqual(LF.family("love", "Google Sans Flex"), "Google Sans Flex")
assert.strictEqual(LF.weight("사랑", 800), 900)
assert.strictEqual(LF.weight("love", 800), 800)
assert.strictEqual(LF.style("사랑", "ExtraBold"), "Black")
assert.strictEqual(LF.style("love", "ExtraBold"), "ExtraBold")

for (const f of ["LyricsWord", "KineticWord", "KineticFillWord", "LyricsKinetic"]) {
    const q = fs.readFileSync(path.join(root, "modules/sekai/desktopWidgets", f + ".qml"), "utf8")
    assert.ok(q.includes('LyricsFont.js" as LF'), f + " imports LyricsFont.js")
    assert.ok(/font\.family: LF\.family\(/.test(q) && !q.includes("font.families"), f + " uses LF.family (not font.families)")
    assert.ok(/font\.weight: LF\.weight\(/.test(q), f + " uses LF.weight")
    assert.ok(/font\.styleName: LF\.style\(/.test(q), f + " uses LF.style")
}
console.log("lyrics font: ok")
