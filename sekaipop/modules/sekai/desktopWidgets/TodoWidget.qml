import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode

// The desktop To-Do widget: a card that sits on the desktop, under your
// windows, over the wallpaper.
//
//   Moving it: in Edit Desktop (right-click the desktop) it is always
//   draggable, by the shield in EditChrome.qml; a click on it there selects it
//   for editing (the tasks below work, and you can type), a right-click
//   removes it. On the normal desktop it can
//   be dragged (anywhere that isn't a button or a task's checkbox) only
//   while "Lock all" (a tile on the Edit Desktop shelf, locked by default)
//   is off. The lock is ignored while editing and applies again when you
//   press Done. There is no per-card lock.
//
//   double-click a task's text, or the pencil, to edit it; Enter saves,
//   Esc cancels (the row's buttons are hidden while you type). Tick the box
//   to check a task off; the bin deletes it.
//   hover a task and drag its grip (the dots at the right end) up or down
//   to put the list in the order you want; the order is remembered.
//
// State (tasks, position) lives in services/TodoService.qml and is
// remembered across restarts.
//
// How the moving works: this is ONE full-screen, transparent window on
// WlrLayer.Bottom, with the card as an Item inside it. Dragging just moves
// that Item — no Wayland reconfigure per frame, so it stays smooth. The
// window's input `mask` is only the card, so every click anywhere else on
// the desktop passes straight through to whatever is underneath.
//
// WlrLayer.Background (mapped after the wallpaper, so over it) is below every window and the dock, and above the wallpaper layer
// (WallpaperLayer.qml owns Background — this deliberately isn't a second
// background client). Keyboard focus is OnDemand: clicking the card lets you
// type into it, and clicking a real window hands the keyboard back.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call todo toggle        (show / hide)
//   qs -c sekaipop ipc call todo lock          (or: unlock)
//   qs -c sekaipop ipc call todo resetPosition (if it ever ends up off-screen)
PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    function resetPosition(): void {
        TodoService.posX = -1;
        TodoService.posY = -1;
        win.place();
        TodoService.setPosition(card.x, card.y, win.uiScale);
    }
    // Which monitor it lives on, by name (`hyprctl monitors`), e.g. "DP-1".
    // Empty = the monitor chosen for the To-Do (DesktopMonitors.qml).
    property string monitor: ""

    readonly property int cardWidth: 320
    // Past this many pixels of tasks the list scrolls instead of growing.
    readonly property int maxListHeight: 340

    // The 2 x 2 size (TodoService.size): the footprint the clock, user card and weather card
    // share, 320 x 276 with the housing. The card keeps every part it has; the list is just
    // a fixed window that scrolls, so the card never grows or shrinks with the tasks.
    // Everything else on the card has a fixed height, so the content comes to 238:
    //   header 36 + rule 2 + list + add box 40, with 10 between the four = 108 + list.
    // ("clear done" moves up into the header: a fifth row would not fit.)
    readonly property bool small: TodoService.small
    readonly property int smallContentH: 238
    readonly property int smallListH: win.smallContentH - 108

    // `monitor` when it is set (a copy), else the monitor chosen for the To-Do (Settings → Desktop →
    // Widgets, or the one it was added on in Edit Desktop). By name, so a reboot cannot swap them.
    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : DesktopMonitors.homeFor("todo")

    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's scale (scale.json / services/ShellScale.qml). The card
    // is drawn in design pixels inside a ScaleHost, so `roomW` x `roomH` is
    // the screen as the card sees it (real size / scale); positions are kept
    // in that same design space.
    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real fullW: win.screen ? win.screen.width : 0
    readonly property real fullH: win.screen ? win.screen.height : 0
    readonly property real roomW: win.fullW / win.uiScale
    readonly property real roomH: win.fullH / win.uiScale

    // ===== a small window while nothing needs the whole screen =====
    // A full-screen layer makes the compositor redraw (and re-blend) the whole screen on every
    // frame the card draws, even when the card is a small corner of it. So at rest the window is
    // just the card plus some room around it for the pop-in overshoot, the shadow and the name
    // tag, and only Edit Desktop (and dragging on an unlocked desktop) gets the full screen back.
    // Everything inside still lives in screen coordinates: `shifter` slides the whole stage by the
    // window's own position, so the card is drawn where it always was. (Same as the visualizer.)
    readonly property bool compact: !EditMode.active && !win.gliding && EditMode.screenName === ""
        && EditMode.compactWindows && !EditMode.desktopDragAllowed && win.fullW > 0 && win.placed
    readonly property real boxPad: Math.ceil((0.16 * Math.max(card.width, card.height) + 24) * win.uiScale)
    readonly property real boxX: win.compact ? Math.max(0, Math.floor(card.x * win.uiScale - win.boxPad)) : 0
    readonly property real boxY: win.compact ? Math.max(0, Math.floor(card.y * win.uiScale - win.boxPad)) : 0
    readonly property real boxW: Math.max(1, Math.min(win.fullW,
        Math.ceil((card.x + card.width) * win.uiScale + win.boxPad)) - win.boxX)
    readonly property real boxH: Math.max(1, Math.min(win.fullH,
        Math.ceil((card.y + card.height) * win.uiScale + win.boxPad)) - win.boxY)

    // On / off: the card pops in with a little overshoot and is swallowed
    // (straight shrink, nothing before it) on the way out, the same language
    // as Edit Desktop, instead of fading. The window stays up until the
    // swallow has finished.
    //
    // Two fixed animations, started from onWantChanged. (A Behavior whose
    // easing is picked by a binding on the same flag can start with the
    // PREVIOUS direction's easing, which is what made the way out misbehave.)
    // Desktop Focus Mode (FocusGate.qml, services/FocusService.qml): `gate.show` is
    // false while an application is on this monitor's workspace, so `want` goes
    // false and the usual swallow + unmap below does the hiding. `switchedOn` is
    // the user's own switch. (The to-do card has no clock or fetch of its own, so
    // hiding is all Focus Mode does to it.)
    FocusGate {
        id: gate
        widgetId: "todo"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: TodoService.shown && TodoService.loaded
    readonly property bool want: win.switchedOn && gate.show
    property real reveal: 0

    // Off while the saved state is read back, so a reload doesn't replay the pop.
    property bool armed: false

    onWantChanged: {
        if (!win.armed) {
            popIn.stop()
            swallow.stop()
            win.reveal = win.want ? 1 : 0
        } else if (win.want) {
            swallow.stop()
            popIn.restart()
        } else {
            popIn.stop()
            swallow.restart()
        }
    }

    NumberAnimation {
        id: popIn
        target: win
        property: "reveal"
        to: 1
        duration: 460
        easing.type: Easing.OutBack
        easing.overshoot: 1.9
    }

    NumberAnimation {
        id: swallow
        target: win
        property: "reveal"
        to: 0
        duration: 300
        easing.type: Easing.InCubic
    }

    Timer {
        interval: 800
        running: TodoService.loaded
        onTriggered: win.armed = true
    }

    property bool placed: false

    // `live`: the card is on, or still being swallowed.
    readonly property bool live: win.want || win.reveal > 0.001

    // Not mapped while the widget is off: a full-screen transparent layer that is only
    // sitting there still costs the compositor a blend on every frame.
    visible: TodoService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock: the widgets rest on Background (mapped after the wallpaper,
    // so over it) and the dock is on Bottom or Top, so the dock is never behind a widget.
    // Up a layer while this widget is edited or moved (EditChrome.raised), so the one
    // edited last is in front of the other widgets (see EditChrome.qml); Bottom is as far
    // up as it goes, because the dock is on Top while editing (see Dock.qml).
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-todo"
    // Not while editing: the shelf keeps the keyboard then (Esc), and a click
    // on a card must not take it away. The shield blocks typing anyway. The one
    // exception is the To-Do while it is selected for editing: then it is
    // used like on the desktop, so it can take the keyboard to type a task.
    WlrLayershell.keyboardFocus: (EditMode.active && EditMode.editTarget !== "todo") || !keys.wanted
        ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        left: true
        right: !win.compact
        bottom: !win.compact
    }

    margins {
        left: win.boxX
        top: win.boxY
    }

    implicitWidth: win.boxW
    implicitHeight: win.boxH

    // Only the card takes clicks; the rest of the screen falls through.
    // (In real window pixels, so it is the card's design rectangle times
    // the scale.)
    mask: Region { item: cardMask }

    // Edit Desktop widens the card's rectangle a little (its outline and tag sit
    // half outside it), and everything here follows the shrink: `stage` is the
    // transform the content is drawn with (EditStage.qml; scale 1 and no
    // offset when not editing).
    Item {
        id: cardMask
        readonly property real m: stage.editing ? 38 : 0
        readonly property real k: win.uiScale * stage.scale
        readonly property real x1: shifter.x + stage.x + (card.x + card.width + m) * k
        readonly property real y1: shifter.y + stage.y + (card.y + card.height + m) * k
        x: !win.live ? 0 : Math.max(0, Math.round(shifter.x + stage.x + (card.x - m) * k))
        y: !win.live ? 0 : Math.max(0, Math.round(shifter.y + stage.y + (card.y - m) * k))
        width: !win.live ? 1 : Math.max(0, Math.ceil(x1) - x)
        height: !win.live ? 1 : Math.max(0, Math.ceil(y1) - y)
    }

    // ===== placement =====
    function place() {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        let x = TodoService.posX
        let y = TodoService.posY
        if (x < 0 || y < 0) {
            x = win.roomW - card.width - 40
            y = 96
        } else if (TodoService.posScale > 0 && win.uiScale > 0) {
            // Saved at another shell scale: same spot on the screen, not the
            // same design pixels (the card keeps its top-left corner).
            const k = TodoService.posScale / win.uiScale
            x *= k
            y *= k
        }
        card.x = Math.max(0, Math.min(x, win.roomW - card.width))
        card.y = Math.max(0, Math.min(y, win.roomH - card.height))
        win.placed = true
    }

    // After a reload the window, the monitor list and scale.json all settle
    // over a few frames; place again once they have, so the card always ends
    // on its saved spot (never while it is being dragged). Same as the clock
    // and the user card.
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            // A position saved before the scale was kept with it: it was in design
            // pixels of the scale in use now (nothing has changed it since), so
            // keep that from here on.
            if (TodoService.loaded && TodoService.posX >= 0 && TodoService.posScale <= 0 && !dragArea.drag.active) {
                TodoService.posScale = win.uiScale
                TodoService.persist()
            }
            if (!chrome.dragging && !dragArea.drag.active)
                win.place()
        }
    }

    // place() runs one turn of the event loop later (Qt.callLater), not inside the window's own
    // size change: the size is boxW / boxH, which read card.x / card.y, which place() sets
    // (Qt logged "Binding loop detected for property implicitWidth"). Same as ClockWidget.qml.
    // To undo: `onWidthChanged: { win.place(); settle.restart() }` (same for the height).
    onWidthChanged: { Qt.callLater(win.place); settle.restart() }
    onHeightChanged: { Qt.callLater(win.place); settle.restart() }
    onUiScaleChanged: { win.place(); settle.restart() }
    onScreenChanged: { win.place(); settle.restart() }
    onVisibleChanged: settle.restart()
    Component.onCompleted: {
        win.reveal = win.want ? 1 : 0
        win.place()
    }

    Connections {
        target: TodoService
        function onLoadedChanged() {
            win.place()
            settle.restart()
        }
        // A desktop preset hands the service another saved spot while the card
        // is on screen. Without this the card only looked at the service when
        // it loaded or when the window / scale / monitor changed, so wearing a
        // preset moved nothing. The spot arrives as several properties one
        // after the other (x, y, scale), so wait a beat and place once.
        function onPosXChanged() { follow.restart() }
        function onPosYChanged() { follow.restart() }
        function onPosScaleChanged() { follow.restart() }
    }

    // A preset hands the card another spot: it glides there instead of jumping
    // (not while it is being dragged, and not when it is already where it
    // should be, which is what dropping it by hand and the scale check come to).
    // `gliding` first, so a small window grows to the whole screen (see
    // `compact`), then `glideOn` switches the card's Behaviors on.
    property bool gliding: false
    property bool glideOn: false

    Timer {
        id: follow
        interval: 16
        onTriggered: {
            if (chrome.dragging || dragArea.drag.active)
                return
            const ox = card.x
            const oy = card.y
            win.place()
            if (Math.abs(card.x - ox) + Math.abs(card.y - oy) < 2)
                return
            card.x = ox
            card.y = oy
            win.gliding = true
            glideStart.restart()
        }
    }

    Timer {
        id: glideStart
        interval: 80
        onTriggered: {
            win.glideOn = true
            win.place()
            glideEnd.restart()
        }
    }

    // A preset changes this card's variant or switches it off: it shrinks away, the
    // preset goes on, and the new variant pops back in (see PresetMotion.qml).
    // 1 = in place, 0 = away. Two fixed animations started from the flag, not one
    // Behavior (see `reveal`).
    property real swapK: 1
    NumberAnimation {
        id: swapOut
        target: win
        property: "swapK"
        to: 0
        duration: PresetMotion.outMs
        easing.type: Easing.InCubic
    }
    NumberAnimation {
        id: swapIn
        target: win
        property: "swapK"
        to: 1
        duration: PresetMotion.inMs
        easing.type: Easing.OutBack
        easing.overshoot: 1.4
    }
    Connections {
        target: PresetMotion
        function onTodoOutChanged() {
            if (PresetMotion.todoOut) {
                swapIn.stop()
                swapOut.restart()
            } else if (win.want) {
                swapOut.stop()
                swapIn.restart()
            } else {
                // Switched off: stays away until the swallow is over, or the card
                // would come back for a moment while it is still being swallowed.
                swapOut.stop()
                swapRest.restart()
            }
        }
    }
    Timer {
        id: swapRest
        interval: 420
        onTriggered: win.swapK = 1
    }
    Connections {
        target: win
        function onWantChanged() {
            if (win.want && swapRest.running) {
                swapRest.stop()
                win.swapK = 1
            }
        }
    }

    Timer {
        id: glideEnd
        interval: 640
        onTriggered: {
            win.glideOn = false
            win.gliding = false
                bumpAnim.restart()
        }
    }

    // Edit Desktop's shelf shows the card as it really looks: a picture of it,
    // taken every second while the mode is on (EditPreview.qml).
    EditPreview {
        widgetId: "todo"
        target: card
        pixelRatio: win.uiScale
    }


    // A small square button: transparent until hovered.
    component IconBtn: Rectangle {
        id: btn

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string icon: ""
        property color hoverColor: mt.accentMint
        signal clicked()

        width: 26
        height: 26
        radius: 9
        color: btnArea.containsMouse ? btn.hoverColor : "transparent"

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        MaterialIcon {
            color: btnArea.containsMouse ? mt.colBorder : mt.pInk
            anchors.centerIn: parent
            name: btn.icon
            size: 18
            weight: 600
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // ===== Edit Desktop =====
    Item {
        id: shifter
        x: -win.boxX
        y: -win.boxY
        width: win.fullW
        height: win.fullH

    // ===========================================================================
    // Edit Desktop shrinks every desktop window into the same card with the same
    // transform (see EditStage.qml / services/EditMode.qml). Out of edit mode
    // this is a no-op: scale 1, no offset.
    EditStage {
        id: stage
        screenObj: win.screen
        uiScale: win.uiScale

        ScaleHost {
            anchors.fill: parent
            factor: win.uiScale

            Item {
                id: card

                // Gliding to a preset's spot (win.glideOn, see `follow`). Off the rest of the time,
                // so dragging and placing are exact.
                Behavior on x {
                    enabled: win.glideOn
                    NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }
                Behavior on y {
                    enabled: win.glideOn
                    NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                }

                // Keeps the classic (white) look in the first dark mode; see Theme.classicFor.
                readonly property bool classicPanel: true

                // Where the content starts: the pill's own border + ring, plus room.
                readonly property int inset: mt.borderWidth + mt.outerRingWidth + 10

                width: win.cardWidth
                height: col.implicitHeight + card.inset * 2 + mt.shadowOffset

                // Drop-and-settle bounce (kept for anything that wants to nudge the card).
                property real bump: 1
                scale: card.bump * Math.max(0, win.reveal) * (0.7 + 0.3 * Math.max(0, win.swapK))
                opacity: Math.max(0, Math.min(1, win.swapK))
                transformOrigin: Item.Center

                SequentialAnimation {
                    id: bumpAnim
                    NumberAnimation { target: card; property: "bump"; to: 1.035; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: card; property: "bump"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
                }

                // Growing (a new task) shouldn't push the bottom off-screen. This
                // works from the SAVED spot each time (place() clamps it), instead
                // of moving the card for good: while the shell starts or reloads the
                // card's height jumps around, and a permanent nudge upwards is how
                // it used to lose its place. When it gets shorter again it goes back.
                // (Not while it is being dragged: then the drag owns the position.)
                onWidthChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                onHeightChanged: {
                    if (!chrome.dragging && !dragArea.drag.active) {
                        win.place()
                        settle.restart()
                    }
                }

                // The housing — the same navy outline / pale ring / white fill /
                // hard shadow as the bar and the dock.
                Pill {
                    anchors.fill: parent
                    cornerRadius: mt.radiusOuter
                    ringWidth: mt.borderWidth + mt.outerRingWidth
                    ringColorTop: mt.pSurfaceRing
                    ringColorBottom: ringColorTop
                    fillColor: mt.pSurface
                }

                // Edit Desktop: outline, corner diamonds, a tag and a drag
                // shield (EditChrome.qml). Draws nothing outside the mode.
                EditChrome {
                    id: chrome
                    widgetId: "todo"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: TodoService.setPosition(card.x, card.y, win.uiScale)
                    onRemoveRequested: TodoService.setShown(false)
                }

                // Left button: drag the card on the normal desktop, unless Lock all
                // is on (EditMode.desktopDragAllowed; while editing, the shield in
                // EditChrome.qml does the moving instead, until the card is
                // selected for editing: then this does). Sits under the content,
                // so buttons and the checkboxes win their own clicks and everything
                // else on the card is "grab here".
                MouseArea {
                    id: dragArea
                    z: 1
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

                    drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, win.roomW - card.width)
                    drag.minimumY: 0
                    drag.maximumY: Math.max(0, win.roomH - card.height)

                    // Clicking the card itself takes the cursor out of any text box.
                    onPressed: card.forceActiveFocus()

                    // Remember the new spot when a drag ends (also when it is cut
                    // short). A plain click doesn't save anything, so a card that
                    // is squeezed onto a small screen for a moment can't overwrite
                    // where you put it.
                    drag.onActiveChanged: {
                        // Edit Desktop's alignment grid (EditChrome.qml) needs to know
                        // about a drag that is not its own shield's.
                        chrome.ownDrag = drag.active
                        if (!drag.active)
                            TodoService.setPosition(card.x, card.y, win.uiScale)
                    }
                }

                // Edit Desktop: flip between FULL and 2 x 2 (only while the card is selected).
                SizeKey {
                    shown: chrome.selected
                    small: win.small
                    onToggled: TodoService.toggleSize()
                }

                Column {
                    id: col
                    z: 2
                    x: card.inset
                    y: card.inset
                    width: card.width - card.inset * 2
                    spacing: 10

                    // ===== header =====
                    Item {
                        width: col.width
                        height: 36

                        Rectangle {
                            id: tile
                            width: 36
                            height: 36
                            radius: 11
                            border.width: mt.borderWidth
                            border.color: mt.pLine
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: mt.accentMint }
                                GradientStop { position: 1.0; color: mt.accentCyan }
                            }

                            MaterialIcon {
                                color: mt.colBorder
                                anchors.centerIn: parent
                                name: "checklist"
                                size: 22
                                weight: 600
                            }
                        }

                        Column {
                            anchors.left: tile.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            Text {
                                text: "To-Do"
                                color: mt.pInk
                                font.family: mt.fontFamily
                                font.pixelSize: 18
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            Text {
                                text: TodoService.total === 0 ? "nothing yet"
                                    : TodoService.doneCount === TodoService.total ? "all done!"
                                    : (TodoService.total - TodoService.doneCount) + " left"
                                color: mt.pInkSub
                                font.family: mt.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        // 2 x 2 only: the footer row is gone, so "clear done" lives up here.
                        Rectangle {
                            visible: win.small && TodoService.doneCount > 0
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: clearTextSmall.implicitWidth + 22
                            height: 26
                            radius: 13
                            border.width: 2
                            border.color: mt.pLine
                            color: clearAreaSmall.containsMouse ? mt.irisColorPink : mt.pSurface

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }

                            Text {
                                id: clearTextSmall
                                anchors.centerIn: parent
                                text: "clear done (" + TodoService.doneCount + ")"
                                color: clearAreaSmall.containsMouse ? mt.colBorder : mt.pInk
                                font.family: mt.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            MouseArea {
                                id: clearAreaSmall
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: TodoService.clearDone()
                            }
                        }
                    }

                    Rectangle {
                        width: col.width
                        height: 2
                        radius: 1
                        color: mt.pSurfaceDivider
                    }

                    // ===== empty state =====
                    Text {
                        visible: TodoService.total === 0
                        width: col.width
                        height: win.small ? win.smallListH : 44
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "add your first task below"
                        color: mt.pInkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    // ===== the list =====
                    Item {
                        id: listBox
                        visible: TodoService.total > 0
                        width: col.width
                        height: win.small ? win.smallListH : Math.min(list.contentHeight, win.maxListHeight)

                        Behavior on height {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }

                        WheelScroll { scroller: list }
                        ListView {
                            id: list
                            anchors.fill: parent
                            clip: true
                            spacing: 4
                            model: TodoService.items
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds

                            // Keep every row instantiated, so the drag can always
                            // measure the rows and a scrolled-away row never loses
                            // the mouse grab half-way through a drag.
                            cacheBuffer: 4000

                            // ===== drag to reorder =====
                            property int dragFrom: -1        // index of the held row (follows it as it moves); -1 = not dragging
                            property string dragTitle: ""
                            property bool dragDone: false
                            property real dragHeight: 36
                            property real dragGrab: 0        // mouse's distance below the top of the held row
                            property real pointerY: 0        // mouse, in listBox coordinates
                            property real scrollCarry: 0     // sub-pixel leftover of the edge auto-scroll
                            readonly property bool dragging: dragFrom >= 0

                            // How far (px) the held task must go past a neighbour's middle
                            // before they swap. Together with the gap between rows this is
                            // the dead zone that stops the tasks flickering back and forth
                            // when the mouse rests right on a boundary.
                            readonly property real swapMargin: 3

                            // The held task is shown as a small one-line chip under the
                            // pointer (not a full copy of the row: a long, wrapped task
                            // covered the rows around it and hid where it would land). The
                            // row's own slot, at its real height, is what shows the spot.
                            readonly property real ghostH: 30
                            readonly property real ghostW: Math.min(listBox.width, 190)

                            // Top of the chip, centred on the pointer, kept inside the list's box.
                            readonly property real ghostTop:
                                Math.max(0, Math.min(pointerY - ghostH / 2, listBox.height - ghostH))

                            function beginDrag(index, title, done, h, grab, py) {
                                list.dragTitle = title
                                list.dragDone = done
                                list.dragHeight = h
                                list.dragGrab = grab
                                list.pointerY = py
                                list.scrollCarry = 0
                                list.dragFrom = index
                            }

                            function moveDrag(py) {
                                list.pointerY = py
                                list.retarget()
                            }

                            function endDrag() {
                                if (list.dragFrom < 0)
                                    return
                                list.dragFrom = -1
                                // The order is only written to disk once you let go, not
                                // on every hop (saving spawns a process; doing that
                                // mid-drag is a hitch whenever you pause over a row).
                                TodoService.commitOrder()
                            }

                            // Move the held task past a neighbour once the pointer (the
                            // chip's centre) is past that neighbour's middle.
                            //
                            // The rule "whichever slot the pointer is over" breaks as soon as
                            // tasks have different heights (a wrapped, two-line task next to
                            // a one-line one): after a swap the slot moves out from under the
                            // pointer, so the very next update swaps it straight back, and so
                            // on every frame. That was the shaking at specific spots. Here,
                            // after a swap down the way back up needs the pointer above
                            // top + h(neighbour) / 2 - margin, while the swap itself needed it
                            // below top + h(held) + gap + h(neighbour) / 2 + margin: swapping
                            // back is strictly harder than the rule that just fired, whatever
                            // the heights, so it settles (and the chip's own height, which is
                            // fixed, no longer takes part).
                            //
                            // All the geometry comes from the rows' own heights (not where
                            // they happen to be mid-animation), and several rows can be
                            // crossed in one call when the mouse is fast. The model is
                            // moved once, at the end.
                            function retarget() {
                                if (list.dragFrom < 0)
                                    return
                                // Apply the previous hop first, so itemAtIndex() matches the model.
                                list.forceLayout()
                                const n = list.count
                                const hs = []
                                for (let i = 0; i < n; i++) {
                                    const it = list.itemAtIndex(i)
                                    if (!it)
                                        return
                                    hs.push(it.height)
                                }
                                const sp = list.spacing
                                const m = list.swapMargin
                                const gMid = (list.contentY - list.originY) + list.ghostTop + list.ghostH / 2

                                let at = list.dragFrom
                                let top = 0                      // top of the held task's slot
                                for (let i = 0; i < at; i++)
                                    top += hs[i] + sp

                                for (let guard = 0; guard < n; guard++) {
                                    if (at < n - 1 && gMid > top + hs[at] + sp + hs[at + 1] / 2 + m) {
                                        const nb = hs[at + 1]
                                        top += nb + sp
                                        hs[at + 1] = hs[at]
                                        hs[at] = nb
                                        at++
                                    } else if (at > 0 && gMid < top - sp - hs[at - 1] / 2 - m) {
                                        const nb = hs[at - 1]
                                        top -= nb + sp
                                        hs[at - 1] = hs[at]
                                        hs[at] = nb
                                        at--
                                    } else {
                                        break
                                    }
                                }

                                if (at !== list.dragFrom && TodoService.move(list.dragFrom, at))
                                    list.dragFrom = at
                            }

                            // A long list scrolls while you hold a task near its top or bottom
                            // edge. Driven by the frame clock and real elapsed time (a 16 ms
                            // Timer drifts against the screen's refresh, which made the
                            // scrolling, and the swaps it triggers, stutter), in whole pixels
                            // so the text isn't drawn on half-pixels while it moves.
                            FrameAnimation {
                                running: list.dragging && list.contentHeight > list.height
                                onTriggered: {
                                    const edge = 30
                                    const p = list.pointerY
                                    let f = 0
                                    if (p < edge)
                                        f = -(edge - p) / edge
                                    else if (p > listBox.height - edge)
                                        f = (p - (listBox.height - edge)) / edge
                                    f = Math.max(-1, Math.min(1, f))
                                    if (f === 0) {
                                        list.scrollCarry = 0
                                        return
                                    }
                                    // Gentle just inside the edge, full speed (~560 px/s) at it.
                                    const dt = Math.min(frameTime, 0.05)
                                    list.scrollCarry += 560 * f * Math.abs(f) * dt
                                    const step = Math.trunc(list.scrollCarry)
                                    if (step === 0)
                                        return
                                    list.scrollCarry -= step
                                    const maxY = list.contentHeight - list.height - list.originY
                                    const next = Math.max(list.originY, Math.min(maxY, list.contentY + step))
                                    if (next !== list.contentY) {
                                        list.contentY = next
                                        list.retarget()
                                    }
                                }
                            }

                            add: Transition {
                                NumberAnimation { properties: "opacity,scale"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                            }
                            remove: Transition {
                                NumberAnimation { property: "opacity"; to: 0; duration: 140 }
                            }
                            displaced: Transition {
                                NumberAnimation { property: "y"; duration: 160; easing.type: Easing.OutCubic }
                            }
                            move: Transition {
                                NumberAnimation { property: "y"; duration: 160; easing.type: Easing.OutCubic }
                            }

                            delegate: Item {
                                id: row

                                required property int index
                                required property string title
                                required property bool done

                                property bool editing: false
                                readonly property real textHeight: row.editing ? editor.implicitHeight : label.implicitHeight

                                width: ListView.view ? ListView.view.width : 0

                                // The task being dragged keeps only a short slot while it is held
                                // (its text is on the chip), so a long, wrapped task does not leave
                                // a tall empty box that pushes the others out of view. The rows'
                                // own heights drive the swap rule, so it uses this one too. No
                                // animation on purpose: the rule reads the heights as they are.
                                readonly property bool held: list.dragFrom === row.index
                                height: row.held ? 36 : Math.max(36, row.textHeight + 14)

                                function beginEdit() {
                                    row.editing = true
                                    editor.text = row.title
                                    editor.forceActiveFocus()
                                    editor.selectAll()
                                }

                                function commit() {
                                    if (!row.editing)
                                        return
                                    row.editing = false
                                    const t = editor.text.trim()
                                    if (t !== "" && t !== row.title)
                                        TodoService.edit(row.index, t)
                                }

                                function cancel() {
                                    row.editing = false
                                }

                                HoverHandler {
                                    id: hover
                                    // Non-blocking, so KeysOnPoint (on the window) still hears
                                    // the pointer over a row and the keyboard works while editing.
                                    blocking: false
                                }

                                // Rows the mouse sweeps over mid-drag shouldn't light up and
                                // sprout buttons: that fading is what looked like flicker.
                                readonly property bool hot: hover.hovered && !list.dragging

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: mt.pSurfaceHover
                                    opacity: row.hot || row.editing ? 1 : 0

                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }
                                }

                                // While this row is being dragged it shows as an empty slot;
                                // the floating copy (`ghost`) is what you're holding.
                                Rectangle {
                                    z: 10
                                    anchors.fill: parent
                                    radius: 10
                                    visible: row.held
                                    color: mt.pSurfaceHover
                                    border.width: 2
                                    border.color: mt.accentCyan
                                }

                                // The checkbox: navy outline, mint-to-cyan when ticked.
                                Rectangle {
                                    id: box
                                    x: 8
                                    y: 7
                                    width: 22
                                    height: 22
                                    radius: 7
                                    color: mt.pSurface
                                    border.width: 2.5
                                    border.color: mt.pLine

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: box.border.width
                                        radius: box.radius - box.border.width
                                        opacity: row.done ? 1 : 0
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: mt.accentMint }
                                            GradientStop { position: 1.0; color: mt.accentCyan }
                                        }

                                        Behavior on opacity {
                                            NumberAnimation { duration: 120 }
                                        }
                                    }

                                    MaterialIcon {
                                        color: mt.colBorder
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: 16
                                        weight: 700
                                        scale: row.done ? 1 : 0

                                        Behavior on scale {
                                            NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: TodoService.toggle(row.index)
                                    }
                                }

                                // The task text. Double-click to edit; the TapHandler only
                                // listens, so a left-drag starting on the text still moves
                                // the card.
                                Text {
                                    id: label
                                    x: 40
                                    y: Math.round((row.height - label.implicitHeight) / 2)
                                    width: row.width - 40 - 10
                                    visible: !row.editing && !row.held
                                    text: row.title
                                    wrapMode: Text.Wrap
                                    color: row.done ? mt.pInkSub : mt.pInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    font.strikeout: row.done

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }

                                    TapHandler {
                                        acceptedButtons: Qt.LeftButton
                                        onDoubleTapped: row.beginEdit()
                                    }
                                }

                                TextInput {
                                    id: editor
                                    x: 40
                                    y: Math.round((row.height - editor.implicitHeight) / 2)
                                    width: row.width - 40 - 10
                                    visible: row.editing
                                    wrapMode: TextInput.Wrap
                                    selectByMouse: true
                                    color: mt.pInk
                                    selectionColor: mt.accentCyan
                                    selectedTextColor: mt.colBorder
                                    font.family: mt.fontFamily
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold

                                    onAccepted: row.commit()
                                    Keys.onEscapePressed: row.cancel()
                                    onActiveFocusChanged: {
                                        if (!editor.activeFocus && row.editing)
                                            row.commit()
                                    }
                                }

                                // Underline while editing.
                                Rectangle {
                                    visible: row.editing
                                    x: 40
                                    y: editor.y + editor.height + 1
                                    width: editor.width
                                    height: 2
                                    radius: 1
                                    color: mt.accentCyan
                                }

                                // Grip / edit / delete, floating over the right end of the row on hover
                                // (not while it is being edited).
                                Rectangle {
                                    id: actions
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    y: 5
                                    width: actionRow.width + 4
                                    height: 26
                                    radius: 10
                                    color: mt.pSurfaceHover
                                    // Hidden while the text is being edited (no bin, no grip,
                                    // no pencil there): Enter saves and Esc cancels.
                                    opacity: !row.editing && (row.hot || list.dragFrom === row.index) ? 1 : 0
                                    visible: opacity > 0.01

                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }

                                    Row {
                                        id: actionRow
                                        anchors.centerIn: parent
                                        spacing: 2

                                        // The grip: hold it and drag up / down to reorder.
                                        // It takes the mouse itself, so a drag here never
                                        // moves the card.
                                        Rectangle {
                                            id: grip
                                            width: 26
                                            height: 26
                                            radius: 9
                                            color: gripArea.containsMouse || gripArea.pressed ? mt.accentCyan : "transparent"

                                            Behavior on color {
                                                ColorAnimation { duration: 120 }
                                            }

                                            MaterialIcon {
                                                color: gripArea.containsMouse || gripArea.pressed ? mt.colBorder : mt.pInk
                                                anchors.centerIn: parent
                                                name: "drag_indicator"
                                                size: 18
                                                weight: 600
                                            }

                                            MouseArea {
                                                id: gripArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton
                                                preventStealing: true
                                                cursorShape: Qt.SizeVerCursor

                                                onPressed: mouse => {
                                                    const p = gripArea.mapToItem(listBox, mouse.x, mouse.y)
                                                    const top = row.mapToItem(listBox, 0, 0).y
                                                    list.beginDrag(row.index, row.title, row.done, row.height, p.y - top, p.y)
                                                }
                                                onPositionChanged: mouse => {
                                                    if (gripArea.pressed)
                                                        list.moveDrag(gripArea.mapToItem(listBox, mouse.x, mouse.y).y)
                                                }
                                                onReleased: list.endDrag()
                                                onCanceled: list.endDrag()
                                            }
                                        }

                                        IconBtn {
                                            icon: "edit"
                                            hoverColor: mt.accentMint
                                            onClicked: row.beginEdit()
                                        }

                                        IconBtn {
                                            icon: "delete"
                                            hoverColor: mt.irisColorPink
                                            onClicked: TodoService.remove(row.index)
                                        }
                                    }
                                }
                            }
                        }

                        // Slim scroll indicator, only when the list overflows.
                        Rectangle {
                            visible: list.contentHeight > list.height
                            x: listBox.width - width
                            y: list.visibleArea.yPosition * listBox.height
                            width: 4
                            height: Math.max(20, list.visibleArea.heightRatio * listBox.height)
                            radius: 2
                            color: mt.pLine
                            opacity: 0.35
                        }

                        // The held task, as a small chip that follows the mouse: one line,
                        // the text cut short, so it never hides the rows it passes over.
                        // Same navy outline and hard shadow as the card itself; it sits at
                        // the right end, where the grip you are holding is.
                        Item {
                            id: ghost
                            visible: list.dragging
                            z: 5
                            width: list.ghostW
                            height: list.ghostH
                            x: listBox.width - width
                            y: list.ghostTop

                            Rectangle {
                                x: 3
                                y: 3
                                width: parent.width
                                height: parent.height
                                radius: 10
                                color: mt.pLineShadow
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: mt.pSurface
                                border.width: 2.5
                                border.color: mt.pLine
                            }

                            Rectangle {
                                id: ghostBox
                                x: 6
                                y: Math.round((ghost.height - height) / 2)
                                width: 18
                                height: 18
                                radius: 6
                                color: mt.pSurface
                                border.width: 2.5
                                border.color: mt.pLine

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: ghostBox.border.width
                                    radius: ghostBox.radius - ghostBox.border.width
                                    visible: list.dragDone
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: mt.accentMint }
                                        GradientStop { position: 1.0; color: mt.accentCyan }
                                    }
                                }

                                MaterialIcon {
                                    visible: list.dragDone
                                    color: mt.colBorder
                                    anchors.centerIn: parent
                                    name: "check"
                                    size: 13
                                    weight: 700
                                }
                            }

                            Text {
                                x: 30
                                y: Math.round((ghost.height - implicitHeight) / 2)
                                width: ghost.width - 30 - 28   // room for the grip on the right
                                text: list.dragTitle
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                wrapMode: Text.NoWrap
                                color: list.dragDone ? mt.pInkSub : mt.pInk
                                font.family: mt.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                font.strikeout: list.dragDone
                            }

                            // The grip, on a small backing so it never sits on top of text.
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: 8
                                color: mt.pSurface

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    color: mt.pInk
                                    name: "drag_indicator"
                                    size: 16
                                    weight: 600
                                }
                            }
                        }
                    }

                    // ===== add a task =====
                    Rectangle {
                        id: addBox
                        width: col.width
                        height: 40
                        radius: 12
                        color: addInput.activeFocus ? mt.pSurface : mt.pSurfaceHover
                        border.width: 2.5
                        border.color: mt.pLine

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        // Click anywhere in the box to start typing.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.IBeamCursor
                            onPressed: addInput.forceActiveFocus()
                        }

                        TextInput {
                            id: addInput
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: addBtn.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            selectByMouse: true
                            color: mt.pInk
                            selectionColor: mt.accentCyan
                            selectedTextColor: mt.colBorder
                            font.family: mt.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold

                            onAccepted: addBtn.submit()
                            Keys.onEscapePressed: {
                                addInput.text = ""
                                card.forceActiveFocus()
                            }

                            Text {
                                visible: addInput.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "add a task…"
                                color: mt.pInkSub
                                font: addInput.font
                            }
                        }

                        Rectangle {
                            id: addBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 9
                            border.width: 2.5
                            border.color: mt.pLine
                            scale: addArea.pressed ? 0.9 : 1
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: mt.accentMint }
                                GradientStop { position: 1.0; color: mt.accentCyan }
                            }

                            Behavior on scale {
                                NumberAnimation { duration: 90 }
                            }

                            function submit() {
                                if (TodoService.add(addInput.text)) {
                                    addInput.text = ""
                                    // The list grows on the next layout pass.
                                    Qt.callLater(() => list.positionViewAtEnd())
                                }
                            }

                            MaterialIcon {
                                color: mt.colBorder
                                anchors.centerIn: parent
                                name: "add"
                                size: 20
                                weight: 700
                            }

                            MouseArea {
                                id: addArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: addBtn.submit()
                            }
                        }
                    }

                    // ===== footer =====
                    Item {
                        visible: TodoService.doneCount > 0 && !win.small
                        width: col.width
                        height: 26

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: clearText.implicitWidth + 22
                            height: 26
                            radius: 13
                            border.width: 2
                            border.color: mt.pLine
                            color: clearArea.containsMouse ? mt.irisColorPink : mt.pSurface

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }

                            Text {
                                id: clearText
                                anchors.centerIn: parent
                                text: "clear done (" + TodoService.doneCount + ")"
                                color: clearArea.containsMouse ? mt.colBorder : mt.pInk
                                font.family: mt.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            MouseArea {
                                id: clearArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: TodoService.clearDone()
                            }
                        }
                    }
                }
            }
        }
    }
    }

    // Asks for the keyboard only under the pointer or while typing (issue #72).
    KeysOnPoint {
        id: keys
    }
}
