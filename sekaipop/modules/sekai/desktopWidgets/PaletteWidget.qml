import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode
import qs.modules.sekai.palette
import "../../common/functions/PaletteMath.js" as PM

// The desktop Palette card: five colours, a source tab, and your favourites, sitting on
// the desktop under your windows, over the wallpaper, with the same drag, lock, scale,
// monitors, Edit Desktop and Focus Mode as the calendar card and the weather card.
//
//   The tabs        Wallpaper / Music / Random. Wallpaper reads the picture on screen, Music
//                   the cover of the playing track, Random makes a colour-wheel harmony.
//                   Tapping the tab you are on reads it again (or shuffles, for Random).
//   The swatches    click one to copy its HEX; the padlock (or right-click) keeps it through
//                   a shuffle or a new picture. Space shuffles while the card has the keyboard.
//   The keys        Shuffle, Save (to the favourites), Copy all, and "Apply to theme".
//   Favourites      a row of saved palettes; click one to bring it back, the cross removes it.
//   The corner key  opens the big Palette tool (live preview of the shell in these colours).
//
// THE RULE the Palette tool keeps holds here too: looking never changes the theme. The
// strip, the shuffle, the locks, the favourites and the copy keys only change
// PaletteService's own state. The theme changes only when you press "Apply to theme"
// (PaletteService.apply(), the one primary key below) and Undo puts the old theme back.
//
// The colours are yours and live in services/PaletteService.qml (the same ones the big
// tool shows, remembered across restarts). The card is OFF until you add it (Edit
// Desktop's shelf, Settings -> Desktop, or the ipc), and a desktop preset does not carry it.
//
// How the moving works: exactly like CalendarCardWidget.qml. ONE transparent window with
// the card as an Item inside it. Dragging just moves that Item, so it stays smooth, and the
// window's input `mask` is only the card, so every click anywhere else passes straight
// through to whatever is underneath.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call palettecard toggle          (show / hide)
//   qs -c sekaipop ipc call palettecard shuffle         (a new random strip; the theme is untouched)
//   qs -c sekaipop ipc call palettecard resetPosition   (if it ever ends up off-screen)

PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    function resetPosition(): void {
        win.clearSpot();
        win.place(true);
        win.saveSpot(card.x, card.y);
    }

    // Which monitor it lives on, by name (`hyprctl monitors`), e.g. "DP-1".
    // Empty = the monitor the card was last dropped on (remembered in PaletteService),
    // or the first screen if it has never been moved.
    property string monitor: ""

    // A copy on another monitor (WidgetClones.qml): the same widget, with a spot of its own. The main
    // copy keeps its spot in the service as before.
    property bool clone: false

    readonly property var cloneSpot: win.clone ? WidgetClones.spot("palettecard", win.wantedScreen) : null
    readonly property bool spotReady: win.clone ? (WidgetClones.loaded && win.cloneSpot !== null) : PaletteService.loaded
    readonly property real spotX: win.clone ? (win.cloneSpot ? win.cloneSpot.x : -1) : PaletteService.posX
    readonly property real spotY: win.clone ? (win.cloneSpot ? win.cloneSpot.y : -1) : PaletteService.posY
    readonly property real spotScale: win.clone ? (win.cloneSpot ? win.cloneSpot.scale : 0) : PaletteService.posScale

    function saveSpot(x, y): void {
        if (win.clone)
            WidgetClones.setSpot("palettecard", win.wantedScreen, x, y, win.uiScale)
        else
            PaletteService.setPosition(x, y, win.screen ? win.screen.name : "", win.uiScale)
    }

    function clearSpot(): void {
        if (win.clone) {
            WidgetClones.clearSpot("palettecard", win.wantedScreen)
        } else {
            PaletteService.posX = -1
            PaletteService.posY = -1
        }
    }

    function fixSpotScale(): void {
        if (win.clone) {
            WidgetClones.setSpot("palettecard", win.wantedScreen, win.spotX, win.spotY, win.uiScale)
        } else {
            PaletteService.posScale = win.uiScale
            PaletteService.persist()
        }
    }

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : PaletteService.screenName
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    // This monitor's scale (scale.json / services/ShellScale.qml). The card is drawn in
    // design pixels inside a ScaleHost, so `roomW` x `roomH` is the screen as the card sees
    // it (real size / scale); positions are kept in that same design space.
    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real fullW: win.screen ? win.screen.width : 0
    readonly property real fullH: win.screen ? win.screen.height : 0
    readonly property real roomW: win.fullW / win.uiScale
    readonly property real roomH: win.fullH / win.uiScale

    // ===== a small window while nothing needs the whole screen =====
    // See CalendarCardWidget.qml: at rest the window is just the card plus some room around
    // it, and only Edit Desktop (and dragging on an unlocked desktop) gets the full screen
    // back. Everything inside still lives in screen coordinates: `shifter` slides the whole
    // stage by the window's own position.
    readonly property bool compact: !EditMode.active && !win.gliding && EditMode.screenName === ""
        && EditMode.compactWindows && !EditMode.desktopDragAllowed && win.fullW > 0 && win.placed
    readonly property real boxPad: Math.ceil((0.16 * Math.max(card.width, card.height) + 24) * win.uiScale)
    readonly property real boxX: win.compact ? Math.max(0, Math.floor(card.x * win.uiScale - win.boxPad)) : 0
    readonly property real boxY: win.compact ? Math.max(0, Math.floor(card.y * win.uiScale - win.boxPad)) : 0
    readonly property real boxW: Math.max(1, Math.min(win.fullW,
        Math.ceil((card.x + card.width) * win.uiScale + win.boxPad)) - win.boxX)
    readonly property real boxH: Math.max(1, Math.min(win.fullH,
        Math.ceil((card.y + card.height) * win.uiScale + win.boxPad)) - win.boxY)

    // On / off: the card pops in with a little overshoot and is swallowed (straight shrink)
    // on the way out; the window stays up until the swallow has finished. Two fixed
    // animations, started from onWantChanged (see WeatherCardWidget.qml).
    //
    // Desktop Focus Mode (FocusGate.qml): `gate.show` is false while an application is on
    // this monitor's workspace, so `want` goes false and the swallow + unmap hide it.
    FocusGate {
        id: gate
        widgetId: "palettecard"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: PaletteService.shown && PaletteService.loaded
    readonly property bool want: win.switchedOn && gate.show
    property real reveal: 0

    // Off while the saved state is read back, so a reload doesn't replay the pop.
    property bool armed: false

    // Stays false until the card has been put on its saved spot, and keeps it drawn at
    // size 0 until then (after a reload the window maps before the compositor has told it
    // its real size).
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
        running: PaletteService.loaded
        onTriggered: win.armed = true
    }

    // `live`: the card is on, or still being swallowed.
    readonly property bool live: win.want || win.reveal > 0.001

    // On screen, or switched on and not suspended by Focus Mode.
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while the widget is off: a transparent layer that is only sitting there
    // still costs the compositor a blend on every frame.
    visible: PaletteService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock (see WeatherCardWidget.qml), up a layer while edited / moved.
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-palettecard"
    // Not while editing: the shelf keeps the keyboard then (Esc), and a click on a card must
    // not take it away. The exception is this card while it is selected for editing.
    WlrLayershell.keyboardFocus: (EditMode.active && EditMode.editTarget !== "palettecard") || !keys.wanted
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
    mask: Region {
        item: cardMask
    }

    // Edit Desktop widens the card's rectangle a little (its outline and tag sit half
    // outside it); `stage` is the transform the content is drawn with.
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

    // ===== the colours =====
    // Where the music cover comes from (the bar, the dock and the lockscreen each have
    // their own MediaSource too). Only built while the card is working.
    Loader {
        active: win.working

        sourceComponent: Item {
            visible: false

            MediaSource {
                id: media
            }

            // Reads the wallpaper or the cover while the card is on screen. While the big
            // tool is open it has its own extractor, so this one steps aside (and does not
            // count the colours twice). The colours it reads go to PaletteService only.
            PaletteExtractor {
                id: extractor
                kind: PaletteService.source
                active: win.working && !PaletteService.toolOpen
                media: media

                Component.onCompleted: win.reader = extractor
                Component.onDestruction: if (win.reader === extractor) win.reader = null
            }
        }
    }

    // The extractor, once the loader above has built it (the tabs call push() on it).
    property var reader: null

    readonly property string note: {
        if (PaletteService.source === "random")
            return PaletteService.scheme !== "" ? ("Harmony: " + PaletteService.scheme) : "Press Shuffle or Space"
        if (win.reader && win.reader.problem !== "")
            return win.reader.problem
        return PaletteService.source === "music" ? "From the cover of the playing track" : "From the wallpaper on screen"
    }

    // The little "Copied" on the Copy all key.
    property bool copiedAll: false

    Timer {
        id: copiedAllTimer
        interval: 1000
        onTriggered: win.copiedAll = false
    }

    // ===== placement =====
    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        // Not before the saved spot has been read, and not while the window is still
        // smaller than the card (the clamp below would put it at 0, 0).
        if (!force && (!PaletteService.loaded || win.roomW < card.width || win.roomH < card.height))
            return
        let x = win.spotX
        let y = win.spotY
        if (x < 0 || y < 0) {
            // The first spot: low on the right, above the dock.
            x = win.roomW - card.width - 48
            y = win.roomH - card.height - 120
        } else if (win.spotScale > 0 && win.uiScale > 0) {
            // Saved at another shell scale: same spot on the screen, not the same design
            // pixels (the card keeps its top-left corner).
            const k = win.spotScale / win.uiScale
            x *= k
            y *= k
        }
        card.x = Math.max(0, Math.min(x, win.roomW - card.width))
        card.y = Math.max(0, Math.min(y, win.roomH - card.height))
        win.placed = true
    }

    // After a reload the window, the monitor list and scale.json all settle over a few
    // frames; place again once they have, so the card always ends on its saved spot (never
    // while it is being dragged).
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            if (win.spotReady && win.spotX >= 0 && win.spotScale <= 0 && !dragArea.drag.active)
                win.fixSpotScale()
            if (!chrome.dragging && !dragArea.drag.active)
                win.place(!win.placed && PaletteService.loaded)
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

    // The spot of a copy changed (a drag, a reset): put the card there.
    Connections {
        target: WidgetClones
        enabled: win.clone
        function onSpotsChanged() { follow.restart() }
    }

    Connections {
        target: PaletteService
        function onLoadedChanged() {
            win.place()
            settle.restart()
        }
        // Something else (Edit Desktop moving the card to this monitor) hands the service
        // another spot while the card is on screen. The spot arrives as several properties
        // one after the other, so wait a beat and place once.
        function onPosXChanged() { follow.restart() }
        function onPosYChanged() { follow.restart() }
        function onPosScaleChanged() { follow.restart() }
    }

    // The card glides to its new spot instead of jumping (not while it is being dragged, and
    // not when it is already where it should be). `gliding` first, so a small window grows to
    // the whole screen (see `compact`), then `glideOn` switches the Behaviors on.
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

    Timer {
        id: glideEnd
        interval: 640
        onTriggered: {
            win.glideOn = false
            win.gliding = false
        }
    }

    // Edit Desktop's shelf shows the card as it really looks: a picture of it, taken every
    // second while the mode is on (EditPreview.qml).
    EditPreview {
        widgetId: win.clone ? "" : "palettecard"
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

    // Edit Desktop shrinks every desktop window into the same card with the same transform
    // (see EditStage.qml / services/EditMode.qml). Out of edit mode this is a no-op: scale 1,
    // no offset.
    EditStage {
        id: stage
        screenObj: win.screen
        uiScale: win.uiScale

        ScaleHost {
            anchors.fill: parent
            factor: win.uiScale

            Item {
                id: card

                // Gliding to a new spot (win.glideOn, see `follow`). Off the rest of the time,
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

                // The content is as tall as its parts (below); the housing adds the inset on
                // every side plus the hard shadow underneath.
                // The 2 x 2 size (PaletteService.size) is the footprint the clock, user card and
                // weather card share: 286 x 238 of content, 320 x 276 with the housing. It is the
                // same card, not another one: the same keys (so still exactly one Apply and one
                // Undo), with the note and the favourites left out and the swatches smaller.
                readonly property bool small: PaletteService.small
                // The 1 x 1 size is a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with
                // the housing, which is not drawn at 1 x 1. It is a keycap with a fan of the five
                // colours (PaletteTile.qml); a click shuffles.
                readonly property bool tiny: PaletteService.tiny
                readonly property int contentW: card.tiny ? 120 : (card.small ? 286 : 396)
                readonly property int contentH: card.tiny ? 94 : (card.small ? 238 : col.implicitHeight)
                readonly property int inset: mt.borderWidth + mt.outerRingWidth + 10

                width: card.contentW + card.inset * 2
                height: card.contentH + card.inset * 2 + mt.shadowOffset

                scale: Math.max(0, win.reveal) * (win.placed ? 1 : 0)
                opacity: win.reveal > 0.001 ? 1 : 0
                transformOrigin: Item.Center

                // Space shuffles while the card has the keyboard (a click on the bare card
                // takes it; Esc leaves it).
                Keys.onSpacePressed: PaletteService.shuffle()

                // A new size (a different scale, a different monitor) keeps the card on screen;
                // not while it is being dragged, then the drag owns the position.
                onWidthChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                onHeightChanged: {
                    if (!chrome.dragging && !dragArea.drag.active)
                        win.place()
                }

                // The housing: the same navy outline / pale ring / surface fill / hard shadow
                // as the bar, the dock, the To-Do card and the clock.
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

                // Edit Desktop: outline, corner diamonds, a tag and a drag shield
                // (EditChrome.qml). Draws nothing outside the mode.
                EditChrome {
                    id: chrome
                    widgetId: "palettecard"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: win.saveSpot(card.x, card.y)
                    onRemoveRequested: EditMode.removeFrom("palettecard", win.screen ? win.screen.name : "")
                }

                // Left button: drag the card on the normal desktop, unless Lock all is on
                // (EditMode.desktopDragAllowed; while editing, the shield in EditChrome.qml does
                // the moving instead, until the card is selected for editing: then this does).
                // Sits UNDER the content, so the keys, the swatches and the favourites win their
                // own clicks and everything else is "grab here".
                MouseArea {
                    id: dragArea
                    z: 1
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    // The 1 x 1 fan opens a little when pointed at.
                    hoverEnabled: card.tiny
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

                    drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, win.roomW - card.width)
                    drag.minimumY: 0
                    drag.maximumY: Math.max(0, win.roomH - card.height)

                    // Remember the new spot when a drag ends (also when it is cut short). A plain
                    // click doesn't save anything.
                    drag.onActiveChanged: {
                        chrome.ownDrag = drag.active
                        if (!drag.active)
                            win.saveSpot(card.x, card.y)
                    }

                    // A click on the bare card takes the keyboard (for Space).
                    onPressed: card.forceActiveFocus()

                    // At 1 x 1 the whole tile is the shuffle key (a drag is not a click, so it
                    // still moves the card).
                    onClicked: {
                        if (card.tiny)
                            PaletteService.shuffle()
                    }
                }

                // Edit Desktop: step through FULL, 2 x 2 and 1 x 1 (only while the card is selected).
                SizeKey {
                    shown: chrome.selected
                    small: card.tiny
                    label: "SIZE  " + (card.tiny ? "1 x 1" : (card.small ? "2 x 2" : "FULL"))
                    onToggled: PaletteService.toggleSize()
                }

                // ===== the 1 x 1 face =====
                Loader {
                    id: tinyLoader
                    z: 2
                    x: card.inset
                    y: card.inset
                    active: card.tiny
                    sourceComponent: tinyFace
                }

                Component {
                    id: tinyFace

                    PaletteTile {
                        width: card.contentW
                        height: card.contentH
                        colors: PaletteService.colors
                        locks: PaletteService.locks
                        hover: dragArea.containsMouse
                        pressed: dragArea.pressed
                    }
                }

                // ===== the content =====
                Item {
                    id: content
                    z: 2
                    visible: !card.tiny
                    x: card.inset
                    y: card.inset
                    width: card.contentW
                    height: card.contentH

                    Column {
                        id: col
                        width: card.contentW
                        // 2 x 2: header 30 + source 28 + swatches 88 + keys 37 + apply 37 = 220, and
                        // 4 between the five = 236 of the 238.
                        spacing: card.small ? 4 : 10

                        // ===== header =====
                        Item {
                            width: parent.width
                            height: card.small ? 30 : 32

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "palette"
                                    size: 24
                                    color: mt.pInk
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Palette"
                                    color: mt.pInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: card.small ? 18 : 20
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                // says out loud whether the theme is being touched
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 26
                                    width: statusRow.implicitWidth + 18
                                    radius: 13
                                    antialiasing: true
                                    color: PaletteService.applied ? mt.accentMint : mt.surfaceHover
                                    border.width: 2
                                    border.color: mt.line

                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Row {
                                        id: statusRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: PaletteService.applied ? "check_circle" : "visibility"
                                            size: 15
                                            color: PaletteService.applied ? mt.colBorder : mt.ink
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: PaletteService.applied ? "Applied" : "Preview only"
                                            color: PaletteService.applied ? mt.colBorder : mt.ink
                                            font.family: mt.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.ExtraBold
                                            font.styleName: mt.fontStyleBold
                                        }
                                    }
                                }

                                // Opens the big tool: live preview of the shell in these colours.
                                Rectangle {
                                    id: expandBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    height: 28
                                    radius: 14
                                    antialiasing: true
                                    color: expandMouse.containsMouse ? mt.surfaceTint : mt.surfaceHover
                                    border.width: 2
                                    border.color: mt.line

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: "open_in_full"
                                        size: 15
                                        color: mt.ink
                                    }

                                    MouseArea {
                                        id: expandMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: PaletteService.requestOpen()
                                    }
                                }
                            }
                        }

                        // ===== where the colours come from =====
                        SegmentSwitch {
                            width: parent.width
                            height: card.small ? 28 : 32
                            options: [
                                { id: "wallpaper", label: "Wallpaper" },
                                { id: "music", label: "Music" },
                                { id: "random", label: "Random" }
                            ]
                            current: PaletteService.source
                            onPicked: id => {
                                if (id === "random") {
                                    PaletteService.shuffle()
                                } else if (id === PaletteService.source) {
                                    if (win.reader)
                                        win.reader.push()
                                } else {
                                    PaletteService.setSource(id)
                                }
                            }
                        }

                        Text {
                            visible: !card.small
                            width: parent.width
                            elide: Text.ElideRight
                            color: mt.pInkSub
                            font.family: mt.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            text: win.note
                        }

                        // ===== the swatches =====
                        Row {
                            id: swatches
                            width: parent.width
                            spacing: (width - 5 * (card.small ? 52 : 71)) / 4

                            Repeater {
                                model: 5

                                delegate: PaletteSwatch {
                                    required property int index

                                    compact: !card.small
                                    mini: card.small
                                    width: card.small ? 52 : 71
                                    hex: PaletteService.colors[index] ?? "#000000"
                                    locked: PaletteService.locks[index] === true
                                    onCopyRequested: {
                                        if (PaletteService.copy(hex))
                                            flashCopied()
                                    }
                                    onLockToggled: PaletteService.toggleLock(index)
                                }
                            }
                        }

                        // ===== actions =====
                        Row {
                            spacing: 8

                            PaletteButton {
                                icon: "casino"
                                label: "Shuffle"
                                onClicked: PaletteService.shuffle()
                            }

                            PaletteButton {
                                icon: "favorite"
                                label: card.small ? "" : (PaletteService.isFavorite ? "Saved" : "Save")
                                lit: PaletteService.isFavorite
                                onClicked: PaletteService.toggleFavorite()
                            }

                            PaletteButton {
                                icon: win.copiedAll ? "check" : "content_copy"
                                label: card.small ? "" : (win.copiedAll ? "Copied" : "Copy all")
                                onClicked: {
                                    PaletteService.copyAll()
                                    win.copiedAll = true
                                    copiedAllTimer.restart()
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: applyBtn.implicitHeight

                            // the ONE key on this card that changes the theme
                            PaletteButton {
                                id: applyBtn
                                anchors.left: parent.left
                                width: undoBtn.visible ? parent.width - undoBtn.width - 8 : parent.width
                                primary: true
                                enabled: !PaletteService.applied
                                icon: PaletteService.applied ? "check" : "format_paint"
                                label: PaletteService.applied ? "Applied" : "Apply to theme"
                                onClicked: PaletteService.apply()
                            }

                            PaletteButton {
                                id: undoBtn
                                anchors.right: parent.right
                                visible: PaletteService.canUndo
                                icon: "undo"
                                label: "Undo"
                                onClicked: PaletteService.undo()
                            }
                        }

                        // ===== favourites =====
                        Column {
                            visible: !card.small
                            width: parent.width
                            spacing: 6

                            Text {
                                text: "FAVOURITES" + (PaletteService.favorites.length > 0 ? " (" + PaletteService.favorites.length + ")" : "")
                                color: mt.pInkSub
                                font.family: mt.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.ExtraBold
                                font.letterSpacing: 0.8
                            }

                            Text {
                                visible: PaletteService.favorites.length === 0
                                width: parent.width
                                text: "Press Save to keep a palette here."
                                wrapMode: Text.WordWrap
                                color: mt.pInkSub
                                font.family: mt.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }

                            Flickable {
                                id: favFlick
                                visible: PaletteService.favorites.length > 0
                                width: parent.width
                                height: 44
                                contentWidth: favRow.width
                                contentHeight: height
                                flickableDirection: Flickable.HorizontalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                clip: contentWidth > width

                                // a plain wheel scrolls the row sideways
                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: event => {
                                        const d = mt.wheelPx(event, true)
                                        favFlick.contentX = Math.max(0, Math.min(Math.max(0, favFlick.contentWidth - favFlick.width), favFlick.contentX - d))
                                    }
                                }

                                Row {
                                    id: favRow
                                    y: 4
                                    spacing: 10

                                    Repeater {
                                        model: PaletteService.favorites

                                        delegate: PaletteFavorite {
                                            required property var modelData

                                            colors: modelData.colors
                                            current: PM.sameColors(modelData.colors, PaletteService.colors)
                                            onPicked: PaletteService.useFavorite(modelData.colors)
                                            onRemoved: PaletteService.removeFavorite(modelData.colors)
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

    // Asks for the keyboard only under the pointer or while typing (issue #72).
    KeysOnPoint {
        id: keys
    }
}
