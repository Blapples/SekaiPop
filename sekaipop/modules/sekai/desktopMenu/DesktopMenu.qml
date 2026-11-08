import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The menu you get by right-clicking the desktop (the right-click itself is
// caught in WallpaperLayer.qml, which asks EditMode to open this):
//
//   Edit Desktop      start Edit Desktop (see services/EditMode.qml)
//   Unpin images      only while a picture is pinned in front of the windows (right-click
//                     a picture on the desktop to pin it): puts them all back. A pinned
//                     picture takes no clicks, so this is how you reach it again.
//                     (There is no "add a picture" row: pictures are added from Edit
//                     Desktop's shelf, and dropped onto their frame.)
//   ----
//   Wallpapers        the wallpaper picker (same as Ctrl+Super+T)
//   Group themes      Edit Desktop's THEME tab (same as Ctrl+Shift+T)
//
// Same card as the tray's right-click menu: white face, navy outline, hard
// shadow, rows that light up under the pointer, and the same bouncy pop-in.
// One window for the whole shell, put on whichever monitor was clicked.
//
// It is a full-screen transparent Overlay window, only while it is open, so
// that a click anywhere else (left, right or middle) can close it. Esc closes
// it too once it has the keyboard (Quickshell only hands that over on a click
// for an OnDemand window, so a click-away is the sure way).
PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    readonly property string wantedScreen: EditMode.menuScreen
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? Quickshell.screens[0]

    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real roomW: win.width / win.uiScale
    readonly property real roomH: win.height / win.uiScale

    visible: EditMode.menuOpen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sekaipop-desktop-menu"
    WlrLayershell.keyboardFocus: EditMode.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The same command the README's keybinds use, so these two rows behave
    // exactly like pressing the keys.
    function ipc(target: string, fn: string): void {
        Quickshell.execDetached(["qs", "-c", "sekaipop", "ipc", "call", target, fn])
    }

    // Click anywhere outside the card: close.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: EditMode.closeMenu()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: EditMode.closeMenu()
    }

    onVisibleChanged: {
        if (win.visible)
            card.pop()
    }

    ScaleHost {
        anchors.fill: parent
        factor: win.uiScale

        Pill {
            id: card

            // Opens with its top-left corner at the pointer, pushed back in
            // when that would hang off the screen.
            x: Math.max(8, Math.min(EditMode.menuX / win.uiScale, win.roomW - card.width - 8))
            y: Math.max(8, Math.min(EditMode.menuY / win.uiScale, win.roomH - card.height - 8))

            readonly property real innerWidth: 204

            cornerRadius: mt.radiusOuter
            ringWidth: mt.borderWidth
            // Dark and Darker: the white (dim grey) inner ring just inside the
            // outline, like the bar's popups and pills. 0 in Light.
            innerRing: mt.cardRing
            fillColor: mt.surface
            implicitWidth: card.innerWidth + 10 + card.ringWidth * 2
            implicitHeight: col.implicitHeight + 2 + card.ringWidth * 2 + mt.shadowOffset
            width: implicitWidth
            height: implicitHeight

            // Pop-in: fades up and scales from the pointer, with a little
            // overshoot (the same motion as the tray menu).
            property real popProgress: 1

            function pop() {
                popAnim.restart()
            }

            SequentialAnimation {
                id: popAnim
                ScriptAction { script: card.popProgress = 0 }
                PauseAnimation { duration: 40 }
                NumberAnimation {
                    target: card
                    property: "popProgress"
                    from: 0
                    to: 1
                    duration: 260
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.4
                }
            }

            opacity: Math.min(1, card.popProgress * 3)
            transform: Scale {
                origin.x: 0
                origin.y: 0
                xScale: 0.86 + 0.14 * card.popProgress
                yScale: 0.86 + 0.14 * card.popProgress
            }

            Column {
                id: col
                x: 5
                y: 1
                width: card.innerWidth

                TrayMenuRow {
                    width: col.width
                    text: "Edit Desktop"
                    onClicked: EditMode.open(EditMode.menuScreen)

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "edit"
                        size: 18
                        weight: 600
                        color: mt.ink
                    }
                }

                TrayMenuRow {
                    width: col.width
                    text: "Edit lockscreen"
                    onClicked: {
                        const screen = EditMode.menuScreen
                        EditMode.closeMenu()
                        LockEditService.open(screen)
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "lock"
                        size: 18
                        weight: 600
                        color: mt.ink
                    }
                }

                TrayMenuRow {
                    width: col.width
                    visible: ImageService.anyPinned
                    text: "Unpin images"
                    onClicked: {
                        EditMode.closeMenu()
                        ImageService.setAllPinned(false)
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "keep_off"
                        size: 18
                        weight: 600
                        color: mt.ink
                    }
                }

                TrayMenuRow {
                    width: col.width
                    separator: true
                }

                TrayMenuRow {
                    width: col.width
                    text: "Wallpapers"
                    onClicked: {
                        EditMode.closeMenu()
                        win.ipc("wallpaperpicker", "toggle")
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "wallpaper"
                        size: 18
                        weight: 600
                        color: mt.ink
                    }
                }

                TrayMenuRow {
                    width: col.width
                    text: "Group themes"
                    onClicked: {
                        EditMode.closeMenu()
                        win.ipc("theme", "toggle")
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "palette"
                        size: 18
                        weight: 600
                        color: mt.ink
                    }
                }
            }
        }
    }
}
