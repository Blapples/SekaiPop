// The Sources page (Suwayomi's extensions, repositories and sources, inside the manga panel), read as
// text (Node can't load QML): every Manga.swXxx it uses is declared by the service, every /sw/ route the
// service calls is one the server answers, and the page is wired into Browse and the panel.
// Run: node tests/manga-reader-test/sources_page_unit.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const manga = read("modules/sekai/readers/Manga.qml")
const server = read("scripts/readers/manga_server.py")
const page = read("modules/sekai/readers/manga/SourcesPage.qml")
const browse = read("modules/sekai/readers/manga/BrowseView.qml")
const mr = read("modules/sekai/readers/MangaReader.qml")
const check = require("../lib/qmlcheck.js")

for (const f of ["modules/sekai/readers/manga/SourcesPage.qml", "modules/sekai/readers/manga/BrowseView.qml", "modules/sekai/readers/MangaReader.qml"]) {
    const problems = check(read(f), f)
    assert.deepStrictEqual(problems, [], problems.join("\n"))
}

// The service declares what the page and Browse use
const declared = new Set([...manga.matchAll(/^\s*(?:readonly\s+)?property\s+[\w<>]+\s+(sw\w+)/gm)].map(m => m[1])
    .concat([...manga.matchAll(/^\s*function\s+(sw\w+)\(/gm)].map(m => m[1])))
for (const [name, text] of [["SourcesPage.qml", page], ["BrowseView.qml", browse]]) {
    const used = new Set([...text.matchAll(/Manga\.(sw[A-Z]\w*)/g)].map(m => m[1]))
    if (name === "SourcesPage.qml") assert(used.size >= 10, "the page uses almost nothing of the service")
    for (const u of used) assert(declared.has(u), name + ": Manga." + u + " is not declared in Manga.qml")
}

// Every route the service calls is one the server answers (and the server only answers its own people)
const routes = new Set([...manga.matchAll(/root\.apiUrl \+ "(\/sw\/\w+)/g)].map(m => m[1]))
for (const r of ["/sw/status", "/sw/extensions", "/sw/ext", "/sw/repos", "/sw/sources"])
    assert(routes.has(r), "the service never calls " + r)
for (const r of routes) assert(server.includes('"' + r + '"'), "server has no route " + r)
assert(/p\.startswith\("\/sw\/"\):\s*\n\s*if not self\._local_only\(\):/.test(server), "the /sw/ routes must be local only")

// The page's actions are the ones the server accepts
for (const a of ["install", "update", "uninstall", "update-all"]) assert(manga.includes('"' + a + '"') || page.includes('"' + a + '"'), "no " + a + " action")
assert(/if action not in \("install", "update", "uninstall"\)/.test(server))

// Wiring: the key in Browse (only while Suwayomi is offered), the page in the panel
assert(/signal sourcesRequested\(\)/.test(browse) && /visible: Manga\.swOffered/.test(browse) && /icon: "extension"/.test(browse))
assert(/onSourcesRequested: sourcesPage\.open\(\)/.test(mr), "Browse does not open the page")
assert(/SourcesPage \{\s*id: sourcesPage/.test(mr))
assert(/sourcesPage\.close\(\)/.test(mr), "the page must close with the tab / when the AniList page opens")
assert(/readonly property bool swOffered: providers\.some\(/.test(manga))

// An install can take a while: the page shows which row is working, and offers nothing else meanwhile
assert(/Manga\.swWorking === modelData\.pkg/.test(page) && /enabled: Manga\.swWorking\.length === 0/.test(page))
// Installed extensions are always listed; the language and 18+ filters only hide what is not installed yet
assert(/if \(!e\.installed\) \{\s*\n\s*if \(e\.nsfw && !root\.showAdult\) continue/.test(page))
// A new repository is read at once, so its extensions show without a Refresh
assert(/swLoadExtensions\(body\.add !== undefined\)/.test(manga))
// Each picked Suwayomi source is a choice of the Source key, like WeebCentral and MangaDex: the key shows the
// chosen name and a tap goes on to the next; a Suwayomi choice asks the server to focus that one source, and the
// service takes the focus back from every view of the sources the server sends
assert(/readonly property var sourceChoices:/.test(manga) && /function pickChoice\(/.test(manga) && /function cycleProvider\(/.test(manga))
assert(/key: "suwayomi:" \+ x\.id/.test(manga) && /focus: x\.id/.test(manga), "no per-source choice")
assert(/text: Manga\.sourceLabel/.test(browse) && /Manga\.cycleProvider\(\)/.test(browse))
assert(!/swRow|swSetFocus/.test(browse), "Browse must not have its own row of source keys any more")
// No "all sources" choice: every Suwayomi choice is one picked source, and the chip never sits on "all"
assert(!/key: "suwayomi", provider: "suwayomi"/.test(manga), "there must be no all-sources Suwayomi choice")
assert(/function _swEnsureFocus\(/.test(manga) && /picks\[0\]\.id/.test(manga), "several picked sources need one focused")
assert(/let i = -1/.test(manga), "cycling from an unknown choice must start at the first one")
assert(/focus: id \|\| ""/.test(manga) && (manga.match(/swFocus = d\.focus \|\| ""/g) || []).length === 2)
assert(/elif "focus" in body:/.test(server) && /def sw_focus_set\(/.test(server) && /def _sw_ask_sources\(/.test(server))
// The names are asked whenever Suwayomi is offered, not only while it is the current source
assert(/if \(!swOffered\) return/.test(manga))
// One Source chip for every source (no bare swap key for Suwayomi)
assert(!/visible: Manga\.provider (!==|===) "suwayomi"/.test(browse))
// The files exist where the docs say
for (const f of ["modules/sekai/readers/manga/SourcesPage.qml", "scripts/readers/tests/test_suwayomi_manage.py"])
    assert(fs.existsSync(path.join(root, f)), f)
console.log("sources page: all checks passed")
