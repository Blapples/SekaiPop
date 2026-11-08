// The novel panel's Browse header and Sources page, read as text (Node can't load QML): the Source key
// cycles the installed sources like the manga panel's, the second segment of the switch carries the
// source's name, the filters key stays while the source's lists show, and the Sources page has the same
// three tabs as the manga panel's (Extensions, Sources, Repositories) over routes the server answers.
// Run: node tests/novel-reader-test/sources_page_unit.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const novel = read("modules/sekai/readers/Novel.qml")
const browse = read("modules/sekai/readers/novel/BrowseView.qml")
const page = read("modules/sekai/readers/novel/SourcesView.qml")
const server = read("scripts/readers/novel_server/server.py")
const mangaBrowse = read("modules/sekai/readers/manga/BrowseView.qml")
const check = require("../lib/qmlcheck.js")

for (const f of ["modules/sekai/readers/novel/SourcesView.qml", "modules/sekai/readers/novel/BrowseView.qml"]) {
    const problems = check(read(f), f)
    assert.deepStrictEqual(problems, [], problems.join("\n"))
}

// ScriptModel comes from Quickshell: a file that uses it must import it (the panel fails to load otherwise)
for (const [name, text] of [["SourcesView.qml", page], ["BrowseView.qml", browse]])
    if (/\bScriptModel\b/.test(text)) assert(/^import Quickshell$/m.test(text), name + " uses ScriptModel without import Quickshell")

