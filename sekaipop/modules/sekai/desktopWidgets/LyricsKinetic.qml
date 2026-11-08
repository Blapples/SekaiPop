import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticMath.js" as KM
import "../../common/functions/LyricsFont.js" as LF

// The kinetic lyrics: the same words as the desktop lyrics card (LyricsWidget.qml), but as
// kinetic typography over the WHOLE desktop. It is the card's other look, chosen with
// `ipc lyrics kinetic on` or Settings -> Desktop -> Lyrics -> Whole screen (LyricsService.kinetic);
// while it is on the card is not built.
//
//   Each line   gets a composition of its own, over the full screen: one giant word with the
//               rest small round it, a stack, a slash across the screen, a burst, a few
//               crooked rows like a poster, a rainbow (KineticMath.plan). The same line
//               always gets the same one, and two in a row never get the same.
//   Each word   is a ghost (the outline of its letters, faint, where it will land) until it is
//               sung. Then it slams in from where its composition throws it, overshoots,
//               squashes, and a ring runs out from it and a few diamonds fly off; its colour
//               fills across it for as long as it is sung (KineticWord.qml, KineticLine.qml).
//   The line    leaves a moment after it has been sung: it flies off the way it came, and the
//               next line takes the screen as it starts.
//   The camera  drifts in a little over a line and out over the next, slowly (or stays still:
//               Settings -> Whole screen camera). Nothing on the screen pulses with the beat.
//   Behind      a soft dark vignette so the words read on any wallpaper (Dim, in Settings), a
//               halftone in two corners, diamonds drifting up, and the line's biggest word
//               drawn huge and faint.
//   The gaps    an intro or an instrumental part is three big diamonds that light one by one.
//
// It lies on the wallpaper under your windows and takes no clicks at all (an empty input
// region), so the desktop and its icons keep working. Desktop Focus Mode hides it like the
// other widgets (FocusGate). It is off in Edit Desktop.
//
// Where the words come from and when each is sung is exactly the card's: services/
// LyricsService.qml (cache, a .lrc beside the file, then the sources in order, Boidu first
// for word-by-word timing) and the player's clock read as in LyricsWidget.qml (the position
// four times a second, a clock running in between, `LyricsMath.observe`). The nudge keys of
// the card are not here (nothing takes clicks): `ipc lyrics nudge 250` does the same.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call lyrics kinetic on|off     (whole-screen kinetic lyrics, or the card)
//   qs -c sekaipop ipc call lyrics kineticToggle
//   qs -c sekaipop ipc call lyrics dim 0.5            (how dark the vignette is, 0 .. 0.85)
PanelWindow {
    id: win

    // Which monitor it lives on, by name. Empty = the monitor the lyrics were last on
    // (LyricsService.screenName), or the first screen. A copy on another monitor (the Edit
    // Desktop copies, WidgetClones) has its own name here.
    property string monitor: ""

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : LyricsService.screenName
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    // The composition is drawn in real pixels of this monitor, sized from its height, so it
    // is the same picture on every screen.
    readonly property real sw: win.screen ? win.screen.width : 0
    readonly property real sh: win.screen ? win.screen.height : 0

    // The colours the words, rings, diamonds and beads take turns in. `theme` follows the
    // active theme (a group palette, matugen, this monitor's own theme): both accents, the
    // glint colour and a deeper shade of each accent so the fill still shows on the white
    // sticker; `sekai` is the five attribute pastels; `accent` is the two accents only.
    readonly property var palette: {
        const m = win.mt
        switch (LyricsService.kineticColors) {
        case "sekai":
            return m.attributeColors
        case "accent":
            return [m.accentCyan, m.accentMint]
        default:
            return [m.accentCyan, m.accentMint, m.capLitSoft, Qt.darker(m.accentCyan, 1.3), Qt.darker(m.accentMint, 1.3)]
        }
    }

    // Desktop Focus Mode (FocusGate.qml): false while an application is on this monitor's
    // workspace.
    FocusGate {
        id: gate
        widgetId: "lyrics"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: LyricsService.shown && LyricsService.loaded && LyricsService.kinetic && !EditMode.active
    readonly property bool want: win.switchedOn && gate.show && win.present && win.sw > 0

    // 0 .. 1: it fades in and out as a whole.
    property real reveal: win.want ? 1 : 0

    Behavior on reveal {
        NumberAnimation {
            duration: 650
            easing.type: Easing.InOutCubic
        }
    }

    readonly property bool live: win.want || win.reveal > 0.001
    // The player is read while the widget is switched on and not suspended by Focus Mode.
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while it is off: a full-screen transparent layer that is only sitting there
    // still costs the compositor a blend on every frame.
    visible: LyricsService.loaded && win.live

    // Under the windows, over the wallpaper, like the lyrics card.
    WlrLayershell.layer: WallpaperService.restacking ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-lyrics-kinetic"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Click-through: an empty region takes no input.
    mask: Region {}

    // ===== the player =====
    // Only built while the widget is switched on (see LyricsWidget.qml).
    Loader {
        active: win.working

        sourceComponent: Item {
            visible: false

            MediaSource {
                id: source

                Component.onCompleted: win.media = source
                Component.onDestruction: if (win.media === source) win.media = null
            }
        }
    }

    property var media: null
    readonly property var player: win.media ? win.media.player : null
    readonly property bool present: win.player !== null && win.player !== undefined
    readonly property bool playing: win.media ? win.media.playing : false

    readonly property string trackTitle: win.player ? String(win.player.trackTitle ?? "") : ""
    readonly property string trackArtist: win.player ? String(win.player.trackArtist ?? "") : ""
    readonly property string trackAlbum: win.player ? String(win.player.trackAlbum ?? "") : ""
    readonly property real trackLength: (win.player && win.player.lengthSupported) ? Number(win.player.length) : 0
    readonly property string trackUrl: {
        const md = win.player ? win.player.metadata : null
        const u = md ? md["xesam:url"] : undefined
        return typeof u === "string" ? u : ""
    }
    readonly property string trackSig: [win.trackTitle, win.trackArtist, win.trackAlbum, Math.round(win.trackLength), win.trackUrl].join("\u241f")

    // A new song restarts the clock; the length arriving a moment after the title must not.
    readonly property string identSig: [win.trackTitle, win.trackArtist, win.trackUrl].join("\u241f")

    onIdentSigChanged: {
        win.clk = LM.clockReset(0, Date.now())
        win.lastPolled = -1
        win.stalePolls = 0
        win.poll()
    }

    onTrackSigChanged: reqTimer.restart()

    onWorkingChanged: reqTimer.restart()

    // Players change the title first and the length a moment later, so wait a beat.
    Timer {
        id: reqTimer
        interval: 500
        onTriggered: {
            if (!win.working)
                return
            if (win.trackTitle === "")
                LyricsService.clear()
            else
                LyricsService.request(win.trackArtist, win.trackTitle, win.trackAlbum, win.trackLength, win.trackUrl)
        }
    }

    // ===== the clock =====
    // The same clock as the card's (see LyricsWidget.qml for why it is built like this).
    property var clk: LM.clockReset(0, 0)
    property real now: Date.now()
    property real lastPolled: -1
    property int stalePolls: 0

    function poll() {
        const p = win.player
        if (!p || !p.positionSupported)
            return
        p.positionChanged()
        const polled = Number(p.position)
        if (!isFinite(polled))
            return
        const trust = LM.pollTrust(win.lastPolled, polled, win.stalePolls, win.playing)
        win.lastPolled = polled
        win.stalePolls = trust.stale
        if (trust.use)
            win.clk = LM.observe(win.clk, polled, Date.now(), win.playing)
        win.now = Date.now()
    }

    onPlayingChanged: {
        const now = Date.now()
        win.clk = LM.clockReset(LM.estimate(win.clk, now, !win.playing), now)
        win.lastPolled = -1
        win.stalePolls = 0
        win.now = now
        win.poll()
    }

    Timer {
        interval: 250
        repeat: true
        running: win.working && win.present
        onTriggered: win.poll()
    }

    // Redraw every frame only while something on screen can still move: nothing depends on
    // the clock once the last line has been sung and has flown off.
    readonly property real songEnd: {
        const n = win.lines.length
        if (n === 0)
            return 0
        let e = Math.max(win.endOf(n - 1), win.bgEndOf(n - 1))
        if (n > 1)
            e = Math.max(e, win.endOf(n - 2))
        return e
    }
    readonly property bool animating: win.lines.length > 0 && win.clockT < win.songEnd + 4

    FrameAnimation {
        running: win.live && win.animating && win.playing
        onTriggered: win.now = Date.now()
    }

    // The player's position is never newer than the sound, so the words are shown a little
    // early, on top of the nudge (`ipc lyrics nudge`).
    readonly property real playerLead: 0.2
    readonly property real clockT: LM.estimate(win.clk, win.now, win.playing) + win.playerLead + LyricsService.syncTotal / 1000

    // ===== what is on =====
    readonly property var lines: LyricsService.lines
    readonly property int curIndex: LM.lineIndexAt(win.lines, win.clockT)
    readonly property real rate: LM.songRate(win.lines)

    // When line i has been sung by (as in LyricsWidget.qml).
    function endOf(i) {
        const l = win.lines[i]
        if (!l)
            return 0
        const next = i + 1 < win.lines.length ? win.lines[i + 1].t : Infinity
        const room = next - l.t
        if (l.text === "")
            return l.t + (isFinite(room) ? room : 4)
        const known = (l.end !== undefined && l.end > l.t) ? l.end - l.t : undefined
        return l.t + LM.sungSpan(l.text, room, win.rate, known)
    }

    function bgEndOf(i) {
        const l = win.lines[i]
        if (!l || !l.bg)
            return 0
        return Math.max(win.endOf(i), l.bg.t + LM.sungSpan(l.bg.text, Infinity, win.rate))
    }

    // The line that is on (its item), for the camera, the faint big word and the gap.
    readonly property var curItem: {
        // (read every frame: the item arrives a moment after the index changes)
        const frame = win.clockT
        const it = linesRep.itemAt(win.curIndex)
        return (it && it.item) ? it.item : null
    }
    // Still: the camera does not move at all (Settings -> Whole screen camera).
    readonly property bool drift: LyricsService.kineticCamera === "drift"
    readonly property var cam: (win.drift && win.curItem) ? win.curItem.cam : ({ scale: 1, rot: 0, dx: 0 })

    // Which look is on (LyricsService.kineticStyle): the poster (this file's stage), the wall
    // (KineticWall.qml) or the marquee (KineticMarquee.qml). Only the one that is on is built.
    readonly property string style: LyricsService.kineticStyle
    readonly property bool poster: win.style !== "wall" && win.style !== "marquee"

    // What the wall and the marquee need to know of the song: when each line starts and when it
    // has been sung by (the poster asks the lines one by one).
    readonly property var lineStarts: win.poster ? [] : win.lines.map(l => l.t)
    readonly property var lineEnds: win.poster ? [] : win.lines.map((l, i) => win.endOf(i))
    readonly property var lineBgEnds: win.poster ? [] : win.lines.map((l, i) => win.bgEndOf(i))

    // The small tag in the corner: what is playing.
    readonly property string tag: {
        const t = win.trackTitle
        const a = win.trackArtist
        let s = a !== "" ? (t + " - " + a) : t
        if (s.length > 64)
            s = s.slice(0, 63) + "..."
        if (LyricsService.status === "loading")
            s += "   looking for the words..."
        return s
    }

    // ===== behind everything =====
    // A vignette so the words read on any wallpaper.
    Rectangle {
        anchors.fill: parent
        opacity: win.reveal * LyricsService.kineticDim
        visible: opacity > 0.002

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(win.mt.colBorder.r, win.mt.colBorder.g, win.mt.colBorder.b, 0.95) }
            GradientStop { position: 0.5; color: Qt.rgba(win.mt.colBorder.r, win.mt.colBorder.g, win.mt.colBorder.b, 0.55) }
            GradientStop { position: 1.0; color: Qt.rgba(win.mt.colBorder.r, win.mt.colBorder.g, win.mt.colBorder.b, 0.95) }
        }
    }

    // The printed look of the game's menus: a halftone melting away from two corners.
    DotField {
        readonly property real gap: Math.max(16, Math.round(win.sh / 26))
        x: 0
        y: 0
        width: Math.round(win.sw * 0.34)
        height: Math.round(win.sh * 0.5)
        corner: "tl"
        spacing: gap
        maxRadius: gap * 0.34
        dotColor: "#ffffff"
        opacity: 0.13 * win.reveal
        visible: opacity > 0.002
    }

    DotField {
        readonly property real gap: Math.max(16, Math.round(win.sh / 26))
        x: Math.round(win.sw - width)
        y: Math.round(win.sh - height)
        width: Math.round(win.sw * 0.34)
        height: Math.round(win.sh * 0.5)
        corner: "br"
        spacing: gap
        maxRadius: gap * 0.34
        dotColor: "#ffffff"
        opacity: 0.13 * win.reveal
        visible: opacity > 0.002
    }

    // ===== the stage =====
    // The camera moves this (and with it the words, the diamonds and the big faint word).
    Item {
        id: stage
        width: win.sw
        height: win.sh
        opacity: win.reveal
        visible: win.poster && opacity > 0.002
        transformOrigin: Item.Center
        scale: win.cam.scale
        rotation: win.cam.rot
        x: win.cam.dx

        // The biggest word of the line, huge and faint, drifting a little.
        Text {
            id: heroText
            readonly property var it: win.curItem
            readonly property real amt: it ? it.heroIn : 0
            visible: amt > 0.002 && text !== ""
            text: it ? it.hero : ""
            font.family: LF.family(text, win.mt.fontFamily)
            font.pixelSize: it ? Math.max(10, Math.round(it.heroSize)) : 10
            font.weight: LF.weight(text, Font.ExtraBold)
            font.styleName: LF.style(text, win.mt.fontStyleBold)
            color: "#ffffff"
            opacity: 0.085 * amt
            x: Math.round((win.sw - width) / 2 + (it ? (win.clockT - it.lineStart) * win.sw * 0.011 * (it.index % 2 === 0 ? 1 : -1) : 0))
            y: Math.round((win.sh - height) / 2)
        }

        // Diamonds drifting up, each at its own speed and size. They move with the lyrics
        // clock, so they stop when the music does.
        Repeater {
            model: 14

            delegate: DiamondDot {
                id: gem

                required property int index

                readonly property real seedX: KM.hash(gem.index * 1.7 + 0.3)
                readonly property real seedY: KM.hash(gem.index * 2.9 + 1.1)
                readonly property real speed: 14 + 40 * KM.hash(gem.index * 3.7 + 2.3)
                readonly property real span: win.sh * 1.25

                lit: true
                size: Math.round(win.sh * (0.012 + 0.03 * KM.hash(gem.index * 5.3 + 4.1)))
                litColor: win.palette[gem.index % win.palette.length]
                x: Math.round(gem.seedX * win.sw)
                y: Math.round(win.sh * 1.1 - ((gem.seedY * gem.span + win.clockT * gem.speed) % gem.span))
                rotation: 45 + win.clockT * 24 * (gem.index % 2 === 0 ? 1 : -1)
                opacity: 0.55
            }
        }

        // One Loader per line of the song, but only the lines next to the one that is on are
        // built (a long song costs nothing), and the next one is built before it starts.
        Repeater {
            id: linesRep
            model: win.lines.length

            delegate: Loader {
                id: slot

                required property int index

                active: win.poster && Math.abs(slot.index - win.curIndex) <= 1

                sourceComponent: KineticLine {
                    readonly property var src: win.lines[slot.index]

                    text: src ? src.text : ""
                    index: slot.index
                    curIndex: win.curIndex
                    lineStart: src ? src.t : 0
                    lineEnd: win.endOf(slot.index)
                    nextStart: slot.index + 1 < win.lines.length ? win.lines[slot.index + 1].t : Infinity
                    nextIsGap: slot.index + 1 < win.lines.length && win.lines[slot.index + 1].text === ""
                    marks: (src && src.marks) ? src.marks : []
                    bgText: (src && src.bg) ? src.bg.text : ""
                    bgStart: (src && src.bg) ? src.bg.t : 0
                    bgEnd: win.bgEndOf(slot.index)
                    t: win.clockT
                    playing: win.playing
                    lineOnly: LyricsService.lineOnly
                    sw: win.sw
                    palette: win.palette
                    sh: win.sh
                }
            }
        }

        // A gap in the singing: three big diamonds that light one by one.
        Row {
            readonly property var it: win.curItem
            readonly property real amt: it ? it.gapAmt : 0
            visible: amt > 0.002
            spacing: Math.round(win.sh * 0.06)
            anchors.centerIn: parent
            scale: 0.4 + 0.6 * amt
            opacity: amt

            Repeater {
                model: 3

                delegate: DiamondDot {
                    id: bead

                    required property int index

                    readonly property var it: win.curItem
                    readonly property real p: it ? it.gapP : 0

                    size: Math.round(win.sh * 0.055)
                    lit: bead.p >= (bead.index + 1) / 4.2
                    litColor: win.palette[(bead.index * 2) % win.palette.length]
                    offColor: "#ffffff"
                    lineColor: win.mt.colBorder
                    border.width: 4
                }
            }
        }
    }

    // ===== the other two looks =====
    // Built only while they are the one that is on, so the poster costs nothing for them.
    Loader {
        active: win.style === "wall"
        anchors.fill: parent

        sourceComponent: KineticWall {
            lines: win.lines
            starts: win.lineStarts
            ends: win.lineEnds
            bgEnds: win.lineBgEnds
            t: win.clockT
            lineOnly: LyricsService.lineOnly
            drift: win.drift
            palette: win.palette
            sw: win.sw
            sh: win.sh
            reveal: win.reveal
        }
    }

    Loader {
        active: win.style === "marquee"
        anchors.fill: parent

        sourceComponent: KineticMarquee {
            lines: win.lines
            starts: win.lineStarts
            ends: win.lineEnds
            bgEnds: win.lineBgEnds
            t: win.clockT
            lineOnly: LyricsService.lineOnly
            drift: win.drift
            palette: win.palette
            sw: win.sw
            sh: win.sh
            reveal: win.reveal
        }
    }

    // What is playing, small, in the corner (not moved by the camera).
    LyricsWord {
        visible: win.tag !== "" && win.reveal > 0.002
        text: win.tag
        pixelSize: Math.max(14, Math.round(win.sh * 0.021))
        opacity: 0.8 * win.reveal
        x: Math.round(win.sw * 0.03)
        y: Math.round(win.sh - height - win.sh * 0.035)
    }
}
