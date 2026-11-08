import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticStyles.js" as KS

// One row of one line in the Marquee look (KineticMarqueeLine.qml): a strip of the line's words
// with a diamond after each repeat, repeated end to end.
//
//   The HERO row   (spec.hero: the big one in the middle) carries the voice. Its strip does not
//                  scroll on its own: it glides so that the word that is being sung is in the
//                  middle of the screen (KineticStyles.voiceFollow, from the real widths of the
//                  words). A word is outline only until it is sung, then it is solid in ONE
//                  colour for the whole line, with a navy edge.
//   The other rows are texture: smaller, hollow, faint (spec.alpha), sliding across in turns at
//                  their own speed (KineticStyles.marqueeX). A sung word only tints them.
//   The strip      is a Row of repeats, each a Row of the words and a diamond, so every width in
//                  it is the real one. The width of one repeat (+ the gap) is the period it
//                  repeats by (so it loops with no seam).
//   Coming in      the row slides in from the side it moves away from and leaves the way it
//                  moves, one row after another (KineticStyles.marqueeAt).
Item {
    id: row

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // The line's words ({ s, adlib }) and when each is sung ({ from, to }).
    property var toks: []
    property var spans: []
    // The width of each word in ems (a guess, only used to choose how many repeats), which are ad libs,
    // and how many words are the main voice (the rest are ad libs, which the hero does not follow).
    property var ems: []
    property var adlibs: []
    property int mainCount: 0
    property real t: 0
    property int lineIndex: 0
    property real lineStart: 0
    property real leaveAt: 0
    property var palette: mt.attributeColors
    property real sw: 1920
    // This row (KineticStyles.marqueeRows).
    property var spec: ({ y: 0, rowH: 180, px: 133, dir: -1, speed: 100, seed: 0, hero: false, alpha: 0.5, kind: 0 })
    property int rowIndex: 0

    readonly property bool hero: row.spec.hero === true
    readonly property int units: KS.marqueeUnits(KS.marqueePeriod(row.ems, row.adlibs, row.spec.px), row.sw)
    readonly property real gap: Math.round(row.spec.px * KS.MARQ_GAP_EM)
    readonly property real sepW: Math.round(row.spec.px * KS.MARQ_SEP_EM)
    // The width of one repeat plus the gap before the next, measured.
    readonly property real period: row.units > 0 ? Math.max(1, (strip.implicitWidth + row.gap) / row.units) : 1
    readonly property var at: KS.marqueeAt(row.t, row.lineStart, row.leaveAt, row.rowIndex, row.spec.dir, row.sw)

    // The one colour of the sung words of the hero row, and the faint tint of the other rows.
    readonly property color heroColor: row.palette[(row.lineIndex * 2) % row.palette.length]
    readonly property color tintColor: {
        const c = row.palette[(row.lineIndex * 2 + row.rowIndex) % row.palette.length]
        return Qt.alpha(c, 0.55)
    }

    // The hero row: where the voice is along the strip (px from the left of the first repeat),
    // from where the first repeat's words really are. (Reads the clock and the strip's width so it
    // is worked out again every frame and once the words have been laid out.)
    readonly property real voiceAt: {
        const clock = row.t
        const laidOut = strip.implicitWidth
        if (!row.hero || row.mainCount === 0)
            return 0
        const first = unitsRep.itemAt(0)
        if (!first)
            return 0
        const froms = []
        const mids = []
        for (let k = 0; k < row.mainCount; k++) {
            const c = first.cells.itemAt(k)
            const sp = row.spans[k]
            if (!c || !sp)
                return 0
            froms.push(sp.from)
            mids.push(c.x + c.width / 2)
        }
        return KS.voiceFollow(froms, mids, row.t)
    }

    x: 0
    y: row.spec.y
    width: row.sw
    height: row.spec.rowH
    opacity: row.at.op * row.spec.alpha
    visible: opacity > 0.002

    Row {
        id: strip
        spacing: row.gap
        x: Math.round((row.hero
            ? KS.heroX(row.sw / 2 - row.voiceAt, row.period)
            : KS.marqueeX(row.t, row.spec.speed, row.spec.seed, row.spec.dir, row.period)) + row.at.ox)

        Repeater {
            id: unitsRep
            model: row.units

            delegate: Row {
                id: unit

                // the words of this repeat (the hero row reads where they are)
                property alias cells: cellsRep

                spacing: row.gap

                Repeater {
                    id: cellsRep
                    model: row.toks.length

                    delegate: Item {
                        id: cell

                        required property int index

                        readonly property var tk: row.toks[cell.index]
                        readonly property var span: row.spans[cell.index]

                        width: kw.width
                        height: row.spec.rowH

                        KineticFillWord {
                            id: kw
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.tk ? cell.tk.s : ""
                            px: Math.max(10, Math.round(row.spec.px * ((cell.tk && cell.tk.adlib) ? KS.MARQ_ADLIB : 1)))
                            // hero: outline only until sung, then solid in one colour with a navy edge
                            // texture: hollow, and a sung word only tints it
                            litColor: row.hero ? row.heroColor : row.tintColor
                            litOutline: row.hero ? row.mt.colBorder : "transparent"
                            restColor: row.hero ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                            restOutline: row.hero ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.6)
                            // a line that is leaving is shown full, whatever was sung of it
                            sung: row.t >= row.leaveAt ? 1 : (cell.span ? LM.sung(cell.span, row.t) : 0)
                        }
                    }
                }

                Item {
                    width: row.sepW
                    height: row.spec.rowH

                    DiamondDot {
                        anchors.centerIn: parent
                        size: Math.round(row.spec.px * 0.2)
                        lit: true
                        litColor: row.hero ? row.heroColor : row.tintColor
                        lineColor: row.mt.colBorder
                        opacity: 0.85
                    }
                }
            }
        }
    }
}
