pragma Singleton
// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.sekai.readers
import "NovelMath.js" as NM

Singleton {
    id: root

    readonly property string apiUrl: "http://127.0.0.1:5151"

    // ── Novel list ───────────────────────────────────────────────────────────
    property list<var> novelList: []
    property bool isFetchingNovel: false
    property string novelError: ""
    property bool hasMoreNovels: false
    property int currentOffset: 0
    property int latestPage: 1
    property string currentSearchText: ""
    property string currentGenre: ""
    property string currentStatus: "All"

    // ── Novel detail ─────────────────────────────────────────────────────────
    property var currentNovel: null
    property bool isFetchingDetail: false
    property string detailError: ""
    // The last novel asked for, so a failed detail fetch can be retried.
    property string _detailId: ""

    // ── Chapter text ─────────────────────────────────────────────────────────
    property var currentChapter: null
    property bool isFetchingChapter: false
    property string chapterError: ""
    property string currentChapterId: ""

    // ── Chapter-list navigation ──────────────────────────────────────────────
    // Prev/Next is driven by the in-memory chapter list (currentNovel.chapters)
    // rather than the scraped prevId/nextId, which are unreliable. The list is
    // sorted ascending by chapter number so navigation works regardless of the
    // order the backend returns chapters in.
    function _chapterNumOf(ch) {
        var m = String(ch).match(/\d+(\.\d+)?/)
        return m ? parseFloat(m[0]) : 0
    }

    readonly property var currentSortedChapters: {
        if (!currentNovel || !currentNovel.chapters) return []
        var arr = currentNovel.chapters.slice()
        arr.sort(function(a, b) { return _chapterNumOf(a.chapter) - _chapterNumOf(b.chapter) })
        return arr
    }

    readonly property int currentChapterIndex: {
        var s = currentSortedChapters
        for (var i = 0; i < s.length; i++)
            if (s[i].id === currentChapterId) return i
        return -1
    }

    readonly property bool hasPrevChapter: currentChapterIndex > 0
    readonly property bool hasNextChapter:
        currentChapterIndex >= 0 && currentChapterIndex < currentSortedChapters.length - 1

    // ── Provider ─────────────────────────────────────────────────────────────
    // The reader's sources are LNReader plugins now: one provider on the backend ("lnreader"),
    // and the Source key picks which installed plugin it browses (see "Sources" below).
    property string activeProvider: "lnreader"
    property bool isSwitchingProvider: false
    readonly property var availableProviders: [
        { name: "lnreader", label: "LNReader" }
    ]

    function switchProvider(name) {
        if (name === activeProvider || isSwitchingProvider) return
        isSwitchingProvider = true
        Http.post(root.apiUrl + "/provider/switch", { provider: name }, function(err, body) {
            isSwitchingProvider = false
            if (err) { console.warn("[ServiceNovel] Provider switch failed:", err); return }
            activeProvider = name
            clearNovelList()
            clearDetail()
            clearChapter()
            fetchHot()
        })
    }

    // ── Sources (LNReader plugins) ───────────────────────────────────────────
    property var sources: []              // installed: [{id, name, lang, site, version, iconUrl}]
    property string activeSource: ""
    property bool sourcesLoaded: false
    readonly property string activeSourceName: {
        for (var i = 0; i < sources.length; i++)
            if (sources[i].id === activeSource) return sources[i].name
        return ""
    }
    // The name the Source key and the second segment of the Browse switch show: the source being
    // browsed (with its language when two installed sources share a name), else \"Source\".
    readonly property string sourceLabel: {
        for (var i = 0; i < sources.length; i++) {
            if (sources[i].id !== activeSource) continue
            var twin = false
            for (var k = 0; k < sources.length; k++)
                if (k !== i && sources[k].name === sources[i].name) twin = true
            return twin && sources[i].lang ? sources[i].name + " · " + sources[i].lang : sources[i].name
        }
        return "Source"
    }

    // The source a novel belongs to (its id is "lnreader:<plugin>~<path>"), which is not always the one
    // being browsed: a Library novel keeps the source it was added from. "" when the id names none.
    function sourceNameFor(novelId) {
        const m = /^lnreader:([^~]+)~/.exec(String(novelId || ""))
        if (!m) return ""
        const id = m[1]
        for (let i = 0; i < sources.length; i++) {
            if (sources[i].id !== id) continue
            let twin = false
            for (let k = 0; k < sources.length; k++)
                if (k !== i && sources[k].name === sources[i].name) twin = true
            return twin && sources[i].lang ? sources[i].name + " \u00b7 " + sources[i].lang : sources[i].name
        }
        return id          // a source that is no longer installed: its id still says where it came from
    }

    property var catalog: []              // every plugin in the LNReader list, with installed / update flags
    property bool isFetchingCatalog: false
    property string catalogError: ""
    property var catalogWarnings: []      // repositories that could not be read in the last round
    property var repos: []                // [{id, name, official}]: where the sources come from
    property var suggestedRepos: []       // [{name, url}]: one tap to add
    property bool repoBusy: false         // a repository change is on its way
    property bool isUpdatingAll: false    // "Update all" is running
    property string sourceBusyId: ""      // the source being installed, removed or switched to
    property string sourceMessage: ""

    // Node and the libraries the plugins load, set up by the backend on first start.
    property string setupState: ""        // ready | installing | missing-node | missing-npm | error
    property string setupMessage: ""

    // Bumped when the source changes, so a reply for the old source is dropped.
    property int _epoch: 0

    // A backend refusal says why in {"error": "..."}; that text beats "HTTP 500".
    function _errText(err, raw) {
        try {
            var d = JSON.parse(raw)
            if (d && d.error) return String(d.error)
        } catch (e) {}
        return "Request failed: " + err
    }

    function fetchSources(done) {
        Http.get(root.apiUrl + "/lnreader/status", function(err, body, raw) {
            if (err) { console.warn("[ServiceNovel] Source list failed:", err); return }
            var wasInstalling = root.setupState === "installing"
            try {
                var d = JSON.parse(body)
                root.sources = d.sources || []
                root.activeSource = d.active || ""
                root.setupState = (d.node && d.node.state) || ""
                root.setupMessage = (d.node && d.node.message) || ""
            } catch (e) {
                console.warn("[ServiceNovel] Source list parse error:", e)
                return
            }
            root.sourcesLoaded = true
            // The libraries finished installing while the grid sat on its error: load it now.
            if (wasInstalling && root.setupState === "ready" && root.activeSource !== ""
                    && root.browseSource === "source"
                    && root.novelList.length === 0 && !root.isFetchingNovel)
                root.fetchHot()
            if (done) done()
        })
    }

    function selectSource(id) {
        if (id === activeSource || sourceBusyId !== "") return
        sourceBusyId = id
        sourceMessage = ""
        Http.post(root.apiUrl + "/lnreader/select", { id: id }, function(err, body, raw) {
            sourceBusyId = ""
            if (err) { sourceMessage = root._errText(err, raw); return }
            activeSource = id
            _epoch++
            isFetchingNovel = false
            clearNovelList()
            clearDetail()
            clearChapter()
            if (root.browseSource === "source") fetchHot()
        })
    }

    // The Source key in Browse goes through the installed sources in turn, like the manga panel's.
    function cycleSource() {
        if (sources.length < 2 || sourceBusyId !== "") return
        var at = -1
        for (var i = 0; i < sources.length; i++)
            if (sources[i].id === activeSource) { at = i; break }
        selectSource(sources[(at + 1) % sources.length].id)
    }

    function fetchCatalog(refresh) {
        if (isFetchingCatalog) return
        isFetchingCatalog = true
        catalogError = ""
        Http.get(root.apiUrl + "/lnreader/catalog" + (refresh ? "?refresh=1" : ""), function(err, body, raw) {
            isFetchingCatalog = false
            if (err) { catalogError = root._errText(err, raw); return }
            try {
                var d = JSON.parse(body)
                root.catalog = d.plugins || []
                root.catalogWarnings = d.warnings || []
            } catch (e) {
                catalogError = "Parse error: " + e
            }
        })
    }

    // The source list and the grid, after something about the installed sources changed.
    function _sourcesChanged(wasActive) {
        fetchSources(function() {
            fetchCatalog(false)
            if (root.activeSource !== wasActive) {
                root._epoch++
                root.isFetchingNovel = false
                clearNovelList()
                clearDetail()
                clearChapter()
                if (root.activeSource !== "" && root.browseSource === "source") fetchHot()
            }
        })
    }

    function installSource(id) {
        if (sourceBusyId !== "") return
        sourceBusyId = id
        sourceMessage = ""
        var wasActive = activeSource
        Http.post(root.apiUrl + "/lnreader/install", { id: id }, function(err, body, raw) {
            sourceBusyId = ""
            if (err) { sourceMessage = root._errText(err, raw); return }
            root._sourcesChanged(wasActive)
        })
    }

    function uninstallSource(id) {
        if (sourceBusyId !== "") return
        sourceBusyId = id
        sourceMessage = ""
        var wasActive = activeSource
        Http.post(root.apiUrl + "/lnreader/uninstall", { id: id }, function(err, body, raw) {
            sourceBusyId = ""
            if (err) { sourceMessage = root._errText(err, raw); return }
            root._sourcesChanged(wasActive)
        })
    }

    // ── Repositories: where the sources come from ───────────────────────────────────────────
    // Each is the address of a plugins.min.json (LNReader's list format); "official" is LNReader's
    // own list. The Extensions tab shows what they list together.
    function fetchRepos() {
        Http.get(root.apiUrl + "/lnreader/repos", function(err, body, raw) {
            if (err) { sourceMessage = root._errText(err, raw); return }
            try {
                var d = JSON.parse(body)
                root.repos = d.repos || []
                root.suggestedRepos = d.suggested || []
            } catch (e) {
                sourceMessage = "Parse error: " + e
            }
        })
    }

    // { add: url } or { remove: id }; the lists are read again at once
    function changeRepos(change) {
        if (repoBusy) return
        repoBusy = true
        sourceMessage = ""
        Http.post(root.apiUrl + "/lnreader/repos", change, function(err, body, raw) {
            repoBusy = false
            if (err) { sourceMessage = root._errText(err, raw); return }
            try {
                var d = JSON.parse(body)
                root.repos = d.repos || []
                root.suggestedRepos = d.suggested || []
            } catch (e) {
                sourceMessage = "Parse error: " + e
                return
            }
            root.catalog = []
            root.fetchCatalog(true)
        })
    }

    // Every installed source that has a newer version
    function updateAllSources() {
        if (isUpdatingAll || sourceBusyId !== "") return
        isUpdatingAll = true
        sourceBusyId = "*"
        sourceMessage = ""
        var wasActive = activeSource
        Http.post(root.apiUrl + "/lnreader/update-all", {}, function(err, body, raw) {
            isUpdatingAll = false
            sourceBusyId = ""
            if (err) { sourceMessage = root._errText(err, raw); return }
            try {
                var d = JSON.parse(body)
                if (d.failed && d.failed.length > 0)
                    sourceMessage = "Could not update " + d.failed.map(function(f) { return f.id }).join(", ")
            } catch (e) {}
            root._sourcesChanged(wasActive)
        })
    }

    // While the libraries install, ask again until they are in place.
    Timer {
        interval: 2500
        repeat: true
        running: root.serverReady && root.setupState === "installing"
        onTriggered: root.fetchSources()
    }

    // ── Library ──────────────────────────────────────────────────────────────
    property list<var> libraryList: []
    property bool libraryLoaded: false

    readonly property string _libraryPath:
        ReaderEnv.dataDir + "/novel/library.json"

    FileView {
        id: libraryFile
        path: root._libraryPath
        onLoaded: {
            try {
                var data = JSON.parse(libraryFile.text())
                root.libraryList = root._migrateNovelbin(Array.isArray(data) ? data : [])
            } catch (e) {
                console.warn("[ServiceNovel] library parse error:", e)
                root.libraryList = []
            }
            root.libraryLoaded = true
            console.log("[ServiceNovel] Library loaded —", root.libraryList.length, "entries")
        }
        onLoadFailed: {
            root.libraryList = []
            root.libraryLoaded = true
            console.log("[ServiceNovel] No library file found, starting fresh")
        }
    }

    FileView {
        id: libraryWriter
        path: root._libraryPath
    }

    function _saveLibrary() {
        libraryWriter.setText(JSON.stringify(root.libraryList, null, 2))
    }

    // NovelBin shut down; its slugs match FreeWebNovel's, so old entries are
    // re-pointed there. Covers/titles came from novelbin and are refreshed
    // from /info once the backend is up (_refreshMigratedEntries).
    property var _migratedIds: []

    function _migrateNovelbin(list) {
        var migrated = []
        var out = list.map(function(e) {
            var m = String(e.id).match(/^novelbin:b\/([^\/]+)$/)
            if (!m) return e
            var slug = m[1]
            var id = "freewebnovel:novel/" + slug
            var ch = String(e.lastReadChapterId || "").match(/\/chapter-(\d+)/)
            migrated.push(id)
            return Object.assign({}, e, {
                id:                id,
                title:             String(e.title).replace(/ Novel - Read .* - Novel Bin$/, ""),
                lastReadChapterId: ch ? id + "/chapter-" + ch[1] : ""
            })
        })
        // Drop duplicates if the novel was also added from FreeWebNovel
        var seen = {}
        out = out.filter(function(e) {
            if (seen[e.id]) return false
            seen[e.id] = true
            return true
        })
        if (migrated.length > 0) {
            console.log("[ServiceNovel] Migrated", migrated.length, "NovelBin library entries to FreeWebNovel")
            root._migratedIds = migrated
            root.libraryList = out
            _saveLibrary()
            if (root.serverReady) root._refreshMigratedEntries()
        }
        return out
    }

    function _refreshMigratedEntries() {
        var ids = root._migratedIds
        root._migratedIds = []
        ids.forEach(function(id) {
            Http.get(root.apiUrl + "/info?id=" + encodeURIComponent(id), function(err, body) {
                if (err) { console.warn("[ServiceNovel] Migrated novel not on FreeWebNovel:", id, err); return }
                try {
                    var info = JSON.parse(body)
                    root.libraryList = root.libraryList.map(function(e) {
                        if (e.id !== id) return e
                        return Object.assign({}, e, {
                            title:    info.title || e.title,
                            coverUrl: info.image || e.coverUrl
                        })
                    })
                    _saveLibrary()
                } catch (e) {
                    console.warn("[ServiceNovel] Migrated info parse error:", e)
                }
            })
        })
    }

    function addToLibrary(novel) {
        if (isInLibrary(novel.id)) return
        var entry = {
            id:                 novel.id,
            title:              novel.title,
            coverUrl:           novel.coverUrl,
            lastReadChapterId:  "",
            lastReadChapterNum: "",
            addedAt:            new Date().toISOString()
        }
        root.libraryList = [entry, ...root.libraryList]
        _saveLibrary()
        console.log("[ServiceNovel] Added to library:", novel.title)
    }

    function removeFromLibrary(novelId) {
        root.libraryList = root.libraryList.filter(function(e) { return e.id !== novelId })
        _saveLibrary()
        console.log("[ServiceNovel] Removed from library:", novelId)
    }

    function isInLibrary(novelId) {
        return root.libraryList.some(function(e) { return e.id === novelId })
    }

    function updateLastRead(novelId, chapterId, chapterNum) {
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== novelId) return e
            return Object.assign({}, e, {
                lastReadChapterId:  chapterId,
                lastReadChapterNum: chapterNum
            })
        })
        _saveLibrary()
        console.log("[ServiceNovel] Last read updated —", novelId, "ch.", chapterNum)
    }

    function getLibraryEntry(novelId) {
        for (var i = 0; i < root.libraryList.length; i++) {
            if (root.libraryList[i].id === novelId) return root.libraryList[i]
        }
        return null
    }

    Component.onCompleted: { libraryFile.reload(); readFile.reload(); trackFile.reload() }

    // ── Backend server ───────────────────────────────────────────────────────
    property bool serverReady: false

    Process {
        id: serverProcess
        command: ReaderEnv.command(ReaderEnv.scripts + "/novel_server/main.py")
        running: true
        onExited: (code) => {
            console.warn("[ServiceNovel] Server exited with code", code, "— restarting")
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
            console.log("[ServiceNovel] Backend ready at", root.apiUrl)
            root.alRefresh()
            if (root._migratedIds.length > 0) root._refreshMigratedEntries()
            // The backend remembers the chosen source across restarts: read it, then load
            // the grid (or leave the "no source yet" card up when none is installed).
            // Discover does not need a source, so it loads at once; the source's own list only
            // when that is the way in that is showing.
            if (root.browseSource === "anilist") root.discoverBrowse(true)
            root.fetchSources(function() {
                if (root.browseSource === "source" && root.activeSource !== "") root.fetchHot()
            })
        }
    }

    // ── HTTP helpers ──────────────────────────────────────────────────────────


    // ── Browse / Search ───────────────────────────────────────────────────────
    // "hot" and "latest" both page; which one the next page continues is browseMode.
    property string browseMode: "hot"
    property int hotPage: 1

    function fetchHot() {
        if (isFetchingNovel) return
        isFetchingNovel = true
        browseMode = "hot"
        hotPage = 1
        novelError = ""
        novelList = []
        currentSearchText = ""
        currentGenre = ""
        _requestHot()
    }

    function _requestHot() {
        var ep = root._epoch
        Http.get(root.apiUrl + "/hot?page=" + hotPage, function(err, body, raw) {
            if (ep !== root._epoch) return
            if (err) { novelError = root._errText(err, raw); isFetchingNovel = false; return }
            _parseNovelResults(body, false)
        })
    }

    function fetchLatest(reset) {
        if (isFetchingNovel) return
        if (reset) { novelList = []; latestPage = 1 }
        browseMode = "latest"
        currentSearchText = ""
        isFetchingNovel = true
        novelError = ""
        var ep = root._epoch
        Http.get(root.apiUrl + "/latest?page=" + latestPage, function(err, body, raw) {
            if (ep !== root._epoch) return
            if (err) { novelError = root._errText(err, raw); isFetchingNovel = false; return }
            _parseNovelResults(body, false)
        })
    }

    function searchNovels(query, genre, status, reset) {
        if (isFetchingNovel) return
        if (reset) { novelList = []; currentOffset = 0 }
        currentSearchText = query
        currentGenre = genre || ""
        currentStatus = status || "All"
        isFetchingNovel = true
        novelError = ""
        var url = root.apiUrl + "/search?q=" + encodeURIComponent(query) + "&page=1"
        if (genre)  url += "&genre="  + encodeURIComponent(genre)
        if (status && status !== "All") url += "&status=" + encodeURIComponent(status)
        var ep = root._epoch
        Http.get(url, function(err, body, raw) {
            if (ep !== root._epoch) return
            if (err) { novelError = root._errText(err, raw); isFetchingNovel = false; return }
            _parseNovelResults(body, false)
        })
    }

    function fetchNextPage() {
        if (!hasMoreNovels || isFetchingNovel) return
        if (currentSearchText.length > 0) {
            currentOffset++
            isFetchingNovel = true
            novelError = ""
            var url = root.apiUrl + "/search?q=" + encodeURIComponent(currentSearchText)
                + "&page=" + (currentOffset + 1)
            if (currentGenre)  url += "&genre="  + encodeURIComponent(currentGenre)
            if (currentStatus && currentStatus !== "All")
                url += "&status=" + encodeURIComponent(currentStatus)
            var ep = root._epoch
            Http.get(url, function(err, body, raw) {
                if (ep !== root._epoch) return
                if (err) { novelError = root._errText(err, raw); isFetchingNovel = false; return }
                _parseNovelResults(body, false)
            })
        } else if (browseMode === "hot") {
            hotPage++
            isFetchingNovel = true
            novelError = ""
            _requestHot()
        } else {
            latestPage++
            fetchLatest(false)
        }
    }

    function _parseNovelResults(json, isHot) {
        try {
            const data = JSON.parse(json)
            if (data.error) { novelError = data.error; isFetchingNovel = false; return }

            const items = isHot ? data : (data.results || [])

            novelList = [...novelList, ...items.map(function(item) {
                return {
                    id:            item.id            || "",
                    title:         item.title         || "",
                    coverUrl:      item.image         || "",
                    author:        item.author        || "",
                    latestChapter: item.latestChapter || "",
                    status:        item.status        || ""
                }
            })]

            hasMoreNovels = isHot ? false : (data.hasMore || false)
            novelError = ""
        } catch (e) {
            novelError = "Parse error: " + e
            console.error("[ServiceNovel]", e)
        }
        isFetchingNovel = false
    }

    // ── Discover (AniList's novels) ──────────────────────────────────────────
    // Browse has two ways in, side by side: Discover (AniList's novels: trending, search and
    // filters; the default) and the picked source's own Hot / Latest lists. A Discover card is a
    // title, not something to read yet: its page (DiscoverInfo) looks the novel up in the picked
    // source, and picking the match opens the novel as any other, with the AniList match kept.
    // The backend is novel_server/anilist.py (/al/browse, /al/tags, /al/info); no login needed.
    property string browseSource: "anilist"       // "anilist" | "source"
    property list<var> discoverList: []
    property bool   isFetchingDiscover: false
    property string discoverError: ""
    property bool   discoverHasMore: false
    property int    discoverPage: 1
    // A newer fetch (another filter, more typing) makes an older one's reply a no-op.
    property int    _discoverReq: 0

    property string discoverQuery: ""
    property string discoverSort: "TRENDING_DESC"
    property var    discoverGenres: []
    property var    discoverTags: []             // AniList tag names (Isekai, Cultivation, ...)
    property string discoverCountry: ""          // "", JP, KR, CN, TW
    property var    discoverStatuses: []         // [] = any
    property int    discoverScoreMin: 0          // AniList's 0-100 average score; 0 = no limit
    property int    discoverScoreMax: 0
    property int    discoverYear: 0
    property string discoverLength: ""           // a NovelMath LENGTHS value; "" = any
    property bool   discoverAdult: false

    function _discoverArgs(page) {
        return {
            query: discoverQuery, sort: discoverSort, genres: discoverGenres, tags: discoverTags,
            country: discoverCountry, statuses: discoverStatuses, scoreMin: discoverScoreMin,
            scoreMax: discoverScoreMax, year: discoverYear, length: discoverLength,
            adult: discoverAdult, page: page
        }
    }

    readonly property int discoverFilterCount: NM.discoverFilterCount(_discoverArgs(1))

    // AniList's tag list for the Tags filter: [{ name, category, isAdult }], asked for the first
    // time the filters are opened (the backend keeps it for a week)
    property list<var> discoverTagList: []
    property bool   isFetchingDiscoverTags: false
    property string discoverTagsError: ""

    function discoverBrowse(reset) {
        const rid = ++_discoverReq
        if (reset) { discoverList = []; discoverPage = 1; discoverHasMore = false }
        isFetchingDiscover = true
        discoverError = ""
        Http.get(root.apiUrl + "/al/browse?" + NM.discoverQuery(_discoverArgs(discoverPage)),
                 function(err, body, raw) {
            if (rid !== root._discoverReq) return
            isFetchingDiscover = false
            if (err) {
                discoverError = root._errText(err, raw)
                discoverHasMore = false        // do not ask again on every scroll; a filter change retries
                return
            }
            try {
                const d = JSON.parse(body)
                if (d.error) { discoverError = String(d.error); discoverHasMore = false; return }
                discoverList = [...discoverList, ...(d.results || []).map(function(c) {
                    return {
                        id:        c.id        || "",
                        anilistId: c.anilistId || 0,
                        title:     c.title     || "",
                        coverUrl:  c.image     || c.cover || "",
                        type:      c.type      || "",
                        status:    c.status    || "",
                        year:      c.year      || 0,
                        score:     c.score     || 0,
                        genres:    c.genres    || [],
                        volumes:   c.volumes   || 0,
                        chapters:  c.chapters  || 0
                    }
                })]
                discoverHasMore = d.hasMore === true
            } catch (e) {
                discoverError = "Parse error: " + e
                discoverHasMore = false
                console.warn("[ServiceNovel] Discover:", e)
            }
        })
    }

    function discoverNextPage() {
        if (!discoverHasMore || isFetchingDiscover) return
        discoverPage++
        discoverBrowse(false)
    }

    function showDiscover() {
        if (browseSource === "anilist") return
        browseSource = "anilist"
        if (discoverList.length === 0 && !isFetchingDiscover) discoverBrowse(true)
    }

    function showSource() {
        if (browseSource === "source") return
        browseSource = "source"
        if (novelList.length === 0 && activeSource !== "" && !isFetchingNovel) fetchHot()
    }

    // The filters. Each one runs the list again.
    function setDiscoverSearch(q) {
        const t = (q || "").trim()
        if (t === discoverQuery) return
        discoverQuery = t
        discoverBrowse(true)
    }
    function setDiscoverSort(v) { discoverSort = v; discoverQuery = ""; discoverBrowse(true) }

    function _toggled(list, v) {
        const i = list.indexOf(v)
        return i >= 0 ? list.filter(function(x) { return x !== v }) : [...list, v]
    }
    function toggleDiscoverGenre(g)  { discoverGenres   = _toggled(discoverGenres, g);   discoverBrowse(true) }
    function toggleDiscoverTag(t)    { discoverTags     = _toggled(discoverTags, t);     discoverBrowse(true) }
    function toggleDiscoverStatus(v) { discoverStatuses = _toggled(discoverStatuses, v); discoverBrowse(true) }
    function setDiscoverCountry(v)   { discoverCountry = v; discoverBrowse(true) }
    function setDiscoverYear(v)      { discoverYear = v;    discoverBrowse(true) }
    function setDiscoverLength(v)    { discoverLength = v;  discoverBrowse(true) }
    function toggleDiscoverAdult()   { discoverAdult = !discoverAdult; discoverBrowse(true) }
    // A minimum above the maximum (or the other way round) would match nothing: the other one
    // is let go.
    function setDiscoverScoreMin(v) {
        discoverScoreMin = v
        if (v > 0 && discoverScoreMax > 0 && discoverScoreMax < v) discoverScoreMax = 0
        discoverBrowse(true)
    }
    function setDiscoverScoreMax(v) {
        discoverScoreMax = v
        if (v > 0 && discoverScoreMin > v) discoverScoreMin = 0
        discoverBrowse(true)
    }
    function clearDiscoverFilters() {
        discoverGenres = []; discoverTags = []; discoverStatuses = []
        discoverCountry = ""; discoverLength = ""
        discoverScoreMin = 0; discoverScoreMax = 0; discoverYear = 0; discoverAdult = false
        discoverBrowse(true)
    }

    function fetchDiscoverTags() {
        if (discoverTagList.length > 0 || isFetchingDiscoverTags) return
        isFetchingDiscoverTags = true
        discoverTagsError = ""
        Http.get(root.apiUrl + "/al/tags", function(err, body, raw) {
            isFetchingDiscoverTags = false
            if (err) { discoverTagsError = root._errText(err, raw); return }
            try { discoverTagList = JSON.parse(body).tags || [] }
            catch (e) { discoverTagsError = "Parse error: " + e }
        })
    }

    // One AniList novel's page: done(info, error)
    function discoverInfo(anilistId, done) {
        Http.get(root.apiUrl + "/al/info?id=" + encodeURIComponent(anilistId), function(err, body, raw) {
            if (err) { done(null, root._errText(err, raw)); return }
            try {
                const d = JSON.parse(body)
                if (d.error) { done(null, String(d.error)); return }
                done(d, "")
            } catch (e) { done(null, "Parse error: " + e) }
        })
    }

    // The picked source's answer to a name, for finding a Discover title in it: done(list, error).
    // Not the grid's search: the Browse list is left as it is.
    function sourceLookup(query, done) {
        const ep = root._epoch
        Http.get(root.apiUrl + "/search?q=" + encodeURIComponent(query) + "&page=1", function(err, body, raw) {
            if (ep !== root._epoch) return           // the source changed meanwhile: the caller asks again
            if (err) { done([], root._errText(err, raw)); return }
            try {
                const d = JSON.parse(body)
                if (d.error) { done([], String(d.error)); return }
                done((d.results || []).map(function(item) {
                    return {
                        id:            item.id            || "",
                        title:         item.title         || "",
                        coverUrl:      item.image         || "",
                        author:        item.author        || "",
                        latestChapter: item.latestChapter || "",
                        status:        item.status        || ""
                    }
                }), "")
            } catch (e) { done([], "Parse error: " + e) }
        })
    }

    // Open a novel of the source that was picked as the one a Discover title is: keep the AniList
    // match first (so tracking is on from the first chapter, with no second guess by name), then
    // open it like a novel tapped in the grid. done() is called once the open has begun.
    function openFromDiscover(novelId, anilistId, title, done) {
        Http.post(root.apiUrl + "/al/match/set", { novelId: novelId, anilistId: anilistId, title: title },
                  function(err, body, raw) {
            if (err) console.warn("[ServiceNovel] AniList match:", _alMessage(err, raw))
            // a match worked out earlier for this novel in this session is out of date now
            if (alMatchFor === novelId) { alMatchFor = ""; alMatch = null }
            fetchNovelDetail(novelId)
            if (done) done()
        })
    }

    // ── Novel detail ──────────────────────────────────────────────────────────
    function fetchNovelDetail(novelId) {
        if (isFetchingDetail) return
        isFetchingDetail = true
        _detailId = novelId
        _adoptedFor = ""
        currentNovel = null
        detailError = ""
        const url = root.apiUrl + "/info?id=" + encodeURIComponent(novelId)
        Http.get(url, function(err, body, raw) {
            if (err) { detailError = root._errText(err, raw); isFetchingDetail = false; return }
            _parseNovelDetail(body)
        })
    }

    function _parseNovelDetail(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { detailError = data.error; isFetchingDetail = false; return }
            currentNovel = {
                id:          data.id          || "",
                title:       data.title       || "",
                description: data.description || "",
                status:      data.status      || "",
                author:      data.author      || "",
                coverUrl:    data.image       || "",
                genres:      data.genres      || [],
                // The site cut the chapter list short; reopening resumes it.
                partial:     data.partial     || false,
                chapters:    (data.chapters || []).map(function(ch) {
                    return {
                        id:      ch.id      || "",
                        chapter: ch.chapter || "",
                        title:   ch.title   || "",
                        // the source's own order, "chapter" or "volume", the volume a chapter sits in
                        index:   ch.index   !== undefined ? ch.index : 0,
                        kind:    ch.kind    || "chapter",
                        volume:  ch.volume  || "",
                        // when the source says it was released: an ISO stamp, or (when the date is
                        // not certain) the source's own words, e.g. "3 months ago"
                        publishAt:    ch.publishAt    || "",
                        releasedText: ch.releasedText || ""
                    }
                })
            }
            detailError = ""
        } catch (e) {
            detailError = "Parse error: " + e
            console.error("[ServiceNovel]", e)
        }
        isFetchingDetail = false
        Qt.callLater(root.alMatchFetch)
    }

    // ── Chapter reading ───────────────────────────────────────────────────────
    // The chapter after the one being read is asked for ahead (prefetchChapter, called by the
    // reader once it is half-way through), so going on to it shows it at once. A few chapters
    // are kept by id; a fetch that finds its chapter here uses it and asks the server nothing.
    property var _chapterCache: ({})
    property var _chapterCacheOrder: []
    property var _prefetching: ({})
    readonly property int _cacheKeep: 4

    // The chapter after the current one: the listed one, else the scraped nextId.
    readonly property string nextChapterId: {
        var s = currentSortedChapters
        if (currentChapterIndex >= 0 && currentChapterIndex < s.length - 1)
            return s[currentChapterIndex + 1].id
        return currentChapter && currentChapter.nextId ? currentChapter.nextId : ""
    }

    function _cachePut(id, chapter) {
        var c = _chapterCache
        var order = _chapterCacheOrder.filter(function(k) { return k !== id })
        c[id] = chapter
        order.push(id)
        while (order.length > _cacheKeep) {
            delete c[order.shift()]
        }
        _chapterCache = c
        _chapterCacheOrder = order
    }

    function _chapterFrom(json) {
        // -> { chapter } or { error }
        try {
            const data = JSON.parse(json)
            if (data.error) return { error: data.error }
            return { chapter: {
                id:         data.id         || "",
                title:      data.title      || "",
                paragraphs: data.paragraphs || [],
                wordCount:  data.wordCount  || 0,
                prevId:     data.prevId     || "",
                nextId:     data.nextId     || ""
            } }
        } catch (e) {
            console.error("[ServiceNovel]", e)
            return { error: "Parse error: " + e }
        }
    }

    // Ask for a chapter in the background. Failures are ignored: the chapter is then fetched
    // the ordinary way when the reader gets there.
    function prefetchChapter(chapterId) {
        if (!chapterId || chapterId.length === 0) return
        if (_chapterCache[chapterId] !== undefined || _prefetching[chapterId] === true) return
        var p = _prefetching
        p[chapterId] = true
        _prefetching = p
        const url = root.apiUrl + "/chapter?id=" + encodeURIComponent(chapterId)
        Http.get(url, function(err, body) {
            var q = root._prefetching
            delete q[chapterId]
            root._prefetching = q
            if (err) return
            const r = root._chapterFrom(body)
            if (r.chapter) root._cachePut(chapterId, r.chapter)
        })
    }

    function fetchChapter(chapterId) {
        if (isFetchingChapter) return
        currentChapterId = chapterId
        chapterError = ""
        const cached = _chapterCache[chapterId]
        if (cached !== undefined) {
            currentChapter = cached
            return
        }
        isFetchingChapter = true
        currentChapter = null
        const url = root.apiUrl + "/chapter?id=" + encodeURIComponent(chapterId)
        Http.get(url, function(err, body, raw) {
            if (err) { chapterError = root._errText(err, raw); isFetchingChapter = false; return }
            _parseChapter(body)
        })
    }

    function _parseChapter(json) {
        const r = _chapterFrom(json)
        if (r.error) {
            chapterError = r.error
        } else {
            currentChapter = r.chapter
            chapterError = ""
            _cachePut(currentChapterId, r.chapter)
        }
        isFetchingChapter = false
    }

    // Fetch a chapter picked from the in-memory list and advance the library
    // entry's last-read marker to it, exactly like selecting it from the
    // chapter list directly.
    function _goToListedChapter(ch) {
        fetchChapter(ch.id)
        if (currentNovel && isInLibrary(currentNovel.id))
            updateLastRead(currentNovel.id, ch.id, ch.chapter)
    }

    function fetchPrevChapter() {
        if (hasPrevChapter) {
            _goToListedChapter(currentSortedChapters[currentChapterIndex - 1])
            return
        }
        // Fallback to scraped prevId if the chapter list is unavailable.
        if (currentChapter && currentChapter.prevId !== "") fetchChapter(currentChapter.prevId)
    }

    function fetchNextChapter() {
        if (hasNextChapter) {
            _goToListedChapter(currentSortedChapters[currentChapterIndex + 1])
            return
        }
        // Fallback to scraped nextId if the chapter list is unavailable.
        if (currentChapter && currentChapter.nextId !== "") fetchChapter(currentChapter.nextId)
    }

    // ── AniList (novels only) ─────────────────────────────────────────────────
    // What is read goes on the user's AniList list, but only for novels: the backend (novel_server/
    // anilist.py, /al/*) searches AniList's NOVEL format only and refuses any other title, so a
    // manga never lands on the list through this reader. The login is the manga reader's (one
    // login serves both; the backend reads its file), so logging in happens in the AniList sheet,
    // which borrows the manga backend's login flow, and the token never reaches QML.
    //
    // A novel from the source is matched to an AniList novel by name (kept per source id, and it can
    // be changed by hand). With a match and a login, a chapter read raises AniList's number: the
    // highest chapter read, never lowering it. `trackAuto` is the "update as I read" switch.
    property bool   alLoggedIn: false
    property bool   alExpired: false
    property var    alViewer: null             // { id, name, avatar, siteUrl, scoreFormat }
    property string alError: ""

    function _alMessage(err, raw) {
        try {
            const j = JSON.parse(raw)
            if (j && j.error) return String(j.error)
        } catch (e) {}
        return "Request failed: " + err
    }

    function alRefresh() {
        Http.get(root.apiUrl + "/al/status", function(err, body) {
            if (err) return
            try {
                const s = JSON.parse(body)
                const was = root.alLoggedIn
                root.alLoggedIn = s.loggedIn === true
                root.alExpired  = s.expired === true
                root.alViewer   = s.viewer || null
                if (root.alLoggedIn && !was) { root.alMatchFetch(); root.trackFetch() }
                if (!root.alLoggedIn) { root.trackInfo = null; root.trackError = "" }
            } catch (e) { console.warn("[ServiceNovel] auth status:", e) }
        })
    }

    // The AniList novel the open novel is: { anilistId, title, manual } or null. `alMatchFor` is
    // the novel it was worked out for (it can still be the previous one's while a new one loads).
    property var    alMatch: null
    property string alMatchFor: ""
    property bool   alMatching: false

    readonly property bool alMatchKnown:
        alMatchFor !== "" && currentNovel !== null && alMatchFor === currentNovel.id
    readonly property bool trackable:
        alLoggedIn && alMatchKnown && alMatch !== null

    // The match and AniList's page of the novel are public, so they are found without a login (the
    // Info sheet and the score stamp need them); only tracking needs the login (`trackable`).
    function alMatchFetch() {
        if (!currentNovel || alMatching) return
        if (alMatchFor === currentNovel.id) return
        const nid = currentNovel.id
        const title = currentNovel.title
        alMatching = true
        Http.get(root.apiUrl + "/al/match?novelId=" + encodeURIComponent(nid)
                 + "&title=" + encodeURIComponent(title), function(err, body, raw) {
            alMatching = false
            if (err) { console.warn("[ServiceNovel] AniList match:", _alMessage(err, raw)); return }
            try {
                const d = JSON.parse(body)
                if (!currentNovel || currentNovel.id !== nid) {
                    // the reader moved on to another novel meanwhile: look for that one
                    Qt.callLater(root.alMatchFetch)
                    return
                }
                alMatch = d.match || null
                alMatchFor = nid
                if (alMatch) trackFetch()
                else trackInfo = null
                alInfoFetch()
            } catch (e) { console.warn("[ServiceNovel] AniList match:", e) }
        })
    }

    // ── AniList's page of the open novel ─────────────────────────────────────
    // What the Info sheet and the stamps in the title's header say: { title, type, status, year,
    // score, genres, tags, names, people, start, end, volumes, chapters, popularity, favourites,
    // siteUrl, ... } (the same page Discover opens, /al/info). It is the matched novel's, found
    // once the match is. `matchInfoFor` is the AniList id it is for.
    property var    matchInfo: null
    property string matchInfoFor: ""
    property bool   matchInfoBusy: false
    property int    _matchInfoReq: 0

    // matchInfo is the open novel's own only once it has arrived and the match is the one it was
    // asked for (until then it can still be the previous novel's)
    readonly property bool infoKnown: matchInfo !== null && alMatch !== null && alMatchKnown
        && matchInfoFor === String(alMatch.anilistId)

    function alInfoFetch() {
        if (!alMatch) { matchInfo = null; matchInfoFor = ""; matchInfoBusy = false; return }
        const aid = String(alMatch.anilistId)
        if (matchInfoFor === aid && matchInfo !== null) return
        const rid = ++_matchInfoReq
        matchInfo = null
        matchInfoFor = ""
        matchInfoBusy = true
        discoverInfo(aid, function(d, err) {
            if (rid !== _matchInfoReq) return            // another novel was asked for meanwhile
            matchInfoBusy = false
            if (err || !d) { console.warn("[ServiceNovel] AniList page:", err); return }
            matchInfo = d
            matchInfoFor = aid
        })
    }

    // AniList novels by name, for picking a match by hand: done(list, error)
    function alSearch(query, done) {
        Http.get(root.apiUrl + "/al/search?q=" + encodeURIComponent(query), function(err, body, raw) {
            if (err) { done([], _alMessage(err, raw)); return }
            try { done(JSON.parse(body), "") } catch (e) { done([], "Parse error: " + e) }
        })
    }

    function alSetMatch(anilistId, title, done) {
        if (!currentNovel) return
        const nid = currentNovel.id
        Http.post(root.apiUrl + "/al/match/set", { novelId: nid, anilistId: anilistId, title: title },
                  function(err, body, raw) {
            if (err) { if (done) done(false, _alMessage(err, raw)); return }
            try {
                const d = JSON.parse(body)
                if (currentNovel && currentNovel.id === nid) {
                    alMatch = d.match || null
                    alMatchFor = nid
                    trackInfo = null
                    _adoptedFor = ""
                    trackFetch()
                    alInfoFetch()
                }
                if (done) done(true, "")
            } catch (e) { if (done) done(false, "Parse error: " + e) }
        })
    }

    function alClearMatch() {
        if (!currentNovel) return
        const nid = currentNovel.id
        Http.post(root.apiUrl + "/al/match/clear", { novelId: nid }, function(err) {
            if (err) return
            alMatch = null
            alMatchFor = ""
            trackInfo = null
            matchInfo = null
            matchInfoFor = ""
            _adoptedFor = ""
            alMatchFetch()           // the automatic match, if there is one
        })
    }

    // ── What is read ──────────────────────────────────────────────────────────
    // A chapter is read once the reader got to its end (the reader calls markRead). Kept by
    // chapter id in readers/novel/read.json.
    property var readMap: ({})
    readonly property string _readPath: ReaderEnv.dataDir + "/novel/read.json"

    FileView {
        id: readFile
        path: root._readPath
        onLoaded: {
            try {
                const d = JSON.parse(readFile.text())
                root.readMap = (d && typeof d === "object" && !Array.isArray(d)) ? d : ({})
            } catch (e) { root.readMap = ({}) }
        }
        onLoadFailed: root.readMap = ({})
    }

    FileView {
        id: readWriter
        path: root._readPath
    }

    Timer {
        id: readSaveTimer
        interval: 700
        onTriggered: readWriter.setText(JSON.stringify(root.readMap))
    }

    function isChapterRead(chapterId) { return root.readMap[chapterId] === true }

    function markRead(chapterId) { setChaptersRead([chapterId], true) }

    // Several chapters at once (one save, one AniList update)
    function markReadMany(ids) { setChaptersRead(ids, true) }

    // Marks every id in `ids` read, or unread when `read` is false. The file is written only when
    // something changed. AniList is told about reads only: it never goes down from here (the track
    // sheet is where a number is lowered by hand).
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
        readSaveTimer.restart()
        if (read) trackSoon()
    }

    // How many of `chapters` (the objects of currentNovel.chapters) are read
    function readCount(chapters) {
        let n = 0
        for (let i = 0; i < (chapters || []).length; i++)
            if (root.readMap[chapters[i].id] === true) n++
        return n
    }

    // The highest chapter number read in the open novel
    function readProgress() {
        return currentNovel ? NM.trackProgress(currentNovel.chapters, isChapterRead) : 0
    }

    // ── Tracking ──────────────────────────────────────────────────────────────
    property bool trackAuto: true
    // "Mark read from AniList": a novel already begun on the list opens with its chapters up to
    // AniList's number marked read. Done once per time a novel is opened (_adoptedFor), so a
    // chapter you then mark unread stays unread.
    property bool trackAdopt: true
    property string _adoptedFor: ""
    // { anilistId, chapters, volumes, siteUrl, entry: { status, score, score100, progress, progressVolumes } | null }
    property var  trackInfo: null
    property bool trackBusy: false
    property string trackError: ""
    // Said when AniList took a new progress: the reader shows it for a moment
    signal trackUpdated(string text)

    readonly property var trackStatuses: NM.TRACK_STATUSES
    function trackStatusLabel(id) { return NM.statusLabel(id) }

    // trackInfo is the open novel's own only once it has arrived: until then it can still be
    // the previous one's, which must not show as this one being tracked
    readonly property bool trackKnown: trackInfo !== null && alMatch !== null
        && trackInfo.anilistId === alMatch.anilistId
    readonly property var trackEntry: trackKnown ? trackInfo.entry : null

    // How the account writes scores (POINT_10, POINT_100, ...); "" until the login has said
    readonly property string scoreFormat: alViewer && alViewer.scoreFormat ? alViewer.scoreFormat : ""
    // Your score of the open novel the way the account writes it ("9/10"), "" when it has none
    readonly property string trackScoreText: trackEntry
        ? NM.yourScoreStamp(trackEntry.score, trackEntry.score100, scoreFormat) : ""

    readonly property string _trackPath: ReaderEnv.dataDir + "/novel/tracking.json"

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

    // Marks read the chapters of the open novel that AniList already counts as read (its
    // progress). Only ever marks, never unmarks, and runs once per opening of the novel.
    function trackAdoptRead() {
        if (!trackAdopt || !trackKnown || trackEntry === null || !currentNovel) return
        const chapters = currentNovel.chapters || []
        if (chapters.length === 0) return
        const key = String(currentNovel.id)
        if (_adoptedFor === key) return
        _adoptedFor = key
        markReadMany(NM.chaptersUpTo(chapters, trackEntry.progress || 0))
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
        console.warn("[ServiceNovel] tracking:", trackError)
        alRefresh()                    // a login AniList turned down shows as logged out
    }

    function trackFetch() {
        if (!trackable) { trackInfo = null; return }
        const aid = alMatch.anilistId
        Http.get(root.apiUrl + "/al/track?id=" + aid, function(err, body, raw) {
            if (err) { _trackFailed(err, raw); return }
            if (alMatch && alMatch.anilistId === aid && _trackApply(body)) trackAdoptRead()
        })
    }

    // A chapter finished: tell AniList in a moment (several in a row go as one)
    Timer {
        id: trackTimer
        interval: 1500
        onTriggered: root.trackSync()
    }

    function trackSoon() {
        if (trackAuto && trackable) trackTimer.restart()
    }

    function trackSync() {
        if (!trackAuto || !trackable) return
        const aid = alMatch.anilistId
        const p = readProgress()
        if (p <= 0) return
        trackBusy = true
        Http.post(root.apiUrl + "/al/track/progress", { anilistId: aid, progress: p },
                  function(err, body, raw) {
            trackBusy = false
            if (err) { _trackFailed(err, raw); return }
            const changed = (function() { try { return JSON.parse(body).changed === true } catch (e) { return false } })()
            if (alMatch && alMatch.anilistId === aid && _trackApply(body) && changed)
                trackUpdated(trackInfo.entry
                    ? trackStatusLabel(trackInfo.entry.status) + " \u00b7 ch. " + trackInfo.entry.progress : "")
        })
    }

    // The track sheet: set the status and the number by hand (may lower them); done(ok)
    function trackSet(status, progress, done) {
        if (!trackable) return
        trackBusy = true
        Http.post(root.apiUrl + "/al/track/set",
                  { anilistId: alMatch.anilistId, status: status, progress: progress },
                  function(err, body, raw) {
            trackBusy = false
            if (err) { _trackFailed(err, raw); if (done) done(false); return }
            const ok = _trackApply(body)
            if (done) done(ok)
        })
    }

    // ── Utility ───────────────────────────────────────────────────────────────
    function clearNovelList() {
        novelList = []
        hasMoreNovels = false
        currentOffset = 0
        latestPage = 1
        novelError = ""
    }

    function clearChapter() {
        currentChapter = null
        currentChapterId = ""
        chapterError = ""
    }

    function retryDetail() {
        if (_detailId.length > 0) fetchNovelDetail(_detailId)
    }

    function clearDetail() {
        currentNovel = null
        detailError = ""
    }
}
