// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// A chapter being read. This holds the state every reading mode shares (which page, the
// colours, the neighbouring chapters, the saved settings) and the keys; the modes themselves
// are StripView (long strip, with or without gaps) and PageStage (paged in three directions,
// and Tablet: two pages joined).
//
//   - which mode a series opens in: the saved one, or the long-strip one for manhwa (the
//     series' type or tags, or else the shape of its first pages), see ReaderMath.js;
//   - W A S D / arrows follow the mode (see ReaderMath.keyAction); the mode is shown for a
//     moment when a chapter opens;
//   - the next chapter is fetched half-way through this one (ChapterPreloader);
//   - Ctrl + wheel, + / - / 0 and a double click zoom; a zoomed page is dragged or moved with the keys;
//   - Ctrl + S, the settings card or a right click save a page as a picture.
Item {
    id: readerView

    // ── Exposed API ──────────────────────────────────────────────────────────
    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    // Emitted when the user navigates back
    signal backRequested()
    signal toggleFullscreen()

    property bool isFullscreen: false

    // ── Internal state ───────────────────────────────────────────────────────
    // The top bar is out of the way while reading: it slides in when the mouse moves and
    // slides out again once the mouse has been still for a moment (it stays while the pointer
    // is on it, or the settings card / page menu is open). `headerPinned` (the H key) keeps it
    // on screen instead.
    property bool headerVisible: true
    property bool headerPinned: false
    property bool settingsOpen: false
    property bool menuOpen: false

    // The mouse cursor goes with the bar's moment: a pointer that has rested for a while on the
    // page (not on the bar, not with the settings card or page menu open) is hidden, and any
    // movement brings it back. The page stages and the progress bar read this for their cursor.
    property bool pointerIdle: false

    function _nudgeHeader() {
        pointerIdle = false
        headerVisible = true
        headerHideTimer.restart()
    }

    onSettingsOpenChanged: { pointerIdle = false; if (!settingsOpen) headerHideTimer.restart() }
    onMenuOpenChanged: { pointerIdle = false; if (!menuOpen) headerHideTimer.restart() }

    Timer {
        id: headerHideTimer
        interval: 1800
        onTriggered: {
            readerView.pointerIdle = !(readerView.settingsOpen || readerView.menuOpen || headerHover.hovered)
            if (readerView.headerPinned || readerView.settingsOpen || readerView.menuOpen
                    || headerHover.hovered)
                return
            readerView.headerVisible = false
        }
    }

    // Any pointer movement over the reader brings the bar back. A HoverHandler only watches:
    // it does not take the pointer away from the page, the progress bar or the buttons.
    //
    // Only a pointer that really moved counts. While a page animates, loads or scrolls under a
    // resting pointer the scene sends hover updates with the same window position; taking each
    // of those for movement kept the bar up for as long as the pointer was over the reader.
    property real _px: -1
    property real _py: -1
    HoverHandler {
        id: pointerWatch
        onHoveredChanged: {
            if (!hovered) {
                readerView._px = -1
                readerView._py = -1
            }
        }
        onPointChanged: {
            const p = point.scenePosition
            if (readerView._px >= 0 && Math.abs(p.x - readerView._px) < 3 && Math.abs(p.y - readerView._py) < 3)
                return
            readerView._px = p.x
            readerView._py = p.y
            readerView._nudgeHeader()
        }
    }

    // The page being looked at (the first page of the two, in Tablet mode).
    property int page: 0
    readonly property int count: Manga.chapterPages.length

    // Called by the parent to reset state when re-entering this view
    function reset() {
        pointerIdle = false
        headerVisible = true
        headerHideTimer.restart()
        settingsOpen = false
        menuOpen = false
        _initFor = ""                 // first, so putting the page back to 0 is not saved as a place
        page = 0
        _announcePending = false
        preload.reset()
        toast.hide()
    }

    // ── Which mode ───────────────────────────────────────────────────────────
    // true = a long-strip series. The series' own type / tags say so when they can; else the
    // shape of this chapter's first pages (remembered for the series in this session).
    readonly property var metaKind: RM.webtoonFromMeta(
        Manga.currentManga ? Manga.currentManga.type : "",
        Manga.currentManga ? Manga.currentManga.tags : [])
    // What the shapes said, by series, for this session (a series is the same shape throughout).
    property var _kindCache: ({})
    readonly property string seriesKey: Manga.currentManga ? String(Manga.currentManga.id) : ""
    readonly property var kind: readerView.metaKind !== null ? readerView.metaKind
        : (readerView._kindCache[readerView.seriesKey] !== undefined ? readerView._kindCache[readerView.seriesKey] : null)
    readonly property bool ready: readerView.count > 0 && readerView.kind !== null

    readonly property string modeId: RM.resolveMode(MangaPrefs.record, readerView.kind === true)
    readonly property var mode: RM.modeInfo(readerView.modeId)
    readonly property string family: readerView.mode.family
    readonly property bool rtl: readerView.mode.dir === "rtl"

    // ── Colours ──────────────────────────────────────────────────────────────
    function bgColorFor(id) {
        switch (id) {
        case "black": return "#000000"
        case "gray":  return "#6f6f74"
        case "white": return "#ffffff"
        default:      return Colors.stage
        }
    }
    readonly property color bg: readerView.bgColorFor(MangaPrefs.background)
    readonly property bool bgLight: readerView.bg.hslLightness > 0.55
    readonly property color fg: readerView.bgLight ? "#1a1a1f" : "#ffffff"
    readonly property color fgDim: Qt.rgba(readerView.fg.r, readerView.fg.g, readerView.fg.b, 0.5)
    readonly property color fgFaint: Qt.rgba(readerView.fg.r, readerView.fg.g, readerView.fg.b, 0.12)
    readonly property color placeholder: readerView.bgLight
        ? Qt.darker(readerView.bg, 1.07) : Qt.tint(readerView.bg, Qt.rgba(1, 1, 1, 0.07))

    // ── Page sizes: what the modes pair, fit and detect from ──────────────────
    property var _sizes: []
    property int sizesRev: 0

    function sizeOf(i) {
        return readerView._sizes[i] || null
    }

    function noteSize(i, w, h) {
        if (w <= 0 || h <= 0)
            return
        const s = readerView._sizes[i]
        if (s && s.w === w && s.h === h)
            return
        readerView._sizes[i] = { w: w, h: h }
        readerView.sizesRev++
        readerView._maybeDecide()
    }

    function _decide(v) {
        if (readerView.kind !== null)
            return
        const c = Object.assign({}, readerView._kindCache)
        c[readerView.seriesKey] = v
        readerView._kindCache = c
    }

    function _maybeDecide() {
        if (readerView.kind !== null)
            return
        const k = RM.looksLikeStrip(readerView._sizes, readerView.count)
        if (k !== null)
            readerView._decide(k)
    }

    // ── What is on screen ────────────────────────────────────────────────────
    readonly property var spreads: {
        readerView.sizesRev
        return readerView.family === "spread" ? RM.buildSpreads(readerView.count, readerView._sizes, MangaPrefs.spreadCover) : []
    }

    readonly property var shown: {
        if (readerView.count === 0)
            return []
        if (readerView.family === "spread" && readerView.spreads.length > 0)
            return readerView.spreads[RM.spreadIndex(readerView.spreads, readerView.page)]
        return [Math.min(readerView.page, readerView.count - 1)]
    }

    readonly property string pageLabel: {
        if (readerView.count === 0)
            return ""
        const s = readerView.shown
        const at = s.length > 1 ? (s[0] + 1) + "\u2013" + (s[s.length - 1] + 1) : String(readerView.page + 1)
        return at + " / " + readerView.count
    }

    // ── Chapters ─────────────────────────────────────────────────────────────
    readonly property var nav: {
        Manga.currentChapterId
        const m = Manga.currentManga
        return RM.chapterNeighbors(m ? m.chapters : [], Manga.currentChapterId)
    }

    function chapterLabel(ch) {
        if (!ch)
            return ""
        if (ch.title && ch.title.length > 0)
            return ch.title
        return (ch.kind === "volume" ? "Volume " : "Chapter ") + ch.chapter
    }

    property string pendingStart: "first"
    property string _initFor: ""
    property bool _announcePending: false
    // The page a chapter was reopened on (0 when it began on the first page)
    property int _resumedAt: 0
    property string _announceKind: "mode"

    // Move to another chapter: the preloaded one when it is there, else fetched as usual.
    // `start` is "first" or "last": which page it opens on (going back lands on the end).
    function openChapter(ch, start) {
        if (!ch)
            return
        readerView.pendingStart = start || "first"
        readerView._announceKind = "chapter"
        const pre = preload.take(ch.id)
        readerView._resetSizes()
        if (pre) {
            Manga.currentChapterId = ch.id
            Manga.pagesError = ""
            Manga.chapterPages = pre
        } else {
            Manga.fetchChapterPages(ch.id)
        }
        if (Manga.currentManga && Manga.isInLibrary(Manga.currentManga.id))
            Manga.updateLastRead(Manga.currentManga.id, ch.id, ch.chapter)
    }

    function nextChapter() {
        // Going on from the last page is finishing the chapter (a one-page chapter has no
        // page change to notice that).
        if (readerView._atEnd())
            readerView._markCurrentRead()
        if (readerView.nav.next)
            readerView.openChapter(readerView.nav.next, "first")
        else
            toast.show("check_circle", "That was the last chapter", "")
    }

    function prevChapter() {
        if (readerView.nav.prev)
            readerView.openChapter(readerView.nav.prev, "last")
        else
            toast.show("danger_circle", "This is the first chapter", "")
    }

    // ── Read state ───────────────────────────────────────────────────────────
    // A chapter counts as read once its last page has been on screen. Arriving on a chapter's
    // last page by going back (`_quiet`) is not reading it.
    property bool _quiet: false
    readonly property bool currentRead: {
        Manga.readMap
        return readerView.nav.current ? Manga.isChapterRead(readerView.nav.current.id) : false
    }

    function _atEnd() {
        const n = readerView.count
        if (n === 0)
            return false
        if (readerView.family === "spread" && readerView.spreads.length > 0) {
            const s = readerView.spreads[RM.spreadIndex(readerView.spreads, readerView.page)]
            return !!s && s.length > 0 && s[s.length - 1] >= n - 1
        }
        return readerView.page >= n - 1
    }

    function _markCurrentRead() {
        if (Manga.currentChapterId.length > 0)
            Manga.markChapterRead(Manga.currentChapterId)
    }

    function _maybeMarkRead() {
        if (readerView._quiet || !readerView.visible || !readerView.ready)
            return
        if (readerView._atEnd())
            readerView._markCurrentRead()
    }

    function toggleCurrentRead() {
        const ch = readerView.nav.current
        if (!ch)
            return
        const was = Manga.isChapterRead(ch.id)
        Manga.setChaptersRead([ch.id], !was)
        toast.show(was ? "eye_closed" : "check_read",
                   was ? "Marked as unread" : "Marked as read",
                   readerView.chapterLabel(ch))
    }

    // What is known about the pages of the chapter that is going (their shapes) is dropped *before* the new pages come in, never after: a page that is already
    // in the image cache reports its size the moment its view is made.
    function _resetSizes() {
        readerView._sizes = []
        readerView.sizesRev++
    }

    onCountChanged: {
        if (readerView.count === 0)
            readerView._resetSizes()
    }

    // A chapter's pages have arrived (or been swapped in): start it afresh.
    function _pagesChanged() {
        if (!readerView.visible || readerView.count === 0)
            return
        readerView._initFor = Manga.currentChapterId
        // Continue opens a chapter that was begun on the page it was left on
        let start = readerView.pendingStart === "last" ? readerView.count - 1 : 0
        readerView._resumedAt = 0
        if (readerView.pendingStart !== "last" && Manga.resumeChapterId === Manga.currentChapterId
                && !Manga.isChapterRead(Manga.currentChapterId)) {
            start = Math.min(readerView.count - 1, Manga.savedPage(Manga.currentChapterId))
            readerView._resumedAt = start
        }
        Manga.resumeChapterId = ""
        readerView._quiet = true
        readerView.page = start
        readerView._quiet = false
        readerView.pendingStart = "first"
        preload.reset()
        readerView._announcePending = true
        readerView._tryAnnounce()
        readerView._maybePreload()
    }

    function _tryAnnounce() {
        if (!readerView._announcePending || !readerView.ready)
            return
        readerView._announcePending = false
        // A Tablet chapter wants the width: the panel takes the screen.
        if (readerView.family === "spread" && !readerView.isFullscreen)
            readerView.toggleFullscreen()
        if (readerView._resumedAt > 0 && readerView.nav.current)
            toast.show("play_arrow", readerView.chapterLabel(readerView.nav.current),
                       "Back on page " + (readerView._resumedAt + 1) + " of " + readerView.count)
        else if (readerView.currentRead && readerView.nav.current)
            toast.show("check_read", readerView.chapterLabel(readerView.nav.current),
                       "Already read \u00b7 " + readerView.mode.label)
        else if (readerView._announceKind === "chapter" && readerView.nav.current)
            toast.show("book", readerView.chapterLabel(readerView.nav.current), readerView.mode.label)
        else
            toast.show(readerView.mode.icon, readerView.mode.label + (MangaPrefs.auto && readerView.kind === true ? " \u00b7 auto" : ""),
                       RM.keysHint(readerView.modeId))
        readerView._announceKind = "mode"
    }

    // Half-way through (or six pages from the end, in a short one): ask for the next chapter.
    function _maybePreload() {
        if (!readerView.visible || readerView.count === 0 || !readerView.nav.next)
            return
        const at = Math.min(Math.floor(readerView.count * 0.5), readerView.count - 6)
        if (readerView.page >= at)
            preload.start(readerView.nav.next.id)
    }

    // Where the reader is in an unfinished chapter, kept for Continue. Not while a chapter is
    // being set up (`_quiet`), not for a chapter already read, and the last page is finishing it.
    function _savePosition() {
        if (readerView._quiet || !readerView.visible || !readerView.ready)
            return
        if (readerView._initFor !== Manga.currentChapterId || readerView.currentRead)
            return
        if (readerView._atEnd())
            return
        Manga.setSavedPage(Manga.currentChapterId, readerView.page)
    }

    onPageChanged: { readerView._maybePreload(); readerView._maybeMarkRead(); readerView._savePosition() }
    onNavChanged: readerView._maybePreload()
    onReadyChanged: readerView._tryAnnounce()

    onVisibleChanged: {
        if (readerView.visible) {
            // opened with the pointer resting: the bar still goes after its moment
            readerView.headerVisible = true
            headerHideTimer.restart()
            readerView.forceActiveFocus()
            if (readerView.count > 0 && readerView._initFor !== Manga.currentChapterId)
                readerView._pagesChanged()
        }
    }

    Connections {
        target: Manga
        function onChapterPagesChanged() { readerView._pagesChanged() }
        function onTrackUpdated(text) {
            if (readerView.visible && text.length > 0)
                toast.show("check_circle", "AniList updated", text)
        }
    }

    // ── The view in use ──────────────────────────────────────────────────────
    readonly property var view: readerView.family === "strip" ? stripLoader.item : stageLoader.item
    readonly property real zoom: readerView.view ? readerView.view.zoom : 1
    readonly property real minZoom: readerView.view ? readerView.view.minZoom : 1
    readonly property real maxZoom: readerView.view ? readerView.view.maxZoom : 1

    function zoomBy(dir, fx, fy) {
        if (readerView.view)
            readerView.view.zoomBy(dir, fx, fy)
    }

    function resetZoom() {
        if (readerView.view)
            readerView.view.resetZoom()
    }

    // ── Moving about ─────────────────────────────────────────────────────────
    function jumpTo(p) {
        if (readerView.count === 0)
            return
        let c = Math.max(0, Math.min(readerView.count - 1, p))
        if (readerView.family === "spread" && readerView.spreads.length > 0)
            c = readerView.spreads[RM.spreadIndex(readerView.spreads, c)][0]
        readerView.page = c
        if (readerView.family === "strip" && readerView.view)
            readerView.view.goTo(c)
    }

    // One page (or one spread) on, or back; past either end it is the next / previous chapter.
    function step(dir) {
        if (readerView.count === 0 || readerView.family === "strip")
            return
        if (readerView.family === "spread" && readerView.spreads.length > 0) {
            const i = RM.spreadIndex(readerView.spreads, readerView.page) + dir
            if (i < 0)
                readerView.prevChapter()
            else if (i >= readerView.spreads.length)
                readerView.nextChapter()
            else
                readerView.jumpTo(readerView.spreads[i][0])
            return
        }
        const p = readerView.page + dir
        if (p < 0)
            readerView.prevChapter()
        else if (p >= readerView.count)
            readerView.nextChapter()
        else
            readerView.jumpTo(p)
    }

    // The mode picked: kept (for long-strip series, or for the rest), shown, and the zoom starts over.
    function pickMode(id) {
        MangaPrefs.setModeFor(id, readerView.kind === true)
        readerView.resetZoom()
        const m = RM.modeInfo(id)
        toast.show(m.icon, m.label, RM.keysHint(id))
        if (m.family === "spread" && !readerView.isFullscreen)
            readerView.toggleFullscreen()
    }

    function cycleMode() {
        let at = 0
        for (let i = 0; i < RM.MODES.length; i++)
            if (RM.MODES[i].id === readerView.modeId)
                at = i
        readerView.pickMode(RM.MODES[(at + 1) % RM.MODES.length].id)
    }

    function cycleBackground() {
        let at = 0
        for (let i = 0; i < RM.BACKGROUNDS.length; i++)
            if (RM.BACKGROUNDS[i].id === MangaPrefs.background)
                at = i
        const next = RM.BACKGROUNDS[(at + 1) % RM.BACKGROUNDS.length]
        MangaPrefs.setBackground(next.id)
        toast.show("palette", "Background \u00b7 " + next.label, "")
    }

    // ── Saving a page as a picture ───────────────────────────────────────────
    function savePage(i) {
        const p = Manga.chapterPages[i]
        if (!p)
            return
        const n = RM.saveName(Manga.currentManga ? Manga.currentManga.title : "",
                              readerView.chapterLabel(readerView.nav.current), i)
        saver.save(p.url, n.dir, n.base, "p. " + (i + 1))
    }

    // The page on screen (both of a Tablet spread).
    function saveCurrent() {
        const list = readerView.shown
        for (let i = 0; i < list.length; i++)
            readerView.savePage(list[i])
    }

    PageSaver {
        id: saver
        onSaved: (path, label) => toast.show("download_minimalistic", "Saved " + label,
            path.indexOf(ReaderEnv.home) === 0 ? "~" + path.substring(ReaderEnv.home.length) : path)
        onFailed: label => toast.show("danger_triangle", "Couldn't save " + label, "Is the reader's server running?")
    }

    ChapterPreloader {
        id: preload
    }

    // ── Keys ─────────────────────────────────────────────────────────────────
    focus: true

    function _dirOf(key) {
        switch (key) {
        case Qt.Key_Left:  case Qt.Key_A: return "left"
        case Qt.Key_Right: case Qt.Key_D: return "right"
        case Qt.Key_Up:    case Qt.Key_W: return "up"
        case Qt.Key_Down:  case Qt.Key_S: return "down"
        }
        return ""
    }

    Keys.onPressed: event => {
        const key = event.key
        const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        const strip = readerView.family === "strip"
        const zoomed = Math.abs(readerView.zoom - 1) > 0.001
        event.accepted = true

        if ((event.modifiers & Qt.ControlModifier) && key === Qt.Key_S) {
            readerView.saveCurrent()
            return
        }
        if (!plain) {
            event.accepted = false
            return
        }
        if (readerView.count === 0 && key !== Qt.Key_Escape) {
            event.accepted = false
            return
        }

        const dir = readerView._dirOf(key)
        if (dir !== "") {
            const act = RM.keyAction(readerView.modeId, dir, zoomed)
            const v = readerView.view
            // a zoomed strip is moved sideways with the keys, a zoomed page the way you drag it
            const s = strip ? -1 : 1
            switch (act) {
            case "next":
                readerView.step(1)
                break
            case "prev":
                readerView.step(-1)
                break
            case "scrollDown":
                if (v && !event.isAutoRepeat && v.atEnd && readerView.nav.next)
                    readerView.nextChapter()
                else if (v)
                    v.scrollKey = 1
                break
            case "scrollUp":
                if (v)
                    v.scrollKey = -1
                break
            case "panLeft":  if (v) v.panBy(s * 90, 0); break
            case "panRight": if (v) v.panBy(-s * 90, 0); break
            case "panUp":    if (v) v.panBy(0, s * 90); break
            case "panDown":  if (v) v.panBy(0, -s * 90); break
            }
            return
        }

        switch (key) {
        case Qt.Key_Space:
        case Qt.Key_PageDown:
        case Qt.Key_Return:
        case Qt.Key_Enter: {
            const back = key === Qt.Key_Space && (event.modifiers & Qt.ShiftModifier)
            if (strip && readerView.view) {
                if (!back && !event.isAutoRepeat && readerView.view.atEnd && readerView.nav.next)
                    readerView.nextChapter()
                else
                    readerView.view.scrollPage(back ? -1 : 1)
            } else {
                readerView.step(back ? -1 : 1)
            }
            break
        }
        case Qt.Key_PageUp:
        case Qt.Key_Backspace:
            if (strip && readerView.view)
                readerView.view.scrollPage(-1)
            else
                readerView.step(-1)
            break
        case Qt.Key_Home:
            readerView.jumpTo(0)
            break
        case Qt.Key_End:
            readerView.jumpTo(readerView.count - 1)
            break
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            readerView.zoomBy(1)
            break
        case Qt.Key_Minus:
        case Qt.Key_Underscore:
            readerView.zoomBy(-1)
            break
        case Qt.Key_0:
            readerView.resetZoom()
            break
        case Qt.Key_BracketRight:
            readerView.nextChapter()
            break
        case Qt.Key_BracketLeft:
            readerView.prevChapter()
            break
        case Qt.Key_M:
            readerView.cycleMode()
            break
        case Qt.Key_B:
            readerView.cycleBackground()
            break
        case Qt.Key_F:
            readerView.toggleFullscreen()
            break
        case Qt.Key_H:
            readerView.headerPinned = !readerView.headerPinned
            readerView._nudgeHeader()
            if (readerView.headerPinned)
                toast.show("eye", "Bar pinned", "H lets it hide again")
            else
                toast.show("eye_closed", "Bar auto-hides", "Move the mouse to bring it back \u00b7 H pins it")
            break
        case Qt.Key_Escape:
            if (readerView.menuOpen)
                readerView.menuOpen = false
            else if (readerView.settingsOpen)
                readerView.settingsOpen = false
            else if (Math.abs(readerView.zoom - 1) > 0.001)
                readerView.resetZoom()
            else
                event.accepted = false
            break
        default:
            event.accepted = false
        }
    }

    Keys.onReleased: event => {
        if (event.isAutoRepeat)
            return
        const d = readerView._dirOf(event.key)
        if ((d === "up" || d === "down") && readerView.view && readerView.family === "strip")
            readerView.view.scrollKey = 0
    }

    onActiveFocusChanged: {
        if (!readerView.activeFocus && readerView.view && readerView.family === "strip")
            readerView.view.scrollKey = 0
    }

    // ── Background ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: readerView.bg
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    // ── The page area ────────────────────────────────────────────────────────
    function _tapped(x, y, count) {
        readerView.forceActiveFocus()
        if (readerView.menuOpen) {
            readerView.menuOpen = false
            return
        }
        if (readerView.settingsOpen) {
            readerView.settingsOpen = false
            return
        }
        const v = readerView.view
        const strip = readerView.family === "strip"
        const a = (!v || (!strip && readerView.zoom > 1.001)) ? "menu" : RM.tapAction(readerView.modeId, x, y, v.width, v.height)
        if (count >= 2 && a === "menu" && v) {
            // a double click zooms in on the point, or back out
            v.zoomTo(Math.abs(readerView.zoom - 1) > 0.001 ? 1 : (strip ? 1.6 : 2.5), x, y)
        } else if (a === "next") {
            readerView.step(1)
        } else if (a === "prev") {
            readerView.step(-1)
        } else {
            readerView._nudgeHeader()
        }
    }

    property real _menuX: 0
    property real _menuY: 0
    property int _menuPage: 0

    function _contextAt(x, y, pageIndex) {
        readerView.forceActiveFocus()
        readerView.settingsOpen = false
        readerView._menuX = x
        readerView._menuY = y
        readerView._menuPage = pageIndex
        readerView.menuOpen = true
    }

    // The page area's mouse cursor. It is an item (not a handler's cursorShape) on purpose: Qt
    // changes the cursor of the item the pointer is on straight away, while a handler's change
    // waits for the next pointer event, which is exactly what a resting pointer never sends.
    // It sits under the page and takes no clicks or wheel; keys and chips that ask for their own
    // cursor (the pointing hand) are above it and keep it.
    MouseArea {
        id: cursorLayer
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: false
        cursorShape: readerView.pointerIdle ? Qt.BlankCursor
            : (readerView.view && readerView.view.dragging === true ? Qt.ClosedHandCursor
            : (readerView.family !== "strip" && readerView.zoom > 1.001 ? Qt.OpenHandCursor : Qt.ArrowCursor))
    }

    Item {
        id: body
        anchors {
            fill: parent
        }

        Loader {
            id: stripLoader
            anchors.fill: parent
            active: readerView.ready && readerView.family === "strip"

            sourceComponent: StripView {
                host: readerView
                pages: Manga.chapterPages
                gap: readerView.mode.gap || 0
                onViewedPage: i => readerView.page = i
                onTapped: (x, y, count) => readerView._tapped(x, y, count)
                onContextRequested: (x, y, i) => readerView._contextAt(x, y, i)
            }

            onLoaded: Qt.callLater(() => {
                if (stripLoader.item)
                    stripLoader.item.goTo(readerView.page)
            })
        }

        Loader {
            id: stageLoader
            anchors.fill: parent
            active: readerView.ready && readerView.family !== "strip"

            sourceComponent: PageStage {
                host: readerView
                pages: Manga.chapterPages
                shown: readerView.shown
                rtl: readerView.rtl
                vertical: readerView.mode.dir === "v"
                ahead: readerView.family === "spread" ? 8 : 6
                onTapped: (x, y, count) => readerView._tapped(x, y, count)
                onContextRequested: (x, y, i) => readerView._contextAt(x, y, i)
                onWheelTurn: dir => readerView.step(dir)
            }
        }
    }

    // The first pages, loaded while the mode is still being worked out: their shape says
    // whether this is a long strip, and the view that opens finds them already in the cache.
    Repeater {
        model: readerView.kind === null ? Math.min(3, readerView.count) : 0

        delegate: Image {
            required property int index

            visible: false
            width: 1
            height: 1
            asynchronous: true
            cache: true
            source: Manga.chapterPages[index] ? Manga.chapterPages[index].url : ""
            onStatusChanged: {
                if (status === Image.Ready)
                    readerView.noteSize(index, implicitWidth, implicitHeight)
            }
        }
    }

    // A page that never loads must not leave the mode undecided for good.
    Timer {
        interval: 2500
        running: readerView.count > 0 && readerView.kind === null
        onTriggered: readerView._decide(false)
    }

    // ── Reader bar ───────────────────────────────────────────────────────────
    ReaderBar {
        id: readerHeader
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
        z: 10
        shown: readerView.headerVisible

        HoverHandler { id: headerHover; onHoveredChanged: if (!hovered) headerHideTimer.restart() }

        RowLayout {
            anchors { fill: parent; leftMargin: 7; rightMargin: 10 }
            spacing: 6

            ReaderKey {
                icon: "arrow_back"
                onClicked: {
                    Manga.clearChapterPages()
                    readerView.backRequested()
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 1

                Text {
                    width: parent.width
                    text: Manga.currentManga ? Manga.currentManga.title : ""
                    font.family: readerView.fontDisplay
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    color: Theme.inkSub
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: readerView.chapterLabel(readerView.nav.current)
                    font.family: readerView.fontDisplay
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    color: Theme.ink
                    elide: Text.ElideRight
                }
            }

            // Already read: stamped on the bar, and the key beside the settings undoes it
            ReaderBadge {
                visible: readerView.currentRead
                text: "READ"
                fill: Theme.accentMint
                rotation: -3
            }

            // Page counter, a sticker that hops when the page changes
            StickerText {
                visible: readerView.count > 0
                text: readerView.pageLabel
                pixelSize: 15
                fillColor: Theme.accentMint
            }

            ReaderKey {
                icon: readerView.currentRead ? "check_read" : "eye_closed"
                lit: readerView.currentRead
                onClicked: {
                    readerView.toggleCurrentRead()
                    readerView.forceActiveFocus()
                }
            }

            ReaderKey {
                icon: "tuning_2"
                lit: readerView.settingsOpen
                onClicked: {
                    readerView.menuOpen = false
                    readerView.settingsOpen = !readerView.settingsOpen
                    readerView.forceActiveFocus()
                }
            }

            ReaderKey {
                icon: readerView.isFullscreen ? "minimize" : "full_screen"
                lit: readerView.isFullscreen
                onClicked: {
                    readerView.toggleFullscreen()
                    readerView.forceActiveFocus()
                }
            }
        }
    }

    // ── Fetching pages overlay ───────────────────────────────────────────────
    LoadingState {
        anchors.fill: parent
        z: 8
        active: Manga.isFetchingPages || (readerView.count > 0 && !readerView.ready)
        color: readerView.bg
        textColor: readerView.fg
        spinnerSize: 40
        label: "loading pages"
        detail: Manga.currentManga ? Manga.currentManga.title : ""
        bodyFont: readerView.fontBody
    }

    // ── Pages error overlay ──────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: readerView.bg
        visible: Manga.pagesError.length > 0 && !Manga.isFetchingPages
        z: 7

        Column {
            anchors.centerIn: parent
            spacing: 10

            StyledText {
                text: "\u26a0"
                font.pixelSize: 32
                color: Colors.error
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.85
            }
            StyledText {
                text: Manga.pagesError
                color: readerView.fgDim
                font.pixelSize: 11
                font.family: readerView.fontBody
                wrapMode: Text.Wrap
                width: 260
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }
        }
    }

    // ── Reading progress (bottom): click or drag to jump ─────────────────────
    ReaderProgress {
        id: progress
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12 }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        z: 9
        visible: readerView.count > 0 && readerView.ready
        value: readerView.count > 0
            ? (readerView.shown.length > 0 ? readerView.shown[readerView.shown.length - 1] + 1 : readerView.page + 1) / readerView.count : 0

        // Right to left reads from the right: the bar fills that way too.
        readonly property bool mirrored: readerView.family !== "strip" && readerView.rtl
        transform: Scale {
            origin.x: progress.width / 2
            xScale: progress.mirrored ? -1 : 1
        }

        MouseArea {
            anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
            cursorShape: readerView.pointerIdle ? Qt.BlankCursor : Qt.PointingHandCursor
            function seek(mx) {
                let f = Math.max(0, Math.min(1, mx / width))
                if (progress.mirrored)
                    f = 1 - f
                readerView.jumpTo(Math.min(readerView.count - 1, Math.floor(f * readerView.count)))
            }
            onPressed: mouse => { readerView.forceActiveFocus(); seek(mouse.x) }
            onPositionChanged: mouse => { if (pressed) seek(mouse.x) }
        }
    }

    // ── Zoom: shown while the page is not at its usual size ──────────────────
    Item {
        id: zoomPill
        z: 9
        anchors { right: parent.right; bottom: progress.top; rightMargin: 18; bottomMargin: 8 }
        width: pillRow.implicitWidth + 28
        height: 44 + Theme.shadowOffset
        opacity: readerView.ready && Math.abs(readerView.zoom - 1) > 0.001 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Pill {
            anchors.fill: parent
            cornerRadius: 18
            ringWidth: Theme.borderWidth
            innerRing: Theme.cardRing
            fillColor: Theme.surface

            Row {
                id: pillRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Theme.shadowOffset / 2
                spacing: 6

                ReaderKey {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "magnifer_zoom_out"
                    enabled: readerView.zoom > readerView.minZoom + 0.001
                    onClicked: readerView.zoomBy(-1)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(readerView.zoom * 100) + "%"
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                ReaderKey {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "magnifer_zoom_in"
                    enabled: readerView.zoom < readerView.maxZoom - 0.001
                    onClicked: readerView.zoomBy(1)
                }

                ReaderKey {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "restart"
                    onClicked: readerView.resetZoom()
                }
            }
        }
    }

    // ── Settings card and page menu ──────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 11
        enabled: readerView.settingsOpen || readerView.menuOpen
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            readerView.settingsOpen = false
            readerView.menuOpen = false
            readerView.forceActiveFocus()
        }
        onWheel: wheel => wheel.accepted = true
    }

    ReaderSettings {
        id: settings
        z: 12
        host: readerView
        shown: readerView.settingsOpen
        x: readerView.width - width - 12
        y: (readerView.headerVisible ? 70 : 12)
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    Item {
        id: pageMenu
        z: 13
        width: 214
        height: menuCol.implicitHeight + 20 + Theme.shadowOffset
        x: Math.max(8, Math.min(readerView.width - width - 8, readerView._menuX))
        y: Math.max(8, Math.min(readerView.height - height - 8, readerView._menuY + body.y))
        opacity: readerView.menuOpen ? 1 : 0
        visible: opacity > 0.01
        scale: readerView.menuOpen ? 1 : 0.94
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

        Pill {
            anchors.fill: parent
            cornerRadius: 18
            ringWidth: Theme.borderWidth
            innerRing: Theme.cardRing
            fillColor: Theme.surface

            Column {
                id: menuCol
                x: 10
                y: 10
                width: parent.width - 20
                spacing: 2

                ReaderMenuRow {
                    width: menuCol.width
                    icon: "download_minimalistic"
                    text: "Save page " + (readerView._menuPage + 1)
                    onClicked: {
                        readerView.menuOpen = false
                        readerView.savePage(readerView._menuPage)
                    }
                }

                ReaderMenuRow {
                    width: menuCol.width
                    icon: "magnifer_zoom_in"
                    text: "Zoom in here"
                    enabled: readerView.zoom < readerView.maxZoom - 0.001
                    onClicked: {
                        readerView.menuOpen = false
                        if (readerView.view)
                            readerView.view.zoomBy(1, readerView._menuX, readerView._menuY)
                    }
                }

                ReaderMenuRow {
                    width: menuCol.width
                    icon: "tuning_2"
                    text: "Reading settings"
                    onClicked: {
                        readerView.menuOpen = false
                        readerView.settingsOpen = true
                    }
                }
            }
        }
    }

    // ── The mode (or the chapter, a save) for a moment ───────────────────────
    ModeToast {
        id: toast
        z: 20
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 64
    }
}
