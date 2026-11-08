import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.modules.common

// The screen lock: one WlSessionLock (the ext-session-lock protocol —
// the compositor itself hides everything else and only shows what this
// draws, so nothing can be clicked or typed into behind it), with one
// LockSurface per monitor. State lives in LockState.qml; the password
// check in LockContext.qml; the look in LockSurface.qml (gacha), LockCalendar.qml or
// LockCanvas.qml (custom), whichever LockHost.qml picks from Settings.
//
// Lock it any of these ways:
//   - the Quick Panel's Power menu (Lock)
//   - qs -c sekaipop ipc call lock lock      (bind it, or use it from hypridle)
//
// There is no IPC call to *unlock* on purpose — the password is the only
// way out.
//
// Locking and unlocking both play the wallpaper transition (the style picked
// in Settings -> Desktop -> Wallpaper) over your REAL desktop (bar, windows
// and all). The compositor hides everything except the lock surface once a
// session lock is engaged, so the effect can't be drawn by the lock surface
// itself. Instead LockRing.qml (one transparent overlay per screen) plays it
// while the session is still unlocked:
//
//   lock:    transition plays over the desktop  ->  session lock engages
//   unlock:  session lock releases              ->  transition plays over the desktop
//
// The lock surface and the overlay show the identical picture, so the
// hand-off in the middle is invisible. LockState.qml has the phases.
//
// If this process dies while locked, the compositor keeps the screen
// locked (a plain "oopsie" screen) rather than exposing the session —
// that's the protocol working as intended. See README.md ("Lockscreen")
// for the recovery steps.
Scope {
    id: root

    LockContext {
        id: lockContext

        onUnlocked: {
            // Release the session lock *now*, or the compositor keeps
            // showing a lock nobody is drawing. The overlay is already up
            // with the same picture, so nothing visibly changes; then
            // the ring opens up the desktop underneath it.
            LockState.beginUnlock()
        }
    }

    // One transparent overlay per screen that plays the ring over the
    // live desktop (see LockRing.qml).
    Variants {
        model: Quickshell.screens
        LockRing {
            context: lockContext
        }
    }

    // Safety nets: the phases normally end when the ring's animation
    // finishes, but if that ever can't happen (a screen that isn't
    // rendering, a shader that failed to load) the lock must still
    // engage and the session must still release.
    Timer {
        running: LockState.phase === "locking"
        interval: LockState.ringMs + 1500
        onTriggered: LockState.engage()
    }
    Timer {
        running: LockState.phase === "unlocking"
        interval: LockState.ringMs + 1500
        onTriggered: LockState.finishUnlock()
    }

    // A fresh lock starts with an empty field.
    Connections {
        target: LockState
        function onLockedChanged() {
            if (LockState.locked)
                lockContext.reset()
        }
    }

    WlSessionLock {
        locked: LockState.locked

        WlSessionLockSurface {
            id: lockWindow

            // Opaque from the first frame: the compositor may show this
            // the instant it's mapped, and the desktop must never peek
            // through. The picture is drawn at once, no fade: LockRing.qml just
            // showed the very same one.
            color: LockPalette.cBorder

            LockHost {
                anchors.fill: parent
                context: lockContext
                uiScale: ShellScale.forScreen(lockWindow.screen)
                screenName: lockWindow.screen ? lockWindow.screen.name : ""
            }
        }
    }
    Process {
        id: logindWatcher
        property bool awaitingSleepState: false
        running: true
        command: [
            "setpriv", "--pdeathsig", "TERM", "dbus-monitor", "--system",
            "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Session',member='Lock'",
            "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
        ]
        stdout: SplitParser {
            onRead: line => {
                // dbus-monitor prints: signal time=... sender=... member=Lock
                if (line.startsWith("signal ") && line.includes("member=Lock")) {
                    LockState.lock()
                    return
                }
                // PrepareForSleep carries its boolean on the next output line.
                if (line.startsWith("signal ") && line.includes("member=PrepareForSleep")) {
                    logindWatcher.awaitingSleepState = true
                    return
                }
                if (logindWatcher.awaitingSleepState && line.trim() !== "") {
                    logindWatcher.awaitingSleepState = false
                    if (line.trim() === "boolean false")
                        lockContext.resumeFromSleep()
                }
            }
        }
        onExited: {
            if (restartTimer.attempts < 5)
                restartTimer.start()
        }
    }

    Timer {
        id: restartTimer
        property int attempts: 0
        interval: 3000
        onTriggered: {
            attempts++
            logindWatcher.running = true
        }
    }
    IpcHandler {
        target: "lock"

        function lock(): void {
            LockState.lock()
        }

        // Hyprland sometimes drops keyboard focus from the lock surface
        // after a wake from sleep; hypridle's after_sleep_cmd (or a
        // keybind) can call this to hand it back.
        function focus(): void {
            lockContext.focusRequested()
        }
    }
}
