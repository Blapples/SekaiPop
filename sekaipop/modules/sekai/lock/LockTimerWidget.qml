import QtQuick
import qs.services
import qs.modules.common

// The dock's timer, stopwatch or pomodoro, while one is running (or paused): the clock, and
// under it what it is. Nothing is drawn when none is on. Read-only: it shows
// services/TimerService.qml and never starts, stops or changes it. Option `label`: the second
// line ("Focus", "Timer", "Stopwatch"; "Paused" is added while it is paused).
LockWidget {
    id: root

    readonly property bool live: TimerService.hasTime
    readonly property bool shown: root.live || root.preview
    readonly property string mode: root.live ? TimerService.shownMode : "pomodoro"
    readonly property string clockText: root.live ? TimerService.shownClock : "24:13"
    readonly property bool paused: root.live && TimerService.shownPaused

    readonly property string word: {
        if (root.mode === "stopwatch")
            return "Stopwatch"
        if (root.mode === "timer")
            return "Timer"
        return root.live ? TimerService.phaseLabel : "Focus"
    }
    readonly property string icon: root.mode === "stopwatch" ? "av_timer" : (root.mode === "timer" ? "timer" : "hourglass_top")

    implicitWidth: root.shown ? cap.width : 0
    implicitHeight: root.shown ? cap.height : 0

    LockInfoCapsule {
        id: cap
        visible: root.shown
        px: root.px
        capH: root.capH
        capPad: root.capPad
        icon: root.icon
        iconColor: root.paused ? LockPalette.lavenderText : LockPalette.mint
        title: root.clockText
        subtitle: root.opt("label", true) === true ? root.word + (root.paused ? " \u00b7 Paused" : "") : ""
    }
}
