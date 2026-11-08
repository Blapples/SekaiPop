import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LockCanvasModel.js" as LM
import "../../common/functions/LockEditMath.js" as EM

// The password block, as the editor shows it: a stand-in with the real block's size (the white
// "Password" pill and the mint "Unlock" pill, LockCore.qml), not the real thing, because the
// real one is wired to the lock's password and the editor never touches that.
//
// It is the one thing on the lockscreen that can not be removed or resized, and it can only
// move inside a range (LockCanvasModel.js: the lower half of the screen), so a layout can never
// hide the way to unlock. Dragging it shows that range (LockEditStage.qml draws it). It snaps
// to the middle of the screen and to the widgets, like the others; hold Shift to move freely.
Item {
    id: core

    required property var stage

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    readonly property bool selected: LockEditService.selected === "core"
    readonly property real px1: 1 / core.stage.k

    // The real block's measures (LockCore.qml): a 560 wide password pill, a gap, a 330 wide
    // unlock pill, all 122 tall at 1080 p.
    readonly property real pillH: core.stage.px(122)
    readonly property real pwW: core.stage.px(560)
    readonly property real unW: core.stage.px(330)
    readonly property real gap: core.stage.px(26)

    readonly property real cx: core.x + core.width / 2
    readonly property real cy: core.y + core.height / 2
    readonly property real drawnW: core.width
    readonly property real drawnH: core.height

    // True while it is being dragged (the stage shows the range it can move in).
    property bool dragging: false

    width: core.pwW + core.gap + core.unW
    height: core.pillH
    x: EM.placeAxis(LockEditService.board.core.x, core.width, 1, core.stage.sw)
    y: EM.placeAxis(LockEditService.board.core.y, core.height, 1, core.stage.sh)
    z: 50

    // ===== the two pills =====
    Rectangle {
        id: pw
        width: core.pwW
        height: core.pillH
        radius: height / 2
        color: LockPalette.paper
        border.width: core.stage.px(5)
        border.color: LockPalette.cBorder
        antialiasing: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: core.stage.px(18)
            radius: height / 2
            color: LockPalette.well
            antialiasing: true

            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: core.stage.px(34)
                text: "Password"
                color: LockPalette.lavenderText
                font.family: Theme.fontFamily
                font.pixelSize: core.stage.px(34)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: core.stage.px(34)
                spacing: core.stage.px(10)

                Repeater {
                    model: 5

                    Rectangle {
                        width: core.stage.px(16)
                        height: width
                        radius: width / 2
                        color: LockPalette.lavenderText
                        opacity: 0.55
                    }
                }
            }
        }
    }

    Rectangle {
        x: core.pwW + core.gap
        width: core.unW
        height: core.pillH
        radius: height / 2
        color: LockPalette.mint
        border.width: core.stage.px(5)
        border.color: LockPalette.cBorder
        antialiasing: true

        Text {
            anchors.centerIn: parent
            text: "Unlock"
            color: LockPalette.cBorder
            font.family: Theme.fontFamily
            font.pixelSize: core.stage.px(44)
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
        }
    }

    // ===== the outline and its name =====
    Rectangle {
        anchors.fill: parent
        anchors.margins: -10 * core.px1
        radius: 14 * core.px1
        color: core.selected ? Qt.rgba(core.mt.accentMint.r, core.mt.accentMint.g, core.mt.accentMint.b, 0.10) : "transparent"
        border.width: (core.selected ? 3 : 2) * core.px1
        border.color: core.mt.accentMint
        opacity: core.selected ? 1 : (area.containsMouse ? 0.75 : 0)
        antialiasing: true

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }

    Item {
        visible: core.selected || area.containsMouse
        x: -10 * core.px1
        y: -10 * core.px1 - chip.height * core.px1 - 6 * core.px1
        width: chip.width
        height: chip.height
        scale: core.px1
        transformOrigin: Item.TopLeft

        Pill {
            id: chip
            width: chipRow.implicitWidth + 22
            height: 26
            cornerRadius: 9
            ringWidth: 3
            shadowDy: 3
            fillColor: core.mt.chipFill

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "lock"
                    size: 13
                    weight: 700
                    color: core.mt.chipInk
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PASSWORD   ALWAYS ON"
                    color: core.mt.chipInk
                    font.family: core.mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: core.mt.fontStyleBold
                }
            }
        }
    }

    // ===== moving it =====
    MouseArea {
        id: area
        anchors.fill: parent
        z: 10
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: area.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real startPx: 0
        property real startPy: 0
        property real startCx: 0
        property real startCy: 0
        property bool moved: false

        onPressed: mouse => {
            LockEditService.select("core")
            core.stage.takeFocus()
            const p = area.mapToItem(core.stage.view, mouse.x, mouse.y)
            area.startPx = p.x
            area.startPy = p.y
            area.startCx = core.cx
            area.startCy = core.cy
            area.moved = false
        }

        onPositionChanged: mouse => {
            if (!area.pressed)
                return
            const p = area.mapToItem(core.stage.view, mouse.x, mouse.y)
            const dx = p.x - area.startPx
            const dy = p.y - area.startPy
            if (!area.moved && Math.abs(dx) + Math.abs(dy) < 3 / core.stage.k)
                return
            if (!area.moved) {
                area.moved = true
                core.dragging = true
                LockEditService.begin()
            }

            let cx = area.startCx + dx
            let cy = area.startCy + dy
            const free = (mouse.modifiers & Qt.ShiftModifier) !== 0
            const t = EM.SNAP_PX / core.stage.k
            let gx = -1
            let gy = -1
            if (!free) {
                const lines = core.stage.linesFor(-1)
                const sx = EM.snapAxis(cx, core.drawnW, lines.xs, t)
                const sy = EM.snapAxis(cy, core.drawnH, lines.ys, t)
                cx += sx.delta
                cy += sy.delta
                gx = sx.line === null ? -1 : sx.line
                gy = sy.line === null ? -1 : sy.line
            }
            core.stage.guideX = gx
            core.stage.guideY = gy

            const fx = EM.keepOn(cx / core.stage.sw, core.width, 1, core.stage.sw)
            const fy = EM.keepOn(cy / core.stage.sh, core.height, 1, core.stage.sh)
            // setCore keeps it in its range, the same range the lock uses.
            LockEditService.live(LM.setCore(LockEditService.board, fx, fy))
        }

        onReleased: {
            core.stage.guideX = -1
            core.stage.guideY = -1
            core.dragging = false
            if (area.moved)
                LockEditService.finish()
            area.moved = false
        }
    }
}
