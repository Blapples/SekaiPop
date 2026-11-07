import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode
import qs.modules.sekai.desktopWidgets

// The desktop audio visualizer. It sits on the desktop, under your windows,
// over the wallpaper, like the clock, and it is the same kind of card as the
// clock (move it in Edit Desktop; pops in and is swallowed on the way out).
//
// What it draws is SekaiVisualizer.qml: a pocket player whose screen is a sheet
// of keycaps with the album cover printed on it. The music presses the keys
// instead of lighting them (kick, snare, hats, bass notes and the singer's voice
// each push the sheet their own way, and the dents run out as ripples), a new
// track re-keys the sheet from the middle out, and the deck under the screen has
// previous / play / next keycaps and a lane to seek on. Plain QML, no shader.
//
// The card is there while something is playing, and (Settings -> Desktop ->
// "Visualizer: stay when paused", on by default) while a player is paused, so
// you can press play on it. It swallows itself when the player is gone and the
// music has stopped. Listening costs nothing while paused: the audio tap only
// runs while audio is playing.
//
// The audio tap is the note analyzer (scripts/cava/sekai_analyzer.py: python3 + numpy
// + parec), which says which hits are kicks, snares, hats and bass notes and
// when a clear lead tone (the voice) is held; if it can't start, or is switched
// off, `cava` (scripts/cava/cava-sekai.conf) is used and the notes are guessed from
// its bands. The tap runs only while a
// media player (MPRIS) is playing, unless "Listen to all audio" is on
// (VisualizerService.alwaysListen), and never in Edit Desktop (a demo song
// plays there instead, so the card and its picture on the shelf show something).
//
//   on the card   (when Lock widgets is on, the default)
//                 press / drag the keys   they go down under your finger
//                 double-click the keys   play / pause
//                 right / middle click    next / previous track
//                 wheel over the keys     the player's volume
//                 the deck's keys, the lane (drag to seek)
//                 With Lock widgets off the card is for dragging instead.
//   edit mode     select the card in Edit Desktop (left click it): a small
//                 button pops up at the top-right corner and goes to the next
//                 size (S / M / L / XL). There is no such button on the normal
//                 desktop.
//
// Styles (VisualizerService.style): besides the Sekai keycap card, this widget can draw
// "tide" (sekaipop's own: three sheets of cut paper, TideVisualizer.qml) and the
// visualizers of end4-pC, ported over: "bars" (plain QML), "aurora", "dots", "mirror"
// (a band across the bottom of the screen, GPU shaders) and "ring" (round, movable like
// the card, with the cover in the middle). They are fed by cava (scripts/cava/cava-pc.conf,
// 50 bands) through ShaderVisualizerEngine.qml and drawn by ShaderVisualizerLayer.qml
// (shaders/visualizer/*.frag.qsb, end4's compiled shaders). They have no keys, deck or
// notes, so they show only while audio plays, and a band does not take clicks. The size
// (S / M / L / XL) is the band's height or the ring's diameter. Switch the style in
// Settings -> Desktop, from the style button on the card in Edit Desktop, or with
// `qs -c sekaipop ipc call visualizer style aurora`.
//
// State (position, shown, size, colors, sensitivity) lives in
// services/VisualizerService.qml and is remembered across restarts.
//
// How the moving works: exactly like ClockWidget.qml. ONE full-screen,
// transparent window on WlrLayer.Background (see `WlrLayershell.layer` below), with the card as an Item inside it.
// Its input `mask` is only the card, and only while it can be moved (Edit
// Desktop, or Lock widgets off); everywhere else, and always on the normal
// locked desktop, every click passes straight through.
//
//   qs -c sekaipop ipc call visualizer toggle          (show / hide)
//   qs -c sekaipop ipc call visualizer colors 0        (0 the cover, 1 the five card attributes, 2 the theme's accents)
//   qs -c sekaipop ipc call visualizer nextSize        (S -> M -> L -> XL)
//   qs -c sekaipop ipc call visualizer vertical true   (a band up the side of the screen instead of along the bottom)
//   qs -c sekaipop ipc call visualizer setSize 3
//   qs -c sekaipop ipc call visualizer stayPaused true (keep the card while a player is paused)
//   qs -c sekaipop ipc call visualizer sensitivity 1.5 (0.5 .. 2.5)
//   qs -c sekaipop ipc call visualizer listenAll true  (listen even without a media player)
//   qs -c sekaipop ipc call visualizer aubio true|false (analyzer: python-aubio pitch + beat tracker, or built-in numpy)
//   qs -c sekaipop ipc call visualizer analyzer false  (cava + band guessing instead of the note analyzer)
//   qs -c sekaipop ipc call visualizer resetPosition   (if it ever ends up off-screen)

PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    function resetPosition(): void {
        VisualizerService.posX = -1;
        VisualizerService.posY = -1;
        VisualizerService.bandY = -1;
        VisualizerService.bandX = -1;
        win.place();
        VisualizerService.setPosition(card.x, card.y, win.screen ? win.screen.name : "", win.uiScale);
    }
    // Which monitor it lives on, by name (`hyprctl monitors`), e.g. "DP-1".
    // Empty = the monitor the card was last dropped on (remembered in
    // VisualizerService), or the first screen if it has never been moved.
    property string monitor: ""

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : VisualizerService.screenName
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's scale (scale.json / services/ShellScale.qml). The card is
    // drawn in design pixels inside a ScaleHost, so `roomW` x `roomH` is the
    // screen as the card sees it (real size / scale).
    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real fullW: win.screen ? win.screen.width : 0
    readonly property real fullH: win.screen ? win.screen.height : 0
    readonly property real roomW: win.fullW / win.uiScale
    readonly property real roomH: win.fullH / win.uiScale

    // ===== a small window while nothing needs the whole screen =====
    // A full-screen layer makes the compositor redraw (and re-blend) the whole screen on every
    // frame the card draws. So at rest the window is just the card plus some room around it for the
    // pop-in overshoot and the name tag, and only Edit Desktop (and dragging on an unlocked desktop)
    // gets the full screen back. Everything inside still lives in screen coordinates: `shifter`
    // slides the whole stage by the window's own position, so the card is drawn where it always was.
    readonly property bool compact: !EditMode.active && !win.gliding && EditMode.screenName === ""
        && EditMode.compactWindows && !EditMode.desktopDragAllowed && win.fullW > 0 && win.placed
    readonly property real boxPad: Math.ceil((0.12 * Math.max(card.width, card.height) + 16) * win.uiScale)
    readonly property real boxX: win.compact ? Math.max(0, Math.floor(card.x * win.uiScale - win.boxPad)) : 0
    readonly property real boxY: win.compact ? Math.max(0, Math.floor(card.y * win.uiScale - win.boxPad)) : 0
    readonly property real boxW: Math.max(1, Math.min(win.fullW,
        Math.ceil((card.x + card.width) * win.uiScale + win.boxPad)) - win.boxX)
    readonly property real boxH: Math.max(1, Math.min(win.fullH,
        Math.ceil((card.y + card.height) * win.uiScale + win.boxPad)) - win.boxY)

    // On / off: pop in with a little overshoot, swallowed on the way out (the
    // same two fixed animations as ClockWidget.qml; see the reasoning there).
    //
    // `switchedOn` is "the widget is switched on" (it listens for audio); `want` is
    // "the card is on screen": while the music plays or has only just stopped,
    // while a player is paused (if you asked for that), and always in Edit Desktop.
    readonly property bool switchedOn: VisualizerService.shown && VisualizerService.loaded

    // Desktop Focus Mode (desktopWidgets/FocusGate.qml, services/FocusService.qml).
    // `gate.show` false = the card is away: `want` goes false, so it is swallowed and
    // the window unmapped, and everything drawn (the shader trees, the key bed) is torn
    // down or idle because it hangs off `live`. What happens to the AUDIO is a separate
    // question (`wantAudio`): it stops while hidden unless the visualizer is allowed to
    // listen in the background (Settings -> Desktop Focus Mode).
    FocusGate {
        id: gate
        widgetId: "visualizer"
        screenName: win.screen ? win.screen.name : ""
    }
    // Which look (see the header): the Sekai card, or one of end4-pC's.
    readonly property string style: VisualizerService.style
    readonly property bool isSekai: VisualizerService.isSekai
    readonly property bool isRing: VisualizerService.isRing
    readonly property bool isBand: VisualizerService.isBand
    readonly property bool vertical: VisualizerService.isBand && VisualizerService.vertical
    readonly property bool want: win.switchedOn && gate.show && (win.isSekai
        ? (levelEngine.fade > 0.05 || (VisualizerService.stayWhenPaused && media.present) || EditMode.active)
        : (pcEngine.fade > 0.05 || EditMode.active))
    property real reveal: 0
    // `armed` is only the pop animation's switch: false until 800 ms after load,
    // so the first state is set without playing the pop in / swallow.
    property bool armed: false
    property bool placed: false

    onWantChanged: {
        if (!win.armed) {
            popIn.stop()
            swallow.stop()
            win.reveal = win.want ? 1 : 0
        } else if (win.want) {
            swallow.stop()
            popIn.restart()
        } else {
            popIn.stop()
            swallow.restart()
        }
    }

    NumberAnimation {
        id: popIn
        target: win
        property: "reveal"
        to: 1
        duration: 460
        easing.type: Easing.OutBack
        easing.overshoot: 1.9
    }

    NumberAnimation {
        id: swallow
        target: win
        property: "reveal"
        to: 0
        duration: 300
        easing.type: Easing.InCubic
    }

    Timer {
        interval: 800
        running: VisualizerService.loaded
        onTriggered: win.armed = true
    }

    readonly property bool live: win.want || win.reveal > 0.001

    // This window maps later than the other widgets (it needs music), and on the shared Background
    // layer the newest one is in front. When it maps, ask for a restack: it goes back down first,
    // the other widgets after it, so it ends up behind them (see WallpaperService.restackWidgets).
    Timer {
        id: stackFix
        interval: 120
        onTriggered: WallpaperService.restackWidgets()
    }

    // Not mapped while the widget is off: a full-screen transparent layer that is only
    // sitting there still costs the compositor a blend, and anything animating inside it
    // (the seek bar glide, the position poll) kept a full-screen frame going all the time.
    visible: VisualizerService.loaded && (win.live || EditMode.active)

    // Always the lowest layer that still shows over the wallpaper: Background, the wallpaper's
    // own layer, mapped after it (this window is only mapped while the visualizer is on, so
    // it is newer than the wallpaper and the compositor draws it over it). The dock (Bottom
    // or Top), the bar (Top) and every window are above it for good. The clock / to-do /
    // user / weather cards are on Background too (so the dock is always in front of them),
    // which means between them and this card the later one mapped is in front. It does not
    // go up while it is edited or moved (EditChrome.raised) like the other widgets do.
    WlrLayershell.layer: WallpaperService.restackingLow ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-visualizer"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        left: true
        right: !win.compact
        bottom: !win.compact
    }

    margins {
        left: win.boxX
        top: win.boxY
    }

    implicitWidth: win.boxW
    implicitHeight: win.boxH

    // Only the card takes clicks, and only while it can be moved; the rest of
    // the screen falls through. The hover buttons sit half outside the card's
    // corner, so they get their own rectangle.
    mask: Region {
        item: cardMask

        Region { item: btnMask }
    }

    readonly property bool grabbable: stage.editing || EditMode.desktopDragAllowed

    Item {
        id: cardMask
        readonly property real m: stage.editing ? 38 : 0
        readonly property real k: win.uiScale * stage.scale
        readonly property real x1: shifter.x + stage.x + (card.x + card.width + m) * k
        readonly property real y1: shifter.y + stage.y + (card.y + card.height + m) * k
        // The Sekai card has keys to press, so it always takes clicks; the end4 styles
        // only while they can be moved (a band across the screen must not eat clicks).
        readonly property bool open: win.live && (win.isSekai || win.grabbable)
        x: !cardMask.open ? 0 : Math.max(0, Math.round(shifter.x + stage.x + (card.x - m) * k))
        y: !cardMask.open ? 0 : Math.max(0, Math.round(shifter.y + stage.y + (card.y - m) * k))
        width: !cardMask.open ? 1 : Math.max(0, Math.ceil(x1) - x)
        height: !cardMask.open ? 1 : Math.max(0, Math.ceil(y1) - y)
    }

    Item {
        id: btnMask
        readonly property real k: win.uiScale * stage.scale
        x: Math.max(0, Math.round(shifter.x + stage.x + (card.x + btnRow.x) * k))
        y: Math.max(0, Math.round(shifter.y + stage.y + (card.y + btnRow.y) * k))
        width: card.btnShown && win.live ? Math.ceil(btnRow.width * k) : 0
        height: card.btnShown && win.live ? Math.ceil(btnRow.height * k) : 0
    }

    // ===== the player =====
    MediaSource {
        id: media
    }

    // ===== the audio =====
    readonly property bool anyPlaying: {
        const list = Mpris.players.values
        for (let i = 0; i < list.length; i++) {
            if (list[i].playbackState === MprisPlaybackState.Playing)
                return true
        }
        return false
    }

    readonly property string cavaConf: Directories.script("cava/cava-sekai.conf")

    readonly property string analyzerScript: Directories.script("cava/sekai_analyzer.py")

    // The note analyzer (scripts/cava/sekai_analyzer.py) is the audio tap unless it
    // is switched off in settings or it could not start (no python3 / numpy /
    // parec): then cava is used, as before.
    property bool analyzerFailed: false
    readonly property bool useAnalyzer: win.isSekai && VisualizerService.analyzer && !win.analyzerFailed
    readonly property bool wantAudio: win.switchedOn && !EditMode.active
        && (VisualizerService.alwaysListen || win.anyPlaying)
        && (gate.show || FocusService.visualizerKeepsListening || audioHold.running)

    // Desktop Focus Mode: the audio tap is not stopped the moment the widgets go away, only after
    // a minute of staying away. Starting a capture of the output (parec / pw-record) makes
    // PipeWire re-plan the graph (the capture asks for a short buffer, so the quantum can drop for
    // everyone), and stopping it plans again; that is the half-second dropout in the music when
    // going between an app and an empty workspace, because the tap started / stopped on every
    // such switch. With the hold, going back and forth keeps the same capture running.
    // (Settings -> Desktop -> Desktop Focus Mode -> Visualizer in background keeps it for good.)
    Timer {
        id: audioHold
        interval: 60000
    }

    Connections {
        target: gate
        function onShowChanged() {
            if (gate.show)
                audioHold.stop()
            else
                audioHold.restart()
        }
    }

    Connections {
        target: VisualizerService
        function onAnalyzerChanged() {
            win.analyzerFailed = false
        }
    }

    // Switching the engine restarts the analyzer: stop it for a moment.
    Connections {
        target: VisualizerService
        function onUseAubioChanged() {
            win.analyzerFailed = false
            analyzerProc.running = false
            engineRestart.restart()
        }
    }

    Timer {
        id: engineRestart
        interval: 300
        onTriggered: analyzerProc.running = Qt.binding(() => win.wantAudio && win.useAnalyzer)
    }

    // One JSON line per frame, 60 a second (the format is in sekai_analyzer.py).
    Process {
        id: analyzerProc
        running: win.wantAudio && win.useAnalyzer
        command: ["nice", "-n", "5", "python3", win.analyzerScript, "--engine", VisualizerService.useAubio ? "auto" : "numpy"]

        property double startedAt: 0

        stdout: SplitParser {
            onRead: data => {
                let f = null
                try {
                    f = JSON.parse(data)
                } catch (e) {
                    return
                }
                levelEngine.feed(f)
            }
        }

        // What the analyzer says about itself ("engine aubio 0.4.9", or why it fell back)
        stderr: SplitParser {
            onRead: data => console.warn("VisualizerWidget: " + data)
        }

        onRunningChanged: {
            if (analyzerProc.running) {
                analyzerProc.startedAt = Date.now()
            } else {
                levelEngine.raw = []
            }
        }

        // A failure right at the start means it can't work here: use cava.
        onExited: (code, status) => {
            // 1 python error (no numpy), 3 no parec / pw-record, 4 the capture gave
            // nothing, 127 no python3. A stop by the shell is none of these.
            if ((code === 1 || code === 3 || code === 4 || code === 127)
                    && Date.now() - analyzerProc.startedAt < 8000) {
                console.warn("VisualizerWidget: the note analyzer did not start (exit " + code
                    + "), using cava instead. It needs python3 with numpy, and parec or pw-record.")
                win.analyzerFailed = true
            }
        }
    }

    // One cava line -> the list of numbers in it, in a single pass (the old split / map /
    // filter built three arrays per frame, up to 60 frames a second). Same numbers out:
    // anything that is not a number (the empty piece after the last ";") is dropped.
    function parseBands(line) {
        const parts = line.split(";")
        const out = []
        for (let i = 0; i < parts.length; i++) {
            const v = parseFloat(parts[i])
            if (!isNaN(v))
                out.push(v)
        }
        return out
    }

    // cava prints one line per frame: "v0;v1;...;v23;". Same parsing as end4's.
    Process {
        id: cava
        running: win.wantAudio && win.isSekai && !win.useAnalyzer
        command: ["setpriv", "--pdeathsig", "TERM", "nice", "-n", "5", "cava", "-p", win.cavaConf]

        stdout: SplitParser {
            onRead: data => levelEngine.raw = win.parseBands(data)
        }

        onRunningChanged: {
            if (!cava.running)
                levelEngine.raw = []
        }
    }

    // The end4 styles' tap: cava with 50 bands (scripts/cava/cava-pc.conf), the same as end4-pC's.
    // It is the bar pill's tap too (services/PcCavaService.qml), so this widget does not start a
    // cava of its own any more: it adds itself to the service's demand count while it wants audio
    // (the same conditions as before: `wantAudio` and a non-Sekai style) and reads the bands
    // from `PcCavaService.raw`. `counted` keeps the add / remove idempotent in any order of
    // signals, and the destruction handler gives the count back if the widget is unloaded
    // (Desktop Focus unload, Game Mode, lock) while it still wants audio.
    QtObject {
        id: tapDemand

        property bool counted: false
        readonly property bool want: win.wantAudio && !win.isSekai

        onWantChanged: tapDemand.sync()

        function sync() {
            if (tapDemand.want === tapDemand.counted)
                return
            tapDemand.counted = tapDemand.want
            PcCavaService.demand(tapDemand.want ? 1 : -1)
        }

        Component.onCompleted: tapDemand.sync()
        Component.onDestruction: {
            if (tapDemand.counted) {
                tapDemand.counted = false
                PcCavaService.demand(-1)
            }
        }
    }

    ShaderVisualizerEngine {
        id: pcEngine
        raw: tapDemand.want ? PcCavaService.raw : []
        active: !win.isSekai && (win.switchedOn || EditMode.active)
        demo: !win.isSekai && EditMode.active
        sensitivity: VisualizerService.sensitivity
        frameGap: gate.dimmed ? 0.1 : (VisualizerService.perf >= 2 ? 0.05 : (VisualizerService.perf === 1 ? 0.028 : 0))
    }

    // The cover (for the ring, and for the cover colours), and the colours of the shapes.
    VisualizerCover {
        id: cover
        artUrl: media.artUrl
        enabled: !win.isSekai && (win.isRing || VisualizerService.colorMode === 0)
    }

    readonly property color neutralInk: mt.dark ? Qt.color("#ffffff") : Qt.color(mt.colBorder)

    // [color1, color2, color3]: the two of the shape, then the accent (peaks, the ring's
    // fallback). The same roles as end4's palettes, from this theme's colours.
    readonly property var themePalette: {
        const A = mt.accentCyan, B = mt.accentMint, P = mt.irisColorPink
        switch (win.style) {
            case "ring": return [A, B, Qt.lighter(A, 1.25)]
            case "dots": return [win.neutralInk, A, P]
            default: return [A, B, P]
        }
    }

    // The five card attributes (Cool, Cute, Happy, Mysterious, Pure).
    readonly property var attrPalette: {
        const a = mt.attributeColors
        switch (win.style) {
            case "dots": return [win.neutralInk, Qt.color(a[1]), Qt.color(a[2])]
            case "bars":
            case "mirror": return [Qt.color(a[0]), Qt.color(a[3]), Qt.color(a[1])]
            default: return [Qt.color(a[0]), Qt.color(a[1]), Qt.color(a[3])]
        }
    }

    readonly property var shapeColors: {
        const mode = VisualizerService.colorMode
        if (mode === 2) return win.themePalette
        if (mode === 0 && cover.palette) {
            const c = cover.palette
            return win.style === "dots" ? [win.neutralInk, c[0], c[1]] : c
        }
        return win.attrPalette
    }

    VisualizerEngine {
        id: levelEngine
        active: win.isSekai && (win.switchedOn || EditMode.active)
        // In Edit Desktop a made-up song plays so the card (and the shelf's
        // picture of it) isn't empty.
        demo: win.isSekai && EditMode.active
        analyzer: win.useAnalyzer
        sensitivity: VisualizerService.sensitivity
        // Listening in the background with nothing on screen: the engine keeps its tempo
        // and levels warm but does not need 60 updates a second.
        frameGap: gate.dimmed ? Math.max(0.1, VisualizerService.frameGap) : VisualizerService.frameGap
    }

    // ===== placement =====
    // A vertical band faces the screen edge it is nearest to (its base on that edge). A horizontal
    // band does the same: in the top half of the screen it hangs from the top edge, upside down
    // (its base on the top edge, the bars growing down). It is only decided when the card is placed
    // or dropped, so it does not flip while it is dragged.
    function updateSide(): void {
        card.leftSide = win.vertical && (card.x + card.width / 2) < win.roomW / 2
        card.topSide = win.isBand && !win.vertical && (card.y + card.height / 2) < win.roomH / 2
    }

    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        if (!force && (!VisualizerService.loaded || win.roomW < card.width || win.roomH < card.height))
            return
        if (VisualizerService.isBand) {
            // A band spans the screen: along the bottom (y is the bottom unless it was dragged), or, when
            // vertical, up the right edge (x is the right edge unless it was dragged).
            const vert = VisualizerService.vertical
            let b = vert ? VisualizerService.bandX : VisualizerService.bandY
            if (b >= 0 && VisualizerService.posScale > 0 && win.uiScale > 0)
                b *= VisualizerService.posScale / win.uiScale
            if (vert) {
                card.y = 0
                card.x = b < 0 ? Math.max(0, win.roomW - card.width)
                               : Math.max(0, Math.min(b, win.roomW - card.width))
            } else {
                card.x = 0
                card.y = b < 0 ? Math.max(0, win.roomH - card.height)
                               : Math.max(0, Math.min(b, win.roomH - card.height))
            }
            win.updateSide()
            win.placed = true
            return
        }
        let x = VisualizerService.posX
        let y = VisualizerService.posY
        if (x < 0 || y < 0) {
            x = (win.roomW - card.width) / 2
            y = win.roomH - card.height - 90
        } else if (VisualizerService.posScale > 0 && win.uiScale > 0) {
            const k = VisualizerService.posScale / win.uiScale
            x *= k
            y *= k
        }
        card.x = Math.max(0, Math.min(x, win.roomW - card.width))
        card.y = Math.max(0, Math.min(y, win.roomH - card.height))
        win.placed = true
    }

    Timer {
        id: settle
        interval: 300
        onTriggered: {
            if (VisualizerService.loaded && VisualizerService.posX >= 0 && VisualizerService.posScale <= 0 && !dragArea.drag.active) {
                VisualizerService.posScale = win.uiScale
                VisualizerService.persist()
            }
            if (!chrome.dragging && !dragArea.drag.active)
                win.place(!win.placed && VisualizerService.loaded)
        }
    }

    onWidthChanged: { win.place(); settle.restart() }
    onHeightChanged: { win.place(); settle.restart() }
    onUiScaleChanged: { win.place(); settle.restart() }
    onScreenChanged: { win.place(); settle.restart() }
    onVisibleChanged: { settle.restart(); if (win.visible) stackFix.restart() }
    Component.onCompleted: {
        if (win.visible) stackFix.restart()
        win.reveal = win.want ? 1 : 0
        win.place()
    }

    Connections {
        target: VisualizerService
        function onLoadedChanged() {
            win.place()
            settle.restart()
        }
        // A desktop preset hands the service another saved spot while the card
        // is on screen. Without this the card only looked at the service when
        // it loaded or when the window / scale / monitor changed, so wearing a
        // preset moved nothing. The spot arrives as several properties one
        // after the other (x, y, scale), so wait a beat and place once.
        function onPosXChanged() { follow.restart() }
        function onPosYChanged() { follow.restart() }
        function onPosScaleChanged() { follow.restart() }
        function onBandYChanged() { follow.restart() }
        function onBandXChanged() { follow.restart() }
        function onVerticalChanged() { follow.restart() }
        function onIsBandChanged() { follow.restart() }
    }

    // A preset hands the card another spot: it glides there instead of jumping
    // (not while it is being dragged, and not when it is already where it
    // should be, which is what dropping it by hand and the scale check come to).
    // `gliding` first, so a small window grows to the whole screen (see
    // `compact`), then `glideOn` switches the card's Behaviors on.
    property bool gliding: false
    property bool glideOn: false

    Timer {
        id: follow
        interval: 16
        onTriggered: {
            if (chrome.dragging || dragArea.drag.active)
                return
            const ox = card.x
            const oy = card.y
            win.place()
            if (Math.abs(card.x - ox) + Math.abs(card.y - oy) < 2)
                return
            card.x = ox
            card.y = oy
            win.gliding = true
            glideStart.restart()
        }
    }

    Timer {
        id: glideStart
        interval: 80
        onTriggered: {
            win.glideOn = true
            win.place()
            glideEnd.restart()
        }
    }

    // A preset changes this card's variant or switches it off: it shrinks away, the
    // preset goes on, and the new variant pops back in (see PresetMotion.qml).
    // 1 = in place, 0 = away. Two fixed animations started from the flag, not one Behavior (see
    // `reveal`).
    property real swapK: 1
    NumberAnimation {
        id: swapOut
        target: win
        property: "swapK"
        to: 0
        duration: PresetMotion.outMs
        easing.type: Easing.InCubic
    }
    NumberAnimation {
        id: swapIn
        target: win
        property: "swapK"
        to: 1
        duration: PresetMotion.inMs
        easing.type: Easing.OutBack
        easing.overshoot: 1.4
    }
    Connections {
        target: PresetMotion
        function onVisualizerOutChanged() {
            if (PresetMotion.visualizerOut) {
                swapIn.stop()
                swapOut.restart()
            } else if (win.want) {
                swapOut.stop()
                swapIn.restart()
            } else {
                // Switched off: stays away until the swallow is over, or the card
                // would come back for a moment while it is still being swallowed.
                swapOut.stop()
                swapRest.restart()
            }
        }
    }
    Timer {
        id: swapRest
        interval: 420
        onTriggered: win.swapK = 1
    }
    Connections {
        target: win
        function onWantChanged() {
            if (win.want && swapRest.running) {
                swapRest.stop()
                win.swapK = 1
            }
        }
    }

    Timer {
        id: glideEnd
        interval: 640
        onTriggered: {
            win.glideOn = false
            win.gliding = false
                bumpAnim.restart()
        }
    }

    // The shelf's picture of the card, taken every second while Edit Desktop is
    // on (EditPreview.qml).
    EditPreview {
        widgetId: "visualizer"
        target: card
        pixelRatio: win.uiScale
    }


    // The little button on the card's corner.
    component CornerButton: Item {
        id: cb

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string icon: "style"
        property bool shown: false
        signal clicked()

        width: 30
        height: 34

        Pill {
            anchors.fill: parent
            cornerRadius: 10
            ringWidth: 3
            pressed: area.pressed
            fillGradient: Gradient {
                GradientStop { position: 0.0; color: mt.accentMint }
                GradientStop { position: 1.0; color: mt.accentCyan }
            }

            MaterialIcon {
                anchors.centerIn: parent
                name: cb.icon
                size: 18
                weight: 600
                color: mt.colBorder
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            // An invisible button must not eat clicks meant for the card.
            enabled: cb.shown
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }

    // ===== Edit Desktop =====
    Item {
        id: shifter
        x: -win.boxX
        y: -win.boxY
        width: win.fullW
        height: win.fullH

        // ===========================================================================
        // Edit Desktop shrinks every desktop window into the same card with the same
        // transform (EditStage.qml / services/EditMode.qml). Out of edit mode this is
        // a no-op: scale 1, no offset.
        EditStage {
            id: stage
            screenObj: win.screen
            uiScale: win.uiScale

            ScaleHost {
                anchors.fill: parent
                factor: win.uiScale

                Item {
                    id: card

                    // Gliding to a preset's spot (win.glideOn, see `follow`). Off the rest of the time,
                    // so dragging and placing are exact.
                    Behavior on x {
                        enabled: win.glideOn
                        NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                    }
                    Behavior on y {
                        enabled: win.glideOn
                        NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                    }

                    // Keeps the classic (white) look in the first dark mode; see Theme.classicFor.
                    readonly property bool classicPanel: true

                    readonly property var sizeNames: ["S", "M", "L", "XL"]
                    // width x height in design pixels. M is the clock's card (2 x 2).
                    readonly property var sizes: [[264, 236], [320, 276], [420, 350], [520, 430]]
                    readonly property var sizePair: card.sizes[VisualizerService.sizeIndex] ?? card.sizes[1]

                    // The end4 styles: the ring is square, a band spans the screen.
                    readonly property var ringSizes: [260, 340, 420, 520]
                    readonly property var bandHeights: [180, 240, 300, 380]
                    readonly property real styleSize: VisualizerService.isRing
                        ? (card.ringSizes[VisualizerService.sizeIndex] ?? 340)
                        : (card.bandHeights[VisualizerService.sizeIndex] ?? 240)

                    width: win.isSekai ? card.sizePair[0] : (win.isBand && !win.vertical ? win.roomW : card.styleSize)
                    height: win.isSekai ? card.sizePair[1] : (win.vertical ? win.roomH : card.styleSize)
                    // A vertical band: true when it sits against the left edge (see win.updateSide)
                    property bool leftSide: false
                    // A horizontal band: true when it sits in the top half of the screen (turned upside down)
                    property bool topSide: false

                    // Drop-and-settle bounce when the size changes.
                    property real bump: 1
                    // A band fades instead of popping (it spans the screen).
                    scale: win.isBand ? 1 : card.bump * Math.max(0, win.reveal) * (win.placed ? 1 : 0) * (0.7 + 0.3 * Math.max(0, win.swapK))
                    opacity: (win.isBand ? Math.max(0, Math.min(1, win.reveal)) * (win.placed ? 1 : 0) : 1) * Math.max(0, Math.min(1, win.swapK))
                    transformOrigin: Item.Center

                    SequentialAnimation {
                        id: bumpAnim
                        NumberAnimation { target: card; property: "bump"; to: 1.035; duration: 90; easing.type: Easing.OutQuad }
                        NumberAnimation { target: card; property: "bump"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
                    }

                    // A new size is a new rectangle: keep the card on screen (not
                    // while it is being dragged: then the drag owns the position).
                    onWidthChanged: {
                        if (!chrome.dragging && !dragArea.drag.active)
                            win.place()
                    }

                    onHeightChanged: {
                        if (!chrome.dragging && !dragArea.drag.active)
                            win.place()
                    }

                    Connections {
                        target: VisualizerService

                        function onSizeIndexChanged() {
                            if (VisualizerService.loaded) {
                                card.chipText = "SIZE  ·  " + card.sizeNames[VisualizerService.sizeIndex]
                                bumpAnim.restart()
                                labelTimer.restart()
                            }
                        }

                        function onVerticalChanged() {
                            if (VisualizerService.loaded) {
                                card.chipText = "DIRECTION  ·  " + (VisualizerService.vertical ? "VERTICAL" : "HORIZONTAL")
                                labelTimer.restart()
                                win.place()
                            }
                        }

                        function onStyleChanged() {
                            if (VisualizerService.loaded) {
                                card.chipText = "STYLE  ·  " + VisualizerService.style.toUpperCase()
                                bumpAnim.restart()
                                labelTimer.restart()
                                win.place()
                            }
                        }
                    }

                    // The key-bed, deck and tag (SekaiVisualizer.qml). Pressing it is for
                    // the locked desktop; unlocked (or in Edit Desktop) the card is for moving.
                    SekaiVisualizer {
                        anchors.fill: parent
                        visible: win.isSekai
                        active: win.live && win.isSekai
                        engine: levelEngine
                        media: media
                        interactive: !win.grabbable
                    }

                    // The end4-pC styles (see the header). A vertical band is drawn as a normal band and turned on
                    // its side: the base ends up on the screen edge and the bass at the bottom, on either edge.
                    Item {
                        id: rotor
                        anchors.centerIn: parent
                        width: win.vertical ? card.height : card.width
                        height: win.vertical ? card.width : card.height
                        rotation: win.vertical ? (card.leftSide ? 90 : -90) : 0

                        Item {
                            id: flip
                            anchors.fill: parent
                            transform: Scale {
                                origin.x: flip.width / 2
                                origin.y: flip.height / 2
                                xScale: win.vertical && card.leftSide ? -1 : 1
                                yScale: win.isBand && !win.vertical && card.topSide ? -1 : 1
                            }

                            Loader {
                                anchors.fill: parent
                                active: !win.isSekai && win.live
                                sourceComponent: Item {
                                    // Ring: the cover is drawn into a texture so the shader gets it already cropped.
                                    Item {
                                        id: coverItem
                                        width: 512
                                        height: 512
                                        visible: win.isRing
                                        Image {
                                            anchors.fill: parent
                                            id: coverImage
                                            source: win.isRing ? cover.coverUrl : ""
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize: Qt.size(512, 512)
                                            asynchronous: true
                                            smooth: true
                                        }
                                    }
                                    ShaderEffectSource {
                                        id: coverTexture
                                        sourceItem: coverItem
                                        hideSource: true
                                        visible: false
                                    }

                                    Loader {
                                        anchors.fill: parent
                                        active: win.style === "bars"
                                        sourceComponent: ShaderBarsVisualizer {
                                            anchors.fill: parent
                                            points: pcEngine.raw
                                            fullWidth: rotor.width
                                            color1: win.shapeColors[0]
                                            color2: win.shapeColors[1]
                                        }
                                    }

                                    // sekaipop's own (TideVisualizer.qml)
                                    Loader {
                                        anchors.fill: parent
                                        active: win.style === "tide"
                                        sourceComponent: TideVisualizer {
                                            anchors.fill: parent
                                            engine: pcEngine
                                            color1: win.shapeColors[0]
                                            color2: win.shapeColors[1]
                                            color3: win.shapeColors[2]
                                            ink: mt.colBorder
                                            lite: VisualizerService.perf >= 2
                                        }
                                    }

                                    // (bars is plain QML and tide has its own shader above; the rest are end4-pC's shaders plus sekaipop's ribbons, scope and pulse.
                                    // The Sekai card has no shader: loading one for it asked for a sekai.frag.qsb that doesn't exist.)
                                    Loader {
                                        anchors.fill: parent
                                        active: win.style !== "bars" && win.style !== "tide" && win.style !== "sekai"
                                        sourceComponent: ShaderVisualizerLayer {
                                            anchors.fill: parent
                                            style: win.style
                                            engine: pcEngine
                                            ink: mt.colBorder
                                            color1: win.shapeColors[0]
                                            color2: win.shapeColors[1]
                                            color3: win.shapeColors[2]
                                            cover: coverTexture
                                            hasCover: coverImage.status === Image.Ready ? 1 : 0
                                            lite: VisualizerService.perf >= 2 ? 1 : 0
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Edit Desktop: outline, corner diamonds, a tag and a drag
                    // shield (EditChrome.qml). Draws nothing outside the mode.
                    EditChrome {
                        id: chrome
                        widgetId: "visualizer"
                        target: card
                        roomW: win.roomW
                        roomH: win.roomH
                        screenName: win.screen ? win.screen.name : ""
                        onMoved: {
                            win.updateSide()
                            VisualizerService.setPosition(card.x, card.y, win.screen ? win.screen.name : "", win.uiScale)
                        }
                        onRemoveRequested: VisualizerService.setShown(false)
                    }

                    // Left button: drag the card on the normal desktop, unless
                    // Lock widgets is on (EditMode.desktopDragAllowed; while editing
                    // the shield in EditChrome.qml moves it instead, until the card
                    // is selected for editing: then this does).
                    MouseArea {
                        id: dragArea
                        z: 10
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        enabled: win.grabbable
                        cursorShape: EditMode.desktopDragAllowed || chrome.selected
                            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

                        drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                        drag.axis: Drag.XAndYAxis
                        drag.minimumX: 0
                        drag.maximumX: Math.max(0, win.roomW - card.width)
                        drag.minimumY: 0
                        drag.maximumY: Math.max(0, win.roomH - card.height)

                        // Remember the new spot when a drag ends (also when cut
                        // short). A plain click doesn't save anything.
                        drag.onActiveChanged: {
                            // Edit Desktop's alignment grid (EditChrome.qml) needs to know
                            // about a drag that is not its own shield's.
                            chrome.ownDrag = drag.active
                            if (!drag.active) {
                                win.updateSide()
                                VisualizerService.setPosition(card.x, card.y, win.screen ? win.screen.name : "", win.uiScale)
                            }
                        }
                    }

                    // ===== the corner button: size =====
                    Timer {
                        id: labelTimer
                        interval: 1400
                    }

                    Timer {
                        id: hideTimer
                        interval: 350
                        onTriggered: card.btnShown = false
                    }

                    property bool btnShown: false
                    property string chipText: ""
                    readonly property bool wantBtn: chrome.selected

                    onWantBtnChanged: {
                        if (card.wantBtn) {
                            hideTimer.stop()
                            card.btnShown = true
                        } else {
                            hideTimer.restart()
                        }
                    }

                    Row {
                        id: btnRow
                        z: 20
                        spacing: 6
                        // A vertical band puts them in the middle of the card, halfway up the screen: the bar
                        // sits over its top corner.
                        x: win.vertical ? (card.width - btnRow.width) / 2
                            : (win.isBand ? card.width - btnRow.width - 10 : card.width - btnRow.width + 10)
                        y: win.vertical ? (card.height - btnRow.height) / 2
                            : (card.topSide ? card.height - btnRow.height + 12 : -12)
                        visible: opacity > 0.01
                        opacity: card.btnShown ? 1 : 0
                        scale: card.btnShown ? 1 : 0.6
                        transformOrigin: Item.Center

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }

                        Behavior on scale {
                            NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }

                        CornerButton {
                            icon: "style"
                            shown: card.btnShown
                            onClicked: VisualizerService.cycleStyle()
                        }

                        CornerButton {
                            icon: "aspect_ratio"
                            shown: card.btnShown
                            onClicked: VisualizerService.cycleSize()
                        }

                        CornerButton {
                            visible: win.isBand
                            icon: "screen_rotation"
                            shown: card.btnShown && win.isBand
                            onClicked: VisualizerService.toggleVertical()
                        }
                    }

                    Pill {
                        id: nameChip
                        z: 19
                        visible: card.btnShown && labelTimer.running
                        x: win.vertical ? btnRow.x + (btnRow.width - nameChip.width) / 2 : btnRow.x - nameChip.width - 4
                        y: win.vertical ? btnRow.y - nameChip.height - 6 : btnRow.y + (btnRow.height - nameChip.height) / 2
                        width: nameText.implicitWidth + 24
                        height: 30
                        cornerRadius: 10
                        ringWidth: 3
                        fillColor: mt.chipFill

                        Text {
                            id: nameText
                            anchors.centerIn: parent
                            text: card.chipText
                            color: mt.chipInk
                            font.family: mt.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }
                    }
                }
            }
        }
    }
}
