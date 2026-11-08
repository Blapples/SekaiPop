import QtQuick
import Quickshell
import qs.modules.common
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticMath.js" as KM
import "../../common/functions/KineticStyles.js" as KS

// The Marquee look of the whole-screen lyrics (LyricsKinetic.qml builds it when
// Settings -> Lyrics -> Whole screen style is "Marquee", `ipc lyrics style marquee`).
//
//   The rows    five rows (three on a short screen; KineticStyles.marqueeRows), each a strip of
//               type saying the line that is being sung, repeated end to end. The one in the
//               middle is the HERO: it is the biggest, and it glides so that the word that is
//               being sung is in the middle of the screen. The others are smaller the further
//               they are from it, hollow and faint, and slide across the screen in turns, each
//               at its own speed. Everything moves with the lyrics clock, so it stops with the
//               music.
//   The voice   a word is outline only until it is sung; then the hero's word fills with ONE
//               colour for the whole line (the other rows are only tinted). The colour fills
//               across the word as it is sung.
//   The band    a darker band lies behind the hero row, so the words read on any wallpaper.
//   The line    a new line's rows slide in from the side they move away from, one after the
//               other, and the old line's rows leave the way they move (KineticMarqueeRow.qml).
//   The camera  a hair of slow zoom over each line and back over the next, or none (Settings ->
//               Whole screen camera: Still). Nothing pulses with the words.
//
// The words, their timing and the clock are LyricsKinetic.qml's. Only the line that is on and
// the ones next to it are built.
Item {
    id: mq

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // The song: LyricsService.lines, when each line starts, and when it has been sung by
    // (LyricsKinetic.lineStarts / lineEnds / lineBgEnds).
    property var lines: []
    property var starts: []
    property var ends: []
    property var bgEnds: []
    // The lyrics clock.
    property real t: 0
    property bool lineOnly: false
    property bool drift: true
    property var palette: mt.attributeColors
    property real sw: 1920
    property real sh: 1080
    // 0 .. 1: fades in and out as a whole.
    property real reveal: 1

    width: mq.sw
    height: mq.sh
    opacity: mq.reveal
    visible: opacity > 0.002

    readonly property int curIndex: LM.lineIndexAt(mq.lines, mq.t)
    readonly property var rows: KS.marqueeRows(mq.sw, mq.sh)

    Item {
        id: stage
        width: mq.sw
        height: mq.sh
        transformOrigin: Item.Center
        scale: mq.drift ? KS.drift(mq.starts, mq.t) : 1

        // A darker band behind the hero row.
        Rectangle {
            readonly property var hr: mq.rows.find(r => r.hero) ?? mq.rows[0]

            visible: hr !== undefined
            y: hr ? Math.round(hr.y - hr.rowH * 0.12) : 0
            width: mq.sw
            height: hr ? Math.round(hr.rowH * 1.24) : 0

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(mq.mt.colBorder.r, mq.mt.colBorder.g, mq.mt.colBorder.b, 0) }
                GradientStop { position: 0.22; color: Qt.rgba(mq.mt.colBorder.r, mq.mt.colBorder.g, mq.mt.colBorder.b, 0.55) }
                GradientStop { position: 0.78; color: Qt.rgba(mq.mt.colBorder.r, mq.mt.colBorder.g, mq.mt.colBorder.b, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(mq.mt.colBorder.r, mq.mt.colBorder.g, mq.mt.colBorder.b, 0) }
            }
        }

        Repeater {
            id: linesRep
            model: mq.lines.length

            delegate: Loader {
                id: slot

                required property int index

                active: Math.abs(slot.index - mq.curIndex) <= 1

                sourceComponent: KineticMarqueeLine {
                    readonly property var src: mq.lines[slot.index]

                    text: src ? src.text : ""
                    index: slot.index
                    curIndex: mq.curIndex
                    lineStart: src ? src.t : 0
                    lineEnd: mq.ends[slot.index] ?? 0
                    nextStart: slot.index + 1 < mq.lines.length ? mq.lines[slot.index + 1].t : Infinity
                    nextIsGap: slot.index + 1 < mq.lines.length && mq.lines[slot.index + 1].text === ""
                    marks: (src && src.marks) ? src.marks : []
                    bgText: (src && src.bg) ? src.bg.text : ""
                    bgStart: (src && src.bg) ? src.bg.t : 0
                    bgEnd: mq.bgEnds[slot.index] ?? 0
                    t: mq.t
                    lineOnly: mq.lineOnly
                    palette: mq.palette
                    rows: mq.rows
                    sw: mq.sw
                    sh: mq.sh
                }
            }
        }
    }
}
