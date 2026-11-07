import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.sekai.readers

// The slim round scroll bar of the shell (SekaiScrollBar's ring grey), as a ScrollBar for
// the lists and grids of the readers.
ScrollBar {
    id: root

    property real thickness: 6
    property real handleRadius: 3
    property color handleColor: Theme.surfaceRing
    property real handleOpacity: 1

    policy: ScrollBar.AsNeeded

    contentItem: Rectangle {
        implicitWidth: root.thickness
        radius: root.handleRadius
        color: root.handleColor
        opacity: root.handleOpacity
        antialiasing: true
    }
}
