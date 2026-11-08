.pragma library

// The font of the lyrics widget's Korean and Japanese words (LyricsWord.qml, KineticWord.qml,
// KineticFillWord.qml, LyricsKinetic.qml's hero word). Pure functions, so node can test them:
// tests/lyrics-test/lyrics_font_unit.js.
//
// A word with any Hangul, kana or kanji in it is set in Pretendard Black. Every other word keeps
// the theme's font and weight. Qt's `font.family` takes ONE name (`font.families` is newer than
// some Qt 6 builds and stops the shell loading), so there is one name here:
//   FAMILY = "Pretendard"       the AUR's ttf-pretendard (yay -S ttf-pretendard): Hangul and kana;
//                               most kanji come from the system's CJK font (Noto CJK)
//   FAMILY = "Pretendard JP"    PretendardJP-Black.otf: the same plus every kanji
// Check what is installed with:  fc-list "Pretendard:style=Black"   (or "Pretendard JP:style=Black")
//
//   LF.cjk("사랑해")          true
//   LF.family(text, theme)    FAMILY for those words, the theme's font for the rest
//   LF.weight(text, normal)   Font.Black (900) for those words, `normal` for the rest
//   LF.style(text, normal)    "Black" for those words, `normal` for the rest

var FAMILY = "Pretendard"
var STYLE = "Black"
var WEIGHT_BLACK = 900

// Hangul (jamo, compatibility jamo, syllables), kana (hiragana, katakana, the small and the
// half-width ones) and the CJK ideographs (kanji).
var RE = /[\u1100-\u11FF\u3130-\u318F\uA960-\uA97F\uAC00-\uD7AF\uD7B0-\uD7FF\u3040-\u30FF\u31F0-\u31FF\uFF66-\uFF9F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/

function cjk(text) {
    return RE.test(text || "")
}

function family(text, themeFamily) {
    return cjk(text) ? FAMILY : themeFamily
}

function weight(text, normal) {
    return cjk(text) ? WEIGHT_BLACK : normal
}

function style(text, normal) {
    return cjk(text) ? STYLE : normal
}
