// Browse: Discover (AniList) is the main way in and the default; the picked source's own lists
// (Popular, Latest, and rating / views where it has them) sit beside it in one switch. Read as text
// (Node can't load QML).
// Run: node tests/manga-reader-test/browse_modes_unit.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const manga = read("modules/sekai/readers/Manga.qml")
const browse = read("modules/sekai/readers/manga/BrowseView.qml")
const seg = read("modules/common/widgets/SegmentSwitch.qml")
const check = require("../lib/qmlcheck.js")

for (const f of ["modules/sekai/readers/manga/BrowseView.qml", "modules/common/widgets/SegmentSwitch.qml"]) {
    const problems = check(read(f), f)
    assert.deepStrictEqual(problems, [], problems.join("\n"))
}

// Opens on Discover
assert(/property string browseMode:\s*"anilist"/.test(manga), "Browse should open on AniList (Discover)")

// One switch, Discover first and the source's name second; it goes through the service, not around it
assert(/SegmentSwitch\s*\{/.test(browse), "Browse has no Discover / source switch")
assert(/id:\s*"anilist",\s*label:\s*"Discover"/.test(browse), "first segment should be Discover")
assert(/id:\s*"source",\s*label:\s*Manga\.sourceLabel/.test(browse), "second segment should be the source's name")
assert(/Manga\.showAniList\(\)/.test(browse) && /Manga\.setSourceSort\(/.test(browse))

// The old Popular / Latest / AniList tab row and its separate AniList sort row are gone
assert(!/showSortRow/.test(browse), "the separate sort row should be folded into the switch row")
assert(!/text:\s*"AniList"/.test(browse), "no AniList tab any more; Discover is the switch's first segment")

// The source's chips come from what the source answered it offers
assert(/Manga\.sourceSorts/.test(browse), "source chips should be built from Manga.sourceSorts")
for (const s of ["popular", "latest", "rating", "views"]) assert(new RegExp(s + ":\\s*\"").test(browse), "no label for the " + s + " sort")

// Filters are Discover's: the key takes the list there first, and the list folds away on the source
assert(/if \(browseView\.sourceMode\) \{ searchBar\.clear\(\); Manga\.showAniList\(\) \}/.test(browse))
assert(/onBrowseModeChanged[\s\S]{0,120}filtersOpen = false/.test(browse))

// The filters key is just an icon (the count rides on its corner), not a "Filters" chip
assert(!/"Filters/.test(browse), "the filters key should have no text")
assert(/ReaderKey\s*\{[^}]*icon:\s*"tune"/.test(browse), "filters should be an icon key")

// A long source name is cut, not spilled over the other segment
assert(/elide:\s*Text\.ElideRight/.test(seg))

console.log("browse modes: all checks passed")
