import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The screen time pill in the bar: an hourglass and how long the screen has been in use today
// ("3h 12m"). Pure UI (no Quickshell imports beyond the theme): Status_Bar.qml feeds it the text
// from ScreenTimeService.qml (via Bar.qml). Same pill shape as Weather / Date, and it presses
// like a physical button: a click opens ScreenTimePopup.qml, a right-click changes how the time
// is written.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // "3h 12m" / "42m" / "03:12" / "03:12:45" (ScreenTimeService.pillText)
    property string text: "0m"

    // True on a standing bar (left / right edge): the icon over the figures, hours and minutes
    // on two lines.
    property bool vertical: false

    // The widest text the format can show ("00h 00m", "00:00", "00:00:00"). The pill is as wide
    // as that and no wider, whatever the digits say, so the pills beside it never shift.
    property string sizeText: "00h 00m"

    // Which edge the bar is on, so the hover tag opens towards the screen.
    property string barPosition: "top"

    // What the hover tag says (ScreenTimeService.tipText).
    property string tipText: ""

    signal clicked()
    // Right-click: the next way of writing the time.
    signal formatRequested()

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Two hidden copies of the widest text, one in 0s and one in 8s (the widest digit in most
    // fonts); the wider of the two is the room the figures get.
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
        fillColor: mt.chipFill
        pressed: area.pressed
        ringWidth: 6   // the bar's pills all share the Utility pill's ring
        implicitWidth: root.vertical ? pill.barVWidth : glyph.width + root.figuresWidth + (pill.capsule ? 26 : 34)
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
                name: "hourglass"
                size: 22
                color: mt.chipInk
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.text.split(/[ :]/).join("\n")
                color: mt.chipInk
                font.family: mt.fontFamily
                font.pixelSize: mt.fontSizeInfo
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        MaterialIcon {
            id: glyph
            visible: !root.vertical
            name: "hourglass"
            size: 22
            color: mt.chipInk
            x: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: label
            visible: !root.vertical
            anchors.left: glyph.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            // A fixed box, the digits centred in it: they can change without the pill growing.
            width: root.figuresWidth
            horizontalAlignment: Text.AlignHCenter
            text: root.text
            color: mt.chipInk
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.formatRequested()
            else
                root.clicked()
        }
    }

    // The hover tag (BarTip.qml): what the popup behind the click would tell you, at a glance.
    BarTip {
        shown: area.containsMouse
        pressed: area.pressed
        text: root.tipText
        barPosition: root.barPosition
    }
}
