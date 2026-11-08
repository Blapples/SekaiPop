import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.sekai.readers

// Hides the mouse cursor while a chapter is on screen and the pointer rests (the novel reader;
// the manga reader does the same inline in MangaReader.qml).
//
// While `active` is true, Hyprland hides a cursor that rests for a couple of seconds and shows
// it on the next move (scripts/hyprland/reader-cursor.sh). It is Hyprland's doing because the
// reader cannot do it alone: an app's blank cursor only takes effect when the pointer next
// moves. The setting is put back when `active` turns false, or when the reader goes away.
// (It is Hyprland's global setting, so it also hides the cursor over other windows for as
// long as a chapter is up.)
//
//   ReaderCursorHider { active: root.open && !root.minimized && root.hideHeader }
Item {
    id: root

    property bool active: false

    width: 0
    height: 0
    visible: false

    readonly property string cursorScript: Directories.script("hyprland/reader-cursor.sh")
    property bool _applied: false

    onActiveChanged: timer.restart()

    // Debounced: switching between the Browse and Library tabs turns one reader off and the
    // other on within the same moment, and only the end state should reach Hyprland.
    Timer {
        id: timer
        interval: 250
        onTriggered: {
            if (root.active === root._applied)
                return
            root._applied = root.active
            Quickshell.execDetached(["sh", root.cursorScript, root.active ? "on" : "off"])
        }
    }

    Component.onDestruction: {
        if (root._applied)
            Quickshell.execDetached(["sh", root.cursorScript, "off"])
    }
}
