import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// A small key under the lyrics (the sync keys). Two looks:
//
//   An icon key   LyricsKey { icon: "double_alt_arrow_left"; tip: "earlier"; onClicked: ... }
//                 The same little badge as the bar's workspace badges (cyan, white ring, navy
//                 outline, hard shadow; nothing behind it, like the Transparent bar), with
//                 just an icon in it. Pointing at it lifts it a little and says what it is in
//                 a small dark tag above it; a press pushes it into its shadow.
//   A text key    LyricsKey { label: "+0.3 s"; onClicked: ... }
//                 A sticker word that grows a little when you point at it (no icon, no tag).
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string label: ""
    // A Solar / Material icon name (MaterialIcon.qml). When set, the key is a badge and `label` is not drawn.
    property string icon: ""
    // What the hover tag says (icon keys).
    property string tip: ""
    // The tag opens under the key instead of over it (the keys sit under the title).
    property bool tipBelow: false
    signal clicked

    readonly property bool hovered: area.containsMouse
    readonly property bool isBadge: root.icon !== ""

    // The workspace badge's box: 36 wide, 36 tall plus the hard shadow.
    readonly property real badgeSize: 36

    implicitWidth: root.isBadge ? root.badgeSize : (wordLoader.item ? wordLoader.item.implicitWidth : 0)
    // A text key is as tall as the icon keys beside it, with its word in the middle.
    implicitHeight: root.badgeSize + mt.shadowOffset
    width: implicitWidth
    height: implicitHeight

    // The key being pointed at is drawn over its neighbours (and its tag over everything).
    z: root.hovered ? 5 : 0

    // ===== text key =====
    Item {
        anchors.fill: parent
        visible: !root.isBadge

        scale: area.pressed ? 0.94 : (area.containsMouse ? 1.1 : 1)
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 2 }
        }

        Loader {
            id: wordLoader
            anchors.centerIn: parent
            active: !root.isBadge

            sourceComponent: LyricsWord {
                text: root.label
                pixelSize: 15
                fillColor: area.containsMouse ? mt.accentMint : "#FFFFFF"
            }
        }
    }

    // ===== icon key =====
    Pill {
        id: badge
        visible: root.isBadge
        width: root.badgeSize
        height: root.badgeSize + mt.shadowOffset

        cornerRadius: mt.radiusBadge
        ringWidth: 8
        fillColor: area.containsMouse ? mt.accentMint : mt.accentCyan
        pressed: area.pressed

        // Lifts a touch when pointed at, same soft bounce as the workspace badges.
        scale: area.containsMouse && !area.pressed ? 1.12 : 1
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }

        MaterialIcon {
            anchors.centerIn: parent
            name: root.icon
            size: 16
            color: mt.colBorder
        }
    }

    // The hover tag: what the key does. Dark, rounded, like the bar's hover tags.
    Rectangle {
        id: tag
        readonly property bool want: root.isBadge && root.tip !== "" && area.containsMouse && !area.pressed

        z: 10
        opacity: tag.want ? 1 : 0
        visible: opacity > 0.01
        x: Math.round((root.width - width) / 2)
        y: root.tipBelow ? root.height + 10 + (tag.want ? 0 : -4) : -height - 10 + (tag.want ? 0 : 4)
        width: tagText.implicitWidth + 18
        height: tagText.implicitHeight + 10
        radius: 8
        color: mt.colBorder
        antialiasing: true

        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Text {
            id: tagText
            anchors.centerIn: parent
            text: root.tip
            color: mt.textWhite
            font.family: mt.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: root.clicked()
    }
}
