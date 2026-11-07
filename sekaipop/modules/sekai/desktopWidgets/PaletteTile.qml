import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The palette card at 1 x 1 (a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with the
// housing): the five colours as ONE paint-chip fan, riveted at its foot, standing straight on
// the wallpaper (no backdrop). Point at it and the fan opens a little wider; a click on the
// tile (PaletteWidget's drag area) shuffles the colours: the fan squeezes while the button is
// down, then the chips flick shut and spring open again on the new ones. A chip that is
// locked wears a small lock. Nothing here changes the theme: Apply is on the bigger sizes.
//
//   PaletteTile {
//       width: card.contentW; height: card.contentH
//       colors: PaletteService.colors
//       locks: PaletteService.locks
//       hover: dragArea.containsMouse
//       pressed: dragArea.pressed
//   }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property var colors: ["#555473", "#6e6d94", "#04feee", "#00ffcb", "#d9fff6"]
    property var locks: [false, false, false, false, false]
    property bool hover: false
    property bool pressed: false

    // Where each chip leans, in degrees, from the rivet at the bottom middle.
    readonly property var lean: [-28, -14, 0, 14, 28]
    readonly property int chipW: 36
    readonly property int chipH: 108

    // The fan's openness: 1 at rest, a little more while pointed at, a little less while the
    // button is down, and the flick on a new set of colours drops it to 0.35 and lets it
    // spring back (see `flick`).
    property real kick: 1
    // Not `readonly`: a Behavior writes to the property it animates, and QML refuses that on a
    // read-only one ("Invalid property assignment: spread is a read-only property").
    property real spread: root.pressed ? 0.8 : (root.hover ? 1.1 : 1)

    Behavior on spread {
        NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }

    // Only a change after the first set of colours flicks.
    property bool armed: false
    Component.onCompleted: root.armed = true

    onColorsChanged: {
        if (root.armed)
            flick.restart()
    }

    SequentialAnimation {
        id: flick
        NumberAnimation { target: root; property: "kick"; to: 0.35; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "kick"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
    }

    TinyFoot {
        id: foot
        anchors.fill: parent

        // Where the chips pivot: the bottom middle of the footprint.
        readonly property real pivotY: foot.capH - 6

        Repeater {
            model: 5

            Pill {
                id: chip
                required property int index

                // The middle chip on top, the outer ones behind it.
                z: 5 - Math.abs(chip.index - 2)
                width: root.chipW
                height: root.chipH
                x: foot.capW / 2 - root.chipW / 2
                y: foot.pivotY - root.chipH
                cornerRadius: 12
                ringWidth: mt.borderWidth + mt.whiteLine
                shadowDx: 3
                shadowDy: 4
                fillColor: root.colors[chip.index] ?? "#888888"
                transformOrigin: Item.Bottom
                rotation: root.lean[chip.index] * root.kick * root.spread

                Behavior on fillColor {
                    ColorAnimation { duration: 280 }
                }

                MaterialIcon {
                    visible: root.locks[chip.index] === true
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 9
                    name: "lock"
                    size: 14
                    weight: 600
                    color: mt.colBorder
                }
            }
        }

        // The rivet that holds the fan together, over every chip.
        Rectangle {
            z: 10
            width: 16
            height: 16
            radius: 8
            x: foot.capW / 2 - 8
            y: foot.pivotY - 18
            color: "#ffffff"
            border.width: mt.borderWidth
            border.color: mt.colBorder
            antialiasing: true

            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: mt.colBorder
            }
        }
    }
}
