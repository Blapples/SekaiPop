import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode

// The App Dock: a floating pill on any screen edge (Settings -> Desktop -> Dock ->
// Position) holding pinned-app keys, folders and separators, PLUS one key per
// running app that isn't pinned (it goes away again when its last window closes),
// then the dock pin button and a small media player.
//
// WHAT IT DOES (the macOS dock's tricks, in this shell's own sticker style)
//   Magnification     keys grow under the pointer, biggest at the pointer and
//                     smaller the further away, and the neighbours slide aside to
//                     make room; the pill widens with them. (Settings: on/off, how big.)
//   Running dots      a small diamond under an app that is open: mint = open, cyan =
//                     the one you are in, hollow = open but every window minimized.
//   Notification      a red count on the key of an app with notifications waiting
//   badges            in the Quick Panel.
//   Minimize          click the key of the app you are in to minimize its window (it
//                     goes to a hidden workspace, see services/DockService.qml); click
//                     the key again, or the tile in the window overview, to bring it back.
//   Pin / remove /    right-click a key for the menu. Drag a pinned key along the dock
//   reorder           to reorder, drag a running app into the pinned part to pin it,
//                     drag a pinned key off the dock to remove it, drop an app on a
//                     folder to put it inside.
//   Hiding            Off, Auto-hide (slides away until the pointer hits the edge) or
//                     Smart hide (only while a window is in its way).
//   Position          bottom / top / left / right, and the icon size.
//   Folders, groups,  a folder is one key that opens a card of apps; a separator
//   layouts           between pinned keys makes groups; the whole arrangement can be
//                     saved as a named layout and switched (services/PinnedAppsService.qml).
//   Tools             Search (opens the launcher), Files (your file manager), Clipboard (the last
//                     copies), Shelf (drop files or text on it, pick them up later) and Timer
//                     (timer, stopwatch, pomodoro; the key shows the time left). They are keys
//                     like the apps: drag to reorder, drag off to remove, add back from the
//                     pin button's right-click menu or Settings. A folder's name is edited on
//                     its card (the pencil) or from its right-click menu.
//   Media             a small player at the end of the dock: click plays / pauses,
//                     right-click skips, the wheel changes the volume, pointing at it opens
//                     a card with cover, title, controls and progress.
//
// The keys still say what an app is doing the keyboard way too (they are keycaps):
// the app you are in is held down, a pinned app that isn't running is grey, an app
// with several windows has sheets peeking out behind its key, pointing at a running
// app opens the WINDOW OVERVIEW (a live picture of each window; click one to jump
// to it, middle-click or the x closes it, the - minimizes) and the wheel over a key
// flips through that app's windows.
//
// Always on screen — not a toggle-with-a-keybind overlay like Overview/QuickPanel —
// so this is a plain PanelWindow, closer to Bar.qml, anchored to its edge and
// floating: exclusionMode Ignore means it never reserves space (unless pinned), so
// it sits over tiled windows instead of pushing them. One window per dock:
// shell.qml builds one on the first monitor, or (Settings -> Desktop -> Dock -> Dock
// on every monitor) one per monitor. With one per monitor, an app that is not pinned
// only gets a key on the dock of the monitor its window is on; pinned apps are on
// every dock. The edge arrives through modelData and is fixed for the life of the
// window (a move builds a fresh one). On the left / right edge the pill stands up
// and its keys run in a column.
//
// HOW THE ROW IS LAID OUT. Everything in the pill is one list (`rowItems`) drawn by
// one Repeater and placed by this file (not by a Grid): the keys' positions have to
// be known up front to work out the magnification (`magData`) in one pass.
PanelWindow {
    id: dockWindow

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    // One entry of shell.qml's dock model: { screen, position, perMonitor }.
    required property var modelData
    screen: modelData.screen

    // The notification daemon (NotificationSource.qml), for the badges. Given by shell.qml.
    property var notificationSource: null
    // The Quick Panel (QuickPanel.qml, whose Apps screen is the launcher) and the old Overview board, for the Search key (and
    // "more in search" on the clipboard card). Given by shell.qml.
    property var launcher: null
    property var overviewBoard: null

    // bottom | top | left | right
    readonly property string position: modelData.position
    readonly property bool vertical: dockWindow.position === "left" || dockWindow.position === "right"
    // How the dock is drawn (Settings -> Desktop -> Dock -> Style, Edit Desktop's DOCK tab):
    //   float        the rounded, outlined pill (what it always was)
    //   transparent  no background at all: the keys sit straight on the wallpaper
    //   capsule      a fully rounded body in a thin rim, like the Capsule bar
    // Only the pill's background changes; its size, and so every place and hit
    // area worked out from it, stays the same in all three.
    readonly property string look: {
        const v = SettingsService.get("dock.style")
        return (v === "transparent" || v === "capsule") ? v : "float"
    }
    // In Capsule the keys are drawn to match the Capsule bar too: each one a flat round
    // chip with a thin ring in the bar's rim colour (no navy outline, no hard shadow), lit
    // with the bar's theme colour (Theme.capLit) instead of mint / cyan, its glyphs in the bar's ink, and
    // the running mark a round dot like the bar's workspace dots.
    readonly property bool capKeys: dockWindow.look === "capsule"
    readonly property real keyRing: dockWindow.capKeys ? mt.capDotRing : 7
    function ringTop(on) {
        return dockWindow.capKeys ? (on ? mt.capLit : mt.capRim)
                                  : (on ? mt.accentMint : mt.ringWhite)
    }
    function ringBottom(on) {
        return dockWindow.capKeys ? (on ? mt.capLit : mt.capRim)
                                  : (on ? mt.accentCyan : mt.ringWhite)
    }
    readonly property bool perMonitor: modelData.perMonitor === true
    // +1 / -1: which way is "toward the middle of the screen" along the axis across the dock.
    readonly property int inward: (dockWindow.position === "bottom" || dockWindow.position === "right") ? -1 : 1
    // The dock's own edge (the side the keys grow away from when magnified).
    readonly property int outerEdge: dockWindow.position === "bottom" ? Item.Bottom
        : (dockWindow.position === "top" ? Item.Top : (dockWindow.position === "left" ? Item.Left : Item.Right))

    // This monitor's scale (scale.json / services/ShellScale.qml). The sizes below
    // are design pixels: the window is that times uiScale, and the pill is drawn
    // inside a ScaleHost so everything in it follows.
    readonly property real uiScale: ShellScale.forScreen(dockWindow.screen)

    // ===== settings =====
    readonly property int iconSize: Math.max(24, Math.min(64, Math.round(SettingsService.get("dock.iconSize"))))
    readonly property bool indicatorsOn: SettingsService.flag("dock.indicators")
    readonly property bool badgesOn: SettingsService.flag("dock.badges")
    readonly property bool clickMinimizes: SettingsService.flag("dock.clickMinimizes")
    readonly property bool mediaOn: SettingsService.flag("dock.media")
    readonly property real magMax: SettingsService.flag("dock.magnify")
        ? Math.max(1, SettingsService.get("dock.magnifyAmount") / 100) : 1
    readonly property bool magOn: dockWindow.magMax > 1.001
    // off | auto | smart (the old on/off "Auto-hide" switch still counts as auto).
    readonly property string hideMode: {
        const m = SettingsService.get("dock.hideMode")
        if (m === "auto" || m === "smart")
            return m
        return SettingsService.flag("dock.autoHide") ? "auto" : "off"
    }

    // The keys: 35 design pixels by default, with the same 61 total height as the
    // bar (35 + 11*2 + the 4 of hard shadow). With running dots the pill is 6 taller
    // each side to leave room for the dot under the key.
    readonly property int iconGap: 12
    readonly property int pillPaddingH: 18
    readonly property int pillPaddingV: 11 + (dockWindow.indicatorsOn ? 6 : 0)
    readonly property int dockDividerWidth: 4

    // Same Lua/non-Lua fork Bar.qml uses for its own dispatches — see its comment
    // on `usingLua` for why only an explicit `false` counts as "not Lua".
    readonly property bool usingLua: Hyprland.usingLua !== false

    // A toplevel's window class / app id ("org.mozilla.firefox", "kitty"...), same
    // fallback chain as Bar.qml's `windowClass`.
    function toplevelClass(t) {
        return t.wayland?.appId
            || t.lastIpcObject?.class
            || t.lastIpcObject?.initialClass
            || ""
    }

    // Opens an app from its class: heuristicLookup guesses the desktop entry (it only
    // ever guesses) and its Exec line runs via DesktopEntry.execute().
    function launchApp(cls) {
        if (!cls)
            return
        let entry = null
        try {
            entry = DesktopEntries.heuristicLookup(cls)
        } catch (e) {}
        if (entry)
            entry.execute()
        else
            console.warn("Dock.qml: no desktop entry found to launch for class:", cls)
    }

    // ===== who is running =====
    // Every open window, by class (one entry per class, so two Firefox windows
    // still take one key), and the same for the windows on THIS dock's monitor
    // only. Each entry is { address, workspaceId, count, minCount, min, toplevel,
    // wins }: the first four describe the window a click goes to (the focused one,
    // else the first that isn't minimized), `count` is the number of windows,
    // `minCount` how many of them are minimized and `wins` all of them
    // ({ address, workspaceId, active, min, toplevel }, for the wheel and the
    // overview). `focused` is the class of the window that has the focus right now
    // ("" if none): its key is held down.
    function addWin(map, cls, t) {
        const wsId = t.workspace?.id ?? null
        const min = DockService.isMinimized(t)
        let e = map[cls]
        if (!e) {
            e = { address: t.address, workspaceId: wsId, count: 0, minCount: 0, min: min, toplevel: t, wins: [] }
            map[cls] = e
        }
        e.count += 1
        if (min)
            e.minCount += 1
        e.wins.push({ address: t.address, workspaceId: wsId, active: t.activated === true, min: min, toplevel: t })
        if (t.activated || (e.min && !min)) {
            e.address = t.address
            e.workspaceId = wsId
            e.min = min
            e.toplevel = t
        }
    }

    readonly property var runningMaps: {
        const all = {}
        const local = {}
        let focused = ""
        const here = dockWindow.screen ? dockWindow.screen.name : ""
        for (const t of Hyprland.toplevels.values) {
            const cls = dockWindow.toplevelClass(t)
            if (cls === "")
                continue
            const onHere = here !== "" && t.workspace?.monitor?.name === here
            dockWindow.addWin(all, cls, t)
            if (onHere)
                dockWindow.addWin(local, cls, t)
            if (t.activated && (!dockWindow.perMonitor || here === "" || onHere))
                focused = cls
        }
        return { all: all, local: local, focused: focused }
    }

    // What the dock lists as running: every window, or (a dock per monitor) only
    // the ones on this monitor.
    readonly property var runningByClass: dockWindow.perMonitor ? dockWindow.runningMaps.local
                                                                 : dockWindow.runningMaps.all

    // A pinned app counts as running if it is open anywhere (a window on this
    // monitor is the one a click goes to); an unpinned one is only here because it
    // is running.
    function infoFor(cls, pinned) {
        return pinned
            ? (dockWindow.runningMaps.local[cls] ?? dockWindow.runningMaps.all[cls] ?? null)
            : (dockWindow.runningByClass[cls] ?? null)
    }

    // ===== switching, minimizing, closing =====
    // Switch to a window: a minimized one comes back first; otherwise its workspace
    // first, then the window itself (two dispatches: `focuswindow` alone was
    // inconsistent about actually switching you there).
    function focusWin(w) {
        if (!w || !w.address)
            return
        if (w.min === true) {
            DockService.restore(w.toplevel, true)
            return
        }
        DockService.focusAddress(w.address, w.workspaceId)
    }

    function minimizeWin(w) {
        if (w && w.toplevel)
            DockService.minimize(w.toplevel)
    }

    function minimizeAll(info) {
        if (!info)
            return
        for (const w of info.wins)
            if (!w.min)
                DockService.minimize(w.toplevel)
    }

    function restoreAll(info) {
        if (!info)
            return
        let first = true
        for (const w of info.wins) {
            if (w.min) {
                DockService.restore(w.toplevel, first)
                first = false
            }
        }
    }

    function closeAll(info) {
        if (!info)
            return
        for (const w of info.wins)
            dockWindow.closeWin(w.address)
    }

    // Closing a window (the same dispatch the Overview uses). The address goes through
    // DockService.hexAddr first: Quickshell's toplevel address can lack the "0x" Hyprland
    // needs, and then the close finds no window and silently does nothing.
    function closeWin(rawAddress) {
        const address = DockService.hexAddr(rawAddress)
        if (address === "")
            return
        Hyprland.dispatch(dockWindow.usingLua
            ? "hl.dsp.window.close({ window = \"address:" + address + "\" })"
            : "closewindow address:" + address)
    }

    // The wheel over a key: the next / previous window of that app.
    function cycleWindows(info, dir) {
        if (!info || !info.wins || info.wins.length < 2)
            return
        const n = info.wins.length
        let cur = info.wins.findIndex(w => w.active)
        if (cur < 0)
            cur = dir > 0 ? -1 : 0
        dockWindow.focusWin(info.wins[(cur + dir + n) % n])
    }

    // The name on a key's flag: the .desktop entry's name when there is one.
    function appName(cls, fallback) {
        let entry = null
        try {
            entry = DesktopEntries.heuristicLookup(cls)
        } catch (e) {}
        return (entry && entry.name) || fallback
    }

    // ===== notification badges =====
    // A notification belongs to a key when the app's desktop entry / name matches
    // the key's class, icon or name (everything lower-cased, ".desktop" and the
    // "org.mozilla." part of a reverse-domain id ignored).
    function normKey(s) {
        return String(s === undefined || s === null ? "" : s).toLowerCase().replace(/\.desktop$/, "").trim()
    }

    function keysOf(list) {
        const out = []
        for (const raw of list) {
            const k = dockWindow.normKey(raw)
            if (k === "")
                continue
            out.push(k)
            const parts = k.split(".")
            if (parts.length > 1)
                out.push(parts[parts.length - 1])
        }
        return out
    }

    readonly property var notifKeys: {
        const src = dockWindow.notificationSource
        if (!src || !src.entries)
            return []
        return src.entries.map(e => dockWindow.keysOf([e.desktopEntry, e.app]))
    }

    function notifCount(desc) {
        if (!dockWindow.badgesOn || dockWindow.notifKeys.length === 0)
            return 0
        const classes = desc.kind === "folder" ? desc.apps : [desc]
        let mine = []
        for (const a of classes)
            mine = mine.concat(dockWindow.keysOf([a.class, a.iconName, a.displayName]))
        if (mine.length === 0)
            return 0
        let n = 0
        for (const ek of dockWindow.notifKeys)
            if (ek.some(k => mine.includes(k)))
                n++
        return n
    }

    // ===== the row: what is in the dock, in order =====
    readonly property var pinnedClasses: PinnedAppsService.allApps().map(a => a.class)

    // The built-in tools (services/PinnedAppsService.qml puts them in the layout).
    readonly property var toolMeta: ({
        search: { label: "Search", icon: "search" },
        files: { label: "Files", icon: "folder" },
        clipboard: { label: "Clipboard", icon: "content_paste" },
        shelf: { label: "Shelf", icon: "inventory_2" },
        timer: { label: "Timer", icon: "timer" }
    })

    // Pinned items, in the order they are saved (which is the order they stand in).
    // Only what stays the same lives here; whether the app is running, how many
    // windows it has and whether it has the focus are read by each key itself, so a
    // change of focus never rebuilds the keys (a rebuilt key could not spring).
    //
    // An app switched OFF in Edit Desktop -> DOCK -> APPS (`hidden`) leaves no key. Its
    // `pinIndex` is still its place in the saved layout, so a key's row number and its
    // pinIndex can differ: anything that edits the layout goes by pinIndex (see endDrag).
    function slotFor(item, i) {
        const k = PinnedAppsService.kindOf(item)
        if (k === "sep")
            return { kind: "sep", key: "sep" + i, pinned: true, pinIndex: i }
        if (k === "tool") {
            const m = dockWindow.toolMeta[item.id] ?? { label: item.id, icon: "build" }
            return { kind: "tool", key: "tool" + item.id, pinned: true, pinIndex: i,
                     tool: item.id, class: "", iconName: "", displayName: m.label }
        }
        if (k === "folder") {
            const shown = item.apps.filter(a => a.hidden !== true)
            if (shown.length === 0)
                return null
            return {
                kind: "folder", key: "folder" + i, pinned: true, pinIndex: i,
                class: "", iconName: "folder", displayName: item.name, name: item.name,
                apps: shown.map(a => ({
                    class: a.class, iconName: a.iconName,
                    displayName: dockWindow.appName(a.class, a.iconName)
                }))
            }
        }
        if (item.hidden === true)
            return null
        return {
            kind: "app", key: "app" + item.class, pinned: true, pinIndex: i,
            class: item.class, iconName: item.iconName,
            displayName: dockWindow.appName(item.class, item.iconName)
        }
    }

    readonly property var pinnedSlots: {
        const out = []
        // Something was left out since the last key. A separator that would then stand first,
        // or right after another separator, or last, has nothing to divide: it is left out too.
        let skipped = false
        PinnedAppsService.pinned.forEach((item, i) => {
            const s = dockWindow.slotFor(item, i)
            if (s === null) {
                skipped = true
                return
            }
            if (s.kind === "sep" && skipped && (out.length === 0 || out[out.length - 1].kind === "sep"))
                return
            out.push(s)
            skipped = false
        })
        if (skipped && out.length > 0 && out[out.length - 1].kind === "sep")
            out.pop()
        return out
    }

    // One key per running app that ISN'T pinned. Icon + display name come from the
    // .desktop entry when there is one. Kept (not a binding) so the list is only
    // replaced when an app starts or stops being listed, and an app keeps its place
    // while it stays open.
    property var autoSlots: []

    function refreshAutoSlots() {
        const live = []
        for (const cls in dockWindow.runningByClass) {
            if (!dockWindow.pinnedClasses.includes(cls))
                live.push(cls)
        }
        const prev = dockWindow.autoSlots
        const kept = prev.map(a => a.class).filter(c => live.includes(c))
        const next = kept.concat(live.filter(c => !kept.includes(c)))
        if (next.length === prev.length && next.every((c, i) => prev[i].class === c))
            return
        dockWindow.autoSlots = next.map(cls => {
            let entry = null
            try {
                entry = DesktopEntries.heuristicLookup(cls)
            } catch (e) {}
            return {
                kind: "app", key: "auto" + cls, pinned: false, pinIndex: -1,
                class: cls,
                iconName: (entry && entry.icon) || cls,
                displayName: (entry && entry.name) || cls
            }
        })
    }

    onRunningByClassChanged: dockWindow.refreshAutoSlots()
    onPinnedClassesChanged: dockWindow.refreshAutoSlots()

    // The player at the end of the dock (the bar has its own MediaSource too —
    // cheap enough not to bother sharing).
    MediaSource {
        id: media
    }
    readonly property bool mediaShown: dockWindow.mediaOn && media.present

    readonly property int pinnedCount: dockWindow.pinnedSlots.length

    // Everything the pill holds, in order: the pinned items, a divider, the
    // unpinned running apps, a divider, the dock-pin button, and (when something is
    // playing) a divider and the media key. `kind`: app | folder | sep | divider |
    // pin | media.
    readonly property var rowItems: {
        const out = []
        for (const s of dockWindow.pinnedSlots)
            out.push(s)
        if (dockWindow.pinnedSlots.length > 0 && dockWindow.autoSlots.length > 0)
            out.push({ kind: "divider", key: "div1" })
        for (const s of dockWindow.autoSlots)
            out.push(s)
        if (out.length > 0)
            out.push({ kind: "divider", key: "div2" })
        out.push({ kind: "pin", key: "pin" })
        if (dockWindow.mediaShown) {
            out.push({ kind: "divider", key: "div3" })
            out.push({ kind: "media", key: "media" })
        }
        return out
    }

    // How much room an item takes along the dock. A key on a standing dock counts
    // its hard shadow, which sits under it.
    readonly property real keyAlong: dockWindow.vertical ? dockWindow.iconSize + mt.shadowOffset : dockWindow.iconSize
    function sizeOf(desc) {
        if (desc.kind === "media" && dockWindow.mediaWide)
            return dockWindow.mediaWidth
        return (desc.kind === "divider" || desc.kind === "sep") ? dockWindow.dockDividerWidth : dockWindow.keyAlong
    }

    // ===== the long media pill =====
    // A dock along the top or bottom gives the media key a long pill: cover and title
    // on the left, previous / play-pause / next on the right. A standing dock (left or
    // right) keeps the small square key, which opens the media card on hover.
    readonly property bool mediaWide: !dockWindow.vertical
    readonly property real mediaWidth: Math.max(300, Math.round(dockWindow.iconSize * 8.2))
    // The pill is taller than the keys: it grows into the dock's padding above and below
    // them (keeping 4px of it clear), so the cover, text and buttons have room.
    readonly property real mediaGrow: Math.max(0, Math.min(10, dockWindow.pillPaddingV - 4))
    readonly property real mediaHeight: dockWindow.iconSize + dockWindow.mediaGrow * 2
    // (Capsule: the same thin ring the other keys have.)
    readonly property real mediaRing: dockWindow.capKeys ? mt.capDotRing : 6
    readonly property real mediaInnerH: Math.max(10, dockWindow.mediaHeight - dockWindow.mediaRing * 2)
    // The three buttons: size, the gap between them, and the room kept to the pill's inner right edge.
    readonly property real mediaBtn: Math.max(16, Math.min(38, dockWindow.mediaInnerH - 10))
    readonly property real mediaBtnGap: 4
    readonly property real mediaPadR: 6
    readonly property int mediaIndex: dockWindow.rowItems.findIndex(r => r.kind === "media")
    // The pointer along the row, as it is (magPointer is smoothed), for the buttons.
    property real pointerAlong: -1000

    // Where along the media pill the pointer is, in design pixels from its left edge.
    function mediaLocal(a) {
        const i = dockWindow.mediaIndex
        if (i < 0)
            return -1000
        return a - (dockWindow.rowPos[i] + (dockWindow.magData.shifts[i] ?? 0))
    }

    // Which part of the long pill a spot is on: prev | play | next | body.
    function mediaZone(local) {
        const b = dockWindow.mediaBtn
        const g = dockWindow.mediaBtnGap
        const right = dockWindow.mediaWidth - dockWindow.mediaRing - dockWindow.mediaPadR
        const nextL = right - b
        const playL = nextL - g - b
        const prevL = playL - g - b
        if (local >= nextL - g / 2)
            return "next"
        if (local >= playL - g / 2)
            return "play"
        if (local >= prevL - g / 2)
            return "prev"
        return "body"
    }

    function mediaPress(zone) {
        if (zone === "prev")
            media.previous()
        else if (zone === "next")
            media.next()
        else
            media.togglePlaying()
    }

    // Where each item starts along the row, and how long the row is.
    readonly property var rowPos: {
        const out = []
        let p = 0
        for (const d of dockWindow.rowItems) {
            out.push(p)
            p += dockWindow.sizeOf(d) + dockWindow.iconGap
        }
        return out
    }
    readonly property real rowLen: dockWindow.rowItems.length === 0 ? 0
        : dockWindow.rowPos[dockWindow.rowItems.length - 1]
          + dockWindow.sizeOf(dockWindow.rowItems[dockWindow.rowItems.length - 1])

    function isKeyKind(kind) {
        return kind === "app" || kind === "folder"
    }

    function centerOf(i) {
        return dockWindow.rowPos[i] + dockWindow.sizeOf(dockWindow.rowItems[i]) / 2
    }

    // ===== magnification =====
    // `magPointer` is where the pointer is along the row (smoothed), `magAmount`
    // fades the whole thing in and out. A key at distance d from the pointer grows
    // to 1 + (max - 1) * bump(d / radius), a smooth hump (cosine) that is 0 beyond
    // the radius. The grown keys need room: every item moves along by half of its
    // own growth plus all the growth of the keys before it, less half of the total
    // (the row stays centred), so the gap between neighbours stays exactly iconGap.
    property real magPointer: -1000
    property real magAmount: (hit.containsMouse && !dockWindow.dragging && dockWindow.revealed && !dockWindow.editing) ? 1 : 0
    // Entering the dock jumps straight to the pointer; after that it follows smoothly.
    Behavior on magPointer {
        enabled: dockWindow.magAmount > 0.3
        NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
    }
    Behavior on magAmount {
        NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
    }
    readonly property real magRadius: (dockWindow.iconSize + dockWindow.iconGap) * 2.2

    function magScaleAt(c) {
        if (!dockWindow.magOn || dockWindow.magAmount < 0.001)
            return 1
        const d = Math.abs(dockWindow.magPointer - c) / dockWindow.magRadius
        if (d >= 1)
            return 1
        return 1 + (dockWindow.magMax - 1) * dockWindow.magAmount * (0.5 + 0.5 * Math.cos(Math.PI * d))
    }

    // scales[i], shifts[i] for every item of the row, the total growth and the
    // biggest scale (how far the keys stick out past the pill).
    readonly property var magData: {
        const rows = dockWindow.rowItems
        const n = rows.length
        const scales = new Array(n)
        const extras = new Array(n)
        let total = 0
        let peak = 1
        for (let i = 0; i < n; i++) {
            const k = rows[i].kind
            const s = (k === "app" || k === "folder" || (k === "media" && !dockWindow.mediaWide) || k === "tool")
                ? dockWindow.magScaleAt(dockWindow.centerOf(i)) : 1
            scales[i] = s
            extras[i] = (s - 1) * dockWindow.iconSize
            total += extras[i]
            if (s > peak)
                peak = s
        }
        const shifts = new Array(n)
        let acc = 0
        for (let i = 0; i < n; i++) {
            shifts[i] = acc + extras[i] / 2 - total / 2
            acc += extras[i]
        }
        return { scales: scales, shifts: shifts, total: total, peak: peak }
    }

    // How far the biggest key sticks out past the pill, design pixels.
    readonly property real magLift: (dockWindow.magData.peak - 1) * (dockWindow.iconSize + mt.shadowOffset)

    // ===== the pointer =====
    // Which item the pointer is on (an index into rowItems, -1 for none), worked
    // out from where the items really are on screen (shifted and grown by the
    // magnification), not from where they would stand at rest.
    property int hoverIdx: -1

    function indexAt(along) {
        const rows = dockWindow.rowItems
        const md = dockWindow.magData
        for (let i = 0; i < rows.length; i++) {
            const sz = dockWindow.sizeOf(rows[i])
            const c = dockWindow.rowPos[i] + sz / 2 + (md.shifts[i] ?? 0)
            const half = sz * (md.scales[i] ?? 1) / 2 + dockWindow.iconGap / 2
            if (Math.abs(along - c) <= half)
                return i
        }
        return -1
    }

    // Something under the pointer that does something when clicked.
    readonly property bool hoverClickable: {
        const r = dockWindow.rowItems[dockWindow.hoverIdx]
        return r !== undefined && r.kind !== "divider"
    }

    // ===== dragging a key =====
    property bool dragging: false
    property int dragIdx: -1
    property real dragAlong: 0
    property int dragTarget: -1
    property bool dragRemove: false
    // A folder key the dragged app is over (row index), -1 for none.
    property int dragFolderRow: -1
    readonly property real removeDistance: 60

    function startDrag(idx) {
        dockWindow.dragging = true
        dockWindow.dragIdx = idx
        dockWindow.dragTarget = idx
        dockWindow.dragRemove = false
        dockWindow.dragFolderRow = -1
        dockWindow.closePopups()
    }

    // `along`: the pointer along the row; `out`: how far it is past the dock's
    // inward side (negative while it is still on the dock).
    function dragMove(along, out) {
        const rows = dockWindow.rowItems
        const from = dockWindow.dragIdx
        if (from < 0 || from >= rows.length)
            return
        const row = rows[from]
        const fromPinned = from < dockWindow.pinnedCount
        dockWindow.dragAlong = along
        dockWindow.dragRemove = fromPinned && row.kind !== "folder" && out > dockWindow.removeDistance
        if (dockWindow.dragRemove) {
            dockWindow.dragFolderRow = -1
            return
        }
        // Over a folder: the app goes in, instead of changing places.
        let folderRow = -1
        if (row.kind === "app") {
            for (let i = 0; i < dockWindow.pinnedCount; i++) {
                if (i !== from && rows[i].kind === "folder"
                        && Math.abs(along - dockWindow.centerOf(i)) < dockWindow.iconSize * 0.34)
                    folderRow = i
            }
        }
        dockWindow.dragFolderRow = folderRow
        if (fromPinned) {
            let best = from
            let bestD = 1e9
            for (let i = 0; i < dockWindow.pinnedCount; i++) {
                const d = Math.abs(along - dockWindow.centerOf(i))
                if (d < bestD) {
                    bestD = d
                    best = i
                }
            }
            dockWindow.dragTarget = best
        } else {
            let t = 0
            for (let i = 0; i < dockWindow.pinnedCount; i++)
                if (dockWindow.centerOf(i) < along)
                    t = i + 1
            dockWindow.dragTarget = t
        }
    }

    function endDrag() {
        const rows = dockWindow.rowItems
        const from = dockWindow.dragIdx
        const row = from >= 0 && from < rows.length ? rows[from] : null
        const fromPinned = from < dockWindow.pinnedCount
        const target = dockWindow.dragTarget
        const remove = dockWindow.dragRemove
        const folderRow = dockWindow.dragFolderRow
        dockWindow.dragging = false
        dockWindow.dragIdx = -1
        dockWindow.dragTarget = -1
        dockWindow.dragRemove = false
        dockWindow.dragFolderRow = -1
        if (!row)
            return
        if (remove) {
            if (row.kind === "app")
                PinnedAppsService.unpin(row.class)
            else if (row.kind === "sep" || row.kind === "tool")
                PinnedAppsService.removeAt(row.pinIndex)
        } else if (folderRow >= 0) {
            PinnedAppsService.addToFolder(rows[folderRow].pinIndex, row.class, row.iconName)
        } else if (fromPinned) {
            // Row numbers are not layout positions while an app is switched off: translate.
            if (target >= 0 && target < rows.length)
                PinnedAppsService.move(row.pinIndex, rows[target].pinIndex)
        } else if (row.kind === "app") {
            let at
            if (target >= 0 && target < dockWindow.pinnedCount)
                at = rows[target].pinIndex
            else if (dockWindow.pinnedCount > 0)
                at = rows[dockWindow.pinnedCount - 1].pinIndex + 1
            PinnedAppsService.pin(row.class, row.iconName, at)
        }
    }

    // ===== the window overview =====
    property string wantCls: ""
    property bool wantPinned: false
    property var wantSlot: null
    property bool cardOn: false
    property string cardCls: ""
    property bool cardPinned: false
    property string cardName: ""
    property string cardIcon: ""
    property var cardSlot: null
    property bool cardHovered: false
    // The pointer is on a running app's key (not an unplugged one's).
    property bool hoverRunning: false
    // Where the card points to, in the dock's design pixels (the key's centre).
    property real anchorX: 0
    property real anchorY: 0

    // Only while the dock itself is there to point from.
    readonly property bool cardVisible: dockWindow.cardOn && !dockWindow.editing && !dockWindow.tucked
                                        && !dockWindow.menuOpen && !dockWindow.folderOpen && !dockWindow.dragging
                                        && dockWindow.toolOpen === ""

    // The windows of the app the card shows, live, and the list of their addresses
    // that the card's tiles are made from. The list only changes when a window
    // opens or closes (a change of focus must not rebuild the tiles: they would
    // restart their capture).
    readonly property var cardInfo: dockWindow.cardCls === "" ? null
        : (dockWindow.cardPinned
            ? (dockWindow.runningMaps.local[dockWindow.cardCls] ?? dockWindow.runningMaps.all[dockWindow.cardCls] ?? null)
            : (dockWindow.runningByClass[dockWindow.cardCls] ?? null))
    property var cardKeys: []

    function refreshCardKeys() {
        const next = dockWindow.cardInfo ? dockWindow.cardInfo.wins.map(w => w.address) : []
        if (JSON.stringify(next) !== JSON.stringify(dockWindow.cardKeys))
            dockWindow.cardKeys = next
    }

    onCardInfoChanged: {
        dockWindow.refreshCardKeys()
        if (dockWindow.cardOn && dockWindow.cardKeys.length === 0)
            dockWindow.cardOn = false
    }

    // The centre of a key as it is drawn right now (shifted, grown), in the
    // overlay's design pixels.
    function anchorOf(slotItem) {
        const t = slotItem.anchorItem
        const pt = t.mapToItem(overlay, t.width / 2, t.height / 2)
        return pt
    }

    function placeCard() {
        const sl = dockWindow.cardSlot
        if (!sl)
            return
        const pt = dockWindow.anchorOf(sl)
        dockWindow.anchorX = pt.x
        dockWindow.anchorY = pt.y
    }

    function applyWant() {
        const sl = dockWindow.wantSlot
        if (!sl)
            return
        dockWindow.cardCls = dockWindow.wantCls
        dockWindow.cardPinned = dockWindow.wantPinned
        dockWindow.cardName = sl.modelData.displayName
        dockWindow.cardIcon = sl.modelData.iconName
        dockWindow.cardSlot = sl
        dockWindow.refreshCardKeys()
        dockWindow.placeCard()
        dockWindow.cardOn = dockWindow.cardKeys.length > 0
    }

    // The pointer came onto a running app's key.
    function previewHover(slotItem) {
        previewClose.stop()
        dockWindow.hoverRunning = true
        dockWindow.wantCls = slotItem.cls
        dockWindow.wantPinned = slotItem.modelData.pinned === true
        dockWindow.wantSlot = slotItem
        if (dockWindow.cardOn)
            dockWindow.applyWant()      // moving along the dock: switch at once
        else
            previewOpen.restart()       // a short wait, so sweeping across doesn't flash it
    }

    // The pointer left the key it was on (or is on a key that isn't running).
    function previewLeave() {
        previewOpen.stop()
        dockWindow.hoverRunning = false
        previewClose.restart()
    }

    Timer {
        id: previewOpen
        interval: 150
        onTriggered: dockWindow.applyWant()
    }

    Timer {
        id: previewClose
        interval: 280
        onTriggered: {
            if (!dockWindow.cardHovered && !dockWindow.hoverRunning)
                dockWindow.cardOn = false
        }
    }

    // ===== the media card =====
    property bool mediaKeyHot: false
    property bool mediaCardOn: false
    property bool mediaCardHovered: false
    property var mediaSlot: null
    property real mediaAnchorX: 0
    property real mediaAnchorY: 0

    function placeMedia() {
        if (!dockWindow.mediaSlot)
            return
        const pt = dockWindow.anchorOf(dockWindow.mediaSlot)
        dockWindow.mediaAnchorX = pt.x
        dockWindow.mediaAnchorY = pt.y
    }

    function mediaHover(slotItem, on) {
        // The long pill shows the player itself, so it has no card.
        if (dockWindow.mediaWide) {
            dockWindow.mediaKeyHot = false
            return
        }
        dockWindow.mediaKeyHot = on
        if (on) {
            dockWindow.mediaSlot = slotItem
            mediaClose.stop()
            mediaOpen.restart()
        } else {
            mediaOpen.stop()
            mediaClose.restart()
        }
    }

    Timer {
        id: mediaOpen
        interval: 180
        onTriggered: {
            dockWindow.placeMedia()
            dockWindow.mediaCardOn = dockWindow.mediaKeyHot
        }
    }

    Timer {
        id: mediaClose
        interval: 300
        onTriggered: {
            if (!dockWindow.mediaCardHovered && !dockWindow.mediaKeyHot)
                dockWindow.mediaCardOn = false
        }
    }

    readonly property bool mediaCardVisible: dockWindow.mediaCardOn && dockWindow.mediaShown && !dockWindow.mediaWide && !dockWindow.editing
        && !dockWindow.tucked && !dockWindow.menuOpen && !dockWindow.folderOpen && !dockWindow.dragging
        && dockWindow.toolOpen === ""

    // ===== right-click menu and folder card =====
    property bool menuOpen: false
    property var menuRows: []
    property var menuFor: null
    property real menuAnchorX: 0
    property real menuAnchorY: 0

    // The tool card that is open ("clipboard" | "shelf" | "timer" | "files" | "").
    property string toolOpen: ""
    property real toolAnchorX: 0
    property real toolAnchorY: 0

    property bool folderOpen: false
    property int folderRow: -1
    property real folderAnchorX: 0
    property real folderAnchorY: 0

    // The folder's apps, with whether each is running.
    readonly property var folderApps: {
        const r = dockWindow.rowItems[dockWindow.folderRow]
        if (!r || r.kind !== "folder")
            return []
        return r.apps.map(a => ({
            class: a.class, iconName: a.iconName, displayName: a.displayName,
            running: dockWindow.infoFor(a.class, true) !== null
        }))
    }
    readonly property string folderTitle: {
        const r = dockWindow.rowItems[dockWindow.folderRow]
        return r && r.kind === "folder" ? r.name : ""
    }

    function closePopups() {
        dockWindow.menuOpen = false
        dockWindow.folderOpen = false
        dockWindow.toolOpen = ""
        dockWindow.cardOn = false
        dockWindow.mediaCardOn = false
        previewOpen.stop()
        mediaOpen.stop()
    }

    // A click outside the dock closes whichever of the menu, the folder card or a tool's
    // card is open. The Shelf's card is the exception: it is somewhere to put things
    // down (drag a file out of a window, drop it on the shelf, drag another), so it
    // stays open while you click and work outside the dock, and only its X (or a click
    // on the Shelf key) closes it. While it is open the dock stays shown (`revealed`).
    HyprlandFocusGrab {
        windows: [dockWindow]
        active: dockWindow.menuOpen || dockWindow.folderOpen
                || (dockWindow.toolOpen !== "" && dockWindow.toolOpen !== "shelf")
        onCleared: {
            dockWindow.menuOpen = false
            dockWindow.folderOpen = false
            if (dockWindow.toolOpen !== "shelf")
                dockWindow.toolOpen = ""
        }
    }

    // Opens the right-click menu of a row.
    function openMenu(idx) {
        const r = dockWindow.rowItems[idx]
        if (!r || r.kind === "divider" || r.kind === "media")
            return
        const slot = rowRepeater.itemAt(idx)
        if (!slot)
            return
        const rows = dockWindow.buildMenu(r)
        if (rows.length === 0)
            return
        dockWindow.closePopups()
        const pt = dockWindow.anchorOf(slot)
        dockWindow.menuAnchorX = pt.x
        dockWindow.menuAnchorY = pt.y
        dockWindow.menuFor = r
        dockWindow.menuRows = rows
        dockWindow.menuOpen = true
    }

    function buildMenu(r) {
        const rows = []
        if (r.kind === "sep") {
            rows.push({ id: "removesep", label: "Remove separator", icon: "horizontal_rule" })
            return rows
        }
        if (r.kind === "tool") {
            rows.push({ header: r.displayName })
            if (r.tool === "files") {
                if (FilesStackService.stackOn) {
                    rows.push({ id: "openfiles", label: "Open file manager", icon: "open_in_new" })
                    rows.push({ sep: true })
                }
                for (const pl of [["DOWNLOAD", "Downloads", "download"], ["DOCUMENTS", "Documents", "description"],
                                  ["PICTURES", "Pictures", "image"], ["VIDEOS", "Videos", "movie"],
                                  ["MUSIC", "Music", "music_note"], ["DESKTOP", "Desktop", "desktop_windows"],
                                  ["TRASH", "Trash", "delete"]])
                    rows.push({ id: "place:" + pl[0], label: pl[1], icon: pl[2] })
                rows.push({ sep: true })
            } else if (r.tool === "shelf") {
                rows.push({ id: "shelfpaste", label: "Add what is on the clipboard", icon: "content_paste_go" })
                if (ShelfService.count > 0)
                    rows.push({ id: "shelfcopyall", label: "Copy everything on the shelf", icon: "copy_all" })
                rows.push({ id: "shelfclear", label: "Clear the shelf", icon: "delete_sweep", danger: true })
                rows.push({ sep: true })
            } else if (r.tool === "clipboard") {
                rows.push({ id: "clipwipe", label: "Clear clipboard history", icon: "delete_sweep", danger: true })
                rows.push({ sep: true })
            }
            rows.push({ id: "removetool", label: "Remove from Dock", icon: "keep_off" })
            rows.push({ id: "addsepafter", label: "Add separator after", icon: "horizontal_rule" })
            return rows
        }
        if (r.kind === "pin") {
            rows.push({ header: "Dock" })
            const active = PinnedAppsService.activePreset
            for (const name of PinnedAppsService.presetNames) {
                rows.push({
                    id: "preset:" + name, label: name,
                    icon: name === active ? "radio_button_checked" : "radio_button_unchecked"
                })
            }
            rows.push({ id: "savelayout", label: "Save layout", icon: "bookmark_add" })
            rows.push({ id: "addsepend", label: "Add separator", icon: "horizontal_rule" })
            const missing = PinnedAppsService.toolIds.filter(id => !PinnedAppsService.hasTool(id))
            if (missing.length > 0) {
                rows.push({ sep: true })
                for (const id of missing)
                    rows.push({ id: "addtool:" + id, label: "Add " + dockWindow.toolMeta[id].label, icon: dockWindow.toolMeta[id].icon })
            }
            rows.push({ sep: true })
            rows.push({ header: "Hiding" })
            rows.push({ id: "hide:off", label: "Always shown", icon: dockWindow.hideMode === "off" ? "radio_button_checked" : "radio_button_unchecked" })
            rows.push({ id: "hide:auto", label: "Auto-hide", icon: dockWindow.hideMode === "auto" ? "radio_button_checked" : "radio_button_unchecked" })
            rows.push({ id: "hide:smart", label: "Smart hide", icon: dockWindow.hideMode === "smart" ? "radio_button_checked" : "radio_button_unchecked" })
            return rows
        }
        if (r.kind === "folder") {
            rows.push({ header: r.displayName })
            rows.push({ id: "openfolder", label: "Open", icon: "folder_open" })
            rows.push({ id: "renamefolder", label: "Rename", icon: "edit" })
            rows.push({ id: "addsepafter", label: "Add separator after", icon: "horizontal_rule" })
            rows.push({ id: "deletefolder", label: "Delete folder (keep apps)", icon: "folder_delete", danger: true })
            return rows
        }
        // An app.
        const info = dockWindow.infoFor(r.class, r.pinned)
        rows.push({ header: r.displayName })
        rows.push({ id: "open", label: info ? "New window" : "Open", icon: "open_in_new" })
        if (info) {
            if (info.count - info.minCount > 0)
                rows.push({ id: "minimize", label: "Minimize", icon: "minimize" })
            if (info.minCount > 0)
                rows.push({ id: "restore", label: "Show windows", icon: "open_in_full" })
            rows.push({ id: "closeall", label: info.count > 1 ? "Close all windows" : "Close window", icon: "close", danger: true })
        }
        rows.push({ sep: true })
        if (r.pinned)
            rows.push({ id: "unpin", label: "Remove from Dock", icon: "keep_off" })
        else
            rows.push({ id: "pin", label: "Keep in Dock", icon: "keep" })
        if (r.pinned)
            rows.push({ id: "addsepafter", label: "Add separator after", icon: "horizontal_rule" })
        rows.push({ id: "newfolder", label: "New folder with this app", icon: "create_new_folder" })
        let shown = 0
        PinnedAppsService.pinned.forEach((it, i) => {
            if (PinnedAppsService.folderShown(it) && shown < 4 && !it.apps.some(a => a.class === r.class)) {
                rows.push({ id: "tofolder:" + i, label: "Add to " + it.name, icon: "folder" })
                shown++
            }
        })
        return rows
    }

    function menuPicked(id) {
        const r = dockWindow.menuFor
        dockWindow.menuOpen = false
        if (!r)
            return
        const info = r.kind === "app" ? dockWindow.infoFor(r.class, r.pinned) : null
        if (id === "open") {
            dockWindow.launchApp(r.class)
        } else if (id === "minimize") {
            dockWindow.minimizeAll(info)
        } else if (id === "restore") {
            dockWindow.restoreAll(info)
        } else if (id === "closeall") {
            dockWindow.closeAll(info)
        } else if (id === "pin") {
            PinnedAppsService.pin(r.class, r.iconName)
        } else if (id === "unpin") {
            PinnedAppsService.unpin(r.class)
        } else if (id === "addsepafter") {
            PinnedAppsService.addSeparator(r.pinIndex + 1)
        } else if (id === "addsepend") {
            PinnedAppsService.addSeparator()
        } else if (id === "removesep") {
            PinnedAppsService.removeAt(r.pinIndex)
        } else if (id === "newfolder") {
            // The folder takes the app's place when it was pinned, else goes at the end.
            const at = r.pinned ? r.pinIndex : undefined
            PinnedAppsService.createFolder("Folder " + (PinnedAppsService.pinned.filter(it => PinnedAppsService.kindOf(it) === "folder").length + 1),
                                           at, [{ class: r.class, iconName: r.iconName }])
        } else if (id === "deletefolder") {
            PinnedAppsService.deleteFolder(r.pinIndex)
        } else if (id === "openfolder") {
            dockWindow.openFolder(dockWindow.rowItems.indexOf(r))
        } else if (id === "renamefolder") {
            dockWindow.openFolder(dockWindow.rowItems.indexOf(r))
            Qt.callLater(() => folderCard.beginEdit())
        } else if (id === "removetool") {
            PinnedAppsService.removeAt(r.pinIndex)
        } else if (id.startsWith("addtool:")) {
            PinnedAppsService.addTool(id.substring(8))
        } else if (id === "openfiles") {
            dockWindow.openFiles()
        } else if (id.startsWith("place:")) {
            const at = dockWindow.rowItems.indexOf(r)
            if (FilesStackService.stackOn && at >= 0) {
                // The stack opens on that folder (this time only; Settings keeps its own default).
                FilesStackService.override = FilesStackService.placePath(id.substring(6))
                dockWindow.toggleTool(at, "files")
            } else {
                dockWindow.openPlace(id.substring(6))
            }
        } else if (id === "shelfpaste") {
            ShelfService.addFromClipboard()
        } else if (id === "shelfcopyall") {
            ShelfService.copyAll()
        } else if (id === "shelfclear") {
            ShelfService.clear()
        } else if (id === "clipwipe") {
            Quickshell.execDetached(["cliphist", "wipe"])
        } else if (id === "savelayout") {
            PinnedAppsService.savePreset(PinnedAppsService.freshPresetName())
        } else if (id.startsWith("preset:")) {
            PinnedAppsService.loadPreset(id.substring(7))
        } else if (id.startsWith("hide:")) {
            SettingsService.set("dock.hideMode", id.substring(5))
            SettingsService.set("dock.autoHide", false)
        } else if (id.startsWith("tofolder:")) {
            PinnedAppsService.addToFolder(parseInt(id.substring(9)), r.class, r.iconName)
        }
    }

    function openFolder(idx) {
        const slot = rowRepeater.itemAt(idx)
        if (!slot)
            return
        dockWindow.closePopups()
        const pt = dockWindow.anchorOf(slot)
        dockWindow.folderAnchorX = pt.x
        dockWindow.folderAnchorY = pt.y
        dockWindow.folderRow = idx
        dockWindow.folderOpen = true
    }

    // An app from a folder's card: jump to it if it is running, else open it.
    function openFromFolder(cls) {
        const info = dockWindow.infoFor(cls, true)
        dockWindow.folderOpen = false
        if (info && info.address)
            dockWindow.focusWin(info)
        else
            dockWindow.launchApp(cls)
    }

    function removeFromFolder(cls) {
        const r = dockWindow.rowItems[dockWindow.folderRow]
        if (r && r.kind === "folder")
            PinnedAppsService.removeFromFolder(r.pinIndex, cls)
        dockWindow.folderOpen = false
    }

    // ===== clicking a key =====
    // Search: the Apps screen of the Quick Panel's phone (the old launcher phone's
    // Home moved there); the Overview if there is no panel.
    function searchOpen() {
        if (dockWindow.launcher && dockWindow.launcher.toggleAppsOn)
            dockWindow.launcher.toggleAppsOn(dockWindow.screen)
        else if (dockWindow.launcher)
            dockWindow.launcher.toggleOn(dockWindow.screen)
        else if (dockWindow.overviewBoard)
            dockWindow.overviewBoard.toggleOn(dockWindow.screen)
    }

    // Files: the file manager (Settings -> `dock.filesCommand`, `xdg-open ~` by default).
    function openFiles() {
        Quickshell.execDetached(["sh", "-c", SettingsService.get("dock.filesCommand")])
    }

    // A folder from the Files key's menu: Downloads, Documents...
    function openPlace(key) {
        if (key === "TRASH") {
            FilesStackService.openTrashInManager()
            return
        }
        Quickshell.execDetached(["sh", "-c", "d=$(xdg-user-dir \"$1\" 2>/dev/null); xdg-open \"${d:-$HOME}\"", "sh", key])
    }

    // Opens (or, if it is the one open, closes) a tool's card over its key.
    function toggleTool(idx, tool) {
        const was = dockWindow.toolOpen
        dockWindow.closePopups()
        if (was === tool)
            return
        const slot = rowRepeater.itemAt(idx)
        if (!slot)
            return
        const pt = dockWindow.anchorOf(slot)
        dockWindow.toolAnchorX = pt.x
        dockWindow.toolAnchorY = pt.y
        dockWindow.toolOpen = tool
    }

    // `ipc call dock files`: the Files stack, from a keybind. False when this dock has no Files key.
    function toggleFiles() {
        const idx = dockWindow.rowItems.findIndex(r => r.kind === "tool" && r.tool === "files")
        if (idx < 0)
            return false
        dockWindow.peek()
        dockWindow.toggleTool(idx, "files")
        return true
    }

    function activateRow(idx) {
        const r = dockWindow.rowItems[idx]
        if (!r)
            return
        if (r.kind === "tool" && (r.tool === "clipboard" || r.tool === "shelf" || r.tool === "timer"
                                  || (r.tool === "files" && FilesStackService.stackOn))) {
            dockWindow.toggleTool(idx, r.tool)
            return
        }
        dockWindow.closePopups()
        if (r.kind === "tool") {
            if (r.tool === "search")
                dockWindow.searchOpen()
            else if (r.tool === "files")
                dockWindow.openFiles()
        } else if (r.kind === "pin") {
            PinnedAppsService.toggleDockPinned()
        } else if (r.kind === "folder") {
            dockWindow.openFolder(idx)
        } else if (r.kind === "media") {
            media.togglePlaying()
        } else if (r.kind === "app") {
            const info = dockWindow.infoFor(r.class, r.pinned)
            if (!info) {
                dockWindow.launchApp(r.class)
            } else if (info.minCount === info.count) {
                dockWindow.restoreAll(info)
            } else if (dockWindow.clickMinimizes && dockWindow.runningMaps.focused === r.class) {
                // Clicking the app you are in puts its window away.
                const w = info.wins.find(x => x.active && !x.min) ?? info.wins.find(x => !x.min)
                dockWindow.minimizeWin(w)
            } else if (info.address) {
                dockWindow.focusWin(info)
            }
        }
    }

    // ===== hiding =====
    // Always on screen unless a hide mode is on. Which *layer* it lives on:
    //   - Dock pin OFF (default): Wayland's Bottom layer, which sits BELOW normal
    //     windows. On an empty workspace you see the dock; the moment a window
    //     covers that part of the screen, the workspace takes over and the window
    //     draws on top of the dock.
    //   - Dock pin ON (the pin button at the end of the dock): Top layer, above
    //     windows, AND it reserves its own space (see exclusionMode below) so
    //     windows shrink to fit, the same way they do for the bar. Remembered across
    //     restarts — see PinnedAppsService.dockPinned.
    //   - A hide mode on: Top layer too (it has to be seen when it slides in).
    readonly property bool dockPinned: PinnedAppsService.dockPinned

    // Auto-hide and Smart hide both give the dock somewhere to slide to; they
    // differ in WHEN it is away: auto-hide always (until the pointer hits the edge),
    // smart hide only while a window is in its way.
    readonly property bool autoHideOn: dockWindow.hideMode !== "off" && !dockWindow.dockPinned
    readonly property bool smartOn: dockWindow.hideMode === "smart" && !dockWindow.dockPinned

    // The strip along the edge the dock stands on, as the screen sees it (real
    // pixels, the monitor's own corner being 0,0): a window in it is "in the way".
    readonly property var smartRect: {
        const s = dockWindow.screen
        if (!s)
            return { x: 0, y: 0, w: 0, h: 0 }
        const W = s.width
        const H = s.height
        const T = dockWindow.lift + dockWindow.stripSize + 4
        const L = Math.ceil((dockWindow.rowLen + dockWindow.pillPaddingH * 2) * dockWindow.uiScale)
        if (dockWindow.position === "bottom")
            return { x: Math.round((W - L) / 2), y: H - T, w: L, h: T }
        if (dockWindow.position === "top")
            return { x: Math.round((W - L) / 2), y: 0, w: L, h: T }
        if (dockWindow.position === "left")
            return { x: 0, y: Math.round((H - L) / 2), w: T, h: L }
        return { x: W - T, y: Math.round((H - L) / 2), w: T, h: L }
    }
    readonly property bool smartCovered: dockWindow.smartOn && dockWindow.screen
        ? DockService.covers(dockWindow.screen.name, dockWindow.smartRect) : false
    // Smart hide while starting up: the window list from Hyprland is not back yet, so it
    // cannot know whether a window is in the way. Until it is (a moment, and only while the
    // dock is coming up) the dock stays away instead of showing over the windows.
    //
    // It waits for the window list itself, not for the 0.6 s the slide animations take to
    // switch on (that gave up too early when Hyprland was slow to answer after a reload or a
    // kill, and the dock showed over the windows). It gives up only after `startupMs` with no
    // answer at all, so a Hyprland that never answers cannot keep the dock away for good (the
    // hot edge still brings it up). Only while the dock comes up: switching Smart hide on
    // later does not slide it away first.
    readonly property int startupMs: 5000
    property bool startupDone: false
    readonly property bool smartWaiting: dockWindow.smartOn && !DockService.ready && !dockWindow.startupDone
    Timer {
        interval: dockWindow.startupMs
        running: dockWindow.visible && !dockWindow.startupDone
        onTriggered: dockWindow.startupDone = true
    }
    Connections {
        target: DockService
        function onReadyChanged() {
            if (DockService.ready)
                dockWindow.startupDone = true
        }
    }
    readonly property bool wantsHidden: dockWindow.hideMode === "auto" || dockWindow.smartCovered || dockWindow.smartWaiting

    // The geometry feed (hyprctl) only runs while some dock is in smart-hide mode. Each
    // dock window holds it with a key of its own, given once when it is built
    // (Component.onCompleted): a key per monitor was shared by the two docks the shell
    // builds on one monitor at startup, and the one going away released it for both
    // (issue #116, DockService.hold).
    property string holdKey: ""
    onSmartOnChanged: DockService.hold(dockWindow.holdKey, dockWindow.smartOn)

    // The gap under the pill, in design pixels, kept INSIDE the window while a hide
    // mode is on (the window then sits right on the edge, so the pill has somewhere
    // to slide to).
    readonly property real innerGap: dockWindow.autoHideOn ? 14 : 0
    // The pointer is on the dock. Several things can see it, and ANY of them counts: the
    // window's own hover handler, the one on the hot area (where the dock pops up), the
    // dock's mouse area and the open cards. A mouse area on top can take the pointer away
    // from a handler under it; if the dock went by one of them alone, it would think the
    // pointer left, slide away, see the pointer again, and come back, over and over.
    property bool hoverWin: false
    readonly property bool hovered: dockWindow.hoverWin || hotHover.hovered || hit.containsMouse
                                    || dockWindow.cardHovered || dockWindow.mediaCardHovered
    // Something is being dragged over the hot strip, the Shelf key or the Shelf card. A drag
    // sends no pointer motion, so none of the hover handlers above see it: without this a
    // hidden dock stayed hidden while you dragged a file to the edge, and a shown one
    // slid away under the file.
    property bool dragKey: false
    readonly property bool dragOver: hotDrop.containsDrag || dockWindow.dragKey || shelfCard.dropping
    onDragOverChanged: {
        if (!dragOver && autoHideOn)
            hideGrace.restart()
    }
    readonly property bool revealed: !dockWindow.autoHideOn || !dockWindow.wantsHidden || dockWindow.editing
                                     || dockWindow.hovered || hideGrace.running || dockWindow.dragOver
                                     || dockWindow.menuOpen || dockWindow.folderOpen || dockWindow.toolOpen !== "" || dockWindow.dragging
    // How far the pill is pushed toward its edge, design pixels (animated).
    property real hideOffset: dockWindow.revealed ? 0 : (dockWindow.pillThickness + mt.shadowOffset
                                                          + dockWindow.innerGap + 4
                                                          + (dockWindow.magMax - 1) * (dockWindow.iconSize + mt.shadowOffset))
    Behavior on hideOffset {
        enabled: dockWindow.animReady
        NumberAnimation { duration: 220; easing.type: dockWindow.revealed ? Easing.OutCubic : Easing.InCubic }
    }

    // Wearing a desktop preset that changes the dock: it slides off its edge, the
    // preset goes on, and it slides back (see PresetMotion.qml). 0 = in place,
    // 1 = away. Added to hiding as "whichever pushes it further", so a dock that
    // is already tucked away by auto-hide stays tucked. Two fixed animations
    // started from the flag, not one Behavior (see ClockWidget's reveal).
    property real presetSlide: 0
    readonly property real fullHide: dockWindow.pillThickness + mt.shadowOffset
                                     + dockWindow.innerGap + 4
                                     + (dockWindow.magMax - 1) * (dockWindow.iconSize + mt.shadowOffset)
    readonly property real pullOffset: Math.max(dockWindow.hideOffset, dockWindow.presetSlide * dockWindow.fullHide)
    NumberAnimation {
        id: presetOut
        target: dockWindow
        property: "presetSlide"
        to: 1
        duration: PresetMotion.outMs
        easing.type: Easing.InCubic
    }
    NumberAnimation {
        id: presetIn
        target: dockWindow
        property: "presetSlide"
        to: 0
        duration: PresetMotion.inMs
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
    }
    Connections {
        target: PresetMotion
        function onDockOutChanged() {
            if (PresetMotion.dockOut) {
                presetIn.stop()
                presetOut.restart()
            } else {
                presetOut.stop()
                presetIn.restart()
            }
        }
    }
    // Fully tucked away: nothing but the strip takes input.
    readonly property bool tucked: dockWindow.autoHideOn && !dockWindow.revealed && dockWindow.hideOffset > 1

    Timer {
        id: hideGrace
        interval: 450
    }
    onHoveredChanged: {
        if (!hovered && autoHideOn)
            hideGrace.restart()
    }

    // Bottom (under windows, over the desktop widgets, which sit on Background; the one
    // being edited is on Bottom) or Top. While Edit Desktop is open the dock is on Top too, so
    // it is in front of the widget being edited (windows are parked then).
    // (Also on Top while the Shelf card is open: it is a place to drop things from other windows,
    // so it must not sit behind them. Same for the Files stack: it opens over your windows.)
    WlrLayershell.layer: (dockWindow.dockPinned || dockWindow.autoHideOn || dockWindow.editing
                          || dockWindow.toolOpen === "files" || dockWindow.toolOpen === "shelf") ? WlrLayer.Top : WlrLayer.Bottom
    WlrLayershell.namespace: "sekaipop-dock"
    // The folder card has a text box (the rename) and the Files stack listens for Esc /
    // Backspace; the dock never takes the keyboard otherwise.
    WlrLayershell.keyboardFocus: (dockWindow.folderOpen || dockWindow.toolOpen === "files") ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // The window itself runs the whole length of its edge and is transparent, so
    // without this the empty strip on either side of the pill would swallow clicks
    // meant for the window underneath. Only the pill (and, while the pointer is on
    // it, the strip above it that grown keys reach into), an open card and the hot
    // strip take input.
    mask: Region {
        item: dockMask
        regions: [ Region { item: hotZone }, Region { item: previewMask }, Region { item: popupMask } ]
    }

    // ===== starting up =====
    // After a shell restart the dock must not show for a moment in the wrong state
    // (shown although it is set to hide, or over the windows although it is not pinned).
    // So the window is not mapped until the saved "pinned" state has been read
    // (`PinnedAppsService.dockLoaded`; the settings are already read, shell.qml waits for
    // them). If that read never answers, it is mapped anyway after 1.5 s.
    property bool startupWaited: false
    readonly property bool stateKnown: PinnedAppsService.dockLoaded || dockWindow.startupWaited
    Timer {
        interval: 1500
        running: !dockWindow.stateKnown
        onTriggered: dockWindow.startupWaited = true
    }

    // The slide in / out is off while the dock comes up (it just stands in its place, or is
    // already away), and switches on 0.6 s after the window is on screen.
    property bool animReady: false
    Timer {
        interval: 600
        running: dockWindow.visible && !dockWindow.animReady
        onTriggered: dockWindow.animReady = true
    }

    // Settings -> Desktop -> Dock -> Show dock.
    visible: SettingsService.flag("dock.visible") && dockWindow.stateKnown

    // Along the bottom / top edge the window runs the whole width and sticks to that
    // edge. Left / right: it runs the whole height and sticks to that edge.
    anchors {
        left: dockWindow.position !== "right"
        right: dockWindow.position !== "left"
        top: dockWindow.vertical || dockWindow.position === "top"
        bottom: dockWindow.vertical || dockWindow.position === "bottom"
    }

    // How far the pill sits in from the screen's edge (`lift`, in real pixels, from
    // the edge to the pill's near side). It is 14 by default. With the bar on the
    // same edge (services/BarPositionService.qml) a pinned dock is already placed
    // past the bar's reserved space by the compositor, so its margin is only the 14;
    // an unpinned one ignores reserved space, so it's moved off the bar by hand.
    readonly property real lift: Math.round((14 + (BarPositionService.position === dockWindow.position
        ? BarPositionService.thickness : 0)) * dockWindow.uiScale)
    // (A hide mode: the window sits `innerGap` closer to the edge, the pill keeps its 14 inside.)
    readonly property real edgeMargin: dockWindow.dockPinned
        ? Math.round(14 * dockWindow.uiScale)
        : dockWindow.lift - Math.round(dockWindow.innerGap * dockWindow.uiScale)
    margins.bottom: dockWindow.position === "bottom" ? dockWindow.edgeMargin : 0
    margins.top: dockWindow.position === "top" ? dockWindow.edgeMargin : 0
    margins.left: dockWindow.position === "left" ? dockWindow.edgeMargin : 0
    margins.right: dockWindow.position === "right" ? dockWindow.edgeMargin : 0
    // Pinned = the dock reserves its own space, exactly like the top bar does, so
    // tiled windows shrink to sit away from it instead of going under it. Unpinned =
    // Ignore, no space reserved, windows use the whole screen and cover the dock.
    // Switches live when you click the pin button.
    exclusionMode: dockWindow.dockPinned ? ExclusionMode.Normal : ExclusionMode.Ignore

    // exclusiveZone is NOT a plain binding on purpose. Quickshell's setter for it
    // also forces exclusionMode to Normal every time it is written, so a plain
    // `exclusiveZone: ...` binding quietly undid the Ignore above: on a shell reload
    // (the zone is evaluated after the mode) the unpinned dock reserved space as if
    // pinned, while the pin button still looked off. A Binding only writes while it
    // is active (the dock is pinned), and RestoreNone stops it writing a "restored"
    // 0 on the way out, which would force Normal too.
    //
    // The space it reserves. Two things decide where the windows stop, and both were
    // wrong before:
    //  - The compositor puts the layer's own margin (`edgeMargin`, the 14 the pill keeps
    //    from the edge) on top of the zone, and then `general.gaps_out` on top of that.
    //    The zone used to include the margin as well, so it was counted twice and the windows
    //    stopped 14 px further away than meant (measured off a screenshot: a 69 px dock,
    //    14 margin, gaps_out 14 -> windows 98 px from the edge, 15 px from the dock, not 1).
    //    The zone is now the pill's thickness alone, less gaps_out, plus the gap wanted.
    //  - The gap is measured from what you SEE. Float and Capsule draw the pill, so that is
    //    its edge. Transparent draws only the keys: the pill's padding on the windows' side
    //    (`pillPaddingV`) is empty, so it is taken off too and the gap to the keys is the
    //    same as the gap to the housing in the other two styles.
    // It follows the Hyprland setting live.
    //   pinnedWindowGap: the gap between the windows and what is visible of the dock,
    //   design pixels. Same number as the Capsule bar's own gap (8). Bigger = more room,
    //   0 = the windows touch.
    readonly property real pinnedWindowGap: 8
    readonly property real pinnedInvisible: dockWindow.look === "transparent" ? dockWindow.pillPaddingV : 0
    readonly property real pinnedTrim: Math.max(0, HyprlandSettings.num("general.gaps_out"))
                                       - Math.round(dockWindow.pinnedWindowGap * dockWindow.uiScale)
                                       + Math.round(dockWindow.pinnedInvisible * dockWindow.uiScale)
    Binding {
        target: dockWindow
        property: "exclusiveZone"
        value: Math.max(1, dockWindow.stripSize - dockWindow.pinnedTrim)
        when: dockWindow.dockPinned
        restoreMode: Binding.RestoreNone
    }
    color: "transparent"

    // ===== Edit Desktop =====
    readonly property bool editing: dockWindow.screen !== null && EditMode.editing(dockWindow.screen.name)
    // How thick the pill is across (design pixels): the key, its padding and, on a
    // flat dock, its hard shadow underneath.
    readonly property real pillThickness: dockWindow.iconSize + dockWindow.pillPaddingV * 2
                                          + (dockWindow.vertical ? 0 : mt.shadowOffset)
    // ...and as the window sees it (real pixels): how far the strip reaches in from the edge.
    readonly property real stripSize: Math.round(dockWindow.pillThickness * dockWindow.uiScale)
    // The window is as big as the screen from the edge the pill is `lift` away from,
    // so its size across is the screen's less that (plus the hide gap that sits
    // inside it). The other way it runs the whole screen.
    readonly property real windowAcross: dockWindow.screen
        ? Math.max(dockWindow.stripSize + Math.round(dockWindow.innerGap * dockWindow.uiScale),
                   Math.round(dockWindow.vertical ? dockWindow.screen.width : dockWindow.screen.height)
                       - dockWindow.lift + Math.round(dockWindow.innerGap * dockWindow.uiScale))
        : dockWindow.stripSize
    implicitHeight: dockWindow.vertical ? 0 : dockWindow.windowAcross
    implicitWidth: dockWindow.vertical ? dockWindow.windowAcross : 0

    // Where this window's top-left corner is on the screen, for Edit Desktop's card
    // (EditStage.qml): a dock on the left (or the top) starts in from the edge; a
    // pinned one on a side edge starts below a bar on the top.
    readonly property real originX: dockWindow.position === "left"
        ? dockWindow.lift - Math.round(dockWindow.innerGap * dockWindow.uiScale) : 0
    readonly property real originY: dockWindow.position === "top"
        ? dockWindow.edgeMargin + (dockWindow.dockPinned && BarPositionService.position === "top"
            ? Math.round(BarPositionService.reserved * dockWindow.uiScale) : 0)
        : (dockWindow.vertical && dockWindow.dockPinned && BarPositionService.position === "top"
            ? Math.round(BarPositionService.reserved * dockWindow.uiScale) : 0)

    // Tell the screen-region picker (RegionSelector.qml) where the dock is, so its
    // toolbar can sit above it. 0 while the dock is hidden, tucked away or being
    // edited: then it isn't in the frozen picture either. (Only a dock along the
    // bottom edge is in the toolbar's way.)
    readonly property real regionTop: dockWindow.visible && !dockWindow.editing && !dockWindow.tucked
                                      && dockWindow.position === "bottom"
        ? dockWindow.lift + dockWindow.stripSize : 0
    readonly property real regionHalf: Math.ceil(dockPill.width * dockWindow.uiScale) / 2
    function reportRegion() {
        if (dockWindow.screen)
            RegionService.setDock(dockWindow.screen.name, dockWindow.regionTop, dockWindow.regionHalf)
    }
    onRegionTopChanged: dockWindow.reportRegion()
    onRegionHalfChanged: dockWindow.reportRegion()
    Component.onCompleted: {
        dockWindow.reportRegion()
        dockWindow.refreshAutoSlots()
        dockWindow.holdKey = DockService.newHoldKey("dock")
        DockService.hold(dockWindow.holdKey, dockWindow.smartOn)
        // A dock built later (another monitor, a preset swap) finds the list already there.
        if (DockService.ready)
            dockWindow.startupDone = true
        // Built in the middle of a preset swap (a new edge builds a new
        // window): start away and come in once the others do.
        if (PresetMotion.dockBusy) {
            dockWindow.presetSlide = 1
            if (!PresetMotion.dockOut)
                presetIn.restart()
        }
    }
    Component.onDestruction: {
        DockService.hold(dockWindow.holdKey, false)
        if (dockWindow.screen)
            RegionService.setDock(dockWindow.screen.name, 0, 0)
    }

    // Pull the dock up for a moment (shell.qml's `ipc call dock peek`); it hides
    // again on its own.
    function peek() {
        hideGrace.restart()
    }

    // ===== the input mask =====
    // How far a grown key can reach past the pill (design pixels): while the
    // pointer is on the dock its input area reaches that far out, so the top of a
    // grown key still counts as "on the dock" (it would otherwise let go of the
    // pointer and shrink).
    readonly property real reach: (dockWindow.magOn && dockWindow.hovered)
        ? (dockWindow.magMax - 1) * (dockWindow.iconSize + mt.shadowOffset) + 8 : 0

    // The pill, plus that reach on its inward side, in design pixels (the pill sits
    // inside a scaled ScaleHost; the mask below is in real window pixels).
    readonly property real hitX: dockPill.x - (dockWindow.position === "right" ? dockWindow.reach : 0)
    readonly property real hitY: dockPill.y - (dockWindow.position === "bottom" ? dockWindow.reach : 0)
    readonly property real hitW: dockPill.width + (dockWindow.vertical ? dockWindow.reach : 0)
    readonly property real hitH: dockPill.height + (dockWindow.vertical ? 0 : dockWindow.reach)

    Item {
        id: dockMask
        readonly property bool none: dockWindow.editing || dockWindow.tucked
        // Tucked away: no input here, only the hot strip below.
        x: none ? 0 : Math.max(0, Math.floor(dockWindow.hitX * dockWindow.uiScale))
        y: none ? 0 : Math.max(0, Math.floor(dockWindow.hitY * dockWindow.uiScale))
        width: none ? 1 : Math.ceil(dockWindow.hitW * dockWindow.uiScale) + 1
        height: none ? 1 : Math.ceil(dockWindow.hitH * dockWindow.uiScale) + 1
    }

    // The window overview's card, and the gap between it and the dock (so the
    // pointer can travel from a key onto the card), in real window pixels. Takes no
    // input unless the card is open. The numbers come from the card itself (`mask*`,
    // in design pixels; this window's contents are drawn at uiScale).
    Item {
        id: previewMask
        readonly property bool none: !dockWindow.cardVisible
        x: none ? 0 : Math.max(0, Math.floor(overviewCard.maskX * dockWindow.uiScale))
        y: none ? 0 : Math.max(0, Math.floor(overviewCard.maskY * dockWindow.uiScale))
        width: none ? 1 : Math.ceil(overviewCard.maskW * dockWindow.uiScale)
        height: none ? 1 : Math.ceil(overviewCard.maskH * dockWindow.uiScale)
    }

    // Same, for whichever of the menu, the folder card, a tool's card and the media card is showing.
    Item {
        id: popupMask
        readonly property var card: menuCard.visible ? menuCard
            : (folderCard.visible ? folderCard
            : (clipCard.visible ? clipCard
            : (shelfCard.visible ? shelfCard
            : (filesCard.visible ? filesCard
            : (timerCard.visible ? timerCard
            : (mediaCard.visible ? mediaCard : null))))))
        readonly property bool none: card === null || dockWindow.editing
        x: none ? 0 : Math.max(0, Math.floor(card.maskX * dockWindow.uiScale))
        y: none ? 0 : Math.max(0, Math.floor(card.maskY * dockWindow.uiScale))
        width: none ? 1 : Math.ceil(card.maskW * dockWindow.uiScale)
        height: none ? 1 : Math.ceil(card.maskH * dockWindow.uiScale)
    }

    // The area that brings a hidden dock back: exactly the spot where the pill pops up
    // (its resting place, a little in from the screen's edge), not a thin line on the edge.
    // Along the edge it is as long as the pill plus a little slack. Empty (1 px in the corner)
    // unless a hide mode is on. The very edge of the screen is left alone, so the Quick
    // Panel's hot edge (bottom-centre) keeps working.
    Item {
        id: hotZone
        readonly property bool on: dockWindow.autoHideOn && !dockWindow.editing
        // Real pixels: how far the resting pill is from the window's edge, and how thick it is.
             // Only a bottom dock with the Quick Panel's hot edge on keeps the strip off the edge;
        // on any other edge the strip starts right at the screen edge, so the dock comes out
        // when the pointer hits the edge, not 2-3 cm before it.
        readonly property real gap: (dockWindow.position === "bottom" && SettingsService.flag("panel.hotEdge"))
          ? Math.round(dockWindow.innerGap * dockWindow.uiScale) : 0
        // How deep the strip is: the pill's thickness at 100 % (the default), less when
        // Settings -> Desktop -> Dock -> "Reveal zone" is lowered, so a pointer working
        // near the edge (a chat box, a toolbar) does not bring the dock up. The strip
        // keeps its edge-side boundary where it was (`gap`) and shrinks toward the
        // middle of the screen, so the Quick Panel's hot edge is still left alone. It is
        // only the strip that shrinks: once the dock is out, the pill itself (and the
        // window's own hover handler) keep it out, at its full size.
        readonly property real zoneFraction: Math.max(0.1, Math.min(1, SettingsService.get("dock.hotZone") / 100))
        readonly property real fullThick: Math.ceil(dockWindow.pillThickness * dockWindow.uiScale)
        readonly property real thick: Math.max(2, Math.min(fullThick, Math.round(fullThick * zoneFraction)))
        readonly property real slack: Math.round(8 * dockWindow.uiScale)
        readonly property real along: Math.min(dockWindow.vertical ? dockWindow.height : dockWindow.width,
            Math.ceil((dockWindow.rowLen + dockWindow.pillPaddingH * 2
                       + (dockWindow.vertical ? mt.shadowOffset : 0)) * dockWindow.uiScale) + slack * 2)
        width: on ? (dockWindow.vertical ? thick : along) : 1
        height: on ? (dockWindow.vertical ? along : thick) : 1
        x: on ? (dockWindow.vertical
                 ? (dockWindow.position === "left" ? gap : dockWindow.width - gap - thick)
                 : Math.round((dockWindow.width - width) / 2))
              : 0
        y: on ? (dockWindow.vertical
                 ? Math.round((dockWindow.height - height) / 2)
                 : (dockWindow.position === "top" ? gap : dockWindow.height - gap - thick))
              : 0

        // Sees the pointer on this area by itself (the dock's mouse area, which is
        // only there once the dock is out, can't take it away from this one).
        HoverHandler {
            id: hotHover
            enabled: hotZone.on
        }

        // A file or text dragged to the edge brings the dock back (see `dragOver`).
        DropArea {
            id: hotDrop
            anchors.fill: parent
            enabled: hotZone.on
        }
    }

    // Sees the pointer over the dock, its cards and the strip (only the masked
    // parts get pointer events at all). A HoverHandler is passive, so the dock's own
    // mouse areas keep working.
    Item {
        anchors.fill: parent
        HoverHandler {
            onHoveredChanged: dockWindow.hoverWin = hovered
        }
    }

    // (`ipc call dock ...` lives in shell.qml: one handler for every dock.)

    // The dock's picture. Scale 1 / no offset out of edit mode; while editing it is
    // scaled down and moved to where the card is, worked out from the SCREEN's size
    // like the wallpaper's (the window stops short of the screen's edge, so its own
    // height is not the one to use). `clip` cuts it at the window's edge, which is
    // now the card's edge.
    EditStage {
        id: stage
        screenObj: dockWindow.screen
        uiScale: dockWindow.uiScale
        originX: dockWindow.originX
        originY: dockWindow.originY
        refWidth: dockWindow.screen ? dockWindow.screen.width : dockWindow.width
        refHeight: dockWindow.screen ? dockWindow.screen.height : dockWindow.height
        clip: true

        ScaleHost {
            anchors.fill: parent
            factor: dockWindow.uiScale

            Pill {
                id: dockPill
                // On the dock's edge, centered along it.
                anchors.horizontalCenter: dockWindow.vertical ? undefined : parent.horizontalCenter
                anchors.verticalCenter: dockWindow.vertical ? parent.verticalCenter : undefined
                anchors.bottom: dockWindow.position === "bottom" ? parent.bottom : undefined
                anchors.top: dockWindow.position === "top" ? parent.top : undefined
                anchors.left: dockWindow.position === "left" ? parent.left : undefined
                anchors.right: dockWindow.position === "right" ? parent.right : undefined
                // A hide mode: kept `innerGap` off the window's edge, and pushed out
                // of sight past it by `hideOffset` while tucked away.
                anchors.bottomMargin: dockWindow.position === "bottom" ? dockWindow.innerGap - dockWindow.pullOffset : 0
                anchors.topMargin: dockWindow.position === "top" ? dockWindow.innerGap - dockWindow.pullOffset : 0
                anchors.leftMargin: dockWindow.position === "left" ? dockWindow.innerGap - dockWindow.pullOffset : 0
                anchors.rightMargin: dockWindow.position === "right" ? dockWindow.innerGap - dockWindow.pullOffset : 0

                // Flat: as wide as its keys (and what the magnification adds), one
                // key tall. Standing: one key wide, as tall as its keys.
                width: dockWindow.vertical ? dockWindow.iconSize + dockWindow.pillPaddingV * 2
                                           : dockWindow.rowLen + dockWindow.magData.total + dockWindow.pillPaddingH * 2
                height: dockWindow.vertical ? dockWindow.rowLen + dockWindow.magData.total + dockWindow.pillPaddingH * 2 + shadowDy
                                            : dockWindow.iconSize + dockWindow.pillPaddingV * 2 + shadowDy

                // A modest rounded rectangle, not a full capsule — same radius
                // MediaPill/BatteryPopup/ResourcePopup/TrayMenu all use for their
                // own wide, multi-item housings (Theme.radiusOuter). Pill's default
                // cornerRadius (height / 2) is for slim single-row things and would
                // round the ends into a stadium here. The shadow Rectangle in
                // Pill.qml reads this same property, so the drop shadow's corners
                // follow too.
                //
                // Capsule: fully rounded instead (half the cap's short side), in
                // the Capsule bar's colours: Pill's `capRim` look, with a rim as
                // thick as the bar's.
                cornerRadius: dockWindow.look === "capsule"
                    ? Math.min(dockPill.capWidth, dockPill.capHeight) / 2 : mt.radiusOuter
                // Transparent: no background, only the keys.
                bare: dockWindow.look === "transparent"
                capRim: dockWindow.look === "capsule"
                borderWidth: dockWindow.look === "capsule" ? mt.capRimWidth : mt.borderWidth
                // Same navy-outline / pale-ring / white-fill construction as the
                // bar's own background (Status_Bar.qml's bgShadow/bgFace/bgFill),
                // just going through Pill's built-in ring. Pill's `ringWidth` is
                // measured from the cap's outer edge (where the navy border sits),
                // while Theme.outerRingWidth is the bar's *visible band* beyond that
                // border — so it takes borderWidth on top to land on the same band.
                ringWidth: dockWindow.look === "capsule" ? mt.capRimWidth
                    : mt.borderWidth + mt.outerRingWidth
                ringColorTop: mt.surfaceRing
                ringColorBottom: mt.surfaceRing
                fillColor: mt.surface

                // The row: every item placed by `rowPos` along it (this file does
                // the layout, see the header).
                Item {
                    id: dockRow
                    anchors.centerIn: parent
                    width: dockWindow.vertical ? dockWindow.iconSize : dockWindow.rowLen
                    height: dockWindow.vertical ? dockWindow.rowLen : dockWindow.iconSize + mt.shadowOffset

                    Repeater {
                        id: rowRepeater
                        model: dockWindow.rowItems
                        delegate: slotDelegate
                    }
                }
            }

            // All the pointer work for the dock, in one mouse area over the pill (and
            // the strip above it that grown keys reach into): which key is under the
            // pointer (worked out from where the keys really are, see `indexAt`),
            // clicks, the right-click menu, the wheel and drag-to-reorder. A mouse
            // area per key could not do this: the keys move and grow.
            MouseArea {
                id: hit
                x: dockWindow.hitX
                y: dockWindow.hitY
                width: dockWindow.hitW
                height: dockWindow.hitH
                enabled: !dockWindow.editing && !dockWindow.tucked
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: dockWindow.hoverClickable ? Qt.PointingHandCursor : Qt.ArrowCursor

                property int pressIdx: -1
                property real pressAlong: 0
                property int pressButton: 0
                property bool dragOk: false
                property real wheelAcc: 0
                // Which part of the long media pill the press started on.
                property string pressZone: ""

                // The pointer along the row.
                function alongOf(mx, my) {
                    const p = hit.mapToItem(dockRow, mx, my)
                    return dockWindow.vertical ? p.y : p.x
                }

                // How far the pointer is past the dock's inward side (negative while it
                // is still on the dock).
                function outOf(mx, my) {
                    const p = hit.mapToItem(dockPill, mx, my)
                    if (dockWindow.position === "bottom")
                        return -p.y
                    if (dockWindow.position === "top")
                        return p.y - dockPill.height
                    if (dockWindow.position === "left")
                        return p.x - dockPill.width
                    return -p.x
                }

                onPositionChanged: (mouse) => {
                    const a = hit.alongOf(mouse.x, mouse.y)
                    dockWindow.magPointer = a
                    dockWindow.pointerAlong = a
                    if (hit.pressed && hit.pressButton === Qt.LeftButton) {
                        if (!dockWindow.dragging && hit.dragOk && Math.abs(a - hit.pressAlong) > 8)
                            dockWindow.startDrag(hit.pressIdx)
                        if (dockWindow.dragging)
                            dockWindow.dragMove(a, hit.outOf(mouse.x, mouse.y))
                    } else {
                        dockWindow.hoverIdx = dockWindow.indexAt(a)
                    }
                }

                onExited: {
                    if (!hit.pressed) {
                        dockWindow.hoverIdx = -1
                        dockWindow.pointerAlong = -1000
                    }
                }

                onPressed: (mouse) => {
                    dockWindow.menuOpen = false
                    const a = hit.alongOf(mouse.x, mouse.y)
                    dockWindow.magPointer = a
                    dockWindow.pointerAlong = a
                    dockWindow.hoverIdx = dockWindow.indexAt(a)
                    hit.pressIdx = dockWindow.hoverIdx
                    hit.pressAlong = a
                    hit.pressButton = mouse.button
                    const r = dockWindow.rowItems[hit.pressIdx]
                    hit.pressZone = (r !== undefined && r.kind === "media" && dockWindow.mediaWide)
                        ? dockWindow.mediaZone(dockWindow.mediaLocal(a)) : ""
                    hit.dragOk = mouse.button === Qt.LeftButton && r !== undefined
                        && (r.kind === "app" || ((r.kind === "folder" || r.kind === "sep" || r.kind === "tool") && hit.pressIdx < dockWindow.pinnedCount))
                }

                onReleased: (mouse) => {
                    if (dockWindow.dragging) {
                        dockWindow.endDrag()
                        hit.pressIdx = -1
                        dockWindow.hoverIdx = -1
                        return
                    }
                    const upAlong = hit.alongOf(mouse.x, mouse.y)
                    const idx = dockWindow.indexAt(upAlong)
                    const r = dockWindow.rowItems[idx]
                    if (idx >= 0 && idx === hit.pressIdx && r !== undefined) {
                        if (mouse.button === Qt.LeftButton) {
                            if (r.kind === "media" && dockWindow.mediaWide) {
                                // Only if it is released on the same part it was pressed on.
                                const z = dockWindow.mediaZone(dockWindow.mediaLocal(upAlong))
                                if (z === hit.pressZone)
                                    dockWindow.mediaPress(z)
                            } else {
                                dockWindow.activateRow(idx)
                            }
                        } else if (mouse.button === Qt.RightButton) {
                            if (r.kind === "media")
                                media.next()
                            else
                                dockWindow.openMenu(idx)
                        } else if (mouse.button === Qt.MiddleButton) {
                            if (r.kind === "media")
                                media.previous()
                            else if (r.kind === "app")
                                dockWindow.launchApp(r.class)
                            else if (r.kind === "tool" && r.tool === "files")
                                dockWindow.openFiles()
                        }
                    }
                    hit.pressIdx = -1
                }

                // Wheel notches add up here (a touchpad sends many small ones). Over
                // an app, one full notch flips to the next window; over the media key
                // it is the player's volume.
                onWheel: (wheel) => {
                    wheel.accepted = true
                    const r = dockWindow.rowItems[dockWindow.hoverIdx]
                    if (r === undefined) {
                        hit.wheelAcc = 0
                        return
                    }
                    hit.wheelAcc += wheel.angleDelta.y
                    if (r.kind === "media") {
                        if (Math.abs(hit.wheelAcc) >= 60) {
                            media.changeVolume(hit.wheelAcc > 0 ? 1 : -1)
                            hit.wheelAcc = 0
                        }
                        return
                    }
                    if (Math.abs(hit.wheelAcc) < 120)
                        return
                    if (r.kind === "app")
                        dockWindow.cycleWindows(dockWindow.infoFor(r.class, r.pinned), hit.wheelAcc < 0 ? 1 : -1)
                    hit.wheelAcc = 0
                }
            }

            // Keeps the cards' place when the dock's size changes under them (an app
            // opens while the pointer is on it) or the keys move (magnification).
            Connections {
                target: dockPill
                function onWidthChanged() {
                    if (dockWindow.cardOn)
                        dockWindow.placeCard()
                    if (dockWindow.mediaCardOn)
                        dockWindow.placeMedia()
                }
                function onHeightChanged() {
                    if (dockWindow.cardOn)
                        dockWindow.placeCard()
                    if (dockWindow.mediaCardOn)
                        dockWindow.placeMedia()
                }
            }

            // ===== the cards =====
            Item {
                id: overlay
                anchors.fill: parent

                // The window overview.
                DockCard {
                    id: overviewCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.anchorX
                    anchorY: dockWindow.anchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.cardVisible
                    contentWidth: body.implicitWidth
                    contentHeight: body.implicitHeight
                    onHoverStateChanged: (on) => {
                        dockWindow.cardHovered = on
                        if (on)
                            previewClose.stop()
                        else
                            previewClose.restart()
                    }

                    Column {
                        id: body
                        x: overviewCard.pad
                        y: overviewCard.pad
                        spacing: 14

                        // The app's name, and how many windows it has.
                        Row {
                            spacing: 9

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13
                                height: 13
                                radius: 4
                                rotation: 45
                                color: mt.accentMint
                                border.width: 2
                                border.color: mt.line
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 280)
                                elide: Text.ElideRight
                                text: dockWindow.cardName
                                color: mt.ink
                                font.family: mt.fontFamily
                                font.pixelSize: 17
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property int n: dockWindow.cardInfo ? dockWindow.cardInfo.count : 0
                                text: n > 1 ? n + " windows · scroll the key to flip" : ""
                                visible: n > 1
                                color: mt.inkSub
                                font.family: mt.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                        }

                        // One tile per window (the first six), up to three a row.
                        Grid {
                            columns: Math.max(1, Math.min(3, dockWindow.cardKeys.length))
                            spacing: 16

                            Repeater {
                                model: dockWindow.cardKeys.slice(0, 6)

                                DockPreviewTile {
                                    id: tile
                                    required property string modelData
                                    address: tile.modelData
                                    win: dockWindow.cardInfo
                                        ? (dockWindow.cardInfo.wins.find(w => w.address === tile.modelData) ?? null) : null
                                    iconName: dockWindow.cardIcon
                                    capture: dockWindow.cardVisible
                                    onActivated: {
                                        dockWindow.focusWin(tile.win)
                                        dockWindow.cardOn = false
                                    }
                                    onCloseRequested: dockWindow.closeWin(tile.modelData)
                                    onMinimizeRequested: {
                                        if (tile.win && tile.win.min)
                                            dockWindow.focusWin(tile.win)
                                        else
                                            dockWindow.minimizeWin(tile.win)
                                    }
                                }
                            }
                        }
                    }
                }

                // The right-click menu.
                DockMenu {
                    id: menuCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.menuAnchorX
                    anchorY: dockWindow.menuAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.menuOpen
                    rows: dockWindow.menuRows
                    onPicked: (id) => dockWindow.menuPicked(id)
                }

                // A folder's apps.
                DockFolderCard {
                    id: folderCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.folderAnchorX
                    anchorY: dockWindow.folderAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.folderOpen
                    title: dockWindow.folderTitle
                    apps: dockWindow.folderApps
                    onOpenApp: (cls) => dockWindow.openFromFolder(cls)
                    onRemoveApp: (cls) => dockWindow.removeFromFolder(cls)
                    onRenamed: (name) => {
                        const r = dockWindow.rowItems[dockWindow.folderRow]
                        if (r && r.kind === "folder")
                            PinnedAppsService.renameFolder(r.pinIndex, name)
                    }
                }

                // The tools' cards.
                DockClipboardCard {
                    id: clipCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.toolAnchorX
                    anchorY: dockWindow.toolAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.toolOpen === "clipboard"
                    onCloseRequested: dockWindow.toolOpen = ""
                    onMoreRequested: {
                        dockWindow.toolOpen = ""
                        dockWindow.searchOpen()
                    }
                }

                DockShelfCard {
                    id: shelfCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.toolAnchorX
                    anchorY: dockWindow.toolAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.toolOpen === "shelf"
                    onCloseRequested: dockWindow.toolOpen = ""
                }

                // The Files key's folder stack.
                DockFilesCard {
                    id: filesCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.toolAnchorX
                    anchorY: dockWindow.toolAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.toolOpen === "files"
                    onCloseRequested: dockWindow.toolOpen = ""
                }

                DockTimerCard {
                    id: timerCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.toolAnchorX
                    anchorY: dockWindow.toolAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.toolOpen === "timer"
                }

                // The media player.
                DockMediaCard {
                    id: mediaCard
                    position: dockWindow.position
                    dockPill: dockPill
                    anchorX: dockWindow.mediaAnchorX
                    anchorY: dockWindow.mediaAnchorY
                    clearance: dockWindow.magLift
                    open: dockWindow.mediaCardVisible
                    source: media
                    onHoverStateChanged: (on) => {
                        dockWindow.mediaCardHovered = on
                        if (!on)
                            mediaClose.restart()
                        else
                            mediaClose.stop()
                    }
                }
            }
        }
    }

    // One item of the row (see `rowItems`): a key (an app or a folder), the dock-pin
    // button, the media key, or a divider / separator. The Repeater above makes one of
    // these for each. The item itself sits still at its place in the row (`along0`);
    // what moves, grows or leans is `tile` inside it, so the mouse area (which is the
    // dock's one `hit` area now, not one per key) and the layout never flicker.
    Component {
        id: slotDelegate

        Item {
            id: slot
            required property var modelData
            required property int index

            readonly property string kind: slot.modelData.kind
            readonly property bool isApp: slot.kind === "app"
            readonly property bool isFolder: slot.kind === "folder"
            readonly property bool isKey: slot.isApp || slot.isFolder
            readonly property bool isMedia: slot.kind === "media"
            readonly property bool isPin: slot.kind === "pin"
            readonly property bool isTool: slot.kind === "tool"
            readonly property bool isDiv: slot.kind === "divider" || slot.kind === "sep"
            readonly property bool pressable: slot.isKey || slot.isMedia || slot.isPin || slot.isTool
            // Keys that lift / grow under the pointer.
            readonly property bool liftable: slot.isKey || slot.isTool
            readonly property string cls: slot.modelData.class ?? ""

            // The card code asks for the thing that is drawn (shifted, grown).
            readonly property Item anchorItem: tile

            // Where this item stands in the row, and its size.
            readonly property real along0: dockWindow.rowPos[slot.index] ?? 0
            width: dockWindow.vertical ? dockWindow.iconSize : dockWindow.sizeOf(slot.modelData)
            readonly property bool longMedia: slot.isMedia && dockWindow.mediaWide
            height: dockWindow.vertical ? dockWindow.sizeOf(slot.modelData)
                : (slot.longMedia ? dockWindow.mediaHeight : dockWindow.iconSize) + mt.shadowOffset
            x: dockWindow.vertical ? 0 : slot.along0
            y: dockWindow.vertical ? slot.along0 : (slot.longMedia ? -dockWindow.mediaGrow : 0)
            // The key under the pointer (and the one being dragged) is above its
            // neighbours (its flag too).
            z: slot.dragged ? 20 : (slot.lit ? 5 : 0)

            // ===== what the app is doing right now =====
            // Windows (all of them / minimized ones) and whether the app is the one you
            // are in. A folder counts its apps together.
            readonly property var info: slot.isApp ? dockWindow.infoFor(slot.cls, slot.modelData.pinned === true) : null
            readonly property var agg: {
                if (slot.isFolder) {
                    let c = 0
                    let m = 0
                    let f = false
                    for (const a of slot.modelData.apps) {
                        const i = dockWindow.infoFor(a.class, true)
                        if (i) {
                            c += i.count
                            m += i.minCount
                            if (dockWindow.runningMaps.focused === a.class)
                                f = true
                        }
                    }
                    return { count: c, min: m, focused: f }
                }
                if (slot.isApp && slot.info)
                    return { count: slot.info.count, min: slot.info.minCount,
                             focused: dockWindow.runningMaps.focused === slot.cls }
                return { count: 0, min: 0, focused: false }
            }
            readonly property bool running: slot.agg.count > 0
            // The app you are in: its key is held down.
            readonly property bool focused: slot.running && slot.agg.focused
            readonly property int badge: slot.isKey ? dockWindow.notifCount(slot.modelData)
                : (slot.isTool && slot.modelData.tool === "shelf" ? ShelfService.count : 0)

            readonly property bool lit: dockWindow.hoverIdx === slot.index && slot.pressable && !dockWindow.dragging
            readonly property bool dragged: dockWindow.dragging && dockWindow.dragIdx === slot.index
            readonly property bool removing: slot.dragged && dockWindow.dragRemove
            readonly property bool pressedNow: hit.pressed && hit.pressIdx === slot.index && !dockWindow.dragging

            // ===== the pointer =====
            onLitChanged: {
                if (slot.isApp) {
                    if (slot.lit && slot.running)
                        dockWindow.previewHover(slot)
                    else if (slot.lit || dockWindow.wantSlot === slot)
                        dockWindow.previewLeave()
                } else if (slot.isMedia) {
                    dockWindow.mediaHover(slot, slot.lit)
                } else if (slot.lit) {
                    dockWindow.previewLeave()
                }
            }
            Component.onDestruction: {
                if (dockWindow.wantSlot === slot)
                    dockWindow.wantSlot = null
                if (dockWindow.mediaSlot === slot)
                    dockWindow.mediaSlot = null
                if (dockWindow.cardSlot === slot) {
                    dockWindow.cardSlot = null
                    dockWindow.cardOn = false
                }
            }

            // ===== magnification, and making room while dragging =====
            readonly property real mag: dockWindow.magData.scales[slot.index] ?? 1
            readonly property real shift: dockWindow.magData.shifts[slot.index] ?? 0

            // While a key is dragged the ones it passes slide a place aside (or, for an
            // app brought in from the unpinned ones, make room for it).
            readonly property real slide: {
                if (!dockWindow.dragging || slot.dragged || dockWindow.dragRemove || dockWindow.dragFolderRow >= 0)
                    return 0
                if (slot.index >= dockWindow.pinnedCount || dockWindow.dragIdx < 0)
                    return 0
                const from = dockWindow.dragIdx
                const target = dockWindow.dragTarget
                const pitch = dockWindow.sizeOf(dockWindow.rowItems[from]) + dockWindow.iconGap
                if (from < dockWindow.pinnedCount) {
                    if (from < target && slot.index > from && slot.index <= target)
                        return -pitch
                    if (target < from && slot.index >= target && slot.index < from)
                        return pitch
                } else if (slot.index >= target) {
                    return pitch
                }
                return 0
            }
            property real slideOff: slot.slide
            Behavior on slideOff {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            // The dragged key follows the pointer along the dock.
            readonly property real dragOff: slot.dragged
                ? dockWindow.dragAlong - (slot.along0 + dockWindow.sizeOf(slot.modelData) / 2 + slot.shift) : 0

            // How far the key sticks out past the pill, design pixels: a lifted key
            // (no magnification) or a grown one.
            readonly property real pop: dockWindow.magOn
                ? (slot.mag - 1) * (dockWindow.vertical ? dockWindow.iconSize : dockWindow.iconSize + mt.shadowOffset)
                : (slot.lit && slot.liftable ? 7 : 0)

            // Everything that moves is the tile. A key under the pointer lifts off the
            // dock, toward the screen (a held-down key stays down); with magnification
            // on it grows from the dock's edge instead.
            Item {
                id: tile
                width: slot.width
                height: slot.height

                readonly property real along: slot.shift + slot.slideOff + slot.dragOff
                property real rise: (slot.lit && !slot.focused && !dockWindow.magOn && slot.liftable) ? 7 : 0
                x: dockWindow.vertical ? dockWindow.inward * tile.rise : tile.along
                y: dockWindow.vertical ? tile.along : dockWindow.inward * tile.rise
                scale: slot.dragged ? 1.12 : (dockWindow.magOn ? slot.mag : (slot.lit && slot.liftable ? 1.12 : 1))
                transformOrigin: dockWindow.magOn ? dockWindow.outerEdge : Item.Center
                opacity: slot.removing ? 0.45 : 1

                Behavior on rise {
                    NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }
                Behavior on scale {
                    enabled: !dockWindow.magOn
                    NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 140 }
                }

                // The stack: one sheet behind the key for two windows, two for three or
                // more. They are the key's own size and peek out at the corners.
                Rectangle {
                    z: -2
                    visible: slot.isKey && slot.agg.count > 2
                    x: -3
                    y: -2
                    width: slot.width
                    height: slot.height - mt.shadowOffset
                    radius: dockWindow.capKeys ? height / 2 : mt.radiusBadge
                    color: dockWindow.capKeys ? mt.capBody : mt.surface
                    border.width: dockWindow.capKeys ? mt.capDotRing : mt.borderWidth
                    border.color: dockWindow.capKeys ? mt.capRim : mt.line
                    rotation: -10
                    antialiasing: true
                }

                Rectangle {
                    z: -1
                    visible: slot.isKey && slot.agg.count > 1
                    x: 2
                    y: -3
                    width: slot.width
                    height: slot.height - mt.shadowOffset
                    radius: dockWindow.capKeys ? height / 2 : mt.radiusBadge
                    color: dockWindow.capKeys ? mt.capBody : mt.surface
                    border.width: dockWindow.capKeys ? mt.capDotRing : mt.borderWidth
                    border.color: dockWindow.capKeys ? mt.capRim : mt.line
                    rotation: 7
                    antialiasing: true
                }

                Loader {
                    anchors.fill: parent
                    active: slot.isApp
                    sourceComponent: appFace
                }

                Loader {
                    anchors.fill: parent
                    active: slot.isFolder
                    sourceComponent: folderFace
                }

                Loader {
                    anchors.fill: parent
                    active: slot.isPin
                    sourceComponent: pinFace
                }

                Loader {
                    anchors.fill: parent
                    active: slot.isTool
                    sourceComponent: toolFace
                }

                Loader {
                    anchors.fill: parent
                    active: slot.isMedia
                    sourceComponent: dockWindow.mediaWide ? mediaWideFace : mediaFace
                }

                DockDivider {
                    visible: slot.isDiv
                    vertical: dockWindow.vertical
                    iconSize: dockWindow.iconSize
                    capsule: dockWindow.capKeys
                    thickness: dockWindow.dockDividerWidth
                }

                // Notifications waiting for this app.
                DockBadge {
                    x: tile.width - width / 2 - 3
                    y: -height / 2 + 3
                    z: 10
                    count: slot.badge
                }
            }

            // The running dot, on the dock's outer side of the key (it follows the key
            // along the dock but does not grow with it).
            Item {
                x: dockWindow.vertical ? 0 : tile.along
                y: dockWindow.vertical ? tile.along : 0
                width: slot.width
                height: slot.height
                visible: dockWindow.indicatorsOn && slot.isKey
                opacity: slot.dragged ? 0 : 1

                DockRunDot {
                    x: dockWindow.position === "left" ? -11
                        : (dockWindow.position === "right" ? slot.width + 1 : (slot.width - width) / 2)
                    y: dockWindow.position === "bottom" ? slot.height - 1
                        : (dockWindow.position === "top" ? -9 : (dockWindow.iconSize - height) / 2)
                    capsule: dockWindow.capKeys
                    mode: !slot.running ? "none"
                        : (slot.focused ? "focused" : (slot.agg.min === slot.agg.count ? "hidden" : "running"))
                }
            }

            // ===== the name flag =====
            Pill {
                id: flag

                readonly property bool wanted: slot.removing
                    || (slot.lit && ((slot.isApp && !slot.running) || slot.isFolder
                                     || (slot.isTool && dockWindow.toolOpen !== slot.modelData.tool)))
                property real shown: flag.wanted ? 1 : 0
                Behavior on shown {
                    NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }

                readonly property string hint: slot.removing ? "release to remove" : "click to open"

                visible: flag.shown > 0.01
                z: 60
                cornerRadius: 13
                borderWidth: 3
                // The same outline + 2 px white line as every block (the calendar's
                // prev / next keys): it was 3.5, a white line only half a pixel thick.
                ringWidth: mt.borderWidth + mt.whiteLine
                shadowDx: 3
                shadowDy: 4
                width: Math.max(flagTitle.width, flagHint.width) + 46
                height: (flag.hint !== "" ? 50 : 38) + shadowDy
                scale: Math.max(0.05, flag.shown)
                opacity: Math.min(1, flag.shown * 1.6)
                rotation: -2.5 + (1 - Math.min(1, flag.shown)) * 8
                transformOrigin: dockWindow.vertical
                    ? (dockWindow.position === "left" ? Item.Left : Item.Right)
                    : (dockWindow.position === "bottom" ? Item.Bottom : Item.Top)

                // Beside a standing dock, on the screen side; above (or under) a flat
                // one. Past a grown key, and moving with it.
                x: dockWindow.vertical
                    ? (dockWindow.position === "left" ? slot.width + 22 + slot.pop : -flag.width - 22 - slot.pop)
                    : Math.round((slot.width - flag.width) / 2) + tile.along
                y: dockWindow.vertical
                    ? Math.round((slot.height - flag.height) / 2) + tile.along
                    : (dockWindow.position === "bottom" ? -flag.height - 18 - slot.pop : slot.height + 18 + slot.pop)

                Row {
                    anchors.centerIn: parent
                    spacing: 9

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 3
                        rotation: 45
                        color: slot.running ? mt.accentMint : mt.ringWhite
                        border.width: 2
                        border.color: mt.line
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            id: flagTitle
                            width: Math.min(implicitWidth, 210)
                            text: slot.modelData.displayName ?? ""
                            elide: Text.ElideRight
                            color: mt.ink
                            font.family: mt.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }

                        Text {
                            id: flagHint
                            visible: flag.hint !== ""
                            width: visible ? implicitWidth : 0
                            height: visible ? implicitHeight : 0
                            text: flag.hint
                            color: mt.inkSub
                            font.family: mt.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            // ===== the faces =====
            // An app's key: the real app icon from the icon theme, in a rounded square.
            Component {
                id: appFace

                Pill {
                    id: iconPill
                    anchors.fill: parent

                    // Same rounded-square shape as the workspace badges
                    // (WorkspaceBadges.qml: Theme.radiusBadge), not a circle. The icon
                    // clip / disc / mask below use the radius of the Pill's inner fill
                    // so the icon follows that shape.
                    // Capsule: a round chip, a thin ring, no outline, no hard shadow.
                    cornerRadius: dockWindow.capKeys ? Math.min(iconPill.capWidth, iconPill.capHeight) / 2 : mt.radiusBadge
                    ringWidth: dockWindow.keyRing
                    borderWidth: dockWindow.capKeys ? 0 : mt.borderWidth
                    flat: dockWindow.capKeys
                    fillColor: dockWindow.capKeys ? mt.capBody : mt.surface
                    // The ring is lit mint-to-cyan under the pointer and on the key that
                    // is held down; plain white otherwise.
                    readonly property bool on: slot.lit || slot.focused
                    ringColorTop: dockWindow.ringTop(iconPill.on)
                    ringColorBottom: dockWindow.ringBottom(iconPill.on)
                    // Held down while you are in the app, and under a finger.
                    pressed: slot.pressedNow || slot.focused

                    // The icon is drawn ~25% oversized before the rounded mask crops it
                    // back down. Icon-theme assets carry wildly inconsistent amounts of
                    // built-in transparent padding (Steam fills its square edge to edge,
                    // Figma sits centered in a mostly empty canvas), so zooming every
                    // icon in by the same fixed amount crops that padding away
                    // consistently and they all touch the ring.
                    //
                    // The crop is a MultiEffect mask over a layer with an explicit
                    // texture size, not a ClippingRectangle: a layer is otherwise drawn
                    // at its item's design size, and the dock is drawn inside a ScaleHost
                    // (which just stretches everything by uiScale), so the icon would be
                    // made small and blown up whenever the scale wasn't 100%. `texel` is
                    // real screen pixels per design pixel.
                    Item {
                        id: iconClip
                        anchors.fill: parent

                        // Corner radius of the Pill's inner fill (see Pill.qml).
                        readonly property real shapeRadius: Math.max(0, iconPill.cornerRadius - iconPill.ringWidth)

                        readonly property real texel: dockWindow.uiScale
                            * (dockWindow.screen ? dockWindow.screen.devicePixelRatio : 1)

                        // Icons are drawn small, so any softness or stair-stepping shows.
                        // Decode the icon and build its layer / mask at `oversample` x the
                        // real pixel size, and let the mipmapped layer scale that down onto
                        // the screen. Magnified keys are drawn bigger than that, so the
                        // factor is never less than the biggest magnification.
                        readonly property real oversample: Math.max(2, Math.ceil(dockWindow.magMax))

                        // Unplugged: a pinned app that isn't running shows its icon grey,
                        // in colour while you point at it.
                        readonly property bool unplugged: !slot.running && !slot.lit

                        // The white disc behind the icon (transparent icon corners show
                        // white).
                        Rectangle {
                            anchors.fill: parent
                            radius: iconClip.shapeRadius
                            color: dockWindow.capKeys ? mt.capBody : mt.surface
                            antialiasing: true
                        }

                        Item {
                            id: iconLayer
                            anchors.fill: parent

                            layer.enabled: true
                            layer.smooth: true
                            layer.mipmap: true
                            layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * iconClip.texel * iconClip.oversample)),
                                                       Math.max(1, Math.ceil(height * iconClip.texel * iconClip.oversample)))
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: iconMask
                                saturation: iconClip.unplugged ? -0.9 : 0
                                brightness: iconClip.unplugged ? 0.1 : 0

                                Behavior on saturation {
                                    NumberAnimation { duration: 220 }
                                }
                                Behavior on brightness {
                                    NumberAnimation { duration: 220 }
                                }
                            }

                            Image {
                                readonly property real zoom: 1.25
                                width: parent.width * zoom
                                height: parent.height * zoom
                                anchors.centerIn: parent
                        source: IconCursorService.path(slot.modelData.iconName, true)|| IconCursorService.path("application-x-executable")
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                // Decoded at (oversample x) the size it lands on screen, so
                                // SVG icons are rasterised sharp at any scale.
                                sourceSize: Qt.size(Math.ceil(width * iconClip.texel * iconClip.oversample),
                                                    Math.ceil(height * iconClip.texel * iconClip.oversample))
                            }
                        }

                        // The rounded mask, at the same texture density as the icon so its
                        // edge is as sharp as the icon.
                        Item {
                            id: iconMask
                            anchors.fill: parent
                            visible: false

                            layer.enabled: true
                            layer.smooth: true
                            layer.mipmap: true
                            layer.textureSize: iconLayer.layer.textureSize

                            Rectangle {
                                anchors.fill: parent
                                radius: iconClip.shapeRadius
                                color: "black"
                                antialiasing: true
                            }
                        }
                    }
                }
            }

            // A folder's key: the first four of its apps, small, in the same housing.
            Component {
                id: folderFace

                Pill {
                    id: folderPill
                    anchors.fill: parent
                    cornerRadius: dockWindow.capKeys ? Math.min(folderPill.capWidth, folderPill.capHeight) / 2 : mt.radiusBadge
                    ringWidth: dockWindow.keyRing
                    borderWidth: dockWindow.capKeys ? 0 : mt.borderWidth
                    flat: dockWindow.capKeys
                    fillColor: dockWindow.capKeys ? mt.capBody : mt.surfaceDivider
                    readonly property bool on: slot.lit || slot.focused
                    ringColorTop: dockWindow.ringTop(folderPill.on)
                    ringColorBottom: dockWindow.ringBottom(folderPill.on)
                    pressed: slot.pressedNow || slot.focused

                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 1.5

                        Repeater {
                            model: slot.modelData.apps.slice(0, 4)

                            delegate: Image {
                                required property var modelData
                                readonly property real cell: Math.max(6, (dockWindow.iconSize - 14) / 2 - 1.5)
                                width: cell
                                height: cell
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(Math.ceil(cell * 2 * dockWindow.uiScale), Math.ceil(cell * 2 * dockWindow.uiScale))
                               source: IconCursorService.path(modelData.iconName, true)|| IconCursorService.path("application-x-executable")
                            }
                        }
                    }
                }
            }

            // The dock pin: keeps the dock above windows (see the layer comment above).
            // Same ring treatment as the keys, except it also stays lit while the dock
            // is pinned, so you can tell the state at a glance. Not an app, so it never
            // touches PinnedAppsService's app list — only dockPinned.
            Component {
                id: pinFace

                Pill {
                    readonly property bool on: slot.lit || dockWindow.dockPinned
                    cornerRadius: capHeight / 2
                    ringWidth: dockWindow.keyRing
                    borderWidth: dockWindow.capKeys ? 0 : mt.borderWidth
                    flat: dockWindow.capKeys
                    fillColor: dockWindow.capKeys ? mt.capBody : mt.surface
                    ringColorTop: dockWindow.ringTop(on)
                    ringColorBottom: dockWindow.ringBottom(on)
                    pressed: slot.pressedNow

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "push_pin"
                        color: dockWindow.capKeys ? mt.capInk : mt.ink
                        size: Math.max(16, dockWindow.iconSize * 0.57)
                        // Upright when pinned, tilted when not; always outline (the lit
                        // ring says pinned / hovered).
                        fill: 0
                        rotation: dockWindow.dockPinned ? 0 : 45
                    }
                }
            }

            // A tool's key: its icon on the same keycap. The Timer shows the time left on
            // top of a fill that rises as it runs; the Shelf takes drops (files or text).
            Component {
                id: toolFace

                Pill {
                    id: toolPill
                    readonly property string tool: slot.modelData.tool
                    readonly property bool timing: tool === "timer" && TimerService.anyRunning
                    readonly property bool on: slot.lit || dockWindow.toolOpen === tool || timing || shelfDrop.containsDrag
                    cornerRadius: dockWindow.capKeys ? Math.min(toolPill.capWidth, toolPill.capHeight) / 2 : mt.radiusBadge
                    ringWidth: dockWindow.keyRing
                    borderWidth: dockWindow.capKeys ? 0 : mt.borderWidth
                    flat: dockWindow.capKeys
                    fillColor: dockWindow.capKeys ? mt.capBody : mt.surface
                    ringColorTop: dockWindow.ringTop(toolPill.on)
                    ringColorBottom: dockWindow.ringBottom(toolPill.on)
                    pressed: slot.pressedNow || dockWindow.toolOpen === toolPill.tool

                    // The fill: how far through the timer / pomodoro / stopwatch minute.
                    // Capsule: the key is a circle, so the fill is the part of that circle below
                    // a rising level line (it never leaves the circle), in the capsule's pink.
                    Shape {
                        id: capFill
                        visible: toolPill.timing && dockWindow.capKeys && capFill.p > 0.004
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        readonly property real r: Math.min(capFill.width, capFill.height) / 2
                        readonly property real p: Math.max(0, Math.min(1, TimerService.shownProgress))
                        // Half the angle, seen from the circle's bottom, that the level line cuts.
                        readonly property real phi: Math.acos(1 - 2 * capFill.p) * 180 / Math.PI

                        ShapePath {
                            strokeWidth: 0
                            strokeColor: "transparent"
                            fillColor: Qt.rgba(mt.capLit.r, mt.capLit.g, mt.capLit.b, 0.55)
                            PathAngleArc {
                                centerX: capFill.width / 2
                                centerY: capFill.height / 2
                                radiusX: capFill.r
                                radiusY: capFill.r
                                startAngle: 90 - capFill.phi
                                sweepAngle: 2 * capFill.phi
                            }
                        }
                    }

                    // Float / Transparent: a bar rising from the bottom of the rounded key.
                    Rectangle {
                        visible: toolPill.timing && !dockWindow.capKeys
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * TimerService.shownProgress
                        radius: 4
                        color: Qt.rgba(mt.accentMint.r, mt.accentMint.g, mt.accentMint.b, 0.55)
                    }

                    MaterialIcon {
                        visible: !toolPill.timing
                        anchors.centerIn: parent
                        name: (dockWindow.toolMeta[toolPill.tool] ?? { icon: "build" }).icon
                        color: dockWindow.capKeys ? mt.capInk : mt.ink
                        size: Math.max(16, dockWindow.iconSize * 0.57)
                        // Always outline: hover / open / drop is shown by the lit ring
                        // and the pressed key, not by filling the glyph.
                        fill: 0
                    }

                    Text {
                        visible: toolPill.timing
                        anchors.centerIn: parent
                        text: TimerService.shownText
                        color: dockWindow.capKeys ? mt.capInk : mt.ink
                        font.family: mt.fontFamily
                        font.pixelSize: Math.max(9, dockWindow.iconSize * 0.3)
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }

                    DropArea {
                        id: shelfDrop
                        anchors.fill: parent
                        enabled: toolPill.tool === "shelf"
                        onEntered: dockWindow.dragKey = true
                        onExited: dockWindow.dragKey = false
                        onDropped: (drop) => {
                            dockWindow.dragKey = false
                            ShelfService.addDrop(drop)
                            // Copy, not the proposed action: the shelf only remembers where a
                            // file is, so the source must not think it was moved.
                            drop.accept(Qt.CopyAction)
                        }
                    }
                }
            }

            // The media key on a dock along the top or bottom: a long pill with the cover
            // and the title (and artist, and a thin progress line) on the left, and
            // previous / play-pause / next on the right. The dock's one mouse area does
            // the clicking (see `mediaZone`); this only draws, and lights the button the
            // pointer is over.
            Component {
                id: mediaWideFace

                Pill {
                    id: widePill
                    // Capsule: fully rounded, flat, in the capsule keys' thin ring (and the cover
                    // is a circle that fills its left end); the other styles keep the rounded
                    // rectangle with the cover cut square at its left.
                    cornerRadius: dockWindow.capKeys ? Math.min(widePill.capWidth, widePill.capHeight) / 2 : mt.radiusBadge
                    ringWidth: dockWindow.mediaRing
                    borderWidth: dockWindow.capKeys ? 0 : mt.borderWidth
                    flat: dockWindow.capKeys
                    fillColor: dockWindow.capKeys ? mt.capBody : mt.surface
                    readonly property bool on: slot.lit || media.playing
                    ringColorTop: dockWindow.ringTop(widePill.on)
                    ringColorBottom: dockWindow.ringBottom(widePill.on)
                    // The whole pill presses down only for the cover / title; the buttons press themselves.
                    pressed: slot.pressedNow && hit.pressZone === "body"

                    // The right side shows the blurred cover: text and buttons go white on it.
                    readonly property bool onArt: blurCover.status === Image.Ready
                    readonly property color textColor: widePill.onArt ? "white" : mt.ink
                    readonly property color subColor: widePill.onArt ? Qt.rgba(1, 1, 1, 0.82) : mt.inkSub

                    readonly property real innerH: dockWindow.mediaInnerH
                    readonly property bool compact: widePill.innerH < 40
                    readonly property string zone: slot.lit
                        ? dockWindow.mediaZone(dockWindow.mediaLocal(dockWindow.pointerAlong)) : ""

                    readonly property var player: media.player
                    readonly property bool hasLength: widePill.player !== null && widePill.player.lengthSupported === true
                                                      && widePill.player.length > 0
                    readonly property real progress: widePill.hasLength && widePill.player.positionSupported
                        ? Math.max(0, Math.min(1, widePill.player.position / widePill.player.length)) : 0

                    // The player doesn't announce its position; ask for it while it plays.
                    Timer {
                        interval: 1000
                        repeat: true
                        running: widePill.hasLength && media.playing && !dockWindow.tucked
                        onTriggered: widePill.player.positionChanged()
                    }

                    // Cover, wrapped like the bar's media pill: edge to edge at the left
                    // end of the pill, as tall as it, with its outer corners following the
                    // pill's own rounded shape and its right edge square.
                    Item {
                        id: wideArt
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        // Capsule: a circle (as wide as the pill is tall), over the blur that
                        // runs under it.
                        width: dockWindow.capKeys ? height : widePill.innerH
                        z: 1

                        readonly property real shapeRadius: Math.max(0, widePill.cornerRadius - widePill.ringWidth)
                        readonly property real texel: dockWindow.uiScale
                            * (dockWindow.screen ? dockWindow.screen.devicePixelRatio : 1)

                        // No mask: the picture is square and DockArtFrame redraws the
                        // pill's own ring and outline over its two left corners (the
                        // way the bar's media pill does), so they follow the pill's curve.
                        Item {
                            id: wideArtLayer
                            anchors.fill: parent
                            clip: !dockWindow.capKeys

                            // Capsule: cut round with a mask (the square cover and its corner
                            // patches below can't make a circle).
                            layer.enabled: dockWindow.capKeys
                            layer.smooth: true
                            layer.mipmap: true
                            layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * wideArt.texel * 2)),
                                                       Math.max(1, Math.ceil(height * wideArt.texel * 2)))
                            layer.effect: MultiEffect {
                                maskEnabled: dockWindow.capKeys
                                maskSource: wideArtMask
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: mt.surfaceDivider
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: wideCover.status !== Image.Ready
                                name: "genres"
                                size: Math.max(16, wideArt.width * 0.45)
                            }

                            Image {
                                id: wideCover
                                anchors.fill: parent
                                visible: status === Image.Ready
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(Math.ceil(width * wideArt.texel * 2),
                                                    Math.ceil(height * wideArt.texel * 2))
                                source: media.artUrl
                                opacity: media.playing ? 1 : 0.7
                            }
                        }

                        Item {
                            id: wideArtMask
                            anchors.fill: parent
                            visible: false

                            layer.enabled: dockWindow.capKeys
                            layer.smooth: true
                            layer.textureSize: wideArtLayer.layer.textureSize

                            Rectangle {
                                anchors.fill: parent
                                radius: Math.min(width, height) / 2
                                color: "black"
                                antialiasing: true
                            }
                        }

                        DockArtFrame {
                            visible: !dockWindow.capKeys
                            edge: "left"
                            cornerRadius: widePill.cornerRadius
                            ringWidth: widePill.ringWidth
                            ringTop: widePill.ringColorTop
                            ringBottom: widePill.ringColorBottom
                        }
                    }

                    // The right of the pill: the same cover, blurred and tinted, behind the
                    // text and buttons. Its right corners follow the pill's shape and its
                    // left edge is square against the sharp cover.
                    Item {
                        id: wideBlur
                        // Capsule: it runs the whole length, under the round cover (whose
                        // corners then show the blur, not the pill's fill).
                        anchors.left: dockWindow.capKeys ? parent.left : wideArt.right
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: blurCover.status === Image.Ready
                        clip: true

                        Item {
                            id: wideBlurLayer
                            anchors.fill: parent

                            layer.enabled: wideBlur.visible
                            layer.smooth: true
                            layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * wideArt.texel)),
                                                       Math.max(1, Math.ceil(height * wideArt.texel)))
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: 0.7
                                blurMax: 32
                                // No fade-out to transparent at the edges (that was the haze).
                                autoPaddingEnabled: false
                                // Capsule: the whole pill's rounded shape.
                                maskEnabled: dockWindow.capKeys
                                maskSource: wideBlurMask
                            }

                            // Drawn a little oversized, so the blur has picture to sample at the edges.
                            Image {
                                id: blurCover
                                anchors.centerIn: parent
                                width: parent.width * 1.4
                                height: parent.height * 1.4
                                asynchronous: true
                                smooth: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(160, 160)
                                source: media.artUrl
                                opacity: media.playing ? 1 : 0.7
                            }

                            // The tint: the theme's navy darkens it a little so the picture keeps
                            // its colour (white over it only made it look dusty) and the white
                            // text on it reads, plus a touch of the theme's cyan.
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(mt.colBorder.r, mt.colBorder.g, mt.colBorder.b, 0.38)
                            }
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.08)
                            }
                        }

                        Item {
                            id: wideBlurMask
                            anchors.fill: parent
                            visible: false

                            layer.enabled: dockWindow.capKeys
                            layer.smooth: true
                            layer.textureSize: wideBlurLayer.layer.textureSize

                            Rectangle {
                                anchors.fill: parent
                                radius: wideArt.shapeRadius
                                color: "black"
                                antialiasing: true
                            }
                        }

                        DockArtFrame {
                            visible: !dockWindow.capKeys
                            edge: "right"
                            cornerRadius: widePill.cornerRadius
                            ringWidth: widePill.ringWidth
                            ringTop: widePill.ringColorTop
                            ringBottom: widePill.ringColorBottom
                        }
                    }

                    // The three buttons, on the right.
                    Row {
                        id: wideButtons
                        anchors.right: parent.right
                        anchors.rightMargin: dockWindow.mediaPadR
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: dockWindow.mediaBtnGap

                        Repeater {
                            model: ["prev", "play", "next"]

                            delegate: Rectangle {
                                id: wideBtn
                                required property string modelData
                                readonly property bool isPlay: wideBtn.modelData === "play"
                                readonly property bool hot: widePill.zone === wideBtn.modelData
                                readonly property bool down: slot.pressedNow && hit.pressZone === wideBtn.modelData
                                readonly property string glyph: wideBtn.modelData === "prev" ? "skip_previous"
                                    : (wideBtn.modelData === "next" ? "skip_next" : (media.playing ? "pause" : "play_arrow"))

                                width: dockWindow.mediaBtn
                                height: dockWindow.mediaBtn
                                radius: width / 2
                                antialiasing: true
                                color: wideBtn.isPlay ? mt.accentCyan
                                    : (wideBtn.hot ? (widePill.onArt ? Qt.rgba(1, 1, 1, 0.24) : mt.surfaceDivider) : "transparent")
                                border.width: wideBtn.isPlay ? 2 : 0
                                border.color: mt.line
                                scale: wideBtn.down ? 0.88 : (wideBtn.hot ? 1.08 : 1)

                                Behavior on scale {
                                    NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: wideBtn.glyph
                                    size: Math.round(parent.width * 0.64)
                                    fill: 0
                                    color: wideBtn.isPlay ? mt.colBorder : widePill.textColor
                                }
                            }
                        }
                    }

                    // Title, artist and the progress line, between the cover and the buttons.
                    Column {
                        anchors.left: wideArt.right
                        anchors.leftMargin: 10
                        anchors.right: wideButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: media.title
                            color: widePill.textColor
                            font.family: mt.fontFamily
                            font.pixelSize: Math.max(10, Math.round(widePill.innerH * 0.28))
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }

                        Text {
                            visible: !widePill.compact && media.artist !== ""
                            width: parent.width
                            elide: Text.ElideRight
                            text: media.artist
                            color: widePill.subColor
                            font.family: mt.fontFamily
                            font.pixelSize: Math.max(9, Math.round(widePill.innerH * 0.21))
                            font.weight: Font.Bold
                        }

                        Rectangle {
                            visible: !widePill.compact && widePill.hasLength
                            width: parent.width
                            height: 4
                            radius: 2
                            color: widePill.onArt ? Qt.rgba(1, 1, 1, 0.3) : mt.surfaceDivider

                            Rectangle {
                                width: parent.width * widePill.progress
                                height: parent.height
                                radius: parent.radius
                                color: mt.accentMint
                            }
                        }
                    }
                }
            }

            // The media key: the cover of what is playing, with a play / pause mark.
            // The ring is lit while something plays.
            Component {
                id: mediaFace

                Pill {
                    id: mediaPill
                    cornerRadius: dockWindow.capKeys ? Math.min(mediaPill.capWidth, mediaPill.capHeight) / 2 : mt.radiusBadge
                    ringWidth: dockWindow.keyRing
                    borderWidth: dockWindow.capKeys ? 0 : mt.borderWidth
                    flat: dockWindow.capKeys
                    fillColor: dockWindow.capKeys ? mt.capBody : mt.surface
                    readonly property bool on: slot.lit || media.playing
                    ringColorTop: dockWindow.ringTop(mediaPill.on)
                    ringColorBottom: dockWindow.ringBottom(mediaPill.on)
                    pressed: slot.pressedNow

                    Rectangle {
                        id: coverBox
                        anchors.fill: parent
                        radius: Math.max(0, mediaPill.cornerRadius - mediaPill.ringWidth)
                        color: mt.surfaceDivider
                        antialiasing: true

                        readonly property real texel: dockWindow.uiScale
                            * (dockWindow.screen ? dockWindow.screen.devicePixelRatio : 1)

                        // The cover is square: it is cut to the key's shape with a mask (a
                        // Rectangle's `clip` only clips to its box, so the corners stuck out of
                        // the circle). Same layer + mask the app keys use, at the same density.
                        Item {
                            id: coverLayer
                            anchors.fill: parent

                            layer.enabled: true
                            layer.smooth: true
                            layer.mipmap: true
                            layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * coverBox.texel * Math.max(2, Math.ceil(dockWindow.magMax)))),
                                                       Math.max(1, Math.ceil(height * coverBox.texel * Math.max(2, Math.ceil(dockWindow.magMax)))))
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: coverMask
                            }

                            Image {
                                id: cover
                                anchors.fill: parent
                                visible: status === Image.Ready
                                asynchronous: true
                                smooth: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(Math.ceil(dockWindow.iconSize * 2 * dockWindow.uiScale),
                                                    Math.ceil(dockWindow.iconSize * 2 * dockWindow.uiScale))
                                source: media.artUrl
                                opacity: media.playing ? 1 : 0.7
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: cover.status !== Image.Ready
                                name: "genres"
                                color: dockWindow.capKeys ? mt.capInk : mt.ink
                                size: Math.max(16, dockWindow.iconSize * 0.55)
                            }
                        }

                        Item {
                            id: coverMask
                            anchors.fill: parent
                            visible: false

                            layer.enabled: true
                            layer.smooth: true
                            layer.mipmap: true
                            layer.textureSize: coverLayer.layer.textureSize

                            Rectangle {
                                anchors.fill: parent
                                radius: coverBox.radius
                                color: "black"
                                antialiasing: true
                            }
                        }

                        // Play / pause mark in the corner (Capsule: on the circle's lower right,
                        // where the square's own corner is empty).
                        Rectangle {
                            x: dockWindow.capKeys ? parent.width / 2 + (parent.width / 2 - 5) * 0.7071 - width / 2
                                                  : parent.width - width - 1
                            y: dockWindow.capKeys ? parent.height / 2 + (parent.height / 2 - 5) * 0.7071 - height / 2
                                                  : parent.height - height - 1
                            width: 15
                            height: 15
                            radius: 7.5
                            color: dockWindow.capKeys ? mt.capBody : mt.surface
                            border.width: 1.5
                            border.color: dockWindow.capKeys ? mt.capRim : mt.line
                            antialiasing: true

                            MaterialIcon {
                                anchors.centerIn: parent
                                name: media.playing ? "pause" : "play_arrow"
                                color: dockWindow.capKeys ? mt.capInk : mt.ink
                                size: 11
                                fill: 1
                            }
                        }
                    }
                }
            }
        }
    }
}
