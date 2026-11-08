// Run with: node tests/novel-reader-test/info_unit.js
// The novel's Info sheet, the stamps in its header, the short type tag on Discover covers (LN, not
// LIGHT NOVEL) and the Library cover's source tag and manga-style title. Node cannot load QML, so this loads NovelMath.js as script text
// and reads the QML files: that they are well formed, that everything they take from the service and
// from NovelMath is declared, and that the pieces are wired to each other and to the backend.
const fs = require("fs")
const path = require("path")
const assert = require("assert")
const check = require("../lib/qmlcheck.js")

const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")

const R = "modules/sekai/readers/"
const files = {
    info:    read(R + "novel/InfoPanel.qml"),
    detail:  read(R + "novel/DetailView.qml"),
    library: read(R + "novel/LibraryView.qml"),
    browse:  read(R + "novel/BrowseView.qml"),
}
const novel = read(R + "Novel.qml")
const mathSrc = read(R + "NovelMath.js")
const server = read("scripts/readers/novel_server/server.py")
const anilist = read("scripts/readers/novel_server/anilist.py")

const N = new Function(mathSrc.replace(/^\.pragma library/m, "") + `
return { typeShort, statusWord, scoreStamp, yourScoreStamp, sourceTag,
         dateText, releasedText, originLanguage, otherNames, authorsText, SOURCE_TAG_MAX }`)()

