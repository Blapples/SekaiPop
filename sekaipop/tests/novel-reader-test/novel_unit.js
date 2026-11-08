// Run with: node tests/novel-reader-test/novel_unit.js
// NovelMath.js is a QML JS library: load it as plain script text.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "..", "modules", "sekai", "readers", "NovelMath.js"), "utf8")
const N = new Function(src.replace(/^\.pragma library/m, "") + `
return { MODES, BACKGROUNDS, DEFAULT_PREFS, modeInfo, isMode, isBackground, palette, nextMode, nextBackground,
         normalizePrefs, keyAction, tapAction, pageStep, pageInfo, shouldPreload, keysHint, PRELOAD_AT,
         trackProgress, chaptersUpTo, readDone, statusLabel, TRACK_STATUSES,
         chapterNumber, orderChapters, chapterTag, titleIsPlain, continueTarget, idsUpTo }`)()

// prefs: defaults and clean-up of a hand-edited file
assert.deepStrictEqual(N.normalizePrefs(null), N.DEFAULT_PREFS)
assert.deepStrictEqual(N.normalizePrefs({}), N.DEFAULT_PREFS)
assert.strictEqual(N.DEFAULT_PREFS.fullWindow, true)
const good = { mode: "paged", background: "sepia", fontSize: 20, lineHeight: 1.9, fullWindow: false }
assert.deepStrictEqual(N.normalizePrefs(good), good)
const bad = N.normalizePrefs({ mode: "zigzag", background: "pink", fontSize: 400, lineHeight: 0, fullWindow: "no" })
assert.strictEqual(bad.mode, "scroll")
assert.strictEqual(bad.background, "theme")
assert.strictEqual(bad.fontSize, 26)
assert.strictEqual(bad.lineHeight, 1.4)
assert.strictEqual(bad.fullWindow, false)
assert.strictEqual(N.normalizePrefs({ fontSize: "abc" }).fontSize, 17)
assert.strictEqual(N.normalizePrefs({ fontSize: 2 }).fontSize, 13)

// modes and backgrounds cycle and wrap
assert.strictEqual(N.nextMode("scroll"), "paged")
assert.strictEqual(N.nextMode("paged"), "scroll")
assert.strictEqual(N.nextMode("nope"), "scroll")
let b = "theme", seen = []
for (let i = 0; i < N.BACKGROUNDS.length; i++) { b = N.nextBackground(b); seen.push(b) }
assert.strictEqual(seen[seen.length - 1], "theme")
assert.strictEqual(new Set(seen).size, N.BACKGROUNDS.length)
assert.strictEqual(N.palette("theme"), null)
assert.strictEqual(N.palette("white").bg, "#ffffff")
assert.strictEqual(N.palette("nope"), null)
assert.strictEqual(N.modeInfo("nope").id, "scroll")

// keys
assert.strictEqual(N.keyAction("scroll", "down"), "scroll_down")
assert.strictEqual(N.keyAction("scroll", "up"), "scroll_up")
assert.strictEqual(N.keyAction("scroll", "left"), "prev_chapter")
assert.strictEqual(N.keyAction("scroll", "right"), "next_chapter")
assert.strictEqual(N.keyAction("paged", "left"), "prev")
assert.strictEqual(N.keyAction("paged", "up"), "prev")
assert.strictEqual(N.keyAction("paged", "right"), "next")
assert.strictEqual(N.keyAction("paged", "down"), "next")
assert.strictEqual(N.keyAction("paged", "sideways"), "")

// taps
assert.strictEqual(N.tapAction("scroll", 5, 5, 800, 600), "menu")
assert.strictEqual(N.tapAction("paged", 100, 300, 800, 600), "prev")
assert.strictEqual(N.tapAction("paged", 700, 300, 800, 600), "next")
assert.strictEqual(N.tapAction("paged", 400, 300, 800, 600), "menu")
assert.strictEqual(N.tapAction("paged", 400, 300, 0, 0), "menu")

// page turns keep a line of overlap and never go below a floor
assert.strictEqual(N.pageStep(800, 17, 1.75), 800 - Math.round(17 * 1.75 * 1.2))
assert.strictEqual(N.pageStep(50, 17, 1.75), 80)
assert.deepStrictEqual(N.pageInfo(0, 0, 700), { index: 1, total: 1 })
assert.deepStrictEqual(N.pageInfo(0, 2100, 700), { index: 1, total: 4 })
assert.deepStrictEqual(N.pageInfo(2100, 2100, 700), { index: 4, total: 4 })
assert.deepStrictEqual(N.pageInfo(-30, 2100, 700), { index: 1, total: 4 })
assert.deepStrictEqual(N.pageInfo(99999, 2100, 700).index, 4)

// preload: half-way, or at once when the chapter is one screen
assert.strictEqual(N.shouldPreload(0.1, false), false)
assert.strictEqual(N.shouldPreload(0.5, false), true)
assert.strictEqual(N.shouldPreload(0.9, false), true)
assert.strictEqual(N.shouldPreload(0, true), true)

