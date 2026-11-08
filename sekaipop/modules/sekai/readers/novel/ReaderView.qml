// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../NovelMath.js" as NM

// A chapter being read. What it does, the same way the manga reader does it:
//
//   - the top and bottom bars are out of the way while reading: they slide in when the mouse
//     moves and out again once it has been still for a moment (H pins them), and the mouse
//     cursor goes with them (a pointer that has rested on the page is hidden);
//   - two reading modes, Scroll (one long page) and Paged (a screen at a time; the outer thirds
//     of the page, A / D and the wheel turn it, and a turn past the end goes on to the next
//     chapter). M switches, and the mode is shown for a moment when a chapter opens;
//   - W A S D / arrows follow the mode (NovelMath.keyAction); Space pages, + / - / 0 set the
//     type size, B the background (shell, black, sepia, white), F the full-screen key, H the bar;
//   - the next chapter is fetched half-way through this one (Novel.prefetchChapter), so Next
//     opens it at once;
//   - the settings are kept between sessions (NovelPrefs).
Item {
    id: readerView

    // The chrome speaks the shell's font; the chapter itself is set in a book face.
    readonly property string fontDisplay: Theme.fontFamily
    readonly property string readFont: "Noto Serif"
    readonly property string fontBody:    Theme.fontFamily

    signal backRequested()
    signal toggleFullscreen()

    property bool isFullscreen: false

    readonly property real fontSize:   NovelPrefs.fontSize
    readonly property real lineHeight: NovelPrefs.lineHeight
    readonly property string modeId:   NovelPrefs.mode
    readonly property bool paged:      readerView.modeId === "paged"

    // ── The bars and the cursor ──────────────────────────────────────────────
    // The bars slide in when the mouse moves and slide out again once it has been still for a
    // moment (they stay while the pointer is on one of them). `headerPinned` (the H key) keeps
    // them on screen instead.
    property bool headerVisible: true
    property bool headerPinned: false

    // The mouse cursor goes with the bars' moment: a pointer that has rested on the page (not
    // on a bar) is hidden, and any movement brings it back.
    property bool pointerIdle: false

    function _nudgeHeader() {
        pointerIdle = false
        headerVisible = true
        headerHideTimer.restart()
    }

    Timer {
        id: headerHideTimer
        interval: 1800
        onTriggered: {
            const onBar = headerHover.hovered || footerHover.hovered
            readerView.pointerIdle = !onBar
            if (readerView.headerPinned || onBar)
                return
            readerView.headerVisible = false
        }
    }

    // Any pointer movement over the reader brings the bars back. A HoverHandler only watches:
    // it does not take the pointer away from the page or the buttons.
    //
    // Only a pointer that really moved counts. While a page scrolls under a resting pointer
    // the scene sends hover updates with the same window position; taking each of those for
    // movement would keep the bars up for as long as the pointer was over the reader.
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

    // ── Colours of the page ──────────────────────────────────────────────────
    readonly property var pal: NM.palette(NovelPrefs.background)
    readonly property color bgColor:     readerView.pal ? readerView.pal.bg : Colors.page
    readonly property color titleColor:  readerView.pal ? readerView.pal.title : Qt.rgba(0.96, 0.93, 0.87, 0.90)
    readonly property color inkColor:    readerView.pal ? readerView.pal.ink : Qt.rgba(0.91, 0.87, 0.80, 0.87)
    readonly property color accentColor: readerView.pal ? readerView.pal.accent : Colors.primary

    // ── Reading position ─────────────────────────────────────────────────────
    readonly property bool _hasPrev: Novel.hasPrevChapter
    readonly property bool _hasNext: Novel.hasNextChapter

    readonly property real progress: textScroll.contentHeight > textScroll.height
        ? Math.min(1, (textScroll.contentY + textScroll.height) / textScroll.contentHeight)
        : 1

    function _maxY() { return Math.max(0, textScroll.contentHeight - textScroll.height) }
    function _clampY(y) { return Math.max(0, Math.min(readerView._maxY(), y)) }
    function _pageStep() { return NM.pageStep(textScroll.height, readerView.fontSize, readerView.lineHeight) }

    readonly property var pageInfo: NM.pageInfo(textScroll.contentY, readerView._maxY(), readerView._pageStep())

    // Called by the parent to reset state when re-entering this view
    function reset() {
        pointerIdle = false
        headerVisible = true
        headerHideTimer.restart()
        scrollKey = 0
        pageAnim.stop()
        textScroll.contentY = 0
        _announced = false
        toast.hide()
    }

    // ── Moving about ─────────────────────────────────────────────────────────
    function _animateTo(y) {
        pageAnim.stop()
        pageAnim.from = textScroll.contentY
        pageAnim.to = readerView._clampY(y)
        pageAnim.start()
    }

    NumberAnimation {
        id: pageAnim
        target: textScroll
        property: "contentY"
        duration: 240
        easing.type: Easing.OutCubic
    }

    // A page turn: +1 forward, -1 back. Past either end of the chapter it goes on to the
    // neighbouring chapter.
    function turn(dir) {
        const y = textScroll.contentY
        if (dir > 0) {
            if (y >= readerView._maxY() - 2) { readerView.gotoChapter(1); return }
            readerView._animateTo(y + readerView._pageStep())
        } else {
            if (y <= 2) { readerView.gotoChapter(-1); return }
            readerView._animateTo(y - readerView._pageStep())
        }
    }

    // A page's worth of scrolling without crossing into another chapter (Scroll mode's Space).
    function scrollPage(dir) {
        readerView._animateTo(textScroll.contentY + dir * readerView._pageStep())
    }

    function gotoChapter(dir) {
        if (Novel.isFetchingChapter)
            return
        if (dir > 0 && readerView._hasNext) {
            Novel.fetchNextChapter()
        } else if (dir < 0 && readerView._hasPrev) {
            Novel.fetchPrevChapter()
        } else {
            toast.show("danger_triangle", dir > 0 ? "Last chapter" : "First chapter", "")
        }
    }

    // Held W / S (or the up / down arrows) scroll smoothly in Scroll mode.
    property int scrollKey: 0
    Timer {
        id: scrollTimer
        interval: 16
        repeat: true
        running: readerView.scrollKey !== 0
        onTriggered: {
            pageAnim.stop()
            textScroll.contentY = readerView._clampY(textScroll.contentY + readerView.scrollKey * 16)
        }
    }

    // Keep the place in the chapter (by proportion) while its height changes: type size, mode.
    function _keepPlace(change) {
        const h = textScroll.contentHeight
        const r = h > 0 ? textScroll.contentY / h : 0
        change()
        Qt.callLater(function() {
            textScroll.contentY = readerView._clampY(r * textScroll.contentHeight)
        })
    }

    function setFont(v) {
        if (NM.clampFont(v) === readerView.fontSize)
            return
        readerView._keepPlace(function() { NovelPrefs.setFontSize(v) })
        toast.show("text_field", "Text size " + NovelPrefs.fontSize, "+ / - change it \u00b7 0 resets")
    }

    function cycleMode() {
        const next = NM.nextMode(readerView.modeId)
        readerView._keepPlace(function() { NovelPrefs.setMode(next) })
        readerView.showMode()
    }

    function cycleBackground() {
        const next = NM.nextBackground(NovelPrefs.background)
        NovelPrefs.setBackground(next)
        let label = next
        for (let i = 0; i < NM.BACKGROUNDS.length; i++)
            if (NM.BACKGROUNDS[i].id === next) label = NM.BACKGROUNDS[i].label
        toast.show("palette", "Background \u00b7 " + label, "B changes it")
    }

    function showMode() {
        const info = NM.modeInfo(readerView.modeId)
        toast.show(info.icon, info.label + " mode", NM.keysHint(readerView.modeId))
    }

    // ── The next chapter, ahead ──────────────────────────────────────────────
    // Half-way through this chapter (or at once when it fits one screen) the next one is asked
    // for, so going on to it needs no wait.
    function _maybePreload() {
        if (!readerView.visible || !Novel.currentChapter || Novel.isFetchingChapter)
            return
        if (textScroll.contentHeight < 200)
            return
        const fits = textScroll.contentHeight <= textScroll.height + 4
        if (NM.shouldPreload(readerView.progress, fits))
            Novel.prefetchChapter(Novel.nextChapterId)
    }

    // A chapter counts as read once the reader is nearly at its end (or it fits one screen and
    // has been open a moment): it is marked, and with an AniList login the number of chapters
    // read goes up there (Novel.markRead -> trackSoon).
    function _maybeMarkRead() {
        if (!readerView.visible || !Novel.currentChapter || Novel.isFetchingChapter)
            return
        if (Novel.currentChapterId === "" || Novel.isChapterRead(Novel.currentChapterId))
            return
        if (textScroll.contentHeight < 200)
            return
        const fits = textScroll.contentHeight <= textScroll.height + 4
        if (NM.readDone(readerView.progress, fits))
            Novel.markRead(Novel.currentChapterId)
    }

    Timer {
        id: preloadTimer
        interval: 400
        onTriggered: { readerView._maybePreload(); readerView._maybeMarkRead() }
    }

    onProgressChanged: preloadTimer.restart()

    // AniList took a new number: say so for a moment
    Connections {
        target: Novel
        function onTrackUpdated(text) {
            if (readerView.visible && text.length > 0)
                toast.show("check_read", "AniList updated", text)
        }
    }

    // ── A chapter arrives ────────────────────────────────────────────────────
    property bool _announced: false

    Connections {
        target: Novel
        function onCurrentChapterChanged() {
            if (!Novel.currentChapter)
                return
            pageAnim.stop()
            textScroll.contentY = 0
            readerView.scrollKey = 0
            preloadTimer.restart()
            if (!readerView.visible)
                return
            if (!readerView._announced) {
                readerView._announced = true
                readerView.showMode()
            } else {
                const n = Novel.currentSortedChapters.length
                toast.show("book_2", Novel.currentChapter.title,
                    Novel.currentChapterIndex >= 0 ? "Chapter " + (Novel.currentChapterIndex + 1) + " of " + n : "")
            }
        }
    }

    onVisibleChanged: {
        if (readerView.visible) {
            // opened with the pointer resting: the bars still go after their moment
            readerView.headerVisible = true
            headerHideTimer.restart()
            readerView.forceActiveFocus()
            if (Novel.currentChapter && !readerView._announced) {
                readerView._announced = true
                readerView.showMode()
            }
        } else {
            readerView.scrollKey = 0
        }
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
        event.accepted = true

        if (!plain) {
            event.accepted = false
            return
        }

        const dir = readerView._dirOf(key)
        if (dir !== "") {
            const act = NM.keyAction(readerView.modeId, dir)
            switch (act) {
            case "scroll_up":   readerView.scrollKey = -1; break
            case "scroll_down": readerView.scrollKey = 1;  break
            case "prev":
                if (!event.isAutoRepeat) readerView.turn(-1)
                break
            case "next":
                if (!event.isAutoRepeat) readerView.turn(1)
                break
            case "prev_chapter":
                if (!event.isAutoRepeat) readerView.gotoChapter(-1)
                break
            case "next_chapter":
                if (!event.isAutoRepeat) readerView.gotoChapter(1)
                break
            }
            return
        }

        switch (key) {
        case Qt.Key_Space:
            if (event.isAutoRepeat) break
            if (readerView.paged) readerView.turn((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            else readerView.scrollPage((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            break
        case Qt.Key_PageDown:
            if (readerView.paged) readerView.turn(1)
            else readerView.scrollPage(1)
            break
        case Qt.Key_PageUp:
            if (readerView.paged) readerView.turn(-1)
            else readerView.scrollPage(-1)
            break
        case Qt.Key_Home:
            readerView._animateTo(0)
            break
        case Qt.Key_End:
            readerView._animateTo(readerView._maxY())
            break
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            readerView.setFont(readerView.fontSize + 1)
            break
        case Qt.Key_Minus:
            readerView.setFont(readerView.fontSize - 1)
            break
        case Qt.Key_0:
            readerView.setFont(NM.DEFAULT_PREFS.fontSize)
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
                toast.show("eye", "Bars pinned", "H lets them hide again")
            else
                toast.show("eye_closed", "Bars auto-hide", "Move the mouse to bring them back \u00b7 H pins them")
            break
        default:
            event.accepted = false
        }
    }

    Keys.onReleased: event => {
        if (event.isAutoRepeat)
            return
        const d = readerView._dirOf(event.key)
        if (d === "up" || d === "down")
            readerView.scrollKey = 0
    }

    onActiveFocusChanged: {
        if (!readerView.activeFocus)
            readerView.scrollKey = 0
    }

    // ── Background ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: readerView.bgColor
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    // The page area's mouse cursor. It is an item (not a handler's cursorShape) on purpose: Qt
    // changes the cursor of the item the pointer is on straight away, while a handler's change
    // waits for the next pointer event, which is exactly what a resting pointer never sends.
    // It sits under the page and takes no clicks or wheel; the keys of the bars ask for their
    // own cursor (the pointing hand) and keep it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: false
        cursorShape: readerView.pointerIdle ? Qt.BlankCursor : Qt.ArrowCursor
    }

    // In Paged mode the wheel turns pages (one turn per flick of the wheel).
    Timer { id: wheelCool; interval: 260 }
    WheelHandler {
        enabled: readerView.paged
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (wheelCool.running || event.angleDelta.y === 0)
                return
            wheelCool.start()
            readerView.turn(event.angleDelta.y < 0 ? 1 : -1)
        }
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
                onClicked: { Novel.clearChapter(); readerView.backRequested() }
            }

            Column {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 1

                Text {
                    width: parent.width
                    text: Novel.currentNovel ? Novel.currentNovel.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: 10
                    font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                    color: Theme.inkSub; elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: Novel.currentChapter ? Novel.currentChapter.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: 13
                    font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                    color: Theme.ink; elide: Text.ElideRight
                }
            }

            ReaderBadge {
                // only where the bar has the room (the full window)
                visible: readerView.width > 760 && Novel.currentChapter !== null && Novel.currentChapter.wordCount > 0
                rotation: 0
                fill: Theme.accentCyan
                text: Novel.currentChapter !== null
                    ? ((Math.round(Novel.currentChapter.wordCount / 100) / 10) + "k words").toUpperCase() : ""
            }

            // Scroll <-> Paged
            ReaderKey {
                icon: NM.modeInfo(readerView.modeId).icon
                lit: readerView.paged
                onClicked: readerView.cycleMode()
            }

            // Shell / black / sepia / white
            ReaderKey {
                icon: "palette"
                lit: NovelPrefs.background !== "theme"
                onClicked: readerView.cycleBackground()
            }

            ReaderKey {
                label: "A−"
                onClicked: readerView.setFont(readerView.fontSize - 1)
            }

            ReaderKey {
                label: "A+"
                onClicked: readerView.setFont(readerView.fontSize + 1)
            }

            ReaderKey {
                icon: readerView.isFullscreen ? "fullscreen_exit" : "fullscreen"
                lit: readerView.isFullscreen
                onClicked: readerView.toggleFullscreen()
            }
        }
    }

    // Loading: a ghost page in the reader's own measure and type size
    Rectangle {
        anchors.fill: parent; color: readerView.bgColor; z: 8
        opacity: Novel.isFetchingChapter ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        SkeletonText {
            anchors.fill: parent
            active: Novel.isFetchingChapter
            fontSize: readerView.fontSize
            lineHeight: readerView.lineHeight
            topInset: 56
        }
    }

    LoadingBar {
        anchors { top: readerHeader.bottom; left: parent.left; right: parent.right }
        z: 10
        active: Novel.isFetchingChapter
    }

    Rectangle {
        anchors.fill: parent; color: readerView.bgColor; z: 7
        visible: Novel.chapterError.length > 0 && !Novel.isFetchingChapter
        Column {
            anchors.centerIn: parent; spacing: 10
            Text {
                text: "⚠"; font.pixelSize: 32; color: Colors.error; opacity: 0.85
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: Novel.chapterError; color: readerView.inkColor; opacity: 0.6
                font.pixelSize: 11; font.family: readerView.fontBody
                wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
            }
        }
    }

    // ── The chapter ──────────────────────────────────────────────────────────
    // The page fills the reader and the bars lie over it, so the text does not move when they
    // come and go; the padding keeps the first and last lines clear of them.
    Flickable {
        id: textScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: textColumn.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        // Paged: the page is turned, not dragged
        interactive: !readerView.paged

        MouseArea {
            anchors.fill: parent; propagateComposedEvents: true
            onClicked: mouse => {
                readerView.forceActiveFocus()
                const a = NM.tapAction(readerView.modeId, mouse.x, mouse.y - textScroll.contentY, textScroll.width, textScroll.height)
                if (a === "next") readerView.turn(1)
                else if (a === "prev") readerView.turn(-1)
                else readerView._nudgeHeader()
                mouse.accepted = false
            }
        }

        Column {
            id: textColumn
            // About 42 em: a line of 65 to 75 characters at any type size
            width: Math.min(parent.width - 48, Math.round(readerView.fontSize * 42))
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 76; bottomPadding: 96; spacing: 0

            StyledText {
                width: parent.width
                text: Novel.currentChapter ? Novel.currentChapter.title : ""
                font.family: readerView.readFont
                font.pixelSize: readerView.fontSize + 7
                font.bold: true
                color: readerView.titleColor
                wrapMode: Text.Wrap; lineHeight: 1.25; bottomPadding: 8
            }

            Item {
                width: parent.width; height: 24
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 5
                    Rectangle { width: 8;  height: 2; radius: 1; color: readerView.accentColor; opacity: 0.3 }
                    Rectangle { width: 32; height: 2; radius: 1; color: readerView.accentColor; opacity: 0.7 }
                    Rectangle { width: 8;  height: 2; radius: 1; color: readerView.accentColor; opacity: 0.3 }
                }
            }

            Item { width: 1; height: 20 }

            Repeater {
                model: Novel.currentChapter ? Novel.currentChapter.paragraphs : []
                StyledText {
                    width: textColumn.width
                    text: modelData
                    font.family: readerView.readFont
                    font.pixelSize: readerView.fontSize
                    color: readerView.inkColor
                    wrapMode: Text.Wrap; lineHeight: readerView.lineHeight
                    bottomPadding: Math.round(readerView.fontSize * readerView.lineHeight * 0.75)
                    textFormat: Text.PlainText
                }
            }
        }

        ScrollBar.vertical: StyledScrollBar {
            visible: !readerView.paged
            thickness: 4
            handleRadius: 2
            handleOpacity: 0.6
        }
    }

    // ── Chapter navigation ───────────────────────────────────────────────────
    ReaderBar {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 }
        z: 10
        atBottom: true
        shown: readerView.headerVisible

        HoverHandler { id: footerHover; onHoveredChanged: if (!hovered) headerHideTimer.restart() }

        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 12

            ReaderChip {
                icon: "chevron_left"
                text: "Prev"
                enabled: readerView._hasPrev
                onClicked: Novel.fetchPrevChapter()
            }

            // How far down the chapter
            ReaderProgress {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                value: readerView.progress
            }

            // Paged: which page of the chapter
            Text {
                visible: readerView.paged
                text: readerView.pageInfo.index + " / " + readerView.pageInfo.total
                color: Theme.inkSub
                font.family: readerView.fontDisplay; font.pixelSize: 11
                font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
            }

            ReaderChip {
                icon: "chevron_right"
                text: "Next"
                lit: readerView._hasNext
                enabled: readerView._hasNext
                onClicked: Novel.fetchNextChapter()
            }
        }
    }

    // ── The mode (or the chapter, the type size) for a moment ────────────────
    ModeToast {
        id: toast
        z: 20
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 76
    }
}
