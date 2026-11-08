import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LockCanvasModel.js" as LM
import "../../common/functions/LockEditMath.js" as EM

// One widget of the Custom lockscreen, on the editor's card (LockEditStage.qml builds one per
// widget on the board). It is drawn by the very same Lock*Widget file the lockscreen uses, in
// the same place and at the same size (LM.placeAxis), with `preview` on so it always shows
// something. On top of it sits the editing:
//
//   press and drag     move it (it snaps to the middle of the screen and to the other widgets;
//                      hold Shift to move freely)
//   the corner knob    drag to resize (shown while it is selected)
//   wheel              resize a notch
//   right click        remove it
//
// The widget itself never gets a click: the media keys, for one, must not work while editing,
// so a MouseArea sits over it. Sizes the editor draws (outline, knob, chip) are divided by
// the card's scale and the widget's own, so they stay the same size on screen.
Item {
    id: slot

    // The stage that builds it (LockEditStage.qml): the card's scale, the screen's size, the
    // widget map and the guide lines.
    required property var stage
    required property int index

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    readonly property var spec: LockEditService.board.items[slot.index]
    readonly property string uid: slot.spec ? slot.spec.uid : ""
    readonly property string kind: slot.spec ? slot.spec.kind : ""
    readonly property real sc: slot.spec ? slot.spec.scale : 1
    readonly property bool selected: slot.uid !== "" && LockEditService.selected === slot.uid
    readonly property var info: LM.describe(slot.kind)

    // Pixels of the SCREEN that make one pixel of the card, for the things that must keep
    // their size on screen.
    readonly property real px1: 1 / (slot.stage.k * slot.sc)

    // The centre and the drawn size along each axis (screen pixels), for the others' guides.
    readonly property real cx: slot.x + slot.width / 2
    readonly property real cy: slot.y + slot.height / 2
    readonly property real drawnW: slot.width * slot.sc
    readonly property real drawnH: slot.height * slot.sc

    width: ld.item ? ld.item.implicitWidth : 0
    height: ld.item ? ld.item.implicitHeight : 0
    scale: slot.sc
    transformOrigin: Item.Center
    x: EM.placeAxis(slot.spec ? slot.spec.x : 0.5, slot.width, slot.sc, slot.stage.sw)
    y: EM.placeAxis(slot.spec ? slot.spec.y : 0.5, slot.height, slot.sc, slot.stage.sh)
    z: slot.selected ? 5 : 1
    visible: slot.spec !== undefined && slot.width > 0 && slot.height > 0

    Loader {
        id: ld
        sourceComponent: slot.stage.kinds[slot.kind]

        onLoaded: {
            ld.item.options = Qt.binding(() => slot.spec ? slot.spec.options : ({}))
            ld.item.u = Qt.binding(() => slot.stage.u)
            ld.item.now = Qt.binding(() => slot.stage.now)
            ld.item.preview = true
        }
    }

    // ===== the outline =====
    Rectangle {
        anchors.fill: parent
        anchors.margins: -10 * slot.px1
        radius: 14 * slot.px1
        color: slot.selected ? Qt.rgba(slot.mt.accentMint.r, slot.mt.accentMint.g, slot.mt.accentMint.b, 0.10) : "transparent"
        border.width: (slot.selected ? 3 : 2) * slot.px1
        border.color: slot.mt.accentMint
        opacity: slot.selected ? 1 : (area.containsMouse ? 0.75 : 0)
        antialiasing: true

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }

    // ===== what it is, and how big =====
    Item {
        visible: slot.selected || area.containsMouse
        x: -10 * slot.px1
        y: -10 * slot.px1 - chip.height * slot.px1 - 6 * slot.px1
        width: chip.width
        height: chip.height
        scale: slot.px1
        transformOrigin: Item.TopLeft

        Pill {
            id: chip
            width: chipText.implicitWidth + 22
            height: 26
            cornerRadius: 9
            ringWidth: 3
            shadowDy: 3
            fillColor: slot.mt.chipFill

            Text {
                id: chipText
                anchors.centerIn: parent
                text: (slot.info ? slot.info.title.toUpperCase() : "") + "   " + EM.percent(slot.sc)
                color: slot.mt.chipInk
                font.family: slot.mt.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: slot.mt.fontStyleBold
            }
        }
    }

    // ===== moving it =====
    MouseArea {
        id: area
        anchors.fill: parent
        z: 10
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        cursorShape: area.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        // Where the pointer and the widget's centre were when the press began (screen pixels).
        property real startPx: 0
        property real startPy: 0
        property real startCx: 0
        property real startCy: 0
        property bool moved: false

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return
            LockEditService.select(slot.uid)
            slot.stage.takeFocus()
            const p = area.mapToItem(slot.stage.view, mouse.x, mouse.y)
            area.startPx = p.x
            area.startPy = p.y
            area.startCx = slot.cx
            area.startCy = slot.cy
            area.moved = false
        }

        onPositionChanged: mouse => {
            if (!area.pressed || !(mouse.buttons & Qt.LeftButton))
                return
            const p = area.mapToItem(slot.stage.view, mouse.x, mouse.y)
            const dx = p.x - area.startPx
            const dy = p.y - area.startPy
            // A click that wobbles a pixel is still a click.
            if (!area.moved && Math.abs(dx) + Math.abs(dy) < 3 / slot.stage.k)
                return
            if (!area.moved) {
                area.moved = true
                LockEditService.begin()
            }

            let cx = area.startCx + dx
            let cy = area.startCy + dy
            const free = (mouse.modifiers & Qt.ShiftModifier) !== 0
            const t = EM.SNAP_PX / slot.stage.k
            let gx = -1
            let gy = -1
            if (!free) {
                const lines = slot.stage.linesFor(slot.index)
                const sx = EM.snapAxis(cx, slot.drawnW, lines.xs, t)
                const sy = EM.snapAxis(cy, slot.drawnH, lines.ys, t)
                cx += sx.delta
                cy += sy.delta
                gx = sx.line === null ? -1 : sx.line
                gy = sy.line === null ? -1 : sy.line
            }
            slot.stage.guideX = gx
            slot.stage.guideY = gy

            const fx = EM.keepOn(cx / slot.stage.sw, slot.width, slot.sc, slot.stage.sw)
            const fy = EM.keepOn(cy / slot.stage.sh, slot.height, slot.sc, slot.stage.sh)
            LockEditService.live(LM.moveItem(LockEditService.board, slot.uid, fx, fy))
        }

        onReleased: mouse => {
            slot.stage.guideX = -1
            slot.stage.guideY = -1
            if (area.moved)
                LockEditService.finish()
            area.moved = false
        }

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                LockEditService.remove(slot.uid)
        }

        onWheel: wheel => {
            LockEditService.select(slot.uid)
            LockEditService.stepScale(slot.uid, wheel.angleDelta.y > 0 ? 1 : -1, 0.05)
            wheel.accepted = true
        }
    }

    // ===== the size knob =====
    Item {
        id: knob
        visible: slot.selected
        z: 20
        width: 26
        height: 26
        x: slot.width + 10 * slot.px1 - 13 * slot.px1
        y: slot.height + 10 * slot.px1 - 13 * slot.px1
        scale: slot.px1
        transformOrigin: Item.TopLeft

        Pill {
            anchors.fill: parent
            cornerRadius: 9
            ringWidth: 3
            shadowDy: 3
            pressed: knobArea.pressed
            fillGradient: Gradient {
                GradientStop { position: 0.0; color: slot.mt.accentMint }
                GradientStop { position: 1.0; color: slot.mt.accentCyan }
            }

            MaterialIcon {
                anchors.centerIn: parent
                name: "open_in_full"
                size: 14
                weight: 700
                color: slot.mt.colBorder
            }
        }

        MouseArea {
            id: knobArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            preventStealing: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeFDiagCursor

            property real startScale: 1
            property real startDist: 1
            property real centreX: 0
            property real centreY: 0
            property bool moved: false

            function dist(mouse) {
                const p = knobArea.mapToItem(slot.stage.view, mouse.x, mouse.y)
                return Math.hypot(p.x - knobArea.centreX, p.y - knobArea.centreY)
            }

            onPressed: mouse => {
                slot.stage.takeFocus()
                // The widget's centre on the screen: the scale is about it, so the pointer's
                // distance from it is what the size follows.
                knobArea.centreX = slot.cx
                knobArea.centreY = slot.cy
                knobArea.startScale = slot.sc
                knobArea.startDist = knobArea.dist(mouse)
                knobArea.moved = false
            }

            onPositionChanged: mouse => {
                if (!knobArea.pressed)
                    return
                if (!knobArea.moved) {
                    knobArea.moved = true
                    LockEditService.begin()
                }
                const s = EM.scaleFromDrag(knobArea.startScale, knobArea.startDist, knobArea.dist(mouse))
                LockEditService.live(LM.scaleItem(LockEditService.board, slot.uid, s))
            }

            onReleased: {
                if (knobArea.moved)
                    LockEditService.finish()
                knobArea.moved = false
            }
        }
    }
}
