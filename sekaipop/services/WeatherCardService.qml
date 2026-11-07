pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// The desktop weather card widget's state — where the card sits and whether it's
// shown — kept as its own singleton (like ClockService.qml) so anything else
// can flip it without touching WeatherCardWidget.qml:
//
//   import qs.services
//   ...
//   WeatherCardService.setShown(false)
//
// WeatherCardWidget.qml is the only thing that draws it. The weather itself is
// not stored here: the card asks Open-Meteo through its own WeatherSource.qml (the
// same one the bar's weather pill uses), and the place and the unit come from
// Settings -> General -> Weather.
//
// Persistence is the same convention as ClockService: a tiny shell script
// (weathercard-state.sh) run as a Process. Position is saved straight away, the
// rest is debounced.
Singleton {
    id: root

    // False until the saved state has been read. Nothing is written before
    // then, or a fresh start would overwrite what's on disk with defaults.
    property bool loaded: false

    property bool shown: false       // off until you add it: ipc weathercard toggle / Edit Desktop (a first run shows only the clock)
    // The card's style: "classic" (plate, gauges and the forecast) or "minimal" (the plate and
    // one row of the next hours). Both are the same 2 x 2 footprint. Remembered across
    // restarts and kept by a desktop preset. Switch it in Settings -> Desktop, with the
    // style key that shows on the card while it is selected in Edit Desktop, or
    // `ipc call weathercard style minimal|classic`. ("full" was the old name of classic:
    // it still works everywhere and reads as classic.)
    property string style: "classic"
    readonly property bool minimal: root.style === "minimal"

    // The card's size: "2x2" (320 x 276 with the housing, the footprint the clock and the other
    // cards share; both styles above live in it) or "1x1" (160 x 138: only the temperature, a
    // quarter of the 2x2; it has no styles). Remembered across restarts. Switch it in Settings ->
    // Desktop, with the second key that shows on the card while it is selected in Edit Desktop,
    // or `ipc call weathercard size 2x2|1x1`.
    property string size: "2x2"
    readonly property bool tiny: root.size === "1x1"
    property real posX: -1           // -1 = never placed; widget picks a default
    property real posY: -1
    // The shell scale (ShellScale) posX / posY were saved at. They are in design
    // pixels, so the card stays on the same spot of the screen when the shell
    // is scaled up or down: the widget turns them into screen pixels with this
    // and back into design pixels with its current scale. 0 = saved before this
    // was kept (the widget adopts the current scale then, see its `settle`).
    property real posScale: 0
    // The monitor (output name, e.g. "DP-1") the card was last dropped on.
    // Empty = never dropped yet (the widget uses the first screen).
    property string screenName: ""

    // Saved straight away (no wait): a refresh or reload right after you drop
    // the card must not be able to beat the save.
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

    // "minimal" and "classic"; anything else (the old "full" too) is "classic".
    function setStyle(value) {
        const v = value === "minimal" ? "minimal" : "classic"
        if (v === root.style)
            return
        root.style = v
        root.persist()
    }

    function toggleStyle() {
        root.setStyle(root.minimal ? "classic" : "minimal")
    }

    // "1x1" (or "tiny"); anything else is "2x2". The style is kept while the card is 1x1.
    function setSize(value) {
        const v = (value === "1x1" || value === "tiny") ? "1x1" : "2x2"
        if (v === root.size)
            return
        root.size = v
        root.persist()
    }

    function toggleSize() {
        root.setSize(root.tiny ? "2x2" : "1x1")
    }

    // ===== persistence =====
    readonly property string script: Directories.script("state/weathercard-state.sh")

    function snapshot() {
        return JSON.stringify({
            x: root.posX,
            y: root.posY,
            scale: root.posScale,
            screen: root.screenName,
            shown: root.shown,
            style: root.style,
            size: root.size
        })
    }

    function restore(text) {
        try {
            const s = JSON.parse(text)
            if (typeof s.x === "number")
                root.posX = s.x
            if (typeof s.y === "number")
                root.posY = s.y
            if (typeof s.scale === "number" && s.scale > 0)
                root.posScale = s.scale
            if (typeof s.screen === "string")
                root.screenName = s.screen
            root.shown = s.shown !== false
            // A file (or a preset) saved before the styles existed has none: the card keeps
            // the style it has.
            if (typeof s.style === "string")
                root.style = s.style === "minimal" ? "minimal" : "classic"
            root.size = s.size === "1x1" ? "1x1" : "2x2"
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
        interval: 300
        onTriggered: saver.save(root.snapshot())
    }

    // Fire-and-forget save. Queues at most one pending snapshot behind an
    // in-flight save rather than dropping it, so the *last* state is what
    // ends up on disk (same reasoning as ClockService's `saver`).
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
