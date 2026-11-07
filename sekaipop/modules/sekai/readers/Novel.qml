pragma Singleton
// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.sekai.readers

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
    property string activeProvider: "freewebnovel"
    property bool isSwitchingProvider: false
    readonly property var availableProviders: [
        { name: "freewebnovel", label: "FreeWebNovel" },
        { name: "chikari",      label: "Chikari" },
        { name: "novelarrow",   label: "NovelArrow" }
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

    Component.onCompleted: libraryFile.reload()

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
            if (root._migratedIds.length > 0) root._refreshMigratedEntries()
            // A restarted server comes back on its default source; put it back
            // on the one the browser is showing before loading the grid.
            if (root.activeProvider !== "freewebnovel") {
                Http.post(root.apiUrl + "/provider/switch", { provider: root.activeProvider },
                          function(err, body) { fetchHot() })
            } else {
                fetchHot()
            }
        }
    }

    // ── HTTP helpers ──────────────────────────────────────────────────────────


    // ── Browse / Search ───────────────────────────────────────────────────────
    function fetchHot() {
        if (isFetchingNovel) return
        isFetchingNovel = true
        novelError = ""
        novelList = []
        currentSearchText = ""
        currentGenre = ""
        Http.get(root.apiUrl + "/hot", function(err, body) {
            if (err) { novelError = "Request failed: " + err; isFetchingNovel = false; return }
            _parseNovelResults(body, true)
        })
    }

    function fetchLatest(reset) {
        if (isFetchingNovel) return
        if (reset) { novelList = []; latestPage = 1 }
        currentSearchText = ""
        isFetchingNovel = true
        novelError = ""
        Http.get(root.apiUrl + "/latest?page=" + latestPage, function(err, body) {
            if (err) { novelError = "Request failed: " + err; isFetchingNovel = false; return }
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
        Http.get(url, function(err, body) {
            if (err) { novelError = "Request failed: " + err; isFetchingNovel = false; return }
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
            Http.get(url, function(err, body) {
                if (err) { novelError = "Request failed: " + err; isFetchingNovel = false; return }
                _parseNovelResults(body, false)
            })
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

    // ── Novel detail ──────────────────────────────────────────────────────────
    function fetchNovelDetail(novelId) {
        if (isFetchingDetail) return
        isFetchingDetail = true
        _detailId = novelId
        currentNovel = null
        detailError = ""
        const url = root.apiUrl + "/info?id=" + encodeURIComponent(novelId)
        Http.get(url, function(err, body) {
            if (err) { detailError = "Request failed: " + err; isFetchingDetail = false; return }
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
                        title:   ch.title   || ""
                    }
                })
            }
            detailError = ""
        } catch (e) {
            detailError = "Parse error: " + e
            console.error("[ServiceNovel]", e)
        }
        isFetchingDetail = false
    }

    // ── Chapter reading ───────────────────────────────────────────────────────
    function fetchChapter(chapterId) {
        if (isFetchingChapter) return
        isFetchingChapter = true
        currentChapterId = chapterId
        currentChapter = null
        chapterError = ""
        const url = root.apiUrl + "/chapter?id=" + encodeURIComponent(chapterId)
        Http.get(url, function(err, body) {
            if (err) { chapterError = "Request failed: " + err; isFetchingChapter = false; return }
            _parseChapter(body)
        })
    }

    function _parseChapter(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { chapterError = data.error; isFetchingChapter = false; return }
            currentChapter = {
                id:         data.id         || "",
                title:      data.title      || "",
                paragraphs: data.paragraphs || [],
                wordCount:  data.wordCount  || 0,
                prevId:     data.prevId     || "",
                nextId:     data.nextId     || ""
            }
            chapterError = ""
        } catch (e) {
            chapterError = "Parse error: " + e
            console.error("[ServiceNovel]", e)
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
