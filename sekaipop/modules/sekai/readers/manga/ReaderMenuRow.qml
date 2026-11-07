import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// One row of the reader's popovers: an icon, a text, a short hint on the right, and a mint
// fill with the shell's outline when it is the chosen one.
//
//   ReaderMenuRow { icon: "book"; text: "Tablet"; checked: mode === "spread"; onClicked: ... }
Item {
    id: root

    property string icon: ""
    property string text: ""
    property string hint: ""
    property bool checked: false
    property alias hovered: area.containsMouse

    signal clicked()

    implicitHeight: 34
    implicitWidth: 240
    opacity: root.enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: 12
        antialiasing: true
        color: root.checked
            ? Qt.tint(Theme.surface, Qt.rgba(Theme.accentMint.r, Theme.accentMint.g, Theme.accentMint.b, 0.55))
            : (area.containsMouse ? Theme.surfaceHover : "transparent")
        border.width: root.checked ? 2 : 0
        border.color: Theme.line
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 10
        spacing: 9

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon.length > 0
            name: root.icon
            size: 17
            weight: 600
            color: Theme.ink
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: root.checked ? Font.ExtraBold : Font.DemiBold
            font.styleName: Theme.fontStyleBold
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 12
        text: root.hint
        color: Theme.inkSub
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.weight: Font.Bold
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
