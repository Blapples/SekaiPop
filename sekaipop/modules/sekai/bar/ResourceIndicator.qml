import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Pure UI (no Quickshell imports): Status_Bar.qml feeds this the two
// numbers from ResourceSource.qml. Two small badges — CPU and RAM,
// same "icon + text" shape as BatteryIndicator.qml — sitting inside
// one Pill so they read as one widget rather than two separate ones.
// Click opens ResourcePopup.qml with the fuller breakdown.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property real cpuPercent: 0
    property real memPercent: 0
    property string memUsedLabel: "--"
    property string memTotalLabel: "--"

    // True on a standing bar (left / right edge): the two figures stack,
    // each one an icon over its number.
    property bool vertical: false

    // Which edge the bar is on, so the hover tag opens towards the screen.
    property string barPosition: "top"

    // The CPU temperature ("62°C", "" when this machine has no sensor we can read), added to the tag.
    property string tempText: ""

    // What the hover tag says.
    readonly property string tipText: "CPU " + Math.round(root.cpuPercent) + "% · RAM " + Math.round(root.memPercent) + "%"
        + (root.tempText !== "" ? " · " + root.tempText : "")

    // Both figures sit in a box as wide as the widest they can read ("100%"), so the pill never
    // changes width as the numbers change and the pills beside it stay put. Measured in 0s and in
    // 8s (the widest digit in most fonts).
    Text {
        id: probeZero
        visible: false
        text: "000%"
        font.family: mt.fontFamily
        font.pixelSize: mt.fontSizeInfo
        font.weight: Font.ExtraBold
        font.styleName: mt.fontStyleBold
    }
    Text {
        id: probeEight
        visible: false
        text: "888%"
        font.family: mt.fontFamily
        font.pixelSize: mt.fontSizeInfo
        font.weight: Font.ExtraBold
        font.styleName: mt.fontStyleBold
    }
    readonly property real figuresWidth: Math.ceil(Math.max(probeZero.implicitWidth, probeEight.implicitWidth))

    signal clicked()

    // True once either figure is running hot enough to flag — used to
    // tint the glyph instead of adding a third color nobody asked for.
    readonly property bool cpuHot: cpuPercent >= 90
    readonly property bool memHot: memPercent >= 90

    // CPU glyph: Material Symbols Rounded only ships the "clock_loader"
    // pie-timer glyph in these six steps, so cpuPercent snaps to
    // whichever is closest (midpoints at 15/30/50/70/85) rather than
    // an even split like Battery's frame_1..frame_6.
    readonly property string cpuGlyphName: {
        var p = root.cpuPercent
        if (p < 15) return "clock_loader_10"
        if (p < 30) return "clock_loader_20"
        if (p < 50) return "clock_loader_40"
        if (p < 70) return "clock_loader_60"
        if (p < 85) return "clock_loader_80"
        return "clock_loader_90"
    }

    // RAM has no percent-stepped glyph in the set, so it's the one
    // fixed "memory" icon regardless of memPercent.
    readonly property string memGlyphName: "memory"

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    Pill {
        id: pill
        anchors.fill: parent
        cornerRadius: mt.radiusBadge
        fillColor: mt.chipFill
        pressed: area.pressed
        ringWidth: 6   // the bar's pills all share the Utility pill's ring (it was 8 when lying flat)
        implicitWidth: root.vertical ? pill.barVWidth : row.implicitWidth + (pill.capsule ? 20 : 24)
        implicitHeight: root.vertical
            ? vcol.implicitHeight + (pill.capsule ? 4 : 2 * ringWidth) + 12 + mt.shadowOffset
            : mt.pillHeight + mt.shadowOffset

        // Standing bar version: CPU, then RAM, each an icon over its number.
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
                    name: root.cpuGlyphName
                    size: 18
                    color: root.cpuHot ? "#e0575b" : mt.chipInk
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.cpuPercent + "%"
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
                    name: root.memGlyphName
                    size: 18
                    color: root.memHot ? "#e0575b" : mt.chipInk
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.memPercent + "%"
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }
        }

        RowLayout {
            id: row
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 10

            RowLayout {
                spacing: 5
                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: root.cpuGlyphName
                    size: 18
                    color: root.cpuHot ? "#e0575b" : mt.chipInk
                }
                Text {
                    Layout.preferredWidth: root.figuresWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.cpuPercent + "%"
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }

            RowLayout {
                spacing: 5
                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: root.memGlyphName
                    size: 18
                    color: root.memHot ? "#e0575b" : mt.chipInk
                }
                Text {
                    Layout.preferredWidth: root.figuresWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.memPercent + "%"
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
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

    // The hover tag (BarTip.qml): what the popup behind the click would tell you, at a glance.
    BarTip {
        shown: area.containsMouse
        pressed: area.pressed
        text: root.tipText
        barPosition: root.barPosition
    }
}
