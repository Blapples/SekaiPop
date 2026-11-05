import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The dock's Timer key (Dock.qml): Timer, Stopwatch and Pomodoro on one card. The
// clocks themselves live in services/TimerService.qml, so they keep running when the card
// is closed (the key then shows the time left).
DockCard {
    id: root

    // timer | stopwatch | pomodoro
    property string tab: "timer"

    // Opens on what is already running.
    onOpenChanged: {
        if (root.open && TimerService.shownMode !== "")
            root.tab = TimerService.shownMode
    }

    readonly property real bodyW: 330

    contentWidth: root.bodyW
    contentHeight: root.tab === "timer" ? 264 : 244

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
        id: timerPage
        visible: root.tab === "timer"
        x: root.pad
        y: root.pad + 46
        width: root.bodyW
        height: 210

        readonly property int customSeconds: Number(customHours.text) * 3600
            + Number(customMinutes.text) * 60 + Number(customSecondsInput.text)
        readonly property bool canSetCustom: !TimerService.timerRunning
            && customHours.acceptableInput && customMinutes.acceptableInput
            && customSecondsInput.acceptableInput
            && customSeconds > 0

        function applyCustom() {
            if (!timerPage.canSetCustom)
                return
            TimerService.setTimerMinutes(timerPage.customSeconds / 60)
        }

        Text {
            id: tBig
            anchors.horizontalCenter: parent.horizontalCenter
            text: TimerService.clock(TimerService.timerLeft, false)
            color: TimerService.timerRunning ? mt.ink : mt.inkSub
            font.family: mt.fontFamily
            font.features: { "tnum": 1 }
            font.kerning: false
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
                label: TimerService.timerRunning ? "Pause" : (TimerService.timerPaused ? "Resume" : "Start")
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

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 166
            spacing: 6
            enabled: !TimerService.timerRunning
            opacity: enabled ? 1 : 0.5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Custom"
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            DockDurationInput {
                id: customHours
                theme: mt
                width: 40
                maximum: 99
                text: "0"
                onAccepted: timerPage.applyCustom()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "h"
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 12
            }

            DockDurationInput {
                id: customMinutes
                theme: mt
                width: 40
                text: "5"
                onAccepted: timerPage.applyCustom()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "m"
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 12
            }

            DockDurationInput {
                id: customSecondsInput
                theme: mt
                width: 40
                text: "0"
                onAccepted: timerPage.applyCustom()
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "s"
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 12
            }

            DockButton {
                height: 30
                label: "Set"
                fontSize: 13
                enabled: timerPage.canSetCustom
                opacity: enabled ? 1 : 0.5
                onClicked: timerPage.applyCustom()
            }
        }
    }

    // ---- Stopwatch ----
    Item {
        id: stopwatch
        visible: root.tab === "stopwatch"
        x: root.pad
        y: root.pad + 46
        width: root.bodyW
        height: 190

        property real now: Date.now()
        readonly property real elapsed: stopwatchTick.running
            ? Math.max(0, (stopwatch.now - TimerService.swStart) / 1000)
            : TimerService.swElapsed

        // Only the open stopwatch panel needs frame-paced fractional updates.
        Timer {
            id: stopwatchTick
            interval: 16
            repeat: true
            triggeredOnStart: true
            running: root.open && stopwatch.visible && TimerService.swRunning
            onTriggered: stopwatch.now = Date.now()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: TimerService.stopwatchClock(stopwatch.elapsed)
            color: TimerService.swRunning ? mt.ink : mt.inkSub
            font.family: mt.fontFamily
            font.features: { "tnum": 1 }
            font.kerning: false
            font.pixelSize: 52
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 28
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
                label: TimerService.swRunning ? "Pause" : (TimerService.swPaused ? "Resume" : "Start")
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

        // All retained laps, newest first, within the existing card height.
        ListView {
            id: lapList
            y: 116
            width: parent.width
            height: parent.height - y
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: TimerService.laps
            onModelChanged: Qt.callLater(lapList.positionViewAtBeginning)

            delegate: Text {
                required property int index
                required property real modelData
                width: lapList.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: "Lap " + (TimerService.lapCount - index) + "   " + TimerService.stopwatchClock(modelData)
                color: mt.inkSub
                font.family: mt.fontFamily
                font.features: { "tnum": 1 }
                font.kerning: false
                font.pixelSize: 14
                font.weight: Font.Bold
            }

            SekaiScrollBar { margin: 4 }
        }

        WheelScroll {
            scroller: lapList
            step: 40
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
            font.features: { "tnum": 1 }
            font.kerning: false
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
                label: TimerService.pomRunning ? "Pause" : (TimerService.pomPaused ? "Resume" : "Start")
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
