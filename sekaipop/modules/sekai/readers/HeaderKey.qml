import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// An icon key for a reader's header plate, built like the Browse / Library switch next to it
// (SegmentSwitch): one flat dark capsule with the theme's thin outline, no ring and no hard
// shadow, so every element on the plate is the same kind of thing and the same height. It lights
// up mint under the pointer (the switch's own thumb colour) and sinks a little while pressed.
//
//   HeaderKey { icon: "remove"; onClicked: ... }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string icon: ""
    readonly property bool hovered: area.containsMouse

    signal clicked()

    // The height every element of the header shares (the switch, the profile key, these).
    implicitWidth: ReaderType.hField
    implicitHeight: ReaderType.hField

    Rectangle {
        id: cap
        anchors.fill: parent
        radius: height / 2.4
        color: root.hovered ? root.mt.accentMint : root.mt.surfaceHover
        border.width: root.mt.borderWidth
        border.color: root.mt.line
        antialiasing: true
        scale: area.pressed ? 0.93 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        // The two window keys are drawn here, bare: the icon set's own minus and x come inside a
        // circle, which made a circle in a capsule. Any other icon name still uses the set.
        readonly property color glyphColor: root.hovered ? Theme.colBorder : Theme.ink

        // Minimize: one bar.
        Rectangle {
            visible: root.icon === "remove"
            anchors.centerIn: parent
            width: 14; height: 2.5; radius: 1.25
            color: cap.glyphColor
            antialiasing: true
        }

        // Close: two bars crossed.
        Item {
            visible: root.icon === "close"
            anchors.centerIn: parent
            width: 14; height: 14
            Rectangle {
                anchors.centerIn: parent
                width: 16; height: 2.5; radius: 1.25
                rotation: 45
                color: cap.glyphColor
                antialiasing: true
            }
            Rectangle {
                anchors.centerIn: parent
                width: 16; height: 2.5; radius: 1.25
                rotation: -45
                color: cap.glyphColor
                antialiasing: true
            }
        }

        MaterialIcon {
            visible: root.icon !== "remove" && root.icon !== "close"
            anchors.centerIn: parent
            name: root.icon
            size: 20
            weight: 600
            color: cap.glyphColor
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
