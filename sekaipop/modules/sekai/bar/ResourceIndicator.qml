import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LoadGlyphs.js" as LG

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

    // What the hover tag says.
    readonly property string tipText: "CPU " + Math.round(root.cpuPercent) + "% · RAM " + Math.round(root.memPercent) + "%"

    signal clicked()

    // True once either figure is running hot enough to flag — used to
    // tint the glyph instead of adding a third color nobody asked for.
    readonly property bool cpuHot: cpuPercent >= 90
    readonly property bool memHot: memPercent >= 90

    // CPU is the chip, RAM the pie that fills with it (LoadGlyphs.js, issue #168).
    readonly property string cpuGlyphName: LG.cpu()
    readonly property string memGlyphName: LG.ram(root.memPercent)

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
