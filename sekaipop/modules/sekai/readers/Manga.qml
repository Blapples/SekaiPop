pragma Singleton
// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.sekai.readers
import "ReaderMath.js" as RM

Singleton {
    id: root

    readonly property string apiUrl: "http://127.0.0.1:5150"

    // ── Source: which site the chapters come from ───────────────────────────
    // The server keeps the choice (provider.json); AniList still does the finding.
    // MangaDex ids start with "md-", Suwayomi ids with "sw-", WeebCentral ids with neither.
    // The server sends the list of sources it offers (Suwayomi only when it is set up), so the
    // Source key cycles through exactly those; the list below is only what shows before it answers.
    property string provider: "weebcentral"
    property string providerLabel: "WeebCentral"
    property var providers: [
        { id: "weebcentral", label: "WeebCentral" },
        { id: "mangadex",    label: "MangaDex"    }
    ]

    function labelForId(id) {
        const s = String(id || "")
        if (s.indexOf("md-") === 0) return "MangaDex"
        if (s.indexOf("sw-") === 0) return "Suwayomi"
        return "WeebCentral"
    }

    // quiet = the caller asks the sources itself next (a pick in the Source key), so no second ask
    function _applyProvider(data, quiet) {
        if (!data || !data.provider) return
        provider = data.provider
        providerLabel = data.label || data.provider
        if (data.providers && data.providers.length > 0) providers = data.providers
        // The Source key lists each picked Suwayomi source by name, so those names are needed
        // whichever site is the current one
        if (!quiet && swOffered) swRefreshActive()
    }

    function fetchProvider() {
        Http.get(root.apiUrl + "/provider", function(err, body) {
            if (err) return
            try { root._applyProvider(JSON.parse(body)) } catch (e) {}
        })
    }

    function setProvider(id) {
        if (id === provider) return
        Http.post(root.apiUrl + "/provider", { provider: id }, function(err, body) {
            if (err) { console.warn("[ServiceManga] could not switch source:", err); return }
            try { root._applyProvider(JSON.parse(body)) } catch (e) { return }
            // The AniList lists stay as they are; only a source's own list has to be asked again.
            root._sourceChanged()
        })
    }

    // ── The Source key's choices ─────────────────────────────────────────────
    // WeebCentral and MangaDex, then (when Suwayomi is set up) every Suwayomi source that is picked,
    // each as a choice of its own: the key shows one name and a tap goes on to the next, so a
    // Suwayomi source behaves exactly like WeebCentral or MangaDex. There is no "all sources at
    // once" choice; with no source picked Suwayomi has no choice at all (the puzzle key opens the
    // Sources page to pick some).
    // { key, provider, focus, label }
    readonly property var sourceChoices: {
        const out = []
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i]
            if (p.id !== "suwayomi") {
                out.push({ key: p.id, provider: p.id, focus: "", label: p.label })
                continue
            }
            const picks = swSources.filter(function(x) { return x.used })
            for (let k = 0; k < picks.length; k++) {
                const x = picks[k]
                // Two sources with one name (a site in two languages) are told apart by the language
                const twin = picks.some(function(o) { return o.id !== x.id && o.name === x.name })
                out.push({ key: "suwayomi:" + x.id, provider: "suwayomi", focus: x.id,
                           label: twin ? x.name + " \u00b7 " + x.lang : x.name })
            }
        }
        return out
    }

    // The key of the choice that is on now. With Suwayomi current, that is the focused source,
    // else the first picked one (_swEnsureFocus tells the server so).
    readonly property string choiceKey: {
        if (provider !== "suwayomi") return provider
        const picks = swSources.filter(function(x) { return x.used })
        if (picks.length === 0) return "suwayomi"
        if (swFocus.length > 0 && picks.some(function(x) { return x.id === swFocus }))
            return "suwayomi:" + swFocus
        return "suwayomi:" + picks[0].id
    }

    function pickChoice(c) {
        if (!c || c.key === choiceKey) return
        if (c.provider === provider) { _swPostFocus(c.focus); return }
        Http.post(root.apiUrl + "/provider", { provider: c.provider }, function(err, body) {
            if (err) { console.warn("[ServiceManga] could not switch source:", err); return }
            try { root._applyProvider(JSON.parse(body), c.provider === "suwayomi") } catch (e) { return }
            if (c.provider === "suwayomi") root._swPostFocus(c.focus)
            // The AniList lists stay as they are; only a source's own list has to be asked again.
            else root._sourceChanged()
        })
    }

    // One key in Browse goes through the choices in turn.
    function cycleProvider() {
        const list = sourceChoices
        if (list.length === 0) return
        let i = -1
        for (let k = 0; k < list.length; k++)
            if (list[k].key === choiceKey) { i = k; break }
        pickChoice(list[(i + 1) % list.length])
    }

    // ── Suwayomi: extensions, repositories and the sources Browse asks ─────────
    // What Suwayomi's own web page does, so nobody has to open it: the Sources page of the panel
    // (SourcesPage.qml) reads and changes all of this through the backend's /sw/* routes.
    readonly property bool swOffered: providers.some(function(p) { return p.id === "suwayomi" })
    property bool   swReady: false          // the backend has answered /sw/status
    property bool   swEnabled: false        // Suwayomi is set up (install-deps.sh, or SEKAIPOP_SW_*)
    property bool   swRunning: false
    property bool   swCustom: false         // the sources were picked by hand (else: automatic)
    property string swLang: "en"
    property var    swExtensions: []        // { pkg, name, lang, version, installed, update, nsfw, icon, repo }
    property var    swLangs: []
    property var    swRepos: []
    property var    swSuggested: []         // { name, url }
    property var    swSources: []           // { id, name, lang, latest, nsfw, used }

    property string swFocus: ""             // the one picked source Browse asks; "" = none chosen yet (the server then asks all picked)

    // The name of the source the Source chip (Browse) and the Library chip show: the name of the
    // choice that is on, else the provider's label.
    readonly property string sourceLabel: {
        const list = sourceChoices
        for (let i = 0; i < list.length; i++)
            if (list[i].key === choiceKey) return list[i].label
        return providerLabel
    }
    property string swError: ""
    property string swNotice: ""
    property bool   swLoading: false        // the extension list is on its way (this may start Suwayomi)
    property bool   swRefreshing: false     // asking the repositories again
    property bool   swBusy: false           // a repository or source change is on its way
    property string swWorking: ""           // the package being installed / updated / removed; "*" = update all

    function _swParse(body, apply) {
        try { apply(JSON.parse(body)); return true }
        catch (e) { swError = "Parse error: " + e; return false }
    }

    // Opening the page: where Suwayomi stands, then (when it is set up) the three lists.
    function swOpen() {
        swError = ""
        swNotice = ""
        Http.get(root.apiUrl + "/sw/status", function(err, body, raw) {
            if (err) { swError = _alMessage(err, raw); return }
            if (!_swParse(body, function(s) {
                swEnabled = s.enabled === true
                swRunning = s.running === true
                swCustom  = s.custom === true
                swLang    = s.lang || "en"
            })) return
            swReady = true
            if (!swEnabled) return
            swLoadRepos()
            swLoadExtensions(false)
            swLoadSources()
        })
    }

    // refresh = true asks every repository again (a round trip over the network)
    function swLoadExtensions(refresh) {
        if (refresh) swRefreshing = true
        else swLoading = true
        Http.get(root.apiUrl + "/sw/extensions" + (refresh ? "?refresh=1" : ""), function(err, body, raw) {
            swLoading = false
            swRefreshing = false
            if (err) { swError = _alMessage(err, raw); return }
            _swParse(body, function(d) {
                swExtensions = d.extensions || []
                swLangs = d.langs || []
                swLang = d.lang || swLang
                swRunning = true
            })
        })
    }

    // install | update | uninstall for one package; "update-all" for every installed one with an update
    function swAction(action, pkg) {
        if (swWorking.length > 0) return
        swWorking = action === "update-all" ? "*" : pkg
        swError = ""
        swNotice = ""
        Http.post(root.apiUrl + "/sw/ext", { action: action, pkg: pkg || "" }, function(err, body, raw) {
            swWorking = ""
            if (err) { swError = _alMessage(err, raw); return }
            _swParse(body, function(d) {
                if (action === "install")
                    swNotice = d.newSources && d.newSources.length > 0
                        ? "Installed. New sources: " + d.newSources.join(", ") : "Installed."
                else if (action === "update-all")
                    swNotice = d.failed && d.failed.length > 0
                        ? "Updated " + d.updated.length + ", " + d.failed.length + " failed (see the server log)."
                        : "Updated " + d.updated.length + "."
                else if (action === "update") swNotice = "Updated."
                else swNotice = "Removed."
            })
            swLoadExtensions(false)
            swLoadSources()
            _swBrowseAgain()
        })
    }

    function swLoadRepos() {
        Http.get(root.apiUrl + "/sw/repos", function(err, body, raw) {
            if (err) { swError = _alMessage(err, raw); return }
            _swParse(body, function(d) { swRepos = d.repos || []; swSuggested = d.suggested || [] })
        })
    }

    // body: { add: url } | { remove: url }. A new repository is read at once, so its extensions show.
    function swChangeRepos(body) {
        if (swBusy) return
        swBusy = true
        swError = ""
        swNotice = ""
        Http.post(root.apiUrl + "/sw/repos", body, function(err, rbody, raw) {
            swBusy = false
            if (err) { swError = _alMessage(err, raw); return }
            _swParse(rbody, function(d) { swRepos = d.repos || []; swSuggested = d.suggested || swSuggested })
            swLoadExtensions(body.add !== undefined)
        })
    }

    function swLoadSources() {
        Http.get(root.apiUrl + "/sw/sources", function(err, body, raw) {
            if (err) { swError = _alMessage(err, raw); return }
            _swApplySources(body)
        })
    }

    // The names for the Source chip, asked without touching the Sources page's error line.
    function swRefreshActive() {
        if (!swOffered) return
        Http.get(root.apiUrl + "/sw/sources", function(err, body) {
            if (err) return
            try {
                const d = JSON.parse(body)
                swSources = d.sources || []
                swCustom = d.custom === true
                swFocus = d.focus || ""
                _swEnsureFocus()
            } catch (e) {}
        })
    }

    function _swApplySources(body) {
        _swParse(body, function(d) {
            swSources = d.sources || []
            swCustom = d.custom === true
            swLang = d.lang || swLang
            swFocus = d.focus || ""
            _swEnsureFocus()
        })
    }

    // Take one source in or out of what Browse and Latest ask
    function swUseSource(id, use) {
        if (swBusy) return
        swBusy = true
        swError = ""
        Http.post(root.apiUrl + "/sw/sources", { id: id, use: use }, function(err, body, raw) {
            swBusy = false
            if (err) { swError = _alMessage(err, raw); return }
            _swApplySources(body)
            _swBrowseAgain()
        })
    }

    function swSourcesAuto() {
        if (swBusy) return
        swBusy = true
        swError = ""
        Http.post(root.apiUrl + "/sw/sources", { auto: true }, function(err, body, raw) {
            swBusy = false
            if (err) { swError = _alMessage(err, raw); return }
            _swApplySources(body)
            _swBrowseAgain()
        })
    }

    // With several sources picked and Suwayomi current, exactly one of them is the choice that is on
    // (the chip names it), so the server is told when it still has no focus, e.g. after a restart.
    function _swEnsureFocus() {
        if (provider !== "suwayomi") return
        const picks = swSources.filter(function(x) { return x.used })
        if (picks.length < 2) return
        if (swFocus.length > 0 && picks.some(function(x) { return x.id === swFocus })) return
        _swPostFocus(picks[0].id)
    }

    function _swPostFocus(id) {
        Http.post(root.apiUrl + "/sw/sources", { focus: id || "" }, function(err, body, raw) {
            if (err) { console.warn("[ServiceManga] could not pick the source:", err); return }
            _swApplySources(body)
            _swBrowseAgain()
        })
    }

    // Another set of sources means another Popular / Latest list
    function _swBrowseAgain() {
        if (provider === "suwayomi") _sourceChanged()
    }

    // ── Manga list ───────────────────────────────────────────────────────────
    property list<var> mangaList: []
    property bool isFetchingManga: false
    property string mangaError: ""
    property bool hasMoreManga: false

    // ── Browse ───────────────────────────────────────────────────────────────
    // "anilist" (the default): Discover, AniList's trending / search / filters (what Seanime's manga
    // page uses); each title is matched to its source's series when opened. "source": the picked
    // source's OWN catalog, the way Mihon browses one: its Popular and Latest lists (and rating /
    // views where it has them). Nothing in it asks AniList.
    property string browseMode: "anilist"
    property string sourceSort: "popular"                    // popular or latest (the server also knows rating and views)
    property var    sourceSorts: ["popular", "latest"]       // what the source answered it offers
    property string browseQuery: ""
    property string browseSort: "TRENDING_DESC"
    property var    browseGenres: []
    property string browseFormat: ""      // "", MANGA, ONE_SHOT
    property string browseCountry: ""     // "", JP, KR, CN
    property var    browseStatuses: []    // any of RELEASING, FINISHED, HIATUS, NOT_YET_RELEASED, CANCELLED; [] = any
    property var    browseTags: []        // AniList tag names (Isekai, School, ...)
    property int    browseScoreMin: 0     // AniList's 0-100 average score; 0 = no limit
    property int    browseScoreMax: 0
    property int    browseYear: 0
    property bool   browseAdult: false
    property int    browsePage: 1
    property int    sourcePage: 1
    // A newer fetch (another filter, more typing) makes an older one's reply a no-op.
    property int    _browseReq: 0

    readonly property int activeFilterCount:
        browseGenres.length + browseTags.length + browseStatuses.length
        + (browseFormat !== "" ? 1 : 0) + (browseCountry !== "" ? 1 : 0)
        + (browseScoreMin > 0 ? 1 : 0) + (browseScoreMax > 0 ? 1 : 0)
        + (browseYear > 0 ? 1 : 0) + (browseAdult ? 1 : 0)

    // AniList's tag list for the tag filter: [{ name, category, isAdult }], asked for the
    // first time the filters are opened (the server keeps it for a week)
    property list<var> tagList: []
    property bool isFetchingTags: false
    property string tagsError: ""

    // ── Manga detail ─────────────────────────────────────────────────────────
    property var currentManga: null
    property bool isFetchingDetail: false
    property string detailError: ""

    // WeebCentral series offered when a title has no match (or the wrong one)
    property list<var> matchCandidates: []
    property bool isFetchingCandidates: false
    property string candidatesError: ""
    property int _candReq: 0

    // ── Chapter pages ────────────────────────────────────────────────────────
    property list<var> chapterPages: []
    property bool isFetchingPages: false
    property string pagesError: ""
    property string currentChapterId: ""
    property bool dataSaverMode: false

    // ── Favorites ────────────────────────────────────────────────────────────
    property list<var> favoritesList: []
    property bool isFetchingFavs: false
    property int favNewCount: 0

    // ── Downloads ────────────────────────────────────────────────────────────
    property list<var> downloadsList: []
    property var downloadProgress: ({})

    // ── Library ──────────────────────────────────────────────────────────────
    // Each entry: { id, title, coverUrl, lastReadChapterId, lastReadChapterNum, lastReadAt, addedAt }
    property list<var> libraryList: []
    property bool libraryLoaded: false

    readonly property string _libraryPath:
        ReaderEnv.dataDir + "/manga/library.json"

    // FileView for reading
    FileView {
        id: libraryFile
        path: root._libraryPath
        onLoaded: {
            try {
                var data = JSON.parse(libraryFile.text())
                root.libraryList = Array.isArray(data) ? data : []
            } catch (e) {
                console.warn("[ServiceManga] library parse error:", e)
                root.libraryList = []
            }
            root.libraryLoaded = true
            console.log("[ServiceManga] Library loaded —", root.libraryList.length, "entries")
        }
        onLoadFailed: {
            // File doesn't exist yet — start empty
            root.libraryList = []
            root.libraryLoaded = true
            console.log("[ServiceManga] No library file found, starting fresh")
        }
    }

    // FileView for writing
    FileView {
        id: libraryWriter
        path: root._libraryPath
    }

    function _saveLibrary() {
        libraryWriter.setText(JSON.stringify(root.libraryList, null, 2))
    }

    function addToLibrary(manga) {
        // manga must have: id, title, coverUrl
        if (isInLibrary(manga.id)) return
        var entry = {
            id:                  manga.id,
            title:               manga.title,
            coverUrl:            manga.coverUrl,
            lastReadChapterId:   "",
            lastReadChapterNum:  "",
            addedAt:             new Date().toISOString()
        }
        root.libraryList = [entry, ...root.libraryList]
        _saveLibrary()
        console.log("[ServiceManga] Added to library:", manga.title)
    }

    function removeFromLibrary(mangaId) {
        root.libraryList = root.libraryList.filter(function(e) { return e.id !== mangaId })
        _saveLibrary()
        console.log("[ServiceManga] Removed from library:", mangaId)
    }

    function isInLibrary(mangaId) {
        return root.libraryList.some(function(e) { return e.id === mangaId })
    }

    function updateLastRead(mangaId, chapterId, chapterNum) {
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== mangaId) return e
            return Object.assign({}, e, {
                lastReadChapterId:  chapterId,
                lastReadChapterNum: chapterNum,
                lastReadAt:         Date.now()     // orders "Jump back in" on the AniList page
            })
        })
        _saveLibrary()
        console.log("[ServiceManga] Last read updated —", mangaId, "ch.", chapterNum)
    }

    function getLibraryEntry(mangaId) {
        for (var i = 0; i < root.libraryList.length; i++) {
            if (root.libraryList[i].id === mangaId) return root.libraryList[i]
        }
        return null
    }

    // ── Read chapters ────────────────────────────────────────────────────────
    // { chapterId: true }. A chapter id belongs to one series of the source, so one flat map
    // serves every title (library or not), and survives changing a title's WeebCentral match.
    property var readMap: ({})

    readonly property string _readPath:
        ReaderEnv.dataDir + "/manga/read.json"

    FileView {
        id: readFile
        path: root._readPath
        onLoaded: {
            try {
                const data = JSON.parse(readFile.text())
                root.readMap = (data && typeof data === "object" && !Array.isArray(data)) ? data : ({})
            } catch (e) {
                console.warn("[ServiceManga] read state parse error:", e)
                root.readMap = ({})
            }
        }
        onLoadFailed: root.readMap = ({})
    }

    FileView {
        id: readWriter
        path: root._readPath
    }

    function isChapterRead(chapterId) {
        return root.readMap[chapterId] === true
    }

    // Marks every id in `ids` read (or unread when `read` is false); writes the file only if
    // something actually changed, so calling it again for a chapter already read costs nothing.
    function setChaptersRead(ids, read) {
        const next = Object.assign({}, root.readMap)
        let changed = false
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i]
            if (!id) continue
            if (read && next[id] !== true)  { next[id] = true; changed = true }
            if (!read && next[id] === true) { delete next[id]; changed = true }
        }
        if (!changed) return
        root.readMap = next
        readWriter.setText(JSON.stringify(next))
        if (read) {
            // a finished chapter has no place to come back to
            root.forgetPages(ids)
            root.trackSoon()
        }
    }

    function markChapterRead(chapterId) { setChaptersRead([chapterId], true) }

    // ── Where you stopped in a chapter ───────────────────────────────────────
    // { chapterId: page index (0-based) } for the chapters begun and not finished, in
    // manga/pages.json. The reader writes it as pages are turned (a moment after the last
    // turn, not on every one); Continue opens the chapter on that page. A chapter marked read
    // drops its entry.
    property var pageMap: ({})

    // Set by Continue to the chapter it is opening, so that chapter opens on its saved page
    // (a tap on a chapter row, or going on to the next chapter, starts from the first page).
    property string resumeChapterId: ""

    readonly property string _pagesPath:
        ReaderEnv.dataDir + "/manga/pages.json"

    FileView {
        id: pagesFile
        path: root._pagesPath
        onLoaded: {
            try {
                const data = JSON.parse(pagesFile.text())
                root.pageMap = (data && typeof data === "object" && !Array.isArray(data)) ? data : ({})
            } catch (e) {
                console.warn("[ServiceManga] page state parse error:", e)
                root.pageMap = ({})
            }
        }
        onLoadFailed: root.pageMap = ({})
    }

    FileView {
        id: pagesWriter
        path: root._pagesPath
    }

    Timer {
        id: pagesSaveTimer
        interval: 700
        onTriggered: pagesWriter.setText(JSON.stringify(root.pageMap))
    }

    // The page saved for a chapter (0 when there is none)
    function savedPage(chapterId) {
        const p = root.pageMap[chapterId]
        return (typeof p === "number" && p > 0) ? Math.floor(p) : 0
    }

    // Remembers `page` for a chapter; page 0 is the start, which needs no entry
    function setSavedPage(chapterId, page) {
        if (!chapterId) return
        if (savedPage(chapterId) === page) return
        const next = Object.assign({}, root.pageMap)
        if (page > 0) next[chapterId] = page
        else          delete next[chapterId]
        root.pageMap = next
        pagesSaveTimer.restart()
    }

    function forgetPages(ids) {
        let next = null
        for (let i = 0; i < ids.length; i++) {
            if (root.pageMap[ids[i]] === undefined) continue
            if (next === null) next = Object.assign({}, root.pageMap)
            delete next[ids[i]]
        }
        if (next === null) return
        root.pageMap = next
        pagesSaveTimer.restart()
    }

    // How many of `chapters` (the objects of currentManga.chapters) are read
    function readCount(chapters) {
        let n = 0
        for (let i = 0; i < chapters.length; i++)
            if (root.readMap[chapters[i].id] === true) n++
        return n
    }

    // Load library as soon as the singleton initialises
    Component.onCompleted: { libraryFile.reload(); readFile.reload(); pagesFile.reload(); trackFile.reload() }

    // ── AniList account ──────────────────────────────────────────────────────
    // Logging in is AniList's implicit grant, run by the backend (manga_server.py, /al/auth/*):
    // alStartLogin() opens AniList in the browser, AniList sends the browser back to a page of
    // the backend, which keeps the token. The token never reaches this file: all it learns is
    // who is logged in. A token can also be pasted (alSubmitToken) when the redirect can't be used.
    property bool   alLoggedIn: false
    property bool   alExpired: false          // a login was kept but its token has run out
    property bool   alHasClientId: false
    property var    alViewer: null            // { id, name, avatar, siteUrl, scoreFormat }
    property string alRedirectUri: "http://127.0.0.1:5150/al/auth/callback"
    // The browser was opened and AniList has not sent it back yet
    property bool   alWaiting: false
    property string alNonce: ""               // proves a pasted token belongs to this login
    property string alError: ""
    property bool   alBusy: false
    property real   _alWaitSince: 0

    function _alApply(json) {
        const s = JSON.parse(json)
        alLoggedIn    = s.loggedIn === true
        alExpired     = s.expired === true
        alHasClientId = s.hasClientId === true
        alViewer      = s.viewer || null
        if (s.redirectUri) alRedirectUri = s.redirectUri
        if (alLoggedIn) { alWaiting = false; alNonce = ""; alError = "" }
    }

    function _alMessage(err, raw) {
        try {
            const j = JSON.parse(raw)
            if (j && j.error) return String(j.error)
        } catch (e) {}
        return "Request failed: " + err
    }

    function alRefresh() {
        Http.get(root.apiUrl + "/al/auth/status", function(err, body) {
            if (err) return
            try { _alApply(body) } catch (e) { console.warn("[ServiceManga] auth status:", e) }
        })
    }

    // Saves the AniList app's client ID (once); with `thenLogin` goes straight on to the login
    function alSetClientId(clientId, thenLogin) {
        alBusy = true
        alError = ""
        Http.post(root.apiUrl + "/al/auth/client", { clientId: clientId }, function(err, body, raw) {
            alBusy = false
            if (err) { alError = _alMessage(err, raw); return }
            try { _alApply(body) } catch (e) { alError = "Parse error: " + e; return }
            if (thenLogin) alStartLogin()
        })
    }

    function alStartLogin() {
        alBusy = true
        alError = ""
        Http.post(root.apiUrl + "/al/auth/start", {}, function(err, body, raw) {
            alBusy = false
            if (err) { alError = _alMessage(err, raw); return }
            try {
                const j = JSON.parse(body)
                alNonce = j.nonce || ""
                if (j.redirectUri) alRedirectUri = j.redirectUri
                alWaiting = true
                _alWaitSince = Date.now()
                Qt.openUrlExternally(j.url)
            } catch (e) {
                alError = "Parse error: " + e
            }
        })
    }

    // A token pasted by hand (the AniList pin page shows one)
    function alSubmitToken(token) {
        if (alNonce === "") { alError = "Start the login first, then paste the token."; return }
        alBusy = true
        alError = ""
        Http.post(root.apiUrl + "/al/auth/token", { token: token, nonce: alNonce }, function(err, body, raw) {
            alBusy = false
            if (err) { alError = _alMessage(err, raw); return }
            try { _alApply(body) } catch (e) { alError = "Parse error: " + e }
        })
    }

    function alCancelLogin() {
        alWaiting = false
        alNonce = ""
        alError = ""
    }

    function alLogout() {
        alBusy = true
        Http.post(root.apiUrl + "/al/auth/logout", {}, function(err, body, raw) {
            alBusy = false
            alWaiting = false
            alNonce = ""
            if (err) { alError = _alMessage(err, raw); return }
            try { _alApply(body) } catch (e) {}
        })
    }

    // While the browser is open: ask the backend every moment whether AniList came back
    Timer {
        interval: 1500
        repeat: true
        running: root.alWaiting
        onTriggered: {
            if (Date.now() - root._alWaitSince > 600000) {
                root.alCancelLogin()
                root.alError = "The login took too long. Try again."
                return
            }
            root.alRefresh()
        }
    }

    // ── AniList tracking ─────────────────────────────────────────────────────
    // With a login, what is read goes on the AniList list (backend /al/track/*): the highest
    // chapter read of the open title is sent a moment after a chapter is marked read, and only
    // ever moves AniList's number up. Works for a title opened from the AniList browse (the ones
    // that have an AniList id). `trackAuto` is the "update as I read" switch (AniList page).
    property bool trackAuto: true
    // "Mark read from AniList": a title already begun on the list opens with its chapters up to
    // AniList's number marked read. Done once per time a title is opened (_adoptedFor), so a
    // chapter you then mark unread stays unread.
    property bool trackAdopt: true
    property string _adoptedFor: ""
    // { anilistId, chapters, volumes, siteUrl, entry: { status, score, score100, progress, progressVolumes } | null }
    property var  trackInfo: null
    property bool trackBusy: false
    property string trackError: ""
    // Said when AniList took a new progress: the reader shows it for a moment
    signal trackUpdated(string text)

    readonly property bool trackable: alLoggedIn && currentManga !== null && currentManga.anilistId > 0

    readonly property var trackStatuses: [
        { id: "CURRENT",   label: "Reading" },
        { id: "PLANNING",  label: "Planning" },
        { id: "COMPLETED", label: "Completed" },
        { id: "PAUSED",    label: "Paused" },
        { id: "DROPPED",   label: "Dropped" },
        { id: "REPEATING", label: "Rereading" }
    ]

    // trackInfo is the open title's own only once it has arrived: until then it can still be the
    // previous title's, which must not show as this one being tracked
    readonly property bool trackKnown: trackInfo !== null && currentManga !== null
        && trackInfo.anilistId === currentManga.anilistId
    // The open title's entry on the user's list (status, score, progress), or null when it is not on it
    readonly property var trackEntry: trackKnown ? trackInfo.entry : null
    // The user's own score for the open title, as their AniList writes it ("8/10"); "" if none
    readonly property string trackScoreText: trackEntry
        ? RM.yourScoreText(trackEntry.score, trackEntry.score100, scoreFormat) : ""

    function trackStatusLabel(id) {
        for (let i = 0; i < trackStatuses.length; i++)
            if (trackStatuses[i].id === id) return trackStatuses[i].label
        return ""
    }

    readonly property string _trackPath: ReaderEnv.dataDir + "/manga/tracking.json"

    FileView {
        id: trackFile
        path: root._trackPath
        onLoaded: {
            try {
                const d = JSON.parse(trackFile.text())
                root.trackAuto  = !(d && d.auto === false)
                root.trackAdopt = !(d && d.adopt === false)
            } catch (e) { root.trackAuto = true; root.trackAdopt = true }
        }
        onLoadFailed: { root.trackAuto = true; root.trackAdopt = true }
    }

    FileView {
        id: trackWriter
        path: root._trackPath
    }

    function _saveTrackPrefs() {
        trackWriter.setText(JSON.stringify({ auto: trackAuto, adopt: trackAdopt }))
    }

    function setTrackAuto(v) {
        trackAuto = v === true
        _saveTrackPrefs()
        if (trackAuto) trackSoon()
    }

    function setTrackAdopt(v) {
        trackAdopt = v === true
        _saveTrackPrefs()
        if (trackAdopt) trackAdoptRead()
    }

    // Marks read the chapters of the open title that AniList already counts as read (its
    // progress, and progressVolumes for volume releases). Only ever marks, never unmarks. It
    // waits for the title's chapter list, and runs once per opening of the title.
    function trackAdoptRead() {
        if (!trackAdopt || !trackKnown || trackEntry === null || !currentManga) return
        const chapters = currentManga.chapters || []
        if (chapters.length === 0) return
        const key = String(currentManga.id)
        if (_adoptedFor === key) return
        _adoptedFor = key
        const ids = RM.chaptersUpTo(chapters, trackEntry.progress || 0, trackEntry.progressVolumes || 0)
        if (ids.length > 0) setChaptersRead(ids, true)
    }

    function _trackApply(body) {
        try {
            const d = JSON.parse(body)
            if (d.error) { trackError = d.error; return false }
            trackInfo = d
            trackError = ""
            return true
        } catch (e) {
            trackError = "Parse error: " + e
            return false
        }
    }

    function _trackFailed(err, raw) {
        trackError = _alMessage(err, raw)
        console.warn("[ServiceManga] tracking:", trackError)
        alRefresh()                   // a login AniList turned down shows as logged out
    }

    // The list entry of the open title (its status and progress), asked when a title opens
    function trackFetch() {
        if (!trackable) { trackInfo = null; return }
        const aid = currentManga.anilistId
        Http.get(root.apiUrl + "/al/track?id=" + aid, function(err, body, raw) {
            if (err) { _trackFailed(err, raw); return }
            if (currentManga && currentManga.anilistId === aid && _trackApply(body)) trackAdoptRead()
        })
    }

    Timer {
        id: trackTimer
        interval: 2500
        onTriggered: root.trackSync()
    }

    // After a chapter was marked read; waits a moment so a run of them is one request
    function trackSoon() {
        if (trackAuto && trackable) trackTimer.restart()
    }

    function trackSync() {
        if (!trackAuto || !trackable) return
        const aid = currentManga.anilistId
        const p = RM.trackProgress(currentManga.chapters, isChapterRead)
        if (p.progress <= 0 && p.volumes <= 0) return
        trackBusy = true
        Http.post(root.apiUrl + "/al/track/progress",
                  { anilistId: aid, progress: p.progress, volumes: p.volumes },
                  function(err, body, raw) {
            trackBusy = false
            if (err) { _trackFailed(err, raw); return }
            let changed = false
            try { changed = JSON.parse(body).changed === true } catch (e) {}
            if (currentManga && currentManga.anilistId === aid && _trackApply(body) && changed)
                trackUpdated(trackInfo.entry
                    ? trackStatusLabel(trackInfo.entry.status) + " \u00b7 ch. " + trackInfo.entry.progress : "")
        })
    }

    // The track sheet: set the status and the number by hand (may lower them)
    function trackSet(status, progress, done) {
        if (!trackable) return
        trackBusy = true
        Http.post(root.apiUrl + "/al/track/set",
                  { anilistId: currentManga.anilistId, status: status, progress: progress },
                  function(err, body, raw) {
            trackBusy = false
            if (err) { _trackFailed(err, raw); return }
            const ok = _trackApply(body)
            if (done) done(ok)
        })
    }

    onAlLoggedInChanged: {
        listEntries = []; listCounts = ({}); listTotal = 0; listLoaded = false; listError = ""
        profile = null; profileError = ""; profileBusy = false; _profileReq++
        overview = null; overviewError = ""; overviewBusy = false; _overviewReq++
        pickEntry = null; pickTotal = 0; pickError = ""; pickBusy = false; _pickReq++
        activity = null; activityBusy = false; _activityReq++
        extras = null; _extrasReq++
        recs = null; _recsReq++
        if (alLoggedIn) trackFetch(); else { trackInfo = null; trackError = "" }
    }

    // ── The AniList profile page ─────────────────────────────────────────────
    // { name, siteUrl, avatar, banner, stats: { count, chaptersRead, volumesRead, meanScore },
    //   favouritesTotal, favourites: [card, ...] } from the backend (/al/profile), which keeps it
    // for two minutes. The page asks whenever it opens; what is already shown stays on screen
    // while it refreshes, so the page never blanks.
    property var    profile: null
    property bool   profileBusy: false
    property string profileError: ""
    property int    _profileReq: 0

    function fetchProfile() {
        if (!alLoggedIn) return
        const rid = ++_profileReq
        profileBusy = true
        // fresh: the page asks for what AniList has now (a new avatar or banner shows at once)
        Http.get(root.apiUrl + "/al/profile?fresh=1", function(err, body, raw) {
            if (rid !== root._profileReq) return
            profileBusy = false
            if (err) {
                profileError = _alMessage(err, raw)
                alRefresh()               // a login AniList turned down shows as logged out
                return
            }
            try {
                const d = JSON.parse(body)
                if (d.error) { profileError = String(d.error); return }
                profile = d
                profileError = ""
                alRefresh()               // the backend kept the new name / avatar: the header key follows
            } catch (e) {
                profileError = "Parse error: " + e
            }
        })
    }

    // ── What the profile page builds from the list ───────────────────────────
    // overview: { counts, scoreFormat, reading: [row, ...], readingTotal, top: [row, ...] } from
    // /al/overview (Reading now, the status bar, Top rated); the rows are the Library's own.
    // The backend cuts it out of the list it already holds, so asking is cheap. Like the profile,
    // what is shown stays on screen while it refreshes.
    property var    overview: null
    property bool   overviewBusy: false
    property string overviewError: ""
    property int    _overviewReq: 0

    function fetchOverview() {
        if (!alLoggedIn) return
        const rid = ++_overviewReq
        overviewBusy = true
        Http.get(root.apiUrl + "/al/overview", function(err, body, raw) {
            if (rid !== root._overviewReq) return
            overviewBusy = false
            if (err) {
                overviewError = _alMessage(err, raw)
                alRefresh()
                return
            }
            try {
                const d = JSON.parse(body)
                if (d.error) { overviewError = String(d.error); return }
                overview = d
                overviewError = ""
            } catch (e) {
                overviewError = "Parse error: " + e
            }
        })
    }

    // "Pick something for me": one random title of the Planning list. `pickEntry` is the Library's
    // row for it (null before the first ask and when Planning is empty), `pickTotal` how many are
    // in Planning. Asked only when the user taps; the id on screen is sent so a reroll differs.
    property var    pickEntry: null
    property int    pickTotal: 0
    property bool   pickBusy: false
    property string pickError: ""
    property int    _pickReq: 0

    function fetchPick() {
        if (!alLoggedIn) return
        const rid = ++_pickReq
        pickBusy = true
        const ex = pickEntry && pickEntry.anilistId ? "?exclude=" + pickEntry.anilistId : ""
        Http.get(root.apiUrl + "/al/pick" + ex, function(err, body, raw) {
            if (rid !== root._pickReq) return
            pickBusy = false
            if (err) { pickError = _alMessage(err, raw); alRefresh(); return }
            try {
                const d = JSON.parse(body)
                if (d.error) { pickError = String(d.error); return }
                pickEntry = d.entry || null
                pickTotal = d.total || 0
                pickError = ""
            } catch (e) {
                pickError = "Parse error: " + e
            }
        })
    }

    // The reading-activity days ({ counts: { "YYYY-MM-DD": n }, total, days, capped }). It takes
    // a few requests on the backend, so it is asked on its own and the page does without it if
    // it fails (no error line: a missing heatmap is not worth one).
    property var    activity: null
    property bool   activityBusy: false
    property int    _activityReq: 0

    function fetchActivity() {
        if (!alLoggedIn) return
        const rid = ++_activityReq
        activityBusy = true
        Http.get(root.apiUrl + "/al/activity", function(err, body, raw) {
            if (rid !== root._activityReq) return
            activityBusy = false
            if (err) return
            try {
                const d = JSON.parse(body)
                if (!d.error) activity = d
            } catch (e) {}
        })
    }

    // What the profile page asks on top of the list, each asked on its own and left out if it fails
    // (no error line: a missing shelf is not worth one).
    //   extras: { color: "#rrggbb" or "", tags: [{ label, count, meanScore }], staff: [{ label, count, meanScore, url }],
    //             feed: [{ id, title, image, status, progress, createdAt }] }  from /al/extras
    //   recs:   { groups: [{ because, becauseId, items: [card, ...] }] }  from /al/recs
    property var    extras: null
    property int    _extrasReq: 0
    property var    recs: null
    property int    _recsReq: 0

    function fetchExtras() {
        if (!alLoggedIn) return
        const rid = ++_extrasReq
        Http.get(root.apiUrl + "/al/extras", function(err, body, raw) {
            if (rid !== root._extrasReq || err) return
            try {
                const d = JSON.parse(body)
                if (!d.error) extras = d
            } catch (e) {}
        })
    }

    function fetchRecs() {
        if (!alLoggedIn) return
        const rid = ++_recsReq
        Http.get(root.apiUrl + "/al/recs", function(err, body, raw) {
            if (rid !== root._recsReq || err) return
            try {
                const d = JSON.parse(body)
                if (!d.error) recs = d
            } catch (e) {}
        })
    }

    // Set by a "Jump back in" card: the title it opens goes straight on to where it was left
    // (the detail page's Continue), instead of waiting for a tap on Continue. Cleared when it
    // fires, when another title is opened, and after a while if it never could.
    property string autoContinueId: ""
    onAutoContinueIdChanged: if (autoContinueId.length > 0) autoContinueTimer.restart()

    Timer {
        id: autoContinueTimer
        interval: 20000
        onTriggered: root.autoContinueId = ""
    }

    // ── The user's AniList lists (the Library's tabs) ────────────────────────
    // Reading / Completed / Dropped / Planning (and Paused / Rereading while they hold
    // something), one status at a time, with the filters and the sort of the Library. The
    // backend (/al/list) reads the whole list from AniList once, keeps it for a minute and cuts
    // the tab, the filters and the sort out of it, so changing any of them is quick. Needs the
    // login above. Nothing here is asked until the Library shows (LibraryView.fetchList()).
    property string listStatus: "CURRENT"
    property string listQuery: ""
    property string listFormat: ""          // "", MANGA, ONE_SHOT, NOVEL
    property string listCountry: ""         // "", JP, KR, CN
    property var    listGenres: []
    property var    listTags: []
    property var    listMStatuses: []       // the title's own status (Releasing, Finished, ...)
    property int    listYear: 0
    property string listSort: "SCORE"       // SCORE, TITLE, PROGRESS, UPDATED, ADDED

    property var    listEntries: []
    property var    listCounts: ({})        // { CURRENT: n, COMPLETED: n, ... }, ignoring the filters
    property int    listTotal: 0            // what the open tab shows after the filters
    property string listScoreFormat: ""
    property bool   listBusy: false
    property bool   listLoaded: false       // the list was read once for this login
    property string listError: ""
    property int    _listReq: 0

    readonly property int activeListFilterCount:
        listGenres.length + listTags.length + listMStatuses.length
        + (listFormat !== "" ? 1 : 0) + (listCountry !== "" ? 1 : 0) + (listYear > 0 ? 1 : 0)

    // How the user's AniList writes scores (POINT_10, POINT_100, ...); "" until known
    readonly property string scoreFormat:
        listScoreFormat !== "" ? listScoreFormat : (alViewer && alViewer.scoreFormat ? alViewer.scoreFormat : "")

    function fetchList() {
        if (!alLoggedIn) return
        const rid = ++_listReq
        listBusy = true
        let url = root.apiUrl + "/al/list?status=" + listStatus + "&sort=" + listSort
        if (listQuery.length > 0)     url += "&q=" + encodeURIComponent(listQuery)
        if (listFormat !== "")        url += "&format=" + listFormat
        if (listCountry !== "")       url += "&country=" + listCountry
        if (listGenres.length > 0)    url += "&genres=" + encodeURIComponent(listGenres.join(","))
        if (listTags.length > 0)      url += "&tags=" + encodeURIComponent(listTags.join("|"))
        if (listMStatuses.length > 0) url += "&mstatus=" + listMStatuses.join(",")
        if (listYear > 0)             url += "&year=" + listYear
        Http.get(url, function(err, body, raw) {
            if (rid !== root._listReq) return
            listBusy = false
            if (err) {
                listError = _alMessage(err, raw)
                alRefresh()               // a login AniList turned down shows as logged out
                return
            }
            try {
                const d = JSON.parse(body)
                if (d.error) { listError = String(d.error); return }
                listEntries = d.entries || []
                listCounts = d.counts || ({})
                listTotal = d.total || 0
                listScoreFormat = d.scoreFormat || ""
                listError = ""
                listLoaded = true
            } catch (e) {
                listError = "Parse error: " + e
            }
        })
    }

    function setListStatus(v)  { if (v === listStatus) return; listStatus = v; listEntries = []; listTotal = 0; fetchList() }
    function setListSort(v)    { listSort = v; fetchList() }
    function setListQuery(v)   { if (v === listQuery) return; listQuery = v; fetchList() }
    function setListFormat(v)  { listFormat = v; fetchList() }
    function setListCountry(v) { listCountry = v; fetchList() }
    function setListYear(v)    { listYear = v; fetchList() }
    function toggleListGenre(g) {
        const i = listGenres.indexOf(g)
        listGenres = i >= 0 ? listGenres.filter(x => x !== g) : [...listGenres, g]
        fetchList()
    }
    function toggleListTag(t) {
        const i = listTags.indexOf(t)
        listTags = i >= 0 ? listTags.filter(x => x !== t) : [...listTags, t]
        fetchList()
    }
    function toggleListMStatus(v) {
        const i = listMStatuses.indexOf(v)
        listMStatuses = i >= 0 ? listMStatuses.filter(x => x !== v) : [...listMStatuses, v]
        fetchList()
    }
    function clearListFilters() {
        listGenres = []; listTags = []; listMStatuses = []
        listFormat = ""; listCountry = ""; listYear = 0
        fetchList()
    }

    // ── Backend server ───────────────────────────────────────────────────────
    property bool serverReady: false

    Process {
        id: serverProcess
        command: ReaderEnv.command(ReaderEnv.scripts + "/manga_server.py")
        running: true
        onExited: (code) => {
            console.warn("[ServiceManga] Server exited with code", code, "— restarting")
            serverReady = false
            restartTimer.start()
        }
    }

    // A pause before restarting, so a server that can't start (port taken,
    // venv missing) isn't respawned in a tight loop.
    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: serverProcess.running = true
    }

    HealthPoller {
        id: healthPoller
        url: root.apiUrl
        onReady: {
            root.serverReady = true
            console.log("[ServiceManga] Backend ready at", root.apiUrl)
            fetchProvider()
            browse(true)
            fetchFavorites()
            fetchDownloads()
            alRefresh()
        }
    }

    Timer {
        id: favChecker
        interval: 900000
        repeat: true
        running: root.serverReady && root.favoritesList.length > 0
        onTriggered: checkFavoritesForUpdates()
    }

    Timer {
        id: dlPoller
        interval: 500
        repeat: true
        running: false
        onTriggered: {
            var hasActive = false
            var ids = Object.keys(root.downloadProgress)
            for (var i = 0; i < ids.length; i++) {
                var st = root.downloadProgress[ids[i]].status
                if (st === "downloading" || st === "pending") { hasActive = true; break }
            }
            if (!hasActive) { dlPoller.stop(); return }
            for (var j = 0; j < ids.length; j++) {
                var s = root.downloadProgress[ids[j]].status
                if (s === "downloading" || s === "pending")
                    _pollOne(ids[j])
            }
        }
    }

    // ── HTTP helpers ──────────────────────────────────────────────────────────


    // ── Browse / Search ───────────────────────────────────────────────────────
    function browse(reset) {
        if (browseMode === "source") { fetchSource(reset); return }
        if (!reset && isFetchingManga) return
        const rid = ++_browseReq
        if (reset) { mangaList = []; browsePage = 1; hasMoreManga = false }
        isFetchingManga = true
        mangaError = ""

        const q = browseQuery.trim()
        let url = root.apiUrl + "/al/browse?page=" + browsePage
        if (q.length > 0) url += "&q=" + encodeURIComponent(q)
        else              url += "&sort=" + browseSort
        if (browseGenres.length > 0) url += "&genres=" + encodeURIComponent(browseGenres.join(","))
        if (browseTags.length > 0)   url += "&tags="   + encodeURIComponent(browseTags.join("|"))
        if (browseFormat  !== "") url += "&format="  + browseFormat
        if (browseCountry !== "") url += "&country=" + browseCountry
        if (browseStatuses.length > 0) url += "&status=" + browseStatuses.join(",")
        if (browseScoreMin > 0)   url += "&score_min=" + browseScoreMin
        if (browseScoreMax > 0)   url += "&score_max=" + browseScoreMax
        if (browseYear > 0)       url += "&year="    + browseYear
        if (browseAdult)          url += "&adult=1"

        Http.get(url, function(err, body) {
            if (rid !== root._browseReq) return
            if (err) { mangaError = "Request failed: " + err; isFetchingManga = false; return }
            _parseBrowse(body)
        })
    }

    // The picked source's own list in the chosen sort (the server asks that site / Suwayomi source).
    function fetchSource(reset) {
        if (!reset && isFetchingManga) return
        const rid = ++_browseReq
        if (reset) { mangaList = []; sourcePage = 1; hasMoreManga = false }
        isFetchingManga = true
        mangaError = ""
        Http.get(root.apiUrl + "/browse?sort=" + sourceSort + "&page=" + sourcePage, function(err, body) {
            if (rid !== root._browseReq) return
            if (err) { mangaError = "Request failed: " + err; isFetchingManga = false; return }
            _parseSource(body)
        })
    }

    // The Popular / Latest tabs and the sort chips of the source list: one state, so Popular as a
    // tab and Popular as a sort are the same thing.
    function setSourceSort(sort) {
        browseQuery = ""
        browseMode = "source"
        sourceSort = sort
        browse(true)
    }

    function showAniList() {
        browseQuery = ""
        browseMode = "anilist"
        browse(true)
    }

    // Another source (or another set of Suwayomi sources) has other sorts, and like opening a
    // source in Mihon it starts on Popular.
    function _sourceChanged() {
        sourceSort = "popular"
        sourceSorts = ["popular", "latest"]
        if (browseMode === "source") browse(true)
    }

    function fetchNextMangaPage() {
        if (!hasMoreManga || isFetchingManga) return
        browse(false)
    }

    // The filters. Each one runs the search again. Changing one while on "latest" goes back
    // to AniList, which is the one that has them.
    function _filtersChanged() {
        if (browseMode === "source") browseMode = "anilist"
        browse(true)
    }
    function toggleGenre(g) {
        const i = browseGenres.indexOf(g)
        browseGenres = i >= 0 ? browseGenres.filter(x => x !== g) : [...browseGenres, g]
        _filtersChanged()
    }
    function setFormat(v)  { browseFormat  = v; _filtersChanged() }
    function setCountry(v) { browseCountry = v; _filtersChanged() }
    function toggleStatus(v) {
        const i = browseStatuses.indexOf(v)
        browseStatuses = i >= 0 ? browseStatuses.filter(x => x !== v) : [...browseStatuses, v]
        _filtersChanged()
    }
    function toggleTag(t) {
        const i = browseTags.indexOf(t)
        browseTags = i >= 0 ? browseTags.filter(x => x !== t) : [...browseTags, t]
        _filtersChanged()
    }
    function setScoreMin(v) {
        browseScoreMin = v
        if (v > 0 && browseScoreMax > 0 && browseScoreMax < v) browseScoreMax = 0
        _filtersChanged()
    }
    function setScoreMax(v) {
        browseScoreMax = v
        if (v > 0 && browseScoreMin > v) browseScoreMin = 0
        _filtersChanged()
    }
    function fetchTags() {
        if (tagList.length > 0 || isFetchingTags) return
        isFetchingTags = true
        tagsError = ""
        Http.get(root.apiUrl + "/al/tags", function(err, body) {
            isFetchingTags = false
            if (err) { tagsError = "Couldn't load the tags: " + err; return }
            try {
                const data = JSON.parse(body)
                if (data.error) { tagsError = data.error; return }
                tagList = data.tags || []
            } catch (e) {
                tagsError = "Parse error: " + e
            }
        })
    }
    function setYear(v)    { browseYear    = v; _filtersChanged() }
    function toggleAdult() { browseAdult   = !browseAdult; _filtersChanged() }
    function clearFilters() {
        browseGenres = []; browseTags = []; browseFormat = ""; browseCountry = ""
        browseStatuses = []; browseScoreMin = 0; browseScoreMax = 0
        browseYear = 0; browseAdult = false
        _filtersChanged()
    }

    function _parseBrowse(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { mangaError = data.error; isFetchingManga = false; return }
            mangaList = [...mangaList, ...(data.results || []).map(item => ({
                id:        item.id        || "",
                anilistId: item.anilistId || 0,
                title:     item.title     || "",
                thumbUrl:  item.image     || "",
                status:    item.status    || "",
                type:      item.type      || "",
                year:      item.year      || 0,
                score:     item.score     || 0,
                author:    ""
            }))]
            hasMoreManga = data.hasMore || false
            browsePage   = data.nextPage || (browsePage + 1)
            mangaError = ""
        } catch (e) {
            mangaError = "Parse error: " + e
            console.error("[ServiceManga]", e)
        }
        isFetchingManga = false
    }

    function _parseSource(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { mangaError = data.error; isFetchingManga = false; return }
            mangaList = [...mangaList, ...(data.results || []).map(item => ({
                id:        item.id     || "",
                anilistId: 0,
                title:     item.title  || "",
                thumbUrl:  item.image  || "",
                status:    item.status || "",
                type:      item.type   || "",
                year:      0,
                score:     0,
                author:    ""
            }))]
            hasMoreManga = data.hasMore || false
            sourcePage   = data.nextPage || (sourcePage + 1)
            if (data.sorts && data.sorts.length > 0) sourceSorts = data.sorts
            mangaError = ""
        } catch (e) {
            mangaError = "Parse error: " + e
            console.error("[ServiceManga]", e)
        }
        isFetchingManga = false
    }

    // ── Manga detail ──────────────────────────────────────────────────────────
    // `mangaId` is "al:<anilist id>" for a title from the AniList browse, else a WeebCentral
    // id (library, favourites, WeebCentral's latest). `keep` leaves the page up while it
    // reloads (after changing the match), so it doesn't blink.
    function fetchMangaDetail(mangaId, keep) {
        if (autoContinueId.length > 0 && autoContinueId !== mangaId) autoContinueId = ""
        if (isFetchingDetail) return
        isFetchingDetail = true
        _adoptedFor = ""
        if (!keep) currentManga = null
        detailError = ""
        const url = mangaId.indexOf("al:") === 0
            ? root.apiUrl + "/al/info?id=" + encodeURIComponent(mangaId.substring(3))
            : root.apiUrl + "/info?id=" + encodeURIComponent(mangaId)
        Http.get(url, function(err, body) {
            if (err) { detailError = "Request failed: " + err; isFetchingDetail = false; return }
            _parseMangaDetail(body)
        })
    }

    function _parseMangaDetail(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { detailError = data.error; isFetchingDetail = false; return }
            currentManga = {
                id:          data.id          || "",
                anilistId:   data.anilistId   || 0,
                title:       data.title       || "",
                description: data.description || "",
                status:      data.status      || "",
                type:        data.type        || "",
                year:        data.year        || 0,
                score:       data.score       || 0,
                coverUrl:    data.image       || "",
                authors:     data.authors     || [],
                tags:        data.tags        || [],
                // The info sheet (AniList; empty for a series AniList does not know)
                statusLabel: data.statusLabel || "",
                genres:      data.genres      || [],
                tagList:     data.tagList     || [],       // [{ name, rank, spoiler, category }]
                altNames:    data.altNames    || [],
                startDate:   data.startDate   || "",
                endDate:     data.endDate     || "",
                endYear:     data.endYear     || 0,
                meanScore:   data.meanScore   || 0,
                popularity:  data.popularity  || 0,
                favourites:  data.favourites  || 0,
                chaptersTotal: data.chaptersTotal || 0,
                volumesTotal:  data.volumesTotal  || 0,
                siteUrl:     data.siteUrl     || "",
                translation: data.translation || null,     // { original, kind, label, sites, licensed }
                match:       data.match       || null,
                unmatched:   data.unmatched === true,
                sourceError: data.sourceError || "",
                chapters:    (data.chapters   || []).map(ch => ({
                    id:        ch.id        || "",
                    chapter:   ch.chapter   || "",
                    kind:      ch.kind      || "chapter",
                    index:     ch.index     !== undefined ? ch.index : 0,
                    title:     ch.title     || "",
                    pages:     0,
                    group:     "",
                    publishAt: ch.publishAt || ""
                }))
            }
            detailError = ""
        } catch (e) {
            detailError = "Parse error: " + e
            console.error("[ServiceManga]", e)
        }
        isFetchingDetail = false
        trackFetch()
    }

    // ── WeebCentral match (which series the chapters come from) ───────────────
    // With no text it lists the best name matches for the open title; with text, a
    // WeebCentral search of that text.
    function fetchMatchCandidates(anilistId, query) {
        const rid = ++_candReq
        isFetchingCandidates = true
        candidatesError = ""
        matchCandidates = []
        let url = root.apiUrl + "/al/candidates?anilistId=" + anilistId
        if (query && query.trim().length > 0) url += "&q=" + encodeURIComponent(query.trim())
        Http.get(url, function(err, body) {
            if (rid !== root._candReq) return
            isFetchingCandidates = false
            if (err) { candidatesError = "Request failed: " + err; return }
            try {
                const data = JSON.parse(body)
                if (data.error) { candidatesError = data.error; return }
                matchCandidates = (data.results || []).map(r => ({
                    id:       r.id     || "",
                    title:    r.title  || "",
                    type:     r.type   || "",
                    year:     r.year   || "",
                    status:   r.status || "",
                    thumbUrl: r.image  || "",
                    score:    r.score  || 0
                }))
            } catch (e) {
                candidatesError = "Parse error: " + e
            }
        })
    }

    function setMatch(anilistId, wcId, title) {
        Http.post(root.apiUrl + "/al/match/set",
            { anilistId: anilistId, id: wcId, title: title },
            function(err, body) { if (!err) fetchMangaDetail("al:" + anilistId, true) })
    }

    function clearMatch(anilistId) {
        Http.post(root.apiUrl + "/al/match/clear", { anilistId: anilistId },
            function(err, body) { if (!err) fetchMangaDetail("al:" + anilistId, true) })
    }

    // ── Chapter pages ─────────────────────────────────────────────────────────
    function fetchChapterPages(chapterId) {
        if (isFetchingPages) return
        isFetchingPages = true
        currentChapterId = chapterId
        chapterPages = []
        pagesError = ""
        const url = root.apiUrl + "/pages?chapterId=" + encodeURIComponent(chapterId)
        Http.get(url, function(err, body) {
            if (err) { pagesError = "Request failed: " + err; isFetchingPages = false; return }
            _parseChapterPages(body)
        })
    }

    function fetchOfflineChapterPages(chapterId) {
        if (isFetchingPages) return
        isFetchingPages = true
        currentChapterId = chapterId
        chapterPages = []
        pagesError = ""
        const url = root.apiUrl + "/dl/pages?chapterId=" + encodeURIComponent(chapterId)
        Http.get(url, function(err, body) {
            if (err) { pagesError = "Request failed: " + err; isFetchingPages = false; return }
            _parseChapterPages(body)
        })
    }

    function _parseChapterPages(json) {
        try {
            const data = JSON.parse(json)
            if (data.error || !Array.isArray(data)) {
                pagesError = data.error || "Invalid response"
                isFetchingPages = false
                return
            }
            if (data.length === 0) {
                pagesError = "No pages found for this chapter"
                isFetchingPages = false
                return
            }
            chapterPages = data.map((p, idx) => ({
                index:     idx,
                url:       p.img || "",
                localPath: p.img || "",
                ready:     true
            }))
            pagesError = ""
            isFetchingPages = false
        } catch (e) {
            pagesError = "Parse error: " + e
            isFetchingPages = false
        }
    }

    // ── Favorites ─────────────────────────────────────────────────────────────
    function fetchFavorites() {
        if (isFetchingFavs) return
        isFetchingFavs = true
        Http.get(root.apiUrl + "/favorites", function(err, body) {
            isFetchingFavs = false
            if (err) { console.warn("[ServiceManga] favorites fetch failed:", err); return }
            try {
                const data = JSON.parse(body)
                favoritesList = data
                favNewCount = data.filter(f => f.hasNewChapters).length
            } catch (e) {
                console.error("[ServiceManga] favorites parse error:", e)
            }
        })
    }

    function addFavorite(manga) {
        const rawUrl = _extractRawUrl(manga.coverUrl)
        Http.post(root.apiUrl + "/favorites/add",
            { id: manga.id, title: manga.title, imageUrl: rawUrl },
                function(err, body) { if (!err) fetchFavorites() })
    }

    function removeFavorite(mangaId) {
        Http.post(root.apiUrl + "/favorites/remove", { id: mangaId },
                function(err, body) { if (!err) fetchFavorites() })
    }

    function isFavorite(mangaId) {
        return favoritesList.some(f => f.id === mangaId)
    }

    function markChapterSeen(mangaId, chapterId) {
        Http.post(root.apiUrl + "/favorites/mark-seen",
            { id: mangaId, chapterId: chapterId },
                function(err, body) { if (!err) fetchFavorites() })
    }

    function checkFavoritesForUpdates() {
        Http.get(root.apiUrl + "/favorites/check", function(err, body) {
            if (err) { console.warn("[ServiceManga] fav check failed:", err); return }
            try {
                const data = JSON.parse(body)
                if (data.updated && data.updated.length > 0) fetchFavorites()
            } catch (e) {}
        })
    }

    // ── Downloads ─────────────────────────────────────────────────────────────
    function fetchDownloads() {
        Http.get(root.apiUrl + "/dl/list", function(err, body) {
            if (err) { console.warn("[ServiceManga] dl/list failed:", err); return }
            try { downloadsList = JSON.parse(body) }
            catch (e) { console.error("[ServiceManga] dl/list parse error:", e) }
        })
    }

    function startDownload(chapter, manga) {
        const rawCover = _extractRawUrl(manga.coverUrl)
        var dp = Object.assign({}, downloadProgress)
        dp[chapter.id] = { status: "pending", total: 0, done: 0 }
        downloadProgress = dp
        dlPoller.start()
        Http.post(root.apiUrl + "/dl/start", {
            mangaId:      manga.id,
            chapterId:    chapter.id,
            chapterNum:   chapter.chapter,
            chapterTitle: chapter.title,
            mangaTitle:   manga.title,
            rawCoverUrl:  rawCover
        }, function(err, body) {
            if (err) {
                var dp2 = Object.assign({}, downloadProgress)
                dp2[chapter.id] = { status: "error", total: 0, done: 0 }
                downloadProgress = dp2
            }
        })
    }

    function _pollOne(chapterId) {
        Http.get(root.apiUrl + "/dl/progress?chapterId=" + encodeURIComponent(chapterId),
                function(err, body) {
                if (err) return
                try {
                    const prog = JSON.parse(body)
                    var dp = Object.assign({}, downloadProgress)
                    dp[chapterId] = prog
                    downloadProgress = dp
                    if (prog.status === "done") fetchDownloads()
                } catch(e) {}
            })
    }

    function getDownloadProgress(chapterId) {
        return downloadProgress[chapterId] || { status: "not_started", total: 0, done: 0 }
    }

    function deleteDownload(chapterId) {
        Http.post(root.apiUrl + "/dl/delete", { chapterId: chapterId },
                function(err, body) { if (!err) fetchDownloads() })
    }

    // ── Utility ───────────────────────────────────────────────────────────────
    function _extractRawUrl(proxyUrl) {
        const match = proxyUrl.match(/[?&]url=([^&]+)/)
        return match ? decodeURIComponent(match[1]) : proxyUrl
    }

    function downloadMorePages(upTo) {}

    function refreshChapterPages() {
        if (currentChapterId.length === 0) return
        chapterPages = []
        fetchChapterPages(currentChapterId)
    }

    function clearChapterList() {
        if (currentManga)
            currentManga = Object.assign({}, currentManga, { chapters: [] })
    }

    function clearChapterPages() {
        chapterPages = []
        currentChapterId = ""
        pagesError = ""
    }

    function clearMangaList() {
        mangaList = []
        hasMoreManga = false
        browsePage = 1
        sourcePage = 1
        mangaError = ""
    }
}
