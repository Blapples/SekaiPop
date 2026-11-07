pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/common/functions/PaletteMath.js" as PM

// The Palette tool's state (modules/sekai/palette/PaletteTool.qml): the five colours
// being looked at, which of them are locked, where they came from, the saved
// favourites, and the theme that was worn before the last Apply.
//
// THE RULE: looking at a palette never changes the theme. Everything here
// (colors, shuffle, locks, favourites, copy) only changes THIS file's state, and the
// tool's live preview draws from `colors` through PaletteMath.toShell, never through
// ThemeService. The theme changes in exactly two functions, apply() and undo(), and
// the tool calls them only from the Apply and Undo buttons.
//
//   import qs.services
//   PaletteService.shuffle()
//   PaletteService.copy("#04feee")
//
// Persistence is the same convention as WeatherCardService: a tiny script
// (palette-state.sh) run as a Process, debounced.
Singleton {
    id: root

    // False until the saved state has been read; nothing is written before then.
    property bool loaded: false
    // True until the tool has been used once (no saved state): the first picture it
    // reads is poured onto the strip so a new user starts from their own colours.
    property bool fresh: true

    // The palette on the strip: five "#rrggbb", dark to light when it came from a picture.
    property var colors: ["#555473", "#6e6d94", "#04feee", "#00ffcb", "#d9fff6"]
    // true = this swatch keeps its colour through a shuffle / a new picture
    property var locks: [false, false, false, false, false]
    // The tab: "wallpaper" | "music" | "random"
    property string source: "wallpaper"
    // The harmony the last shuffle used ("" when the colours came from a picture)
    property string scheme: ""
    // [{ colors: [5 hex], source }], newest first, at most 48
    property var favorites: []
    // The theme id worn before the last Apply, so Undo can put it back
    property string prevTheme: ""

    readonly property bool isFavorite: PM.isFavorite(root.favorites, root.colors)
    // The shell is wearing exactly the strip's colours right now
    readonly property bool applied: ThemeService.current === "custom"
        && PM.sameColors(ThemeService.customColors, root.colors)
    readonly property bool canUndo: ThemeService.current === "custom"
        && root.prevTheme !== "" && root.prevTheme !== "custom" && ThemeService.has(root.prevTheme)

    // ===== the desktop widget (modules/sekai/desktopWidgets/PaletteWidget.qml) =====
    // Off until you add it (Edit Desktop, Settings -> Desktop, or the ipc): a shell update
    // must not put a new card over your desktop by itself.
    property bool shown: false       // ipc: palettecard toggle / show / hide

    // The card's size: "full", "2x2" or "1x1". "full" is the card as it has always been; "2x2" is the footprint the
    // clock, user card and weather card share (320 x 276), so the cards line up as a set.
    // Remembered across restarts. Switch it in Settings -> Desktop, with the size key that
    // shows on the card while it is selected in Edit Desktop, or `ipc call palettecard size 1x1|2x2|full`.
    property string size: "full"
    readonly property bool small: root.size === "2x2"
    // "1x1" is a quarter of the 2x2 (160 x 138 with the housing): a tile, not a card.
    readonly property bool tiny: root.size === "1x1"
    property real posX: -1           // -1 = never placed; the widget picks a default
    property real posY: -1
    // The shell scale posX / posY were saved at, in design pixels (same idea as
    // CalendarCardService): 0 = saved before this was kept.
    property real posScale: 0
    // The monitor (output name, e.g. "DP-1") the card was last dropped on.
    property string screenName: ""
    // True while the big tool (PaletteTool.qml) is open, so the widget does not read the
    // picture a second time for the same colours.
    property bool toolOpen: false

    // Asks the tool (PaletteTool.qml) to open on the focused monitor; Settings and the
    // widget's expand key use it.
    signal openRequested()

    function requestOpen() {
        root.openRequested()
    }

    // ===== looking (these never touch the theme) =====
    function setSource(name) {
        if (name !== "wallpaper" && name !== "music" && name !== "random")
            return
        root.source = name
        root.persist()
    }

    // Colours from a picture: `list` is whatever the quantizer gave. Locked swatches keep
    // their colour, the others take the new ones.
    function fillFrom(list, src) {
        const picked = PM.pick(list, PM.SLOTS)
        root.colors = PM.fill(root.colors, picked, root.locks)
        root.fresh = false
        root.scheme = ""
        if (src)
            root.source = src
        root.persist()
    }

    function shuffle() {
        const kept = []
        for (let i = 0; i < PM.SLOTS; i++)
            kept.push(root.locks[i] ? root.colors[i] : "")
        const r = PM.random({ locked: kept })
        root.colors = r.colors
        root.scheme = r.scheme
        root.source = "random"
        root.persist()
    }

    function toggleLock(i) {
        if (i < 0 || i >= PM.SLOTS)
            return
        const l = root.locks.slice()
        l[i] = !l[i]
        root.locks = l
        root.persist()
    }

    function saveFavorite() {
        root.favorites = PM.addFavorite(root.favorites, root.colors, root.source, 48)
        root.persist()
    }

    function removeFavorite(colors) {
        root.favorites = PM.removeFavorite(root.favorites, colors)
        root.persist()
    }

    function toggleFavorite() {
        if (root.isFavorite)
            root.removeFavorite(root.colors)
        else
            root.saveFavorite()
    }

    // A saved palette back on the strip (locks are cleared, it replaces all five).
    function useFavorite(colors) {
        const c = PM.parse(colors)
        if (!c)
            return
        root.colors = c
        root.locks = [false, false, false, false, false]
        root.scheme = ""
        root.persist()
    }

    function copy(hex) {
        const h = PM.norm(hex)
        if (h === "")
            return false
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", h])
        return true
    }

    function copyAll() {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", root.colors.join(", ")])
    }

    // ===== the widget's place =====
    // Saved straight away (no wait): a reload right after you drop the card must not be
    // able to beat the save. None of this touches the theme.
    function setPosition(x, y, screen, scale) {
        if (!root.loaded)
            return
        root.posX = x
        root.posY = y
        if (typeof scale === "number" && scale > 0)
            root.posScale = scale
        if (typeof screen === "string" && screen !== "")
            root.screenName = screen
        saveTimer.stop()
        saver.save(root.snapshot())
    }

    function setShown(value) {
        root.shown = value
        root.persist()
    }

    // "1x1" (or "tiny"), "2x2" (or "small") and "full"; anything else is "full".
    function setSize(value) {
        const v = (value === "1x1" || value === "tiny") ? "1x1"
            : (value === "2x2" || value === "small") ? "2x2" : "full"
        if (v === root.size)
            return
        root.size = v
        root.persist()
    }

    // One press goes full -> 2x2 -> 1x1 -> full.
    function toggleSize() {
        root.setSize(root.tiny ? "full" : (root.small ? "1x1" : "2x2"))
    }

    // ===== wearing (the only two places the theme changes) =====
    function apply() {
        if (root.applied)
            return
        if (ThemeService.current !== "custom")
            root.prevTheme = ThemeService.current
        ThemeService.applyPalette(root.colors)
        root.persist()
    }

    function undo() {
        if (!root.canUndo)
            return
        ThemeService.setTheme(root.prevTheme)
    }

    // ===== persistence =====
    readonly property string script: Directories.script("state/palette-state.sh")

    function snapshot() {
        return JSON.stringify({
            v: 1,
            colors: root.colors,
            locks: root.locks,
            source: root.source,
            scheme: root.scheme,
            favorites: root.favorites,
            prev: root.prevTheme,
            fresh: root.fresh,
            x: root.posX,
            y: root.posY,
            scale: root.posScale,
            screen: root.screenName,
            shown: root.shown,
            size: root.size
        })
    }

    function restore(text) {
        try {
            const s = JSON.parse(text)
            // A file made before the widget existed has no `fresh`: the tool had been used.
            root.fresh = s.fresh === true
            const c = PM.parse(s.colors)
            if (c)
                root.colors = c
            if (Array.isArray(s.locks) && s.locks.length === PM.SLOTS)
                root.locks = s.locks.map(v => v === true)
            if (s.source === "wallpaper" || s.source === "music" || s.source === "random")
                root.source = s.source
            if (typeof s.scheme === "string")
                root.scheme = s.scheme
            root.favorites = PM.cleanFavorites(s.favorites)
            if (typeof s.prev === "string")
                root.prevTheme = s.prev
            if (typeof s.x === "number")
                root.posX = s.x
            if (typeof s.y === "number")
                root.posY = s.y
            if (typeof s.scale === "number" && s.scale > 0)
                root.posScale = s.scale
            if (typeof s.screen === "string")
                root.screenName = s.screen
            root.shown = s.shown === true
            root.size = (s.size === "2x2" || s.size === "1x1") ? s.size : "full"
        } catch (e) {
            // No file yet (first run) or an unreadable one: keep the defaults.
        }
        root.loaded = true
    }

    // Runs once, at startup.
    Process {
        running: true
        command: ["sh", root.script, "load"]
        stdout: StdioCollector {
            onStreamFinished: root.restore(text)
        }
    }

    function persist() {
        if (root.loaded)
            saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: saver.save(root.snapshot())
    }

    // Queues at most one pending snapshot behind an in-flight save, so the last state wins.
    Process {
        id: saver

        property var pending: null

        function save(json) {
            if (saver.running) {
                saver.pending = json
                return
            }
            saver.pending = null
            saver.exec(["sh", root.script, "save", json])
        }

        onExited: {
            if (saver.pending !== null) {
                const json = saver.pending
                saver.pending = null
                saver.exec(["sh", root.script, "save", json])
            }
        }
    }
}
