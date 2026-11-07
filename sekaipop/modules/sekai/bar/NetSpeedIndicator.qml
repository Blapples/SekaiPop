import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The network speed pill in the bar: an arrow down and the download speed, an arrow up and the
// upload speed, in KB/s ("↓ 1200  ↑ 45  KB/s"). Pure UI: Status_Bar.qml feeds it the two texts from
// NetSpeedService.qml (via Bar.qml). A click opens NetSpeedPopup.qml.
//
// Each speed is a plain number of KB/s (NetSpeedMath.kbText) and sits in a box as wide as the
// widest it normally gets (four digits), so the pill never changes width and the pills beside it
// stay put. One small "KB/s" label names the unit for both. An arrow dims while its direction is quiet.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // KB/s as a plain number: "1200" / "45" / "0"
    property string downText: "0"
    property string upText: "0"

    // The widest a speed normally reads ("0000"), for the boxes to measure.
    property string sizeText: "0000"

    // True on a standing bar (left / right edge): download over upload, each an arrow over its speed.
    property bool vertical: false

    // Which edge the bar is on, so the hover tag opens towards the screen.
    property string barPosition: "top"

    // What the hover tag says (NetSpeedService.tipText).
    property string tipText: ""

    signal clicked()

    readonly property bool downQuiet: root.downText === "0"
    readonly property bool upQuiet: root.upText === "0"

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // The widest speed, measured in 0s and in 8s (the widest digit in most fonts).
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
        implicitWidth: root.vertical ? pill.barVWidth : row.implicitWidth + (pill.capsule ? 20 : 24)
        implicitHeight: root.vertical
            ? vcol.implicitHeight + (pill.capsule ? 4 : 2 * ringWidth) + 12 + mt.shadowOffset
            : mt.pillHeight + mt.shadowOffset

        // Standing bar version: download, then upload, each an arrow over its speed.
        Column {
            id: vcol
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 6

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1
                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "arrow_downward"
                    size: 18
                    color: mt.chipInk
                    opacity: root.downQuiet ? 0.45 : 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.downText
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1
                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "arrow_upward"
                    size: 18
                    color: mt.chipInk
                    opacity: root.upQuiet ? 0.45 : 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.upText
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            // The unit, once, for both speeds.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "KB/s"
                color: mt.chipInk
                opacity: 0.6
                font.family: mt.fontFamily
                font.pixelSize: mt.fontSizeInfo - 3
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        Row {
            id: row
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 6

            Row {
                spacing: 2
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_downward"
                    size: 18
                    color: mt.chipInk
                    opacity: root.downQuiet ? 0.45 : 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.figuresWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.downText
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            Row {
                spacing: 2
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_upward"
                    size: 18
                    color: mt.chipInk
                    opacity: root.upQuiet ? 0.45 : 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.figuresWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.upText
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            // The unit, once, for both speeds.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "KB/s"
                color: mt.chipInk
                opacity: 0.6
                font.family: mt.fontFamily
                font.pixelSize: mt.fontSizeInfo - 3
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
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

    // The hover tag (BarTip.qml): the two speeds in full.
    BarTip {
        shown: area.containsMouse
        pressed: area.pressed
        text: root.tipText
        barPosition: root.barPosition
    }
}
