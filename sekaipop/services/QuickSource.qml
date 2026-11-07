import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.services
import "../modules/common/functions/QuickTiles.js" as QT
import qs.modules.common

// The system side of the Quick Panel — what MediaSource.qml is to the
// media pill and TraySource.qml is to the tray. QuickPanelFace.qml stays
// pure UI; QuickPanel.qml feeds it what's in here and turns its signals
// into calls to the toggle functions below.
//
// Everything goes through small command-line tools, so nothing here can
// stop the shell from loading if one is missing — a missing tool just
// leaves its tile showing OFF:
//
//   Wi-Fi / Ethernet   nmcli            (NetworkManager)
//   Bluetooth          bluetoothctl     (BlueZ)
//   Speaker / Mic      wpctl + pactl    (PipeWire; pactl notices mute
//                                        changes from a keyboard key, and
//                                        does the device list below)
//   Extra buttons      easyeffects, warp-cli, wtype (the on-screen keyboard), grim + slurp,
//                      hyprpicker, songrec + ffmpeg, power-profiles-daemon,
//                      plus hyprctl for Anti-Flashbang — see the "extra
//                      buttons" section below. Each is optional.
//   Keep Awake         systemd-inhibit  (holds an idle inhibitor — idle
//                                        timers only, never a sleep lock —
//                                        for as long as it's ON; remembered
//                                        across shell reloads — see the
//                                        Keep Awake section below)
//
// Nothing polls while the panel is closed: `active` (set from shell.qml
// to "the panel is open") turns the refresh timer and the audio listener
// on, and the panel refreshes once the moment it opens.
//
// Right-clicking the Network/Bluetooth tile pulls a heavier one-off list
// (nearby Wi-Fi networks / paired Bluetooth devices) for NetworkDialog.qml
// / BluetoothDialog.qml — see the "Wi-Fi network list / Bluetooth device
// list" section below. That's on top of nmcli/bluetoothctl above, not an
// extra dependency. Right-clicking a volume slider does the same with
// `pactl` for VolumeMixerDialog.qml, listing sinks/sources and the
// apps using them instead.
Scope {
    id: root

    property bool active: false

    // ===== what the panel shows =====
    readonly property string userName: Quickshell.env("USER") || "user"
    property string hostName: ""

    property bool wifiOn: false          // the Wi-Fi radio
    property string wifiName: ""         // network it's joined, "" if none
    property string ethernetName: ""     // wired connection, "" if none

    // The first tile shows Ethernet only while there's a wired connection
    // and Wi-Fi isn't connected; otherwise it's the Wi-Fi tile.
    readonly property string networkKind: ethernetName !== "" && wifiName === "" ? "ethernet" : "wifi"
    readonly property bool networkOn: networkKind === "ethernet" ? true : wifiOn
    readonly property string networkDetail: {
        if (networkKind === "ethernet")
            return ethernetName
        if (!wifiOn)
            return "OFF"
        return wifiName !== "" ? wifiName : "Not connected"
    }

    property bool bluetoothOn: false
    property string bluetoothDevice: ""  // first connected device
    readonly property string bluetoothDetail: bluetoothOn ? (bluetoothDevice !== "" ? bluetoothDevice : "ON") : "OFF"

    // ON means "not muted", matching how the tiles read.
    property bool speakerOn: true
    property bool microphoneOn: true

    // 0-100, the sliders' own state. Set optimistically the instant you
    // drag (see setSpeakerVolume/setMicrophoneVolume below) and corrected
    // by the next poll if the command didn't take — same shape as every
    // toggle here.
    property real speakerVolume: 0
    property real microphoneVolume: 0

    // Which monitor Brightness controls — shell.qml binds this to
    // panel.targetScreen, so it always tracks whichever screen the
    // phone itself is currently open on.
    property var targetScreen: null

    // 0-100, the slider's own state — same optimistic-then-corrected
    // shape as speakerVolume/microphoneVolume above. Brightness lives
    // in raw device units internally (see brightnessRawMax), not a
    // clean 0-100 wpctl-style percentage, so this is derived from a
    // current/max pair on every poll instead.
    property real brightness: 100
    property int brightnessRawMax: 100

    // 0-100, the screen's gamma through hyprsunset (100 = unchanged) — the
    // short bar next to Brightness. Same optimistic-then-corrected shape;
    // read back on every poll so the OSD's gamma keys keep it in step.
    property real gamma: 100
    readonly property real gammaMin: 10   // below this the screen is unusably dark

    // Which backend the target screen resolved to. Two tools cover this,
    // same "missing tool just leaves it be" shape as everything else:
    //   Laptop panel      brightnessctl    (backlight sysfs class)
    //   External monitor  ddcutil          (DDC/CI over I2C, once the
    //                                       monitor's bus is detected)
    property bool brightnessDdc: false
    property string brightnessBus: ""

    // ddcutil detect is slow (a few hundred ms per bus at least), so
    // it's run once — the first time the panel opens — rather than on
    // every 3s poll. Each entry is {name: <DRM connector, e.g. "DP-1">,
    // busNum: <I2C bus number>}.
    property var ddcMonitors: []
    property bool ddcDetected: false

    readonly property bool keepAwakeOn: inhibitor.running

    // The Notifications tile: OFF is do-not-disturb. shell.qml hands it to
    // NotificationSource, which then stops notifications taking over the
    // media pill in the bar (they still land in the panel's list). Kept in
    // settings.json ("notify.on") so a silent desktop stays silent across
    // shell restarts and logins, instead of announcing again after each one.
    readonly property bool notificationsOn: SettingsService.flag("notify.on")
    property bool editing: false

    // Night Light (hyprsunset's colour temperature) is read back from
    // Hyprland on every poll below, so it follows changes made from
    // elsewhere. Game Mode is not: it is owned by GameModeService (it also
    // takes the dock and the desktop widgets away, so a poll must not be able
    // to flip it), and this only shows it.
    property bool nightLightOn: false
    readonly property bool gameModeOn: GameModeService.enabled
    // The extra buttons (Dark Mode .. Anti-Flashbang), see the section
    // below. The first four are read back on every poll.
    property bool easyEffectsOn: false
    property bool warpOn: false
    property bool warpConnecting: false
    // Is warp-cli on this system at all? Looked up once with `command -v`
    // (warpProbe below), so a missing binary is a notification and a
    // "Not installed" tile instead of a "Process failed to start" in the log
    // every poll. Optimistic until the probe has answered.
    property bool warpInstalled: true
    property bool warpProbed: false
    // On-Screen Keyboard: one shared state, see KeyboardService.qml.
    readonly property bool keyboardOn: KeyboardService.running
    property bool antiFlashbangOn: false
    // 0 = off, 1 = weak, 2 = strong (end4's two shaders)
    property int antiFlashbangLevel: 0
    // Kelvin. hyprsunset reports 6000 when it isn't tinting, so anything
    // else counts as ON. This is how warm the screen goes while Night Light
    // is ON (the Night Light card, right-click on the tile, sets it) and is
    // remembered across restarts (scripts/state/nightlight-state.sh).
    property int nightLightTemperature: 4500
    readonly property int nightLightMinKelvin: 2500
    readonly property int nightLightMaxKelvin: 6000

    // Automatic: switch Night Light on at `nightLightAutoFrom` (hour of
    // day) and off again at `nightLightAutoTo`. Only the moment of
    // crossing either time acts, so a click on the tile in between sticks
    // until the next crossing instead of being undone a minute later.
    property bool nightLightAuto: false
    property int nightLightAutoFrom: 20
    property int nightLightAutoTo: 6

    // ===== refreshing =====
    property int actionGen: 0
    property int pollGen: 0

    onActiveChanged: {
        if (active) {
            refresh()
            if (!ddcDetected)
                ddcDetectProc.running = true
        } else {
            // Forget the last sample so reopening the panel doesn't spread
            // one giant delta over however long it was closed.
            netLastRx = -1
            netLastTx = -1
            downloadBps = 0
            uploadBps = 0
            // Closing the panel ends edit mode, so it never reopens half-edited.
            editing = false
        }
    }

    // Re-resolve which backend applies (and re-poll it) whenever the
    // panel moves to a different monitor. Before the first DDC detect
    // finishes there's nothing to resolve against yet — onExited below
    // does this same pair of calls once detection lands.
    onTargetScreenChanged: {
        if (ddcDetected) {
            resolveBrightnessBackend()
            refreshBrightness()
        }
    }

    function refresh() {
        if (poll.running)
            return
        pollGen = actionGen
        poll.running = true
        KeyboardService.refresh()
        refreshBrightness()
        refreshWarp()
    }

    // A moment after something changed, look again (debounced).
    function refreshSoon() {
        settle.restart()
    }

    Timer {
        id: settle
        interval: 350
        onTriggered: root.refresh()
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    // One shell script gathers everything as key=value lines. Each tool
    // gets 2 seconds at most, and a missing one just prints nothing.
    // `nmcli -e no` keeps colons in network names unescaped. `--rescan no`
    // on the SSID query is load-bearing: without it, `nmcli device wifi
    // list` forces a fresh scan every single poll (every 3s while the
    // panel's open), and mid-scan the currently-connected AP briefly drops
    // out of the list — which is what was showing up as the tile blinking
    // to "Not connected" and back. Passing `--rescan no` just reads
    // NetworkManager's last-known scan instead of forcing a new one, so
    // the connected SSID stays put between polls.
    readonly property string script: [
        "w=$(timeout 2 nmcli -t radio wifi 2>/dev/null)",
        "s=$(timeout 2 nmcli -t -e no -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null | sed -n 's/^yes://p' | head -n1)",
        "e=$(timeout 2 nmcli -t -e no -f TYPE,STATE,CONNECTION dev 2>/dev/null | sed -n 's/^ethernet:connected://p' | head -n1)",
        "b=$(timeout 2 bluetoothctl show 2>/dev/null | sed -n 's/^[[:space:]]*Powered: //p' | head -n1)",
        "d=$(timeout 2 bluetoothctl devices Connected 2>/dev/null | sed -n 's/^Device [^ ]* //p' | head -n1)",
        "sm=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -c MUTED)",
        "mm=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -c MUTED)",
        "sv=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | sed -n 's/^Volume: \\([0-9.]*\\).*/\\1/p')",
        "mv=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | sed -n 's/^Volume: \\([0-9.]*\\).*/\\1/p')",
        "nl=$(timeout 2 hyprctl hyprsunset temperature 2>/dev/null | head -n1)",
        "gg=$(timeout 2 hyprctl hyprsunset gamma 2>/dev/null | head -n1)",
        "gm=$( { timeout 2 hyprctl getoption animations:enabled; timeout 2 hyprctl getoption animations.enabled; } 2>/dev/null | sed -nE 's/^[[:space:]]*(int|bool|float): *//p' | head -n1 | cut -d' ' -f1)",
        "gmm=$([ -f \"${XDG_RUNTIME_DIR:-/tmp}/sekaipop-gamemode\" ] && echo 1 || echo 0)",
        "ee=$(pgrep -x easyeffects >/dev/null 2>&1 && echo 1 || echo 0)",
        "af=$( { timeout 2 hyprctl getoption decoration.screen_shader; timeout 2 hyprctl getoption decoration:screen_shader; } 2>/dev/null | sed -n 's/^[[:space:]]*str: //p' | head -n1)",
        "printf 'wifi=%s\\nssid=%s\\neth=%s\\nbt=%s\\nbtdev=%s\\nsinkmuted=%s\\nsrcmuted=%s\\nsinkvol=%s\\nsrcvol=%s\\nnl=%s\\ngg=%s\\ngm=%s\\ngmm=%s\\nee=%s\\naf=%s\\n' \"$w\" \"$s\" \"$e\" \"$b\" \"$d\" \"$sm\" \"$mm\" \"$sv\" \"$mv\" \"$nl\" \"$gg\" \"$gm\" \"$gmm\" \"$ee\" \"$af\""
    ].join("\n")

    Process {
        id: poll
        command: ["sh", "-c", root.script]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    function apply(text) {
        if (pollGen !== actionGen) {
            // A click happened while this was running; ask again.
            refreshSoon()
            return
        }
        const kv = {}
        for (const line of text.split("\n")) {
            const i = line.indexOf("=")
            if (i > 0)
                kv[line.slice(0, i)] = line.slice(i + 1)
        }
        wifiOn = kv.wifi === "enabled"
        wifiName = kv.ssid || ""
        ethernetName = kv.eth || ""
        bluetoothOn = (kv.bt || "").trim() === "yes"
        bluetoothDevice = kv.btdev || ""
        speakerOn = kv.sinkmuted === "0"
        microphoneOn = kv.srcmuted === "0"

        // hyprsunset prints its current temperature; anything that isn't
        // a number (not running, hyprctl missing) reads as OFF.
        const nl = parseInt(kv.nl, 10)
        nightLightOn = !isNaN(nl) && nl !== 6000
        // hyprsunset's gamma, as a percent. No answer (not running yet)
        // leaves the last-known value alone.
        const gg = parseFloat(kv.gg)
        if (!isNaN(gg) && gg > 0)
            gamma = Math.max(gammaMin, Math.min(100, Math.round(gg)))
        // (Game Mode is not read here any more: GameModeService owns it. The
        // `gm` and `gmm` fields of the poll are still printed and not used.)

        // The extra buttons: each reads "not there" as OFF.
        easyEffectsOn = (kv.ee || "").trim() === "1"
        if (!antiFlashbangAction.running) {
            const af = kv.af || ""
            antiFlashbangLevel = af.indexOf("anti-flashbang-weak.glsl") >= 0 ? 1
                : (af.indexOf("anti-flashbang.glsl") >= 0 ? 2 : 0)
            antiFlashbangOn = antiFlashbangLevel > 0
        }

        // wpctl reports volume as a 0-and-up fraction ("0.45", or over 1
        // if the sink/source is boosted past 100%) — missing wpctl, or a
        // line that didn't parse, leaves the last-known value alone
        // rather than snapping to 0.
        const sv = parseFloat(kv.sinkvol)
        if (!isNaN(sv))
            speakerVolume = Math.round(sv * 100)
        const mv = parseFloat(kv.srcvol)
        if (!isNaN(mv))
            microphoneVolume = Math.round(mv * 100)
    }

    // ===== internet speed =====
    property real downloadBps: 0
    property real uploadBps: 0
    property real netLastRx: -1
    property real netLastTx: -1
    property double netLastMs: 0

    Timer {
        interval: 1000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            netDev.reload()
            root.applyNet(netDev.text())
        }
    }

    FileView {
        id: netDev
        path: "/proc/net/dev"
    }

    function applyNet(text) {
        let rx = 0
        let tx = 0
        for (const line of text.split("\n")) {
            const i = line.indexOf(":")
            if (i < 0)
                continue
            const name = line.slice(0, i).trim()
            if (/^(lo$|veth|docker|br-|virbr|tun|tap|wg|tailscale|zt)/.test(name))
                continue
            // 8 receive columns, then transmit — bytes are the first of each
            const f = line.slice(i + 1).trim().split(/\s+/)
            rx += Number(f[0]) || 0
            tx += Number(f[8]) || 0
        }

        const now = Date.now()
        if (netLastRx >= 0 && now > netLastMs) {
            const dt = (now - netLastMs) / 1000
            // max(0, ...): an interface disappearing drops the sum
            downloadBps = Math.max(0, rx - netLastRx) / dt
            uploadBps = Math.max(0, tx - netLastTx) / dt
        }
        netLastRx = rx
        netLastTx = tx
        netLastMs = now
    }

    // ===== brightness =====

    Process {
        id: ddcDetectProc
        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                if (!data.startsWith("Display "))
                    return
                const lines = data.split("\n").map(l => l.trim())
                const connLine = lines.find(l => l.startsWith("DRM connector:"))
                const busLine = lines.find(l => l.startsWith("I2C bus:"))
                if (!connLine || !busLine)
                    return
                root.ddcMonitors.push({
                    name: connLine.split("-").slice(1).join("-"),
                    busNum: busLine.split("/dev/i2c-")[1]
                })
            }
        }
        onExited: {
            root.ddcDetected = true
            root.resolveBrightnessBackend()
            root.refreshBrightness()
        }
    }

    // Picks brightnessctl or ddcutil for `targetScreen`, based on
    // whether that screen's name showed up as a DDC display above.
    function resolveBrightnessBackend() {
        if (!root.targetScreen)
            return
        const match = root.ddcMonitors.find(m => m.name === root.targetScreen.name)
        root.brightnessDdc = !!match
        root.brightnessBus = match ? match.busNum : ""
    }

    // Same "throw away a stale read" guard apply() above uses for the
    // network/audio poll (pollGen vs. actionGen) — brightness never had
    // its own copy, so a slow read already in flight (ddcutil especially:
    // a few hundred ms over I2C) could land *after* a drag's optimistic
    // setBrightness() and stomp it back to the pre-drag value, which then
    // only self-corrected on the next poll a moment later. A fast
    // drag-then-release made this easy to hit: plenty of time for a poll
    // that started just before the drag to still be running when it ends.
    property int brightnessPollGen: 0

    function refreshBrightness() {
        if (!root.ddcDetected || !root.targetScreen || brightnessPoll.running)
            return
        root.brightnessPollGen = root.actionGen
        // Both branches print "<current> <max>" so apply() below can
        // parse them the same way regardless of backend. ddcutil's own
        // `getvcp 10 --brief` already prints that shape at the tail of
        // "VCP 10 C <current> <max>"; brightnessctl needs two separate
        // calls (g = current, m = max) stitched together to match.
        brightnessPoll.command = root.brightnessDdc
            ? ["ddcutil", "-b", root.brightnessBus, "getvcp", "10", "--brief"]
            : ["sh", "-c", "echo \"$(brightnessctl g 2>/dev/null) $(brightnessctl m 2>/dev/null)\""]
        brightnessPoll.running = true
    }

    Process {
        id: brightnessPoll
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.brightnessPollGen !== root.actionGen) {
                    // A drag happened while this read was in flight, so
                    // it's already out of date — ask again once things
                    // settle instead of clobbering the newer value.
                    root.refreshSoon()
                    return
                }
                const parts = text.trim().split(/\s+/)
                const [current, max] = root.brightnessDdc ? [parts[3], parts[4]] : [parts[0], parts[1]]
                const c = parseFloat(current)
                const m = parseFloat(max)
                if (!isNaN(c) && !isNaN(m) && m > 0) {
                    root.brightnessRawMax = m
                    root.brightness = Math.round((c / m) * 100)
                }
            }
        }
    }

    // Gamma bar: same optimistic-set-then-debounce shape as brightness
    // below, through hyprsunset (started first if nothing's running it —
    // same trick as Night Light).
    function setGamma(percent) {
        actionGen++
        root.gamma = Math.max(root.gammaMin, Math.min(100, Math.round(percent)))
        settleGamma.restart()
    }

    Timer {
        id: settleGamma
        interval: 80
        onTriggered: {
            if (gammaAction.running)
                settleGamma.restart()
            else
                gammaAction.running = true
        }
    }

    Process {
        id: gammaAction
        command: ["sh", "-c",
            "pidof hyprsunset >/dev/null || { setsid hyprsunset >/dev/null 2>&1 & sleep 0.6; }; hyprctl hyprsunset gamma "
            + Math.round(root.gamma)]
        onExited: root.refreshSoon()
    }

    // Same optimistic-set-then-debounce shape as setSpeakerVolume/
    // setMicrophoneVolume below, just working in raw device units
    // (brightnessRawMax) instead of a clean 0-100 wpctl percentage.
    function setBrightness(percent) {
        actionGen++
        root.brightness = Math.max(0, Math.min(100, Math.round(percent)))
        settleBrightness.restart()
    }

    Timer {
        id: settleBrightness
        interval: 80
        onTriggered: {
            if (brightnessAction.running)
                settleBrightness.restart()
            else
                brightnessAction.running = true
        }
    }

    Process {
        id: brightnessAction
        command: {
            if (root.brightnessDdc) {
                const raw = Math.max(1, Math.round((root.brightness / 100) * root.brightnessRawMax))
                return ["ddcutil", "-b", root.brightnessBus, "setvcp", "10", String(raw)]
            }
            // Avoid setting the backlight to a literal 0% (that can
            // black the panel out on some drivers) — 1% is effectively
            // the same dimness without actually losing the display.
            const pct = Math.round(root.brightness)
            return ["brightnessctl", "--class", "backlight", "s", (pct <= 0 ? "1" : pct + "%"), "--quiet"]
        }
        onExited: root.refreshSoon()
    }

    // Tells us when the default speaker / mic is muted or unmuted from
    // somewhere else (a keyboard mute key, a mixer), so the tile can
    // follow — and pulse — right away. `on sink #` / `on source #`
    // deliberately skips sink-input / source-output, which chatter
    // whenever audio plays.
    Process {
        command: ["setpriv", "--pdeathsig", "TERM", "pactl", "subscribe"]
        running: root.active
        stdout: SplitParser {
            onRead: line => {
                if (/'change' on (sink|source) #/.test(line))
                    root.refreshSoon()
            }
        }
    }

    Process {
        command: ["uname", "-n"]   // `hostname` is not installed by default on Arch (inetutils)
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.hostName = text.trim()
        }
    }

    // ===== actions =====

    function toggleNetwork() {
        actionGen++
        wifiOn = !wifiOn
        wifiAction.running = true
    }

    function toggleBluetooth() {
        actionGen++
        bluetoothOn = !bluetoothOn
        bluetoothAction.running = true
    }

    function toggleSpeaker() {
        actionGen++
        speakerOn = !speakerOn
        speakerAction.running = true
    }

    function toggleMicrophone() {
        actionGen++
        microphoneOn = !microphoneOn
        microphoneAction.running = true
    }

    // Sliders call these on every pointer move while dragging, so the
    // percentage is applied to `speakerVolume`/`microphoneVolume` (and
    // shown) immediately, but the actual `wpctl` call is debounced —
    // otherwise a single drag gesture would spawn dozens of processes a
    // second. `settleVolume` restarting on every call means only the
    // last value in a burst actually reaches wpctl, ~80ms after the
    // pointer stops moving (or the click/tap releases).
    function setSpeakerVolume(percent) {
        actionGen++
        root.speakerVolume = Math.max(0, Math.min(100, Math.round(percent)))
        settleSpeakerVolume.restart()
    }

    function setMicrophoneVolume(percent) {
        actionGen++
        root.microphoneVolume = Math.max(0, Math.min(100, Math.round(percent)))
        settleMicrophoneVolume.restart()
    }

    Timer {
        id: settleSpeakerVolume
        interval: 80
        // A wpctl call from the previous tick is (very rarely) still
        // in flight — same guard refresh() uses for the poll process:
        // wait rather than overlap two of them.
        onTriggered: {
            if (speakerVolumeAction.running)
                settleSpeakerVolume.restart()
            else
                speakerVolumeAction.running = true
        }
    }

    Timer {
        id: settleMicrophoneVolume
        interval: 80
        onTriggered: {
            if (microphoneVolumeAction.running)
                settleMicrophoneVolume.restart()
            else
                microphoneVolumeAction.running = true
        }
    }

    Process {
        id: speakerVolumeAction
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.round(root.speakerVolume) + "%"]
        onExited: root.refreshSoon()
    }

    Process {
        id: microphoneVolumeAction
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", Math.round(root.microphoneVolume) + "%"]
        onExited: root.refreshSoon()
    }

    function toggleKeepAwake() {
        const want = !inhibitor.running
        inhibitor.running = want
        // Remember the choice so a shell reload can put it back (see the
        // Keep Awake section below). Only a click writes it — never the
        // inhibitor exiting — so a reload can't overwrite it with "off".
        Quickshell.execDetached(["sh", root.keepAwakeScript, "save", want ? "on" : "off"])
    }

    function toggleNotifications() {
        SettingsService.toggle("notify.on")
    }

    function toggleEditing() {
        editing = !editing
    }

    // Night Light: starts hyprsunset if nothing's running it yet (it
    // needs a moment before it answers hyprctl), then sets the colour
    // temperature — or sets it back to 6000, hyprsunset's "no tint".
    function toggleNightLight() {
        setNightLight(!nightLightOn)
    }

    function setNightLight(on) {
        actionGen++
        nightLightOn = on
        nightLightApply.restart()
    }

    // The Night Light card's intensity slider. Dragging it also switches
    // Night Light on, so you see the warmth you're picking.
    function setNightLightTemperature(kelvin) {
        const k = Math.max(nightLightMinKelvin, Math.min(nightLightMaxKelvin, Math.round(kelvin)))
        if (k === nightLightTemperature && nightLightOn)
            return
        actionGen++
        nightLightTemperature = k
        nightLightOn = k < nightLightMaxKelvin
        nightLightApply.restart()
        nightLightSave.restart()
    }

    function setNightLightAuto(on) {
        nightLightAuto = on
        nightLightSave.restart()
        if (on)
            checkNightLightSchedule(true)
    }

    function setNightLightSchedule(from, to) {
        nightLightAutoFrom = ((from % 24) + 24) % 24
        nightLightAutoTo = ((to % 24) + 24) % 24
        nightLightSave.restart()
        if (nightLightAuto)
            checkNightLightSchedule(true)
    }

    // Is `now` between "from" and "to"? Handles overnight spans (20 -> 6).
    // from === to counts as "never".
    function nightLightWindowNow() {
        const d = new Date()
        const h = d.getHours() + d.getMinutes() / 60
        const f = nightLightAutoFrom
        const t = nightLightAutoTo
        if (f === t)
            return false
        return f < t ? (h >= f && h < t) : (h >= f || h < t)
    }

    // -1 = not checked yet, 0 = last seen outside the window, 1 = inside.
    property int nightLightWasInWindow: -1

    // `force` (Automatic just switched on, or the times changed) applies
    // the window's state straight away; otherwise only a crossing acts.
    function checkNightLightSchedule(force) {
        if (!nightLightAuto) {
            nightLightWasInWindow = -1
            return
        }
        const inside = nightLightWindowNow() ? 1 : 0
        if (force || inside !== nightLightWasInWindow)
            setNightLight(inside === 1)
        nightLightWasInWindow = inside
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.nightLightAuto
        onTriggered: root.checkNightLightSchedule(false)
    }

    // Slider drags fire this many times a second; hyprctl gets one call
    // per pause instead, and never two at once.
    Timer {
        id: nightLightApply
        interval: 90
        onTriggered: {
            if (nightLightAction.running)
                nightLightApply.restart()
            else
                nightLightAction.running = true
        }
    }

    Process {
        id: nightLightAction
        command: ["sh", "-c", root.nightLightOn
            ? "pidof hyprsunset >/dev/null || { setsid hyprsunset >/dev/null 2>&1 & sleep 0.6; }; hyprctl hyprsunset temperature " + root.nightLightTemperature
            : "hyprctl hyprsunset temperature " + root.nightLightMaxKelvin]
        onExited: root.refreshSoon()
    }

    readonly property string nightLightScript: Directories.script("state/nightlight-state.sh")

    Timer {
        id: nightLightSave
        interval: 500
        onTriggered: Quickshell.execDetached(["sh", root.nightLightScript, "save",
            String(root.nightLightTemperature), root.nightLightAuto ? "on" : "off",
            String(root.nightLightAutoFrom), String(root.nightLightAutoTo)])
    }

    // Runs once, at startup: the saved intensity + schedule. If Automatic
    // was on and it's inside the window right now, the tint comes back
    // (so a reload or a login at night brings it back).
    Process {
        running: true
        command: ["sh", root.nightLightScript, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length < 4)
                    return
                const k = parseInt(p[0], 10)
                const f = parseInt(p[2], 10)
                const t = parseInt(p[3], 10)
                if (!isNaN(k))
                    root.nightLightTemperature = Math.max(root.nightLightMinKelvin,
                        Math.min(root.nightLightMaxKelvin - 50, k))
                if (!isNaN(f))
                    root.nightLightAutoFrom = ((f % 24) + 24) % 24
                if (!isNaN(t))
                    root.nightLightAutoTo = ((t % 24) + 24) % 24
                root.nightLightAuto = p[1] === "on"
                // Inside the window: bring the tint back. Outside it: leave
                // things be (a Night Light you switched on by hand before
                // a reload stays on) and just remember where we are.
                if (root.nightLightAuto) {
                    const inside = root.nightLightWindowNow()
                    root.nightLightWasInWindow = inside ? 1 : 0
                    if (inside)
                        root.setNightLight(true)
                }
            }
        }
    }

    // Game Mode (GameModeService.qml): the same set of Hyprland options
    // illogical-impulse's Game Mode tile flips (scripts/hyprland/gamemode-state.sh),
    // plus the shell's own side of it: the bar shrinks to date / clock / weather,
    // and the dock and the desktop widgets are taken away. This only forwards the
    // click; a click while the last change is still being applied is ignored there.
    function toggleGameMode() {
        GameModeService.toggle()
    }

    // ===== extra buttons =====

    readonly property bool darkModeOn: ThemeService.dark
    readonly property string darkModeName: ThemeService.mode

    function toggleDarkMode() {
        ThemeService.cycleModeAndSystem()
    }

    // Power Profile: power-saver -> balanced -> performance, live from
    // power-profiles-daemon (no polling).
    readonly property string powerProfileName: PowerProfiles.profile === PowerProfile.PowerSaver
        ? "saver" : (PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced")

    function cyclePowerProfile() {
        const p = PowerProfiles.profile
        if (p === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced
        else if (p === PowerProfile.Balanced)
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile
                ? PowerProfile.Performance : PowerProfile.PowerSaver
        else
            PowerProfiles.profile = PowerProfile.PowerSaver
    }

    // Easy Effects: ON = the app is running in the background (service mode,
    // no window). Also finds the Flatpak when there's no native install.
    function toggleEasyEffects() {
        actionGen++
        easyEffectsOn = !easyEffectsOn
        easyEffectsAction.running = true
    }

    Process {
        id: easyEffectsAction
        command: ["sh", "-c", root.easyEffectsOn
            ? "pgrep -x easyeffects >/dev/null && exit 0; if command -v easyeffects >/dev/null 2>&1; then setsid easyeffects --hide-window --service-mode >/dev/null 2>&1 & else setsid flatpak run com.github.wwmm.easyeffects --gapplication-service >/dev/null 2>&1 & fi"
            : "pkill -x easyeffects"]
        onExited: root.refreshSoon()
    }

    // Cloudflare WARP, the way end4's dots-hyprland does it: plain warp-cli
    // calls, no helper script. A click flips the tile at once and runs
    // `warp-cli connect` / `disconnect`; the state is read from
    // `warp-cli status` (only while the tile is on the panel). No
    // registration yet ("Unable")? The first click runs
    // `warp-cli registration new`, then connects. If something fails, a
    // notification says so. While WARP is still connecting, the tile
    // reads "Connecting...".
    //
    // One addition to end4's version: before connecting, the tile checks
    // that DNS is handled by systemd-resolved. When NetworkManager and
    // WARP both rewrite /etc/resolv.conf they fight, WARP's own
    // connectivity check keeps failing, and the status sticks on
    // "Connecting" although traffic flows. If /etc/resolv.conf isn't
    // resolved's, the tile fixes it (enable systemd-resolved, link
    // resolv.conf to its stub file) through pkexec, which shows the
    // shell's own Polkit prompt. Asked at most once per shell session.
    property int warpPollGen: 0
    property bool warpNeedsReg: false
    property bool warpDnsDeclined: false
    // Right after a click, `warp-cli status` still lags behind what was
    // asked, so polls inside this window are ignored.
    property double warpIgnoreUntil: 0
    // Any step of a click still in flight (the Polkit prompt can sit open
    // for a while): the tile keeps showing the click and doesn't poll.
    readonly property bool warpBusy: warpDnsCheck.running || warpDnsFix.running
        || warpRegister.running || warpConnect.running

    // Exit 10 = DNS needs the fix; anything else (fine, or no systemd-resolved
    // on this system at all) = leave it alone.
    readonly property string warpDnsCheckCmd: [
        "command -v systemctl >/dev/null 2>&1 || exit 0",
        "systemctl cat systemd-resolved.service >/dev/null 2>&1 || exit 0",
        "systemctl is-active --quiet systemd-resolved.service || exit 10",
        "case \"$(readlink -f /etc/resolv.conf)\" in /run/systemd/resolve/*) exit 0;; esac",
        "exit 10"
    ].join("\n")

    function refreshWarp() {
        if (warpPoll.running || warpBusy || !tiles.some(t => t.id === "warp"))
            return
        if (!warpProbed) {
            // First time: find out whether warp-cli exists before running it.
            if (!warpProbe.running)
                warpProbe.running = true
            return
        }
        if (!warpInstalled)
            return
        warpPollGen = actionGen
        warpPoll.running = true
    }

    // Where to get it, shown when the tile is clicked without warp-cli.
    readonly property string warpInstallHint:
        "warp-cli isn't installed. On Arch: yay -S cloudflare-warp-bin, then sudo systemctl enable --now warp-svc. "
        + "Other distros: https://developers.cloudflare.com/warp-client/get-started/linux/"

    // `command -v warp-cli`: exit 0 = installed. Run once at the first poll,
    // and again on a click while it is missing, so installing it later
    // works without restarting the shell.
    property bool warpProbeFromClick: false
    Process {
        id: warpProbe
        command: ["sh", "-c", "command -v warp-cli >/dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            const fromClick = root.warpProbeFromClick
            root.warpProbeFromClick = false
            root.warpInstalled = exitCode === 0
            root.warpProbed = true
            if (root.warpInstalled) {
                if (fromClick)
                    root.toggleWarp()
                else
                    root.refreshWarp()
            } else {
                root.warpOn = false
                root.warpConnecting = false
                if (fromClick)
                    Quickshell.execDetached(["notify-send", "-a", "Shell", "-u", "normal", "-i", "material:vpn_lock",
                        "Cloudflare WARP is not installed", root.warpInstallHint])
                else
                    console.warn("[warp] " + root.warpInstallHint)
            }
        }
    }

    Process {
        id: warpPoll
        command: ["warp-cli", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.warpBusy)
                    return
                if (root.warpPollGen !== root.actionGen) {
                    root.refreshSoon()
                    return
                }
                if (Date.now() < root.warpIgnoreUntil)
                    return
                // The daemon not answering also says "Unable", so tell the
                // two apart: only a missing registration needs registering.
                const daemonDown = text.includes("daemon")
                root.warpNeedsReg = text.includes("Unable") && !daemonDown
                if (text.includes("Connecting")) {
                    root.warpOn = false
                    root.warpConnecting = true
                } else if (text.includes("Connected")) {
                    root.warpOn = true
                    root.warpConnecting = false
                } else {
                    root.warpOn = false
                    root.warpConnecting = false
                }
            }
        }
    }

    function toggleWarp() {
        if (warpBusy || warpProbe.running)
            return
        if (!warpProbed || !warpInstalled) {
            // Not known to be there (yet, or still not): look again, and
            // either carry on with the click or tell the user to install it.
            warpProbeFromClick = true
            warpProbe.running = true
            return
        }
        actionGen++
        const want = !(warpOn || warpConnecting)
        warpIgnoreUntil = Date.now() + 6000
        warpOn = false
        warpConnecting = want
        if (!want)
            Quickshell.execDetached(["warp-cli", "disconnect"])
        else if (!warpDnsDeclined)
            warpDnsCheck.running = true
        else
            warpRegisterOrConnect()
    }

    function warpRegisterOrConnect() {
        if (warpNeedsReg) {
            warpRegister.running = true
        } else {
            warpIgnoreUntil = Date.now() + 6000
            warpConnect.running = true
        }
    }

    Process {
        id: warpDnsCheck
        command: ["sh", "-c", root.warpDnsCheckCmd]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 10)
                warpDnsFix.running = true
            else
                root.warpRegisterOrConnect()
        }
    }

    Process {
        id: warpDnsFix
        command: ["pkexec", "sh", "-c",
            "systemctl enable --now systemd-resolved.service && ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.warpDnsDeclined = true
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "material:vpn_lock", "Cloudflare WARP",
                    "DNS fix skipped, so WARP may keep saying Connecting even when it works"])
            }
            root.warpRegisterOrConnect()
        }
    }

    Process {
        id: warpConnect
        command: ["warp-cli", "connect"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.warpConnecting = false
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "material:vpn_lock", "Cloudflare WARP",
                    "Connection failed. Please inspect manually with the warp-cli command"])
            }
        }
    }

    Process {
        id: warpRegister
        command: ["warp-cli", "registration", "new"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.warpNeedsReg = false
                root.warpIgnoreUntil = Date.now() + 6000
                warpConnect.running = true
            } else {
                root.warpConnecting = false
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "material:vpn_lock", "Cloudflare WARP",
                    "Registration failed. Please inspect manually with the warp-cli command"])
            }
        }
    }

    // On-Screen Keyboard: the shell's own (modules/sekai/keyboard/), the same one (and the
    // same state, KeyboardService.qml) as the bar's keyboard button.
    function toggleKeyboard() {
        KeyboardService.toggle()
    }

    // Anti-Flashbang, from end4's dots-hyprland: Hyprland's screen shader set
    // to one of his two shaders (scripts/hyprland/anti-flashbang-weak.glsl and
    // anti-flashbang.glsl), which dim the whole screen the brighter it is on
    // average. Each click cycles off -> weak -> strong -> off.
    //
    // Hyprland's Lua config ignores `hyprctl keyword`, so (like end4) the
    // setting goes into a Lua override file, ~/.config/hypr/sekaipop_overrides.lua,
    // through scripts/hyprland/antiflashbang-state.sh, which also reloads Hyprland and
    // applies it live. For it to survive a reload or restart, hyprland.lua
    // needs one line:  pcall(require, "sekaipop_overrides")
    // The state is read back from Hyprland, so a reload that drops it shows
    // up as OFF.
    readonly property string antiFlashbangScript: Directories.script("hyprland/antiflashbang-state.sh")
    readonly property var antiFlashbangNames: ["off", "weak", "strong"]

    function toggleAntiFlashbang() {
        if (antiFlashbangAction.running)
            return
        actionGen++
        antiFlashbangLevel = (antiFlashbangLevel + 1) % 3
        antiFlashbangOn = antiFlashbangLevel > 0
        antiFlashbangAction.command = ["sh", root.antiFlashbangScript,
                                       root.antiFlashbangNames[root.antiFlashbangLevel]]
        antiFlashbangAction.running = true
    }

    Process {
        id: antiFlashbangAction
        onExited: root.refreshSoon()
    }

    // Music Recognition: listens to what the speakers are playing for a few
    // seconds and notifies the song (scripts/musicRecognition/music-recognize.sh). ON for as
    // long as that takes; a click while it's listening does nothing.
    readonly property bool musicListening: musicProc.running
    readonly property string musicScript: Directories.script("musicRecognition/music-recognize.sh")

    function toggleMusicRecognition() {
        if (!musicProc.running)
            musicProc.running = true
    }

    Process {
        id: musicProc
        command: ["sh", root.musicScript]
    }

    // Screen Snip and Color Picker are one-shots. QuickPanel.qml closes the
    // panel first; the wait lets its drop-away animation finish so it
    // isn't in the picture (or under the picker).
    //
    // Screen Snip is the same thing as the bar's Screenshot button: the shell's
    // own region picker (Copy / Save / ..., then the preview card), kept off the
    // frozen picture until the phone is gone (RegionService.showLater). With
    // Settings -> General -> "Own region picker" off it is the old grim + slurp.
    function runTileAction(id) {
        if (id === "screenSnip" && SettingsService.flag("region.own")) {
            RegionService.showLater("copy")
        } else if (id === "screenSnip") {
            Quickshell.execDetached(["sh", "-c", [
                "sleep 1",
                "dir=\"$HOME/Pictures/Screenshots\"",
                "mkdir -p \"$dir\"",
                "f=\"$dir/$(date +%Y-%m-%d_%H-%M-%S).png\"",
                "g=$(slurp) || exit 0",
                "grim -g \"$g\" \"$f\" && wl-copy < \"$f\" && notify-send -a sekaipop -i material:photo_camera \"Screenshot saved\" \"$f\""
            ].join("; ")])
        } else if (id === "colorPicker") {
            Quickshell.execDetached(["sh", "-c", "sleep 1; exec hyprpicker -a"])
        }
    }

    // ===== button layout =====
    property var tiles: QT.defaultTiles
    // Most buttons a row may hold, 1-5 (edit mode's Columns setting; 5 is
    // the old width-only flow). Saved next to the list as an "@columns" pair.
    property int tileColumns: QT.defaultColumns

    // Desktop presets (services/DesktopPresetService.qml) save and wear the
    // button layout. This file isn't a singleton, so it tells the service what
    // it has whenever that changes, and listens for a preset's layout.
    function reportTiles() {
        DesktopPresetService.noteQuickTiles(root.tiles, root.tileColumns)
    }

    onTilesChanged: root.reportTiles()
    onTileColumnsChanged: root.reportTiles()
    Component.onCompleted: root.reportTiles()

    Connections {
        target: DesktopPresetService

        function onQuickTilesRequested(list, columns) {
            const c = QT.clampColumns(parseInt(columns, 10))
            const clean = QT.sanitize(list.map(t => ({ id: t.id, size: t.size })), c)
            root.tileColumns = c
            root.setTiles(clean)
        }
    }

    function setTiles(list) {
        tiles = list
        const args = ["sh", root.tilesScript, "save", "@columns", String(root.tileColumns)]
        for (const t of list) {
            args.push(t.id)
            args.push(t.size)
        }
        Quickshell.execDetached(args)
    }

    // Fewer columns make the grid taller, so going down is refused (nothing
    // changes) when the buttons wouldn't fit under the panel's row limit —
    // remove a button first. Going up always fits.
    function setTileColumns(columns) {
        const c = QT.clampColumns(columns)
        if (c === tileColumns || !QT.fits(tiles, c))
            return
        tileColumns = c
        setTiles(tiles)
    }

    function indexOfTile(id) {
        return tiles.findIndex(t => t.id === id)
    }

    // Move the button at `from` so it ends up at position `to`.
    function moveTile(from, to) {
        if (from < 0 || from >= tiles.length || to < 0 || to >= tiles.length || from === to)
            return
        const list = tiles.slice()
        const [t] = list.splice(from, 1)
        list.splice(to, 0, t)
        setTiles(list)
    }

    // Small -> big -> long -> small (1, 2, 3 columns), skipping a size that
    // wouldn't fit under the panel's row limit. Nothing changes if no other
    // size fits.
    function resizeTile(index) {
        if (index < 0 || index >= tiles.length)
            return
        const size = QT.nextSize(tiles, index, tileColumns)
        if (size === tiles[index].size)
            return
        const list = tiles.map(t => ({ id: t.id, size: t.size }))
        list[index].size = size
        setTiles(list)
    }

    function removeTile(index) {
        if (index < 0 || index >= tiles.length)
            return
        const list = tiles.slice()
        list.splice(index, 1)
        setTiles(list)
    }

    // New buttons join the end, small. Ignored if it's already there, isn't
    // a real button, or there's no room left.
    function addTile(id) {
        if (QT.catalog.indexOf(id) < 0 || indexOfTile(id) >= 0)
            return
        const list = tiles.concat([{ id: id, size: "small" }])
        if (!QT.fits(list, tileColumns))
            return
        setTiles(list)
    }

    Process {
        id: wifiAction
        command: ["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"]
        onExited: root.refreshSoon()
    }

    Process {
        id: bluetoothAction
        command: ["bluetoothctl", "power", root.bluetoothOn ? "on" : "off"]
        onExited: root.refreshSoon()
    }

    Process {
        id: speakerAction
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", root.speakerOn ? "0" : "1"]
        onExited: root.refreshSoon()
    }

    Process {
        id: microphoneAction
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", root.microphoneOn ? "0" : "1"]
        onExited: root.refreshSoon()
    }

    // ===== Wi-Fi network list / Bluetooth device list =====

    property var wifiNetworks: []          // [{ssid, signal, secured, connected}]
    property bool wifiScanning: false
    // True while a rescan "burst" runs: from the moment the dialog opens (or
    // "Scan" is pressed) until the burst's last read. Separate from
    // wifiScanning, which also goes true for every quiet background read —
    // the button would flash "Scanning…" on its own if it followed that.
    property bool wifiManualScanning: false
    property bool networkDialogOpen: false
    // Reads left in the current burst.
    property int wifiBurstLeft: 0
    property string wifiConnectingSsid: ""
    property string wifiConnectSsid: ""
    property string wifiConnectPassword: ""
    // The profile for the current Wi-Fi action (empty when joining a new network).
    property string wifiProfileUuid: ""
    property string wifiConnectError: ""
    // Saved profiles keyed by SSID and security kind. A saved network
    // connects without a password and can be forgotten (its profile deleted).
    property var wifiSaved: ({})
    // What the last scan saw, before the saved flag is put on it.
    property var wifiSeen: []

    // `--rescan no` reads NetworkManager's last-known scan: it answers at once, so
    // the dialog has something to show the moment it opens. A real rescan is a
    // separate job (wifiRescanAction below) that is started in the background at
    // the same time, and the list is read again every second for a few seconds
    // while the radio finishes its sweep, so new networks appear as they are
    // found instead of after one long blocking wait. Same "-e no, SSID takes
    // whatever's left" trick as the connected-SSID line above, extended to 3
    // fields instead of 1: signal/security/in-use never contain a colon, so
    // they're safe to peel off the right with awk, whatever's left (however
    // many colons it has) is the SSID.
    readonly property string wifiListScript: [
        "LC_ALL=C nmcli -t -e no -f SSID,SIGNAL,SECURITY,IN-USE device wifi list --rescan no 2>/dev/null | awk -F: '",
        "  { n = NF; inuse = $n; sec = $(n - 1); sig = $(n - 2)",
        "    ssid = $1; for (i = 2; i <= n - 3; i++) ssid = ssid \":\" $i",
        "    if (ssid == \"\") next",
        "    print sig \"|\" sec \"|\" inuse \"|\" ssid }'"
    ].join("\n")

    // Ask NetworkManager for a fresh scan. It may refuse if the last one was very
    // recent (it rate-limits) — that is fine, the cached list is then fresh anyway.
    readonly property string wifiRescanScript: "timeout 5 nmcli device wifi rescan >/dev/null 2>&1"

    // Plain read of the list (cheap path). If one is already running this one is
    // skipped: the burst timer reads again a second later, and the live refresh
    // does too, so nothing is lost.
    function fetchWifiList() {
        if (wifiListAction.running)
            return
        wifiScanning = true
        wifiListAction.running = true
    }

    // Show what NetworkManager already knows right now, ask for a fresh scan, and
    // keep reading for a few seconds. Pressing "Scan" while a read is in flight
    // used to be dropped (the second press was the one that worked); now the
    // rescan is its own process, so the press always goes through.
    function startWifiRescan() {
        wifiManualScanning = true
        wifiBurstLeft = 7
        if (!wifiRescanAction.running)
            wifiRescanAction.running = true
        fetchWifiList()
        wifiBurstTimer.restart()
    }

    function stopWifiRescan() {
        wifiBurstTimer.stop()
        wifiBurstLeft = 0
        wifiManualScanning = false
    }

    // forceRescan=true -> rescan burst (dialog just opened, or "Scan" pressed);
    // otherwise one quiet read.
    function scanWifi(forceRescan) {
        if (forceRescan)
            startWifiRescan()
        else
            fetchWifiList()
    }

    readonly property bool wifiActionRunning: wifiConnectAction.running || wifiDisconnectAction.running || wifiForgetAction.running

    function connectWifi(ssid, password) {
        if (wifiActionRunning)
            return
        actionGen++
        wifiConnectError = ""
        wifiConnectingSsid = ssid
        wifiConnectSsid = ssid
        wifiConnectPassword = password
        // No password given and a profile exists: bring that profile up (it has the password).
        wifiProfileUuid = password === "" ? (wifiNetworks.find(n => n.ssid === ssid)?.profileUuid || "") : ""
        wifiConnectAction.running = true
    }

    function disconnectWifi(ssid) {
        if (wifiActionRunning)
            return
        const network = wifiNetworks.find(n => n.ssid === ssid && n.connected)
        if (!network || !network.activeProfileUuid) {
            wifiConnectError = "The active Wi-Fi profile is unavailable. Try again after the list refreshes."
            fetchWifiSaved()
            return
        }
        actionGen++
        wifiConnectError = ""
        wifiProfileUuid = network.activeProfileUuid
        wifiDisconnectAction.running = true
    }

    function forgetWifi(uuid) {
        if (wifiActionRunning || !uuid || !wifiNetworks.some(n => n.profileUuid === uuid))
            return
        actionGen++
        wifiConnectError = ""
        wifiProfileUuid = uuid
        wifiForgetAction.running = true
    }

    // The saved flag goes on the scan's list; redone when either the scan or the saved list
    // changes, whichever arrives second.
    function annotateWifi() {
        const next = wifiSeen.map(n => {
            const profile = wifiSaved[JSON.stringify([n.ssid, n.securityKind])]
            return {
                ssid: n.ssid,
                signal: n.signal,
                secured: n.secured,
                connected: n.connected,
                saved: profile !== undefined,
                profileUuid: profile ? profile.uuid : "",
                activeProfileUuid: profile && profile.active ? profile.uuid : ""
            }
        })
        // The dialog shows the signal as 3 bars, so a few points of change is not a change: a
        // new list resets the dialog's list (scroll position, an opened row), and during a
        // scan the list is read every second.
        const key = list => JSON.stringify(list.map(n => [n.ssid, n.signal >= 33, n.signal >= 66, n.secured, n.connected, n.profileUuid, n.activeProfileUuid]))
        if (key(next) !== key(wifiNetworks))
            wifiNetworks = next
    }

    function fetchWifiSaved() {
        if (!wifiSavedAction.running)
            wifiSavedAction.running = true
    }

    function applyWifiSaved(text) {
        let profiles
        try {
            profiles = JSON.parse(text)
        } catch (e) {
            return
        }
        if (!Array.isArray(profiles))
            return
        const map = {}
        for (const profile of profiles) {
            const key = JSON.stringify([profile.ssid, profile.securityKind])
            if (map[key] === undefined || profile.active)
                map[key] = profile
        }
        wifiSaved = map
        annotateWifi()
    }

    function applyWifiList(text) {
        const list = []
        for (const line of text.split("\n")) {
            if (line.trim() === "")
                continue
            const parts = line.split("|")
            if (parts.length < 4)
                continue
            const signal = parseInt(parts[0], 10)
            const security = parts[1]
            const ssid = parts.slice(3).join("|")
            if (ssid === "")
                continue
            list.push({
                ssid: ssid,
                signal: isNaN(signal) ? 0 : signal,
                secured: security !== "" && security !== "--",
                securityKind: security === "" || security === "--" ? "open"
                    : security.includes("802.1X") ? "enterprise" : "personal",
                connected: parts[2] === "*"
            })
        }
        // nmcli lists every BSSID it can see separately — the same SSID from two
        // APs — so one row is kept per name: the connected one, else the strongest.
        const best = new Map()
        for (const n of list) {
            const e = best.get(n.ssid)
            if (e === undefined || (n.connected && !e.connected)
                    || (n.connected === e.connected && n.signal > e.signal))
                best.set(n.ssid, n)
        }
        // Connected first, then strongest signal. The list is read again every
        // second during a rescan, so the signal is compared in steps of 10 and
        // ties keep the place the row already had — rows don't jump around under
        // a finger because a signal moved by one or two points.
        const prev = {}
        wifiSeen.forEach((n, i) => { prev[n.ssid] = i })
        const rank = n => (n.connected ? 1000 : 0) + Math.round(n.signal / 10) * 10
        wifiSeen = Array.from(best.values()).sort((a, b) => {
            const d = rank(b) - rank(a)
            if (d !== 0)
                return d
            const pa = prev[a.ssid] !== undefined ? prev[a.ssid] : 1e6
            const pb = prev[b.ssid] !== undefined ? prev[b.ssid] : 1e6
            if (pa !== pb)
                return pa - pb
            return a.ssid < b.ssid ? -1 : (a.ssid > b.ssid ? 1 : 0)
        })
        annotateWifi()
    }

    Process {
        id: wifiSavedAction
        command: ["python3", Directories.script("system/wifi-saved-profiles.py")]
        stdout: StdioCollector {
            onStreamFinished: root.applyWifiSaved(text)
        }
    }

    // Which networks are saved is read when the dialog opens, not on every refresh tick.
    // Closing the dialog ends any rescan burst that is still running.
    onNetworkDialogOpenChanged: {
        if (networkDialogOpen)
            fetchWifiSaved()
        else
            stopWifiRescan()
    }

    Process {
        id: wifiListAction
        command: ["sh", "-c", root.wifiListScript]
        stdout: StdioCollector {
            onStreamFinished: root.applyWifiList(text)
        }
        onExited: root.wifiScanning = false
    }

    // The real rescan. It runs on its own, so it never blocks the reads below.
    Process {
        id: wifiRescanAction
        command: ["sh", "-c", root.wifiRescanScript]
    }

    // While a rescan burst runs: read the list once a second (new networks show up
    // as the radio finds them), then stop. The 7th read ends the burst.
    Timer {
        id: wifiBurstTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.fetchWifiList()
            root.wifiBurstLeft--
            if (root.wifiBurstLeft <= 0)
                root.stopWifiRescan()
        }
    }

    // Keeps the network list live after the burst is over instead of frozen at
    // whatever nmcli returned last — same idea as audioMixerRefresh further down,
    // using the cheap `--rescan no` path rather than a real rescan on every tick.
    // Paused during a burst, which already reads every second.
    Timer {
        id: wifiLiveRefresh
        interval: 5000
        repeat: true
        running: root.active && root.networkDialogOpen && !root.wifiManualScanning
        onTriggered: root.scanWifi(false)
    }

    Process {
        id: wifiConnectAction
        command: root.wifiProfileUuid !== ""
            ? ["nmcli", "connection", "up", "uuid", root.wifiProfileUuid]
            : (root.wifiConnectPassword !== ""
                ? ["nmcli", "device", "wifi", "connect", root.wifiConnectSsid, "password", root.wifiConnectPassword]
                : ["nmcli", "device", "wifi", "connect", root.wifiConnectSsid])
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.wifiConnectError = text.trim()
            }
        }
        onExited: {
            root.wifiConnectPassword = ""
            root.wifiProfileUuid = ""
            root.wifiConnectingSsid = ""
            root.refreshSoon()
            root.scanWifi(false)
            // a new network that just connected now has a profile
            root.fetchWifiSaved()
        }
    }

    Process {
        id: wifiDisconnectAction
        command: ["nmcli", "connection", "down", "uuid", root.wifiProfileUuid]
        onExited: {
            root.wifiProfileUuid = ""
            root.refreshSoon()
            root.fetchWifiSaved()
            root.scanWifi(false)
        }
    }

    Process {
        id: wifiForgetAction
        command: ["nmcli", "connection", "delete", "uuid", root.wifiProfileUuid]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.wifiConnectError = text.trim()
            }
        }
        onExited: {
            root.wifiProfileUuid = ""
            root.refreshSoon()
            root.fetchWifiSaved()
            root.scanWifi(false)
        }
    }

    property var bluetoothDevices: []      // [{address, name, connected, paired, battery}]
    property bool bluetoothScanning: false
    // True while a discovery burst runs: from the moment the dialog opens (or
    // "Scan" is pressed) until the burst's last read. Separate from
    // bluetoothScanning, which also goes true for every quiet background read.
    property bool bluetoothManualScanning: false
    property bool bluetoothDialogOpen: false
    // Reads left in the current burst.
    property int bluetoothBurstLeft: 0
    property string bluetoothConnectingAddress: ""
    property string bluetoothConnectAddress: ""
    property string bluetoothConnectError: ""

    // Every device BlueZ knows: the paired ones first, then the ones discovery has
    // found nearby. Each line is `mac|connected|battery|paired|name`. A connected
    // device gets a single `bluetoothctl info` for its battery level (BlueZ's
    // "Battery Percentage"; empty when the device doesn't report one). A nearby
    // device that was never paired and has no name (BLE beacons show their own
    // address as the name) is left out, or the list would fill up with noise.
    readonly property string bluetoothListScript: [
        "p=$(timeout 3 bluetoothctl devices Paired 2>/dev/null)",
        "a=$(timeout 3 bluetoothctl devices 2>/dev/null)",
        "c=$(timeout 3 bluetoothctl devices Connected 2>/dev/null)",
        "printf '%s\\n%s\\n' \"$p\" \"$a\" | awk 'NF && !seen[$2]++' | while IFS= read -r line; do",
        "  mac=$(printf '%s' \"$line\" | awk '{print $2}')",
        "  name=$(printf '%s' \"$line\" | cut -d' ' -f3-)",
        "  pair=0",
        "  printf '%s\\n' \"$p\" | grep -q \"$mac\" && pair=1",
        "  if [ \"$pair\" = 0 ]; then",
        "    [ -n \"$name\" ] || continue",
        "    [ \"$name\" = \"$(printf '%s' \"$mac\" | tr ':' '-')\" ] && continue",
        "  fi",
        "  conn=0",
        "  printf '%s\\n' \"$c\" | grep -q \"$mac\" && conn=1",
        "  batt=",
        "  if [ \"$conn\" = 1 ]; then",
        "    batt=$(timeout 2 bluetoothctl info \"$mac\" </dev/null 2>/dev/null | sed -n 's/.*Battery Percentage:.*(\\([0-9]*\\)).*/\\1/p' | head -n1)",
        "  fi",
        "  printf '%s|%s|%s|%s|%s\\n' \"$mac\" \"$conn\" \"$batt\" \"$pair\" \"$name\"",
        "done"
    ].join("\n")

    // Discovery: bluetoothctl looks for devices for 9 seconds and then quits (the
    // discovery stops when it quits). `exec` so that stopping this process also
    // stops bluetoothctl. A burst of reads runs next to it (bluetoothBurstTimer).
    readonly property string bluetoothDiscoverScript: "exec timeout 15 bluetoothctl --timeout 9 scan on >/dev/null 2>&1"

    // Pair, trust and connect a nearby device; the address comes in as $1. It
    // registers a "no input, no output" agent, which is what headphones, speakers
    // and the like need ("just works" pairing). A device that asks for a PIN or a
    // code (a keyboard, say) can't be paired this way: it ends with an error that
    // points to the Advanced button. Success is checked on the device itself.
    readonly property string bluetoothPairScript: [
        "mac=\"$1\"",
        "case \"$mac\" in ??:??:??:??:??:??) ;; *) exit 2 ;; esac",
        "{",
        "  printf 'agent NoInputNoOutput\\ndefault-agent\\npair %s\\n' \"$mac\"",
        "  i=0",
        "  while [ \"$i\" -lt 25 ]; do",
        "    sleep 1",
        "    bluetoothctl info \"$mac\" 2>/dev/null | grep -q 'Paired: yes' && break",
        "    i=$((i + 1))",
        "  done",
        "  printf 'trust %s\\nconnect %s\\n' \"$mac\" \"$mac\"",
        "  sleep 5",
        "} | timeout 45 bluetoothctl >/dev/null 2>&1",
        "bluetoothctl info \"$mac\" 2>/dev/null | grep -q 'Paired: yes' && exit 0",
        "echo \"Could not pair. A device that asks for a PIN needs the Advanced button.\" >&2",
        "exit 1"
    ].join("\n")

    // Forget (remove) a paired device; the address comes in as $1. BlueZ drops the
    // pairing and the device from its list, and disconnects it if it was connected.
    readonly property string bluetoothForgetScript: [
        "case \"$1\" in ??:??:??:??:??:??) ;; *) exit 2 ;; esac",
        "out=$(timeout 10 bluetoothctl remove \"$1\" 2>&1)",
        "case \"$out\" in *\"has been removed\"*) exit 0 ;; esac",
        "echo \"Could not forget the device.\" >&2",
        "exit 1"
    ].join("\n")

    // The popups' "Advanced" button: the full Wi-Fi / Bluetooth settings app
    // (nm-connection-editor / blueman, or the first of a few alternatives, see the script).
    function openNetworkSettings() {
        Quickshell.execDetached(["sh", Directories.script("system/open-settings-app.sh"), "wifi"])
    }

    function openBluetoothSettings() {
        Quickshell.execDetached(["sh", Directories.script("system/open-settings-app.sh"), "bluetooth"])
    }

    // One quiet read of the list (cheap path). If one is already running this one is
    // skipped: the burst timer and the live refresh read again soon after.
    function fetchBluetoothList() {
        if (bluetoothListAction.running)
            return
        bluetoothScanning = true
        bluetoothListAction.running = true
    }

    // Show what BlueZ already knows right now, start looking for devices, and keep
    // reading for a few seconds so devices show up as they are found.
    function startBluetoothScan() {
        bluetoothManualScanning = true
        bluetoothBurstLeft = 9
        if (!bluetoothDiscoverAction.running)
            bluetoothDiscoverAction.running = true
        fetchBluetoothList()
        bluetoothBurstTimer.restart()
    }

    function stopBluetoothScan() {
        bluetoothBurstTimer.stop()
        bluetoothBurstLeft = 0
        bluetoothManualScanning = false
        // looking for devices slows pairing down and can make a playing headset stutter
        if (bluetoothDiscoverAction.running)
            bluetoothDiscoverAction.running = false
    }

    // discover=true -> look for devices (dialog just opened, or "Scan" pressed);
    // otherwise one quiet read.
    function scanBluetooth(discover) {
        if (discover)
            startBluetoothScan()
        else
            fetchBluetoothList()
    }

    // A device that is not paired yet is paired first (see bluetoothPairScript);
    // a paired one is just connected.
    function connectBluetoothDevice(address) {
        actionGen++
        bluetoothConnectError = ""
        bluetoothConnectingAddress = address
        bluetoothConnectAddress = address
        const d = bluetoothDevices.find(x => x.address === address)
        if (d !== undefined && d.paired === false) {
            stopBluetoothScan()
            bluetoothPairAction.running = true
        } else {
            bluetoothConnectAction.running = true
        }
    }

    // Forget a paired device (BlueZ "remove": the pairing is deleted, a connected device is dropped).
    function forgetBluetoothDevice(address) {
        const d = bluetoothDevices.find(x => x.address === address)
        if (d === undefined || d.paired !== true || bluetoothForgetAction.running)
            return
        actionGen++
        bluetoothConnectError = ""
        bluetoothConnectAddress = address
        bluetoothForgetAction.running = true
    }

    function disconnectBluetoothDevice(address) {
        actionGen++
        bluetoothConnectError = ""
        bluetoothConnectingAddress = address
        bluetoothConnectAddress = address
        bluetoothDisconnectAction.running = true
    }

    function applyBluetoothList(text) {
        const list = []
        for (const line of text.split("\n")) {
            if (line.trim() === "")
                continue
            const parts = line.split("|")
            if (parts.length < 5)
                continue
            const address = parts[0]
            if (address === "")
                continue
            const name = parts.slice(4).join("|")
            // -1 = the device doesn't report a battery level.
            const battery = parseInt(parts[2], 10)
            list.push({
                address: address,
                name: name !== "" ? name : address,
                connected: parts[1] === "1",
                paired: parts[3] === "1",
                battery: isNaN(battery) ? -1 : Math.max(0, Math.min(100, battery))
            })
        }
        // Connected first, then paired, then the ones found nearby. The list is read
        // again every second while looking for devices, so a row keeps the place it
        // already had and a new device goes to the end of its group (by name).
        const prev = {}
        bluetoothDevices.forEach((d, i) => { prev[d.address] = i })
        const rank = d => d.connected ? 2 : (d.paired ? 1 : 0)
        list.sort((a, b) => {
            const r = rank(b) - rank(a)
            if (r !== 0)
                return r
            const pa = prev[a.address] !== undefined ? prev[a.address] : 1e6
            const pb = prev[b.address] !== undefined ? prev[b.address] : 1e6
            if (pa !== pb)
                return pa - pb
            return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0)
        })
        // same reason as annotateWifi: no new list when nothing on screen changed
        if (JSON.stringify(list) !== JSON.stringify(bluetoothDevices))
            bluetoothDevices = list
    }

    Process {
        id: bluetoothListAction
        command: ["sh", "-c", root.bluetoothListScript]
        stdout: StdioCollector {
            onStreamFinished: root.applyBluetoothList(text)
        }
        onExited: root.bluetoothScanning = false
    }

    // The discovery itself. It runs on its own, so it never blocks the reads.
    Process {
        id: bluetoothDiscoverAction
        command: ["sh", "-c", root.bluetoothDiscoverScript]
    }

    // While a discovery burst runs: read the list once a second (devices show up as
    // they are found), then stop. The 9th read ends the burst.
    Timer {
        id: bluetoothBurstTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.fetchBluetoothList()
            root.bluetoothBurstLeft--
            if (root.bluetoothBurstLeft <= 0)
                root.stopBluetoothScan()
        }
    }

    // Closing the dialog ends the burst and the discovery.
    onBluetoothDialogOpenChanged: if (!bluetoothDialogOpen) stopBluetoothScan()

    // Same live-list idea as wifiLiveRefresh: bluetoothctl devices is
    // cheap (no discovery), so this just re-reads paired/connected
    // state every few seconds while the dialog's open. Paused during a
    // burst, which already reads every second.
    Timer {
        id: bluetoothLiveRefresh
        interval: 3000
        repeat: true
        running: root.active && root.bluetoothDialogOpen && !root.bluetoothManualScanning
        onTriggered: root.scanBluetooth()
    }

    // Pairs a nearby device that was tapped (see bluetoothPairScript).
    Process {
        id: bluetoothPairAction
        command: ["sh", "-c", root.bluetoothPairScript, "sh", root.bluetoothConnectAddress]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.bluetoothConnectError = text.trim()
            }
        }
        onExited: {
            root.bluetoothConnectingAddress = ""
            root.refreshSoon()
            root.scanBluetooth()
        }
    }

    Process {
        id: bluetoothForgetAction
        command: ["sh", "-c", root.bluetoothForgetScript, "sh", root.bluetoothConnectAddress]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.bluetoothConnectError = text.trim()
            }
        }
        onExited: {
            root.refreshSoon()
            root.scanBluetooth()
        }
    }

    Process {
        id: bluetoothConnectAction
        command: ["bluetoothctl", "connect", root.bluetoothConnectAddress]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.bluetoothConnectError = text.trim()
            }
        }
        onExited: {
            root.bluetoothConnectingAddress = ""
            root.refreshSoon()
            root.scanBluetooth()
        }
    }

    Process {
        id: bluetoothDisconnectAction
        command: ["bluetoothctl", "disconnect", root.bluetoothConnectAddress]
        onExited: {
            root.bluetoothConnectingAddress = ""
            root.refreshSoon()
            root.scanBluetooth()
        }
    }

    // ===== Audio device picker + per-app mixer =====
    property var speakerDevices: []      // [{id, name, active}]
    property var microphoneDevices: []   // [{id, name, active}]
    property var speakerStreams: []      // [{id, name, volume, muted, corked}] — sink-inputs, e.g. Spotify/a browser/a game
    property var microphoneStreams: []   // [{id, name, volume, muted, corked}] — source-outputs, e.g. a voice call, OBS
    property bool audioDevicesScanning: false
    property bool audioDevicesManualScanning: false
    property string audioDeviceSelectingId: ""
    property string audioSetSinkId: ""
    property string audioSetSourceId: ""
    // Sits under the dialog itself (see QuickPanel.qml): a live mixer is
    // worth polling faster than the panel's normal 3s, since apps starting
    // up or finishing is exactly the kind of thing you'd want to catch
    // while this is open, unlike the Wi-Fi/Bluetooth lists next to it.
    property bool audioMixerActive: false

    readonly property string audioSnapshotScript: [
        "pactl get-default-sink 2>/dev/null",
        "echo '___SPLIT___'",
        "pactl get-default-source 2>/dev/null",
        "echo '___SPLIT___'",
        "pactl -f json list sinks 2>/dev/null",
        "echo '___SPLIT___'",
        "pactl -f json list sources 2>/dev/null",
        "echo '___SPLIT___'",
        "pactl -f json list sink-inputs 2>/dev/null",
        "echo '___SPLIT___'",
        "pactl -f json list source-outputs 2>/dev/null"
    ].join("\n")

    function scanAudioDevices(manual) {
        if (manual)
            audioDevicesManualScanning = true
        if (audioSnapshotAction.running)
            return
        audioDevicesScanning = true
        audioSnapshotAction.running = true
    }

    function setDefaultSink(id) {
        actionGen++
        audioDeviceSelectingId = id
        audioSetSinkId = id
        setDefaultSinkAction.running = true
    }

    function setDefaultSource(id) {
        actionGen++
        audioDeviceSelectingId = id
        audioSetSourceId = id
        setDefaultSourceAction.running = true
    }

    // kind is "sink-input" (a speaker-side app, from speakerStreams) or
    // "source-output" (a microphone-side one, from microphoneStreams) —
    // matches pactl's own two command families one-for-one.
    //
    // Same debounce as setSpeakerVolume/setMicrophoneVolume above: the
    // row's own number updates immediately (so a drag doesn't wait on a
    // process, let alone the next 2s auto-refresh), the actual `pactl`
    // call settles 80ms after the last move. One shared pending/timer
    // pair is enough since only one slider is ever being dragged at a
    // time — if a second one starts before the first settles, its value
    // just wins, same as the master sliders already assume.
    property string pendingStreamKind: ""
    property string pendingStreamId: ""
    property real pendingStreamVolume: 0

    // Which per-app row (if any) currently has an active mouse drag —
    // set by VolumeMixerDialog.qml's streamDragStarted/streamDragEnded
    // by way of QuickPanelFace/QuickPanel. Guards the streams-array
    // reassignment below: speakerStreams/microphoneStreams back a
    // ListView (mixerList in VolumeMixerDialog.qml), and a plain JS
    // array bound as a QML model gets fully torn down and rebuilt the
    // instant its top-level reference changes, however small the
    // actual change — there's no incremental diffing. Reassigning it
    // on every pointer-move (which setStreamVolume used to do
    // unconditionally) destroyed the very delegate whose MouseArea
    // held the drag grab, so only the initial click ever registered
    // and holding-and-sliding never worked. The dragged row already
    // shows its own live value locally via dragValue/dragging, so
    // skipping the echo here costs nothing until the drag ends.
    property string draggingStreamKind: ""
    property string draggingStreamId: ""

    function beginStreamDrag(kind, id) {
        draggingStreamKind = kind
        draggingStreamId = id
    }

    function endStreamDrag(kind, id) {
        if (draggingStreamKind !== kind || draggingStreamId !== id)
            return
        draggingStreamKind = ""
        draggingStreamId = ""
        // Reconcile immediately rather than waiting for the next
        // poll — the drag's last value is already the true one.
        if (pendingStreamKind === kind && pendingStreamId === id) {
            setStreamListFor(kind, streamListFor(kind).map(
                s => s.id === id ? Object.assign({}, s, { volume: pendingStreamVolume }) : s))
        }
    }

    function streamListFor(kind) {
        return kind === "source-output" ? microphoneStreams : speakerStreams
    }

    function setStreamListFor(kind, list) {
        if (kind === "source-output")
            microphoneStreams = list
        else
            speakerStreams = list
    }

    function setStreamVolume(kind, id, value) {
        const pct = Math.max(0, Math.min(100, Math.round(value)))
        pendingStreamKind = kind
        pendingStreamId = id
        pendingStreamVolume = pct
        // See draggingStreamKind/draggingStreamId above: skip the
        // display-array echo while this exact row is mid-drag.
        if (draggingStreamKind !== kind || draggingStreamId !== id) {
            setStreamListFor(kind, streamListFor(kind).map(
                s => s.id === id ? Object.assign({}, s, { volume: pct }) : s))
        }
        settleStreamVolume.restart()
    }

    function setStreamMuted(kind, id, muted) {
        setStreamListFor(kind, streamListFor(kind).map(
            s => s.id === id ? Object.assign({}, s, { muted: muted }) : s))
        Quickshell.execDetached(["pactl",
            kind === "source-output" ? "set-source-output-mute" : "set-sink-input-mute",
            id, muted ? "1" : "0"])
    }

    Timer {
        id: settleStreamVolume
        interval: 80
        onTriggered: {
            if (streamVolumeAction.running)
                settleStreamVolume.restart()
            else
                streamVolumeAction.running = true
        }
    }

    Process {
        id: streamVolumeAction
        command: ["pactl",
            root.pendingStreamKind === "source-output" ? "set-source-output-volume" : "set-sink-input-volume",
            root.pendingStreamId, root.pendingStreamVolume + "%"]
    }

    // A JSON sink/source/sink-input/source-output entry, straight from
    // `pactl -f json`, isn't trusted to have every field this reads —
    // defused with `|| {}` / `?.` / fallbacks throughout rather than
    // wrapping the whole thing in one try/catch that'd silently drop
    // everything over one missing key.
    function firstVolumePercent(entry) {
        const vol = entry && entry.volume
        if (!vol || typeof vol !== "object")
            return 100
        for (const key in vol) {
            const pct = vol[key] && vol[key].value_percent
            if (typeof pct === "string") {
                const n = parseInt(pct, 10)
                if (!isNaN(n))
                    return n
            }
        }
        return 100
    }

    function applyAudioSnapshot(text) {
        const parts = text.split("___SPLIT___")
        const defSink = (parts[0] || "").trim()
        const defSource = (parts[1] || "").trim()

        function parseArray(json) {
            try {
                const v = JSON.parse((json || "").trim() || "[]")
                return Array.isArray(v) ? v : []
            } catch (e) {
                return []
            }
        }

        const rawSinks = parseArray(parts[2])
        const rawSources = parseArray(parts[3])
        const rawSinkInputs = parseArray(parts[4])
        const rawSourceOutputs = parseArray(parts[5])

        function deviceEntry(d, defName) {
            const name = d && d.name
            if (!name)
                return null
            const desc = d.description || (d.properties && d.properties["device.description"]) || name
            return { id: name, name: desc, active: name === defName }
        }

        const sinks = rawSinks.map(d => deviceEntry(d, defSink)).filter(Boolean)
        const sources = rawSources.map(d => deviceEntry(d, defSource))
            .filter(d => d && !/\.monitor$/.test(d.id))
        sinks.sort((a, b) => (b.active - a.active))
        sources.sort((a, b) => (b.active - a.active))
        speakerDevices = sinks
        microphoneDevices = sources

        function streamEntry(s) {
            if (typeof s.index === "undefined" || s.index === null)
                return null
            const props = s.properties || {}
            const name = props["application.name"] || props["media.name"] || "Unknown app"
            return {
                id: String(s.index),
                name: name,
                volume: firstVolumePercent(s),
                muted: !!s.mute,
                corked: !!s.corked
            }
        }

        // Same guard as setStreamVolume: while a row's being dragged,
        // leave its array alone rather than handing the mixer's
        // ListView a fresh reference (and thus a full rebuild) out
        // from under the held-down mouse. Covers a drag that outlasts
        // the 2s mixer-refresh interval; endStreamDrag reconciles the
        // moment the drag actually finishes.
        if (draggingStreamKind !== "sink-input")
            speakerStreams = rawSinkInputs.map(streamEntry).filter(Boolean)
        if (draggingStreamKind !== "source-output")
            microphoneStreams = rawSourceOutputs.map(streamEntry).filter(Boolean)
    }

    Process {
        id: audioSnapshotAction
        command: ["sh", "-c", root.audioSnapshotScript]
        stdout: StdioCollector {
            onStreamFinished: root.applyAudioSnapshot(text)
        }
        onExited: {
            root.audioDevicesScanning = false
            root.audioDevicesManualScanning = false
        }
    }

    Process {
        id: setDefaultSinkAction
        command: ["pactl", "set-default-sink", root.audioSetSinkId]
        onExited: {
            root.audioDeviceSelectingId = ""
            root.refreshSoon()
            root.scanAudioDevices()
        }
    }

    Process {
        id: setDefaultSourceAction
        command: ["pactl", "set-default-source", root.audioSetSourceId]
        onExited: {
            root.audioDeviceSelectingId = ""
            root.refreshSoon()
            root.scanAudioDevices()
        }
    }

    // While the mixer's open, poll faster than the panel's normal 3s —
    // apps opening/closing/changing volume out from under it is exactly
    // what a live mixer needs to catch, unlike the Wi-Fi/Bluetooth lists.
    Timer {
        id: audioMixerRefresh
        interval: 2000
        repeat: true
        running: root.active && root.audioMixerActive
        onTriggered: root.scanAudioDevices()
    }

    // Keep Awake: an idle inhibitor that lives exactly as long as this
    // process does. It is `idle` only, on purpose: that stops auto-lock,
    // screen-off and auto-suspend (hypridle and logind's idle action both
    // honour it), but it is NOT a `sleep` lock — a `sleep` block lock makes
    // `systemctl suspend` / `hibernate` fail for a normal user, which broke
    // the Power menu's Sleep and Hibernate while Keep Awake was on (and
    // would also have stopped the lid from suspending the laptop). systemd-inhibit hands the lock to the command it
    // runs, and that command polls its own parent (the shell) and exits
    // when it's gone — so closing or crashing the shell can't leave the
    // machine unable to sleep.
    //
    // Reloads: Quickshell reloading doesn't restart the Quickshell process,
    // so without the bookkeeping below a reload used to leave the tile
    // showing OFF while the old inhibitor could still be alive (or, if it
    // was torn down, leave you OFF when you'd had it ON). Now the choice is
    // saved by toggleKeepAwake(), and on every load the script below first
    // kills any leftover inhibitor, then — if the saved choice was ON —
    // starts a fresh one. Either way the tile shows what's really running.
    // The "sekaipop-keep-awake" comment in the command is the marker the
    // script finds leftovers by; keep the two in step.
    readonly property string keepAwakeScript: Directories.script("state/keep-awake-state.sh")

    Process {
        id: inhibitor
        command: ["systemd-inhibit", "--what=idle", "--who=sekaipop",
                  "--why=Keep Awake (Quick Panel)", "--mode=block",
                  "sh", "-c", "while kill -0 $PPID 2>/dev/null; do sleep 5; done # sekaipop-keep-awake"]
    }

    readonly property string tilesScript: Directories.script("state/qp-tiles-state.sh")

    // Runs once, at startup: the saved button layout. Nothing saved yet
    // keeps the default; a saved-but-empty panel is just "#v2" and "-".
    Process {
        running: true
        command: ["sh", root.tilesScript, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.trim() !== "")
                // Nothing saved yet, or saved by an older layout format
                // (no "#v2" first line): keep the default.
                if (lines.length === 0 || lines[0].trim() !== "#v2")
                    return
                const list = []
                let columns = QT.defaultColumns
                for (const line of lines.slice(1)) {
                    const parts = line.split("\t")
                    if (parts.length < 2)
                        continue
                    if (parts[0] === "@columns")
                        columns = QT.clampColumns(parseInt(parts[1], 10))
                    else
                        list.push({ id: parts[0], size: parts[1].trim() })
                }
                root.tileColumns = columns
                root.tiles = QT.sanitize(list, columns)
            }
        }
    }

    // Runs once, at startup: clear leftovers, then restore the saved state.
    Process {
        running: true
        command: ["sh", root.keepAwakeScript, "restore"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "on")
                    inhibitor.running = true
            }
        }
    }

    // ===== Power menu actions =====
    // Each systemctl call falls back to loginctl (the same two paths end4's
    // session menu tries), so if one of them isn't usable the other still
    // gets a go.
    function powerOff() {
        powerOffAction.running = true
    }

    function reboot() {
        rebootAction.running = true
    }

    function logout() {
        logoutAction.running = true
    }

    // Locks the screen with this shell's own lockscreen (Lockscreen.qml)
    // — nothing external to install or run.
    function lock() {
        LockState.lock()
    }

    // Sleep and Hibernate lock first, so the machine wakes up on the
    // lockscreen instead of an open desktop. LockState.lock() plays the
    // lock ring over the live desktop and only engages the session lock when
    // it finishes (phase "locked"), so the suspend has to wait for that —
    // suspending the moment the ring starts could freeze it half-way.
    //   pendingAfterLock   "sleep" / "hibernate" while waiting, else ""
    //   settleTimer        a beat after "locked" so the lock surface has
    //                      really been drawn before the screen goes away
    //   lockSafety         if the lock never engages, suspend anyway — a
    //                      button that silently does nothing is worse
    // Already locked: it just goes straight to sleep.
    property string pendingAfterLock: ""

    function sleep() {
        root.lockThen("sleep")
    }

    function hibernate() {
        root.lockThen("hibernate")
    }

    function lockThen(action) {
        if (LockState.phase === "locked") {
            root.pendingAfterLock = action
            settleTimer.restart()
            return
        }
        root.pendingAfterLock = action
        lockSafety.restart()
        LockState.lock()
    }

    function runPending() {
        const action = root.pendingAfterLock
        root.pendingAfterLock = ""
        settleTimer.stop()
        lockSafety.stop()
        if (action === "hibernate")
            hibernateAction.running = true
        else if (action === "sleep")
            sleepAction.running = true
    }

    Connections {
        target: LockState
        function onPhaseChanged() {
            if (root.pendingAfterLock !== "" && LockState.phase === "locked")
                settleTimer.restart()
        }
    }

    Timer {
        id: settleTimer
        interval: 400
        onTriggered: root.runPending()
    }

    Timer {
        id: lockSafety
        interval: LockState.ringMs + 3000
        onTriggered: root.runPending()
    }

    function firmwareReboot() {
        firmwareAction.running = true
    }

    function openSystemMonitor() {
        monitorAction.running = true
    }

    Process {
        id: powerOffAction
        command: ["sh", "-c", "systemctl poweroff || loginctl poweroff"]
    }

    Process {
        id: rebootAction
        command: ["sh", "-c", "systemctl reboot || loginctl reboot"]
    }

    Process {
        id: logoutAction
        // Asks every open window's program to quit, waits a moment, then
        // ends the Hyprland session (see the script for the details). Swap
        // the script's last line for your own compositor's equivalent if this
        // isn't running under Hyprland.
        command: ["sh", Directories.script("system/session-logout.sh")]
    }

    Process {
        id: sleepAction
        command: ["sh", "-c", "systemctl suspend || loginctl suspend"]
    }

    Process {
        id: hibernateAction
        command: ["sh", "-c", "systemctl hibernate || loginctl hibernate"]
    }

    Process {
        id: firmwareAction
        // Reboots straight into the UEFI/BIOS setup screen, on hardware
        // that supports it.
        command: ["sh", "-c",
            "systemctl reboot --firmware-setup || loginctl reboot --firmware-setup"]
    }

    Process {
        id: monitorAction
        // Tries a few common system monitors in order; replace with
        // whichever one you actually use.
        command: ["sh", "-c",
            "exec gnome-system-monitor 2>/dev/null || " +
            "exec plasma-systemmonitor 2>/dev/null || " +
            "exec \"$TERMINAL\" -e btop 2>/dev/null || " +
            "exec \"$TERMINAL\" -e htop"]
    }
}
