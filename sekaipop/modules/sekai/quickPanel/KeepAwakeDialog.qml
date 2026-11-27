import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.phone

// The Keep Awake chooser that drops down over the phone's screen when you
// right-click the Keep Awake tile — same idea as BluetoothDialog.qml, three
// rows at most: this session only, until I turn it off, and (while it is on)
// turn off. The row for the current mode gets a check mark.
Item {
    id: root

    readonly property var mt: Theme.of(QsWindow.window)

    property bool open: false
    // "off" | "session" | "always"
    property string mode: "off"

    signal closeRequested()
    signal modeSelected(string mode)

    readonly property var choices: {
        const list = [
            { id: "session", title: "This session only", sub: "Forgotten when you log out or reboot" },
            { id: "always", title: "Until I turn it off", sub: "Stays on after a reboot" }
        ]
        if (root.mode !== "off")
            list.push({ id: "off", title: "Turn off", sub: "Let the screen and system idle again" })
        return list
    }

    readonly property real rowH: 78
    readonly property real rowGap: 12
    readonly property real cardH: 84 + choices.length * (rowH + rowGap) + 8

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.open ? 140 : 220
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: mt.phoneScreenInset
        radius: mt.phoneCornerRadius - mt.phoneScreenInset
        color: mt.scrim
        opacity: root.open ? 0.55 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
        antialiasing: true
    }

    Rectangle {
        x: 40 + (mt.quickFlat ? 0 : 5)
        y: 200 + 4
        width: 575
        height: root.cardH
        radius: 41
        color: mt.pLineShadow
        antialiasing: true
    }

    Rectangle {
        id: card
        x: 40
        y: 200
        width: 575
        height: root.cardH
        radius: 41
        color: mt.pSurface
        border.width: 3
        border.color: mt.pLine
        clip: true

        MouseArea { anchors.fill: parent }

        Text {
            x: 28
            y: 26
            text: "Keep Awake"
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 26
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Repeater {
            model: root.choices

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                x: 14
                y: 84 + index * (root.rowH + root.rowGap)
                width: card.width - 28
                height: root.rowH
                radius: 28
                color: rowArea.containsMouse ? mt.pSurfaceHover : "transparent"
                border.width: 2
                border.color: mt.pLine
                antialiasing: true

                Text {
                    x: 24
                    y: 14
                    text: row.modelData.title
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Text {
                    x: 24
                    y: 44
                    text: row.modelData.sub
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 14
                }

                Text {
                    visible: row.modelData.id === root.mode
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✓"
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 26
                    font.weight: Font.ExtraBold
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.modeSelected(row.modelData.id)
                        root.closeRequested()
                    }
                }
            }
        }
    }
}