// AniList: the highest chapter number read, whole numbers, unnumbered chapters left out
const chs = [{ id: "a", chapter: "1" }, { id: "b", chapter: "Chapter 2" }, { id: "c", chapter: "12.5" },
             { id: "d", chapter: "Prologue" }, { id: "e", chapter: 30 }, null]
const read = new Set(["a", "b", "d"])
assert.strictEqual(N.trackProgress(chs, id => read.has(id)), 2)
read.add("c")
assert.strictEqual(N.trackProgress(chs, id => read.has(id)), 12)
read.add("e")
assert.strictEqual(N.trackProgress(chs, id => read.has(id)), 30)
assert.strictEqual(N.trackProgress([], () => true), 0)
assert.strictEqual(N.trackProgress(null, () => true), 0)
assert.strictEqual(N.trackProgress(chs, () => false), 0)
// Opening a novel already begun on AniList: the chapters up to its number count as read
assert.deepStrictEqual(N.chaptersUpTo(chs, 0), [])
assert.deepStrictEqual(N.chaptersUpTo(chs, 2), ["a", "b"])
assert.deepStrictEqual(N.chaptersUpTo(chs, 12), ["a", "b", "c"])
assert.deepStrictEqual(N.chaptersUpTo(chs, 30), ["a", "b", "c", "e"])
assert.deepStrictEqual(N.chaptersUpTo(null, 5), [])
assert.strictEqual(N.readDone(0.5, false), false)
assert.strictEqual(N.readDone(0.9, false), true)
assert.strictEqual(N.readDone(0, true), true)
assert.strictEqual(N.statusLabel("CURRENT"), "Reading")
assert.strictEqual(N.statusLabel("ZZZ"), "ZZZ")
assert.strictEqual(N.TRACK_STATUSES.length, 6)

// ── The chapter list: order, stamps, plain titles, where Continue goes ──────────
{
    const ch = (id, chapter, extra) => Object.assign({ id, chapter, title: "" }, extra || {})
    // shuffled, with a number repeated by a source that restarts the count in each volume
    const list = [ch("c3", "3"), ch("v2c1", "1", { index: 5 }), ch("c1", "1", { index: 1 }), ch("c2", "2")]
    assert.deepStrictEqual(N.orderChapters(list).map(c => c.id), ["c1", "v2c1", "c2", "c3"])
    assert.deepStrictEqual(N.orderChapters(null), [])
    assert.strictEqual(N.chapterNumber(ch("x", "12.5")), 12.5)
    assert.strictEqual(N.chapterNumber(ch("x", "Prologue")), 0)

    assert.strictEqual(N.chapterTag(ch("a", "47")), "CH.47")
    assert.strictEqual(N.chapterTag(ch("a", "7", { kind: "volume", volume: "2" })), "VOL.2")
    assert.strictEqual(N.chapterTag(ch("a", "7", { kind: "volume" })), "VOL.7")
    assert.strictEqual(N.chapterTag(null), "CH.?")

    assert.ok(N.titleIsPlain("Chapter 47") && N.titleIsPlain("Ch. 3") && N.titleIsPlain("Volume 2") && N.titleIsPlain(""))
    assert.ok(!N.titleIsPlain("Volume 1 - Chapter 10: What Lies Ahead") && !N.titleIsPlain("Prologue"))

    // Continue
    const four = [ch("a", "1"), ch("b", "2"), ch("c", "3"), ch("d", "4")]
    const reads = (...ids) => id => ids.includes(id)
    assert.deepStrictEqual(N.continueTarget(four, "", reads()), { chapter: four[0], started: false })   // not started
    assert.deepStrictEqual(N.continueTarget(four, "", reads("a", "b")), { chapter: four[2], started: true })
    assert.deepStrictEqual(N.continueTarget(four, "d", reads("a")), { chapter: four[3], started: true }) // opened, not finished
    assert.deepStrictEqual(N.continueTarget(four, "b", reads("a", "b")), { chapter: four[2], started: true })   // finished: on to the next
    assert.deepStrictEqual(N.continueTarget(four, "", reads("a", "c")), { chapter: four[3], started: true })    // beyond the furthest read
    assert.strictEqual(N.continueTarget(four, "d", reads("a", "b", "c", "d")), null)                    // all read
    assert.strictEqual(N.continueTarget([], "", reads()), null)
    // the list in the source's newest-first order still continues in reading order
    assert.strictEqual(N.continueTarget([...four].reverse(), "", reads("a")).chapter.id, "b")

    // Up to here
    assert.deepStrictEqual(N.idsUpTo([...four].reverse(), "c"), ["a", "b", "c"])
    assert.deepStrictEqual(N.idsUpTo(four, "zzz"), [])

    // a whole volume is not a chapter AniList counts
    const mixed = [ch("c1", "1"), ch("c2", "2"), ch("v1", "3", { kind: "volume", volume: "1" })]
    assert.strictEqual(N.trackProgress(mixed, () => true), 2)
    assert.deepStrictEqual(N.chaptersUpTo(mixed, 5), ["c1", "c2"])
}

assert.ok(N.keysHint("paged").length > 0 && N.keysHint("scroll").length > 0)
console.log("novel_unit: ok")