// ── well formed, and everything they take is declared ───────────────────────
for (const [name, text] of Object.entries(files)) {
    const problems = check(text, name)
    assert.deepStrictEqual(problems, [], name + ": " + problems.join("\n"))
}
const declared = new Set([...novel.matchAll(/^\s*(?:readonly\s+)?property\s+[\w<>]+\s+(\w+)/gm)].map(m => m[1])
    .concat([...novel.matchAll(/^\s*function\s+(\w+)\(/gm)].map(m => m[1]))
    .concat([...novel.matchAll(/^\s*signal\s+(\w+)/gm)].map(m => m[1])))
const mathFns = new Set([...mathSrc.matchAll(/^function\s+(\w+)/gm)].map(m => m[1]))
for (const [name, text] of Object.entries(files)) {
    for (const u of new Set([...text.matchAll(/\bNovel\.([A-Za-z_]\w*)/g)].map(m => m[1])))
        assert(declared.has(u), name + ": Novel." + u + " is not declared in Novel.qml")
    for (const u of new Set([...text.matchAll(/\bNM\.([A-Za-z_]\w*)/g)].map(m => m[1])))
        assert(mathFns.has(u) || /^[A-Z_]+$/.test(u), name + ": NM." + u + " is not declared in NovelMath.js")
}
// the sheet reads the same ReaderMath helpers the manga one does: they must exist
const rm = read(R + "ReaderMath.js")
for (const u of new Set([...files.info.matchAll(/\bRM\.([A-Za-z_]\w*)/g)].map(m => m[1])))
    assert(new RegExp("^function\\s+" + u + "\\b", "m").test(rm), "ReaderMath.js has no " + u)

// ── the short type tag ──────────────────────────────────────────────────────
const labels = [...anilist.matchAll(/"(JP|KR|CN|TW)":\s*"([A-Z ]+)"/g)].map(m => m[2])
assert(labels.length >= 4, "could not read the server's type labels")
assert.strictEqual(N.typeShort("LIGHT NOVEL"), "LN")
for (const l of labels) {
    const t = N.typeShort(l)
    assert(t.length > 0 && t.length <= 4, "the tag for " + l + " (" + t + ") must be short enough to sit beside the score")
}
assert.strictEqual(N.typeShort("light novel"), "LN", "case does not matter")
assert.strictEqual(N.typeShort(""), "")
assert.strictEqual(N.typeShort(undefined), "")
assert(N.typeShort("Some Unheard Of Format").length <= 6, "an unknown label is cut to its first word")
// Discover wears the short tag, not the server's long label
assert(/NM\.typeShort\(modelData\.type\)/.test(files.browse), "Discover covers do not use the short type tag")
assert(!/text:\s*\(modelData\.type \|\| ""\)\.toUpperCase\(\)/.test(files.browse), "the long type label is still on the cover")
// ... and the score stamp is still drawn on the same cover, on the other corner
assert(/"\\u2605 " \+ \(\(modelData\.score/.test(files.browse) || /text: "★ "/.test(files.browse), "Discover covers lost their score stamp")

// the grid's titles are the manga grid's: the whole title over the art, nothing written under it
assert(/fullTitle:\s*true/.test(files.browse) && /holdTitle:\s*false/.test(files.browse), "Browse covers do not put the title over the art")
assert(!/subtitle:/.test(files.browse.slice(files.browse.indexOf("CoverCard {"))), "a Browse cover still has a subtitle (volumes / chapters)")
assert(/ReaderEnv\.panelBodyTarget/.test(files.browse), "the Browse grid does not hold its width while the panel resizes")

// ── stamps ──────────────────────────────────────────────────────────────────
assert.strictEqual(N.statusWord("Releasing"), "Ongoing")
assert.strictEqual(N.statusWord("FINISHED"), "Completed")
assert.strictEqual(N.statusWord("Hiatus"), "Hiatus")
assert.strictEqual(N.statusWord("Ongoing"), "Ongoing", "the manga wording is left as it is")
assert.strictEqual(N.statusWord(""), "")
assert.strictEqual(N.scoreStamp(82), "8.2")
assert.strictEqual(N.scoreStamp(100), "10.0")
assert.strictEqual(N.scoreStamp(0), "")
assert.strictEqual(N.scoreStamp(null), "")
assert.strictEqual(N.yourScoreStamp(9, 90, "POINT_10"), "9/10")
assert.strictEqual(N.yourScoreStamp(8.5, 85, "POINT_10_DECIMAL"), "8.5/10")
assert.strictEqual(N.yourScoreStamp(85, 85, "POINT_100"), "85/100")
assert.strictEqual(N.yourScoreStamp(4, 80, "POINT_5"), "4\u2605")
assert.strictEqual(N.yourScoreStamp(0, 0, "POINT_10"), "", "not rated is nothing")
assert.strictEqual(N.yourScoreStamp(0, 70, ""), "7.0/10", "a format the login has not said is read as 0-100 out of 10")

// the source plate: a name in capitals, cut to fit a cover
assert.strictEqual(N.sourceTag("FreeWebNovel"), "FREEWEBNOVEL")
assert.strictEqual(N.sourceTag("  Royal Road "), "ROYAL ROAD", "spaces around are dropped")
assert.strictEqual(N.sourceTag("Royal Road \u00b7 en"), "ROYAL ROAD\u2026", "a name too long for a cover is cut at a word, not on a dot")
assert.strictEqual(N.sourceTag(""), "")
const longTag = N.sourceTag("A Source With A Very Long Name Indeed")
assert(longTag.length <= N.SOURCE_TAG_MAX && longTag.endsWith("\u2026"), longTag)
assert(!/[\s\u00b7.\-]\u2026$/.test(longTag), "no dangling space or dot before the ellipsis: " + longTag)

// ── the Info sheet's words ──────────────────────────────────────────────────
assert.strictEqual(N.dateText("2018-03-09"), "Mar 9, 2018")
assert.strictEqual(N.dateText("2018-03"), "Mar 2018")
assert.strictEqual(N.dateText("2018"), "2018")
assert.strictEqual(N.dateText("2018-13-01"), "2018", "a month that is not one is dropped")
assert.strictEqual(N.dateText("yesterday"), "")
assert.strictEqual(N.dateText(""), "")
assert.strictEqual(N.releasedText("2018-08-01", "", "Releasing", 2018), "Aug 1, 2018  \u2192  now")
assert.strictEqual(N.releasedText("2014-01-10", "2021-06-02", "Finished", 2014), "Jan 10, 2014  \u2192  Jun 2, 2021")
assert.strictEqual(N.releasedText("2014-01-10", "2014-01-10", "Finished", 2014), "Jan 10, 2014")
assert.strictEqual(N.releasedText("", "", "Releasing", 2019), "2019", "only the year is known")
assert.strictEqual(N.releasedText("", "", "", 0), "")
assert.strictEqual(N.originLanguage("LIGHT NOVEL"), "Japanese")
assert.strictEqual(N.originLanguage("KOREAN NOVEL"), "Korean")
assert.strictEqual(N.originLanguage("CHINESE NOVEL"), "Chinese")
assert.strictEqual(N.originLanguage("NOVEL"), "")
assert.deepStrictEqual(
    N.otherNames(["Re:ZERO -Starting Life in Another World-", "Re:Zero kara Hajimeru", "re zero starting life in another world", "Re:Zero kara Hajimeru", ""],
                 "Re:ZERO -Starting Life in Another World-"),
    ["Re:Zero kara Hajimeru"], "the shown title and repeats are not listed as other names")
assert.deepStrictEqual(N.otherNames(null, "x"), [])
assert.strictEqual(N.authorsText([{ name: "A. Writer", role: "Story" }, { name: "B. Artist" }, { name: "A. Writer" }, null]), "A. Writer, B. Artist")
assert.strictEqual(N.authorsText(undefined), "")

// ── the title page: stamps, the Info key, the sheet that pushes the chapters down ──
const d = files.detail
for (const text of ['text: "TRACKED"', 'Novel.trackScoreText', 'detailView._statusWord', 'detailView._score', 'detailView._year',
                    'text: "Info"', 'infoPanel.toggle()', 'InfoPanel {', 'onTrackRequested: trackSheet.open()'])
    assert(d.includes(text), "DetailView.qml has no " + text)
assert(/transform:\s*Translate\s*\{\s*y:\s*infoPanel\.progress\s*\*\s*lowerArea\.height\s*\}/.test(d),
    "the chapters are not carried down by the sheet")
assert(/id:\s*lowerArea[\s\S]{0,200}clip:\s*true/.test(d), "the lower area must clip, or the sheet shows above the strip")
assert((d.match(/infoPanel\.reset\(\)/g) || []).length >= 2, "the sheet must be put away with the novel and when the page is hidden")
assert.strictEqual((d.match(/^ {4}onVisibleChanged:/gm) || []).length, 1, "more than one onVisibleChanged on the root")
// the search bar, the chapter list, the continue key and the selection bar are all inside the area the sheet pushes
const lowerAt = d.indexOf("id: lowerArea"), infoAt = d.indexOf("id: infoPanel")
for (const id of ["id: chapterSearch", "id: chapterList", "id: continueKey", "id: selectBar"]) {
    const at = d.indexOf(id)
    assert(at > lowerAt && at < infoAt, id + " is not inside the lower area")
}
// the header (cover, stamps, the strip with the Info key) is above it, so it stays in view
for (const id of ["Last read", "LAST READ"]) void id
assert(d.indexOf("text: \"Info\"") < lowerAt, "the Info key must be in the strip above the area the sheet fills")

// ── the sheet ───────────────────────────────────────────────────────────────
const i = files.info
for (const text of ["function open()", "function close()", "function toggle()", "function reset()", "property real progress",
                    "THE TITLE", "TRANSLATION", "RATINGS", "TRACKING", "OTHER NAMES", "GENRES", "TAGS",
                    "Open on AniList", "Novel.infoKnown", "Novel.trackEntry", "Novel.trackScoreText", "Novel.sourceNameFor"])
    assert(i.includes(text), "InfoPanel.qml has no " + text)
assert(/Novel\.alInfoFetch\(\)/.test(i), "opening the sheet does not ask again for a page that has not come")
assert(/onClicked:\s*\{\s*root\.close\(\);\s*root\.trackRequested\(\)\s*\}/.test(i), "the Edit key must close the sheet and open the track sheet")
// no AniList match is not a dead end: the source's own words are still shown, and the sheet says what to do
assert(/_authorsText[\s\S]{0,200}m\.author/.test(i), "a novel with no AniList match has no author line")
assert(/not matched to an AniList novel/.test(i), "the sheet does not explain why it is short")

// ── the service ─────────────────────────────────────────────────────────────
// the match, and so the page and the stamps, no longer wait for a login (tracking still does)
const matchFn = novel.slice(novel.indexOf("function alMatchFetch()"), novel.indexOf("function alMatchFetch()") + 300)
assert(!/alLoggedIn/.test(matchFn.split("\n").slice(0, 3).join("\n")), "the AniList match still waits for a login")
assert(/readonly property bool trackable:\s*\n?\s*alLoggedIn/.test(novel), "tracking must still need the login")
for (const text of ["property var    matchInfo", "function alInfoFetch()", "readonly property bool infoKnown", "readonly property string trackScoreText"])
    assert(novel.includes(text), "Novel.qml has no " + text)
assert(/discoverInfo\(aid, function\(d, err\)/.test(novel), "the page is not asked for with /al/info")
// a page that comes back for another novel is not taken for this one
assert(/rid !== _matchInfoReq/.test(novel), "a late page for another novel is not dropped")
assert(/matchInfoFor === String\(alMatch\.anilistId\)/.test(novel), "infoKnown does not check the page is the match's")
// every place that changes the match keeps the page in step
assert((novel.match(/alInfoFetch\(\)/g) || []).length >= 3, "set / fetch of the match do not refresh the page")
assert(/matchInfo = null\s*\n\s*matchInfoFor = ""/.test(novel), "clearing the match leaves its page behind")

// ── the Library covers ──────────────────────────────────────────────────────
const l = files.library
// built like the manga Saved grid: the whole title over the art, held width while the panel resizes
for (const text of ["fullTitle: true", "holdTitle: false", "ReaderEnv.panelResizing", "ReaderEnv.panelBodyTarget",
                    "NM.sourceTag(Novel.sourceNameFor(libEntry.id))", "CoverProgressBar"])
    assert(l.includes(text), "LibraryView.qml has no " + text)
// ... and says nothing else about the novel on the art: no score, status, year or tracked stamp
for (const text of ["libraryMeta", "TRACKED", "\\u2605", "stamps.", "accentMint"])
    assert(!l.includes(text), "LibraryView.qml still has " + text + " on the cover")
assert((l.match(/ReaderBadge \{/g) || []).length === 1, "the cover wears one tag: its source")
assert(/Novel\.fetchNovelDetail\(libEntry\.id\)/.test(l) && /libraryView\.novelSelected\(libEntry\.id\)/.test(l))
assert(/label:\s*libEntry\.lastReadChapterNum/.test(l) && l.includes('"Not started"'))
// no leftovers of the per-cover AniList lookup
assert(!/library_meta|\/al\/library|fetchLibraryMeta/.test(novel + server + anilist), "the Library lookup is still in the service or backend")

// ── Edit Desktop puts both reader panels away at once ──────────────────────
const host = read(R + "ReaderHost.qml")
assert(/target:\s*FocusService[\s\S]{0,200}function onEditingChanged\(\)/.test(host), "ReaderHost does not follow Edit Desktop")
const handler = host.slice(host.indexOf("function onEditingChanged()"), host.indexOf("function onEditingChanged()") + 200)
assert(/if \(!FocusService\.editing\)\s*return/.test(handler), "the panels must only be put away when editing starts, not when it ends")
assert(/mangaSlot\.minimize\(\)/.test(handler) && /novelSlot\.minimize\(\)/.test(handler), "both panels must be minimized")
assert(!/\.close\(\)|\.hide\(\)/.test(handler), "minimize, not close: what you were reading must still be there")
assert(/readonly property bool editing:\s*EditMode\.active \|\| EditMode\.screenName !== ""/.test(read("services/FocusService.qml")), "FocusService.editing changed")
const hp = check(host, "ReaderHost.qml")
assert.deepStrictEqual(hp, [], hp.join("\n"))


console.log("novel info sheet, stamps and library covers: all checks passed")
