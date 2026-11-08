import Quickshell
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Your avatar (the Quick Panel's picture, or your initial) and your name, and when the
// screen was locked. Option `since`: show the "Locked since" line.
LockWidget {
    id: root

    readonly property string userName: Quickshell.env("USER") || "user"
    readonly property bool use24h: SettingsService.flag("time.use24h")
    readonly property bool since: root.opt("since", true) === true

    implicitWidth: cap.width
    implicitHeight: cap.height

    LockCapsule {
        id: cap
        width: row.implicitWidth + root.px(14) + root.px(40)
        height: root.capH

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: root.px(14)
            spacing: root.px(18)

            RoundClip {
                width: root.px(88)
                height: width
                radii: [width / 2, width / 2, width / 2, width / 2]
                color: LockPalette.mint

                Image {
                    id: avatar
                    anchors.fill: parent
                    visible: status === Image.Ready
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(root.px(176), root.px(176))
                    source: PanelImages.avatar
                }

                Text {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: root.userName.charAt(0).toUpperCase()
                    color: LockPalette.cBorder
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(50)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(2)

                Text {
                    width: Math.min(implicitWidth, root.px(320))
                    elide: Text.ElideRight
                    text: root.userName
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(40)
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                Text {
                    visible: root.since
                    text: "Locked since " + Qt.formatDateTime(LockState.lockedAt, root.use24h ? "HH:mm" : "h:mm AP")
                    color: LockPalette.lavenderText
                    font.family: Theme.fontFamily
                    font.pixelSize: root.px(22)
                    font.weight: Font.Bold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }
    }
}
