import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// The capsule most of the lockscreen's information widgets share (timer, notifications, event,
// to-do, countdown): an icon, a main line, and a smaller second line under it when there is
// one. It is not a widget itself, only the look; the widgets give it their words. It draws
// and nothing else, like every part of the lockscreen.
LockCapsule {
    id: root

    // The widget's px() (design pixels at the screen's scale), capH and capPad (LockWidget.qml).
    property var px: n => n
    property real capH: 116
    property real capPad: 44

    property string icon: ""
    property color iconColor: LockPalette.lavenderText
    property string title: ""
    property color titleColor: "white"
    property string subtitle: ""

    width: row.implicitWidth + root.capPad * 2
    height: root.capH

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.px(16)

        MaterialIcon {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: root.px(48)
            weight: 600
            color: root.iconColor
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: Math.min(implicitWidth, root.px(560))
                elide: Text.ElideRight
                text: root.title
                color: root.titleColor
                font.family: Theme.fontFamily
                font.pixelSize: root.px(40)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Text {
                visible: root.subtitle !== ""
                width: Math.min(implicitWidth, root.px(560))
                elide: Text.ElideRight
                text: root.subtitle
                color: LockPalette.lavenderText
                font.family: Theme.fontFamily
                font.pixelSize: root.px(22)
                font.weight: Font.Bold
                font.styleName: Theme.fontStyleBold
            }
        }
    }
}
