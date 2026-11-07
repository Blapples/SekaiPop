pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The manga reader (left) and the novel reader (right) as side panels over the desktop.
// Ported from dhrruvsharma/shell (GPL-3.0-or-later): the readers' QML and their Python backends
// are theirs, re-coloured from SekaiPop's theme (Colors.qml) and started from here.
//
// Nothing is built or run until a panel is opened: each one is loaded on its first toggle and
// put away in one of two ways (the two keys in the panel's header):
//
//   minimize  the card shrinks into the screen edge and the panel stays loaded, so the reader and
//             its backend keep running in the background. There is no tab to click: the only way
//             back is the shortcut (toggle / show), which grows the card out of the edge again.
//   close     the card shrinks into the edge and the panel is unloaded shortly after, which stops
//             the reader and its backend completely.
//
// The backends (scripts/readers) start with the panel and listen on 127.0.0.1 only
// (manga 5150, novel 5151).
//
//   qs -c sekaipop ipc call mangareader toggle | show | hide | minimize | close
//   qs -c sekaipop ipc call novelreader toggle | show | hide | minimize | close
//
// `toggle` opens the panel (or brings a minimized one back), and closes it when it is open;
// `hide` is the same as `close`.
Scope {
    id: host

    // The monitor the panels are on: the focused one when a panel is opened.
    property var targetScreen: null

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        for (const s of Quickshell.screens) {
            if (s.name === name)
                return s
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    component ReaderSlot: Loader {
        id: slot

        // Tracked by hand: what the panel is wanted to do, not what it looks like (it
        // stays on screen for the swallow after it is asked to close).
        property bool open: false
        // Still on screen: open, or on its way out (and the few empty frames after it, so the
        // compositor's last picture of the window is an empty one), or minimized. A minimized
        // panel keeps the window mapped, showing nothing and taking no input: creating and
        // mapping a window is slow, and when it was brought back the card's growth ran into
        // that stall and jumped ahead, so there was no grow to see.
        readonly property bool present: slot.open || (slot.item ? (slot.item.reveal > 0.001 || slot.item.settling || slot.item.minimized) : false)

        function show() {
            if (!active) {
                active = true
                item.open = true
                open = true
            } else if (!open) {
                // bringing back a minimized panel (it drops `minimized` itself as it grows);
                // closing it next time unloads it
                item.open = true
                open = true
            }
        }

        // Hide it but keep it loaded and running; `show` / `toggle` bring it back.
        function minimize() {
            if (open && item)
                item.minimize()
        }

        // Hide it for good: it is unloaded once the card has gone into the edge. A minimized
        // panel (already hidden) is unloaded at once.
        function close() {
            if (open && item) {
                item.close()
            } else if (item && item.minimized) {
                item.minimized = false
                unloadTimer.start()
            }
        }

        function hide() {
            close()
        }

        function toggle() {
            if (open)
                hide()
            else
                show()
        }

        active: false

        Timer {
            id: unloadTimer
            interval: 600
            // unless it was reopened or minimized in the meantime
            onTriggered: if (!slot.open && !slot.item?.minimized) slot.active = false
        }

        Connections {
            target: slot.item
            // Closed from the toggle or its own minimize / close keys.
            function onOpenChanged() {
                if (slot.item.open)
                    return
                slot.open = false
            }
            // The swallow is done: now it can be unloaded.
            function onSwallowed() {
                if (!slot.open && !slot.item.minimized)
                    unloadTimer.start()
            }
        }
    }

    function open(slot) {
        host.targetScreen = host.focusedScreen()
        slot.show()
    }

    // The input region of one panel, in REAL window pixels. The panels are laid out in design
    // pixels inside a ScaleHost (below), so their `hitItem` is in the scaled space: this puts its
    // rectangle where it really is on screen, the way the dock's mask does (Dock.qml dockMask).
    component MaskBox: Item {
        id: box
        property var slot: null
        readonly property Item src: box.slot && box.slot.present && box.slot.item ? box.slot.item.hitItem : null
        // The window's scale, passed in (an inline component cannot look the window up itself).
        property real f: 1
        x: box.src ? Math.max(0, Math.floor((box.slot.x + box.src.x) * box.f)) : 0
        y: box.src ? Math.max(0, Math.floor((box.slot.y + box.src.y) * box.f)) : 0
        width: box.src ? Math.ceil(box.src.width * box.f) + 1 : 0
        height: box.src ? Math.ceil(box.src.height * box.f) + 1 : 0
    }

    PanelWindow {
        id: window

        screen: host.targetScreen

        // This monitor's shell scale (Settings -> Bar -> Size, scale.json). The window stays
        // the whole screen; the panels are drawn inside a ScaleHost at this factor, so they
        // grow and shrink with the rest of the shell.
        readonly property real uiScale: ShellScale.forScreen(window.screen)

        // Mapped only while a panel is showing; the rest of the surface passes input
        // through to the windows below.
        // Stays mapped until a panel has been swallowed.
        visible: mangaSlot.present || novelSlot.present

        WlrLayershell.namespace: "sekaipop-readers"
        WlrLayershell.layer: WlrLayer.Top
        // Keep clear of the bar's and the dock's exclusive zones.
        exclusionMode: ExclusionMode.Normal
        focusable: true
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // The window starts where the bar's reserved strip ends, and that is not where the bar
        // stops being drawn: it is a pixel or two short of it for Float / Straight, and
        // several pixels INSIDE it for Transparent / Capsule (the strip is trimmed by
        // gaps_out). The panel is clipped by this window's edge, so it sat beside
        // the bar in one style and on top of it in another. BarGeometry says how far to move
        // the edge on the bar's side so it is the same distance from what is drawn in every
        // style (see services/BarGeometry.qml). Real pixels; may be negative.
        margins {
            left: BarGeometry.position === "left" ? Math.round(BarGeometry.shiftReal(window.screen)) : 0
            right: BarGeometry.position === "right" ? Math.round(BarGeometry.shiftReal(window.screen)) : 0
            top: BarGeometry.position === "top" ? Math.round(BarGeometry.shiftReal(window.screen)) : 0
            bottom: BarGeometry.position === "bottom" ? Math.round(BarGeometry.shiftReal(window.screen)) : 0
        }

        MaskBox { id: mangaMask; slot: mangaSlot; f: window.uiScale }
        MaskBox { id: novelMask; slot: novelSlot; f: window.uiScale }

        mask: Region {
            Region {
                item: mangaMask.src ? mangaMask : null
            }
            Region {
                item: novelMask.src ? novelMask : null
            }
        }

        ScaleHost {
            anchors.fill: parent
            factor: window.uiScale

            ReaderSlot {
                id: mangaSlot
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                sourceComponent: MangaReader {}
            }

            ReaderSlot {
                id: novelSlot
                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                sourceComponent: NovelReader {}
            }
        }
    }

    IpcHandler {
        target: "mangareader"

        function toggle(): void {
            if (mangaSlot.open)
                mangaSlot.hide()
            else
                host.open(mangaSlot)
        }

        function show(): void {
            host.open(mangaSlot)
        }

        function hide(): void {
            mangaSlot.hide()
        }

        // Hide it but keep it running in the background (the shortcut brings it back).
        function minimize(): void {
            mangaSlot.minimize()
        }

        // Close it completely (also a minimized one).
        function close(): void {
            mangaSlot.close()
        }
    }

    IpcHandler {
        target: "novelreader"

        function toggle(): void {
            if (novelSlot.open)
                novelSlot.hide()
            else
                host.open(novelSlot)
        }

        function show(): void {
            host.open(novelSlot)
        }

        function hide(): void {
            novelSlot.hide()
        }

        // Hide it but keep it running in the background (the shortcut brings it back).
        function minimize(): void {
            novelSlot.minimize()
        }

        // Close it completely (also a minimized one).
        function close(): void {
            novelSlot.close()
        }
    }
}
