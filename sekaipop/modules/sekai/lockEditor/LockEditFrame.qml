import QtQuick
import Quickshell
import qs.services
import qs.modules.common

// The frame round the lockscreen card: navy outline, white ring, navy outline, on a hard
// shadow down and to the right. Exactly Edit Desktop's (EditFrame.qml and EditBackdrop.qml).
//
// The rings must be drawn ON TOP of the card: they are thick enough to hide the card's square
// corners, so only the rounded hole shows the picture. The shadow is a filled shape and must
// be UNDER it. So the stage uses this twice, one for each:
//
//   LockEditFrame { drawRings: false; ... }    before the card (the shadow)
//   LockEditFrame { drawShadow: false; ... }   after the card (the rings)
//
//   LockEditFrame { cardX: ...; cardY: ...; cardW: ...; cardH: ...; uiScale: ...; grow: ... }
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property real uiScale: 1
    // Where the card is, in this item's pixels.
    property real cardX: 0
    property real cardY: 0
    property real cardW: 0
    property real cardH: 0
    // 0 -> 1 as the card shrinks into place: the frame grows from nothing with it, like Edit
    // Desktop's (a ring at full thickness round a full-screen card would be off the screen).
    property real grow: 1
    property bool drawShadow: true
    property bool drawRings: true

    readonly property real frame: EditMode.frameWidth * root.uiScale * Math.min(1, Math.max(0, root.grow))
    readonly property real line: Math.min(3 * root.uiScale, root.frame / 4)
    readonly property real cardR: EditMode.cardRadius * root.uiScale

    // The hard shadow.
    Rectangle {
        visible: root.drawShadow
        x: root.cardX - root.frame + 9 * root.uiScale
        y: root.cardY - root.frame + 11 * root.uiScale
        width: root.cardW + root.frame * 2
        height: root.cardH + root.frame * 2
        radius: root.cardR + root.frame
        color: Qt.darker(root.mt.colBorder, 3.6)
        antialiasing: true
    }

    // The white ring (drawn first, so the two outlines sit on top of its edges).
    Rectangle {
        visible: root.drawRings
        readonly property real to: root.frame - root.line
        x: root.cardX - to
        y: root.cardY - to
        width: root.cardW + to * 2
        height: root.cardH + to * 2
        radius: root.cardR + to
        color: "transparent"
        border.width: Math.max(0, to - root.line)
        border.color: root.mt.pRingWhite
        antialiasing: true
    }

    // The inner navy outline, against the picture.
    Rectangle {
        visible: root.drawRings
        readonly property real to: root.line
        x: root.cardX - to
        y: root.cardY - to
        width: root.cardW + to * 2
        height: root.cardH + to * 2
        radius: root.cardR + to
        color: "transparent"
        border.width: to
        border.color: root.mt.colBorder
        antialiasing: true
    }

    // The outer navy outline.
    Rectangle {
        visible: root.drawRings
        readonly property real to: root.frame
        x: root.cardX - to
        y: root.cardY - to
        width: root.cardW + to * 2
        height: root.cardH + to * 2
        radius: root.cardR + to
        color: "transparent"
        border.width: root.line
        border.color: root.mt.colBorder
        antialiasing: true
    }
}
