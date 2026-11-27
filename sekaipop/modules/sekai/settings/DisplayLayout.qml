import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import "../../common/functions/DisplayMath.js" as DM

// The screens drawn to scale, side by side the way they sit on the desk. Drag one to
// move it: it snaps to the edges of the others (flush, or lined up top / bottom / left
// / right), and when you let go it is slid off any screen it landed on. Nothing is
// applied until you press Apply in the card (services/DisplayService.qml keeps the
// draft). The main screen (the one the Placed keys measure from) is the coloured one.
//
//   DisplayLayout { width: card.innerWidth }
Item {
    id: root
    // The screen whose settings the card shows (drawn with a thicker outline), and a
    // click on a screen to pick it.
    property string selected: ""
    signal screenPicked(string name)

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    width: parent ? parent.width : 600
    height: 250

    // The screens that are on: [{ name, x, y, w, h }], in layout (logical) pixels.
    readonly property var screens: DisplayService.rects()
    readonly property real pad: 14
    readonly property var vw: DM.view(screens, width - pad * 2, height - pad * 2)
    // How near an edge has to be (on screen) before it snaps.
    readonly property real snapPx: 14

    // The whole drawing sits on a soft floor.
    Rectangle {
        anchors.fill: parent
        radius: 22
        color: mt.pSurfaceHover
        border.width: 2
        border.color: mt.pSurfaceDivider
        antialiasing: true
    }

    Text {
        anchors.centerIn: parent
        visible: root.screens.length === 0
        text: "No screen is on"
        color: mt.pInkSub
        font.family: mt.fontFamily
        font.pixelSize: 16
    }

    Repeater {
        model: root.screens

        Item {
            id: tile

            required property var modelData
            readonly property var r: modelData
            readonly property bool isMain: r.name === DisplayService.mainName

            // While it is being dragged it shows the snapped spot; the draft only
            // changes when you let go.
            property bool dragging: false
            property real lx: r.x
            property real ly: r.y

            x: root.pad + root.vw.ox + (dragging ? lx : r.x) * root.vw.scale
            y: root.pad + root.vw.oy + (dragging ? ly : r.y) * root.vw.scale
            width: Math.max(24, r.w * root.vw.scale)
            height: Math.max(18, r.h * root.vw.scale)
            z: dragging ? 10 : 1

            Behavior on x { enabled: !tile.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !tile.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            // hard shadow, deeper while it is lifted
            Rectangle {
                x: tile.dragging ? 4 : 2
                y: tile.dragging ? 6 : 3
                width: tile.width
                height: tile.height
                radius: 12
                color: mt.pLineShadow
                antialiasing: true
            }

            Rectangle {
                id: face
                anchors.fill: parent
                radius: 12
                antialiasing: true
                border.width: tile.r.name === root.selected ? mt.borderWidth * 2 + 1 : mt.borderWidth
                border.color: mt.pLine
                gradient: tile.isMain ? mainFill : null
                color: tile.isMain ? mt.accentCyan : (area.containsMouse || tile.dragging ? mt.pSurfaceHover : mt.pSurface)

                Gradient {
                    id: mainFill
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: mt.accentCyan }
                    GradientStop { position: 1; color: mt.accentMint }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    spacing: 1

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tile.r.name
                        color: mt.pInk
                        font.family: mt.fontFamily
                        font.pixelSize: Math.max(10, Math.min(17, tile.height / 4.5))
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }

                    Text {
                        visible: tile.height > 54
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: Math.round(tile.r.w) + " \u00d7 " + Math.round(tile.r.h)
                        color: mt.pInkSub
                        font.family: mt.fontFamily
                        font.pixelSize: Math.max(9, Math.min(13, tile.height / 6))
                    }
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                enabled: !DisplayService.confirming
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                // Where the press landed, in the card's own coordinates (the tile
                // moves under the pointer, so tile coordinates would chase themselves).
                property real sx: 0
                property real sy: 0

                function others() {
                    return root.screens.filter(o => o.name !== tile.r.name)
                }

                onPressed: mouse => {
                    root.screenPicked(tile.r.name)
                    const p = mapToItem(root, mouse.x, mouse.y)
                    sx = p.x
                    sy = p.y
                    tile.lx = tile.r.x
                    tile.ly = tile.r.y
                    tile.dragging = true
                }

                onPositionChanged: mouse => {
                    if (!pressed)
                        return
                    const p = mapToItem(root, mouse.x, mouse.y)
                    const s = root.vw.scale
                    const snapped = DM.snap({
                        x: tile.r.x + (p.x - sx) / s,
                        y: tile.r.y + (p.y - sy) / s,
                        w: tile.r.w,
                        h: tile.r.h
                    }, others(), root.snapPx / s)
                    tile.lx = snapped.x
                    tile.ly = snapped.y
                }

                onReleased: {
                    if (!tile.dragging)
                        return
                    const moved = Math.abs(tile.lx - tile.r.x) >= 1 || Math.abs(tile.ly - tile.r.y) >= 1
                    if (moved)
                        DisplayService.setPosition(tile.r.name, tile.lx, tile.ly)
                    tile.dragging = false
                }

                onCanceled: tile.dragging = false
            }
        }
    }
}
