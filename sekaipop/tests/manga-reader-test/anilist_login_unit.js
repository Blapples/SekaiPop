// The AniList login's QML, read as text (Node can't load QML): every Manga.alXxx the panel uses is
// declared by the service, the server routes the service calls exist, and the pieces are wired.
// Run: node tests/manga-reader-test/anilist_login_unit.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const manga = read("modules/sekai/readers/Manga.qml")
const server = read("scripts/readers/manga_server.py")
const users = ["modules/sekai/readers/manga/AniListLogin.qml", "modules/sekai/readers/manga/AccountKey.qml"]

const declared = new Set([...manga.matchAll(/^\s*(?:readonly\s+)?property\s+[\w<>]+\s+(al\w+)/gm)].map(m => m[1])
    .concat([...manga.matchAll(/^\s*function\s+(al\w+)\(/gm)].map(m => m[1])))
for (const f of users) {
    const used = new Set([...read(f).matchAll(/Manga\.(al[A-Z]\w*)/g)].map(m => m[1]))
    assert(used.size > 0, f + " uses nothing of the service")
    for (const u of used) assert(declared.has(u), f + ": Manga." + u + " is not declared in Manga.qml")
}

// Every route the service calls is one the server answers
for (const m of manga.matchAll(/root\.apiUrl \+ "(\/al\/auth\/\w+)"/g))
    assert(server.includes('"' + m[1] + '"'), "server has no route " + m[1])

// The token is never asked for or kept by the QML side
assert(!/anilist_auth|access_token|\bwindow\.location/.test(manga), "Manga.qml must not touch the token")
assert(!/property\s+\w+\s+alToken/.test(manga))

// Wiring
const panel = read("modules/sekai/readers/ReaderPanel.qml")
assert(/property alias headerData: headerExtra\.data/.test(panel), "ReaderPanel has no header slot")
assert(/id: headerExtra/.test(panel))
const mr = read("modules/sekai/readers/MangaReader.qml")
assert(/headerData: AccountKey/.test(mr) && /anilistLogin\.open\(\)/.test(mr))
assert(/AniListLogin \{\s*id: anilistLogin/.test(mr))
assert(/alRefresh\(\)/.test(manga.slice(manga.indexOf("onReady:"), manga.indexOf("onReady:") + 400)), "status not read at start")
// A paste field never shows the token
assert(/secret: true/.test(read("modules/sekai/readers/manga/AniListLogin.qml")))
// Http hands the reply body to the caller on an error (the server explains a refusal in it)
assert(/onDone\("HTTP " \+ xhr\.status, null, xhr\.responseText\)/.test(read("modules/sekai/readers/Http.qml")))
// The files exist where the docs say
for (const f of ["modules/sekai/readers/ReaderField.qml", "modules/sekai/readers/manga/AniListLogin.qml"])
    assert(fs.existsSync(path.join(root, f)), f)
console.log("anilist login: all checks passed")

// The profile page: the server route exists, the service declares what the page uses, and the
// page is wired into the AniList page and the panel
{
    const pp = read("modules/sekai/readers/manga/ProfilePage.qml")
    assert(server.includes('"/al/profile"') && /root\.apiUrl \+ "\/al\/profile[?"]/.test(manga), "profile route not wired")
    for (const name of ["profile", "profileBusy", "profileError", "fetchProfile", "autoContinueId"])
        assert(new RegExp("(property\\s+\\w+\\s+" + name + "\\b|function\\s+" + name + "\\()").test(manga), "Manga." + name + " is not declared")
    for (const used of new Set([...pp.matchAll(/Manga\.(profile\w*|fetchProfile|autoContinueId)/g)].map(m => m[1])))
        assert(new RegExp("(property\\s+\\w+\\s+" + used + "\\b|function\\s+" + used + "\\()").test(manga), "ProfilePage uses undeclared Manga." + used)
    assert(/ProfilePage \{/.test(read("modules/sekai/readers/manga/AniListLogin.qml")), "AniListLogin does not show the profile")
    assert(/onMangaSelected/.test(mr) && /anilistLogin\.close\(\)/.test(mr), "the panel does not open a title picked on the profile")
    assert(/_autoContinueReady/.test(read("modules/sekai/readers/manga/DetailView.qml")), "no auto-continue in the detail page")
    assert(/lastReadAt/.test(manga), "last read time is not kept")
}
console.log("profile page ok")

// The profile page's additions: status bar, random pick, Reading now, Top rated, taste, about
{
    const dir = "modules/sekai/readers/manga/"
    const files = ["ProfilePage", "ProfileHeading", "ProfileStatusBar", "ProfilePick", "ProfileTaste"]
    for (const route of ["/al/overview", "/al/pick", "/al/activity"]) {
        assert(server.includes('"' + route + '"'), route + " is not a server route")
        assert(manga.includes('root.apiUrl + "' + route), "Manga does not ask " + route)
    }
    // every Manga.xxx any of the profile files uses is declared by the service
    for (const f of files) {
        const src = read(dir + f + ".qml")
        for (const used of new Set([...src.matchAll(/Manga\.(\w+)/g)].map(m => m[1])))
            assert(new RegExp("(property\\s+[\\w<>]+\\s+" + used + "\\b|function\\s+" + used + "\\()").test(manga), f + " uses undeclared Manga." + used)
    }
    // the page shows every section, and the old inline heading is gone
    const pp = read(dir + "ProfilePage.qml")
    for (const t of ["ProfileStatusBar {", "ProfilePick {", "ProfileTaste {", "Reading now", "Top rated", 'title: "About"'])
        assert(pp.includes(t), "ProfilePage lacks " + t)
    assert(!/SectionTitle/.test(pp), "the inline SectionTitle should be ProfileHeading now")
    assert(/Manga\.fetchOverview\(\)/.test(pp) && /Manga\.fetchActivity\(\)/.test(pp), "the page does not ask for the overview and activity when it shows")
    assert(/onMangaSelected: function\(id\) \{ root\.mangaSelected\(id\) \}/.test(pp), "the pick does not reach the panel")
    // a login change forgets all of it
    const at = manga.indexOf("onAlLoggedInChanged")
    const reset = manga.slice(at, at + 900)
    for (const r of ["overview = null", "pickEntry = null", "activity = null", "_overviewReq++", "_pickReq++", "_activityReq++"])
        assert(reset.includes(r), "a login change does not reset: " + r)
    // the pick is asked only on a tap, never by the page itself
    assert(!/fetchPick/.test(pp.replace(/\/\/.*$/gm, "")), "the page must not draw a pick by itself")
    // a save drops the copies kept for the profile
    assert(/_cache_drop\("al:activity:"\)/.test(server), "a save does not drop the activity copy")
}
console.log("profile additions ok")
