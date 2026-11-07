import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../dock"

// The card that drops down from TimerIndicator.qml: Timer, Stopwatch and Pomodoro on one card,
// the same three the dock's Timer key has (DockTimerCard.qml), in the bar popups' shared frame
// (SekaiPopup.qml). The clocks live in services/TimerService.qml, so they run whether this card
// or the dock's is open or neither, and the two always agree. It uses the dock's buttons
// (DockButton.qml).
SekaiPopup {
    id: root

    readonly property int pad: 16
    readonly property int bodyW: 330

    // timer | stopwatch | pomodoro
    property string tab: "timer"

    // Opens on what is already running.
    onOpenChanged: {
        if (open && TimerService.shownMode !== "")
            root.tab = TimerService.shownMode
    }

    contentWidth: root.bodyW + 2 * root.pad
    contentHeight: 46 + 190 + 2 * root.pad - 8

    // ---- tabs ----
    Row {
        id: tabs
        x: root.pad
        y: root.pad
        spacing: 8

        Repeater {
            model: [
                { id: "timer", label: "Timer", icon: "timer" },
                { id: "stopwatch", label: "Stopwatch", icon: "av_timer" },
                { id: "pomodoro", label: "Pomodoro", icon: "nutrition" }
            ]

            delegate: DockButton {
                required property var modelData
                height: 34
                icon: modelData.icon
                label: modelData.label
                fontSize: 13
                iconSize: 18
                selected: root.tab === modelData.id
                onClicked: root.tab = modelData.id
            }
        }
    }

    // ---- Timer ----
    Item {
        visible: root.tab === "timer"
        x: root.pad
        y: root.pad + 46
        width: root.bodyW
        height: 190

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: TimerService.clock(TimerService.timerLeft, false)
            color: TimerService.timerRunning ? mt.ink : mt.inkSub
            font.family: mt.fontFamily
            font.pixelSize: 52
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 68
            spacing: 6

            Repeater {
                model: [1, 5, 10, 15, 25, 45]

                delegate: DockButton {
                    required property int modelData
                    height: 30
                    label: modelData + "m"
                    fontSize: 13
                    selected: Math.round(TimerService.timerTotal) === modelData * 60
                    opacity: TimerService.timerRunning ? 0.5 : 1
                    onClicked: TimerService.setTimerMinutes(modelData)
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 118
            spacing: 10

            DockButton {
                accent: true
                icon: TimerService.timerRunning ? "pause" : "play_arrow"
                label: TimerService.timerRunning ? "Pause" : "Start"
                onClicked: TimerService.toggleTimer()
            }

            DockButton {
                icon: "add"
                label: "1 min"
                onClicked: TimerService.addTimerMinute()
            }

            DockButton {
                icon: "restart_alt"
                onClicked: TimerService.resetTimer()
            }
        }
    }

    // ---- Stopwatch ----
    Item {
        visible: root.tab === "stopwatch"
        x: root.pad
        y: root.pad + 46
        width: root.bodyW
        height: 190

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: TimerService.clock(TimerService.swElapsed, true)
            color: TimerService.swRunning ? mt.ink : mt.inkSub
            font.family: mt.fontFamily
            font.pixelSize: 52
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 68
            spacing: 10

            DockButton {
                accent: true
                icon: TimerService.swRunning ? "pause" : "play_arrow"
                label: TimerService.swRunning ? "Pause" : "Start"
                onClicked: TimerService.toggleStopwatch()
            }

            DockButton {
                icon: "flag"
                label: "Lap"
                onClicked: TimerService.lapStopwatch()
            }

            DockButton {
                icon: "restart_alt"
                onClicked: TimerService.resetStopwatch()
            }
        }

        // The last three laps, newest first.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 116
            spacing: 2

            Repeater {
                model: TimerService.laps.slice(0, 3)

                delegate: Text {
                    required property int index
                    required property real modelData
                    text: "Lap " + (TimerService.laps.length - index) + "   " + TimerService.clock(modelData, true)
                    color: mt.inkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
            }
        }
    }

    // ---- Pomodoro ----
    Item {
        visible: root.tab === "pomodoro"
        x: root.pad
        y: root.pad + 46
        width: root.bodyW
        height: 190

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: TimerService.phaseLabel
                color: TimerService.pomPhase === "focus" ? mt.ink : mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 15
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }

            // One diamond per focus round: filled for the ones done, ringed for this one.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Repeater {
                    model: TimerService.pomRounds

                    delegate: Rectangle {
                        required property int index
                        width: 10
                        height: 10
                        radius: 3
                        rotation: 45
                        color: index + 1 < TimerService.pomRound
                            || (index + 1 === TimerService.pomRound && TimerService.pomPhase !== "focus")
                            ? mt.accentMint : "transparent"
                        border.width: 2
                        border.color: index + 1 === TimerService.pomRound ? mt.accentCyan : mt.line
                    }
                }
            }
        }

        Text {
            y: 24
            anchors.horizontalCenter: parent.horizontalCenter
            text: TimerService.clock(TimerService.pomLeft, false)
            color: TimerService.pomRunning ? mt.ink : mt.inkSub
            font.family: mt.fontFamily
            font.pixelSize: 52
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 98
            spacing: 10

            DockButton {
                accent: true
                icon: TimerService.pomRunning ? "pause" : "play_arrow"
                label: TimerService.pomRunning ? "Pause" : "Start"
                onClicked: TimerService.togglePomodoro()
            }

            DockButton {
                icon: "skip_next"
                label: "Skip"
                onClicked: TimerService.nextPhase(TimerService.pomRunning)
            }

            DockButton {
                icon: "restart_alt"
                onClicked: TimerService.resetPomodoro()
            }
        }

        Text {
            y: 148
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: Math.round(TimerService.pomWorkMin) + " min focus · " + Math.round(TimerService.pomShortMin)
                + " short · " + Math.round(TimerService.pomLongMin) + " long"
            color: mt.inkSub
            font.family: mt.fontFamily
            font.pixelSize: 12
            font.weight: Font.Bold
        }
    }
}
