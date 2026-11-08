import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common/functions/DownloadMath.js" as DM
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode

// The desktop Downloader: copy a link, press the key, get the file. A cobalt-style "save what
// you love" widget made of the shell's own parts (Pill, StickerText, Burst, Slant, MaterialIcon),
// so it looks like the rest of the desktop cards.
//
// Two sizes (Settings -> Desktop -> Downloader size, the size key on it while it is selected in
// Edit Desktop, or `ipc call downloader size 1x1|2x2`):
//   1 x 1  ONE key (DownloaderTile.qml): GET. Press it and the link on the clipboard is
//          downloaded; the key fills with colour as the file comes in and says SAVED. The wheel
//          changes what it saves (video, audio, mute).
//   2 x 2  (the clock's / user card's footprint) the big paste key on the left (the same fill),
//          a mode key (VIDEO / AUDIO / MUTE) and a quality key (1080P ... or the sound format),
//          the last downloads as rows (click a finished one to open it, a failed one to try it
//          again, the cross cancels or removes it), and the keys for the folder and for
//          clearing the list.
//   Both take a link dropped on them (a link dragged from the browser).
//
// What does the work: scripts/downloader/download.sh, by yt-dlp (videos and sound), gallery-dl
// (pictures and picture posts) on this machine, or a cobalt instance you name in Settings ->
// Desktop -> Downloader; "auto" tries them in turn (services/DownloaderService.qml has the details
// and the queue). A post with several items can ask which ones to save (2 x 2). Nothing runs until
// you press the key.
//
//   Moving it: in Edit Desktop (right-click the desktop) it is always draggable, by the shield in
//   EditChrome.qml; a click on it there selects it for editing, a right-click removes it. On the normal
//   desktop it can be dragged only while "Lock all" (a tile on the Edit Desktop shelf, locked by
//   default) is off, by any part of the card that is not a key.
//
// How the moving works: exactly like DownloaderWidget.qml and UserCardWidget.qml. ONE transparent
// window with the card as an Item inside it. Dragging just moves that Item, and the window's input
// `mask` is only the card, so every click anywhere else passes straight through to whatever is
// underneath. The card never takes keyboard focus.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call downloader toggle         (show / hide)
//   qs -c sekaipop ipc call downloader paste          (download the link on the clipboard)
//   qs -c sekaipop ipc call downloader get <link>     (download a link)
//   qs -c sekaipop ipc call downloader cancel         (stop the running one and the queue)
//   qs -c sekaipop ipc call downloader mode audio     (video | audio | mute)
//   qs -c sekaipop ipc call downloader quality 720    (max | 1080 | 720 | 480)
//   qs -c sekaipop ipc call downloader engine auto    (auto | ytdlp | gallerydl | cobalt)
//   qs -c sekaipop ipc call downloader cookies firefox (the browser whose login to use; "" = none)
//   qs -c sekaipop ipc call downloader subs en        (subtitles language; "" = none)
//   qs -c sekaipop ipc call downloader names pretty   (basic | pretty | classic | nerdy)
//   qs -c sekaipop ipc call downloader ask true       (ask which items of a post to save, at 2 x 2)
//   qs -c sekaipop ipc call downloader folder ~/Videos
//   qs -c sekaipop ipc call downloader open           (open the folder)
//   qs -c sekaipop ipc call downloader clear          (empty the list of finished ones)
//   qs -c sekaipop ipc call downloader status
//   qs -c sekaipop ipc call downloader size 1x1       (or 2x2)
//   qs -c sekaipop ipc call downloader resetPosition  (if it ever ends up off-screen)

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
    // DownloaderService), or the first screen if it has never been moved.
    property string monitor: ""

    readonly property bool spotReady: DownloaderService.loaded
    readonly property real spotX: DownloaderService.posX
    readonly property real spotY: DownloaderService.posY
    readonly property real spotScale: DownloaderService.posScale

    function saveSpot(x, y): void {
        DownloaderService.setPosition(x, y, win.screen ? win.screen.name : "", win.uiScale)
    }

    function clearSpot(): void {
        DownloaderService.posX = -1
        DownloaderService.posY = -1
    }

    function fixSpotScale(): void {
        DownloaderService.posScale = win.uiScale
        DownloaderService.persist()
    }

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : DownloaderService.screenName
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
        widgetId: "downloader"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: DownloaderService.shown && DownloaderService.loaded
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
        running: DownloaderService.loaded
        onTriggered: win.armed = true
    }

    // `live`: the card is on, or still being swallowed.
    readonly property bool live: win.want || win.reveal > 0.001

    // On screen, or switched on and not suspended by Focus Mode (see ClockWidget.qml).
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while the widget is off: a full-screen transparent layer that is only
    // sitting there still costs the compositor a blend on every frame.
    visible: DownloaderService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock: the widgets rest on Background (mapped after the wallpaper,
    // so over it) and the dock is on Bottom or Top, so the dock is never behind a widget.
    // Up a layer while this widget is edited or moved (EditChrome.raised), so the one
    // edited last is in front of the other widgets (see EditChrome.qml); Bottom is as far
    // up as it goes, because the dock is on Top while editing (see Dock.qml).
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-downloader"
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

    // ===== the downloads =====
    // The queue, the options and the numbers are DownloaderService's. This is what the window adds:
    // a little play in the face that is up when something happens.
    function face() {
        return card.tiny ? tinyLoader.item : fullLoader.item
    }

    Connections {
        target: DownloaderService

        // A link was taken: the key squashes and throws its puff.
        function onJobAdded() {
            const f = win.face()
            if (f)
                f.pop()
        }

        // A file is saved: the big burst. One failed: the key says so.
        function onJobFinished(ok) {
            const f = win.face()
            if (!f)
                return
            if (ok)
                f.cheer()
            else
                f.failed()
        }

        // A link that was not taken: the reason, in a chip for a moment.
        function onRejected(why) {
            const f = win.face()
            if (f)
                f.note(DM.shortReason(why))
        }
    }

    // ===== placement =====
    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        // Not before the saved spot has been read, and not while the window is
        // still smaller than the card (the clamp below would put it at 0, 0).
        if (!force && (!DownloaderService.loaded || win.roomW < card.width || win.roomH < card.height))
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
                win.place(!win.placed && DownloaderService.loaded)
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
        target: DownloaderService
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
        widgetId: "downloader"
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
                // The 1 x 1 size (DownloaderService.size) is a quarter of it: 120 x 94 of content,
                // 154 x 132 with the housing. It shows one key you press (DownloaderTile.qml).
                readonly property bool tiny: DownloaderService.tiny
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
                    widgetId: "downloader"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: win.saveSpot(card.x, card.y)
                    onRemoveRequested: EditMode.removeFrom("downloader", win.screen ? win.screen.name : "")
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
                    // The 1 x 1 key lights up when pointed at, and a click on it downloads the link on the clipboard.
                    hoverEnabled: card.tiny
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                        : (card.tiny ? Qt.PointingHandCursor : Qt.ArrowCursor)

                    // Where the card was when the button went down: a click that ended after the card
                    // was dragged somewhere else is a drop, not a press.
                    property point pressSpot: Qt.point(0, 0)
                    onPressed: pressSpot = Qt.point(card.x, card.y)

                    // The 1 x 1 key: a click downloads the link on the clipboard. (At 2 x 2 the big key does
                    // it.) Not while Edit Desktop is open or the card is selected there: then a click only selects.
                    onClicked: {
                        if (!card.tiny || EditMode.active || chrome.selected)
                            return
                        if (Math.abs(card.x - pressSpot.x) + Math.abs(card.y - pressSpot.y) > 3)
                            return
                        // A post is waiting for you to choose its items: the 2 x 2 shows them.
                        if (DownloaderService.pickJob)
                            DownloaderService.setSize("2x2")
                        else
                            DownloaderService.paste()
                    }

                    // The wheel on the 1 x 1 key: changes what it saves (video, audio, mute).
                    onWheel: wheel => {
                        if (!card.tiny || EditMode.active || chrome.selected) {
                            wheel.accepted = false
                            return
                        }
                        DownloaderService.cycleMode()
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
                    onToggled: DownloaderService.toggleSize()
                }

                // A link dragged onto the card (from the browser, a file manager's address bar ...).
                DropArea {
                    id: dropArea
                    z: 1
                    anchors.fill: parent
                    onDropped: drop => {
                        let t = ""
                        if (drop.hasText)
                            t = drop.text
                        else if (drop.hasUrls && drop.urls.length > 0)
                            t = String(drop.urls[0])
                        drop.accept()
                        DownloaderService.submit(t)
                    }
                }

                // While a link is held over the card: an outline around it, so it is clear it will take it.
                Rectangle {
                    z: 3
                    anchors.fill: parent
                    anchors.margins: card.tiny ? 0 : 2
                    anchors.bottomMargin: (card.tiny ? 0 : 2) + mt.shadowOffset
                    visible: dropArea.containsDrag
                    radius: card.tiny ? 30 : mt.radiusOuter
                    color: "transparent"
                    border.width: 4
                    border.color: mt.accentMint
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

                    // ===== 1 x 1: one key =====
                    Component {
                        id: tinyFace

                        DownloaderTile {
                            width: card.contentW
                            height: card.contentH
                            running: DownloaderService.runningId !== 0
                            pct: DownloaderService.livePct
                            waiting: DownloaderService.counts.queued
                            modeLabel: DM.modeText(DownloaderService.mode)
                            modeIcon: DM.modeIcon(DownloaderService.mode)
                            speed: DownloaderService.liveSpeed
                            choosing: DownloaderService.pickJob !== null
                            hover: dragArea.containsMouse
                            pressed: dragArea.pressed
                        }
                    }

                    // ===== 2 x 2: the wide paste key, the options, the list =====
                    Component {
                        id: fullFace

                        Item {
                            id: face
                            width: card.contentW
                            height: card.contentH

                            // ----- what it says for a moment after something happened -----
                            // "" | "saved" | "failed" | "note"
                            property string flash: ""
                            property string noteText: ""

                            function pop() {
                                squish.restart()
                                puff.fire()
                            }

                            function cheer() {
                                face.flash = "saved"
                                flashTimer.restart()
                                squish.restart()
                                cheerBurst.fire()
                            }

                            function failed() {
                                face.flash = "failed"
                                flashTimer.restart()
                                squish.restart()
                            }

                            function note(text) {
                                face.noteText = text
                                face.flash = "note"
                                flashTimer.restart()
                            }

                            Timer {
                                id: flashTimer
                                interval: 2400
                                onTriggered: face.flash = ""
                            }

                            readonly property bool isSaved: face.flash === "saved"
                            readonly property bool isFailed: face.flash === "failed"
                            readonly property bool isNote: face.flash === "note"
                            readonly property bool isOdd: face.isFailed || face.isNote

                            // ----- the fill: it rises as the file comes in -----
                            readonly property bool running: DownloaderService.runningId !== 0
                            readonly property real pct: DownloaderService.livePct
                            property real breath: 0

                            SequentialAnimation on breath {
                                running: face.running && face.pct < 0 && win.live
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.1; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
                            }

                            readonly property real level: face.isSaved ? 1
                                : (face.running ? (face.pct >= 0 ? face.pct / 100 : 0.18 + face.breath) : 0)

                            property real shownLevel: face.level

                            Behavior on shownLevel {
                                NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                            }

                            readonly property string bigText: face.isSaved ? "SAVED"
                                : (face.isFailed ? "OOPS"
                                : (face.running ? (face.pct >= 0 ? Math.round(face.pct) + "%" : "\u00b7\u00b7\u00b7") : "GET"))
                            readonly property int bigSize: face.isSaved ? 28 : (face.isFailed ? 32 : (face.running ? 36 : 42))

                            readonly property string topText: face.isNote ? face.noteText
                                : (face.isFailed ? "FAILED"
                                : (face.isSaved ? "DONE"
                                : (face.running ? (DownloaderService.counts.queued > 0 ? "+" + DownloaderService.counts.queued + " WAITING" : "LOADING")
                                : (DownloaderService.pickJob ? "PICK ITEMS"
                                : (DownloaderService.problem !== "" ? "SET UP" : "READY")))))

                            readonly property string bottomText: face.running
                                ? (DownloaderService.liveSpeed !== "" ? DownloaderService.liveSpeed + (DownloaderService.liveEta !== "" ? " \u00b7 " + DownloaderService.liveEta : "") : (DownloaderService.liveEngine !== "" ? DM.engineText(DownloaderService.liveEngine) : "WORKING"))
                                : "PASTE LINK"

                            // ===== the title row: the tab on the left, what it is doing on the right =====
                            Slant {
                                id: titleTab
                                x: 2
                                y: 0
                                width: 118
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
                                    name: "download"
                                    fill: 0
                                    size: 15
                                    weight: 700
                                    color: mt.dark ? mt.accentMint : mt.colBorder
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "DOWNLOAD"
                                    color: mt.chipInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    font.letterSpacing: 1.6
                                }
                            }

                            // What it is doing, on the right of the title row (READY, LOADING, +2 WAITING, DONE...).
                            Pill {
                                id: statusChip
                                width: Math.min(face.width - titleTab.width - 16, topLabel.implicitWidth + 26)
                                height: 29
                                x: face.width - width - 2
                                y: 0
                                shadowDy: 3
                                cornerRadius: 12
                                ringWidth: mt.borderWidth + mt.whiteLine
                                fillColor: face.isSaved ? mt.accentMint : (face.isOdd ? mt.warnFill : mt.chipFill)

                                Text {
                                    id: topLabel
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -1
                                    width: parent.width - 14
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: face.topText
                                    color: (face.isSaved || face.isOdd) ? mt.colBorder : mt.chipInk
                                    font.family: mt.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    font.letterSpacing: 1.2
                                }
                            }

                            // ===== the paste key: one wide key. The round arrow on the left is the same button the 1 x 1 is,
                            // the big word is what it is doing, and the colour comes up behind all of it as the file comes in. =====
                            Pill {
                                id: tray
                                x: 0
                                y: 32
                                width: face.width
                                height: 100
                                cornerRadius: 30
                                ringWidth: mt.borderWidth + mt.whiteLine
                                fillColor: mt.pSurface
                                pressed: trayArea.pressed

                                property real sx: 1
                                property real sy: 1

                                transform: Scale {
                                    origin.x: tray.width / 2
                                    origin.y: tray.height / 2
                                    xScale: tray.sx
                                    yScale: tray.sy
                                }

                                DownloadFill {
                                    anchors.fill: parent
                                    radius: tray.cornerRadius - tray.ringWidth
                                    level: face.shownLevel
                                }

                                // The round arrow (a check when it is saved, a mark when it went wrong).
                                Pill {
                                    id: disc
                                    width: 64
                                    height: 64 + 3
                                    x: 10
                                    y: (parent.height - 64) / 2 - 1
                                    shadowDy: 3
                                    cornerRadius: 32
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: face.isSaved ? mt.accentMint : (face.isOdd ? mt.warnFill : mt.chipFill)

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: (trayArea.containsMouse && !face.running ? 3 : 0) - 1
                                        name: face.isSaved ? "check" : (face.isOdd ? "error" : (face.running ? "downloading" : "download"))
                                        size: 34
                                        color: (face.isSaved || face.isOdd) ? mt.colBorder : (mt.dark ? mt.accentMint : mt.colBorder)

                                        Behavior on anchors.verticalCenterOffset {
                                            NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                        }
                                    }
                                }

                                // The big word: GET, the percent, SAVED.
                                StickerText {
                                    id: bigWord
                                    x: 90
                                    y: 27 - height / 2
                                    text: face.bigText
                                    pixelSize: face.bigSize
                                    fillColor: Qt.darker(mt.colBorder, 1.8)
                                    ringColor: "#ffffff"
                                }

                                // What pressing does, or how fast it is going.
                                Pill {
                                    x: 90
                                    y: parent.height - 24 - 8
                                    width: Math.min(parent.width - 90 - 12, bottomLabel.implicitWidth + 26)
                                    height: 24 + 3
                                    shadowDy: 3
                                    cornerRadius: 11
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.chipFill

                                    Text {
                                        id: bottomLabel
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        width: parent.width - 12
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: face.bottomText
                                        color: mt.chipInk
                                        font.family: mt.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                        font.letterSpacing: 1.0
                                    }
                                }

                                MouseArea {
                                    id: trayArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: DownloaderService.paste()
                                }
                            }

                            SequentialAnimation {
                                id: squish
                                ParallelAnimation {
                                    NumberAnimation { target: tray; property: "sx"; to: 1.03; duration: 80; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: tray; property: "sy"; to: 0.95; duration: 80; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: tray; property: "sx"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                    NumberAnimation { target: tray; property: "sy"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                }
                            }

                            Burst {
                                id: puff
                                x: tray.x + 10 + 32
                                y: tray.y + tray.height / 2
                                radius: 70
                                count: 8
                            }

                            Burst {
                                id: cheerBurst
                                x: tray.x + tray.width / 2
                                y: tray.y + tray.height / 2
                                radius: 110
                                count: 14
                                size: 11
                            }

                            // ===== the rest: the options, the list, the folder =====
                            Item {
                                id: side
                                x: 0
                                y: 0
                                width: face.width
                                height: face.height

                                // ===== what to save: video / audio / mute, and how good =====
                                Pill {
                                    id: modeKey
                                    x: 0
                                    y: 138
                                    width: 118
                                    height: 40
                                    shadowDy: 4
                                    cornerRadius: 15
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.accentMint
                                    pressed: modeArea.pressed

                                    Row {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        spacing: 6

                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: DM.modeIcon(DownloaderService.mode)
                                            size: 19
                                            color: mt.colBorder
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: DM.modeText(DownloaderService.mode)
                                            color: mt.colBorder
                                            font.family: mt.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.ExtraBold
                                            font.styleName: mt.fontStyleBold
                                            font.letterSpacing: 1.0
                                        }
                                    }

                                    MouseArea {
                                        id: modeArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DownloaderService.cycleMode()
                                    }
                                }

                                Pill {
                                    id: qualityKey
                                    x: 126
                                    y: 138
                                    width: 74
                                    height: 40
                                    shadowDy: 4
                                    cornerRadius: 15
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.chipFill
                                    pressed: qualityArea.pressed

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        text: DownloaderService.mode === "audio" ? DownloaderService.audioFormat.toUpperCase() : DM.qualityText(DownloaderService.quality)
                                        color: mt.chipInk
                                        font.family: mt.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                        font.letterSpacing: 1.0
                                    }

                                    MouseArea {
                                        id: qualityArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DownloaderService.mode === "audio" ? DownloaderService.cycleAudio() : DownloaderService.cycleQuality()
                                    }
                                }

                                // ===== the keys on the right of that row: the folder, and clearing the list =====
                                Pill {
                                    id: folderKey
                                    x: side.width - 36 - 8 - 36
                                    y: 138
                                    width: 36
                                    height: 40
                                    shadowDy: 4
                                    cornerRadius: 14
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.chipFill
                                    pressed: folderArea.pressed

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        name: "folder_open"
                                        size: 19
                                        color: mt.chipInk
                                    }

                                    MouseArea {
                                        id: folderArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DownloaderService.openFolder()
                                    }
                                }

                                Pill {
                                    id: clearKey
                                    x: side.width - 36
                                    y: 138
                                    width: 36
                                    height: 40
                                    shadowDy: 4
                                    cornerRadius: 14
                                    ringWidth: mt.borderWidth + mt.whiteLine
                                    fillColor: mt.chipFill
                                    pressed: clearArea.pressed
                                    opacity: DownloaderService.counts.done + DownloaderService.counts.failed > 0 ? 1 : 0.45

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        name: "delete"
                                        size: 19
                                        color: mt.chipInk
                                    }

                                    MouseArea {
                                        id: clearArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DownloaderService.clearFinished()
                                    }
                                }

                                // ===== the last downloads, newest on top =====
                                // Nothing yet: how to start, or what is missing.
                                Text {
                                    visible: DownloaderService.recent.length === 0
                                    x: 2
                                    y: 190
                                    width: side.width - 4
                                    wrapMode: Text.WordWrap
                                    text: DownloaderService.problem !== "" ? DownloaderService.problem : "Copy a link, then press GET. Or drop a link on this card."
                                    color: mt.pInk
                                    opacity: DownloaderService.problem !== "" ? 1 : 0.8
                                    font.family: mt.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.ExtraBold
                                    font.styleName: mt.fontStyleBold
                                    lineHeight: 1.1
                                }

                                Column {
                                    id: list
                                    x: 0
                                    y: 187
                                    width: side.width
                                    spacing: 3

                                    Repeater {
                                        model: DownloaderService.recent.slice(0, 2)

                                        delegate: Rectangle {
                                            id: row
                                            required property var modelData

                                            readonly property string st: row.modelData.status
                                            readonly property bool isRunning: row.st === "running"
                                            readonly property bool live: row.st === "running" || row.st === "queued"

                                            width: list.width
                                            height: 25
                                            radius: 9
                                            color: Qt.rgba(mt.pInk.r, mt.pInk.g, mt.pInk.b, rowArea.containsMouse ? 0.16 : 0.09)
                                            border.width: 2
                                            border.color: row.st === "failed" ? mt.warnFill : (row.isRunning ? mt.accentMint : mt.pLine)
                                            antialiasing: true

                                            // How far the running one is (a short bar that slides when that is not known yet).
                                            Item {
                                                visible: row.isRunning
                                                x: 5
                                                y: parent.height - 7
                                                width: parent.width - 10
                                                height: 3
                                                clip: true

                                                Rectangle {
                                                    id: rowBar
                                                    height: parent.height
                                                    radius: 1.5
                                                    color: mt.accentMint
                                                    width: DownloaderService.livePct >= 0 ? parent.width * DownloaderService.livePct / 100 : parent.width * 0.3
                                                    x: 0

                                                    SequentialAnimation on x {
                                                        running: row.isRunning && DownloaderService.livePct < 0 && win.live
                                                        loops: Animation.Infinite
                                                        NumberAnimation { from: 0; to: rowBar.parent.width * 0.7; duration: 800; easing.type: Easing.InOutSine }
                                                        NumberAnimation { to: 0; duration: 800; easing.type: Easing.InOutSine }
                                                    }
                                                }
                                            }

                                            // A click on the row: open a finished file, try a failed one again.
                                            MouseArea {
                                                id: rowArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: (row.st === "done" || row.st === "failed" || row.st === "cancelled") ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (row.st === "done")
                                                        DownloaderService.openFile(row.modelData.id)
                                                    else if (row.st === "failed" || row.st === "cancelled")
                                                        DownloaderService.retry(row.modelData.id)
                                                }
                                            }

                                            MaterialIcon {
                                                id: rowIcon
                                                x: 7
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.verticalCenterOffset: row.isRunning ? -2 : 0
                                                name: row.st === "done" ? "check_circle"
                                                    : (row.st === "failed" ? "error"
                                                    : (row.st === "running" ? "downloading"
                                                    : (row.st === "cancelled" ? "refresh" : "history")))
                                                size: 17
                                                color: row.st === "failed" ? mt.pInk : (row.st === "done" && !mt.dark ? mt.colBorder : mt.pInk)
                                                opacity: row.st === "queued" ? 0.55 : 1
                                            }

                                            Text {
                                                x: 30
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.verticalCenterOffset: row.isRunning ? -2 : 0
                                                width: row.width - 30 - 30
                                                elide: Text.ElideRight
                                                text: row.st === "failed" ? row.modelData.error
                                                    : (row.modelData.title !== "" ? row.modelData.title
                                                    : (row.modelData.host !== "" ? row.modelData.host : row.modelData.url))
                                                color: mt.pInk
                                                opacity: row.st === "queued" ? 0.6 : 1
                                                font.family: mt.fontFamily
                                                font.pixelSize: 12
                                                font.weight: row.st === "failed" ? Font.DemiBold : Font.ExtraBold
                                                font.styleName: mt.fontStyleBold
                                            }

                                            // The cross: stop a running or waiting one, take a finished one off the list.
                                            Item {
                                                id: crossBox
                                                anchors.right: parent.right
                                                anchors.rightMargin: 3
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 24
                                                height: 24

                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    name: "close"
                                                    size: 15
                                                    color: mt.pInk
                                                    opacity: crossArea.containsMouse ? 1 : 0.6
                                                }

                                                MouseArea {
                                                    id: crossArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.LeftButton
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (row.live)
                                                            DownloaderService.cancel(row.modelData.id)
                                                        else
                                                            DownloaderService.remove(row.modelData.id)
                                                    }
                                                }
                                            }
                                        
                                        }
                                    }
                                }

                                // ===== choosing items of a post (covers everything under the title row while it waits) =====
                                Rectangle {
                                    id: picker
                                    visible: DownloaderService.pickJob !== null
                                    x: 0
                                    y: 32
                                    width: side.width
                                    height: side.height - 32
                                    radius: 22
                                    color: mt.pSurface
                                    border.width: 3
                                    border.color: mt.pLine
                                    antialiasing: true

                                    readonly property var job: DownloaderService.pickJob
                                    readonly property int on: DM.countOn(DownloaderService.pickMask)
                                    readonly property int total: job ? job.items.length : 0

                                    // Clicks on the panel do not reach what is under it.
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.AllButtons
                                    }

                                    Text {
                                        x: 10
                                        y: 6
                                        text: "PICK WHAT TO SAVE"
                                        color: mt.pInkSub
                                        font.family: mt.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                        font.letterSpacing: 1.2
                                    }

                                    GridView {
                                        id: grid
                                        x: 6
                                        y: 24
                                        width: picker.width - 12
                                        height: picker.height - 24 - 44
                                        clip: true
                                        cellWidth: 36
                                        cellHeight: 36
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: picker.job ? picker.job.items : []

                                        delegate: Item {
                                            id: cell
                                            required property int index
                                            required property var modelData
                                            readonly property bool sel: DownloaderService.pickMask[cell.index] === true

                                            width: grid.cellWidth
                                            height: grid.cellHeight

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                radius: 8
                                                color: mt.chipFill
                                                border.width: cell.sel ? 3 : 2
                                                border.color: cell.sel ? mt.accentMint : mt.pLine
                                                antialiasing: true
                                                clip: true

                                                // The picture when there is one (it may not load: then the icon shows).
                                                Image {
                                                    id: thumb
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    source: cell.modelData.thumb
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    sourceSize.width: 64
                                                    sourceSize.height: 64
                                                    opacity: cell.sel ? 1 : 0.35
                                                }

                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    visible: thumb.status !== Image.Ready
                                                    name: DM.typeIcon(cell.modelData.type)
                                                    size: 16
                                                    color: mt.chipInk
                                                    opacity: cell.sel ? 1 : 0.45
                                                }

                                                // A video: a small play mark over its picture.
                                                MaterialIcon {
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 1
                                                    visible: cell.modelData.type !== "photo" && thumb.status === Image.Ready
                                                    name: "play_arrow"
                                                    size: 13
                                                    color: "#ffffff"
                                                }

                                                // The tick.
                                                Rectangle {
                                                    visible: cell.sel
                                                    anchors.top: parent.top
                                                    anchors.right: parent.right
                                                    anchors.margins: 1
                                                    width: 13
                                                    height: 13
                                                    radius: 6.5
                                                    color: mt.accentMint

                                                    MaterialIcon {
                                                        anchors.centerIn: parent
                                                        name: "check_circle"
                                                        size: 11
                                                        color: mt.colBorder
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: DownloaderService.togglePick(picker.job.id, cell.index)
                                            }
                                        }
                                    }

                                    // SAVE n | all / none | cancel
                                    Pill {
                                        id: saveKey
                                        x: 6
                                        y: picker.height - height - 6
                                        width: 70
                                        height: 36
                                        shadowDy: 3
                                        cornerRadius: 13
                                        ringWidth: mt.borderWidth + mt.whiteLine
                                        fillColor: mt.accentMint
                                        opacity: picker.on > 0 ? 1 : 0.5
                                        pressed: saveArea.pressed

                                        Text {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: -1
                                            text: "SAVE " + picker.on
                                            color: mt.colBorder
                                            font.family: mt.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.ExtraBold
                                            font.styleName: mt.fontStyleBold
                                            font.letterSpacing: 0.8
                                        }

                                        MouseArea {
                                            id: saveArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: DownloaderService.confirmPick(picker.job.id)
                                        }
                                    }

                                    Pill {
                                        id: allKey
                                        x: 82
                                        y: picker.height - height - 6
                                        width: 34
                                        height: 36
                                        shadowDy: 3
                                        cornerRadius: 13
                                        ringWidth: mt.borderWidth + mt.whiteLine
                                        fillColor: mt.chipFill
                                        pressed: allArea.pressed

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: -1
                                            name: picker.on < picker.total ? "check_circle" : "close"
                                            size: 18
                                            color: mt.chipInk
                                        }

                                        MouseArea {
                                            id: allArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: DownloaderService.pickAll(picker.job.id, picker.on < picker.total)
                                        }
                                    }

                                    Pill {
                                        id: dropKey
                                        x: 122
                                        y: picker.height - height - 6
                                        width: 28
                                        height: 36
                                        shadowDy: 3
                                        cornerRadius: 13
                                        ringWidth: mt.borderWidth + mt.whiteLine
                                        fillColor: mt.chipFill
                                        pressed: dropArea2.pressed

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: -1
                                            name: "close"
                                            size: 16
                                            color: mt.chipInk
                                        }

                                        MouseArea {
                                            id: dropArea2
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: DownloaderService.cancel(picker.job.id)
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
