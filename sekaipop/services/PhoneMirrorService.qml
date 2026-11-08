pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import "../modules/common/functions/PhoneMirror.js" as PMir

// The phone mirror: your Android phone's screen, live, on a phone at the side of the screen
// (modules/sekai/phoneMirror/). A port of p3drovfx's illogical-impulse scrcpy phone mirror,
// without KDE Connect: the phone is found with `adb` alone (USB, or Wi-Fi after `connect`).
//
//   qs -c sekaipop ipc call phonemirror toggle | show | hide
//   qs -c sekaipop ipc call phonemirror connect 192.168.1.20:5555
//   qs -c sekaipop ipc call phonemirror start | stop | restart | detach | key <home|back|recents|power|...>
//
// Needs `scrcpy` and `adb` (pacman -S scrcpy android-tools), USB debugging on the phone, and
// Hyprland, with a Lua config or a plain hyprland.conf (the window is placed either way).
//
// How it works. Wayland has no window embedding, so the picture and the touches are carried
// separately:
//
//   - The picture is a `ScreencopyView` of scrcpy's own window, which the panel draws like any
//     other item: rounded, clipped, sliding with the panel. Nothing goes through main memory
//     and no v4l2 loopback, kernel module or re-encode is involved.
//
//   - The touches are the real thing. scrcpy's window waits off the side of every monitor and,
//     while the panel is settled, is moved to sit exactly under the picture and pinned there.
//     The panel cuts that rectangle out of its input region, so a click lands on scrcpy at
//     the very coordinates the user aimed at, and scrcpy does what it has always done with it:
//     multi-touch, scrolling, the keyboard, the clipboard. The window itself is never seen,
//     the panel paints over every pixel of it.
//
// The window is only attached while it is fully covered. Anything that can uncover it (the
// panel still sliding in, a monitor change) parks it again first.
Singleton {
    id: root

    // ===== what the panel is doing =====
    // The panel is up (or sliding in). The panel's window reads this and animates itself.
    property bool shown: false
    // The monitor it comes up on: whichever was focused when it was opened.
    property string targetScreenName: ""
    readonly property var targetScreen: {
        const screens = Quickshell.screens ?? []
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === root.targetScreenName)
                return screens[i]
        }
        return screens.length > 0 ? screens[0] : null
    }

    function show(): void {
        const m = Hyprland.focusedMonitor
        root.targetScreenName = m ? m.name : ""
        // "Start when opened" off: the panel comes up with scrcpy off, unless it is already on.
        if (!SettingsService.flag("phoneMirror.autoStart") && !root.embedRunning && !root.embedLaunching)
            root.stopped = true
        root.shown = true
        root.refresh()
    }

    function hide(): void {
        root.shown = false
    }

    function toggle(): void {
        if (root.shown)
            root.hide()
        else
            root.show()
    }

    // ===== starting and stopping scrcpy =====
    // Showing the panel and running scrcpy are two things. `stopped` is the user's own "scrcpy
    // off": the panel can be up (showing a Start key) with nothing running and the phone left
    // alone. It is only this shell's memory of the last Start / Stop, so a restarted shell
    // begins with scrcpy on, unless Settings says opening the panel should not start it.
    property bool stopped: false
    readonly property bool sessionOn: !root.stopped

    // Starts mirroring, if it is off, and looks at the phone again.
    function start(): void {
        root.stopped = false
        root.embedError = ""
        root.waitingText = ""
        root.placementError = ""
        root.refresh()
        root._start()
    }

    // Ends the mirror now (the phone stops encoding) and keeps it off until Start. The
    // separate scrcpy window, if there is one, is closed too.
    function stop(): void {
        root.stopped = true
        root.embedError = ""
        root.waitingText = ""
        root.placementError = ""
        root.release()
        if (root.windowRunning)
            root.closeWindow()
    }

    function toggleSession(): void {
        if (root.stopped)
            root.start()
        else
            root.stop()
    }

    // ===== tools =====
    property bool scrcpyAvailable: false
    property string scrcpyVersion: ""
    property bool adbMissing: false
    // The tools are looked for each time the panel opens, so installing them needs no reload.
    function refresh(): void {
        if (!scrcpyProbe.running) scrcpyProbe.running = true
        root._pollDevices()
        if (root.address !== "") root.connectAddress(root.address)
    }

    Process {
        id: scrcpyProbe
        command: ["scrcpy", "--version"]
        stdout: SplitParser {
            onRead: line => {
                const v = PMir.parseVersion(line)
                if (v) {
                    root.scrcpyAvailable = true
                    root.scrcpyVersion = v.major + "." + v.minor
                }
            }
        }
        // Not installed: the process never starts, or exits 127.
        onExited: (code, status) => { if (code !== 0) root.scrcpyAvailable = false }
    }

    // ===== the phone =====
    property var devices: []
    readonly property string wantedSerial: SettingsService.get("phoneMirror.serial")
    readonly property string address: SettingsService.get("phoneMirror.address")
    readonly property var device: PMir.pickDevice(root.devices, root.wantedSerial)
    // "ready" | "unauthorized" | "offline" | "none"
    readonly property string deviceStatus: PMir.deviceStatus(root.devices, root.wantedSerial)
    readonly property bool adbReady: root.device !== null
    readonly property string deviceName: root.device ? (root.device.model || root.device.serial) : ""

    function targetArgs(): var {
        return root.device ? ["-s", root.device.serial] : []
    }

    // While the panel is up, ask every few seconds: a cable plugged in, a phone that was
    // locked, the debugging prompt accepted. Not at all while it is away.
    Timer {
        interval: 4000
        repeat: true
        running: root.shown
        onTriggered: root._pollDevices()
    }

    function _pollDevices(): void {
        if (devicesProc.running)
            return
        devicesProc.running = true
    }

    Process {
        id: devicesProc
        command: ["sh", "-c", "command -v adb >/dev/null 2>&1 || exit 127; adb devices -l"]
        stdout: StdioCollector {
            onStreamFinished: root.devices = PMir.parseDevices(this.text)
        }
        onExited: (code, status) => {
            root.adbMissing = code === 127
            if (code !== 0)
                root.devices = []
        }
    }

    // `adb connect host:port`, for a phone on Wi-Fi (Settings > Developer options > Wireless
    // debugging). The address is kept, so it is tried again each time the panel opens.
    function connectAddress(text: string): void {
        const addr = PMir.normalizeAddress(text)
        if (addr === "")
            return
        if (addr !== root.address)
            SettingsService.set("phoneMirror.address", addr)
        connectProc.command = ["adb", "connect", addr]
        connectProc.running = false
        connectProc.running = true
    }

    function forgetAddress(): void {
        const addr = root.address
        SettingsService.set("phoneMirror.address", "")
        if (addr !== "")
            Quickshell.execDetached(["adb", "disconnect", addr])
        root._pollDevices()
    }

    Process {
        id: connectProc
        onExited: root._pollDevices()
    }

    // The phone's resolution. The frame has to have its aspect ratio exactly, or scrcpy
    // letterboxes inside a window the panel drew to fit. Read once per session.
    property int deviceWidth: 0
    property int deviceHeight: 0
    readonly property real deviceAspect: (root.deviceWidth > 0 && root.deviceHeight > 0)
        ? (root.deviceWidth / root.deviceHeight)
        : (9 / 20)

    function _probeDeviceSize(): void {
        if (!root.adbReady)
            return
        sizeProc.running = false
        sizeProc.command = ["adb"].concat(root.targetArgs()).concat(["shell", "wm", "size"])
        sizeProc.running = true
    }

    Process {
        id: sizeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const s = PMir.parseSize(this.text)
                if (s) {
                    root.deviceWidth = s.w
                    root.deviceHeight = s.h
                }
            }
        }
    }

    // ===== the options =====
    function _options(): var {
        return {
            "stayAwake": SettingsService.flag("phoneMirror.stayAwake"),
            "turnScreenOff": SettingsService.flag("phoneMirror.turnScreenOff"),
            "audio": SettingsService.flag("phoneMirror.audio"),
            "maxFps": SettingsService.get("phoneMirror.maxFps"),
            "bitRate": SettingsService.get("phoneMirror.bitRate"),
            "keyboard": SettingsService.get("phoneMirror.keyboard"),
            "clipboardSync": SettingsService.flag("phoneMirror.clipboardSync")
        }
    }

    // ===== sessions =====
    readonly property string embedId: "embed"
    readonly property string windowId: "window"
    property bool embedRunning: false
    property bool embedLaunching: false
    property string embedError: ""
    property bool windowRunning: false
    // What the manager says while it holds a launch back ("Unlock your phone ...").
    property string waitingText: ""

    // Hyprland with a Lua config takes Lua calls; a plain hyprland.conf takes the classic
    // dispatchers. Same rule as the bar, the dock and the overview: only an explicit `false`
    // means "not Lua".
    readonly property bool usingLua: Hyprland.usingLua !== false
    readonly property string windowTitle: PMir.windowTitle(root.embedId)

    // The mirror stays up this long after the panel goes away, so a trip back does not pay
    // for a fresh connection. The phone keeps encoding for that long, which is why it is
    // bounded (and can be set to 0).
    readonly property int keepWarmMs: Math.max(0, SettingsService.get("phoneMirror.keepWarm")) * 1000

    // scrcpy reads its options once, when it starts, and a session that is already up (kept warm
    // after the panel closed, or just shown) is reused as it is. So a changed option did nothing
    // until the mirror was stopped and started by hand ("Turn the phone's screen off" looked
    // broken). The options that become scrcpy arguments are watched as one string, and a change
    // while a session is up restarts it. Debounced, so a few quick changes restart it once.
    readonly property string _launchOptionsKey: JSON.stringify(root._options())
    on_LaunchOptionsKeyChanged: optionsRestartTimer.restart()

    Timer {
        id: optionsRestartTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.embedRunning || root.embedLaunching)
                root.restart()
        }
    }

    // ----- the session manager -----
    // It only acts on commands written to its stdin and sits in a blocking read between them,
    // so it is started when there is a command to send, and shut down once it has been idle
    // with no live session. Never while one is running: it owns those scrcpy processes and
    // reports their exit.
    property bool _managerWanted: false
    property var _pendingCommands: []

    function _send(payload): void {
        root._managerWanted = true
        managerIdle.restart()
        const line = JSON.stringify(payload) + "\n"
        // Process.write() is thrown away while the child is still being spawned, and `running`
        // is already true by then: only processId tells the two apart. So a command sent right
        // after the manager started waits for onStarted.
        if (!manager.processId) {
            root._pendingCommands = root._pendingCommands.concat([line])
            return
        }
        manager.write(line)
    }

    Timer {
        id: managerIdle
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.embedRunning && !root.embedLaunching && !root.windowRunning)
                root._managerWanted = false
        }
    }

    Process {
        id: manager
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "python3", Directories.script("phone/scrcpy_session_manager.py")]
        running: root._managerWanted

        onStarted: {
            const queued = root._pendingCommands
            root._pendingCommands = []
            for (let i = 0; i < queued.length; i++) manager.write(queued[i])
        }

        // Every session was this process' child and nothing will report on them again.
        onExited: {
            root.embedRunning = false
            root.embedLaunching = false
            root.windowRunning = false
            const queued = root._pendingCommands.length > 0
            root._managerWanted = false
            if (queued) Qt.callLater(() => { root._managerWanted = true })
        }

        stdout: SplitParser {
            onRead: data => root._onManagerLine(data)
        }

        stderr: SplitParser {
            onRead: data => { if (data.trim().length > 0) console.warn("[PhoneMirrorService manager]", data) }
        }
    }

    function _onManagerLine(data): void {
        let msg
        try {
            msg = JSON.parse(data)
        } catch (e) {
            console.warn("[PhoneMirrorService] not JSON:", data)
            return
        }
        const id = msg.id
        root._log("manager: " + msg.event + " " + id + (msg.reason ? " (" + msg.reason + ")" : "")
                  + (msg.code !== undefined ? " code " + msg.code : "") + (msg.error ? " " + msg.error : "")
                  + (msg.message ? " " + msg.message : ""))
        switch (msg.event) {
        case "started":
            if (id === root.embedId) {
                root.embedRunning = true
                root.embedLaunching = false
                root.embedError = ""
                root.waitingText = ""
            } else if (id === root.windowId) {
                root.windowRunning = true
            }
            break
        case "waiting":
            if (id === root.embedId) root.embedLaunching = true
            root.waitingText = PMir.waitingText(msg)
            break
        case "exited": {
            const asked = !!root._intentionalStops[id] || msg.deliberate === true
            const resuming = root._maybeResume(id, msg.code, msg.deliberate === true)
            // A drop that is about to be reopened is not worth a message, and neither is a stop
            // the user asked for. A non-zero exit that printed nothing is still a failure.
            const failed = msg.code !== 0 && !resuming && !asked
            if (id === root.embedId) {
                root.embedRunning = false
                root.embedLaunching = resuming
                if (failed) root.embedError = PMir.friendlyError(msg.error || "")
            } else if (id === root.windowId) {
                root.windowRunning = false
                if (failed) root._notify("Phone window closed", PMir.friendlyError(msg.error || ""))
            }
            delete root._intentionalStops[id]
            break
        }
        case "error":
            root.waitingText = ""
            if (id === root.embedId) {
                root.embedLaunching = false
                root.embedError = PMir.friendlyError(msg.message || "")
            } else {
                root._notify("Phone mirroring failed", PMir.friendlyError(msg.message || ""))
            }
            break
        }
    }

    // `qs -c sekaipop log | grep PhoneMirror` shows what the mirror did and in which order.
    function _log(text: string): void {
        console.info("[PhoneMirror] " + text)
    }

    function _notify(title: string, body: string): void {
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "smartphone", title, body])
    }

    // ----- starting and stopping -----
    // Asked for by the panel; it says when its frame has stopped moving, and the encoder is
    // then sized from the frame it comes to rest on (see _streamSize).
    property var _intentionalStops: ({})
    property var _resumeAttempts: ({})

    function _launchEmbed(): void {
        if (root.stopped || !root.adbReady || !root.scrcpyAvailable) return
        root._probeDeviceSize()
        const size = PMir.streamSize(root.touchRect.width, root.touchRect.height, root._screenScale())
        root.embedLaunching = true
        root.embedError = ""
        delete root._intentionalStops[root.embedId]
        root._send({
            "cmd": "launch",
            "id": root.embedId,
            "target_args": root.targetArgs(),
            "extra_args": PMir.embedArgs(root._options(), size),
            "auto_unlock": SettingsService.flag("phoneMirror.autoUnlock")
        })
    }

    function _screenScale(): real {
        const s = root.targetScreen
        return s ? Math.max(1, Math.min(2, s.devicePixelRatio || 1)) : 1
    }

    function _stopEmbedNow(): void {
        root._park()
        root._intentionalStops[root.embedId] = true
        root.embedLaunching = false
        root._send({ "cmd": "stop", "id": root.embedId })
        root.attached = false
        root.captureReady = false
    }

    // Drops the embedded session now instead of keeping it warm.
    function release(): void {
        launchDebounce.stop()
        stopGrace.stop()
        if (root.embedRunning || root.embedLaunching || root.toplevel)
            root._stopEmbedNow()
    }

    // The screen's "Try again": look at everything again, and start over.
    function retry(): void {
        root.embedError = ""
        root.waitingText = ""
        root.placementError = ""
        root._placedAttached = false
        root.refresh()
        root._start()
        root._schedulePlacement()
    }

    function restart(): void {
        root.stopped = false
        root.release()
        restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 700
        repeat: false
        onTriggered: if (root.shown) root._start()
    }

    // Hands the phone to a normal scrcpy window, for when the panel is too small for what is
    // on screen. The embedded session is let go first: both would keep the phone streaming.
    function openWindow(): void {
        if (!root.adbReady || !root.scrcpyAvailable) return
        if (root.windowRunning) {
            root._send({ "cmd": "focus", "id": root.windowId })
            return
        }
        root.release()
        delete root._intentionalStops[root.windowId]
        root._send({
            "cmd": "launch",
            "id": root.windowId,
            "target_args": root.targetArgs(),
            "extra_args": PMir.windowArgs(root._options()),
            "auto_unlock": SettingsService.flag("phoneMirror.autoUnlock")
        })
    }

    function closeWindow(): void {
        root._intentionalStops[root.windowId] = true
        root._send({ "cmd": "stop", "id": root.windowId })
    }

    // The embedded session has no window of its own to close it from, so the shell says, every
    // few seconds, that it still wants it. The manager ends it when that stops: the panel
    // closed, the config reloaded, the shell died.
    Timer {
        interval: 5000
        repeat: true
        running: root.embedRunning && (root.shown || stopGrace.running)
        triggeredOnStart: true
        onTriggered: root._send({ "cmd": "keepalive", "id": root.embedId })
    }

    // ----- the panel's lease -----
    // Where the picture is, in the panel window's own coordinates, and whether it has come to
    // rest. The panel sets these (PhoneMirror.qml).
    // Written only by the panel (PhoneMirror.qml binds it), never here: the panel is the one that
    // knows its picture has come to rest, and a value set from this side would stay wrong until
    // the panel's own answer happened to change.
    property bool touchWanted: false
    property rect touchRect: Qt.rect(0, 0, 0, 0)
    property string layerNamespace: "sekaipop-phonemirror"
    // Matched to the frame's corner radius: the window sits exactly under the frame, so square
    // corners would poke past the rounded picture.
    property int cornerRadius: 0
    property bool attached: false

    onShownChanged: {
        root._stuckTicks = 0
        root._healRestarts = 0
        if (root.shown) {
            captureHoldTimer.stop()
            root.captureHold = false
            stopGrace.stop()
            root._start()
        } else {
            // Before _park: it is what takes the picture's conditions away.
            root.captureHold = root.attached && root.captureReady
            if (root.captureHold)
                captureHoldTimer.restart()
            launchDebounce.stop()
            root._park()
            if (root.embedRunning || root.embedLaunching)
                stopGrace.restart()
        }
    }

    Timer {
        id: stopGrace
        interval: Math.max(1000, root.keepWarmMs)
        repeat: false
        onTriggered: if (!root.shown) root._stopEmbedNow()
    }

    function _start(): void {
        if (root.stopped || !root.scrcpyAvailable || !root.adbReady) return
        if (root.embedRunning || root.embedLaunching) {
            root._schedulePlacement()
            return
        }
        // Even a measured frame is still growing into place on the way in, and the encoder is
        // sized once: what it wants is the rectangle the frame comes to rest on.
        launchDebounce.restart()
    }

    Timer {
        id: launchDebounce
        interval: 260
        repeat: false
        onTriggered: {
            if (!root.shown || root.embedRunning || root.embedLaunching) return
            if (root.touchRect.height <= 0) { launchDebounce.restart(); return }
            // A mirror this engine never asked for is one kept warm across a config reload:
            // starting beside it would leave two scrcpy windows fighting for the same frame.
            if (root.toplevel && !root.embedRunning) {
                root._send({ "cmd": "stop", "id": root.embedId })
                root.toplevel.close()
            }
            root._launchEmbed()
        }
    }

    // The tools or the phone turned up after the panel was opened.
    onScrcpyAvailableChanged: if (root.shown) root._start()
    // The phone's real shape is only read once the panel is already up (a first open starts with
    // a guess of 20:9), so the frame changes size under a window that has just been placed.
    // Placing it again on the shape that arrives is what a close and an open used to do by hand.
    onDeviceAspectChanged: {
        if (root.shown && root.attached) {
            root._log("phone shape known (" + root.deviceWidth + "x" + root.deviceHeight + "), placing again")
            root.reassertGeometry()
        }
    }

    onAdbReadyChanged: {
        if (root.adbReady) root._probeDeviceSize()
        if (root.shown) root._start()
    }

    // ----- losing the phone for a moment -----
    // adbd restarts whenever the phone is unlocked: every ADB connection drops for a few
    // seconds and takes any live scrcpy with it. scrcpy keeps an exit code of its own for a
    // lost connection (2); the same session is opened again once the phone answers. Anything
    // else is the window closing or a launch that failed outright, which would fail the same
    // way on every retry.
    readonly property int _maxResumeAttempts: 5

    function _maybeResume(id, code, deliberate): bool {
        if (id !== root.embedId || root._intentionalStops[id] || deliberate || code !== 2 || !root.shown)
            return false
        const now = Date.now()
        let attempt = root._resumeAttempts[id]
        if (!attempt || now - attempt.first > 120000) attempt = { "count": 0, "first": now }
        if (attempt.count >= root._maxResumeAttempts) {
            delete root._resumeAttempts[id]
            root.embedError = "The phone connection was lost, and could not be reopened."
            return false
        }
        attempt.count += 1
        root._resumeAttempts[id] = attempt
        resumeTimer.restart()
        return true
    }

    Timer {
        id: resumeTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!root.shown) { root.embedLaunching = false; return }
            root._pollDevices()
            root.embedLaunching = false
            root._start()
        }
    }

    // ===== the window =====
    // scrcpy's window, once it exists. The loop reads every title, so the binding re-runs
    // when one changes and not only when the list does.
    readonly property Toplevel toplevel: {
        const list = ToplevelManager.toplevels?.values ?? []
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].title === root.windowTitle)
                return list[i]
        }
        return null
    }

    // The window waits off the side of every monitor when nothing shows it. Far past any real
    // monitor: a special workspace was the obvious place, but Hyprland pulls one into view the
    // moment a window is assigned to it.
    readonly property int parkCoordinate: 99000

    onTouchRectChanged: {
        root._schedulePlacement()
        // Every change pushes the launch back, so it lands on the size the frame settles at
        // and not on one it passes through.
        if (root.shown && !root.embedRunning && !root.embedLaunching && root.adbReady && root.scrcpyAvailable)
            launchDebounce.restart()
    }
    onTouchWantedChanged: root._schedulePlacement()
    onCornerRadiusChanged: {
        root._placedAttached = false
        root._schedulePlacement()
    }
    onToplevelChanged: {
        root._log("window " + (root.toplevel ? "appeared" : "gone"))
        if (root.toplevel) {
            // A new scrcpy window opens wherever Hyprland likes (the window rules would send it
            // off screen, but they are in the user's own config, which an update does not touch).
            // Until it is placed under the picture it is put out of sight.
            root._hideStray()
            root._schedulePlacement()
            if (!root.shown) strayCheck.restart()
        } else {
            root.attached = false
            root.captureReady = false
            root._placedAttached = false
            root._pinnedByUs = false
            strayCheck.stop()
        }
    }

    // A config reload hands the manager, and every scrcpy under it, to the new engine, but
    // nothing here remembers having asked for one. The embedded window is invisible by design,
    // so left behind it would keep the phone encoding video for nobody.
    Timer {
        id: strayCheck
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.shown || root.embedRunning || root.embedLaunching || !root.toplevel) return
            root._send({ "cmd": "stop", "id": root.embedId })
            root.toplevel.close()
        }
    }

    // ----- placement -----
    // Geometry arrives as a stream while the panel slides; Hyprland only needs the value it
    // comes to rest on.
    Timer {
        id: placementDebounce
        interval: 60
        repeat: false
        onTriggered: root._applyPlacement()
    }

    function _schedulePlacement(): void {
        placementDebounce.restart()
    }

    // What was last sent, so an unchanged rectangle never becomes an IPC call.
    property rect _placedRect: Qt.rect(0, 0, 0, 0)
    property bool _placedAttached: false

    function _applyPlacement(): void {
        if (!root.toplevel)
            return

        if (!root.touchWanted || !root.shown) {
            root._park()
            return
        }

        const r = root.touchRect
        const rw = Math.round(r.width)
        const rh = Math.round(r.height)
        const rx = Math.round(r.x)
        const ry = Math.round(r.y)
        if (rw < 16 || rh < 16)
            return

        if (root._placedAttached
            && root._placedRect.x === rx && root._placedRect.y === ry
            && root._placedRect.width === rw && root._placedRect.height === rh)
            return

        // What is asked for, in the panel window's own coordinates. Where the panel stands on
        // the desktop is read from Hyprland first (a bar's exclusive zone moves a layer surface
        // without anything in QML saying so), then the window is sent there.
        root._wantRect = Qt.rect(rx, ry, rw, rh)
        root._layerMisses = 0
        root._layerLookOnly = false
        root._askLayers()
    }

    property rect _wantRect: Qt.rect(0, 0, 0, 0)
    property int _layerMisses: 0
    property bool _layersAgain: false
    // The panel's layer surface as Hyprland reports it: { x, y, mon }.
    property var _layer: null
    // How far `movewindowpixel exact` lands from where it was told to (a monitor's own
    // offset, on some versions). Learned from the first answer, applied to the resend.
    property point _corr: Qt.point(0, 0)
    // Where the window should end up on the desktop, to check against what Hyprland says.
    property point _expectAt: Qt.point(0, 0)
    property point _sentAt: Qt.point(0, 0)
    // The window is pinned by this shell (only ever the shell, so a toggle is safe).
    property bool _pinnedByUs: false

    function _askLayers(): void {
        if (layersProc.running) {
            root._layersAgain = true
            return
        }
        layersProc.running = true
    }

    Process {
        id: layersProc
        command: ["hyprctl", "-j", "layers"]
        stdout: StdioCollector {
            onStreamFinished: root._onLayers(this.text)
        }
        onExited: {
            if (root._layersAgain) {
                root._layersAgain = false
                layersProc.running = true
            }
        }
    }

    Timer {
        id: layersRetry
        interval: 150
        repeat: false
        onTriggered: root._askLayers()
    }

    function _onLayers(text: string): void {
        const lookOnly = root._layerLookOnly
        root._layerLookOnly = false
        if (!root.toplevel || !root.shown || !root.touchWanted)
            return
        let found = null
        try {
            const data = JSON.parse(text)
            for (const mon in data) {
                const levels = data[mon].levels ?? {}
                for (const lv in levels) {
                    for (const l of levels[lv]) {
                        if (l.namespace === root.layerNamespace)
                            found = { "x": l.x, "y": l.y, "mon": mon }
                    }
                }
            }
        } catch (e) {
            found = null
        }
        // Only a look to see whether the panel's layer has moved (see _recheck): if hyprctl did
        // not answer, or the panel is where it was, there is nothing to do and nothing to show.
        if (lookOnly) {
            if (!found || (root._layer && found.x === root._layer.x && found.y === root._layer.y && found.mon === root._layer.mon))
                return
            root._log("recheck: the panel's layer moved to " + found.x + "," + found.y + ", placing the window again")
            root._layer = found
            root._placeAt()
            return
        }
        // The panel is not mapped yet, or hyprctl did not answer: look again a few times.
        if (!found) {
            root._layerMisses += 1
            if (root._layerMisses < 10) {
                layersRetry.restart()
            } else {
                root.placementOk = false
                root.placementError = "Hyprland does not list the phone panel, so its window cannot be put under it."
            }
            return
        }
        root._layer = found
        root._placeAt()
    }

    function _monitorWorkspaceId(name: string): int {
        const list = Hyprland.monitors?.values ?? []
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].name === name)
                return list[i].activeWorkspace ? list[i].activeWorkspace.id : -1
        }
        return -1
    }

    // Sends the window to the rectangle in `_wantRect`, with the panel's position in `_layer`.
    // Sizing lands before moving: `exact` resizing keeps the window centred on where it was.
    function _placeAt(): void {
        if (!root.toplevel || !root._layer)
            return
        const w = root._wantRect
        const ex = root._layer.x + w.x
        const ey = root._layer.y + w.y
        const sx = Math.round(ex - root._corr.x)
        const sy = Math.round(ey - root._corr.y)
        const ws = root._monitorWorkspaceId(root._layer.mon)
        root._log("config: " + (root.usingLua ? "Lua" : "classic hyprland.conf") + ", workspace " + ws)
        const radius = Math.max(0, root.cornerRadius)
        const sel = "title:^" + root.windowTitle + "$"

        if (root.usingLua) {
            // Hyprland's IPC takes one Lua expression, so the whole placement travels as one
            // call and not seven round trips. Each step that a Hyprland might word differently
            // is in a pcall, so it can be skipped without losing the rest.
            let ops = root._luaFindWindow()
            if (ws >= 0)
                ops += root._luaWorkspace(ws)
            ops += `if not w.floating then pcall(function() hl.dispatch(hl.dsp.window.float({window=w,action="enable"})) end) end `
                + `pcall(function() hl.dispatch(hl.dsp.window.alter_zorder({window=w,mode="top"})) end) `
                + `hl.dispatch(hl.dsp.window.resize({window=w,x=${w.width},y=${w.height},exact=true})) `
                + `hl.dispatch(hl.dsp.window.move({window=w,x=${sx},y=${sy},exact=true})) `
                + `if not w.pinned then hl.dispatch(hl.dsp.window.pin({window=w})) end `
                + `hl.dispatch(hl.dsp.window.set_prop({window=w,rounding=${radius}})) `
                + root._luaPlainProps()
            Hyprland.dispatch(root._luaWrap(ops))
        } else {
            // The classic dispatchers, for a plain hyprland.conf.
            Hyprland.dispatch("setfloating " + sel)
            if (ws >= 0)
                Hyprland.dispatch("movetoworkspacesilent " + ws + "," + sel)
            Hyprland.dispatch("resizewindowpixel exact " + w.width + " " + w.height + "," + sel)
            Hyprland.dispatch("movewindowpixel exact " + sx + " " + sy + "," + sel)
            if (!root._pinnedByUs) {
                Hyprland.dispatch("pin " + sel)
                root._pinnedByUs = true
            }
            Hyprland.dispatch("alterzorder top," + sel)
            // `lock`: a window rule that is evaluated again (scrcpy changes its title after it
            // opens) otherwise puts the compositor's own rounding back over this one.
            Hyprland.dispatch("setprop " + sel + " rounding " + radius + " lock")
            // The window sits under the panel: its own border, shadow and blur are drawn outside
            // its square, where the panel's rounded corners do not cover them. Each name is sent
            // in both spellings Hyprland has used; a name it does not know is only an error reply.
            for (const prop of ["noborder 1", "bordersize 0", "no_border 1", "border_size 0",
                                "noshadow 1", "no_shadow 1", "noblur 1", "no_blur 1",
                                "noanim 1", "no_anim 1"])
                Hyprland.dispatch("setprop " + sel + " " + prop)
        }

        root._log("placing at " + ex + "," + ey + " size " + w.width + "x" + w.height
                  + " (panel layer " + root._layer.x + "," + root._layer.y + " on " + root._layer.mon + ")")
        root._expectAt = Qt.point(ex, ey)
        root._sentAt = Qt.point(sx, sy)
        root._placedRect = w
        root._placedAttached = true
        root.attached = true
        // The picture can be shown at once, but the panel only opens its click-through hole once
        // Hyprland has been seen to put the window there (see _readPlacement).
        root.placementOk = false
        root._verifyTries = 0
        verifyTimer.restart()
    }

    // ----- is it really there? -----
    // A hole over a window that is not there lets every click fall through to whatever is behind
    // the panel, which is worse than a phone that does not react. So the panel's hole opens only
    // when Hyprland reports the window floating and the size that was asked for.
    property bool placementOk: false
    // The picture may be captured: Hyprland has been seen to have the window in place at least
    // once since it appeared, and the panel has not gone away since. Unlike `placementOk` it does
    // NOT drop while the window is being checked or put right again. `placementOk` governs the
    // click-through hole (a hole over a window that is not there is the worse mistake); the
    // capture was tied to it too, so every re-check tore the picture down and the screen went
    // back to "Waiting for the picture..." (a workspace change, the Quick Panel opening).
    property bool captureReady: false
    // The panel is sliding away and the picture on it must not go blank while it does. Parking
    // the window (which has to happen at once: it is a real window, and the slide would leave
    // it standing in the open) drops `attached` and `captureReady`, and the capture used to go
    // with them, so the screen turned empty the instant Close was pressed and an empty phone
    // slid off. While this is up the capture is kept on the window as it is, parked or not, and
    // the last frame stays on the glass. Set only if there was a picture to keep, cleared when
    // the slide is over (or the panel comes back).
    property bool captureHold: false

    // Longer than the panel's slide out (PhoneMirror.qml, hideAnim: 220 ms).
    Timer {
        id: captureHoldTimer
        interval: 320
        repeat: false
        onTriggered: root.captureHold = false
    }
    // What is wrong, for the screen to say; "" when nothing is.
    property string placementError: ""
    property int _verifyTries: 0
    property bool _resent: false

    Timer {
        id: verifyTimer
        interval: 300
        repeat: false
        onTriggered: {
            Hyprland.refreshToplevels()
            readTimer.restart()
        }
    }

    Timer {
        id: readTimer
        interval: 250
        repeat: false
        onTriggered: root._readPlacement()
    }

    function _readPlacement(): void {
        if (!root.attached || !root.shown)
            return
        const list = Hyprland.toplevels?.values ?? []
        let o = null
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].title === root.windowTitle) {
                o = list[i].lastIpcObject
                break
            }
        }
        // Not read yet: ask again a few times. If Hyprland never says, the hole stays shut: a
        // hole over a window that is not there is the worse mistake.
        if (!o || o.floating === undefined || !o.size || !o.at) {
            root._verifyTries += 1
            if (root._verifyTries < 4) {
                verifyTimer.restart()
            } else {
                root.placementOk = false
                root.placementError = "Hyprland did not report where the phone window is."
            }
            return
        }
        const want = root._placedRect
        const sizeOk = Math.abs(o.size[0] - want.width) <= 3 && Math.abs(o.size[1] - want.height) <= 3
        const atOk = Math.abs(o.at[0] - root._expectAt.x) <= 3 && Math.abs(o.at[1] - root._expectAt.y) <= 3
        root._log("window is at " + o.at + " size " + o.size + " floating " + o.floating
                  + " (wanted " + root._expectAt.x + "," + root._expectAt.y + ")")
        if (o.floating === true && sizeOk && atOk) {
            root.placementError = ""
            root._resent = false
            root.placementOk = true
            root.captureReady = true
            return
        }
        if (!root._resent) {
            // One more try, once: `_placeAt` starts the count over, so without this a window that
            // never obeys would be asked forever. If it floats and has the size but lands
            // somewhere else by a steady amount, the second try corrects for that amount.
            root._resent = true
            if (o.floating === true && sizeOk) {
                root._corr = Qt.point(o.at[0] - root._sentAt.x + root._corr.x,
                                      o.at[1] - root._sentAt.y + root._corr.y)
            }
            root._placeAt()
            return
        }
        root.placementOk = false
        root.placementError = o.floating !== true
            ? "The phone window is not floating, so it cannot be moved. Add the sekai-phone window rules to your Hyprland config (docs/PHONE-MIRROR.md), then press Try again."
            : (sizeOk ? "The phone window landed in the wrong place."
                      : "The phone window would not take its size.")
    }

    /** Puts the window back on the rectangle the frame is asking for, after something outside
     *  the shell has moved or resized it. */
    function reassertGeometry(): void {
        root._placedAttached = false
        root._schedulePlacement()
    }

    // Floats the window and sends it off screen, whatever this shell thinks it knows about it.
    function _hideStray(): void {
        if (!root.toplevel || root._placedAttached)
            return
        const sel = "title:^" + root.windowTitle + "$"
        if (root.usingLua) {
            const ops = root._luaFindWindow()
                + `if not w.floating then pcall(function() hl.dispatch(hl.dsp.window.float({window=w,action="enable"})) end) end `
                + `hl.dispatch(hl.dsp.window.move({window=w,x=${root.parkCoordinate},y=${root.parkCoordinate},exact=true})) `
            Hyprland.dispatch(root._luaWrap(ops))
        } else {
            Hyprland.dispatch("setfloating " + sel)
            Hyprland.dispatch("movewindowpixel exact " + root.parkCoordinate + " " + root.parkCoordinate + "," + sel)
        }
    }

    function _park(): void {
        // The panel is away (not just sliding or being resized): the capture goes with it, and
        // starts again from a verified placement when the panel comes back.
        if (!root.shown)
            root.captureReady = false
        if (!root._placedAttached)
            return
        root._placedAttached = false
        root._placedRect = Qt.rect(0, 0, 0, 0)
        root.attached = false
        root.placementOk = false
        root.placementError = ""
        root._resent = false
        if (!root.toplevel)
            return
        const sel = "title:^" + root.windowTitle + "$"
        // Unpinned first: a pinned window belongs to every workspace at once, and letting go
        // of it is also what stops it following the user around while it waits out of sight.
        if (root.usingLua) {
            const ops = root._luaFindWindow()
                + `if w.pinned then hl.dispatch(hl.dsp.window.pin({window=w})) end `
                + `hl.dispatch(hl.dsp.window.move({window=w,x=${root.parkCoordinate},y=${root.parkCoordinate},exact=true})) `
            Hyprland.dispatch(root._luaWrap(ops))
        } else {
            if (root._pinnedByUs) {
                Hyprland.dispatch("pin " + sel)
                root._pinnedByUs = false
            }
            Hyprland.dispatch("movewindowpixel exact " + root.parkCoordinate + " " + root.parkCoordinate + "," + sel)
        }
    }

    // A config reload takes this singleton down while the window is still attached, and the
    // panel that was covering it goes with it. Parking it first is cheap.
    Component.onDestruction: root._park()

    // Hyprland's IPC takes one Lua expression, so everything a placement does travels as a
    // single call and not four round trips.
    function _luaWrap(ops: string): string {
        return `(function() ${ops} return hl.dsp.no_op() end)()`
    }

    function _luaFindWindow(): string {
        return `local t="${root.windowTitle}" local w `
            + `for _,v in ipairs(hl.get_windows()) do if v.title==t then w=v end end `
            + `if not w then return hl.dsp.no_op() end `
    }

    /** No border, shadow, blur or animation on the window under the panel (see _placeAt). Each
     *  in a pcall: a prop name this Hyprland does not have must not stop the placement. */
    function _luaPlainProps(): string {
        const props = ["border_size=0", "no_border=true", "no_shadow=true", "no_blur=true", "no_anim=true"]
        return props.map(p => `pcall(function() hl.dispatch(hl.dsp.window.set_prop({window=w,${p}})) end) `).join("")
    }

    /** Moves the window onto the panel's monitor's workspace, first: a pinned window belongs
     *  to one monitor, so it has to be there before it is pinned. `ws` is that workspace's id. */
    function _luaWorkspace(ws: int): string {
        return `pcall(function() local ws for _,x in ipairs(hl.get_workspaces()) do if x.id==${ws} then ws=x end end `
            + `if ws and (not w.workspace or w.workspace.id~=ws.id) then `
            + `hl.dispatch(hl.dsp.window.move({window=w,workspace=ws,follow=false})) end end) `
    }

    // ===== keeping it put =====
    // The window is pinned, so a workspace change takes it along; nothing has to be redone for
    // that. What Hyprland can still do is leave it somewhere else when the monitor's layout shifts
    // under it (a bar's reserved area, a layer opening). So these events only start a look, and
    // the window is put again only if the look shows it has moved. They used to throw the
    // placement away at once: the click-through hole closed, the capture was dropped, and the
    // screen said "Waiting for the picture..." on every workspace change and every layer that
    // opened, the Quick Panel's phone included.
    Connections {
        target: Hyprland
        enabled: root.attached
        ignoreUnknownSignals: true
        function onRawEvent(event): void {
            switch (event.name) {
            case "monitoradded":
            case "monitorremoved":
                // The desktop's shape changed: where the panel stands is worked out again.
                root._placedAttached = false
                root._schedulePlacement()
                break
            case "workspace":
            case "focusedmon":
            case "openlayer":
            case "closelayer":
                root._recheckSoon()
                break
            }
        }
    }

    Timer {
        id: recheckTimer
        interval: 400
        repeat: false
        onTriggered: root._recheck()
    }

    Timer {
        id: recheckRead
        interval: 250
        repeat: false
        onTriggered: root._readStill()
    }

    // True for the one answer of `hyprctl layers` that only checks where the panel is.
    property bool _layerLookOnly: false

    function _recheckSoon(): void {
        // Not placed yet, or a placement is still being checked: that already ends in a look at
        // where the window is.
        if (!root._placedAttached || !root.placementOk)
            return
        recheckTimer.restart()
    }

    function _recheck(): void {
        if (!root.toplevel || !root.shown || !root.touchWanted || !root._placedAttached || !root.placementOk)
            return
        Hyprland.refreshToplevels()
        recheckRead.restart()
        if (!layersProc.running && !layersRetry.running && !placementDebounce.running) {
            root._layerLookOnly = true
            layersProc.running = true
        }
    }

    // Where Hyprland says the window is now, against where it was put. Anything it cannot say
    // is left alone: the picture stays, and nothing is redone on a guess.
    function _readStill(): void {
        if (!root.attached || !root.shown || !root.placementOk || !root.toplevel)
            return
        const list = Hyprland.toplevels?.values ?? []
        let o = null
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].title === root.windowTitle) {
                o = list[i].lastIpcObject
                break
            }
        }
        if (!o || o.floating === undefined || !o.size || !o.at)
            return
        const want = root._placedRect
        const sizeOk = Math.abs(o.size[0] - want.width) <= 3 && Math.abs(o.size[1] - want.height) <= 3
        const atOk = Math.abs(o.at[0] - root._expectAt.x) <= 3 && Math.abs(o.at[1] - root._expectAt.y) <= 3
        const pinnedOk = o.pinned !== false
        if (o.floating === true && sizeOk && atOk && pinnedOk)
            return
        root._log("recheck: the window is at " + o.at + " size " + o.size + " floating " + o.floating
                  + " pinned " + o.pinned + ", placing it again")
        if (o.pinned === false)
            root._pinnedByUs = false
        root._placedAttached = false
        root._schedulePlacement()
    }

    // ===== the phone's keys =====
    // One-shot and rare, so the ~120 ms `adb shell input` costs is invisible next to keeping a
    // shell open on the phone for the whole session.
    function sendKey(name: string): void {
        const code = PMir.keycodes[name]
        if (!code || !root.adbReady)
            return
        Quickshell.execDetached(["adb"].concat(root.targetArgs()).concat(["shell", "input", "keyevent", code]))
    }

    function openNotifications(): void {
        if (!root.adbReady)
            return
        Quickshell.execDetached(["adb"].concat(root.targetArgs()).concat(["shell", "cmd", "statusbar", "expand-notifications"]))
    }

    // ===== a step that stalls =====
    // Opening the phone is four steps in a row (scrcpy starts, its window appears, the window is
    // put under the screen, the picture arrives) and each waits on something outside this shell
    // (adb, Hyprland, the compositor's capture). Any can be missed once: an event that came a
    // moment before something was ready, a window that was closed while it was being placed. So
    // while the panel is up this looks every second and a half and nudges whichever step has
    // not moved, and after a while of nothing starts the session over, twice at most, before
    // saying so on the screen.
    // Written by the panel: it is the one that sees the picture.
    property bool pictureOk: false
    property int _stuckTicks: 0
    property int _healRestarts: 0

    Timer {
        interval: 1500
        repeat: true
        running: root.shown && !root.stopped
        onTriggered: root._heal()
    }

    function _heal(): void {
        const ready = root.scrcpyAvailable && root.adbReady && !root.windowRunning
        if (!ready || root.embedError !== "" || root.placementError !== "" || root.embedLaunching) {
            root._stuckTicks = 0
            return
        }
        if (!root.embedRunning) {
            // Nothing was started, and nothing is about to be.
            root._stuckTicks = 0
            if (!launchDebounce.running && !restartTimer.running && !resumeTimer.running) {
                root._log("heal: nothing was started, starting")
                root._start()
            }
            return
        }
        if (root.pictureOk) {
            root._stuckTicks = 0
            root._healRestarts = 0
            return
        }
        root._stuckTicks += 1
        if (root.toplevel && !root.attached && root._stuckTicks % 2 === 0) {
            // The window is there and was never put in place: ask again.
            root._log("heal: window not placed, asking again")
            root._placedAttached = false
            root._schedulePlacement()
        }
        if (root._stuckTicks < 6)
            return
        root._stuckTicks = 0
        if (root._healRestarts < 2) {
            root._healRestarts += 1
            root._log("heal: no picture after ~9 s (window " + !!root.toplevel + ", attached " + root.attached + "), restarting")
            root.restart()
        } else {
            root.embedError = !root.toplevel
                ? "scrcpy is running but its window never appeared."
                : (!root.attached ? "The phone window could not be put under the screen."
                                  : "The picture of the phone's window never arrived.")
        }
    }

    // ===== command line =====
    IpcHandler {
        target: "phonemirror"

        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function start(): void { root.start() }
        function stop(): void { root.stop() }
        function restart(): void { root.restart() }
        function detach(): void { root.openWindow() }
        function connect(address: string): void { root.connectAddress(address) }
        function disconnect(): void { root.forgetAddress() }
        function key(name: string): void { root.sendKey(name) }

        function status(): string {
            return root.shown
                ? (root.stopped ? "stopped" : (root.embedRunning ? "mirroring " + root.deviceName : root.deviceStatus))
                : "hidden"
        }
    }
}
