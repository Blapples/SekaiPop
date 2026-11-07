// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Shapes
import qs.modules.sekai.readers

// The indeterminate loading ring: an arc that grows and shrinks as it chases
// round a faint track. Set `width` to resize; height and radius follow.
// `border.width` sets both strokes, `border.color` tints the track and
// `arcColor` the arc.
Rectangle {
    id: root

    // One full turn of the ring.
    property int duration: 800
    property alias running: spin.running
    property color arcColor: Colors.primary

    width: 28
    height: root.width
    radius: root.width / 2
    color: "transparent"
    border.color: Colors.withAlpha(root.arcColor, 0.16)
    border.width: 2

    // Each grow/shrink cycle leaves the arc's tail 220° further on; this
    // turns the arc by that much so the restart doesn't jump (18 × 220° is a
    // whole number of turns).
    property int _cycle: 0

    Shape {
        anchors.fill: parent
        rotation: root._cycle * 220
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.arcColor
            strokeWidth: root.border.width
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                id: arc
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.border.width) / 2
                radiusY: arc.radiusX
                startAngle: -90
                sweepAngle: 30
            }
        }
    }

    RotationAnimator on rotation {
        id: spin
        from: 0
        to: 360
        duration: root.duration
        loops: Animation.Infinite
        running: root.visible
        easing.type: Easing.Linear
    }

    SequentialAnimation {
        running: spin.running
        loops: Animation.Infinite

        // Grow: the head runs ahead of a fixed tail…
        NumberAnimation {
            target: arc; property: "sweepAngle"
            from: 30; to: 250
            duration: root.duration * 0.9
            easing.type: Easing.InOutCubic
        }
        // …then shrink: the tail catches up with a fixed head.
        ParallelAnimation {
            NumberAnimation {
                target: arc; property: "startAngle"
                from: -90; to: 130
                duration: root.duration * 0.9
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                target: arc; property: "sweepAngle"
                from: 250; to: 30
                duration: root.duration * 0.9
                easing.type: Easing.InOutCubic
            }
        }
        ScriptAction {
            script: {
                arc.startAngle = -90
                root._cycle = (root._cycle + 1) % 18
            }
        }
    }
}
