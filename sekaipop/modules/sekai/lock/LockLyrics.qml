import QtQuick
import qs.services
import qs.modules.common
import "../../common/functions/LyricsMath.js" as LM

// The words of the song that is playing, on the lockscreen: the line being sung, and the
// next one under it, in a capsule like the others on the screen. Off until it is switched
// on (Settings -> General -> Lockscreen; `lock.lyrics`), because it asks the lyrics
// providers for the song, the same lookups the desktop Lyrics widget makes.
//
//   LockLyrics { media: media; px: root.px }
//
// The lyrics themselves come from LyricsService (the cache, a .lrc file beside the music,
// then the providers); this only asks for the track and draws the line that is on. It
// needs no widget on the desktop: the lockscreen has its own player reading (4 times a
// second, with a clock running between the readings, the same LyricsMath the widget uses)
// and the same sync nudge. Nothing is drawn, and nothing runs, while no song is playing or
// the song has no lyrics: the capsule closes.
Item {
    id: root

    // The lockscreen's MediaSource, and its px() so everything scales like the rest.
    required property var media
    property var px: n => n
    // How wide the capsule may grow.
    property real maxWidth: 900
    // The Lyrics widget of the Custom lockscreen (LockLyricsWidget.qml) is on because it was
    // placed, so it does not wait for the setting; the Gacha look still does.
    property bool always: false
    // The editor's sample: a made-up line, shown whether or not anything is playing.
    property bool preview: false

    readonly property bool enabled: root.always || SettingsService.flag("lock.lyrics")
    readonly property var player: root.media ? root.media.player : null
    readonly property bool playing: root.media ? root.media.playing : false
    readonly property bool working: root.enabled && root.media !== null && root.media.present && root.player !== null && root.player !== undefined

    // ===== the track =====
    readonly property string trackTitle: root.player ? String(root.player.trackTitle ?? "") : ""
    readonly property string trackArtist: root.player ? String(root.player.trackArtist ?? "") : ""
    readonly property string trackAlbum: root.player ? String(root.player.trackAlbum ?? "") : ""
    readonly property real trackLength: (root.player && root.player.lengthSupported) ? Number(root.player.length) : 0
    readonly property string trackUrl: {
        const md = root.player ? root.player.metadata : null
        const u = md ? md["xesam:url"] : undefined
        return typeof u === "string" ? u : ""
    }
    readonly property string trackSig: [root.trackTitle, root.trackArtist, root.trackAlbum, Math.round(root.trackLength), root.trackUrl].join("\u241f")
    readonly property string identSig: [root.trackTitle, root.trackArtist, root.trackUrl].join("\u241f")

    onTrackSigChanged: reqTimer.restart()
    onWorkingChanged: reqTimer.restart()

    // Players change the title first and the length a moment later (and every monitor's
    // lockscreen asks, but asking for the track that is already on does nothing).
    Timer {
        id: reqTimer
        interval: 500
        onTriggered: {
            if (root.working && root.trackTitle !== "")
                LyricsService.request(root.trackArtist, root.trackTitle, root.trackAlbum, root.trackLength, root.trackUrl)
        }
    }

    // ===== the clock =====
    property var clk: LM.clockReset(0, 0)
    property real now: Date.now()
    property real lastPolled: -1
    property int stalePolls: 0

    function poll() {
        const p = root.player
        if (!p || !p.positionSupported)
            return
        p.positionChanged()
        const polled = Number(p.position)
        if (!isFinite(polled))
            return
        const trust = LM.pollTrust(root.lastPolled, polled, root.stalePolls, root.playing)
        root.lastPolled = polled
        root.stalePolls = trust.stale
        if (trust.use)
            root.clk = LM.observe(root.clk, polled, Date.now(), root.playing)
        root.now = Date.now()
    }

    onIdentSigChanged: {
        root.clk = LM.clockReset(0, Date.now())
        root.lastPolled = -1
        root.stalePolls = 0
        root.poll()
    }

    onPlayingChanged: {
        const now = Date.now()
        root.clk = LM.clockReset(LM.estimate(root.clk, now, !root.playing), now)
        root.lastPolled = -1
        root.stalePolls = 0
        root.now = now
        root.poll()
    }

    // Only while there is something to show: lyrics found, and the song playing.
    readonly property var lines: LyricsService.lines
    readonly property bool haveLines: root.working && LyricsService.status === "ready" && root.lines.length > 0

    Timer {
        interval: 250
        repeat: true
        running: root.working
        onTriggered: root.poll()
    }

    // The line changes at most every few seconds, so a 10 Hz clock is plenty here (the
    // widget's per-frame redraw is for its word-by-word animation, which this has none of).
    Timer {
        interval: 100
        repeat: true
        running: root.haveLines && root.playing
        onTriggered: root.now = Date.now()
    }

    // The player's position runs a little behind the sound (the widget's `playerLead`).
    readonly property real clockT: LM.estimate(root.clk, root.now, root.playing) + 0.2 + LyricsService.syncTotal / 1000
    readonly property int curIndex: root.haveLines ? LM.lineIndexAt(root.lines, root.clockT) : -1

    function textAt(i) {
        const l = (i >= 0 && i < root.lines.length) ? root.lines[i] : null
        return l ? String(l.text ?? "").trim() : ""
    }

    // The next line that has words in it (a gap in the singing has none).
    function nextText(i) {
        for (let j = i + 1; j < root.lines.length && j <= i + 3; j++) {
            const t = root.textAt(j)
            if (t !== "")
                return t
        }
        return ""
    }

    // What is shown: kept while the capsule closes, so the words do not blank before it is gone.
    property string shownNow: root.preview ? "The line being sung" : ""
    property string shownNext: root.preview ? "and the line after it" : ""
    readonly property string wantNow: root.curIndex < 0 ? "" : (root.textAt(root.curIndex) || "\u266a")
    readonly property string wantNext: root.curIndex < 0 ? root.textAt(0) : root.nextText(root.curIndex)

    onWantNowChanged: if (root.haveLines) root.shownNow = root.wantNow
    onWantNextChanged: if (root.haveLines) root.shownNext = root.wantNext
    onHaveLinesChanged: {
        if (root.haveLines) {
            root.shownNow = root.wantNow
            root.shownNext = root.wantNext
        }
    }

    // ===== the capsule =====
    // 0 -> 1: it opens (height, then its words) rather than popping.
    property real reveal: ((root.haveLines || root.preview) && root.shownNow + root.shownNext !== "") ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    readonly property real pad: root.px(24)
    readonly property real fullHeight: capsule.implicitHeight

    implicitWidth: capsule.width
    implicitHeight: Math.round(root.fullHeight * root.reveal)
    width: implicitWidth
    height: implicitHeight
    clip: true
    visible: root.reveal > 0.001

    Rectangle {
        id: capsule

        readonly property real textW: Math.min(root.maxWidth - root.pad * 2,
            Math.max(nowText.implicitWidth, nextText.implicitWidth))
        width: Math.round(textW + root.pad * 2)
        implicitHeight: Math.round(col.implicitHeight + root.px(34))
        height: implicitHeight
        radius: root.px(26)
        color: LockPalette.cap
        opacity: Math.max(0, Math.min(1, (root.reveal - 0.15) / 0.85))

        Column {
            id: col
            anchors.centerIn: parent
            width: capsule.textW
            spacing: root.px(6)

            Text {
                id: nowText
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.shownNow
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(38)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold

                onTextChanged: lineIn.restart()

                NumberAnimation on opacity {
                    id: lineIn
                    from: 0.25
                    to: 1
                    duration: 180
                    running: false
                }
            }

            Text {
                id: nextText
                width: parent.width
                visible: root.shownNext !== ""
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                maximumLineCount: 1
                text: root.shownNext
                color: LockPalette.lavenderText
                opacity: 0.8
                font.family: Theme.fontFamily
                font.pixelSize: root.px(26)
                font.weight: Font.Medium
            }
        }
    }
}
