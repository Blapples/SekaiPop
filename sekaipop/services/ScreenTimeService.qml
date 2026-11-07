pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../modules/common/functions/ScreenTimeMath.js" as STM
import qs.modules.common

// How long the screen has been in use today, and which apps it went to: what the bar's screen
// time pill (ScreenTimeIndicator.qml, ScreenTimePopup.qml) shows. One count for the whole shell
// (the bars on every monitor read this one), kept as a singleton like WaterTankService.qml.
//
//   import qs.services
//   ...
//   ScreenTimeService.total        // seconds today
//
// What counts: time while the session is unlocked and you have touched the keyboard or mouse in
// the last `idleSeconds` (Wayland's idle notification, the same one hypridle listens to, but read
// here only to tell "at the screen" from "walked away"; a compositor without it counts all the
// unlocked time). The time goes to whichever window has focus when it is counted (Hyprland only:
// on another compositor the total still counts, the per-app list just stays empty).
//
// Right-click on the pill changes how it writes the time ("3h 12m", "03:12", "03:12:45");
// the choice is remembered ("bar.screenTimeFormat").
//
// Counting runs only while the pill is switched on (Settings -> Bar -> Modules, "bar.screenTime"):
// with it off nothing is read and nothing is written.
//
// A day is a local calendar day. Every tick checks it, so the count starts again at 0 after
// midnight and yesterday's total goes into `history` (30 days are kept, for the week bars).
//
// Persistence is the same convention as WaterTankService: a tiny shell script (screentime-state.sh)
// run as a Process. Saved every 10 seconds while something changed, and when the day changes.
//
//   qs -c sekaipop ipc call screentime status
//   qs -c sekaipop ipc call screentime reset        today back to 0 (the days before stay)
Singleton {
    id: root

    // False until the saved state has been read. Nothing is written before then, or a fresh
    // start would overwrite what's on disk with defaults.
    property bool loaded: false

    // The pill's master switch (Settings -> Bar -> Modules).
    readonly property bool enabled: SettingsService.flag("bar.screenTime")

    // Seconds without input after which you count as away.
    readonly property int idleSeconds: 180

    // ===== the day =====
    property string day: ""          // the day `total` belongs to ("2026-10-27")
    property real total: 0           // seconds today
    property var apps: ({})          // { "firefox": seconds today, ... }
    property var history: ({})       // { "2026-10-26": seconds, ... } the days before today

    readonly property var topToday: STM.topApps(root.apps, 0)
    readonly property string shortText: STM.shortText(root.total)

    // How the pill writes the time (right-click on it cycles): short "3h 12m", clock "03:12",
    // seconds "03:12:45". Only the last one changes every second, so only it ticks that often.
    readonly property string format: STM.normalizeFormat(SettingsService.get("bar.screenTimeFormat"))
    readonly property string pillText: STM.formatText(root.total, root.format)
    // The widest this format can get: the pill keeps that width so nothing beside it moves.
    readonly property string pillTemplate: STM.formatTemplate(root.format)

    function cycleFormat() {
        SettingsService.set("bar.screenTimeFormat", STM.nextFormat(root.format))
    }
    readonly property string longText: STM.longText(root.total)
    readonly property var bars: STM.weekBars(root.history, root.total, root.day !== "" ? root.day : STM.dayKey(new Date()), 7)
    readonly property real average: STM.average(root.history, root.day !== "" ? root.day : STM.dayKey(new Date()), 7)

    // What the pill's hover tag says: the total and the app it mostly went to.
    readonly property string tipText: {
        const top = root.topToday.length > 0 ? root.topToday[0] : null
        const base = "Screen time today: " + root.longText
        return top ? base + " · most in " + root.displayName(top.key) : base
    }

    // ===== counting =====
    // Created when the idle notification exists (Quickshell 0.2 and newer); null otherwise.
    property var idleMonitor: null
    readonly property bool idle: root.idleMonitor ? root.idleMonitor.isIdle : false
    readonly property bool counting: root.loaded && root.enabled && !LockState.locked && !root.idle

    property real lastTick: 0
    property bool dirty: false

    Component.onCompleted: {
        try {
            root.idleMonitor = Qt.createQmlObject(
                "import Quickshell.Wayland\nIdleMonitor { timeout: " + root.idleSeconds + " }",
                root, "ScreenTimeIdle")
        } catch (e) {
            root.idleMonitor = null
        }
    }

    // The focused window's class, "" when none has focus (or this is not Hyprland).
    function currentClass() {
        const w = Hyprland.activeToplevel
        if (!w)
            return ""
        return w.wayland?.appId || w.lastIpcObject?.class || w.lastIpcObject?.initialClass || ""
    }

    // "Firefox" for "org.mozilla.firefox": the .desktop entry's name when there is one.
    function displayName(key) {
        if (key === "")
            return ""
        try {
            const entry = DesktopEntries.heuristicLookup(key)
            if (entry && entry.name)
                return entry.name
        } catch (e) {}
        return STM.prettyApp(key)
    }

    // The app's icon as a file url ("" when it has no .desktop entry or no icon).
    function iconFor(key) {
        if (key === "")
            return ""
        try {
            const entry = DesktopEntries.heuristicLookup(key)
            if (entry && entry.icon)
                return IconCursorService.path(entry.icon, "application-x-executable")
        } catch (e) {}
        return ""
    }

    // The count starts again after midnight; yesterday's total goes into the history.
    function checkDay() {
        if (!root.loaded)
            return
        const r = STM.rollover({ day: root.day, total: root.total, apps: root.apps, history: root.history },
                               STM.dayKey(new Date()))
        if (!r.changed)
            return
        root.day = r.day
        root.total = r.total
        root.apps = r.apps
        root.history = r.history
        root.save()
    }

    function tick() {
        const now = Date.now()
        const dt = STM.elapsed(root.lastTick, now)
        root.lastTick = now
        if (!root.loaded)
            return
        root.checkDay()
        if (!root.counting || dt <= 0)
            return
        const r = STM.addTime(root.total, root.apps, STM.appKey(root.currentClass()), dt)
        root.total = r.total
        root.apps = r.apps
        root.dirty = true
    }

    // Today back to 0 (the days before stay).
    function resetToday() {
        if (!root.loaded)
            return
        root.total = 0
        root.apps = ({})
        root.save()
    }

    Timer {
        interval: root.format === "seconds" ? 1000 : 5000
        repeat: true
        running: root.loaded && root.enabled
        triggeredOnStart: false
        onRunningChanged: if (running) root.lastTick = Date.now()
        onTriggered: root.tick()
    }

    // ===== persistence =====
    readonly property string script: Directories.script("state/screentime-state.sh")

    function snapshot() {
        return JSON.stringify({
            day: root.day,
            total: Math.round(root.total),
            apps: STM.trimApps(root.apps),
            history: root.history
        })
    }

    function restore(text) {
        try {
            const s = JSON.parse(text)
            if (typeof s.day === "string")
                root.day = s.day
            if (typeof s.total === "number" && s.total >= 0)
                root.total = Math.min(s.total, 86400)
            if (s.apps && typeof s.apps === "object")
                root.apps = STM.trimApps(s.apps)
            if (s.history && typeof s.history === "object")
                root.history = STM.trimHistory(s.history, STM.dayKey(new Date()))
        } catch (e) {
            // No file yet (first run) or an unreadable one: keep the defaults.
        }
        root.loaded = true
        root.lastTick = Date.now()
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

    // Written straight away (a new day, a reset); the ticks only mark the count as changed.
    function save() {
        if (!root.loaded)
            return
        root.dirty = false
        saver.save(root.snapshot())
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.loaded && root.enabled
        onTriggered: if (root.dirty) root.save()
    }

    // Fire-and-forget save. Queues at most one pending snapshot behind an in-flight save rather
    // than dropping it, so the *last* state is what ends up on disk (same as WaterTankService).
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
