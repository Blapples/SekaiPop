import QtQuick
import Quickshell
import qs.modules.common
import "../../common/functions/LyricsFont.js" as LF

// One word of a lyric, drawn as a sticker with no card behind it, so it sits straight
// on the wallpaper: a navy outline all round (the string drawn eight times on a small
// circle), a hard shadow down-right of it (four copies), the colour on top, and, while the
// word is being sung, the "sung" colour sweeping across it from the left.
//
//   LyricsWord { text: "hello"; pixelSize: 38; sung: 0.4; withFill: true }
//
// It is a lighter cousin of StickerText.qml (that one draws a pale ring and a thicker
// shadow as well, 25 strings a word; this is 13, and there are a few dozen words on the
// screen at once). The item's size is the string plus the outline and the shadow, so words
// lay out in a Row like any other Item.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string text: ""
    property int pixelSize: 38
    property color fillColor: "#FFFFFF"
    property color litColor: mt.accentCyan
    property color outlineColor: mt.colBorder
    // 0 .. 1: how much of the word the sung colour has covered. Only drawn when `withFill`.
    property real sung: 0
    // Build the layer that holds the sung colour. Left off for words that are not being
    // sung, which saves a string each.
    property bool withFill: false

    readonly property real outline: Math.max(2.5, root.pixelSize * 0.085)
    readonly property real shadowDx: Math.max(2, root.pixelSize * 0.06)
    readonly property real shadowDy: Math.max(3, root.pixelSize * 0.09)
    readonly property real edge: Math.ceil(root.outline) + 1

    // The string is measured by the colour layer below (`ink`): it is the same string in the
    // same font, so it is the same size, and no extra text item is kept just to measure it.
    implicitWidth: Math.ceil(ink.implicitWidth + 2 * root.edge + root.shadowDx)
    implicitHeight: Math.ceil(ink.implicitHeight + 2 * root.edge + root.shadowDy)

    component Glyphs: Text {

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)
        text: root.text
        font.family: LF.family(root.text, mt.fontFamily)
        font.pixelSize: root.pixelSize
        font.weight: LF.weight(root.text, Font.ExtraBold)
        font.styleName: LF.style(root.text, mt.fontStyleBold)
    }

    Item {
        id: box
        x: root.edge
        y: root.edge
        width: ink.implicitWidth
        height: ink.implicitHeight

        // the hard shadow
        Repeater {
            model: 4

            Glyphs {
                required property int index
                x: root.shadowDx + (index % 2 === 0 ? -1 : 1) * root.outline * 0.7
                y: root.shadowDy + (index < 2 ? -1 : 1) * root.outline * 0.7
                color: root.outlineColor
            }
        }

        // the outline
        Repeater {
            model: 8

            Glyphs {
                required property int index
                x: Math.cos(index * Math.PI / 4) * root.outline
                y: Math.sin(index * Math.PI / 4) * root.outline
                color: root.outlineColor
            }
        }

        // the colour
        Glyphs {
            id: ink
            color: root.fillColor
        }

        // the sung colour, swept in from the left. The clip is wider than the string on every
        // side (`pad`): a letter's ink can reach past its advance width (the tail of an s or
        // a y, an f, a swash), and a clip cut at the advance left a white sliver of the word
        // uncoloured, even at 100 %. The sweep's moving edge is still exactly at
        // sung x the string's width; once the word is sung nothing is cut at all.
        Item {
            id: fillClip
            readonly property real pad: Math.ceil(root.pixelSize * 0.3)
            readonly property real k: Math.max(0, Math.min(1, root.sung))
            visible: root.withFill && root.sung > 0.001
            x: -fillClip.pad
            y: -fillClip.pad
            width: fillClip.k >= 0.999 ? box.width + 2 * fillClip.pad : Math.round(box.width * fillClip.k) + fillClip.pad
            height: box.height + 2 * fillClip.pad
            clip: true

            Glyphs {
                x: fillClip.pad
                y: fillClip.pad
                color: root.litColor
            }
        }
    }
}
