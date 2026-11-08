// Run with: node tests/novel-reader-test/detail_unit.js
// The novel's title page works like the manga one: a release date on every row, where the chapters come
// from, "N read", AniList, Continue, a selection bar, and the ... menu (select, mark all read / unread).
// Node cannot load QML, so this reads the files: that the view is well formed, that everything it takes
// from the service and from NovelMath is declared, and that the date really travels from the server.
const fs = require("fs")
const path = require("path")
const assert = require("assert")
const check = require("../lib/qmlcheck.js")

const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")

const detail = read("modules/sekai/readers/novel/DetailView.qml")
const novel = read("modules/sekai/readers/Novel.qml")
const math = read("modules/sekai/readers/NovelMath.js")
const provider = read("scripts/readers/novel_server/providers/lnreader.py")

// well formed
const problems = check(detail, "novel/DetailView.qml")
assert.deepStrictEqual(problems, [], problems.join("\n"))

// everything the view takes from the service and from NovelMath is declared there
const declared = new Set([...novel.matchAll(/^\s*(?:readonly\s+)?property\s+[\w<>]+\s+(\w+)/gm)].map(m => m[1])
    .concat([...novel.matchAll(/^\s*function\s+(\w+)\(/gm)].map(m => m[1]))
    .concat([...novel.matchAll(/^\s*signal\s+(\w+)/gm)].map(m => m[1])))
for (const u of new Set([...detail.matchAll(/\bNovel\.([A-Za-z_]\w*)/g)].map(m => m[1])))
    assert(declared.has(u), "Novel." + u + " is not declared in Novel.qml")
const mathFns = new Set([...math.matchAll(/^function\s+(\w+)/gm)].map(m => m[1]))
for (const u of new Set([...detail.matchAll(/\bNM\.([A-Za-z_]\w*)/g)].map(m => m[1])))
    assert(mathFns.has(u), "NM." + u + " is not declared in NovelMath.js")

// the menu row is shared now (the novel folder cannot see the manga folder's files)
assert(fs.existsSync(path.join(root, "modules/sekai/readers/ReaderMenuRow.qml")), "ReaderMenuRow.qml is not in readers/")
assert(!fs.existsSync(path.join(root, "modules/sekai/readers/manga/ReaderMenuRow.qml")), "ReaderMenuRow.qml is still in manga/ as well")

// the keys the page asked for
for (const text of ["Select chapters", "Mark all as read", "Mark all as unread", "Up to here", "Continue", "AniList",
                    "Chapters from ", "releaseText(modelData)"])
    assert(detail.includes(text), "DetailView.qml has no \"" + text + "\"")
// the whole-novel keys and the selection bar write through the one function that also tells AniList
assert(/Novel\.setChaptersRead\(Novel\.currentNovel\.chapters\.map/.test(detail), "Mark all does not use setChaptersRead")
assert(/Novel\.setChaptersRead\(Object\.keys\(_selected\), read\)/.test(detail), "the selection bar does not use setChaptersRead")
// the old Continue / Next Chapter row is gone: Continue is the floating key
assert(!/readNext|continueReading/.test(detail), "the old Continue / Next functions are still there")
// a second onVisibleChanged handler on the root would stop the page from loading
assert.strictEqual((detail.match(/^ {4}onVisibleChanged:/gm) || []).length, 1, "more than one onVisibleChanged on the root")

// the service keeps the date and the volume of each chapter, and can mark unread
for (const field of ["publishAt", "releasedText", "kind", "volume", "index"])
    assert(new RegExp("\\b" + field + ":\\s+ch\\." + field).test(novel), "Novel.qml does not keep chapter." + field)
assert(/function setChaptersRead\(ids, read\)/.test(novel) && /delete next\[id\]/.test(novel), "Novel.qml cannot mark unread")
assert(/if \(read\) trackSoon\(\)/.test(novel), "marking unread must not send AniList anything")
assert(/function readCount\(/.test(novel) && /function sourceNameFor\(/.test(novel))

// ... and the server sends them
for (const field of ["publishAt", "releasedText", "kind", "volume", "index"])
    assert(provider.includes('"' + field + '"'), "lnreader.py does not send " + field)
assert(/ch\.get\("releaseTime"\)/.test(provider), "lnreader.py does not read the plugin's releaseTime")

console.log("novel detail view: all checks passed")
