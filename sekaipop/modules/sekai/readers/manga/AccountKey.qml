import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The AniList account key in the manga panel's header: the logged-in profile (avatar and name),
// or "Log in" with an account icon while nobody is. Built like the other elements of the header
// plate (HeaderKey, the Browse / Library switch): one flat dark capsule, the same 40 px tall,
// lighting up mint under the pointer. The avatar comes through the backend's /image proxy
// (Manga.alViewer.avatar), like the covers.
//
//   AccountKey { onClicked: anilistLogin.open() }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    readonly property bool loggedIn: Manga.alLoggedIn
    readonly property string name: Manga.alViewer && Manga.alViewer.name ? Manga.alViewer.name : ""
    readonly property string avatar: Manga.alViewer && Manga.alViewer.avatar ? Manga.alViewer.avatar : ""
    // The room the name has before it is cut with an ellipsis.
    property real maxNameWidth: 96
    readonly property bool hovered: area.containsMouse

    signal clicked()

    // The picture sits 4 px in from the capsule's edge, all round.
    readonly property real avatarSize: 32

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 4 + 14
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: cap
        anchors.fill: parent
        radius: height / 2.4
        color: root.hovered ? root.mt.accentMint : root.mt.surfaceHover
        border.width: root.mt.borderWidth
        border.color: root.mt.line
        antialiasing: true
        scale: area.pressed ? 0.96 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        Row {
            id: row
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // The profile picture, or an account icon while logged out / before it has loaded.
            RoundClip {
                anchors.verticalCenter: parent.verticalCenter
                width: root.avatarSize
                height: root.avatarSize
                radii: [root.avatarSize / 2.4, root.avatarSize / 2.4, root.avatarSize / 2.4, root.avatarSize / 2.4]

                Rectangle {
                    anchors.fill: parent
                    color: Colors.surface_container_high
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: avatarImage.status !== Image.Ready
                    name: "account_circle"
                    size: 22
                    weight: 600
                    color: Theme.ink
                }

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: root.loggedIn ? root.avatar : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 64
                    sourceSize.height: 64
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.maxNameWidth)
                text: root.loggedIn && root.name.length > 0 ? root.name : (root.loggedIn ? "Profile" : "Log in")
                elide: Text.ElideRight
                color: root.hovered ? Theme.colBorder : Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
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
