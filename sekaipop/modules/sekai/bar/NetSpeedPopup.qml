import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/NetSpeedMath.js" as NSM

// The card that drops down from NetSpeedIndicator.qml, in the same family as the other bar popups
// (Resources, Screen time, Battery): the shared SekaiPopup frame and SekaiPlates with sticker
// numerals. Everything comes from NetSpeedService.qml (one reading for the whole shell), so
// Bar.qml only has to open it.
//
//   The plates    download and upload side by side, each a big sticker number and its unit
//                 ("1.2" "MB/s"); download wears the accent gradient, upload pink.
//   The chart     the last two minutes, one bar per reading: download rising from the middle line,
//                 upload hanging below it, the newest on the right. Each half is scaled to its
//                 own tallest bar (with a floor, so a quiet minute is not stretched), and the
//                 peaks are written under it.
//   The totals    how much has moved since the shell started.
//   The note      which interfaces are counted, and what is left out.
SekaiPopup {
    id: root

    readonly property int pad: 16
    readonly property int innerW: 304
    readonly property real halfW: (root.innerW - 10) / 2
    readonly property int bars: 60
    readonly property real barGap: 1
    readonly property real barW: (root.innerW - (root.bars - 1) * root.barGap) / root.bars
    readonly property int halfH: 36
    readonly property color upColor: "#FF9ECB"

    readonly property var downParts: NSM.speedParts(NetSpeedService.down)
    readonly property var upParts: NSM.speedParts(NetSpeedService.up)

    contentWidth: root.innerW + 2 * root.pad
    contentHeight: stack.implicitHeight + 2 * root.pad - 2

    // ===== the open choreography =====
    property real fillWave: 1

    NumberAnimation {
        id: fillAnim
        target: root
        property: "fillWave"
        from: 0
        to: 1
        duration: 650
        easing.type: Easing.OutCubic
    }

    onOpenChanged: {
        // Pressed again while the card was still going away: it turns round
        // instead of replaying the rise.
        if (open && root.reveal < 0.35)
            fillAnim.restart()
    }

    Column {
        id: stack
        x: root.pad
        y: root.pad - 2
        width: root.innerW
        spacing: 10

        // ===== the plates =====
        Row {
            width: root.innerW
            spacing: 10

            SekaiPlate {
                id: downPlate
                width: root.halfW
                height: 92

                Row {
                    x: 12
                    y: 10
                    spacing: 4

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow_downward"
                        fill: 0
                        size: 16
                        weight: 700
                        color: mt.colBorder
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "DOWN"
                        color: mt.colBorder
                        font.family: mt.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                        font.letterSpacing: 1.2
                    }
                }

                StickerText {
                    id: downNum
                    x: 6
                    y: 28
                    text: root.downParts.num
                    pixelSize: 38
                    fillColor: downPlate.numberFill
                    ringColor: downPlate.numberRing
                }
                StickerText {
                    x: downNum.x + downNum.width - 4
                    y: 46
                    text: root.downParts.unit
                    pixelSize: 15
                    fillColor: downPlate.numberFill
                    ringColor: downPlate.numberRing
                }
            }

            SekaiPlate {
                id: upPlate
                width: root.halfW
                height: 92
                colorTop: Qt.lighter(root.upColor, 1.12)
                colorBottom: root.upColor

                Row {
                    x: 12
                    y: 10
                    spacing: 4

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow_upward"
                        fill: 0
                        size: 16
                        weight: 700
                        color: mt.colBorder
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "UP"
                        color: mt.colBorder
                        font.family: mt.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                        font.letterSpacing: 1.2
                    }
                }

                StickerText {
                    id: upNum
                    x: 6
                    y: 28
                    text: root.upParts.num
                    pixelSize: 38
                    fillColor: upPlate.numberFill
                    ringColor: upPlate.numberRing
                }
                StickerText {
                    x: upNum.x + upNum.width - 4
                    y: 46
                    text: root.upParts.unit
                    pixelSize: 15
                    fillColor: upPlate.numberFill
                    ringColor: upPlate.numberRing
                }
            }
        }

        // ===== the chart =====
        SectionTab {
            text: "Last 2 minutes"
        }

        Item {
            id: chart
            width: root.innerW
            height: 2 * root.halfH + 3

            // Download: bars standing on the middle line.
            Row {
                id: downRow
                anchors.bottom: mid.top
                anchors.bottomMargin: 1
                spacing: root.barGap

                Repeater {
                    model: NetSpeedService.downFracs

                    Item {
                        required property real modelData
                        width: root.barW
                        height: root.halfH

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: modelData > 0 ? Math.max(2, root.halfH * modelData * root.fillWave) : 1
                            radius: Math.min(2, width / 2)
                            color: modelData > 0 ? mt.accentCyan : mt.chipFill
                            opacity: modelData > 0 ? 1 : 0.5
                        }
                    }
                }
            }

            Rectangle {
                id: mid
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: mt.inkSub
                opacity: 0.5
            }

            // Upload: bars hanging from it.
            Row {
                anchors.top: mid.bottom
                anchors.topMargin: 1
                spacing: root.barGap

                Repeater {
                    model: NetSpeedService.upFracs

                    Item {
                        required property real modelData
                        width: root.barW
                        height: root.halfH

                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width
                            height: modelData > 0 ? Math.max(2, root.halfH * modelData * root.fillWave) : 1
                            radius: Math.min(2, width / 2)
                            color: modelData > 0 ? root.upColor : mt.chipFill
                            opacity: modelData > 0 ? 1 : 0.5
                        }
                    }
                }
            }
        }

        Item {
            width: root.innerW
            height: peakDownText.implicitHeight

            Text {
                id: peakDownText
                anchors.left: parent.left
                text: "Peak ↓ " + NSM.speedLong(NetSpeedService.peakDown)
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
            Text {
                anchors.right: parent.right
                text: "Peak ↑ " + NSM.speedLong(NetSpeedService.peakUp)
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }
        }

        // ===== the totals =====
        SectionTab {
            text: "Since the shell started"
        }

        Row {
            width: root.innerW
            spacing: 10

            Row {
                width: root.halfW
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_downward"
                    size: 18
                    color: mt.ink
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: NSM.bytesText(NetSpeedService.totalDown)
                        color: mt.ink
                        font.family: mt.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }
                    Text {
                        text: "downloaded"
                        color: mt.inkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            Row {
                width: root.halfW
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_upward"
                    size: 18
                    color: mt.ink
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: NSM.bytesText(NetSpeedService.totalUp)
                        color: mt.ink
                        font.family: mt.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }
                    Text {
                        text: "uploaded"
                        color: mt.inkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ===== the note =====
        Text {
            width: root.innerW
            text: (NetSpeedService.ifaces.length > 0 ? "Counting " + NetSpeedService.ifaces.join(", ") + ". " : "")
                + "Loopback, containers, virtual machines and VPN tunnels are left out."
            wrapMode: Text.WordWrap
            color: mt.inkSub
            font.family: mt.fontFamily
            font.pixelSize: 10
        }
    }
}
