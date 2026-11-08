import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The calendar card at 1 x 1 (a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with the
// housing): today's date as ONE object, a page torn off a desk calendar. A mint header with
// two punched holes carries the weekday and the month, so the page reads as a page on any
// palette; the date is a big sticker numeral on the paper under it, and a row of seven small
// dots along the foot is the week, with today lit. Nothing else.
//
// It is a button like the rest of the shell's: it sinks into its hard shadow while pressed,
// and tips a little when pointed at (until it is pressed; it straightens and stays straight until the pointer has left for a moment). It turns the page by itself at midnight (`today`
// follows the card's clock, and the numeral hops when it changes).
//
//   CalendarTile {
//       width: card.contentW; height: card.contentH
//       today: win.today
//       hover: dragArea.containsMouse
//       pressed: dragArea.pressed
//   }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property date today: new Date()
    property bool hover: false
    property bool pressed: false

    // The tip is for pointing, not for after a press: once pressed, the page stays straight until
    // the pointer has really left (a click or a drag used to leave it tilted under the pointer).
    // "Really left" = out of the card for a moment (leaveWait), and never while a button is down:
    // dragging the card moves it under the pointer, which lags a frame behind, so `hover` flickers
    // off and on during a drag (and the window can re-map after a drop). Resetting on that flicker
    // is what put the tilt back right after the press.
    property bool pressedSinceEnter: false
    readonly property int leaveWait: 400

    onPressedChanged: {
        if (root.pressed) {
            root.pressedSinceEnter = true
            leaveTimer.stop()
        } else if (!root.hover) {
            leaveTimer.restart()
        }
    }
    onHoverChanged: {
        if (root.hover)
            leaveTimer.stop()
        else if (!root.pressed)
            leaveTimer.restart()
    }

    Timer {
        id: leaveTimer
        interval: root.leaveWait
        onTriggered: {
            if (!root.hover && !root.pressed)
                root.pressedSinceEnter = false
        }
    }

    readonly property string dayText: String(root.today.getDate())
    readonly property int weekday: root.today.getDay()
    readonly property string weekdayText: Qt.locale().dayName(root.today.getDay(), Locale.ShortFormat).toUpperCase()
    readonly property string monthText: Qt.locale().monthName(root.today.getMonth(), Locale.ShortFormat).toUpperCase()

    // The sticker numerals' ink: a dark fill inside a white ring (as on the popups' plates).
    readonly property color numberFill: Qt.darker(mt.colBorder, 1.8)
    readonly property color numberRing: "#ffffff"

    TinyFoot {
        id: foot
        anchors.fill: parent

        Pill {
            id: page
            width: foot.capW
            height: foot.capH + foot.shadowDy
            cornerRadius: 24
            ringWidth: mt.borderWidth + mt.whiteLine
            pressed: root.pressed

            transformOrigin: Item.Center
            rotation: root.hover && !root.pressed && !root.pressedSinceEnter ? -2 : 0

            Behavior on rotation {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            }

            // The header: rounded at the top (the paper's own corners), square at the foot.
            Rectangle {
                id: band
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36
                radius: parent.radius
                color: mt.accentMint
                antialiasing: true
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: band.radius
                height: band.height - band.radius
                color: mt.accentMint
            }

            // A thin edge under the header, so the paper and the header are two things.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: band.height - 2
                height: 2
                color: Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.35)
            }

            // The two holes the page hangs on.
            Repeater {
                model: 2

                Rectangle {
                    required property int index

                    width: 9
                    height: 9
                    radius: 4.5
                    x: index === 0 ? 15 : band.width - 15 - width
                    y: (band.height - height) / 2
                    color: page.fillColor
                    antialiasing: true
                }
            }

            // The legend: weekday, a diamond, month.
            Row {
                anchors.horizontalCenter: band.horizontalCenter
                y: (band.height - height) / 2
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.weekdayText
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 1.8
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 1.5
                    rotation: 45
                    color: mt.colBorder
                    antialiasing: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.monthText
                    color: mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 1.8
                }
            }

            // The date, on the paper, between the header and the week.
            StickerText {
                id: dateNum
                text: root.dayText
                pixelSize: root.dayText.length === 1 ? 56 : 50
                fillColor: root.numberFill
                ringColor: root.numberRing
                x: (parent.width - dateNum.width) / 2
                y: band.height + (weekDots.y - band.height - dateNum.height) / 2 + 2
            }

            // The week, along the foot: seven dots, today's is bigger and lit.
            Row {
                id: weekDots
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 12 - 9
                height: 12
                spacing: 8

                Repeater {
                    model: 7

                    Item {
                        id: dot
                        required property int index
                        readonly property bool isToday: dot.index === root.weekday

                        width: 10
                        height: 12

                        Rectangle {
                            anchors.centerIn: parent
                            width: dot.isToday ? 10 : 6
                            height: width
                            radius: width / 2
                            color: dot.isToday ? mt.accentMint : Qt.rgba(mt.pInk.r, mt.pInk.g, mt.pInk.b, 0.3)
                            border.width: dot.isToday ? 2 : 0
                            border.color: mt.pInk
                            antialiasing: true
                        }
                    }
                }
            }
        }
    }
}
