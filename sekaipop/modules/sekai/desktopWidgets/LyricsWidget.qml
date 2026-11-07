import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode
import "../../common/functions/LyricsMath.js" as LM

// The desktop lyrics widget: the words of the song that is playing, sung along on the
// desktop. There is no card: the lyrics are stickers (a navy outline and a hard shadow, see
// LyricsWord.qml) lying straight on the wallpaper, so it is transparent everywhere except
// the letters, and it sits under your windows.
//
//   The stack    the line being sung is big in the middle; the one before it has slid up and
//                faded, the one to come waits below, small and tilted. A few moments before
//                a line starts it climbs into the middle and its words hop up one after
//                another.
//   The singing  the words of the line fill with colour as they are sung, and a diamond
//                bounces from word to word, landing on each exactly as it starts; the
//                word it lands on squashes and a few diamonds fly off (LyricsLine.qml).
//   Taken over   when the next line begins while this one is still being sung (voices that
//                overlap, a quick answer), the line is not faded out in mid-word: it is held
//                just above the new line, still strong, and goes on singing; when its last
//                word is done a few diamonds fly off and it settles back into the faded slot,
//                while the new line lands with a soft swell (LyricsLine.qml, LyricsMath.js).
//   The gaps     an intro or an instrumental part is three diamonds that light one by one.
//   Pausing      the lyrics stay where they were and dim, and the marker stops mid-hop.
//
// Where the words come from: services/LyricsService.qml (the cache, a .lrc beside the music
// file, then LRCLIB, fetched with curl; only the track's artist, title, album and length are
// ever sent). The
// time comes from the player (MPRIS): its position is read four times a second and a clock
// runs smoothly in between (LyricsMath.observe). A reading can only ever be older than the
// truth, never newer, so the clock follows the best of the last ten readings instead of
// their average: that is what keeps the words from being early, then late, then early again
// with a player that is slow to answer or moves its position once a second. A seek is
// followed at once.
//
// When a word is sung: a plain lyrics file only says when a LINE starts (and sometimes, by an
// empty stamp after it, when it ends), so the line's time is shared out over its words by
// syllable, and how long the line lasts comes from how fast THIS song is sung (learned from
// its lines). A file with word timing (enhanced LRC, "<00:12.40>want") is used as it is.
// (With Word by word off, `ipc lyrics words off`, all of that is ignored and the whole line lights when it starts.)
// Words in brackets, "(oh oh)", are ad libs: sung over the line, smaller and raised, and the
// bouncing marker skips them; a second line at the same moment sings along as a small row.
//
// Keeping in sync: the lines themselves are exactly as timed in the lyrics file. If a song
// is still early or late (the file was made for another cut of it, or your speakers lag),
// point at the lyrics: "earlier" and "later" keys appear, a tenth of a second a click, and
// the number between them is this song's nudge (click it to clear it). It is remembered for
// that song. `ipc lyrics nudge 250` does the same from a key bind, and `nudgeAll` shifts every
// song (a speaker that is always behind). When the lyrics were made for a cut of a different
// length than the song, the tag under them says so.
//
// The widget shows while something is playing (or paused) and goes away when nothing is.
// It is OFF until you add it (Edit Desktop's shelf, Settings -> Desktop, or the ipc). In
// Edit Desktop, with nothing playing, it shows a made-up verse so you can place it.
//
// How the moving works: exactly like PaletteWidget.qml. ONE transparent window with the
// card as an Item inside it. Dragging just moves that Item, so it stays smooth, and the
// window's input `mask` is only the card, even while Lock all is on, so its
// timing controls remain usable. Clicks outside the card pass through.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call lyrics toggle          (show / hide)
//   qs -c sekaipop ipc call lyrics nudge 250       (lyrics 250 ms earlier; -250 for later)
//   qs -c sekaipop ipc call lyrics words off       (light the whole line at once, no word hops; on = word by word)
//   qs -c sekaipop ipc call lyrics refresh         (look for this track's lyrics again)
//   qs -c sekaipop ipc call lyrics picker          (the source picker: where the words come from)
//   qs -c sekaipop ipc call lyrics debug           (show the clock's numbers under the lyrics)
//   qs -c sekaipop ipc call lyrics resetPosition   (if it ever ends up off-screen)

