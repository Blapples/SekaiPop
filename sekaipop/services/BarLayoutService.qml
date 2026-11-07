pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// Where each module of the bar sits: in the LEFT, CENTER or RIGHT zone, and in
// what order inside it. Remembered across restarts.
//
//   left     starts at the left end of a flat bar (the top of a standing one)
//   center   sits dead-center (the middle of a standing one)
//   right    ends at the right end of a flat bar (the bottom of a standing one)
//
// By default there is one layout for the whole shell and every monitor's bar
// follows it. With Settings -> Bar -> "Separate bar per monitor"
// (`bar.perMonitor`) on, each monitor keeps its own: the arrangement AND which
// modules are on its bar. A monitor that has not been edited yet follows the
// shared layout until its first change (that change starts from a copy of the
// shared one). Turning the option off again shows the shared layout everywhere
// and keeps each monitor's own for next time.
//
// It is changed from Edit Desktop (the shelf's BAR tab, EditBarLayout.qml; it
// edits the monitor it is open on). Whether a module is shown at all stays the
// Settings Panel's job (SettingsService "bar.*" switches, the master switch for
// every monitor): a module that is switched off keeps its place here and just
// takes no room. A per-monitor bar can only take modules off on top of that.
//
// From a keybind or a script:
//   qs -c sekaipop ipc call barlayout get
//   qs -c sekaipop ipc call barlayout move clock left 0     (zone, position in it)
//   qs -c sekaipop ipc call barlayout reset
//   qs -c sekaipop ipc call barlayout clearall               (every module off the bar)
//   qs -c sekaipop ipc call barlayout movescreen DP-1 clock left 0
//   qs -c sekaipop ipc call barlayout resetscreen DP-1
//
// Plugins with a bar entry (PluginService.barModules, docs/PLUGINS.md) are modules too, by
// the id "plugin:<id>". Their master switch is the plugin's own (PluginState.barShown), not a
// SettingsService "bar.*" key, and they are off until turned on. One not in a saved layout
// yet (just installed) goes at the end of the right zone; one in a saved layout that is not
// installed (any more, or not scanned yet at start-up) keeps its place and takes no room.
Singleton {
    id: root

    // Every module the bar can carry: the built-in ones, then the plugins'. `id` is what
    // Status_Bar.qml knows it by (and what the layout below is made of).
    readonly property var modules: root.builtinModules.concat(PluginService.barModules)

    readonly property var builtinModules: [
        { id: "workspaces", label: "Workspaces", icon: "grid_view" },
        { id: "activeWindow", label: "Active window", icon: "web_asset" },
        { id: "media", label: "Media", icon: "music_note" },
        { id: "privacy", label: "Privacy", icon: "shield_with_heart" },
        { id: "discord", label: "Discord call", icon: "headset_mic" },
        { id: "updates", label: "Updates", icon: "system_update_alt" },
        { id: "utilButtons", label: "Utility keys", icon: "construction" },
        { id: "resources", label: "CPU & RAM", icon: "memory" },
        { id: "screenTime", label: "Screen time", icon: "hourglass" },
        { id: "timer", label: "Timer", icon: "timer" },
        { id: "netSpeed", label: "Network speed", icon: "arrow_downward" },
        { id: "status", label: "Wi-Fi, Bluetooth & sound", icon: "wifi" },
        { id: "battery", label: "Battery", icon: "battery_android_full" },
        { id: "keyboardLayout", label: "Keyboard layout", icon: "keyboard_alt" },
        { id: "notifications", label: "Notification bell", icon: "notifications" },
        { id: "tray", label: "Tray", icon: "apps" },
        { id: "weather", label: "Weather", icon: "partly_cloudy_day" },
        { id: "date", label: "Date", icon: "calendar_month" },
        { id: "clock", label: "Clock", icon: "schedule" }
    ]

    // The pills a desktop preset saved before it kept a list of its own had to choose from.
    // FIXED: never add to it. A pill added later (Screen time, Timer and Network speed were the
    // first) is left out, so an old preset wears it off; a preset saved from now on lists every
    // pill that existed (`bar.modules`, DesktopPresetService), so a newer pill is the same
    // for it. Adding a pill is one line in `builtinModules`, nothing here.
    readonly property var legacyModules: ["workspaces", "activeWindow", "media", "privacy", "discord", "updates",
        "utilButtons", "resources", "status", "battery", "keyboardLayout", "notifications", "tray", "weather",
        "date", "clock"]

    readonly property var zoneNames: ["left", "center", "right"]

    // ===== plugin modules =====
    readonly property var pluginIdRe: /^plugin:[a-z0-9][a-z0-9-]{0,39}$/

    function isPlugin(id) {
        return typeof id === "string" && root.pluginIdRe.test(id)
    }

    // A name a layout may keep: a built-in module, or anything shaped like a plugin's (it may
    // not be installed yet, or not scanned yet: the saved layout is read before the plugins).
    function keepable(id) {
        return root.builtinModules.some(m => m.id === id) || root.isPlugin(id)
    }

    // The module's master switch: Settings > Bar > Modules for a built-in one, the plugin's
    // own for a plugin's. An unknown plugin is off.
    function masterOn(id) {
        if (root.isPlugin(id)) {
            const st = PluginService.stateFor(id)
            return !!st && st.barShown && !!st.plugin.bar
        }
        return SettingsService.flag("bar." + id)
    }

    function setMaster(id, on) {
        if (root.isPlugin(id)) {
            const st = PluginService.stateFor(id)
            if (st && st.plugin.bar)
                st.setBarShown(on)
            return
        }
        SettingsService.set("bar." + id, on)
    }

    // A layout with every installed plugin module in it: one it does not name yet goes at the
    // end of the right zone.
    function withPlugins(lay) {
        const named = lay.left.concat(lay.center, lay.right)
        const missing = PluginService.barModules.map(m => m.id).filter(id => named.indexOf(id) < 0)
        if (missing.length === 0)
            return lay
        const out = Object.assign({}, lay)
        out.right = lay.right.concat(missing)
        return out
    }

    // The default bar:
    //   LEFT    Active window, Media, Tray
    //   CENTER  Wi-Fi/Bluetooth/sound, Weather, Workspaces, Clock, Date
    //   RIGHT   Utility keys, Network speed, Screen time, Timer, Battery, Privacy, Discord call, Notification bell
    // CPU & RAM and Updates (both off by default, see SettingsService
    // "bar.resources" and "bar.updates") and Keyboard layout are listed too, so
    // a module that is switched on later lands in a sensible place; none of
    // them takes room while it is off or has nothing to show.
    readonly property var defaults: ({
        left: ["activeWindow", "media", "tray"],
        center: ["status", "weather", "workspaces", "clock", "date"],
        right: ["utilButtons", "resources", "netSpeed", "screenTime", "timer", "battery", "keyboardLayout", "privacy", "discord", "updates",
                "notifications"]
    })

    // { left: [...], center: [...], right: [...] }: the shared layout. Always
    // replaced whole, so bindings that read it update.
    property var layout: root.defaults

    // "Separate bar per monitor" (Settings -> Bar).
    readonly property bool perMonitor: SettingsService.flag("bar.perMonitor")

    // Each monitor's own bar, by output name: { "DP-1": { left, center, right,
    // off: [module ids that are off on this monitor] } }. Also always replaced
    // whole. Only read while `perMonitor` is on.
    property var screenLayouts: ({})

    // Set once the layout was changed this session, so the startup load below
    // can't land late and undo it.
    property bool touched: false

    function labelOf(id) {
        const m = root.modules.find(x => x.id === id)
        return m ? m.label : id
    }

    function iconOf(id) {
        const m = root.modules.find(x => x.id === id)
        return m ? m.icon : "widgets"
    }

    // The monitor's own bar, or null when it follows the shared one (the option
    // is off, the monitor has not been edited yet, or no name was given).
    function ownFor(name) {
        if (!root.perMonitor || !name)
            return null
        return root.screenLayouts[name] ?? null
    }

    // The layout the bar on monitor `name` is drawn from.
    function layoutFor(name) {
        return root.withPlugins(root.ownFor(name) ?? root.layout)
    }

    // Module ids that are switched off on this monitor only.
    function offFor(name) {
        const o = root.ownFor(name)
        return o ? o.off : []
    }

    // Is the module on the bar of this monitor? (Its master switch in Settings
    // and, with separate bars, this monitor's own off list.)
    function isOn(id, name) {
        return root.masterOn(id) && root.offFor(name).indexOf(id) < 0
    }

    // Which modules are on, by the names Status_Bar.qml uses (SettingsService.
    // barModules, minus what this monitor has taken off).
    function modulesFor(name) {
        const out = Object.assign({}, SettingsService.barModules)
        for (const m of PluginService.barModules)
            out[m.id] = root.masterOn(m.id)
        for (const id of root.offFor(name))
            out[id] = false
        return out
    }

    function zoneOf(id, name) {
        const lay = root.layoutFor(name)
        for (const z of root.zoneNames) {
            if (lay[z].indexOf(id) >= 0)
                return z
        }
        return "right"
    }

    // Cleans up any layout (a saved file, a script's input): unknown names go,
    // a module named twice keeps its first place, and a module that is missing
    // (added in a newer version) goes back to its default zone.
    function normalize(raw) {
        const seen = {}
        const out = { left: [], center: [], right: [] }
        for (const z of root.zoneNames) {
            const list = raw && Array.isArray(raw[z]) ? raw[z] : []
            for (const id of list) {
                if (root.keepable(id) && !seen[id]) {
                    seen[id] = true
                    out[z].push(id)
                }
            }
        }
        for (const z of root.zoneNames) {
            const dz = root.defaults[z]
            for (let i = 0; i < dz.length; i++) {
                const id = dz[i]
                if (seen[id])
                    continue
                seen[id] = true
                // Next to the module that comes before it in the default bar
                // (when that one is in this zone), so a module added in a newer
                // version doesn't end up after the clock.
                let at = out[z].length
                for (let j = i - 1; j >= 0; j--) {
                    const k = out[z].indexOf(dz[j])
                    if (k >= 0) {
                        at = k + 1
                        break
                    }
                }
                out[z].splice(at, 0, id)
            }
        }
        return out
    }

    // The saved per-monitor bars, cleaned up the same way (and `off` made a list
    // of known module names).
    function normalizeScreens(raw) {
        const out = {}
        if (!raw || typeof raw !== "object")
            return out
        for (const name of Object.keys(raw)) {
            const entry = root.normalize(raw[name])
            const off = raw[name] && Array.isArray(raw[name].off) ? raw[name].off : []
            entry.off = off.filter((id, i) => root.keepable(id) && off.indexOf(id) === i)
            out[name] = entry
        }
        return out
    }

    // What is written to bar-layout.json: the shared layout (so an older version
    // of the shell still reads the file) and, when there are any, the monitors'.
    function payload() {
        const out = { left: root.layout.left, center: root.layout.center, right: root.layout.right }
        if (Object.keys(root.screenLayouts).length > 0)
            out.screens = root.screenLayouts
        return out
    }

    function persist() {
        saver.save(JSON.stringify(root.payload()))
    }

    // Puts a whole saved bar in place (what payload() makes): the shared
    // layout and each monitor's own. Used by desktop presets
    // (DesktopPresetService.qml). Cleaned up like a file read at startup.
    function applyPayload(raw) {
        if (!raw || typeof raw !== "object")
            return
        root.touched = true
        root.layout = root.normalize(raw)
        root.screenLayouts = root.normalizeScreens(raw.screens)
        root.persist()
    }

    // ===== editing =====
    function editsOwn(name) {
        return root.perMonitor && !!name
    }

    // A monitor's bar as a fresh object an edit can change: its own, or a copy
    // of the shared one for a monitor that has not been edited yet.
    function copyFor(name) {
        const src = root.layoutFor(name)
        return {
            left: src.left.slice(),
            center: src.center.slice(),
            right: src.right.slice(),
            off: (src.off ?? []).slice()
        }
    }

    // Stores a monitor's new bar and writes everything to disk.
    function commit(name, next) {
        root.touched = true
        if (root.editsOwn(name)) {
            const all = Object.assign({}, root.screenLayouts)
            all[name] = next
            root.screenLayouts = all
        } else {
            root.layout = { left: next.left, center: next.center, right: next.right }
        }
        root.persist()
    }

    // Puts a module into `zone` at `index` (0 = first; past the end = last).
    function move(id, zone, index, screenName) {
        if (root.zoneNames.indexOf(zone) < 0 || !root.modules.some(m => m.id === id))
            return
        const name = screenName || ""
        const next = root.copyFor(name)
        for (const z of root.zoneNames)
            next[z] = next[z].filter(x => x !== id)
        const at = Math.max(0, Math.min(next[zone].length, Math.round(index)))
        next[zone].splice(at, 0, id)
        root.commit(name, next)
    }

    // Takes a module off the bar of a monitor (`off` true) or puts it back.
    // With separate bars that is only this monitor's bar; otherwise it is the
    // Settings switch (Bar -> Modules), the same one as always.
    //
    // A module that the Settings switch has turned off everywhere stays off on
    // the other monitors when it is put back on this one, so editing one bar
    // never changes another.
    function setOff(id, off, screenName) {
        if (!root.modules.some(m => m.id === id))
            return
        const name = screenName || ""
        if (!root.editsOwn(name)) {
            root.setMaster(id, !off)
            return
        }
        const wasOnEverywhere = root.masterOn(id)
        const next = root.copyFor(name)
        next.off = next.off.filter(x => x !== id)
        if (off)
            next.off.push(id)
        root.touched = true
        const all = Object.assign({}, root.screenLayouts)
        all[name] = next
        if (!off && !wasOnEverywhere) {
            for (const s of Quickshell.screens) {
                if (s.name === name)
                    continue
                const other = root.copyFor(s.name)
                if (other.off.indexOf(id) < 0)
                    other.off.push(id)
                all[s.name] = other
            }
            root.setMaster(id, true)
        }
        root.screenLayouts = all
        root.persist()
    }

    // The order only: back to the default for a monitor (or for the shared layout).
    function reset(screenName) {
        const name = screenName || ""
        const next = root.normalize(root.defaults)
        next.off = root.copyFor(name).off
        root.commit(name, next)
    }

    // Is this module on the default bar? (Its switch in Settings -> Bar ->
    // Modules is on unless the defaults say otherwise: CPU & RAM and Updates
    // are off.)
    function onByDefault(id) {
        if (root.isPlugin(id))
            return false
        return SettingsService.defaults["bar." + id] !== false
    }

    // Edit Desktop's RESET: the default order AND every module of the default
    // bar back on the bar of that monitor. A module that is off in the default
    // bar (CPU & RAM, Updates) is left as it is. Other monitors' bars stay as they are.
    function resetAll(screenName) {
        const name = screenName || ""
        if (!root.editsOwn(name)) {
            root.reset("")
            for (const m of root.modules) {
                if (root.onByDefault(m.id))
                    root.setMaster(m.id, true)
            }
            return
        }
        root.touched = true
        const all = Object.assign({}, root.screenLayouts)
        const offEverywhere = root.modules.map(m => m.id)
            .filter(id => root.onByDefault(id) && !root.masterOn(id))
        for (const s of Quickshell.screens) {
            if (s.name === name)
                continue
            const other = root.copyFor(s.name)
            for (const id of offEverywhere) {
                if (other.off.indexOf(id) < 0)
                    other.off.push(id)
            }
            all[s.name] = other
        }
        const mine = root.normalize(root.defaults)
        mine.off = []
        all[name] = mine
        for (const id of offEverywhere)
            root.setMaster(id, true)
        root.screenLayouts = all
        root.persist()
    }

    // Edit Desktop's CLEAR ALL: every module off the bar of that monitor. They
    // keep their zones, so the OFF lane (or RESET) puts them back where they
    // were. With separate bars that is only this monitor's bar; otherwise it is
    // the Settings switches (Bar -> Modules), the same ones a single module
    // uses when it is taken off.
    function clearAll(screenName) {
        const name = screenName || ""
        const ids = root.modules.map(m => m.id)
        if (!root.editsOwn(name)) {
            for (const id of ids)
                root.setMaster(id, false)
            return
        }
        const next = root.copyFor(name)
        next.off = ids
        root.touched = true
        const all = Object.assign({}, root.screenLayouts)
        all[name] = next
        root.screenLayouts = all
        root.persist()
    }

    // True when the monitor's bar is not the default one (the shared layout when
    // no monitor is given or the option is off).
    // Plugin modules are left out of the comparison: the default bar has none, and one that
    // was only appended (withPlugins) is not a change the user made.
    function customizedFor(name) {
        return root.builtinOrder(root.layoutFor(name)) !== JSON.stringify(root.defaults)
    }

    function builtinOrder(lay) {
        const f = list => list.filter(id => !root.isPlugin(id))
        return JSON.stringify({ left: f(lay.left), center: f(lay.center), right: f(lay.right) })
    }

    // True when the shared layout is not the default one.
    readonly property bool customized: root.builtinOrder(root.layout) !== JSON.stringify(root.defaults)

    // ===== persistence =====
    readonly property string script: Directories.script("state/barlayout-state.sh")

    // Runs once, at startup.
    Process {
        running: true
        command: ["sh", root.script, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.touched || text.trim() === "")
                    return
                try {
                    const raw = JSON.parse(text)
                    root.layout = root.normalize(raw)
                    root.screenLayouts = root.normalizeScreens(raw.screens)
                } catch (e) {
                    console.warn("BarLayoutService: couldn't read bar-layout.json (" + e + ") — using the default bar")
                }
            }
        }
    }

    Process {
        id: saver

        property string pending: ""

        function save(json) {
            if (saver.running) {
                saver.pending = json
                return
            }
            saver.pending = ""
            saver.exec(["sh", root.script, "save", json])
        }

        onExited: {
            if (saver.pending !== "") {
                const json = saver.pending
                saver.pending = ""
                saver.exec(["sh", root.script, "save", json])
            }
        }
    }

    IpcHandler {
        target: "barlayout"

        function get(): string {
            return JSON.stringify(root.payload())
        }

        function move(id: string, zone: string, index: int): void {
            root.move(id, zone, index, "")
        }

        function reset(): void {
            root.reset("")
        }

        function clearall(): void {
            root.clearAll("")
        }

        // These two need "Separate bar per monitor" on; otherwise they change
        // the shared layout, same as move / reset.
        function movescreen(screen: string, id: string, zone: string, index: int): void {
            root.move(id, zone, index, screen)
        }

        function resetscreen(screen: string): void {
            root.reset(screen)
        }
    }
}
