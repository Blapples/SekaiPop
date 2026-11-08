import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common/functions/WaterMath.js" as WTM
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode

// The desktop Water Tank: a glass on the wallpaper that fills as you drink. Tap it for a glass of
// water, watch the level rise toward your daily goal, keep a streak. Made of the shell's own parts
// (Pill, StickerText, Burst, Slant, MaterialIcon), so it looks like the rest of the desktop cards.
//
// Two sizes (Settings -> Desktop -> Water tank size, the size key on it while it is selected in
// Edit Desktop, or `ipc call watertank size 1x1|2x2`):
//   1 x 1  ONE glass key (WaterTile.qml): the water, a droplet chip, the goal, the count as a sticker
//          numeral. Click: +1 (it squashes, a puff of diamonds). Wheel up +1, wheel down -1.
//          At the goal the droplet turns into a check and a bigger burst flies.
//   2 x 2  (the clock's / user card's footprint) the title tab and the streak (days in a row the goal was
//          reached) along the top; under them the glass (a tick for every glass of the goal, the count)
//          beside the amount in litres and a - and a + key; and the last seven days as a row of tanks
//          along the foot (a day that reached the goal wears a diamond).
//
// The numbers (today's glasses, the goal, the glass size, the last days) live in
// services/WaterTankService.qml and are remembered across restarts; the count starts again at 0
// after midnight. Settings -> Desktop has the goal and the size of a glass.
//
//   Moving it: in Edit Desktop (right-click the desktop) it is always draggable, by the shield in
//   EditChrome.qml; a click on it there selects it for editing, a right-click removes it. On the normal
//   desktop it can be dragged only while "Lock all" (a tile on the Edit Desktop shelf, locked by
//   default) is off, by any part of the card that is not a key.
//
// Nothing runs on its own: the level eases when it changes, the pop plays on a glass, and a timer
// once a minute checks whether the day changed.
//
// How the moving works: exactly like WaterTankWidget.qml and UserCardWidget.qml. ONE transparent
// window with the card as an Item inside it. Dragging just moves that Item, and the window's input
// `mask` is only the card, so every click anywhere else passes straight through to whatever is
// underneath. The card never takes keyboard focus.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call watertank toggle         (show / hide)
//   qs -c sekaipop ipc call watertank add            (a glass of water)
//   qs -c sekaipop ipc call watertank addMany 2      (two glasses)
//   qs -c sekaipop ipc call watertank remove         (take one back)
//   qs -c sekaipop ipc call watertank reset          (today back to 0)
//   qs -c sekaipop ipc call watertank goal 10        (glasses a day)
//   qs -c sekaipop ipc call watertank size 1x1       (or 2x2)
//   qs -c sekaipop ipc call watertank resetPosition  (if it ever ends up off-screen)

PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    function resetPosition(): void {
        win.clearSpot();
        win.place();
        win.saveSpot(card.x, card.y);
    }
    // Which monitor it lives on, by name (`hyprctl monitors`), e.g. "DP-1".
    // Empty = the monitor the card was last dropped on (remembered in
    // WaterTankService), or the first screen if it has never been moved.
    property string monitor: ""

    readonly property bool spotReady: WaterTankService.loaded
    readonly property real spotX: WaterTankService.posX
    readonly property real spotY: WaterTankService.posY
    readonly property real spotScale: WaterTankService.posScale

    function saveSpot(x, y): void {
        WaterTankService.setPosition(x, y, win.screen ? win.screen.name : "", win.uiScale)
    }

    function clearSpot(): void {
        WaterTankService.posX = -1
        WaterTankService.posY = -1
    }

    function fixSpotScale(): void {
        WaterTankService.posScale = win.uiScale
        WaterTankService.persist()
    }

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : WaterTankService.screenName
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's scale (scale.json / services/ShellScale.qml). The card is
    // drawn in design pixels inside a ScaleHost, so `roomW` x `roomH` is the
    // screen as the card sees it (real size / scale); positions are kept in
    // that same design space.
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
    // as the clock and Edit Desktop. The window stays up until the swallow
    // has finished.
    //
    // Two fixed animations, started from onWantChanged. (A Behavior whose
    // easing is picked by a binding on the same flag can start with the
    // PREVIOUS direction's easing.)
    // Desktop Focus Mode (FocusGate.qml, services/FocusService.qml): `gate.show` is
    // false while an application is on this monitor's workspace, so `want` goes
    // false and the usual swallow + unmap below does the hiding. `switchedOn` is
    // the user's own switch; `working` is whether the card's clock / fetches may
    // run (they stop while it is hidden, unless Settings keeps them going).
    FocusGate {
        id: gate
        widgetId: "watertank"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: WaterTankService.shown && WaterTankService.loaded
    readonly property bool want: win.switchedOn && gate.show
    property real reveal: 0

    // Off while the saved state is read back, so a reload doesn't replay the pop.
    property bool armed: false

    // Stays false until the card has been put on its saved spot, and keeps it
    // drawn at size 0 until then. After a reload the window maps before the
    // compositor has told it its real size, and a card placed (or clamped) in
    // that window sits at the top-left corner for a moment before it jumps to
    // where it was saved. place() waits for a believable window instead.
    property bool placed: false

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
        running: WaterTankService.loaded
        onTriggered: win.armed = true
    }

    // `live`: the card is on, or still being swallowed.
    readonly property bool live: win.want || win.reveal > 0.001

    // On screen, or switched on and not suspended by Focus Mode (see ClockWidget.qml).
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while the widget is off: a full-screen transparent layer that is only
    // sitting there still costs the compositor a blend on every frame.
    visible: WaterTankService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock: the widgets rest on Background (mapped after the wallpaper,
    // so over it) and the dock is on Bottom or Top, so the dock is never behind a widget.
    // Up a layer while this widget is edited or moved (EditChrome.raised), so the one
    // edited last is in front of the other widgets (see EditChrome.qml); Bottom is as far
    // up as it goes, because the dock is on Top while editing (see Dock.qml).
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-watertank"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
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
    // (In real window pixels, so it is the card's design rectangle times the
    // scale.)
    mask: Region {
        item: cardMask
    }

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

    // ===== the water =====
    // The day's count, the goal and the size of a glass are WaterTankService's. This is what the
    // window adds: the count starts again after midnight (checked once a minute while it is on
    // screen or Edit Desktop is open), and a glass played into the face that is up.
    Timer {
        interval: 60000
        running: win.working || EditMode.active
        repeat: true
        triggeredOnStart: true
        onTriggered: WaterTankService.checkDay()
    }

    // A glass was added: the face squashes and throws its puff; the glass that reaches the goal
    // throws the big burst instead.
    function popFace(big): void {
        const f = card.tiny ? tinyLoader.item : fullLoader.item
        if (!f)
            return
        if (big)
            f.cheer()
        else
            f.pop()
    }

    Connections {
        target: WaterTankService
        function onGlassAdded() {
            win.popFace(WaterTankService.done && WaterTankService.glasses === WaterTankService.goal)
        }
    }

    // The last seven days (oldest first, today last) and the streak, for the 2 x 2.
    readonly property string todayKey: WaterTankService.day !== "" ? WaterTankService.day : WTM.dayKey(new Date())
    readonly property var bars: WTM.weekBars(WaterTankService.history, WaterTankService.glasses, win.todayKey, 7)
    readonly property int streak: WTM.streak(WaterTankService.history, WaterTankService.glasses, WaterTankService.goal, win.todayKey)

    // ===== placement =====
    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        // Not before the saved spot has been read, and not while the window is
        // still smaller than the card (the clamp below would put it at 0, 0).
        if (!force && (!WaterTankService.loaded || win.roomW < card.width || win.roomH < card.height))
            return
        let x = win.spotX
        let y = win.spotY
        if (x < 0 || y < 0) {
            x = 728
            y = 396
        } else if (win.spotScale > 0 && win.uiScale > 0) {
            // Saved at another shell scale: same spot on the screen, not the
            // same design pixels (the card keeps its top-left corner).
            const k = win.spotScale / win.uiScale
            x *= k
            y *= k
        }
        card.x = Math.max(0, Math.min(x, win.roomW - card.width))
        card.y = Math.max(0, Math.min(y, win.roomH - card.height))
        win.placed = true
    }

    // After a reload the window, the monitor list and scale.json all settle
    // over a few frames; place again once they have, so the card always ends
    // on its saved spot (never while it is being dragged).
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            // A position saved before the scale was kept with it: it was in design
            // pixels of the scale in use now (nothing has changed it since), so
            // keep that from here on.
            if (win.spotReady && win.spotX >= 0 && win.spotScale <= 0 && !dragArea.drag.active)
                win.fixSpotScale()
            if (!chrome.dragging && !dragArea.drag.active)
                win.place(!win.placed && WaterTankService.loaded)
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
        target: WaterTankService
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

    // 1 = in place. (A preset's shrink-away motion is optional polish, see PresetMotion.qml:
    // this widget just uses its normal pop-in and swallow when a preset changes it.)
    readonly property real swapK: 1

    Timer {
        id: glideEnd
        interval: 640
        onTriggered: {
            win.glideOn = false
            win.gliding = false
        }
    }

    // Edit Desktop's shelf shows the card as it really looks: a picture of it,
    // taken every second while the mode is on (EditPreview.qml).
    EditPreview {
        widgetId: "watertank"
        target: card
        pixelRatio: win.uiScale
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

                // The same footprint as the clock's KEYS card: its content is
                // 286 x 238, and the housing adds the inset on every side plus
                // the hard shadow underneath.
                // The 1 x 1 size (WaterTankService.size) is a quarter of it: 120 x 94 of content,
                // 154 x 132 with the housing. It shows one glass you tap (WaterTile.qml).
                readonly property bool tiny: WaterTankService.tiny
                readonly property int contentW: card.tiny ? 120 : 286
                readonly property int contentH: card.tiny ? 94 : 238
                readonly property int inset: mt.borderWidth + mt.outerRingWidth + 10

                width: card.contentW + card.inset * 2
                height: card.contentH + card.inset * 2 + mt.shadowOffset

                scale: Math.max(0, win.reveal) * (win.placed ? 1 : 0) * (0.7 + 0.3 * Math.max(0, win.swapK))
                opacity: Math.max(0, Math.min(1, win.swapK))
                transformOrigin: Item.Center

                // A new size (a different scale, a different monitor) keeps the
                // card on screen; not while it is being dragged, then the drag
                // owns the position.
                onWidthChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                onHeightChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                // The housing: the same navy outline / pale ring / surface fill /
                // hard shadow as the bar, the dock, the To-Do card and the clock.
                // Not drawn at 1 x 1: that size is one bare object on the wallpaper (TinyFoot.qml).
                Pill {
                    visible: !card.tiny
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
                    widgetId: "watertank"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: win.saveSpot(card.x, card.y)
                    onRemoveRequested: EditMode.removeFrom("watertank", win.screen ? win.screen.name : "")
                }

                // Left button: drag the card on the normal desktop, unless Lock all
                // is on (EditMode.desktopDragAllowed; while editing, the shield in
                // EditChrome.qml does the moving instead, until the card is
                // selected for editing: then this does). Sits UNDER the content, so
                // the keys and the disc win their own clicks and everything else
                // on the card is "grab here".
                MouseArea {
                    id: dragArea
                    z: 1
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    // The 1 x 1 glass lights up when pointed at, and a click on it is a glass of water.
                    hoverEnabled: card.tiny
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                        : (card.tiny ? Qt.PointingHandCursor : Qt.ArrowCursor)

                    // Where the card was when the button went down: a click that ended after the card
                    // was dragged somewhere else is a drop, not a glass.
                    property point pressSpot: Qt.point(0, 0)
                    onPressed: pressSpot = Qt.point(card.x, card.y)

                    // The 1 x 1 glass: a click is +1. (At 2 x 2 the + and - keys do it.) Not while
                    // Edit Desktop is open or the card is selected there: then a click only selects.
                    onClicked: {
                        if (!card.tiny || EditMode.active || chrome.selected)
                            return
                        if (Math.abs(card.x - pressSpot.x) + Math.abs(card.y - pressSpot.y) > 3)
                            return
                        WaterTankService.addGlass()
                    }

                    // The wheel: up is a glass, down takes one back.
                    onWheel: wheel => {
                        if (EditMode.active || chrome.selected) {
                            wheel.accepted = false
                            return
                        }
                        if (wheel.angleDelta.y > 0)
                            WaterTankService.addGlass()
                        else if (wheel.angleDelta.y < 0)
                            WaterTankService.removeGlass()
                    }

                    drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, win.roomW - card.width)
                    drag.minimumY: 0
                    drag.maximumY: Math.max(0, win.roomH - card.height)

                    // Remember the new spot when a drag ends (also when it is cut
                    // short). A plain click doesn't save anything, so a card that
                    // is squeezed onto a small screen for a moment can't overwrite
                    // where you put it.
                    drag.onActiveChanged: {
                        // Edit Desktop's alignment grid (EditChrome.qml) needs to know
                        // about a drag that is not its own shield's.
                        chrome.ownDrag = drag.active
                        if (!drag.active)
                            win.saveSpot(card.x, card.y)
                    }
                }

                // Edit Desktop: flip between 2 x 2 and 1 x 1 (only while the card is selected).
                SizeKey {
                    shown: chrome.selected
                    small: card.tiny
                    label: "SIZE  " + (card.tiny ? "1 x 1" : "2 x 2")
                    onToggled: WaterTankService.toggleSize()
                }

                // ===== the content =====
                Item {
                    id: content
                    z: 2
                    x: card.inset
                    y: card.inset
                    width: card.contentW
                    height: card.contentH

                    // Only the size in use is built.
                    Loader {
                        id: tinyLoader
                        active: card.tiny
                        sourceComponent: tinyFace
                    }

                    Loader {
                        id: fullLoader
                        active: !card.tiny
                        sourceComponent: fullFace
                    }

                    // ===== 1 x 1: one glass you tap =====
                    Component {
                        id: tinyFace

                        WaterTile {
                            width: card.contentW
                            height: card.contentH
                            glasses: WaterTankService.glasses
                            goal: WaterTankService.goal
                            level: WaterTankService.level
                            done: WaterTankService.done
                            amountText: WaterTankService.amountText
                            hover: dragArea.containsMouse
                            pressed: dragArea.pressed
                        }
                    }

                    // ===== 2 x 2: the glass and the count, the keys, the week and the streak =====
                    Component {
                        id: fullFace

                        Item {
                            id: face
                            width: card.contentW
                            height: card.contentH

                            // The glass squashes and throws a puff (a glass was added), or the big burst (the goal).
                            function pop() {
                                squish.restart()
                                puff.fire()
                            }

                            function cheer() {
                                squish.restart()
                                cheerBurst.fire()
                            }

                            // What the water shows: it eases to the level with an overshoot.
                            property real shownLevel: WaterTankService.level

                            Behavior on shownLevel {
                                NumberAnimation { duration: 820; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                            }

                            // ===== the title row: the tab on the left, the streak on the right =====
                            Slant {
                                id: titleTab
                                x: 2
                                y: 0
                                width: 104
                                height: 26
                                skew: 0.2
                                radius: 9
                                color: mt.chipFill
                                borderColor: mt.pLine
                                borderWidth: 3
                            }

                            // Text goes NEXT to the Slant (a child would lean with it).
                            Row {
                                x: titleTab.x + titleTab.lean / 2 + 10
                                y: titleTab.y
                                height: titleTab.height
                                spacing: 5

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "water_drop"
                                    fill: 0
                                    size: 15
                                    weight: 700
                                    color: mt.dark ? mt.accentMint : mt.colBorder
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "WATER"
                                    color: mt.chipInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    font.letterSpacing: 1.6
                                }
                            }

                            // The streak: days in a row the goal was reached. Lit (mint flame) once there is one.
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 2
                                y: 0
                                height: 26
                                spacing: 5

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "flame"
                                    fill: 0
                                    size: 18
                                    weight: 700
                                    color: win.streak > 0 ? (mt.dark ? mt.accentMint : mt.colBorder) : Qt.rgba(mt.pInk.r, mt.pInk.g, mt.pInk.b, 0.45)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: win.streak > 0 ? win.streak + " DAY STREAK" : "NO STREAK YET"
                                    color: mt.pInk
                                    opacity: win.streak > 0 ? 1 : 0.7
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    font.letterSpacing: 1.0
                                }
                            }

                            // ===== the glass: the water, a tick for every glass of the goal, the count =====
                            Pill {
                                id: glass
                                x: 0
                                y: 32
                                width: 132
                                height: 122
                                cornerRadius: 30
                                ringWidth: mt.borderWidth + mt.whiteLine
                                fillColor: mt.pSurface
                                fillGradient: Gradient {
                                    GradientStop { position: 0.0; color: mt.pSurface }
                                    GradientStop { position: 1.0; color: Qt.tint(mt.pSurface, Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.18)) }
                                }

                                property real sx: 1
                                property real sy: 1

                                transform: Scale {
                                    origin.x: glass.width / 2
                                    origin.y: glass.height / 2
                                    xScale: glass.sx
                                    yScale: glass.sy
                                }

                                WaterFill {
                                    anchors.fill: parent
                                    radius: glass.cornerRadius - glass.ringWidth
                                    level: face.shownLevel
                                    marks: WaterTankService.goal
                                }

                                // The goal, at the top ("GOAL!" once it is reached).
                                Pill {
                                    x: (parent.width - width) / 2 - 6
                                    y: 8
                                    width: goalLabel.implicitWidth + 24
                                    height: 27
                                    shadowDy: 3
                                    cornerRadius: 12
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: WaterTankService.done ? mt.accentMint : mt.chipFill

                                    Text {
                                        id: goalLabel
                                        anchors.centerIn: parent
                                        text: WaterTankService.done ? "GOAL!" : "OF " + WaterTankService.goal
                                        color: WaterTankService.done ? mt.colBorder : mt.chipInk
                                        font.family: mt.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                        font.letterSpacing: 1.2
                                    }
                                }

                                // The glasses you have had, in the middle, over the water.
                                StickerText {
                                    x: (parent.width - width) / 2 - 6
                                    y: (parent.height - height) / 2 + 12
                                    text: String(WaterTankService.glasses)
                                    pixelSize: String(WaterTankService.glasses).length <= 1 ? 72 : 56
                                    fillColor: Qt.darker(mt.colBorder, 1.8)
                                    ringColor: "#ffffff"
                                }
                            }

                            SequentialAnimation {
                                id: squish
                                ParallelAnimation {
                                    NumberAnimation { target: glass; property: "sx"; to: 1.06; duration: 80; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: glass; property: "sy"; to: 0.95; duration: 80; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: glass; property: "sx"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                    NumberAnimation { target: glass; property: "sy"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                }
                            }

                            Burst {
                                id: puff
                                x: glass.x + glass.width / 2
                                y: glass.y + glass.height / 2
                                radius: 70
                                count: 8
                            }

                            Burst {
                                id: cheerBurst
                                x: glass.x + glass.width / 2
                                y: glass.y + glass.height / 2
                                radius: 100
                                count: 14
                                size: 11
                            }

                            // ===== the right side: how much, and the two keys =====
                            Item {
                                id: side
                                x: 144
                                y: 32
                                width: face.width - 144
                                height: 122

                                // How much you have had, big; of how much, small under it.
                                Text {
                                    x: 2
                                    y: 0
                                    width: side.width - 4
                                    elide: Text.ElideRight
                                    text: WaterTankService.amountText.toUpperCase()
                                    color: mt.pInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 24
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }

                                Text {
                                    x: 2
                                    y: 30
                                    width: side.width - 4
                                    elide: Text.ElideRight
                                    text: "OF " + WaterTankService.goalText.toUpperCase() + " TODAY"
                                    color: mt.pInk
                                    opacity: 0.75
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    font.letterSpacing: 1.2
                                }

                                // ===== the keys: take one back, drink one =====
                                Pill {
                                    id: minusKey
                                    x: 0
                                    y: 62
                                    width: 56
                                    height: 60
                                    shadowDy: 4
                                    cornerRadius: 18
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.chipFill
                                    pressed: minusArea.pressed

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        name: "remove"
                                        size: 26
                                        color: mt.chipInk
                                    }

                                    MouseArea {
                                        id: minusArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WaterTankService.removeGlass()
                                    }
                                }

                                Pill {
                                    id: plusKey
                                    x: 64
                                    y: 62
                                    width: side.width - 64
                                    height: 60
                                    shadowDy: 4
                                    cornerRadius: 18
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.accentMint
                                    pressed: plusArea.pressed

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        name: "add"
                                        size: 36
                                        color: mt.colBorder
                                    }

                                    MouseArea {
                                        id: plusArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WaterTankService.addGlass()
                                    }
                                }
                            }

                            // ===== the last seven days, today on the right =====
                            Row {
                                id: weekRow
                                x: 2
                                y: 168
                                spacing: 6

                                Repeater {
                                    model: win.bars

                                    delegate: Item {
                                        id: dayCol
                                        required property var modelData

                                        readonly property real frac: WTM.fraction(dayCol.modelData.count, WaterTankService.goal)

                                        width: Math.floor((face.width - 4 - 36) / 7)
                                        height: 68

                                        Rectangle {
                                            id: track
                                            width: parent.width
                                            height: 46
                                            radius: 11
                                            color: Qt.rgba(mt.pInk.r, mt.pInk.g, mt.pInk.b, 0.14)
                                            border.width: 2
                                            border.color: dayCol.modelData.today ? mt.accentMint : Qt.rgba(mt.pInk.r, mt.pInk.g, mt.pInk.b, 0.35)
                                            antialiasing: true

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.margins: 2
                                                height: dayCol.modelData.count > 0 ? Math.max(8, (track.height - 4) * dayCol.frac) : 0
                                                radius: 9
                                                color: (dayCol.modelData.today || dayCol.frac >= 1) ? mt.accentMint : Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.85)
                                                antialiasing: true
                                            }

                                            // A day that reached the goal wears a small diamond.
                                            Rectangle {
                                                visible: dayCol.frac >= 1
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: 9
                                                width: 7
                                                height: 7
                                                radius: 1.5
                                                rotation: 45
                                                color: mt.colBorder
                                                antialiasing: true
                                            }
                                        }

                                        Text {
                                            anchors.top: track.bottom
                                            anchors.topMargin: 5
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.locale().dayName(dayCol.modelData.weekday, Locale.NarrowFormat).toUpperCase()
                                            color: mt.pInk
                                            opacity: dayCol.modelData.today ? 1 : 0.7
                                            font.family: mt.fontFamily
                                            font.pixelSize: 11
                                            font.weight: dayCol.modelData.today ? Font.ExtraBold : Font.DemiBold
                                            font.styleName: mt.fontStyleBold
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
