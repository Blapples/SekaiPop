import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// A small capsule that pops up over the page for a moment, in the shell's card look: the
// reading mode when a chapter opens or the mode changes, "Saved p. 12", the chapter that
// just opened. It lies on the page, so it takes no clicks.
//
//   toast.show("book", "Tablet \u00b7 right to left", "\u2190 / A next \u00b7 \u2192 / D back")
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string sub: ""
    // How long it stays, ms.
    property int hold: 2300

    property bool shown: false

    implicitWidth: card.width
    implicitHeight: card.height
    width: implicitWidth
    height: implicitHeight

    function show(icon, title, sub) {
        root.icon = icon || ""
        root.title = title || ""
        root.sub = sub || ""
        root.shown = true
        hideTimer.restart()
    }

    function hide() {
        hideTimer.stop()
        root.shown = false
    }

    opacity: root.shown ? 1 : 0
    visible: root.opacity > 0.01
    scale: root.shown ? 1 : 0.92
    enabled: false

    Behavior on opacity { NumberAnimation { duration: root.shown ? 160 : 320; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

    Timer {
        id: hideTimer
        interval: root.hold
        onTriggered: root.shown = false
    }

    Pill {
        id: card

        width: Math.max(150, row.implicitWidth + 36)
        height: 52 + Theme.shadowOffset
        cornerRadius: 20
        ringWidth: Theme.borderWidth
        innerRing: Theme.cardRing
        fillColor: Theme.surface

        Row {
            id: row
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Theme.shadowOffset / 2
            spacing: 11

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon.length > 0
                name: root.icon
                size: 22
                weight: 600
                color: Theme.ink
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: root.title
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                Text {
                    visible: root.sub.length > 0
                    text: root.sub
                    color: Theme.inkSub
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }
        }
    }
}