PanelWindow {
    id: win

    function resetPosition(): void {
        win.clearSpot();
        win.place(true);
        win.saveSpot(card.x, card.y);
    }

    // Which monitor it lives on, by name (`hyprctl monitors`), e.g. "DP-1".
    // Empty = the monitor the card was last dropped on (remembered in LyricsService),
    // or the first screen if it has never been moved.
    property string monitor: ""

    // A copy on another monitor (WidgetClones.qml): the same widget, with a spot of its own. The main
    // copy keeps its spot in the service as before.
    property bool clone: false

    readonly property var cloneSpot: win.clone ? WidgetClones.spot("lyrics", win.wantedScreen) : null
    readonly property bool spotReady: win.clone ? (WidgetClones.loaded && win.cloneSpot !== null) : LyricsService.loaded
    readonly property real spotX: win.clone ? (win.cloneSpot ? win.cloneSpot.x : -1) : LyricsService.posX
    readonly property real spotY: win.clone ? (win.cloneSpot ? win.cloneSpot.y : -1) : LyricsService.posY
    readonly property real spotScale: win.clone ? (win.cloneSpot ? win.cloneSpot.scale : 0) : LyricsService.posScale

    function saveSpot(x, y): void {
        if (win.clone)
            WidgetClones.setSpot("lyrics", win.wantedScreen, x, y, win.uiScale)
        else
            LyricsService.setPosition(x, y, win.screen ? win.screen.name : "", win.uiScale)
    }

    function clearSpot(): void {
        if (win.clone) {
            WidgetClones.clearSpot("lyrics", win.wantedScreen)
        } else {
            LyricsService.posX = -1
            LyricsService.posY = -1
        }
    }

    function fixSpotScale(): void {
        if (win.clone) {
            WidgetClones.setSpot("lyrics", win.wantedScreen, win.spotX, win.spotY, win.uiScale)
        } else {
            LyricsService.posScale = win.uiScale
            LyricsService.persist()
        }
    }

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : LyricsService.screenName
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's scale (scale.json / services/ShellScale.qml). The card is drawn in
    // design pixels inside a ScaleHost, so `roomW` x `roomH` is the screen as the card sees
    // it (real size / scale); positions are kept in that same design space.
    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real fullW: win.screen ? win.screen.width : 0
    readonly property real fullH: win.screen ? win.screen.height : 0
    readonly property real roomW: win.fullW / win.uiScale
    readonly property real roomH: win.fullH / win.uiScale

    // ===== a small window while nothing needs the whole screen =====
    // See PaletteWidget.qml: at rest the window is just the card plus some room around it.
    // Follows `EditMode.compactWindows` like every other widget (off by default; Low-end mode
    // turns it on). It used to be on for the lyrics whatever that switch said, but swapping the
    // full-screen window for the small one when Done was pressed made the card flash at the
    // top-left corner before it reached its spot: the card is drawn shifted by the box's
    // margin straight away, and the compositor only moves the window a moment later.
    // To get the idle saving back for the lyrics alone, drop `EditMode.compactWindows &&`
    // (and the jump comes back with it).
    readonly property bool compact: EditMode.compactWindows && !EditMode.active && !win.gliding
        && EditMode.screenName === "" && !EditMode.desktopDragAllowed && win.fullW > 0 && win.placed
    readonly property real boxPad: Math.ceil((0.16 * Math.max(card.width, card.height) + 24) * win.uiScale)
    readonly property real boxX: win.compact ? Math.max(0, Math.floor(card.x * win.uiScale - win.boxPad)) : 0
    readonly property real boxY: win.compact ? Math.max(0, Math.floor(card.y * win.uiScale - win.boxPad)) : 0
    readonly property real boxW: Math.max(1, Math.min(win.fullW,
        Math.ceil((card.x + card.width) * win.uiScale + win.boxPad)) - win.boxX)
    readonly property real boxH: Math.max(1, Math.min(win.fullH,
        Math.ceil((card.y + card.height) * win.uiScale + win.boxPad)) - win.boxY)

    // Desktop Focus Mode (FocusGate.qml): `gate.show` is false while an application is on
    // this monitor's workspace, so `want` goes false and the fade + unmap hide it.
    FocusGate {
        id: gate
        widgetId: "lyrics"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: LyricsService.shown && LyricsService.loaded
    // Nothing to show while no player is around, except the made-up verse in Edit Desktop.
    readonly property bool want: win.switchedOn && gate.show && (win.present || win.demo)
    property real reveal: 0

    // Off while the saved state is read back, so a reload doesn't replay the pop.
    property bool armed: false

    // Stays false until the card has been put on its saved spot, and keeps it drawn at
    // size 0 until then (after a reload the window maps before the compositor has told it
    // its real size).
    property bool placed: false

    onWantChanged: {
        if (!win.armed) {
            popIn.stop()
            fadeOut.stop()
            win.reveal = win.want ? 1 : 0
        } else if (win.want) {
            fadeOut.stop()
            popIn.restart()
        } else {
            popIn.stop()
            fadeOut.restart()
        }
    }

    NumberAnimation {
        id: popIn
        target: win
        property: "reveal"
        to: 1
        duration: 520
        easing.type: Easing.OutBack
        easing.overshoot: 1.6
    }

    NumberAnimation {
        id: fadeOut
        target: win
        property: "reveal"
        to: 0
        duration: 360
        easing.type: Easing.InCubic
    }

    Timer {
        interval: 800
        running: LyricsService.loaded
        onTriggered: win.armed = true
    }

    // `live`: the widget is on, or still fading out.
    readonly property bool live: win.want || win.reveal > 0.001

    // The player is read while the widget is switched on and not suspended by Focus Mode.
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while the widget is off: a transparent layer that is only sitting there
    // still costs the compositor a blend on every frame.
    visible: LyricsService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock, up a layer while edited / moved (see PaletteWidget.qml).
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-lyrics"
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

    // Keep the card interactive for its timing controls, even while locked.
    // Dragging is gated separately; the rest of the screen stays click-through.
    mask: Region {
        item: cardMask
    }

    Item {
        id: cardMask
        readonly property real m: stage.editing ? 38 : 0
        readonly property real k: win.uiScale * stage.scale
        readonly property real x1: shifter.x + stage.x + (card.x + card.width + m) * k
        readonly property real y1: shifter.y + stage.y + (card.y + card.height + m) * k
        x: (!win.live) ? 0 : Math.max(0, Math.round(shifter.x + stage.x + (card.x - m) * k))
        y: (!win.live) ? 0 : Math.max(0, Math.round(shifter.y + stage.y + (card.y - m) * k))
        width: (!win.live) ? 1 : Math.max(0, Math.ceil(x1) - x)
        height: (!win.live) ? 1 : Math.max(0, Math.ceil(y1) - y)
    }

    // ===== the player =====
    // Where the track and the time come from (the bar, the dock and the lockscreen each
    // have their own MediaSource too). Only built while the widget is switched on.
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

    // Edit Desktop with nothing playing: a made-up verse, so there is something to place.
    readonly property bool demo: EditMode.active && !win.present
    readonly property var demoLines: [
        { t: 0, text: "" },
        { t: 3, text: "this is where the words go" },
        { t: 7, text: "one by one, as they are sung" },
        { t: 11.5, text: "drop me anywhere you like" },
        { t: 15, text: "" }
    ]
    readonly property real demoTotal: 18

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

    // A new song restarts the clock; the length arriving a moment after the title (a browser)
    // must not, so the two are told apart.
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
    // The player's position is read four times a second; between the readings a clock runs
    // on its own, set by the best of the last ten readings (LyricsMath.observe).
    property var clk: LM.clockReset(0, 0)
    property real now: Date.now()
    // The last reading, and how many in a row said the same while playing (LyricsMath.pollTrust:
    // a position that does not move is not trusted, the clock runs on its own instead).
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
        if (trust.use) {
            const stamp = Date.now()
            const before = LM.estimate(win.clk, stamp, win.playing)
            win.clk = LM.observe(win.clk, polled, stamp, win.playing)
            const jump = LM.estimate(win.clk, stamp, win.playing) - before
            // More than half a second at once is a seek (or a player that stalled). The log
            // says so, for working out why the words were off at some moment.
            if (win.playing && Math.abs(jump) > 0.5)
                console.log("[lyrics] clock moved " + (jump > 0 ? "+" : "") + jump.toFixed(2) + " s (a seek, or the player stalled)")
        }
        win.now = Date.now()
    }

    onPlayingChanged: {
        // Pause / resume: freeze the clock where it was (or restart it from there), so a
        // player that gives no position keeps its place too.
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

    // Redraw every frame only while something on screen can still move. With no lyrics (a
    // video, a track nobody has words for, "looking for the words...") or once the last line
    // has been sung and has settled, nothing depends on the clock any more, so the window is
    // left alone instead of being redrawn at the screen's refresh rate for the rest of the
    // track. The 250 ms poll above still keeps `now` right, so a seek back, or the words
    // arriving, starts the frames again at once.
    readonly property real songEnd: {
        const n = win.lines.length
        if (n === 0)
            return 0
        // (an earlier line can be sung past a short last one, and the voice that sings along
        // can outlast its line)
        let e = Math.max(win.endOf(n - 1), win.bgEndOf(n - 1))
        if (n > 1)
            e = Math.max(e, win.endOf(n - 2))
        return e
    }
    // 3 s covers what settles after the last word: a held line lets go over 0.7 s, the
    // marker shrinks away in 0.26 s, the diamonds fly for 0.6 s.
    readonly property bool animating: win.demo || (win.lines.length > 0 && win.clockT < win.songEnd + 3)

    FrameAnimation {
        running: win.live && win.animating && (win.demo || win.playing)
        onTriggered: win.now = Date.now()
    }

    // The player's position is never newer than the sound and the sound takes a moment to leave
    // the speakers, so the words are shown this many seconds early on top of the nudge (the
    // nudge keys and `ipc lyrics nudgeAll` still move them from here).
    readonly property real playerLead: 0.2
    readonly property real clockT: win.demo
        ? (win.now / 1000) % win.demoTotal
        : LM.estimate(win.clk, win.now, win.playing) + win.playerLead + LyricsService.syncTotal / 1000

    // ===== what is on =====
    readonly property var lines: win.demo ? win.demoLines : LyricsService.lines
    // How long before a line starts the stack begins to climb to it (LyricsMath.cursor).
    readonly property real lead: 0.45
    readonly property real cursorV: LM.cursor(win.lines, win.clockT, win.lead, win.nextRush)
    readonly property int curIndex: LM.lineIndexAt(win.lines, win.clockT)
    readonly property int base: Math.round(win.cursorV)

    // How fast this song is sung, in syllables a second, learned from its own lines.
    readonly property real rate: LM.songRate(win.lines)

    // How much line i is held (0 .. 1): it is still being sung when the stack starts to climb
    // away from it (LyricsMath.leaveAt, rushOf). Such a line is held, not faded (see
    // LyricsLine.qml). A gap in the singing and the last line are never held.
    function rushAfter(i) {
        if (i < 0 || i + 1 >= win.lines.length)
            return 0
        const l = win.lines[i]
        if (l.text === "")
            return 0
        return LM.rushOf(LM.overrun(win.endOf(i), LM.leaveAt(l.t, win.lines[i + 1].t, win.lead)))
    }

    // How much the line after line i TAKES IT OVER (0 .. 1): it is still being sung when the
    // next one has begun. The stack then takes a little longer to climb and the new line lands
    // with a swell. Only changes when the line on changes, not every frame.
    function takeAfter(i) {
        if (i < 0 || i + 1 >= win.lines.length || win.lines[i].text === "")
            return 0
        return LM.rushOf(LM.overrun(win.endOf(i), win.lines[i + 1].t))
    }

    readonly property real nextRush: win.takeAfter(win.curIndex)

    // When line i has been sung by: its start plus the time its words take, never past the
    // start of the next. A line that says when it ends (an empty stamp after it) is taken at
    // its word; otherwise it is the amount of singing at the song's rate. A gap in the
    // singing lasts until the next line.
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

    // When the voice that sings along with line i has been sung by (it can outlast the line).
    function bgEndOf(i) {
        const l = win.lines[i]
        if (!l || !l.bg)
            return 0
        return Math.max(win.endOf(i), l.bg.t + LM.sungSpan(l.bg.text, Infinity, win.rate))
    }

    // What the middle says when there are no lines to sing.
    readonly property string message: {
        if (win.demo || win.lines.length > 0)
            return ""
        switch (LyricsService.status) {
        case "loading": return "looking for the words...";
        // "none" (no synced lyrics) and "instrumental" say nothing on purpose: a song without
        // words just shows its title under the card, no placeholder text in the middle.
        case "offline": return "can't reach the lyrics service";
        default: return "";
        }
    }

    // The small tag under the lyrics: what is playing.
    readonly property string tag: {
        if (win.demo)
            return "lyrics";
        // ipc lyrics debug: the numbers the timing is made of, instead of the title. `spread`
        // is how far apart the player's last ten readings were (a steady player: a few ms;
        // one that is slow to answer or moves once a second: hundreds), `line` is the one
        // that is on, `rate` is how fast the song is sung.
        if (LyricsService.debug)
            return "clock spread " + LM.clockSpread(win.clk) + " ms   line " + (win.curIndex + 1) + "/" + win.lines.length
                + "   " + win.rate.toFixed(1) + " syl/s   nudge " + (LyricsService.syncTotal / 1000).toFixed(1) + " s";
        const t = win.trackTitle
        const a = win.trackArtist
        let s = a !== "" ? (t + " - " + a) : t
        if (s.length > 56)
            s = s.slice(0, 55) + "..."
        // The lyrics were made for a cut of a different length: they may need a nudge.
        if (Math.abs(LyricsService.versionDiff) >= 1.5 && win.lines.length > 0)
            s += "  (lyrics for a " + Math.abs(LyricsService.versionDiff).toFixed(1) + " s " + (LyricsService.versionDiff > 0 ? "longer" : "shorter") + " cut)"
        return s
    }

    // ===== placement =====
    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        // Not before the saved spot has been read, and not while the window is still
        // smaller than the card (the clamp below would put it at 0, 0).
        if (!force && (!LyricsService.loaded || win.roomW < card.width || win.roomH < card.height))
            return
        let x = win.spotX
        let y = win.spotY
        if (x < 0 || y < 0) {
            // The first spot: the middle, low on the screen, above the dock.
            x = (win.roomW - card.width) / 2
            y = win.roomH - card.lyricsH - 150
        } else if (win.spotScale > 0 && win.uiScale > 0) {
            // Saved at another shell scale: same spot on the screen, not the same design
            // pixels (the card keeps its top-left corner).
            const k = win.spotScale / win.uiScale
            x *= k
            y *= k
        }
        card.x = Math.max(0, Math.min(x, win.roomW - card.width))
        card.y = Math.max(0, Math.min(y, win.roomH - card.height))
        win.placed = true
    }

    // After a reload the window, the monitor list and scale.json all settle over a few
    // frames; place again once they have, so the card always ends on its saved spot (never
    // while it is being dragged).
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            if (win.spotReady && win.spotX >= 0 && win.spotScale <= 0 && !dragArea.drag.active)
                win.fixSpotScale()
            if (!chrome.dragging && !dragArea.drag.active)
                win.place(!win.placed && LyricsService.loaded)
        }
    }

    // place() runs one turn of the event loop later (Qt.callLater), not inside the window's own
    // size change: the size is boxW / boxH, which read card.x / card.y, which place() sets
    // (Qt logged "Binding loop detected for property implicitWidth"). Same as ClockWidget.qml.
    // To undo: `onWidthChanged: { win.place(); settle.restart() }` (same for the height).
    onWidthChanged: { Qt.callLater(win.place); settle.restart() }
    onHeightChanged: { Qt.callLater(win.place); settle.restart() }
    onUiScaleChanged: { win.place(); settle.restart() }
    onScreenChanged: { win.place(); settle.restart() }
    onVisibleChanged: settle.restart()
    Component.onCompleted: {
        win.reveal = win.want ? 1 : 0
        win.place()
    }

    // The spot of a copy changed (a drag, a reset): put the card there.
    Connections {
        target: WidgetClones
        enabled: win.clone
        function onSpotsChanged() { follow.restart() }
    }

    Connections {
        target: LyricsService
        function onLoadedChanged() {
            win.place()
            settle.restart()
        }
        // Something else (Edit Desktop moving the card to this monitor) hands the service
        // another spot while the card is on screen. The spot arrives as several properties
        // one after the other, so wait a beat and place once.
        function onPosXChanged() { follow.restart() }
        function onPosYChanged() { follow.restart() }
        function onPosScaleChanged() { follow.restart() }
    }

    // The card glides to its new spot instead of jumping (not while it is being dragged, and
    // not when it is already where it should be). `gliding` first, so a small window grows to
    // the whole screen (see `compact`), then `glideOn` switches the Behaviors on.
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

    Timer {
        id: glideEnd
        interval: 640
        onTriggered: {
            win.glideOn = false
            win.gliding = false
        }
    }

    // Edit Desktop's shelf shows the card as it really looks (EditPreview.qml).
    EditPreview {
        widgetId: win.clone ? "" : "lyrics"
        target: card
        pixelRatio: win.uiScale
    }

    // ===== Edit Desktop =====
    Item {
        id: shifter
        x: -win.boxX
        y: -win.boxY
        width: win.fullW
        height: win.fullH

    // Edit Desktop shrinks every desktop window into the same card with the same transform
    // (see EditStage.qml / services/EditMode.qml). Out of edit mode this is a no-op.
    EditStage {
        id: stage
        screenObj: win.screen
        uiScale: win.uiScale

        ScaleHost {
            anchors.fill: parent
            factor: win.uiScale

            Item {
                id: card

                Behavior on x {
                    enabled: win.glideOn
                    NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }
                Behavior on y {
                    enabled: win.glideOn
                    NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }

                // The room the lyrics have: the stack of lines is centred in it, the tag is
                // under it. Nothing is drawn behind it.
                readonly property real midY: 112
                // The lyrics' own room (the title sits at its bottom); the sync keys hang
                // under the title, in `keysRoom` of their own, so the lyrics and the title
                // stay where they were.
                readonly property real lyricsH: 244
                readonly property real keysRoom: 84
                width: 720
                height: card.lyricsH + card.keysRoom

                scale: (0.72 + 0.28 * Math.max(0, win.reveal)) * (win.placed ? 1 : 0)
                opacity: Math.max(0, Math.min(1, win.reveal * 1.6))
                transformOrigin: Item.Center

                onWidthChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                onHeightChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                // Edit Desktop: outline, corner diamonds, a tag and a drag shield
                // (EditChrome.qml). Draws nothing outside the mode.
                EditChrome {
                    id: chrome
                    widgetId: "lyrics"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: win.saveSpot(card.x, card.y)
                    onRemoveRequested: EditMode.removeFrom("lyrics", win.screen ? win.screen.name : "")
                }

                // Left button: drag the card on the normal desktop, unless Lock all is on
                // (EditMode.desktopDragAllowed; while editing, the shield in EditChrome.qml
                // does the moving instead, until the card is selected for editing: then
                // this does).
                MouseArea {
                    id: dragArea
                    enabled: EditMode.desktopDragAllowed || chrome.selected
                    z: 1
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

                    drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, win.roomW - card.width)
                    drag.minimumY: 0
                    drag.maximumY: Math.max(0, win.roomH - card.height)

                    // Remember the new spot when a drag ends (also when it is cut short). A
                    // plain click doesn't save anything.
                    drag.onActiveChanged: {
                        chrome.ownDrag = drag.active
                        if (!drag.active)
                            win.saveSpot(card.x, card.y)
                    }
                }

                // ===== the lyrics =====
                // One Loader per line of the song, but only the lines within two of the middle
                // are built (so a long song costs nothing), and a line is built just before
                // it slides into view.
                Repeater {
                    model: win.lines.length

                    delegate: Loader {
                        id: slot

                        required property int index

                        active: Math.abs(slot.index - win.base) <= 2

                        sourceComponent: LyricsLine {
                            text: win.lines[slot.index] ? win.lines[slot.index].text : ""
                            index: slot.index
                            curIndex: win.curIndex
                            lineStart: win.lines[slot.index] ? win.lines[slot.index].t : 0
                            lineEnd: win.endOf(slot.index)
                            rush: win.rushAfter(slot.index)
                            prevRush: win.rushAfter(slot.index - 1)
                            prevEnd: slot.index > 0 ? win.endOf(slot.index - 1) : 0
                            marks: (win.lines[slot.index] && win.lines[slot.index].marks) ? win.lines[slot.index].marks : []
                            bgText: (win.lines[slot.index] && win.lines[slot.index].bg) ? win.lines[slot.index].bg.text : ""
                            bgStart: (win.lines[slot.index] && win.lines[slot.index].bg) ? win.lines[slot.index].bg.t : 0
                            bgEnd: win.bgEndOf(slot.index)
                            t: win.clockT
                            d: slot.index - win.cursorV
                            playing: win.demo || win.playing
                            lineOnly: LyricsService.lineOnly
                            maxW: card.width - 40
                            cx: card.width / 2
                            cy: card.midY
                        }
                    }
                }

                // A message in the middle when there is nothing to sing.
                LyricsLine {
                    visible: win.message !== ""
                    still: true
                    text: win.message
                    px: 30
                    d: 0
                    playing: true
                    maxW: card.width - 40
                    cx: card.width / 2
                    cy: card.midY
                }

                // Point at the lyrics: the sync keys appear even with widgets locked,
                // but stay hidden while arranging widgets in Edit Desktop.
                HoverHandler {
                    id: hover
                }

                readonly property bool keysOn: hover.hovered && !EditMode.active
                    && !win.demo

                // Built only while pointed at (and while they fade out): four stickers are 56
                // text items that would otherwise sit there, unseen, for the whole song.
                Loader {
                    id: syncKeys
                    z: 3
                    active: card.keysOn || syncKeys.opacity > 0.01
                    opacity: card.keysOn ? 1 : 0
                    visible: opacity > 0.01
                    x: Math.round((card.width - width) / 2)
                    y: card.lyricsH + 8

                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    sourceComponent: Row {
                        spacing: 12

                        // Icon keys (workspace-badge look); the hover tag says which is which.
                        LyricsKey {
                            icon: "double_alt_arrow_left"
                            tipBelow: true
                            tip: "later"
                            visible: win.lines.length > 0
                            onClicked: LyricsService.nudge(-100)
                        }

                        // This song's nudge; a click clears it.
                        LyricsKey {
                            label: (LyricsService.trackOffsetMs > 0 ? "+" : "") + (LyricsService.trackOffsetMs / 1000).toFixed(1) + " s"
                            visible: win.lines.length > 0
                            onClicked: LyricsService.setTrackOffset(0)
                        }

                        LyricsKey {
                            icon: "double_alt_arrow_right"
                            tipBelow: true
                            tip: "earlier"
                            visible: win.lines.length > 0
                            onClicked: LyricsService.nudge(100)
                        }

                        // Where the words come from, and what each provider found (LyricsSources.qml).
                        LyricsKey {
                            icon: "travel_explore"
                            tipBelow: true
                            tip: "sources"
                            onClicked: LyricsService.togglePicker(win.screen ? win.screen.name : "", card.x + card.width / 2, card.y + card.lyricsH + 8)
                        }
                    }
                }

                // What is playing, small, under the lyrics.
                LyricsWord {
                    visible: win.tag !== ""
                    text: win.tag
                    pixelSize: 15
                    opacity: 0.78
                    x: Math.round((card.width - width) / 2)
                    y: card.lyricsH - height - 2
                }
            }
        }
    }
    }
}
