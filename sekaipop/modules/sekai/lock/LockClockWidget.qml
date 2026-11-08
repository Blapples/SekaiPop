import QtQuick
import qs.services
import qs.modules.common

// The time, in big outlined type. Option `format`: auto (follows Settings -> General ->
// 24-hour time) | 12h | 24h.
LockWidget {
    id: root

    readonly property string format: String(root.opt("format", "auto"))
    readonly property bool use24h: root.format === "auto" ? SettingsService.flag("time.use24h") : root.format === "24h"

    implicitWidth: row.implicitWidth
    implicitHeight: face.implicitHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.px(16)

        LockOutlinedText {
            id: face
            text: Qt.formatDateTime(root.now, root.use24h ? "HH:mm" : "h:mm")
            pixelSize: root.px(190)
            outline: Math.max(1, root.px(4))
        }

        // AM / PM.
        Rectangle {
            visible: !root.use24h
            anchors.verticalCenter: parent.verticalCenter
            width: tag.implicitWidth + root.px(36)
            height: root.px(52)
            radius: height / 2
            color: LockPalette.mint

            Text {
                id: tag
                anchors.centerIn: parent
                text: Qt.formatDateTime(root.now, "AP")
                color: LockPalette.cBorder
                font.family: Theme.fontFamily
                font.pixelSize: root.px(32)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }
    }
}
