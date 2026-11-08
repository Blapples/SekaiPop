import QtQuick
import Quickshell
import qs.modules.common
import "../../common/functions/LyricsMath.js" as LM
import "../../common/functions/KineticMath.js" as KM
import "../../common/functions/KineticStyles.js" as KS

// The Wall look of the whole-screen lyrics (LyricsKinetic.qml builds it when
// Settings -> Lyrics -> Whole screen style is "Wall", `ipc lyrics style wall`).
//
//   The wall    every line of the song is a block of giant type on ONE huge wall, stacked down
//               it, each against the left, the right or the middle (KineticStyles.wallPlan).
//   The camera  flies from WORD to word: it pushes in on the word that is being sung (about half
//               of the screen's width, never more than twice what its line needs) and sets off a
//               moment before the word, so it has arrived as it starts (KineticStyles.wallFollow,
//               from where the words really are). The moves add up, so words in a row blend into
//               one glide instead of jumping. A line with nothing sung (a gap) is a point at its
//               middle.
//   The tilt    the whole wall is turned a couple of degrees, and swings a little more while the
//               camera is moving (KineticStyles.wallRoll). Still (Settings -> Whole screen
//               camera) stops the swing and the slow zoom on top: the flight is the look.
//   The depth   the lines round the one that is on are smaller and blurrier the further they are
//               (KineticStyles.wallDepth) and dimmer (KineticStyles.wallShade).
//   The light   in the line that is on only the word that is sung is bright: the ones sung
//               already are coloured and dimmer, the ones to come faint. A soft band of light
//               lies behind the middle of the screen.
//
// The words, their timing and the clock are LyricsKinetic.qml's. Only the lines next to the
// one that is on are built (a long song costs nothing).
Item {
    id: wall

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
    // The slow zoom on top of the flight between lines.
    property bool drift: true
    property var palette: mt.attributeColors
    property real sw: 1920
    property real sh: 1080
    // 0 .. 1: fades in and out as a whole.
    property real reveal: 1

    width: wall.sw
    height: wall.sh
    opacity: wall.reveal
    visible: opacity > 0.002

    readonly property int curIndex: LM.lineIndexAt(wall.lines, wall.t)
    // How many lines each side of the one that is on are built.
    readonly property int reach: 6

    // What the plan needs to know of a line: how wide each word is, which are ad libs.
    function describe(l) {
        const main = LM.tokens(l.text)
        const bg = (l.bg && l.bg.text) ? LM.tokens(l.bg.text) : []
        const toks = main.concat(bg.map(tk => ({ s: tk.s, adlib: true })))
        return {
            blank: toks.length === 0,
            ems: toks.map(tk => Math.max(0.3, KM.wordEm(tk.s) - 0.2)),
            adlib: toks.map(tk => tk.adlib === true)
        }
    }

    readonly property var plan: KS.wallPlan(wall.lines.map(l => wall.describe(l)), wall.sw, wall.sh)

    // The line that is built for line i (null while it is not).
    function lineItem(i) {
        const it = linesRep.itemAt(i)
        return (it && it.item) ? it.item : null
    }

    // The camera's waypoints: one at each word being sung of the lines round the one that is on
    // (where the word REALLY is, measured on the built line), one at the middle of a gap. Lines that
    // are not built yet are a point at their middle.
    function waypoints() {
        const out = []
        const lo = Math.max(0, wall.curIndex - 2)
        const hi = Math.min(wall.lines.length - 1, wall.curIndex + 3)
        for (let i = lo; i <= hi; i++) {
            const blk = wall.plan.lines[i]
            if (!blk || wall.starts[i] === undefined)
                continue
            const lz = Math.log(blk.zoom)
            const it = blk.blank ? null : wall.lineItem(i)
            let any = false
            if (it) {
                for (let k = 0; k < it.mainCount; k++) {
                    const c = it.center(k)
                    const sp = it.sp[k]
                    if (!c || !sp)
                        continue
                    out.push({ t: sp.from, x: blk.x0 + c.x, y: blk.y0 + c.y, lz: Math.log(KS.wallWordZoom(c.w, blk.zoom, wall.sw)) })
                    any = true
                }
            }
            if (!any)
                out.push({ t: wall.starts[i], x: blk.cx, y: blk.cy, lz: lz })
        }
        out.sort((a, b) => a.t - b.t)
        return out
    }

    // Where the camera is: { x, y, z } the world point on the middle of the screen and the zoom,
    // and `roll`, how much the wall swings (degrees; the base tilt is added by the rig).
    readonly property var cam: {
        const pts = wall.waypoints()
        if (pts.length === 0) {
            const c0 = KS.wallCamera(wall.plan, wall.starts, wall.t, wall.drift)
            return { x: c0.x, y: c0.y, z: c0.z, roll: 0 }
        }
        const c = KS.wallFollow(pts, wall.t, KS.WALL_WLEAD, KS.WALL_WMOVE)
        let roll = 0
        if (wall.drift) {
            // the speed of the camera across the screen, from a step back in time
            const p = KS.wallFollow(pts, wall.t - 0.05, KS.WALL_WLEAD, KS.WALL_WMOVE)
            roll = KS.wallRoll((c.x * c.z - p.x * p.z) / 0.05)
        }
        return { x: c.x, y: c.y, z: c.z * (wall.drift ? KS.drift(wall.starts, wall.t) : 1), roll: roll }
    }

    // A soft band of light behind the middle of the screen, where the line that is on sits.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: wall.sw
        height: Math.round(wall.sh * 0.46)

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.075) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    // ===== the wall =====
    // The rig turns the whole wall about the middle of the screen (the tilt, and its swing).
    Item {
        id: rig
        width: wall.sw
        height: wall.sh
        transformOrigin: Item.Center
        rotation: KS.WALL_TILT + wall.cam.roll

        // The camera moves this: its top left corner is the wall's, so a point of the wall lands
        // at (x * zoom + this.x, y * zoom + this.y).
        Item {
            id: world
            transformOrigin: Item.TopLeft
            scale: wall.cam.z
            x: wall.sw / 2 - wall.cam.x * wall.cam.z
            y: wall.sh / 2 - wall.cam.y * wall.cam.z

            Repeater {
                id: linesRep
                model: wall.lines.length

                delegate: Loader {
                    id: slot

                    required property int index

                    readonly property var block: wall.plan.lines[slot.index]

                    active: slot.block !== undefined && Math.abs(slot.index - wall.curIndex) <= wall.reach
                    x: slot.block ? slot.block.x0 : 0
                    y: slot.block ? slot.block.y0 : 0

                    sourceComponent: KineticWallLine {
                        readonly property var src: wall.lines[slot.index]

                        text: src ? src.text : ""
                        index: slot.index
                        curIndex: wall.curIndex
                        lineStart: src ? src.t : 0
                        lineEnd: wall.ends[slot.index] ?? 0
                        nextStart: slot.index + 1 < wall.lines.length ? wall.lines[slot.index + 1].t : Infinity
                        marks: (src && src.marks) ? src.marks : []
                        bgText: (src && src.bg) ? src.bg.text : ""
                        bgStart: (src && src.bg) ? src.bg.t : 0
                        bgEnd: wall.bgEnds[slot.index] ?? 0
                        t: wall.t
                        lineOnly: wall.lineOnly
                        palette: wall.palette
                        block: slot.block
                    }
                }
            }
        }
    }
}
