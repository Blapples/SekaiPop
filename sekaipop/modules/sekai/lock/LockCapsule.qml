import QtQuick
import qs.modules.common

// The dark rounded capsule the small lockscreen widgets sit on (the same colours as the
// Gacha look's battery and "Locked since" capsules). Give it a width and a height; put
// what it holds inside.
Rectangle {
    radius: height / 2
    color: LockPalette.cap
    border.width: 1
    border.color: LockPalette.panelEdge
    antialiasing: true
}
