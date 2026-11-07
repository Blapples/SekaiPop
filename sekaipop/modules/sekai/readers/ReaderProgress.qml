import QtQuick
import qs.modules.common
import qs.modules.sekai.readers

// A reading-progress track in the shell's look: a pill with the navy outline, filled from the
// left with the accent gradient. `value` runs 0..1.
Item {
    id: root

    property real value: 0

    implicitHeight: 12

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceHover
        border.width: 2
        border.color: Theme.line
        antialiasing: true
    }

    Rectangle {
        x: 2
        y: 2
        height: root.height - 4
        width: Math.max(root.height - 4, (root.width - 4) * Math.max(0, Math.min(1, root.value)))
        visible: root.value > 0
        radius: height / 2
        antialiasing: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.accentMint }
            GradientStop { position: 1.0; color: Theme.accentCyan }
        }
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
}