// The service declares everything the page and Browse use of it
const declared = new Set([...novel.matchAll(/^\s*(?:readonly\s+)?property\s+[\w<>]+\s+(\w+)/gm)].map(m => m[1])
    .concat([...novel.matchAll(/^\s*function\s+(\w+)\(/gm)].map(m => m[1])))
for (const [name, text] of [["SourcesView.qml", page], ["BrowseView.qml", browse]]) {
    const used = new Set([...text.matchAll(/\bNovel\.([A-Za-z_]\w*)/g)].map(m => m[1]))
    for (const u of used) assert(declared.has(u), name + ": Novel." + u + " is not declared in Novel.qml")
}

// Every route the service calls is one the server answers
const routes = new Set([...novel.matchAll(/root\.apiUrl \+ "(\/lnreader\/[\w-]+)/g)].map(m => m[1]))
for (const r of ["/lnreader/status", "/lnreader/catalog", "/lnreader/install", "/lnreader/uninstall",
                 "/lnreader/select", "/lnreader/repos", "/lnreader/update-all"])
    assert(routes.has(r), "the service never calls " + r)
for (const r of routes) assert(server.includes('"' + r + '"'), "server has no route " + r)

// ── Browse: the Source key is the manga panel's, with the novel panel's sources behind it ──────────────
// a tap goes to the next installed source (with none installed: the Sources page), and shows its name
assert(/icon: "swap_horiz"/.test(browse) && /Novel\.cycleSource\(\)/.test(browse) && /text: \{[^}]*Novel\.sourceLabel/.test(browse))
assert(/Novel\.sources\.length === 0\) browseView\.sourcesOpen = true/.test(browse), "no way to the Sources page without a source")
assert(/function cycleSource\(\)/.test(novel) && /selectSource\(sources\[\(at \+ 1\) % sources\.length\]\.id\)/.test(novel))
assert(!/providerPopup|providerBox|sourceMenu/.test(browse + novel), "the dropped-down source card is gone")
// the puzzle key beside it, always there (the novel panel has no provider to leave out)
assert(/icon: "extension"\s*\n\s*onClicked: browseView\.sourcesOpen = true/.test(browse))
assert(!/visible: Novel\./.test(browse.slice(browse.indexOf('icon: "extension"') - 200, browse.indexOf('icon: "extension"'))))
// the filters key stays in the source's lists and takes you to Discover, where the filters are
const tune = browse.slice(browse.indexOf('icon: "tune"'), browse.indexOf('icon: "tune"') + 700)
const tuneKey = browse.slice(browse.indexOf("id: tuneKey"), browse.indexOf('icon: "tune"'))
assert(tuneKey.length > 0 && !/visible:/.test(tuneKey), "the filters key must not hide in the source's lists")
assert(/if \(!browseView\.discover\) \{[^}]*Novel\.showDiscover\(\)/.test(tune) && /filtersOpen = !browseView\.filtersOpen/.test(tune))
// the second segment of the switch is the source's name, and the switch is as wide as the longer name needs
assert(/\{ id: "source",\s+label: Novel\.sourceLabel \}/.test(browse) && /text: Novel\.sourceLabel/.test(browse))
assert(!/label: "Source"\s*\}/.test(browse), "the segment still says Source whatever the source")
assert(/Math\.min\(320, Math\.max\(190,/.test(browse))
// it matches the manga panel's header: same heights, same margins
for (const re of [/leftMargin: 16; rightMargin: 16/, /Layout\.preferredHeight: ReaderType\.hField/, /icon: "swap_horiz"/, /icon: "tune"/])
    assert(re.test(browse) && re.test(mangaBrowse), "Browse header differs from the manga panel's: " + re)
// the sort chips of the source's lists are still its own
assert(/\{ label: "Hot",\s+value: "hot"\s+\}/.test(browse) && /\{ label: "Latest", value: "latest" \}/.test(browse))
// the label shows the language when two installed sources share a name
assert(/twin && sources\[i\]\.lang/.test(novel))

// ── The Sources page: the manga panel's three tabs ─────────────────────────────────────────────────────
for (const t of ['text: "Extensions"', 'text: "Sources"', 'text: "Repositories"'])
    assert(page.includes(t), "no tab " + t)
assert(/currentIndex: root\.tab === "extensions" \? 0 : \(root\.tab === "sources" \? 1 : 2\)/.test(page))
assert(/SourcesView \{[^}]*visible: browseView\.sourcesOpen/s.test(browse) && /onClosed: browseView\.sourcesOpen = false/.test(browse))
// it starts on Extensions each time it is shown, and reads the repositories and the list
assert(/onVisibleChanged:[^]*root\.tab = "extensions"[^]*Novel\.fetchRepos\(\)/.test(page))
// Extensions: language, Installed, Update all, Refresh; a row is Install / Update / Remove, one at a time
for (const t of ['icon: "language"', 'text: "Installed"', "Novel.updateAllSources()", "Novel.fetchCatalog(true)",
                 "Novel.installSource(row.modelData.id)", "Novel.uninstallSource(row.modelData.id)"])
    assert(page.includes(t), "Extensions tab lacks " + t)
assert(/enabled: !root\.working/.test(page) && /readonly property bool working: Novel\.sourceBusyId !== ""/.test(page))
// installed ones always show; the language only hides what is not installed yet
assert(/if \(!e\.installed && root\.langPick !== "" && e\.lang !== root\.langPick\) continue/.test(page))
// Sources: the one in use, and a way to switch to another
assert(/text: srow\.current \? "In use" : "Use"/.test(page) && /Novel\.selectSource\(srow\.modelData\.id\)/.test(page))
// Repositories: the list with a bin key each, a field, Add, and the suggested one
assert(/Novel\.changeRepos\(\{ remove: rrow\.modelData\.id \}\)/.test(page) && /Novel\.changeRepos\(\{ add: url \}\)/.test(page))
assert(/model: Novel\.suggestedRepos/.test(page) && /Novel\.changeRepos\(\{ add: modelData\.url \}\)/.test(page))
// a new repository is read at once, so its extensions show without a Refresh
assert(/function changeRepos\(change\)[^]*root\.fetchCatalog\(true\)/.test(novel))
// the old one-address "List" box is gone
assert(!/editingRepo|setRepo|catalogRepo/.test(page + novel + browse))

// the server: several repositories, the legacy one-address call kept, and "official" is a list of its own
const lr = read("scripts/readers/novel_server/providers/lnreader.py")
assert(/def change_repos\(/.test(lr) && /def update_all\(/.test(lr) && /def set_repo\(/.test(lr) && /OFFICIAL_MARK = "official"/.test(lr))
assert(/p == "\/lnreader\/repos"/.test(server) && /p == "\/lnreader\/update-all"/.test(server) && /p == "\/lnreader\/repo"/.test(server))

// the Extensions list puts the installed ones first, then the rest (each in the catalog's order)
{
    const sv = fs.readFileSync(path.join(root, "modules/sekai/readers/novel/SourcesView.qml"), "utf8")
    assert(/have\.concat\(rest\)/.test(sv) && /if \(e\.installed\) have\.push\(e\)/.test(sv), "installed extensions are not listed first")
}

console.log("novel sources page: all checks passed")
