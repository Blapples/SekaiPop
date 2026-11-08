import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The water inside a glass (WaterTile.qml, WaterTankWidget.qml): a body of colour that rises from the
// bottom, with a bright line on its surface, clipped to the glass's rounded inside. The colour is the
// theme's cyan fading to mint, so it follows matugen and the looks like everything else.
//
//   WaterFill {
//       anchors.fill: parent
//       radius: key.cornerRadius - key.ringWidth      // the glass's inner corner radius
//       level: 0.6                                    // 0..1 (a little more is fine: the overshoot)
//       marks: 8                                      // ticks along the edge, one per glass of the goal (0 = none)
//   }
RoundClip {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property real level: 0
    property real radius: 20
    property int marks: 0

    radii: [root.radius, root.radius, root.radius, root.radius]

    Rectangle {
        id: water
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.height * Math.max(0, Math.min(1.08, root.level))

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.82) }
            GradientStop { position: 1.0; color: Qt.rgba(mt.accentMint.r, mt.accentMint.g, mt.accentMint.b, 0.66) }
        }

        // The surface: a bright line on top of the water.
        Rectangle {
            visible: water.height > 5
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 3
            color: Qt.rgba(1, 1, 1, 0.7)
        }
    }

    // One tick per glass of the goal, short, on the right edge.
    Repeater {
        model: root.marks > 1 ? root.marks - 1 : 0

        delegate: Rectangle {
            required property int index

            width: 12
            height: 2
            radius: 1
            x: root.width - width - 6
            y: root.height * (1 - (index + 1) / root.marks) - 1
            // Light on a dark glass (the navy ticks vanished into it), navy on a light one.
            color: mt.dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.4)
        }
    }
}
