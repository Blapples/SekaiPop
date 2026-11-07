import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// One page at a time (Paged, any direction), or two joined side by side (Tablet): fitted to
// the view, zoomed and dragged on its own, with the neighbouring pages already loading.
//
//   shown   the page numbers on screen, lowest first ([4] or [4, 5]); in a right-to-left
//           mode the higher one is drawn on the left, like an open manga
//   zoom    1 = the page fits; it zooms to `maxZoom`, about the pointer
//
// The interface the reader uses is the same as StripView's: zoom, zoomTo, zoomBy, resetZoom,
// panBy, goTo and the signals. Turning the page is the reader's (it owns the page number);
// this only draws what it is given, with a short slide when that changes.
Item {
    id: root

    property var host: null
    property var pages: []
    property var shown: []
    property bool rtl: false
    property bool vertical: false
    // How many pages after the one on screen are fetched ahead.
    property int ahead: 6

    property real zoom: 1
    readonly property real minZoom: 1
    readonly property real maxZoom: 6
    property real panX: 0
    property real panY: 0

    readonly property var order: root.rtl ? root.shown.slice().reverse() : root.shown
    readonly property var aspects: {
        if (!root.host)
            return []
        root.host.sizesRev
        return root.order.map(i => RM.aspectOf(root.host.sizeOf(i)))
    }
    // The page(s) at zoom 1: as big as fits, together as wide as one row of them.
    readonly property var fit: RM.fitSize(root.width, root.height, root.aspects)

    signal tapped(real x, real y, int count)
    signal contextRequested(real x, real y, int pageIndex)
    signal wheelTurn(int dir)

    clip: true

    // ── The interface shared with StripView ───────────────────────────────────

    function goTo(i) {}

    function zoomTo(z, fx, fy) {
        const r = RM.zoomAbout(root.width, root.height, root.fit.w, root.fit.h, root.zoom, root.panX, root.panY, z,
                               fx === undefined ? root.width / 2 : fx, fy === undefined ? root.height / 2 : fy,
                               root.minZoom, root.maxZoom)
        root.zoom = r.zoom
        root.panX = r.panX
        root.panY = r.panY
    }

    function zoomBy(dir, fx, fy) {
        root.zoomTo(RM.stepZoom(root.zoom, dir, root.minZoom, root.maxZoom), fx, fy)
    }

    function resetZoom() {
        root.zoom = 1
        root.panX = 0
        root.panY = 0
    }

    function panBy(dx, dy) {
        const p = RM.clampPan(root.width, root.height, root.fit.w, root.fit.h, root.zoom, root.panX + dx, root.panY + dy)
        root.panX = p.panX
        root.panY = p.panY
    }

    // The page under (x, y) of this view (the left or right half, in a spread).
    function pageAt(x, y) {
        if (root.order.length < 2)
            return root.order.length > 0 ? root.order[0] : 0
        const local = content.mapFromItem(root, x, y)
        let edge = 0
        for (let i = 0; i < root.order.length; i++) {
            edge += root.fit.widths[root.rtl ? root.order.length - 1 - i : i]
            if (local.x < edge)
                return root.order[i]
        }
        return root.order[root.order.length - 1]
    }

    // A zoomed page that is resized (the bar slides away, the panel widens) keeps covering the view.
    onFitChanged: root.panBy(0, 0)

    // ── Turning: a short slide in the direction of reading ────────────────────
    property int _lastFirst: -1
    property real slide: 0
    property real fade: 1

    onShownChanged: {
        const first = root.shown.length > 0 ? root.shown[0] : -1
        if (first === root._lastFirst)
            return
        const forward = first > root._lastFirst
        const known = root._lastFirst >= 0 && first >= 0
        root._lastFirst = first
        // a new page starts unzoomed and centred
        root.resetZoom()
        if (!known)
            return
        // forward comes in from where the next page is: the right (left when reading right
        // to left), or below; backward from the other side
        const sign = (forward ? 1 : -1) * (root.rtl && !root.vertical ? -1 : 1)
        root.slide = sign * 38
        root.fade = 0.25
        turn.restart()
    }

    ParallelAnimation {
        id: turn
        NumberAnimation { target: root; property: "slide"; to: 0; duration: 210; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "fade"; to: 1; duration: 210; easing.type: Easing.OutCubic }
    }

    // ── The page(s) ───────────────────────────────────────────────────────────
    Item {
        id: content

        width: root.fit.w
        height: root.fit.h
        x: (root.width - width) / 2 + root.panX + (root.vertical ? 0 : root.slide)
        y: (root.height - height) / 2 + root.panY + (root.vertical ? root.slide : 0)
        scale: root.zoom
        transformOrigin: Item.Center
        opacity: root.fade

        Row {
            id: row
            spacing: 0

            Repeater {
                model: root.order.length

                delegate: Item {
                    id: cell

                    required property int index

                    readonly property int pageIndex: root.order[cell.index]
                    readonly property bool known: {
                        if (!root.host)
                            return false
                        root.host.sizesRev
                        return root.host.sizeOf(cell.pageIndex) !== null
                    }

                    width: root.fit.widths[root.rtl ? root.order.length - 1 - cell.index : cell.index] || 0
                    height: content.height

                    Image {
                        id: img
                        anchors.fill: parent
                        source: root.pages[cell.pageIndex] ? (root.pages[cell.pageIndex].url || "") : ""
                        fillMode: Image.Stretch
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }

                        onStatusChanged: {
                            if (status === Image.Ready && root.host)
                                root.host.noteSize(cell.pageIndex, implicitWidth, implicitHeight)
                        }
                    }

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
                                text: "p. " + (cell.pageIndex + 1) + (img.status === Image.Error ? "  \u00b7  failed to load" : "")
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
            }
        }
    }

    // ── Pages next to this one, fetched ahead (and kept: they are what the next page
    //    turn shows, and what Tablet mode needs to know the shape of to pair the pages) ─
    Repeater {
        model: root.pages.length

        delegate: Image {
            id: probe

            required property int index

            readonly property int first: root.shown.length > 0 ? root.shown[0] : 0
            readonly property int last: root.shown.length > 0 ? root.shown[root.shown.length - 1] : 0
            readonly property bool wanted: probe.index >= probe.first - 2 && probe.index <= probe.last + root.ahead

            visible: false
            width: 1
            height: 1
            asynchronous: true
            cache: true
            source: probe.wanted && root.pages[probe.index] ? (root.pages[probe.index].url || "") : ""

            onStatusChanged: {
                if (status === Image.Ready && root.host)
                    root.host.noteSize(probe.index, implicitWidth, implicitHeight)
            }
        }
    }

    // ── Input ─────────────────────────────────────────────────────────────────

    // The reader draws the cursor (open / closed hand) from this.
    readonly property bool dragging: drag.active

    // A zoomed page is dragged.
    DragHandler {
        id: drag
        enabled: root.zoom > 1.001
        target: null
        acceptedButtons: Qt.LeftButton

        property real lastX: 0
        property real lastY: 0

        onActiveChanged: {
            drag.lastX = 0
            drag.lastY = 0
        }
        onTranslationChanged: {
            root.panBy(drag.translation.x - drag.lastX, drag.translation.y - drag.lastY)
            drag.lastX = drag.translation.x
            drag.lastY = drag.translation.y
        }
    }

    // Wheel: Ctrl zooms about the pointer; on a zoomed page it moves the page; otherwise it
    // turns pages (one per notch, and a touchpad's small steps add up to one).
    WheelHandler {
        id: wheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property real acc: 0
        property double lastTurn: 0

        onWheel: event => {
            const dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
            if (event.modifiers & Qt.ControlModifier) {
                if (dy !== 0)
                    root.zoomBy(dy > 0 ? 1 : -1, event.x, event.y)
                return
            }
            if (root.zoom > 1.001) {
                const sideways = (event.modifiers & Qt.ShiftModifier) !== 0
                const d = Theme.wheelPx(event, sideways)
                if (sideways)
                    root.panBy(d, 0)
                else
                    root.panBy(event.angleDelta.x !== 0 ? Theme.wheelPx(event, true) : 0, d)
                return
            }
            wheel.acc += dy
            const now = Date.now()
            if (Math.abs(wheel.acc) >= 100 && now - wheel.lastTurn > 140) {
                root.wheelTurn(wheel.acc < 0 ? 1 : -1)
                wheel.lastTurn = now
                wheel.acc = 0
            } else if (Math.abs(wheel.acc) >= 100) {
                wheel.acc = 0
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
