import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/ScreenTimeMath.js" as STM

// The card that drops down from ScreenTimeIndicator.qml, in the same family as the other bar
// popups (Resources, Battery, Weather): the shared SekaiPopup frame and a SekaiPlate with sticker
// numerals. Everything it shows comes from ScreenTimeService.qml (one count for the whole shell),
// so Bar.qml only has to open it; the frame, focus grab, pop-in and swallow come from SekaiPopup.qml.
//
//   The plate     today's screen time as big sticker numerals, "3h 12m", with the average of
//                 the days before on its right.
//   The week      the last seven days as bars, today's in the accent colour; they rise when the
//                 card opens.
//   The apps      where today went: up to five apps, longest first, each with its icon, its time
//                 and a bar against the longest.
//   The note      what counts (time at the screen: not locked, not idle).
SekaiPopup {
    id: root

    readonly property int pad: 16
    readonly property int innerW: 304
    readonly property int chartH: 64
    readonly property int maxApps: 5

    readonly property var parts: STM.parts(ScreenTimeService.total)
    readonly property var apps: ScreenTimeService.topToday.slice(0, root.maxApps)
    readonly property real topSecs: root.apps.length > 0 ? root.apps[0].secs : 1

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

        // ===== the plate =====
        SekaiPlate {
            id: plate
            width: root.innerW
            height: 100

            Row {
                x: 14
                y: 11
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "hourglass"
                    fill: 0
                    size: 18
                    weight: 600
                    color: mt.colBorder
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SCREEN TIME"
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 1.2
                }
            }

            // Hours (only once there is one), then minutes, each with a small unit on its baseline.
            StickerText {
                id: hoursNum
                visible: root.parts.h > 0
                x: 6
                y: 28
                text: String(root.parts.h)
                pixelSize: 44
                fillColor: plate.numberFill
                ringColor: plate.numberRing
            }

            StickerText {
                id: hoursUnit
                visible: root.parts.h > 0
                x: hoursNum.x + hoursNum.width - 6
                y: 48
                text: "h"
                pixelSize: 18
                fillColor: plate.numberFill
                ringColor: plate.numberRing
            }

            StickerText {
                id: minutesNum
                x: root.parts.h > 0 ? hoursUnit.x + hoursUnit.width + 4 : 6
                y: 28
                text: String(root.parts.m)
                pixelSize: 44
                fillColor: plate.numberFill
                ringColor: plate.numberRing
            }

            StickerText {
                x: minutesNum.x + minutesNum.width - 6
                y: 48
                text: "m"
                pixelSize: 18
                fillColor: plate.numberFill
                ringColor: plate.numberRing
            }

            // The days before, for scale.
            Column {
                visible: ScreenTimeService.average > 0
                anchors.right: parent.right
                anchors.rightMargin: 16
                y: 14
                spacing: 1

                Text {
                    anchors.right: parent.right
                    text: STM.shortText(ScreenTimeService.average)
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
                Text {
                    anchors.right: parent.right
                    text: "daily average"
                    color: mt.colBorder
                    opacity: 0.7
                    font.family: mt.fontFamily
                    font.pixelSize: 10
                }
            }
        }

        // ===== the week =====
        SectionTab {
            text: "Last 7 days"
        }

        Item {
            id: week
            width: root.innerW
            height: root.chartH + 22

            Row {
                anchors.fill: parent
                spacing: 8

                Repeater {
                    model: ScreenTimeService.bars

                    Item {
                        id: col
                        required property var modelData
                        width: (root.innerW - 6 * 8) / 7
                        height: week.height

                        // The bar rises from the baseline; today's is the accent colour.
                        Rectangle {
                            id: bar
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: dayLabel.top
                            anchors.bottomMargin: 4
                            width: parent.width
                            height: col.modelData.secs > 0 ? Math.max(6, root.chartH * col.modelData.frac * root.fillWave) : 4
                            radius: 6
                            color: col.modelData.today ? mt.accentMint : mt.chipFill
                            border.width: mt.borderWidth
                            border.color: mt.colBorder
                            opacity: col.modelData.secs > 0 ? 1 : 0.45
                        }

                        Text {
                            id: dayLabel
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: Qt.locale().dayName(col.modelData.weekday, Locale.ShortFormat)
                            color: col.modelData.today ? mt.ink : mt.inkSub
                            font.family: mt.fontFamily
                            font.pixelSize: 10
                            font.weight: col.modelData.today ? Font.ExtraBold : Font.Normal
                            font.styleName: col.modelData.today ? mt.fontStyleBold : ""
                        }

                        MouseArea {
                            id: barHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        // The day's total, when the pointer rests on its bar.
                        Text {
                            visible: barHover.containsMouse && col.modelData.secs > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: bar.top
                            anchors.bottomMargin: 2
                            text: STM.shortText(col.modelData.secs)
                            color: mt.ink
                            font.family: mt.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }
                    }
                }
            }
        }

        // ===== the apps =====
        SectionTab {
            text: "Today's apps"
        }

        Column {
            width: root.innerW
            spacing: 8

            Repeater {
                model: root.apps

                Item {
                    id: row
                    required property var modelData
                    width: root.innerW
                    height: 32

                    readonly property string iconUrl: ScreenTimeService.iconFor(row.modelData.key)
                    readonly property string name: ScreenTimeService.displayName(row.modelData.key)

                    // The app's icon, or its first letter on a chip when it has none.
                    Item {
                        id: iconBox
                        width: 26
                        height: 26
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            id: appIcon
                            anchors.fill: parent
                            source: row.iconUrl
                            sourceSize.width: 52
                            sourceSize.height: 52
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: status === Image.Ready
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !appIcon.visible
                            radius: 8
                            color: mt.chipFill
                            border.width: mt.borderWidth
                            border.color: mt.colBorder

                            Text {
                                anchors.centerIn: parent
                                text: row.name.charAt(0).toUpperCase()
                                color: mt.chipInk
                                font.family: mt.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }
                        }
                    }

                    Text {
                        id: nameText
                        anchors.left: iconBox.right
                        anchors.leftMargin: 10
                        anchors.right: timeText.left
                        anchors.rightMargin: 8
                        y: 2
                        text: row.name
                        elide: Text.ElideRight
                        color: mt.ink
                        font.family: mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }

                    Text {
                        id: timeText
                        anchors.right: parent.right
                        y: 2
                        text: STM.shortText(row.modelData.secs)
                        color: mt.inkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }

                    // The app's share of the longest one.
                    Rectangle {
                        anchors.left: nameText.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        height: 6
                        radius: 3
                        color: mt.chipFill
                        opacity: 0.6

                        Rectangle {
                            height: parent.height
                            width: parent.width * Math.min(1, row.modelData.secs / root.topSecs) * root.fillWave
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: mt.accentMint }
                                GradientStop { position: 1.0; color: mt.accentCyan }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.apps.length === 0
                width: root.innerW
                text: "Nothing counted yet today."
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 12
            }
        }

        // ===== the note =====
        Text {
            width: root.innerW
            text: "Counts the time you're at the screen: not locked, not idle. Starts again at midnight."
            wrapMode: Text.WordWrap
            color: mt.inkSub
            font.family: mt.fontFamily
            font.pixelSize: 10
        }
    }
}
