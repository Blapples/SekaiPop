import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import QtQuick.Effects
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticMath.js" as KM
import "../../common/functions/KineticStyles.js" as KS

// One line of the Wall look (KineticWall.qml): a block of type at its place on the wall.
//
// The block's size, its rows and where it sits come from KineticStyles.wallPlan(); the words are
// laid out here, row by row, from their real widths. Words are dim solid type until they are
// sung; the colour fills across each as it is sung (the timing is the card's:
// LyricsMath.spansFor); a line that has been sung stays coloured, dimmed, and a line yet to come
// is dim white. How bright the whole block is follows the camera: full while it is the one that
// is on, dimmer the further it is from it (KineticStyles.wallShade).
//
// In the line that is on only the word that is sung is bright: the words sung already are
// coloured and a little dimmer, the ones to come faint (KineticStyles.wordGlow). The lines round it
// are smaller and blurrier the further they are (KineticStyles.wallDepth). The camera asks
// where each word really is (`center`).
//
// Everything is worked out from the lyrics clock `t`, so a pause freezes the picture and a seek
// puts it where it should be. A gap in the singing (an intro, an instrumental part) is a block
// of three diamonds that light one by one.
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
    property var marks: []
    property string bgText: ""
    property real bgStart: 0
    property real bgEnd: 0
    property real t: 0
    // Word by word off: the whole line lands at once.
    property bool lineOnly: false
    property var palette: mt.attributeColors
    // This line's block (KineticStyles.wallBlock).
    property var block: ({ blank: true, size: 40, rowH: 44, w: 0, h: 44, align: 2, rows: [], rowW: [], words: [], zoom: 1 })

    width: line.block.w
    height: line.block.h

    // ===== depth: smaller and blurrier the further from the line that is on =====
    readonly property var depth: KS.wallDepth(line.index - line.curIndex)
    transformOrigin: Item.Center
    scale: line.depth.scale
    layer.enabled: line.depth.blur > 0 && Math.abs(line.index - line.curIndex) <= 3
    layer.smooth: true
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 28
        blur: line.depth.blur * 0.55
    }

    // ===== where the words are (for the camera) =====
    // The cell of each word of the line, k -> Item (the cells register themselves).
    property var cells: ({})
    readonly property int mainCount: line.mainToks.length

    // Where the middle of word k is in this line, and how big it is: { x, y, w, h } (null while
    // the word is not laid out).
    function center(k) {
        const c = line.cells[k]
        if (!c)
            return null
        const p = c.mapToItem(line, c.width / 2, c.height / 2)
        return { x: p.x, y: p.y, w: c.width, h: c.height }
    }

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

    // ===== how bright =====
    readonly property real spot: KS.wallFocus(line.t, line.lineStart, line.nextStart)
    opacity: KS.wallShade(line.index - line.curIndex, line.spot)

    // A gap in the singing: how far through it we are.
    readonly property real gapP: line.blank ? KM.clamp((line.t - line.lineStart) / Math.max(0.5, line.lineEnd - line.lineStart), 0, 1) : 0

    Item {
        id: rowsHost
        visible: !line.blank
        width: line.width
        height: line.height

        Repeater {
            model: line.blank ? 0 : line.block.rows.length

            delegate: Row {
                id: rowItem

                required property int index

                readonly property var members: line.block.rows[rowItem.index] ?? []

                spacing: Math.round(line.block.size * KS.WALL_GAP_EM)
                y: rowItem.index * line.block.rowH
                height: line.block.rowH
                x: line.block.align === 0 ? 0
                    : (line.block.align === 1 ? Math.round(line.block.w - rowItem.width) : Math.round((line.block.w - rowItem.width) / 2))

                Repeater {
                    model: rowItem.members.length

                    delegate: Item {
                        id: cell

                        required property int index

                        readonly property int k: rowItem.members[cell.index]
                        readonly property var tk: line.toks[cell.k]
                        readonly property var span: line.sp[cell.k]

                        width: kw.width
                        height: line.block.rowH

                        Component.onCompleted: line.cells[cell.k] = cell
                        Component.onDestruction: delete line.cells[cell.k]

                        // in the line that is on only the word that is sung is bright
                        readonly property real glow: cell.span ? KS.wordGlow(cell.span.from, cell.span.to, line.t) : 0
                        readonly property real base: kw.sung >= 0.999 ? 0.6 : 0.32
                        opacity: line.index === line.curIndex ? cell.base + (1 - cell.base) * cell.glow : 1

                        KineticFillWord {
                            id: kw
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.tk ? cell.tk.s : ""
                            px: Math.max(10, Math.round(line.block.size * ((cell.tk && cell.tk.adlib) ? KS.WALL_ADLIB : 1)))
                            litColor: line.palette[(cell.k + line.index * 2) % line.palette.length]
                            restColor: Qt.rgba(1, 1, 1, 0.55)
                            restOutline: "transparent"
                            bar: 0.045
                            sung: cell.span ? LM.sung(cell.span, line.t) : 0
                            // a word that has just been sung pops a little
                            scale: 1 + 0.14 * (cell.span ? LM.hit(line.sp, cell.k, line.t) : 0)
                        }
                    }
                }
            }
        }
    }

    // ===== a gap: three diamonds =====
    Row {
        visible: line.blank
        anchors.centerIn: parent
        spacing: Math.round(line.block.size * 0.5)

        Repeater {
            model: 3

            delegate: DiamondDot {
                id: bead

                required property int index

                size: Math.round(line.block.size * 0.42)
                lit: line.gapP >= (bead.index + 1) / 4.2
                litColor: line.palette[(bead.index * 2) % line.palette.length]
                offColor: "#ffffff"
                lineColor: line.mt.colBorder
                border.width: 4
            }
        }
    }
}
