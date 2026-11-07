import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The bar that floats over a chapter while it is read: the shell's flat card (outline, inner
// ring in the dark modes, hard shadow) as a rounded capsule. Tapping the page hides it by
// sliding it up out of the way (`shown`). What goes in it is laid out by the caller, inside
// the card:
//
//   ReaderBar {
//       anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
//       shown: headerVisible
//       RowLayout { anchors { fill: parent; leftMargin: 8; rightMargin: 12 } ... }
//   }
Item {
    id: root

    property bool shown: true
    // Sits at the bottom edge: it leaves downwards instead of upwards.
    property bool atBottom: false
    default property alias content: inner.data

    implicitHeight: 50 + Theme.shadowOffset
    opacity: root.shown ? 1 : 0
    visible: root.opacity > 0.01

    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    transform: Translate {
        y: root.shown ? 0 : (root.atBottom ? 1 : -1) * (root.height + 10)
        Behavior on y {
            NumberAnimation {
                duration: root.shown ? 300 : 170
                easing.type: root.shown ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.4
            }
        }
    }

    Pill {
        anchors.fill: parent
        cornerRadius: 17
        ringWidth: Theme.borderWidth
        innerRing: Theme.cardRing
        fillColor: Theme.surface

        Item {
            id: inner
            anchors.fill: parent
        }
    }
}
