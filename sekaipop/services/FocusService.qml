pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../modules/common/functions/FocusMath.js" as FM

// Desktop Focus Mode: when you are using applications the desktop widgets go
// away and stop working; on an empty workspace they come back.
//
// Two things live here, and they are kept apart on purpose:
//
//   1. VISIBILITY (the Desktop Visibility Manager). Which monitor's widgets
//      should be on screen, from what Hyprland says is on that monitor's active
//      workspace. The rules are in FocusMath.js (unit-tested with node,
//      tests/focus-test/focus_unit.js); this file only collects the facts.
//
//   2. SUSPENSION (the Widget Suspension Manager). What a widget that is not on
//      screen may stop doing: its clock, its fetches, its audio tap, its effects.
//      This is just a set of switches (`suspendWorkloads`, `visualizerBackground`,
//      `reduceEffects`); each widget decides what they mean for it through its
//      FocusGate (modules/sekai/desktopWidgets/FocusGate.qml). Hiding without
//      suspending is a valid setting: visibility never depends on suspension.
//
// Four separate ideas, four separate answers (FocusGate gives a widget all four):
//
//     visibility   hiddenOn(screen)        should the widget be on the desktop?
//     rendering    gate.show               may it draw at all (window mapped)?
//     activity     !gate.suspended         may its clock / fetches / audio run?
//     suspension   gate.suspended          has its non-essential work paused?
//
// WHERE THE FACTS COME FROM. Nothing new is opened and nothing is polled:
//   - which windows exist, and which workspace each is on: Quickshell's own
//     Hyprland models (Hyprland.toplevels / workspaces / monitors), which it keeps
//     current from the one event socket it already has
//   - whether a window is floating (and mapped, pinned, fullscreen): Quickshell
//     only learns that from `Hyprland.refreshToplevels()`, so that is called, on
//     the same socket (no hyprctl process), after the handful of events that can
//     change it (openwindow, changefloatingmode, movewindowv2, fullscreen, pin).
//     Quickshell does not react to changefloatingmode by itself.
//   - which workspace each monitor shows: HyprlandMonitor.activeWorkspace
//   Every other event (activewindow, windowtitle, layers ...) is ignored here.
//
// Only while Focus Mode is on: with it off nothing is listened to and every
// monitor reads "not hidden".
//
// For a script / keybind:
//   qs -c sekaipop ipc call focus toggle | enable | disable
//   qs -c sekaipop ipc call focus status
//
//   import qs.services
//   FocusService.hiddenOn("DP-1")
Singleton {
    id: root

    // ===== the switches (Settings -> Desktop -> Desktop Focus Mode) =====
    // Not read before the saved settings have been, or a start with Focus Mode
    // switched off would hide the widgets for a moment first.
    readonly property bool enabled: SettingsService.loaded && SettingsService.flag("focus.enabled")
    readonly property bool hideTiled: SettingsService.flag("focus.hideTiled")
    readonly property bool hideFloating: SettingsService.flag("focus.hideFloating")
    // Suspension: what a hidden widget may stop doing (see the header).
    readonly property bool suspendWorkloads: SettingsService.flag("focus.suspend")
    // The audio visualizer's own switch: keep its audio tap and analyzer warm while it is hidden.
    readonly property bool visualizerBackground: SettingsService.flag("focus.visualizerBackground")
    // Costly effects (a video wallpaper) pause while a window is on the monitor.
    // (Low-end mode, `perf.lowEnd`, counts as this switch being on.)
    readonly property bool reduceEffects: SettingsService.flag("focus.reduceEffects") || SettingsService.flag("perf.lowEnd")

    // Aggressive: a widget that has been hidden for a while is destroyed (its whole QML
    // tree, images and models) and built again when the desktop comes back. Unloading is
    // suspension taken to its end, so it needs suspension to be on.
    // (Low-end mode, `perf.lowEnd`, counts as `focus.unload` being on.)
    readonly property bool unloadHidden: (SettingsService.flag("focus.unload") || SettingsService.flag("perf.lowEnd")) && root.suspendWorkloads

    // Does the visualizer's audio tap keep running while the widget is hidden?
    // Its own switch says so, and so does switching suspension off altogether
    // ("hide the widgets but do not pause anything").
    readonly property bool visualizerKeepsListening: root.visualizerBackground || !root.suspendWorkloads

    // ===== what is published =====
    // monitor name -> { hidden, busy, tiled, floating, workspaceId } (FocusMath.compute).
    // Only replaced when a `hidden` or `busy` actually changed, so a Hyprland event
    // that changed nothing here wakes nobody (the counts live in `detail`).
    property var screens: ({})
    property var detail: ({})

    // Shell surfaces that take a whole monitor but are not Hyprland windows (a layer-shell panel,
    // like the readers at full width): claim id -> monitor name. Each counts on its monitor as a
    // maximized app, on whatever workspace is showing, so the widgets there hide and stop exactly
    // as they do for a fullscreen window. The claim holds while the surface says so; the surface
    // lets go of it when it shrinks to a side card, is minimized or closed.
    property var claims: ({})

    function claim(id, screenName) {
        if (!id || !screenName || root.claims[id] === screenName)
            return
        const next = Object.assign({}, root.claims)
        next[id] = screenName
        root.claims = next
        root.schedule()
    }

    function release(id) {
        if (!(id in root.claims))
            return
        const next = Object.assign({}, root.claims)
        delete next[id]
        root.claims = next
        root.schedule()
    }

    // Edit Desktop needs every widget on show, whatever is open (it also parks
    // you on an empty workspace, see EditMode.park, but it must not depend on that).
    readonly property bool editing: EditMode.active || EditMode.screenName !== ""

    // Visibility: should the desktop widgets of this monitor be on screen?
    // Plain function, so a binding that calls it follows `screens`, `enabled`
    // and `editing`.
    function hiddenOn(screenName) {
        if (!root.enabled || root.editing || !screenName)
            return false
        const s = root.screens[screenName]
        return !!s && s.hidden
    }

    // Is any window on this monitor's workspace (whether or not that hides anything)?
    function busyOn(screenName) {
        if (!root.enabled || !screenName)
            return false
        const s = root.screens[screenName]
        return !!s && s.busy
    }

    // "Reduce expensive effects while focused": a window is on the monitor.
    function effectsReducedOn(screenName) {
        return root.reduceEffects && !root.editing && root.busyOn(screenName)
    }

    // ===== collecting the facts =====
    function gather() {
        const wins = []
        const tl = Hyprland.toplevels.values
        for (let i = 0; i < tl.length; i++) {
            const t = tl[i]
            const o = t.lastIpcObject || {}
            const ws = t.workspace
            // `floating` is only in what `hyprctl clients` said; a window that has just
            // opened has none until refreshToplevels() answers (see the header).
            const known = typeof o.floating === "boolean"
            wins.push({
                address: t.address,
                workspaceId: ws ? ws.id : 0,
                monitor: ws && ws.monitor ? ws.monitor.name : "",
                floating: known ? o.floating : undefined,
                mapped: o.mapped,
                hidden: o.hidden,
                pinned: o.pinned === true,
                fullscreen: o.fullscreen === undefined ? 0 : o.fullscreen,
                cls: typeof o.class === "string" ? o.class : "",
                known: known
            })
        }

        // The claims, as fullscreen windows pinned to their monitor (FocusMath counts a pinned
        // window on its monitor whatever workspace is up, and a fullscreen one as tiled).
        for (const id of Object.keys(root.claims)) {
            wins.push({
                address: "claim:" + id,
                workspaceId: 0,
                monitor: root.claims[id],
                floating: false,
                mapped: true,
                hidden: false,
                pinned: true,
                fullscreen: 1,
                cls: "",
                known: true
            })
        }

        const mons = []
        const ml = Hyprland.monitors.values
        for (let i = 0; i < ml.length; i++) {
            const m = ml[i]
            const aw = m.activeWorkspace
            const sp = m.lastIpcObject ? m.lastIpcObject.specialWorkspace : null
            mons.push({
                name: m.name,
                workspaceId: aw ? aw.id : 0,
                specialId: sp && sp.id ? sp.id : 0
            })
        }
        return { wins: wins, mons: mons }
    }

    function recompute(settled) {
        if (!root.enabled) {
            root.clear()
            return
        }
        const g = root.gather()
        const next = FM.compute(g.wins, g.mons, {
            enabled: true,
            hideTiled: root.hideTiled,
            hideFloating: root.hideFloating
        })
        // Hide at once; come back only when the answer has held for a moment.
        const hold = FM.holding(root.screens, next)
        const pub = FM.publish(root.screens, next, settled === true)
        if (hold && !settled) {
            if (!settleTimer.running)
                settleTimer.start()
        } else {
            settleTimer.stop()
        }
        root.detail = pub
        if (!FM.same(root.screens, pub))
            root.screens = pub
    }

    function clear() {
        refreshTimer.stop()
        verifyTimer.stop()
        settleTimer.stop()
        root.wantWindows = false
        root.wantMonitors = false
        root.detail = ({})
        if (Object.keys(root.screens).length > 0)
            root.screens = ({})
    }

    // One recompute per turn of the event loop, however many signals asked for it
    // (a window closing touches the toplevel list, its workspace and its monitor).
    function schedule() {
        if (root.enabled)
            recalcTimer.restart()
    }

    Timer {
        id: recalcTimer
        interval: 0
        onTriggered: root.recompute(false)
    }

    // The answer has been "back to visible" for the whole settle time.
    Timer {
        id: settleTimer
        interval: 90
        onTriggered: root.recompute(true)
    }

    // ===== asking Hyprland again, on the connection Quickshell already has =====
    property bool wantWindows: false
    property bool wantMonitors: false
    // An event arrived while an earlier refresh may still have been on its way
    // (Quickshell drops a refreshToplevels() that overlaps one in flight).
    property bool again: false

    function refresh(windows, monitors) {
        if (windows)
            root.wantWindows = true
        if (monitors)
            root.wantMonitors = true
        if (verifyTimer.running)
            root.again = true
        refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        // Events come in bursts (a window opening is openwindow, movewindowv2, activewindow ...).
        interval: 30
        onTriggered: {
            if (root.wantWindows)
                Hyprland.refreshToplevels()
            if (root.wantMonitors)
                Hyprland.refreshMonitors()
            root.wantWindows = false
            root.wantMonitors = false
            verifyTimer.restart()
        }
    }

    Timer {
        id: verifyTimer
        interval: 140
        onTriggered: {
            if (!root.again)
                return
            root.again = false
            Hyprland.refreshToplevels()
            Hyprland.refreshMonitors()
            verifyTimer.restart()
        }
    }

    Connections {
        target: Hyprland
        enabled: root.enabled

        function onRawEvent(event) {
            switch (event.name) {
            // Can change what a window is: floating, fullscreen, pinned, where it is.
            case "openwindow":
            case "changefloatingmode":
            case "movewindowv2":
            case "fullscreen":
            case "pin":
                root.refresh(true, false)
                break
            // Which workspace a monitor shows / which monitor a workspace is on. Quickshell
            // keeps these current itself; asking once more is the ground truth for the cases
            // it does not cover (a workspace changed on a monitor that is not focused).
            case "focusedmon":
            case "workspacev2":
            case "moveworkspacev2":
            case "destroyworkspacev2":
            case "monitoraddedv2":
            case "monitorremoved":
                root.refresh(false, true)
                root.schedule()
                break
            case "configreloaded":
                root.refresh(true, true)
                root.schedule()
                break
            // A scratchpad opened or closed over a monitor.
            case "activespecialv2":
                root.refresh(false, true)
                break
            // Gone: the toplevel list changes by itself, this only makes sure of it.
            case "closewindow":
                root.schedule()
                break
            default:
                break
            }
        }
    }

    // The model signals are what normally drive a recompute (answers to the refreshes
    // above land here too): the lists themselves ...
    Connections {
        target: Hyprland.toplevels
        enabled: root.enabled
        function onValuesChanged() { root.schedule() }
    }

    Connections {
        target: Hyprland.monitors
        enabled: root.enabled
        function onValuesChanged() { root.schedule() }
    }

    Connections {
        target: Hyprland.workspaces
        enabled: root.enabled
        function onValuesChanged() { root.schedule() }
    }

    // ... and the few things on each object that can change without the list changing.
    Component {
        id: watcher

        Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true

            // window: moved to another workspace / answered by `hyprctl clients`
            function onWorkspaceChanged() { root.schedule() }
            function onLastIpcObjectChanged() { root.schedule() }
            // window / workspace: which monitor it is on now
            function onMonitorChanged() { root.schedule() }
            // monitor: which workspace it shows now
            function onActiveWorkspaceChanged() { root.schedule() }
        }
    }

    Instantiator {
        model: root.enabled ? Hyprland.toplevels : null
        delegate: watcher
    }

    Instantiator {
        model: root.enabled ? Hyprland.monitors : null
        delegate: watcher
    }

    Instantiator {
        model: root.enabled ? Hyprland.workspaces : null
        delegate: watcher
    }

    // ===== reacting to the switches =====
    onEnabledChanged: {
        if (root.enabled) {
            root.refresh(true, true)
            root.schedule()
        } else {
            root.clear()
        }
    }

    onHideTiledChanged: root.schedule()
    onHideFloatingChanged: root.schedule()

    Component.onCompleted: {
        if (root.enabled) {
            root.refresh(true, true)
            root.schedule()
        }
    }

    // ===== ipc =====
    //   qs -c sekaipop ipc call focus toggle | enable | disable | status
    IpcHandler {
        target: "focus"

        function toggle(): void { SettingsService.toggle("focus.enabled") }
        function enable(): void { SettingsService.set("focus.enabled", true) }
        function disable(): void { SettingsService.set("focus.enabled", false) }

        // One line per monitor: what the widgets there are doing and why.
        function status(): string {
            const lines = ["focus mode " + (root.enabled ? "on" : "off")
                + (root.editing ? " (Edit Desktop: widgets shown)" : "")]
            const d = root.detail
            for (const name of Object.keys(d).sort()) {
                const s = d[name]
                lines.push(name + ": " + (root.hiddenOn(name) ? "widgets hidden" : "widgets shown")
                    + " (workspace " + s.workspaceId + ", " + s.tiled + " tiled, " + s.floating + " floating)")
            }
            return lines.join("\n")
        }
    }
}
