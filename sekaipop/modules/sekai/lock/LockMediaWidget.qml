import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// What is playing (title and artist) with previous / play-pause / next keys, in a capsule
// the same height as the User widget's. Option: `controls` (the keys). The line of the song
// being sung is its own widget (LockLyricsWidget.qml).
//
// The keys are the one thing on the lockscreen that does something besides draw: they
// only ever call the player's own MPRIS controls (MediaSource), never a program. There is
// no cover picture on purpose: players hand over web addresses for it, and the lockscreen
// does not fetch from the network. Nothing is drawn while no player is running (always
// something in the editor).
LockWidget {
    id: root

    readonly property bool present: root.media !== null && root.media.present
    readonly property bool shown: root.present || root.preview
    readonly property bool controls: root.opt("controls", true) === true

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    // A round key. `px` is passed in: an inline component does not see the file's own ids.
    component RoundKey: Rectangle {
        id: key

        property string icon: ""
        property var px: n => n
        signal clicked()

        width: key.px(64)
        height: width
        radius: width / 2
        color: area.pressed ? LockPalette.mint : LockPalette.well

        MaterialIcon {
            anchors.centerIn: parent
            name: key.icon
            size: key.px(32)
            weight: 600
            color: area.pressed ? LockPalette.cBorder : "white"
        }

        MouseArea {
            id: area
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: key.clicked()
        }
    }

    LockCapsule {
        id: cap
        visible: root.shown
        width: root.controls ? root.px(640) : root.px(520)
        height: root.capH

        Column {
            x: root.capPad
            anchors.verticalCenter: parent.verticalCenter
            width: root.controls ? root.px(330) : parent.width - root.capPad * 2
            spacing: root.px(2)

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.present ? root.media.title : "Song title"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(40)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: root.present ? root.media.artist : "Artist"
                color: LockPalette.lavenderText
                font.family: Theme.fontFamily
                font.pixelSize: root.px(22)
                font.weight: Font.Bold
                font.styleName: Theme.fontStyleBold
            }
        }

        Row {
            visible: root.controls
            anchors.right: parent.right
            anchors.rightMargin: root.px(26)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.px(10)

            RoundKey {
                px: root.px
                icon: "skip_previous"
                onClicked: if (root.media) root.media.previous()
            }

            RoundKey {
                px: root.px
                icon: root.present && root.media.playing ? "pause" : "play_arrow"
                onClicked: if (root.media) root.media.togglePlaying()
            }

            RoundKey {
                px: root.px
                icon: "skip_next"
                onClicked: if (root.media) root.media.next()
            }
        }
    }
}
