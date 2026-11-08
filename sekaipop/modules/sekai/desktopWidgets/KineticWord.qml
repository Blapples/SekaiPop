import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/LyricsFont.js" as LF

// One word of the kinetic lyrics (LyricsKinetic.qml, KineticLine.qml).
//
//   Waiting   until it is sung the word is only a ghost: the outline of its letters, faint,
//             in the place it will land, so the whole line can be read before it is sung.
//   Slam      when it is sung the sticker (LyricsWord.qml, the same navy outline and hard
//             shadow as the desktop lyrics card) arrives from wherever its style throws it
//             from (KineticMath.motionFor), overshoots a little and settles; as it lands it
//             squashes down and a ring of its colour runs out from it.
//   Singing   the word's colour sweeps across it for as long as it is sung.
//   Leaving   when its line goes, the word flies off the way its style says.
//
// The pose (`pose`: where it is, how big, how tilted, how strong) is worked out by the
// line from the lyrics clock (KineticMath.wordAt); this item only draws it, centred on
// (cx, cy). It builds no timers and keeps nothing between frames.
Item {
    id: word

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property string text: ""
    property int px: 80
    property color litColor: mt.accentCyan
    // Where the word's middle goes and how it is tilted when it is at rest.
    property real cx: 0
    property real cy: 0
    property real baseRot: 0
    // The word's pose at this moment (KineticMath.wordAt).
    property var pose: ({ started: false, ox: 0, oy: 0, s: 1, rot: 0, op: 0, hit: 0, ring: 1, sung: 0, gone: false })

    readonly property bool resting: !word.pose.started
    readonly property bool onScreen: word.resting || word.pose.op > 0.002

    // The sticker is the biggest thing in here, so it sets the size.
    width: sticker.implicitWidth
    height: sticker.implicitHeight
    x: word.cx - word.width / 2
    y: word.cy - word.height / 2
    visible: word.onScreen

    // ===== waiting: the ghost =====
    Text {
        id: ghost
        visible: word.resting
        anchors.centerIn: parent
        text: word.text
        font.family: LF.family(word.text, word.mt.fontFamily)
        font.pixelSize: word.px
        font.weight: LF.weight(word.text, Font.ExtraBold)
        font.styleName: LF.style(word.text, word.mt.fontStyleBold)
        color: "transparent"
        style: Text.Outline
        styleColor: Qt.rgba(1, 1, 1, 0.38)
        rotation: word.baseRot
    }

    // ===== the shockwave =====
    // A ring of the word's colour, from the word's middle, getting wide and thin and gone.
    Rectangle {
        readonly property real u: word.pose.ring
        visible: u > 0.001 && u < 0.999
        anchors.centerIn: parent
        width: Math.round(word.px * (1.1 + 2.4 * u) + word.width * 0.35)
        height: width
        radius: width / 2
        color: "transparent"
        border.color: word.litColor
        border.width: Math.max(2, Math.round(word.px * 0.045 * (1 - u)))
        opacity: 0.75 * (1 - u)
        antialiasing: true
    }

    // ===== the sticker =====
    Item {
        id: holder
        width: sticker.implicitWidth
        height: sticker.implicitHeight
        visible: !word.resting
        opacity: word.pose.op
        x: parent.width / 2 - width / 2 + word.pose.ox
        y: parent.height / 2 - height / 2 + word.pose.oy
        scale: Math.max(0.001, word.pose.s)
        rotation: word.baseRot + word.pose.rot
        transformOrigin: Item.Center

        transform: Scale {
            origin.x: holder.width / 2
            origin.y: holder.height * 0.6
            xScale: 1 + 0.09 * word.pose.hit
            yScale: 1 - 0.18 * word.pose.hit
        }

        LyricsWord {
            id: sticker
            text: word.text
            pixelSize: word.px
            withFill: true
            litColor: word.litColor
            sung: word.pose.sung
        }
    }
}
