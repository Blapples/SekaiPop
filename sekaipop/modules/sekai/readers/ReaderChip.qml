import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// A small text key in the shell's own build: the Pill (outline, white ring, hard shadow) that
// dips into its shadow when pressed and springs back. Same as the chips of the shell-scale
// card. `lit` fills it with the accent gradient (the chosen filter, "in library"), and an
// optional `icon` sits before the text.
//
//   ReaderChip { text: "Latest"; lit: current === "latest"; onClicked: ... }
Item {
    id: root

    property string text: ""
    property string icon: ""
    property bool lit: false

    signal clicked()

    implicitHeight: ReaderType.hChip
    implicitWidth: chipPill.implicitWidth
    opacity: root.enabled ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Gradient {
        id: litGradient
        GradientStop { position: 0.0; color: Theme.accentMint }
        GradientStop { position: 1.0; color: Theme.accentCyan }
    }

    Pill {
        id: chipPill
        anchors.fill: parent
        shadowDy: 3
        ringWidth: 5
        cornerRadius: 15
        pressed: chipArea.pressed && root.enabled
        fillColor: chipArea.containsMouse && !root.lit ? Theme.surfaceTint : Theme.surfaceHover
        fillGradient: root.lit ? litGradient : null
        implicitWidth: chipRow.implicitWidth + (root.icon.length > 0 ? 26 : 30)

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            MaterialIcon {
                visible: root.icon.length > 0
                anchors.verticalCenter: parent.verticalCenter
                name: root.icon
                size: 15
                weight: 600
                color: root.lit ? Theme.colBorder : Theme.ink
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                color: root.lit ? Theme.colBorder : Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }
    }

    MouseArea {
        id: chipArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
