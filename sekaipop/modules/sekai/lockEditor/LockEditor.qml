import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common

// The lockscreen editor's window (LockEditStage.qml is what is in it): one full-screen Overlay
// window on the monitor being edited (LockEditService.screenName), mapped only while the
// editor is open, and unbuilt (the Loader) the rest of the time, so it costs nothing.
//
//   qs -c sekaipop ipc call lockedit toggle        (also open / close)
//
// It takes the keyboard (Exclusive), like the picture framer does: Esc, Tab, the arrows and
// Delete are the editor's while it is up. While a file chooser is open for the Image widget
// the window steps aside (`picking`), or it would cover the chooser, and comes back after.
// `qs -c sekaipop ipc call lockedit close` ends it if anything ever goes wrong.
PanelWindow {
    id: win

    screen: Quickshell.screens.find(s => s.name === LockEditService.screenName) ?? Quickshell.screens[0]

    readonly property real uiScale: ShellScale.forScreen(win.screen)

    // Open, or still animating shut.
    readonly property bool shown: LockEditService.active || LockEditService.progress > 0.001

    visible: win.shown && !LockEditService.picking
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sekaipop-lock-edit"
    WlrLayershell.keyboardFocus: LockEditService.active && !LockEditService.picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Loader {
        anchors.fill: parent
        active: win.visible

        sourceComponent: LockEditStage {
            screenObj: win.screen
            uiScale: win.uiScale
        }
    }
}
