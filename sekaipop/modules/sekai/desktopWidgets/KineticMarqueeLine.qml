import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticMath.js" as KM
import "../../common/functions/KineticStyles.js" as KS

// One line of the Marquee look (KineticMarquee.qml): every row of the screen says this line
// (KineticMarqueeRow.qml): the big hero row in the middle follows the voice, the smaller rows
// above and below slide past as texture.
//
// When each word is sung is the card's (LyricsMath.spansFor: real word timing where a source
// has it, shared out by syllable where it only has the line). When the line leaves is
// KineticMath.leaveStart, as in the poster. A gap in the singing is three big diamonds that
// light one by one.
Item {
    id: line

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string text: ""
    property int index: 0
    property int curIndex: -1
    property real lineStart: 0
    property real lineEnd: 0
    property real nextStart: Infinity
    property bool nextIsGap: false
    property var marks: []
    property string bgText: ""
    property real bgStart: 0
    property real bgEnd: 0
    property real t: 0
    property bool lineOnly: false
    property var palette: mt.attributeColors
    // The rows of the screen (KineticStyles.marqueeRows).
    property var rows: []
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

    // When the line starts to leave (KineticMath.leaveStart).
    readonly property real leaveAt: KM.leaveStart(line.lineStart, Math.max(line.lineEnd, line.bgToks.length > 0 ? line.bgEnd : 0), line.nextStart, line.nextIsGap)

    // A guess of how wide each word is (each row chooses how many repeats of the line it is built
    // with from it) and which are ad libs.
    readonly property var ems: line.toks.map(tk => Math.max(0.3, KM.wordEm(tk.s) - 0.2))
    readonly property var adlibs: line.toks.map(tk => tk.adlib === true)

    Repeater {
        model: line.blank ? 0 : line.rows.length

        delegate: KineticMarqueeRow {
            id: mr

            required property int index

            toks: line.toks
            spans: line.sp
            ems: line.ems
            adlibs: line.adlibs
            mainCount: line.mainToks.length
            t: line.t
            lineIndex: line.index
            lineStart: line.lineStart
            leaveAt: line.leaveAt
            palette: line.palette
            sw: line.sw
            spec: line.rows[mr.index]
            rowIndex: mr.index
        }
    }

    // ===== a gap in the singing: three big diamonds =====
    readonly property real gapP: line.blank ? KM.clamp((line.t - line.lineStart) / Math.max(0.5, line.lineEnd - line.lineStart), 0, 1) : 0
    readonly property real gapAmt: (line.blank && line.index === line.curIndex)
        ? KM.clamp((line.t - line.lineStart) / 0.4, 0, 1) * KM.clamp((line.lineEnd - line.t) / 0.4, 0, 1)
        : 0

    Row {
        visible: line.gapAmt > 0.002
        anchors.centerIn: parent
        spacing: Math.round(line.sh * 0.06)
        scale: 0.4 + 0.6 * line.gapAmt
        opacity: line.gapAmt

        Repeater {
            model: 3

            delegate: DiamondDot {
                id: bead

                required property int index

                size: Math.round(line.sh * 0.055)
                lit: line.gapP >= (bead.index + 1) / 4.2
                litColor: line.palette[(bead.index * 2) % line.palette.length]
                offColor: "#ffffff"
                lineColor: line.mt.colBorder
                border.width: 4
            }
        }
    }
}
