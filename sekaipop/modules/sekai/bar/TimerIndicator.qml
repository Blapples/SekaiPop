import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The timer pill in the bar. With nothing running it is just the icon (a small pill that opens
// the card); while a timer, stopwatch or pomodoro runs it adds the clock ("24:13"). Pure UI:
// Status_Bar.qml feeds it from TimerService.qml (via Bar.qml). A click opens TimerPopup.qml.
//
// The clock sits in a box as wide as the widest it can get ("00:00", or "0:00:00" from an hour
// up), so the pills beside it do not move as the digits change. The pill does get wider once when
// something starts and narrower when it stops: that is a thing you did, not the digits.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // "" (nothing running) | timer | stopwatch | pomodoro
    property string mode: ""

    // The clock as written: "24:13" / "1:23:45". "" when nothing runs.
    property string text: ""

    // The widest the clock can get ("00:00" / "0:00:00").
    property string sizeText: "00:00"

    // True on a standing bar (left / right edge): the icon over the clock, split on the colons.
    property bool vertical: false

    // Which edge the bar is on, so the hover tag opens towards the screen.
    property string barPosition: "top"

    // What the hover tag says (TimerService.shownTip).
    property string tipText: ""

    signal clicked()

    readonly property bool running: root.mode !== ""

    // The icon says which of the three is running.
    readonly property string glyphName: root.mode === "stopwatch" ? "av_timer"
        : (root.mode === "pomodoro" ? "nutrition" : "timer")

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Two hidden copies of the widest clock, in 0s and in 8s (the widest digit in most fonts);
    // the wider of the two is the room the figures get.
    Text {
        id: probeZero
        visible: false
        text: root.sizeText.replace(/\d/g, "0")
        font.family: mt.fontFamily
        font.pixelSize: mt.fontSizeInfo
        font.weight: Font.ExtraBold
        font.styleName: mt.fontStyleBold
    }
    Text {
        id: probeEight
        visible: false
        text: root.sizeText.replace(/\d/g, "8")
        font.family: mt.fontFamily
        font.pixelSize: mt.fontSizeInfo
        font.weight: Font.ExtraBold
        font.styleName: mt.fontStyleBold
    }
    readonly property real figuresWidth: Math.ceil(Math.max(probeZero.implicitWidth, probeEight.implicitWidth))

    Pill {
        id: pill
        anchors.fill: parent
        cornerRadius: mt.radiusBadge
        fillColor: root.running ? mt.accentMint : mt.chipFill
        pressed: area.pressed
        ringWidth: 6   // the bar's pills all share the Utility pill's ring
        implicitWidth: root.vertical ? pill.barVWidth
            : (root.running ? glyph.width + root.figuresWidth + (pill.capsule ? 26 : 34)
                            : glyph.width + (pill.capsule ? 20 : 24))
        implicitHeight: root.vertical
            ? vcol.implicitHeight + (pill.capsule ? 4 : 2 * ringWidth) + 8 + mt.shadowOffset
            : mt.pillHeight + mt.shadowOffset

        Column {
            id: vcol
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 1

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.glyphName
                size: 22
                color: root.running ? mt.colBorder : mt.chipInk
            }

            Text {
                visible: root.running
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.text.split(":").join("\n")
                color: mt.colBorder
                font.family: mt.fontFamily
                font.pixelSize: mt.fontSizeInfo
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        MaterialIcon {
            id: glyph
            visible: !root.vertical
            name: root.glyphName
            size: 22
            color: root.running ? mt.colBorder : mt.chipInk
            x: root.running ? 10 : (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: label
            visible: !root.vertical && root.running
            anchors.left: glyph.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            // A fixed box, the digits centred in it: they can change without the pill growing.
            width: root.figuresWidth
            horizontalAlignment: Text.AlignHCenter
            text: root.text
            color: mt.colBorder
            font.family: mt.fontFamily
            font.pixelSize: mt.fontSizeInfo
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }
    }

    // A sibling of the Pill (not inside it) so the hit area doesn't
    // move with the pressed cap — same as the date and clock buttons.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // The hover tag (BarTip.qml): what the card behind the click holds, at a glance.
    BarTip {
        shown: area.containsMouse
        pressed: area.pressed
        text: root.tipText
        barPosition: root.barPosition
    }
}
