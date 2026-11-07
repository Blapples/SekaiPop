// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import qs.modules.sekai.readers
import qs.modules.common.widgets

// Round icon-only button that tints its background on hover.
ClickableRect {
    id: root

    property string icon: ""
    property int iconSize: 16
    property color iconColor: Colors.on_surface_variant
    property color hoverColor: Colors.surface_container_highest
    property color idleColor: "transparent"

    implicitWidth: 30
    implicitHeight: 30
    radius: root.width / 2
    color: root.hovered ? root.hoverColor : root.idleColor

    MaterialIcon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        color: root.iconColor
    }
}
