import QtQuick
import Quickshell
import qs.modules.common
import "../../common/functions/LyricsFont.js" as LF

// One word of the Wall and Marquee looks of the whole-screen lyrics (KineticWall.qml,
// KineticMarquee.qml): flat type, not the poster's sticker.
//
//   Waiting  the word is `restColor` with a thin `restOutline` (hollow type: restColor
//            transparent; or dim solid type).
//   Singing  `litColor` fills across it as `sung` goes 0 .. 1 (the same sweep as the card's
//            words), with a thin navy edge, and an optional bar grows under it.
//
// The pose (scale, opacity, place) is the owner's: this item only draws the word, and builds
// two strings (three with the bar). The sung colour is not cut at the string's advance width
// (the tail of an s or a y would stay unlit): the clip is 0.3 em wider on every side and not
// cut at all once the word is sung, like LyricsWord.qml.
Item {
    id: word

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string text: ""
    property int px: 80
    property color litColor: mt.accentCyan
    property color restColor: "transparent"
    property color restOutline: Qt.rgba(1, 1, 1, 0.4)
    property color litOutline: mt.colBorder
    // 0 .. 1: how much of the word the colour has covered.
    property real sung: 0
    // The bar under the word, as a share of its size (0 = no bar). It grows with the colour.
    property real bar: 0

    implicitWidth: rest.implicitWidth
    implicitHeight: rest.implicitHeight
    width: implicitWidth
    height: implicitHeight
    transformOrigin: Item.Center

    Text {
        id: rest
        text: word.text
        font.family: LF.family(word.text, word.mt.fontFamily)
        font.pixelSize: word.px
        font.weight: LF.weight(word.text, Font.ExtraBold)
        font.styleName: LF.style(word.text, word.mt.fontStyleBold)
        color: word.restColor
        style: Text.Outline
        styleColor: word.restOutline
    }

    Item {
        id: fill
        readonly property real pad: Math.ceil(word.px * 0.3)
        visible: word.sung > 0.001
        clip: true
        x: -fill.pad
        y: -fill.pad
        width: word.sung >= 0.999 ? word.width + 2 * fill.pad : fill.pad + word.width * word.sung
        height: word.height + 2 * fill.pad

        Text {
            x: fill.pad
            y: fill.pad
            text: word.text
            font.family: LF.family(word.text, word.mt.fontFamily)
            font.pixelSize: word.px
            font.weight: LF.weight(word.text, Font.ExtraBold)
            font.styleName: LF.style(word.text, word.mt.fontStyleBold)
            color: word.litColor
            style: Text.Outline
            styleColor: word.litOutline
        }
    }

    Rectangle {
        visible: word.bar > 0 && word.sung > 0.001
        x: 0
        y: Math.round(word.height * 0.94)
        width: Math.round(word.width * word.sung)
        height: Math.max(3, Math.round(word.px * word.bar))
        radius: height / 2
        color: word.litColor
    }
}
