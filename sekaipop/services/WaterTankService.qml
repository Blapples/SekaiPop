pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/WaterMath.js" as WTM
import qs.modules.common

// The desktop Water Tank widget's state: where it sits, whether it is shown, how big it is, and
// the water itself (how many glasses today, the daily goal, the size of a glass, and the last
// days). Kept as its own singleton (like WeatherCardService.qml) so anything else can add a
// glass or flip the widget without touching WaterTankWidget.qml:
//
//   import qs.services
//   ...
//   WaterTankService.addGlass()
//
// WaterTankWidget.qml (and WaterTile.qml, its 1 x 1 face) are the only things that draw it.
//
// A day is a local calendar day. The widget calls checkDay() once a minute while it is on
// screen, and every change calls it first, so the count starts again at 0 after midnight and
// yesterday's count goes into `history` (the last 14 days are kept, for the week bars and the
// streak).
//
// Persistence is the same convention as WeatherCardService: a tiny shell script
// (watertank-state.sh) run as a Process. Position is saved straight away, the rest is debounced.
//
// What a desktop preset holds (PresetWidgets.qml): the spot, the monitor, the size and on / off.
// The glasses, the goal, the glass size and the history are yours, not the look's.
Singleton {
    id: root

    // False until the saved state has been read. Nothing is written before then, or a fresh
    // start would overwrite what's on disk with defaults.
    property bool loaded: false

    property bool shown: false       // off until you add it: ipc watertank toggle / Edit Desktop (a first run shows only the clock)

    // The widget's size: "1x1" (154 x 132 with the housing: one tank you tap) or "2x2" (320 x 276:
    // the tank, the keys, the week and the streak). Remembered across restarts. Switch it in
    // Settings -> Desktop, with the size key that shows on the widget while it is selected in
    // Edit Desktop, or `ipc call watertank size 1x1|2x2`.
    property string size: "1x1"
    readonly property bool tiny: root.size === "1x1"

    property real posX: -1           // -1 = never placed; widget picks a default
    property real posY: -1
    // The shell scale (ShellScale) posX / posY were saved at (see WeatherCardService.qml).
    property real posScale: 0
    // The monitor (output name, e.g. "DP-1") it was last dropped on. Empty = the first screen.
    property string screenName: ""

    // ===== the water =====
    property int goal: 8             // glasses a day
    property int glassMl: 250        // the size of one glass
    property int glasses: 0          // today's count
    property string day: ""          // the day `glasses` belongs to ("2026-10-27")
    property var history: ({})       // { "2026-10-26": 7, ... } the days before today

    readonly property real level: WTM.fraction(root.glasses, root.goal)
    readonly property bool done: WTM.reached(root.glasses, root.goal)
    readonly property string amountText: WTM.amountText(root.glasses, root.glassMl)
    readonly property string goalText: WTM.amountText(root.goal, root.glassMl)

    // Fired after a glass is added (a click, the wheel, the + key, `ipc call watertank add`), so the
    // widget can squash and throw its puff. Not for a glass taken back.
    signal glassAdded()

    // The count starts again after midnight; yesterday's goes into the history.
    function checkDay() {
        if (!root.loaded)
            return
        const r = WTM.rollover({ day: root.day, glasses: root.glasses, history: root.history }, WTM.dayKey(new Date()))
        if (!r.changed)
            return
        root.day = r.day
        root.glasses = r.glasses
        root.history = r.history
        root.persist()
    }

    function addGlass(n) {
        if (!root.loaded)
            return
        root.checkDay()
        const by = typeof n === "number" && n > 0 ? Math.round(n) : 1
        root.glasses = Math.min(99, root.glasses + by)
        root.persist()
        root.glassAdded()
    }

    function removeGlass() {
        if (!root.loaded)
            return
        root.checkDay()
        if (root.glasses <= 0)
            return
        root.glasses = root.glasses - 1
        root.persist()
    }

    // Today's count back to 0 (yesterday and before stay).
    function resetToday() {
        if (!root.loaded)
            return
        root.checkDay()
        root.glasses = 0
        root.persist()
    }

    function setGoal(value) {
        const v = WTM.clampGoal(value)
        if (v === root.goal)
            return
        root.goal = v
        root.persist()
    }

    function setGlassMl(value) {
        const v = WTM.clampGlass(value)
        if (v === root.glassMl)
            return
        root.glassMl = v
        root.persist()
    }

    // Saved straight away (no wait): a refresh or reload right after you drop the widget must
    // not be able to beat the save.
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

    // "1x1" (or "tiny"); anything else is "2x2".
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
    readonly property string script: Directories.script("state/watertank-state.sh")

    function snapshot() {
        return JSON.stringify({
            x: root.posX,
            y: root.posY,
            scale: root.posScale,
            screen: root.screenName,
            shown: root.shown,
            size: root.size,
            goal: root.goal,
            glassMl: root.glassMl,
            glasses: root.glasses,
            day: root.day,
            history: root.history
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
            // A preset (or a file) that says nothing about it leaves the widget off.
            root.shown = s.shown === true
            root.size = s.size === "2x2" ? "2x2" : "1x1"
            if (typeof s.goal === "number")
                root.goal = WTM.clampGoal(s.goal)
            if (typeof s.glassMl === "number")
                root.glassMl = WTM.clampGlass(s.glassMl)
            if (typeof s.glasses === "number" && s.glasses >= 0)
                root.glasses = Math.min(99, Math.round(s.glasses))
            if (typeof s.day === "string")
                root.day = s.day
            if (s.history && typeof s.history === "object")
                root.history = WTM.trimHistory(s.history, WTM.dayKey(new Date()))
        } catch (e) {
            // No file yet (first run) or an unreadable one: keep the defaults.
        }
        root.loaded = true
        // After a restart on a later day: yesterday goes into the history.
        root.checkDay()
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

    // Fire-and-forget save. Queues at most one pending snapshot behind an in-flight save rather
    // than dropping it, so the *last* state is what ends up on disk (same as WeatherCardService).
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
