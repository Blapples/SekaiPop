// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import qs.modules.sekai.readers

// A Rectangle that knows whether the pointer is over it. Replaces the
// `Rectangle { ... MouseArea { id: ma; hoverEnabled: true } }` +
// `ma.containsMouse ? a : b` pairing that was written out ~96 times.
//
// The MouseArea is declared first so anything the call site adds renders above it,
// and a nested interactive child still wins the event.
Rectangle {
    id: root

    property alias hovered: mouse.containsMouse
    property alias pressed: mouse.containsPress
    property alias cursorShape: mouse.cursorShape
    property alias acceptedButtons: mouse.acceptedButtons
    property alias propagateComposedEvents: mouse.propagateComposedEvents
    // Set false for a hover-only surface that must let clicks through.
    property bool interactive: true

    signal clicked(var mouse)
    signal entered
    signal exited


    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        onClicked: m => root.clicked(m)
        onEntered: root.entered()
        onExited: root.exited()
    }
}
