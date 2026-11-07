import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// A round-cornered icon (or short text) key, like the − / + keys of the shell-scale card:
// the Pill with outline, ring and hard shadow, pressing into it on a click. Back arrows,
// font size, fullscreen, sort order. `lit` turns it into the accent gradient.
//
//   ReaderKey { icon: "arrow_back"; onClicked: ... }
//   ReaderKey { label: "A+"; onClicked: ... }
Item {
    id: root

    property string icon: ""
    // Text instead of an icon ("A−", "A+").
    property string label: ""
    property bool lit: false
    property alias hovered: keyArea.containsMouse

    signal clicked()

    implicitWidth: 40
    implicitHeight: 36
    opacity: root.enabled ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Gradient {
        id: litGradient
        GradientStop { position: 0.0; color: Theme.accentMint }
        GradientStop { position: 1.0; color: Theme.accentCyan }
    }

    Pill {
        anchors.fill: parent
        shadowDy: 3
        ringWidth: 4
        cornerRadius: 15
        pressed: keyArea.pressed && root.enabled
        fillColor: root.lit ? Theme.accentCyan : (keyArea.containsMouse ? Theme.accentMint : Theme.chipFill)
        fillGradient: root.lit ? litGradient : null

        MaterialIcon {
            visible: root.icon.length > 0
            anchors.centerIn: parent
            name: root.icon
            size: 18
            weight: 600
            color: (root.lit || keyArea.containsMouse) ? Theme.colBorder : Theme.chipInk
        }

        Text {
            visible: root.label.length > 0
            anchors.centerIn: parent
            text: root.label
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
            color: (root.lit || keyArea.containsMouse) ? Theme.colBorder : Theme.chipInk
        }
    }

    MouseArea {
        id: keyArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
