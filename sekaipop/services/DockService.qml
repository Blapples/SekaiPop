pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The two things the dock (Dock.qml) needs from Hyprland that Quickshell's own
// window list does not give it:
//
// 1. MINIMIZING. Hyprland has no "minimize". The usual answer, and the one used
//    here: send the window to a hidden special workspace ("special:dockmin"). It
//    vanishes from the screen but stays open, and the dock still lists it (its
//    key shows a hollow dot). Restoring sends it back to the workspace it came
//    from (remembered in `origins`, in memory — after a shell reload it comes
//    back to the workspace you are on instead) and focuses it.
//
// 2. WINDOW GEOMETRY, for "Smart hide": the dock hides only while a window is
//    in its way. `hyprctl clients -j` / `monitors -j` are read (and only while at
//    least one dock is in smart-hide mode) whenever Hyprland says a window
//    opened, moved, resized or went full screen.
//
//   import qs.services
//   DockService.minimize(toplevel) / restore(toplevel) / isMinimized(toplevel)
//   DockService.covers("DP-1", { x, y, w, h })   // a window overlaps this rect (screen pixels)
Singleton {
    id: root

    readonly property string specialName: "dockmin"
    readonly property bool usingLua: Hyprland.usingLua !== false

    // window address -> the workspace id it was minimized from
    property var origins: ({})

    function isMinimized(t) {
        const n = t && t.workspace ? (t.workspace.name ?? "") : ""
        return n === "special:" + root.specialName
    }

    function addrOf(t) {
        return t.address
    }

    // The address as `hyprctl` and the dispatchers want it: "0x...". Quickshell's own
    // toplevel address may come without the prefix, and a dispatch with a bare address
    // finds no window (nothing happens, no error). Used by every dock dispatch.
    function hexAddr(address) {
        const a = String(address === undefined || address === null ? "" : address)
        if (a === "")
            return ""
        return a.indexOf("0x") === 0 ? a : "0x" + a
    }

    function moveTo(rawAddress, workspace) {
        const address = root.hexAddr(rawAddress)
        if (workspace === root.specialName) {
            Hyprland.dispatch(root.usingLua
                ? "hl.dsp.window.move({ workspace = \"special:" + root.specialName + "\", follow = false, window = \"address:" + address + "\" })"
                : "movetoworkspacesilent special:" + root.specialName + ",address:" + address)
        } else {
            Hyprland.dispatch(root.usingLua
                ? "hl.dsp.window.move({ workspace = " + workspace + ", follow = false, window = \"address:" + address + "\" })"
                : "movetoworkspacesilent " + workspace + ",address:" + address)
        }
    }

    function focusAddress(rawAddress, workspace) {
        const address = root.hexAddr(rawAddress)
        if (workspace !== null && workspace !== undefined && workspace > 0) {
            Hyprland.dispatch(root.usingLua
                ? "hl.dsp.focus({ workspace = " + workspace + " })"
                : "workspace " + workspace)
        }
        Hyprland.dispatch(root.usingLua
            ? "hl.dsp.focus({ window = \"address:" + address + "\" })"
            : "focuswindow address:" + address)
    }

    function minimize(t) {
        if (!t || root.isMinimized(t))
            return
        const ws = t.workspace ? t.workspace.id : null
        const next = Object.assign({}, root.origins)
        if (ws !== null && ws > 0)
            next[t.address] = ws
        root.origins = next
        root.moveTo(t.address, root.specialName)
    }

    // Back to the workspace it was on (else the one you are on) and focus it.
    function restore(t, focus) {
        if (!t || !root.isMinimized(t))
            return
        let ws = root.origins[t.address]
        if (ws === undefined || ws === null || ws <= 0)
            ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
        root.moveTo(t.address, ws)
        if (focus !== false)
            root.focusAddress(t.address, ws)
        const next = Object.assign({}, root.origins)
        delete next[t.address]
        root.origins = next
    }

    // ===== geometry for smart hide =====
    property var holders: ({})
    readonly property bool wanted: Object.keys(root.holders).length > 0

    // Each dock that is in smart-hide mode holds a key while it is. The key is the
    // dock window's own (newHoldKey), never one it shares with another dock: keyed by
    // monitor, a dock rebuilt on the same monitor (the shell builds it twice at startup)
    // found the key already held and skipped its own claim, and the old dock let go of it
    // on its way out. With nobody holding, the window list was never asked for again and
    // window events were ignored, so Smart hide stayed on whatever it had last seen, or on
    // nothing at all: the dock stood over a maximized window (issue #116).
    property int keysGiven: 0

    // A key for a new holder, unique for the life of the shell. Call it once, when the
    // holder is built (not from a binding: it counts up).
    function newHoldKey(prefix) {
        root.keysGiven += 1
        return prefix + "#" + root.keysGiven
    }

    function hold(key, on) {
        if (!key)
            return
        const has = key in root.holders
        if (has === on)
            return
        const next = Object.assign({}, root.holders)
        if (on)
            next[key] = true
        else
            delete next[key]
        root.holders = next
    }

    property var clients: []
    property var monitors: []

    // The first windows list AND monitors list have come back. Until then `covers` has
    // nothing to go on (it says "nothing is in the way"), so Smart hide waits for this at
    // startup instead of showing the dock over the windows.
    property bool clientsSeen: false
    property bool monitorsSeen: false
    readonly property bool ready: root.clientsSeen && root.monitorsSeen

    onWantedChanged: {
        if (root.wanted)
            root.refresh()
    }

    // Until the first windows AND monitors lists have come back, ask again every 400 ms. A
    // read that fails (Hyprland still starting, or a half-written answer) used to be tried
    // again only when Hyprland next reported a window event, which can be minutes away, and
    // Smart hide cannot tell what is in the way until it has an answer.
    Timer {
        interval: 400
        repeat: true
        running: root.wanted && !root.ready
        onTriggered: root.refresh()
    }

    function refresh() {
        if (getClients.running || getMonitors.running) {
            root.again = true
            return
        }
        getClients.running = true
        getMonitors.running = true
    }

    property bool again: false

    function afterFetch() {
        if (root.again && !getClients.running && !getMonitors.running) {
            root.again = false
            root.refresh()
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!root.wanted)
                return
            // Layer-shell and screencast events fire constantly (this shell's own
            // popups are layers) and never move a window.
            if (event.name === "openlayer" || event.name === "closelayer" || event.name === "screencast")
                return
            debounce.restart()
        }
    }

    Timer {
        id: debounce
        interval: 60
        onTriggered: root.refresh()
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsOut
            onStreamFinished: {
                try {
                    root.clients = JSON.parse(clientsOut.text)
                    root.clientsSeen = true
                } catch (e) {
                    console.warn("[dock] couldn't parse hyprctl clients:", e)
                }
            }
        }
        onExited: root.afterFetch()
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsOut
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsOut.text)
                    root.monitorsSeen = true
                } catch (e) {
                    console.warn("[dock] couldn't parse hyprctl monitors:", e)
                }
            }
        }
        onExited: root.afterFetch()
    }

    // Does any window on the monitor's visible workspace overlap `rect`
    // ({ x, y, w, h } in that monitor's own pixels, the top-left corner being 0,0)?
    // Minimized and hidden windows never count.
    function covers(screenName, rect) {
        let mon = null
        for (const m of root.monitors) {
            if (m.name === screenName) {
                mon = m
                break
            }
        }
        if (!mon || !mon.activeWorkspace)
            return false
        const ws = mon.activeWorkspace.id
        for (const c of root.clients) {
            if (c.mapped === false || c.hidden === true)
                continue
            if (!c.workspace || c.workspace.id !== ws)
                continue
            const cx = c.at[0] - mon.x
            const cy = c.at[1] - mon.y
            if (cx < rect.x + rect.w && cx + c.size[0] > rect.x
                    && cy < rect.y + rect.h && cy + c.size[1] > rect.y)
                return true
        }
        return false
    }
}
