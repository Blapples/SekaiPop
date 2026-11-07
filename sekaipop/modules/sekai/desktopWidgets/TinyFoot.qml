import QtQuick
import Quickshell
import qs.modules.common

// The frame every 1 x 1 tile draws its one object in. The 1 x 1 cards have no housing, so
// each tile is a single pressable object (a calendar page, a round button, a fan of paint
// chips, the avatar) standing straight on the wallpaper. This item only gives them the
// card's footprint to stand in:
//
//   (0, 0)         the footprint's top-left corner (the card's edge, which is what the Edit
//                  Desktop grid lines up)
//   capW x capH    the raised part's room: the footprint without the hard shadow
//   shadowDy       the hard shadow's room under it (put a Pill of height `capH + shadowDy`
//                  at y 0 and its shadow lands in it)
//
// The footprint is the tile's own 120 x 94 box grown by the housing's inset on every side
// (borderWidth + outerRingWidth + 10 = 17 px, as the 2 x 2 housing has), so the card is
// 154 x 132 and four of them make one 2 x 2 (a 12 px gap between the objects when they are
// snapped to the 2 x 2's edges).
//
//   TinyFoot {
//       id: foot
//       anchors.fill: parent
//       Pill { width: foot.capW; height: foot.capH + foot.shadowDy; cornerRadius: 24 }
//   }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // How far the footprint reaches out of the tile's box on every side.
    readonly property real bleed: mt.borderWidth + mt.outerRingWidth + 10
    // The hard shadow drops straight down by the housing's own depth.
    readonly property real shadowDy: mt.shadowOffset

    readonly property real capW: root.width + root.bleed * 2
    readonly property real capH: root.height + root.bleed * 2

    default property alias content: frame.data

    Item {
        id: frame
        x: -root.bleed
        y: -root.bleed
        width: root.capW
        height: root.capH + root.shadowDy
    }
}
