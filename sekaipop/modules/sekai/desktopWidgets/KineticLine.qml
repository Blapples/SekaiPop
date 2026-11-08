import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticMath.js" as KM

// One line of the kinetic lyrics, laid out over the WHOLE screen (W x H).
//
// Which composition a line gets (a giant word, a stack, a slash, a burst, a few crooked
// rows, a rainbow) and where every word goes comes from KineticMath.plan(): the same line
// always gets the same picture, and two lines in a row never get the same one. When each word
// is sung comes from the lyrics file exactly as in the lyrics card (LyricsMath.spansFor: real
// word timing where a source has it, shared out by syllable where it only has the line).
//
// Everything is worked out from the lyrics clock `t`, so a pause freezes the picture and a
// seek puts it where it should be.
//
// A voice that sings along (`bgText`) is laid out as small words in the corners, and a word in
// brackets, "(oh oh)", is small too.
Item {
    id: line

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string text: ""
    property int index: 0
    property int curIndex: -1
    property real lineStart: 0
    property real lineEnd: 0
    // When the next line starts, and whether that one is a gap (an instrumental part).
    property real nextStart: Infinity
    property bool nextIsGap: false
    property var marks: []
    property string bgText: ""
    property real bgStart: 0
    property real bgEnd: 0
    property real t: 0
    property bool playing: false
    // Word by word off: the whole line lands at once, a hair apart.
    property bool lineOnly: false
    // The colours to take turns in (LyricsKinetic.palette).
    property var palette: mt.attributeColors
    property real sw: 1920
    property real sh: 1080

    width: line.sw
    height: line.sh

    // ===== the words =====
    readonly property var mainToks: LM.tokens(line.text)
    readonly property var bgToks: line.bgText !== "" ? LM.tokens(line.bgText).map(tk => ({ s: tk.s, gap: tk.gap, adlib: true })) : []
    readonly property var toks: line.mainToks.concat(line.bgToks)
    readonly property bool blank: line.toks.length === 0
    readonly property var mainSp: LM.spansFor(line.mainToks, line.lineStart, Math.max(0.1, line.lineEnd - line.lineStart), line.marks)
    readonly property var bgSp: line.bgToks.length > 0
        ? LM.spans(line.bgToks, line.bgStart, Math.max(0.2, Math.max(line.bgEnd, line.lineEnd) - line.bgStart))
        : []
    readonly property var sp: {
        const all = line.mainSp.concat(line.bgSp)
        if (!line.lineOnly)
            return all
        // The whole line at once: every word lands within a quarter of a second of the start.
        return all.map((s, i) => ({ from: line.lineStart + Math.min(0.25, i * 0.045), to: line.lineStart + Math.min(0.25, i * 0.045) + 0.2 }))
    }

    // Where each word goes and how it comes and goes.
    readonly property var layout: line.blank ? ({ style: "flow", words: [] }) : KM.plan(line.toks, line.index, line.sw, line.sh)
    readonly property string style: line.layout.style

    // When the line starts to leave (KineticMath.leaveStart).
    readonly property real leaveAt: KM.leaveStart(line.lineStart, Math.max(line.lineEnd, line.bgToks.length > 0 ? line.bgEnd : 0), line.nextStart, line.nextIsGap)

    // A colour for each word, from the palette.
    readonly property var colors: line.palette

    // ===== what the stage needs to know =====
    readonly property bool isCur: line.index === line.curIndex
    // The last word that has been sung (of the main text): a burst of diamonds flies off it.
    readonly property int km: LM.wordAt(line.mainSp, line.t)
    // The slow camera move of this line (it never pulses with the words).
    readonly property var cam: KM.camera(line.t, line.lineStart, line.leaveAt, line.index, line.sw)

    // The biggest word of the line, drawn huge and faint behind everything.
    readonly property string hero: {
        let best = ""
        for (let i = 0; i < line.mainToks.length; i++) {
            if (!line.mainToks[i].adlib && line.mainToks[i].s.length >= best.length)
                best = line.mainToks[i].s
        }
        return best
    }
    readonly property real heroSize: line.hero === "" ? 0 : Math.min(line.sh * 0.7, (line.sw * 0.97) / KM.wordEm(line.hero))
    // 0 .. 1: it comes up with the line and goes with it.
    readonly property real heroIn: line.blank ? 0
        : KM.clamp((line.t - line.lineStart) / 0.45, 0, 1) * (1 - KM.clamp((line.t - line.leaveAt) / 0.35, 0, 1))

    // A gap in the singing (an intro, an instrumental part): how far through it we are, and how
    // much of it is on screen (it comes in and goes out over 0.4 s).
    readonly property real gapP: line.blank ? KM.clamp((line.t - line.lineStart) / Math.max(0.5, line.lineEnd - line.lineStart), 0, 1) : 0
    readonly property real gapAmt: (line.blank && line.isCur)
        ? KM.clamp((line.t - line.lineStart) / 0.4, 0, 1) * KM.clamp((line.lineEnd - line.t) / 0.4, 0, 1)
        : 0

    readonly property var idle: ({ started: false, ox: 0, oy: 0, s: 1, rot: 0, op: 0, hit: 0, ring: 1, sung: 0, gone: false })

    // A word has just been sung: a small burst of diamonds off it.
    onKmChanged: {
        if (!line.isCur || !line.playing || line.lineOnly || line.km < 0 || line.t >= line.leaveAt)
            return
        // (a seek that lands in the middle of the line is not a word being sung)
        const s = line.mainSp[line.km]
        if (s === undefined || line.t - s.from > 0.3)
            return
        const w = line.layout.words[line.km]
        if (!w)
            return
        const puff = (line.km % 2 === 0) ? puffA : puffB
        puff.x = w.x
        puff.y = w.y
        puff.radius = Math.max(60, w.size * 1.1)
        puff.size = Math.max(8, Math.round(w.size * 0.13))
        puff.fire()
    }

    Repeater {
        model: line.toks.length

        delegate: KineticWord {
            id: kw

            required property int index

            readonly property var wp: line.layout.words[kw.index]
            readonly property var span: line.sp[kw.index]

            text: line.toks[kw.index].s
            px: kw.wp ? kw.wp.size : 40
            cx: kw.wp ? kw.wp.x : 0
            cy: kw.wp ? kw.wp.y : 0
            baseRot: kw.wp ? kw.wp.rot : 0
            litColor: line.colors[(kw.index + line.index * 2) % line.colors.length]
            pose: (kw.wp && kw.span)
                ? KM.wordAt(line.t, kw.span.from, kw.span.to, kw.wp, line.leaveAt, kw.index, line.toks.length, line.lineOnly)
                : line.idle
        }
    }

    // The diamonds that fly off a word as it is sung (two, taking turns, so a quick word
    // does not cut the one before it short).
    Burst {
        id: puffA
        count: 9
        colors: line.palette
    }

    Burst {
        id: puffB
        count: 9
        colors: line.palette
    }
}
