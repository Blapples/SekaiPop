import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// Long strip, and long strip with gaps: the pages one under the other. The reader (`host`)
// holds what is shared (the pages, their sizes, the colours, the neighbouring chapters);
// this is the scrolling and the zoom.
//
//   - W / S / arrows scroll while held (a steady glide, not a jump), Space / Page keys a screen;
//   - the wheel glides; Ctrl + wheel zooms around the pointer; a zoomed strip is dragged;
//   - a page of the strip is never wider than `maxContent` (a 1920 px screen would stretch a
//     webtoon into a poster); the colour shows on both sides;
//   - the top has "previous chapter", the bottom "next chapter".
//
// The interface the reader uses is the same as PageStage's: zoom, zoomTo, zoomBy, resetZoom,
// panBy, goTo and the signals.
Item {
    id: root

    property var host: null
    property var pages: []
    property int gap: 0
    property real maxContent: 900

    // 1 = the strip at its usual width; the zoom scales that width.
    property real zoom: 1
    readonly property real minZoom: 0.4
    readonly property real maxZoom: 3
    readonly property real baseWidth: Math.min(root.width, root.maxContent)
    readonly property real contentW: root.baseWidth * root.zoom

    // -1 / 0 / 1: a scroll key is held down.
    property int scrollKey: 0
    readonly property bool atEnd: list.contentHeight > 0 && list.atYEnd
    readonly property bool atStart: list.atYBeginning
    property int viewed: 0
    // The view only reports the page in the middle once it has been put where it starts.
    property bool tracking: false

    // The reader's glide speed while a key is held, px per frame at 60 Hz.
    readonly property real keySpeed: 16

    signal viewedPage(int index)
    signal tapped(real x, real y, int count)
    signal contextRequested(real x, real y, int pageIndex)

    clip: true

    // ── The interface shared with PageStage ───────────────────────────────────

    function goTo(i) {
        glide.stop()
        list.cancelFlick()
        const at = Math.max(0, Math.min(root.pages.length - 1, i))
        list.positionViewAtIndex(at, ListView.Beginning)
        root.viewed = at
        root.tracking = true
    }

    function _maxY() {
        return Math.max(list.originY, list.originY + list.contentHeight - list.height)
    }

    function _maxX() {
        return Math.max(0, list.contentWidth - list.width)
    }

    function _x0(w) {
        return Math.max(0, (list.width - w) / 2)
    }

    // Zoom to `z`, keeping the part of the strip under (fx, fy) where it is.
    function zoomTo(z, fx, fy) {
        const nz = RM.clamp(z, root.minZoom, root.maxZoom)
        if (Math.abs(nz - root.zoom) < 0.0001)
            return
        const vx = fx === undefined ? list.width / 2 : fx
        const vy = fy === undefined ? list.height / 2 : fy
        glide.stop()
        list.cancelFlick()

        // The page under the focus, and where in it (a share of its height / width), so the
        // pages above it, the gaps and the header (which do not scale) cannot shift it.
        const cx = list.contentX + list.width / 2
        const idx = list.indexAt(cx, list.contentY + vy)
        const item = idx >= 0 ? list.itemAtIndex(idx) : null
        const fracY = item ? (list.contentY + vy - item.y) / item.height : 0
        const k = nz / root.zoom
        const inX = (list.contentX + vx - root._x0(root.contentW)) * k   // px inside the page, at the new zoom
        const oldY = list.contentY

        root.zoom = nz
        list.forceLayout()

        const again = idx >= 0 ? list.itemAtIndex(idx) : null
        if (again)
            list.contentY = Math.max(list.originY, Math.min(root._maxY(), again.y + fracY * again.height - vy))
        else
            list.contentY = Math.max(list.originY, Math.min(root._maxY(), (oldY + vy) * k - vy))
        list.contentX = Math.max(0, Math.min(root._maxX(), root._x0(root.contentW) + inX - vx))
        root._track()
    }

    function zoomBy(dir, fx, fy) {
        root.zoomTo(RM.stepZoom(root.zoom, dir, root.minZoom, root.maxZoom), fx, fy)
    }

    function resetZoom() {
        root.zoomTo(1)
    }

    // Move the view by (dx, dy), as the keys do on a zoomed strip.
    function panBy(dx, dy) {
        glide.stop()
        list.cancelFlick()
        list.contentX = Math.max(0, Math.min(root._maxX(), list.contentX + dx))
        list.contentY = Math.max(list.originY, Math.min(root._maxY(), list.contentY + dy))
    }

    // A screen at a time (Space / Page keys), gliding.
    function scrollPage(dir) {
        const from = list.contentY
        const base = glide.running ? glide.to : from
        glide.stop()
        list.cancelFlick()
        glide.from = from
        glide.to = Math.max(list.originY, Math.min(root._maxY(), base + dir * list.height * 0.88))
        glide.start()
    }

    // The page in the middle of the view, handed to the reader as "the page being looked at".
    function _track() {
        if (!root.tracking)
            return
        const i = list.indexAt(list.contentX + list.width / 2, list.contentY + list.height / 2)
        if (i >= 0 && i !== root.viewed) {
            root.viewed = i
            root.viewedPage(i)
        }
    }

    function pageAt(x, y) {
        const i = list.indexAt(list.contentX + list.width / 2, list.contentY + y - list.y)
        return i >= 0 ? i : root.viewed
    }

    onScrollKeyChanged: if (root.scrollKey !== 0) { glide.stop(); list.cancelFlick() }

    // ── The strip ─────────────────────────────────────────────────────────────

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: root.pages
        spacing: root.gap
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        // Pages a screen or two away are already built, so scrolling meets them loaded.
        cacheBuffer: Math.max(1000, list.height * 2)
        contentWidth: root.contentW
        reuseItems: false

        onContentYChanged: root._track()
        onHeightChanged: root._track()

        header: Item {
            width: list.width
            height: root.host && root.host.nav.prev ? 78 : 12

            ReaderChip {
                visible: root.host !== null && root.host.nav.prev !== null
                anchors.centerIn: parent
                icon: "arrow_back"
                text: "Previous chapter"
                onClicked: root.host.openChapter(root.host.nav.prev, "last")
            }
        }

        footer: Item {
            width: list.width
            height: 190

            Column {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.host && root.host.nav.next ? "End of the chapter" : "That was the last chapter"
                    color: root.host ? root.host.fgDim : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 1.2
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                ReaderChip {
                    visible: root.host !== null && root.host.nav.next !== null
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: "arrow_forward"
                    lit: true
                    text: root.host && root.host.nav.next ? "Next: " + root.host.chapterLabel(root.host.nav.next) : ""
                    onClicked: root.host.openChapter(root.host.nav.next, "first")
                }

                Text {
                    visible: root.host !== null && root.host.nav.next !== null
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "or press S / \u2193 once more"
                    color: root.host ? root.host.fgDim : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    opacity: 0.8
                }
            }
        }

        delegate: Item {
            id: cell

            required property int index
            required property var modelData

            // The page's own shape once it is known (by any earlier visit), else a guess.
            readonly property real ratio: {
                if (!root.host)
                    return 1.42
                root.host.sizesRev
                const s = root.host.sizeOf(cell.index)
                return s ? s.h / s.w : 1.42
            }

            x: root._x0(width)
            width: root.contentW
            height: width * cell.ratio

            Image {
                id: img
                anchors.fill: parent
                source: cell.modelData.url || ""
                fillMode: Image.Stretch
                asynchronous: true
                cache: true
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260 } }

                onStatusChanged: {
                    if (status === Image.Ready && root.host)
                        root.host.noteSize(cell.index, implicitWidth, implicitHeight)
                }
            }

            // Beside the page, not inside it: the page is at opacity 0 until it is ready.
            Rectangle {
                anchors.fill: parent
                z: -1
                color: root.host ? root.host.placeholder : "#222"
                visible: img.status !== Image.Ready

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Spinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: img.status !== Image.Error
                        width: 22
                        border.width: 2
                        border.color: root.host ? root.host.fgFaint : "#333"
                        arcColor: root.host ? root.host.fgDim : "#888"
                        duration: 1200
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: img.status === Image.Error
                        text: "\u2298"
                        font.pixelSize: 22
                        color: root.host ? root.host.fgDim : "#888"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "p. " + (cell.index + 1) + (img.status === Image.Error ? "  \u00b7  failed to load" : "")
                        color: root.host ? root.host.fgDim : "#888"
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                        font.letterSpacing: 1.5
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: img.status === Image.Loading && img.progress > 0
                        width: 96
                        height: 2
                        radius: 1
                        color: root.host ? root.host.fgFaint : "#333"

                        Rectangle {
                            width: parent.width * img.progress
                            height: parent.height
                            radius: 1
                            color: Colors.primary
                        }
                    }
                }
            }
        }

        ScrollBar.vertical: StyledScrollBar {
            thickness: 2
            handleOpacity: 0.35
            handleRadius: 1
        }
    }

    // A held W / S / arrow: a steady glide while it is down.
    Timer {
        interval: 16
        repeat: true
        running: root.scrollKey !== 0
        onTriggered: {
            list.cancelFlick()
            list.contentY = Math.max(list.originY, Math.min(root._maxY(), list.contentY + root.scrollKey * root.keySpeed))
        }
    }

    NumberAnimation {
        id: glide
        target: list
        property: "contentY"
        duration: 240
        easing.type: Easing.OutCubic
    }

    // Grabbing or flicking the strip takes over from a glide.
    Connections {
        target: list
        function onMovementStarted() { glide.stop() }
    }

    // ── Wheel: scroll with a glide; Ctrl + wheel zooms ────────────────────────
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.modifiers & Qt.ControlModifier) {
                const dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                if (dy !== 0)
                    root.zoomBy(dy > 0 ? 1 : -1, event.x, event.y)
                return
            }
            const px = event.pixelDelta.y !== 0
            const d = Theme.wheelPx(event, false)
            if (d === 0)
                return
            const cur = list.contentY
            list.cancelFlick()
            if (!px) {
                // Notches that arrive mid-glide extend the target, so fast spinning stays fluid.
                const base = glide.running ? glide.to : cur
                glide.stop()
                glide.from = cur
                glide.to = Math.max(list.originY, Math.min(root._maxY(), base - d))
                glide.start()
            } else {
                glide.stop()
                list.contentY = Math.max(list.originY, Math.min(root._maxY(), cur - d))
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: (eventPoint, button) => root.tapped(eventPoint.position.x, eventPoint.position.y, tapCount)
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint, button) =>
            root.contextRequested(eventPoint.position.x, eventPoint.position.y, root.pageAt(eventPoint.position.x, eventPoint.position.y))
    }
}
