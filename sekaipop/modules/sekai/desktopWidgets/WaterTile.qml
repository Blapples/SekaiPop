import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The Water Tank at 1 x 1 (a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with the
// housing): ONE rounded glass key that fills with water as you drink. It reads like a measuring
// glass: a tick for every glass of the goal runs down the right edge (so the glass is a glass
// even when it is empty), and the water rises behind them with an overshoot, like it sloshed.
//
// A slanted title tab (a droplet and WATER, the same tab the 2 x 2 has) sits upper left and a
// round + key upper right says what a press does. The glasses you have had are the big sticker
// numeral lower left, with "/ 8" (the goal) after it. At the goal the tab turns mint and says
// GOAL!, and the + becomes a check.
//
// A click (or the wheel up) adds a glass: the key squashes and springs back and a small puff of
// diamonds flies out. The wheel down takes one back. Reaching the goal throws a bigger burst. It
// sinks into its hard shadow while pressed, and tips a little when pointed at (until it is
// pressed; it straightens and stays straight until the pointer has left for a moment, the same
// rule as CalendarTile.qml).
//
//   WaterTile {
//       width: card.contentW; height: card.contentH
//       glasses: WaterTankService.glasses
//       goal: WaterTankService.goal
//       level: WaterTankService.level
//       done: WaterTankService.done
//       amountText: WaterTankService.amountText
//       hover: dragArea.containsMouse
//       pressed: dragArea.pressed
//   }
//   ... tile.pop() on a glass, tile.cheer() when the goal is reached.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property int glasses: 0
    property int goal: 8
    // 0..1: how full the tank is.
    property real level: 0
    property bool done: false
    property string amountText: ""
    property bool hover: false
    property bool pressed: false

    // The tip is for pointing, not for after a press (see CalendarTile.qml): once pressed, the key
    // stays straight until the pointer has really left, and `hover` flickering off and on while
    // the card is dragged does not count as leaving.
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

    readonly property bool tipped: root.hover && !root.pressed && !root.pressedSinceEnter

    // What the water shows: it eases to `level` with an overshoot (a plain property: QML refuses
    // a Behavior on a readonly one).
    property real shownLevel: root.level

    Behavior on shownLevel {
        NumberAnimation { duration: 820; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
    }

    // A glass was added: squash and a puff.
    function pop() {
        squish.restart()
        puff.fire()
    }

    // The goal was reached: the same, and a bigger burst.
    function cheer() {
        squish.restart()
        cheerBurst.fire()
    }

    // Two characters are the big size; "10" and up step down so they never run into the goal.
    readonly property string countText: String(root.glasses)
    readonly property int numSize: root.countText.length <= 1 ? 58 : 46

    // The sticker numerals' ink: a dark fill inside a white ring (as on the popups' plates).
    readonly property color numberFill: Qt.darker(mt.colBorder, 1.8)
    readonly property color numberRing: "#ffffff"

    TinyFoot {
        id: foot
        anchors.fill: parent

        Pill {
            id: key
            width: foot.capW
            height: foot.capH + foot.shadowDy
            cornerRadius: 30
            ringWidth: mt.borderWidth + mt.whiteLine
            pressed: root.pressed

            // The glass: paper at the top, a little colour toward the bottom.
            fillColor: mt.pSurface
            fillGradient: Gradient {
                GradientStop { position: 0.0; color: mt.pSurface }
                GradientStop { position: 1.0; color: Qt.tint(mt.pSurface, Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.18)) }
            }

            property real sx: 1
            property real sy: 1

            transformOrigin: Item.Center
            rotation: root.tipped ? -2 : 0

            Behavior on rotation {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            }

            transform: Scale {
                origin.x: key.width / 2
                origin.y: key.height / 2
                xScale: key.sx
                yScale: key.sy
            }

            // The water, clipped to the glass's rounded inside, with a tick per glass of the goal.
            WaterFill {
                anchors.fill: parent
                radius: key.cornerRadius - key.ringWidth
                level: root.shownLevel
                marks: root.goal
            }

            // The title tab, upper left: a droplet and WATER (a check and GOAL! at the goal).
            Slant {
                id: tab
                x: 8
                y: 9
                width: 90
                height: 26
                skew: 0.2
                radius: 9
                color: root.done ? mt.accentMint : mt.chipFill
                borderColor: mt.pLine
                borderWidth: 3
            }

            // Text goes NEXT to the Slant (a child would lean with it).
            Row {
                x: tab.x + tab.lean / 2 + 9
                y: tab.y
                height: tab.height
                spacing: 4

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.done ? "check_circle" : "water_drop"
                    fill: 0
                    size: 15
                    weight: 700
                    color: root.done ? mt.colBorder : (mt.dark ? mt.accentMint : mt.colBorder)
                    transformOrigin: Item.Center
                    rotation: root.tipped ? -14 : 0

                    Behavior on rotation {
                        NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.done ? "GOAL!" : "WATER"
                    color: root.done ? mt.colBorder : mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 1.4
                }
            }

            // The + key, upper right: what a press does (the whole key is the button).
            Pill {
                id: addChip
                width: 34
                height: 34 + 3
                x: parent.width - width - 10
                y: 8
                shadowDy: 3
                cornerRadius: 17
                ringWidth: mt.borderWidth + mt.whiteLine
                fillColor: mt.accentMint
                pressed: root.pressed

                MaterialIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    name: root.done ? "check" : "add"
                    size: 24
                    color: mt.colBorder
                    transformOrigin: Item.Center
                    rotation: root.tipped ? 90 : 0

                    Behavior on rotation {
                        NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }
                }
            }

            // The glasses you have had, lower left, over the water, with the goal after it.
            Item {
                id: group
                width: countNum.width + goalNum.width - 6
                height: countNum.height
                x: 6
                y: parent.height - group.height + 2

                StickerText {
                    id: countNum
                    text: root.countText
                    pixelSize: root.numSize
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }

                StickerText {
                    id: goalNum
                    x: countNum.width - 6
                    y: group.height - goalNum.height - 6
                    text: "/" + root.goal
                    pixelSize: 22
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }
            }
        }

        SequentialAnimation {
            id: squish
            ParallelAnimation {
                NumberAnimation { target: key; property: "sx"; to: 1.1; duration: 80; easing.type: Easing.OutQuad }
                NumberAnimation { target: key; property: "sy"; to: 0.9; duration: 80; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: key; property: "sx"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                NumberAnimation { target: key; property: "sy"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
            }
        }

        Burst {
            id: puff
            x: key.width / 2
            y: key.height / 2
            radius: 64
            count: 8
        }

        Burst {
            id: cheerBurst
            x: key.width / 2
            y: key.height / 2
            radius: 92
            count: 14
            size: 11
        }
    }
}
