pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Which keyboard layout is active ("us", "ru", ...), read from Hyprland. State only,
// no window: the bar's layout pill (Bar.qml) and both lockscreen looks (LockSurface.qml,
// LockCalendar.qml) read it, so they always agree and Hyprland is asked once, not once
// per bar.
//
//   import qs.services
//   ...
//   text: KeyboardLayoutService.code      // "EN", or "" when there is nothing to switch between
//
// Only worth showing when more than one layout is configured: on a one-layout system a
// pill would permanently say "EN". So `code` is empty then, and every pill hides itself.
Singleton {
    id: root

    // Hyprland's name for the active keymap, "English (US)", "Russian", ...
    property string layoutName: ""
    // How many layouts kb_layout lists ("us,ru" is two).
    property int layoutCount: 0

    readonly property string code: root.layoutCount > 1 && root.layoutName !== ""
        ? root.layoutName.slice(0, 2).toUpperCase() : ""

    // `hyprctl switchxkblayout` is its own hyprctl command, not a dispatcher, so it is the
    // same on a Lua-mode and a hyprlang config. "all" moves every keyboard together, so the
    // code shown is always the one you are typing with.
    function cycle() {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
    }

    function refresh() {
        fetch.running = false
        fetch.running = true
    }

    // A read right as the shell starts can come back empty (seen once, at an install's
    // restart), and nothing else would ask again until Hyprland sent an event. So a failed
    // read is tried again a few times, not for ever: with no Hyprland (niri) it never works.
    property int failures: 0

    Process {
        id: fetch
        running: true
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(collector.text)
                    const kb = (parsed.keyboards || []).find(k => k.main === true) || (parsed.keyboards || [])[0]
                    if (kb) {
                        root.layoutName = kb.active_keymap || ""
                        root.layoutCount = (kb.layout || "").split(",").filter(s => s.length > 0).length
                    }
                    root.failures = 0
                } catch (e) {
                    console.warn("KeyboardLayoutService: couldn't parse `hyprctl -j devices` for keyboard layout: " + e + " (got " + collector.text.length + " bytes)")
                    if (++root.failures < 4)
                        refetch.restart()
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Hyprland sends "activelayout" as "<device>,<layout name>"
            if (event.name === "activelayout" && root.layoutCount > 1)
                root.layoutName = event.data.substring(event.data.indexOf(",") + 1)
            // A reload can add or drop layouts (kb_layout = "us,ru"), so ask again.
            else if (event.name === "configreloaded")
                root.refresh()
        }
    }

    // The Hyprland page's keyboard card changes kb_layout live: read the list again
    // a moment after, once Hyprland has rebuilt the keymaps.
    Connections {
        target: HyprlandSettings
        function onApplied(path) {
            if (path.indexOf("input.kb_") === 0)
                refetch.restart()
        }
    }

    // Locking is when the code matters most and when a missed event would hurt: nobody can
    // fix it from the lockscreen, so start from what Hyprland says right now.
    Connections {
        target: LockState
        function onLockedChanged() {
            if (LockState.locked)
                root.refresh()
        }
    }

    Timer {
        id: refetch
        interval: root.failures > 0 ? 2000 : 400
        onTriggered: root.refresh()
    }
}
