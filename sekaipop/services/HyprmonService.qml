pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import "../modules/common/functions/HyprmonMath.js" as HM

// hyprmon as the display handler (Settings > Hyprland > Displays: "Display handler").
// hyprmon (github.com/erans/hyprmon) keeps monitor profiles and writes the one in use to
// ~/.config/hypr/hyprmon.lua; this service lists its profiles, applies them (always with
// hyprmon's own `-profile`), saves the Displays card's screens into one, renames, deletes
// and reorders them (scripts/hyprland/hyprmon.sh, on hyprmon's own files), and adds what
// hyprmon has no part for: switching profile by itself when screens are plugged in or
// out, and never leaving you with no screen on.
//
// Picking a profile (modules/common/functions/HyprmonMath.js): only profiles that turn
// on at least one screen and whose screens that are on are all plugged in; the one that
// knows exactly the screens plugged in first; a tie goes to the profile used last on
// these screens (remembered here), then to the first in your order.
//
//     HyprmonService.apply("Work-3")
//     HyprmonService.saveProfile("Desk 4", monitors)   // monitors in hyprmon's shape
//
// Only does anything while the handler is hyprmon (`on`). State (the profile used last on
// each set of screens): ~/.local/state/sekaipop/hyprmon.json.
Singleton {
    id: root

    // hyprmon is installed.
    property bool available: false
    // The handler is hyprmon (and it is there).
    readonly property bool on: root.available && SettingsService.get("display.handler") === "hyprmon"
    readonly property bool autoSwitch: root.on && SettingsService.flag("display.hyprmonAuto")

    // [{ name, monitors, created_at, updated_at }] in the user's order.
    property var profiles: []
    // The profile hyprmon says is on now ("" = none matches the screens exactly).
    property string active: ""
    // The profile put on last from here (by hand or automatically).
    property string lastApplied: ""
    // The profile the card calls "on now": hyprmon's own answer, or, when hyprmon finds
    // none (it compares a screen that is off by its position too, which Hyprland and the
    // profile may not agree on), the one put on last.
    readonly property string current: root.active !== "" ? root.active
        : (root.profile(root.lastApplied) ? root.lastApplied : "")
    // { setKey: profileName }: the profile used last on each set of screens.
    property var remembered: ({})
    // A command is running (the card shows it and does not start another).
    property bool busy: false
    // What happened last, for the card ("Switched to Work-3", "Couldn't save ...").
    property string message: ""
    // The Displays card is in the middle of a change (Apply, then the "keep these?"
    // countdown): never switch profile under it (DisplayService sets it).
    property bool held: false
    // The screens plugged in at the last look (HM.setKey): a switch is only chosen when
    // they change. Turning a screen off or on sends Hyprland's monitorremoved /
    // monitoradded too, but plugs nothing in or out.
    property string lastSetKey: ""

    readonly property string script: Directories.script("hyprland/hyprmon.sh")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/sekaipop"

    function profile(name) {
        return root.profiles.find(p => p.name === name) || null
    }

    function summary(name) {
        return HM.summary(root.profile(name))
    }

    // ===== reading =====
    function refresh() {
        if (!root.available)
            return
        if (!lister.running)
            lister.running = true
    }

    Process {
        id: checker
        command: ["sh", "-c", "command -v hyprmon >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = text.trim() === "yes"
                if (root.available)
                    root.refresh()
            }
        }
    }

    Process {
        id: lister
        command: ["sh", root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text)
                    if (Array.isArray(list) && JSON.stringify(list) !== JSON.stringify(root.profiles))
                        root.profiles = list
                } catch (e) {
                    console.warn("HyprmonService: couldn't read the profiles (" + e + ")")
                }
                if (!activeReader.running)
                    activeReader.running = true
            }
        }
    }

    Process {
        id: activeReader
        command: ["sh", root.script, "active"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.active = text.trim()
                // A check waiting for the profiles to be read (see `settle`).
                if (root.wantCheck !== "") {
                    const what = root.wantCheck
                    root.wantCheck = ""
                    root.readScreens(what)
                }
            }
        }
    }

    // "choose" / "guard" once the profiles have been read again, or "".
    property string wantCheck: ""

    // ===== state =====
    FileView {
        id: state
        path: root.stateDir + "/hyprmon.json"
        onLoaded: {
            try {
                const s = JSON.parse(text())
                root.remembered = (s && typeof s.remembered === "object" && s.remembered) || {}
                root.lastApplied = (s && typeof s.lastApplied === "string") ? s.lastApplied : ""
            } catch (e) {
                root.remembered = {}
            }
        }
    }

    function saveState() {
        state.setText(JSON.stringify({ remembered: root.remembered, lastApplied: root.lastApplied }, null, 2) + "\n")
    }

    // ===== commands =====
    // One command at a time; `then(ok, output)` runs after it.
    property var pending: null

    Process {
        id: runner
        stdout: StdioCollector { id: runOut }
        stderr: StdioCollector { id: runErr }
        onExited: code => {
            const then = root.pending
            root.pending = null
            root.busy = false
            if (then)
                then(code === 0, (runOut.text + "\n" + runErr.text).trim())
            root.refresh()
        }
    }

    function run(args, then) {
        if (runner.running)
            return false
        root.busy = true
        root.pending = then || null
        runner.command = args
        runner.running = true
        return true
    }

    // Put a profile on. `why` is "auto" for a switch made by itself (it says so).
    function apply(name, why) {
        if (!root.on || !HM.validName(name))
            return
        root.quietUntil = Date.now() + root.quietMs
        root.run(["sh", root.script, "apply", name], (ok, out) => {
            if (!ok) {
                root.message = "Couldn't apply " + name + (out ? ": " + out.split("\n").slice(-1)[0] : "")
                return
            }
            root.lastApplied = name
            root.message = (why === "auto" ? "Switched to " : "Applied ") + name
            root.rememberNow(name)
            if (why === "auto")
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "material:monitor", "Displays", "Switched to the " + name + " profile"])
            // hyprmon reloads Hyprland: look again once it has, and make sure a screen is on.
            guardSoon.restart()
        })
    }

    // Save screens into a profile (a new one goes last), then put it on with hyprmon so
    // hyprmon.lua is written from it. `monitors` in hyprmon's shape (HM.toProfileMonitor).
    function saveProfile(name, monitors, then) {
        if (!root.on || !HM.validName(name) || !monitors || monitors.length === 0)
            return false
        const old = root.profile(name)
        const all = HM.mergeMonitors(old ? old.monitors : [], monitors)
        const tmp = "/tmp/sekaipop-hyprmon-" + Date.now() + ".json"
        return root.run(["sh", "-c", "printf '%s' \"$2\" > \"$1\" && sh \"$3\" save \"$4\" \"$1\"; rc=$?; rm -f \"$1\"; exit $rc",
                         "sh", tmp, JSON.stringify({ monitors: all }), root.script, name], (ok, out) => {
            root.message = ok ? "Saved to " + name : "Couldn't save " + name + (out ? ": " + out.split("\n").slice(-1)[0] : "")
            if (ok)
                root.apply(name, "save")
            if (then)
                then(ok)
        })
    }

    function rename(oldName, newName) {
        if (!root.on || !HM.validName(oldName) || !HM.validName(newName) || oldName === newName)
            return
        if (root.profile(newName)) {
            root.message = "There is already a profile called " + newName
            return
        }
        root.run(["sh", root.script, "rename", oldName, newName], (ok, out) => {
            root.message = ok ? "Renamed to " + newName : "Couldn't rename: " + out
            if (!ok)
                return
            const next = {}
            Object.keys(root.remembered).forEach(k => { next[k] = root.remembered[k] === oldName ? newName : root.remembered[k] })
            root.remembered = next
            if (root.lastApplied === oldName)
                root.lastApplied = newName
            root.saveState()
        })
    }

    function remove(name) {
        if (!root.on || !HM.validName(name))
            return
        root.run(["sh", root.script, "delete", name], (ok, out) => {
            root.message = ok ? "Deleted " + name + " (a copy is in ~/.config/hyprmon/backups)" : "Couldn't delete: " + out
            if (!ok)
                return
            const next = {}
            Object.keys(root.remembered).forEach(k => { if (root.remembered[k] !== name) next[k] = root.remembered[k] })
            root.remembered = next
            root.saveState()
        })
    }

    // Move a profile one place earlier (-1) or later (+1) in the order.
    function move(name, step) {
        const names = root.profiles.map(p => p.name)
        const i = names.indexOf(name), j = i + step
        if (!root.on || i < 0 || j < 0 || j >= names.length)
            return
        names.splice(i, 1)
        names.splice(j, 0, name)
        root.run(["sh", root.script, "order"].concat(names), null)
    }

    // ===== the screens plugged in =====
    // What to do once the screens have been read: "choose" or "guard".
    property string afterRead: ""

    function readScreens(then) {
        root.afterRead = then
        if (!screens.running)
            screens.running = true
    }

    Process {
        id: screens
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list
                try {
                    list = JSON.parse(text)
                } catch (e) {
                    return
                }
                // Hyprland's stand-ins (no screen at all, a virtual one) are not screens.
                const real = list.filter(m => m.name !== "FALLBACK" && !String(m.name).startsWith("HEADLESS"))
                const ids = HM.hardwareIds(real.map(m => ({ name: m.name, make: m.make, model: m.model, serial: m.serial })))
                const connected = real.map(m => ({ name: m.name, hwid: ids[m.name] || "", on: m.disabled !== true }))
                const key = HM.setKey(connected)
                const changed = key !== root.lastSetKey
                root.lastSetKey = key
                if (root.afterRead === "choose" && changed)
                    root.choose(connected)
                else
                    root.guard(connected)
            }
        }
    }

    function rememberNow(name) {
        root.rememberName = name
        if (!rememberReader.running)
            rememberReader.running = true
    }

    property string rememberName: ""

    Process {
        id: rememberReader
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = root.rememberName
                if (name === "")
                    return
                try {
                    const real = JSON.parse(text).filter(m => m.name !== "FALLBACK" && !String(m.name).startsWith("HEADLESS"))
                    const ids = HM.hardwareIds(real.map(m => ({ name: m.name, make: m.make, model: m.model, serial: m.serial })))
                    const key = HM.setKey(real.map(m => ({ name: m.name, hwid: ids[m.name] || "" })))
                    const next = Object.assign({}, root.remembered)
                    next[key] = name
                    root.remembered = next
                } catch (e) {}
                root.saveState()
            }
        }
    }

    // Auto-switch: the best profile for these screens, unless it is on already.
    function choose(connected) {
        if (!root.autoSwitch || root.held || connected.length === 0)
            return
        const pick = HM.chooseProfile(root.profiles, connected, root.remembered)
        if (pick === "") {
            root.guard(connected)
            return
        }
        if (pick === root.active && connected.some(c => c.on))
            return
        root.apply(pick, "auto")
    }

    // Never no screen: if every plugged-in screen is off, turn one on (the laptop's own
    // first), at its preferred mode, and say so.
    function guard(connected) {
        if (!root.on || connected.length === 0 || connected.some(c => c.on))
            return
        const pickOne = connected.find(c => /^(eDP|LVDS|DSI)/.test(c.name)) || connected[0]
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + pickOne.name + "\", mode = \"preferred\", position = \"auto\", scale = 1, disabled = false })"])
        root.message = "No screen was on: turned " + pickOne.name + " on"
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-u", "critical", "-i", "material:monitor", "Displays",
                                 "No screen was on, so " + pickOne.name + " was turned back on. Save a profile for these screens."])
    }

    // ===== plugging in and out =====
    // Hyprland sends several events for one plug (and our own apply reloads Hyprland,
    // which sends them again): wait for them to settle, and ignore the ones an apply
    // of ours causes.
    readonly property int quietMs: 5000
    property double quietUntil: 0

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.on)
                return
            const n = event.name
            if (n !== "monitoradded" && n !== "monitoraddedv2" && n !== "monitorremoved" && n !== "monitorremovedv2")
                return
            if (String(event.data).indexOf("FALLBACK") >= 0 || String(event.data).indexOf("HEADLESS") >= 0)
                return
            if (Date.now() < root.quietUntil)
                return
            settle.restart()
        }
    }

    Timer {
        id: settle
        interval: 1500
        onTriggered: root.checkSoon(root.autoSwitch ? "choose" : "guard")
    }

    // Read the profiles again, then the screens, then choose / guard.
    function checkSoon(what) {
        if (!root.available)
            return
        root.wantCheck = what
        if (lister.running || activeReader.running)
            return
        lister.running = true
    }

    Timer {
        id: guardSoon
        interval: 2500
        onTriggered: root.readScreens("guard")
    }

    // At start the session may not match the profile hyprmon.lua was written from
    // (started undocked after a docked day): choose once.
    Timer {
        id: startCheck
        interval: 4000
        onTriggered: if (root.on) root.checkSoon(root.autoSwitch ? "choose" : "guard")
    }

    Component.onCompleted: {
        checker.running = true
        startCheck.start()
    }
}
