import QtQuick
import Quickshell
import qs.modules.common

// One labelled reading with a thin bar under it, for the rows of the CPU & RAM card
// (ResourcePopup.qml): a temperature or a disk's fill. "CPU", "62°C · COOL" on the right, and the bar
// runs 0..1 in the accent gradient, turning red-pink when `hot`. The bar rises when the card opens
// (`wave` goes 0 -> 1, the same value the card's gauges use).
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string label: ""
    property string valueText: ""
    property real frac: 0
    property bool hot: false
    property real wave: 1

    implicitHeight: 32

    Text {
        anchors.left: parent.left
        y: 2
        anchors.right: valueLabel.left
        anchors.rightMargin: 8
        elide: Text.ElideRight
        text: root.label
        color: mt.ink
        font.family: mt.fontFamily
        font.pixelSize: 13
        font.weight: Font.ExtraBold
        font.styleName: mt.fontStyleBold
    }

    Text {
        id: valueLabel
        anchors.right: parent.right
        y: 2
        text: root.valueText
        color: root.hot ? "#e0575b" : mt.inkSub
        font.family: mt.fontFamily
        font.pixelSize: 12
        font.weight: Font.ExtraBold
        font.styleName: mt.fontStyleBold
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        height: 6
        radius: 3
        color: mt.chipFill
        opacity: 0.6

        Rectangle {
            height: parent.height
            width: parent.width * Math.max(0, Math.min(1, root.frac)) * root.wave
            radius: 3
            color: root.hot ? "#e0575b" : "transparent"
            gradient: root.hot ? null : fill
        }

        Gradient {
            id: fill
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: mt.accentMint }
            GradientStop { position: 1.0; color: mt.accentCyan }
        }
    }
}
