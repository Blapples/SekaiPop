import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode

// The desktop user card: a small player card that sits on the desktop, under
// your windows, over the wallpaper, with the same drag and lock as the clock.
// It is exactly the clock's KEYS card in size (320 x 276), so the two sit side
// by side. One design for now.
//
//   Moving it: in Edit Desktop (right-click the desktop) it is always
//   draggable, by the shield in EditChrome.qml; a click on it there selects it
//   for editing (the avatar pops), a right-click removes it. On the normal
//   desktop it can be dragged only while "Lock all" (a tile on the Edit
//   Desktop shelf, locked by default) is off. There is no per-card lock.
//
//   click the avatar   it squashes and throws a burst of diamonds
//   hover the avatar   it tips the other way
//
// What is on it (all of it real, nothing made up):
//
//   the banner   the Quick Panel's banner picture, or the mint-to-cyan
//                gradient with a few diamonds that pop once a minute. A navy
//                chip on it greets you by the time of day.
//   the avatar   the Quick Panel's avatar picture on a tilted sticker, or your
//                initial on a navy chip until one is picked. (Pick pictures
//                on the Quick Panel: they are the same two pictures.)
//   the name     your user name, and @ the host name.
//   three keys   how long the machine has been up, your shell, your desktop,
//                in a shallow V like the clock's keycaps. Each presses in
//                when its value changes.
//   the lane     how much of today is gone: a playhead hops along a lane with
//                gates at 6 / 12 / 18h, and a chip shows the percentage.
//
// Nothing animates endlessly: the card is idle between minute ticks and clicks.
// The two knobs for the attitude are `tilt` and `stagger` on the card below;
// set both to 0 for a perfectly level row of keys.
//
// State (position, shown) lives in services/UserCardService.qml and is
// remembered across restarts.
//
// How the moving works: exactly like ClockWidget.qml. ONE full-screen,
// transparent window on WlrLayer.Bottom, with the card as an Item inside it.
// Dragging just moves that Item, so it stays smooth, and the window's input
// `mask` is only the card, so every click anywhere else passes straight through
// to whatever is underneath. The card never takes keyboard focus.
//
// Bind a key / call it from a script:
//   qs -c sekaipop ipc call usercard toggle         (show / hide)
//   qs -c sekaipop ipc call usercard resetPosition  (if it ever ends up off-screen)

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
    // UserCardService), or the first screen if it has never been moved.
    property string monitor: ""

    // A copy on another monitor (WidgetClones.qml): the same widget, with a spot of its own. The main
    // copy keeps its spot in the service as before.
    property bool clone: false

    readonly property var cloneSpot: win.clone ? WidgetClones.spot("usercard", win.wantedScreen) : null
    readonly property bool spotReady: win.clone ? (WidgetClones.loaded && win.cloneSpot !== null) : UserCardService.loaded
    readonly property real spotX: win.clone ? (win.cloneSpot ? win.cloneSpot.x : -1) : UserCardService.posX
    readonly property real spotY: win.clone ? (win.cloneSpot ? win.cloneSpot.y : -1) : UserCardService.posY
    readonly property real spotScale: win.clone ? (win.cloneSpot ? win.cloneSpot.scale : 0) : UserCardService.posScale

    function saveSpot(x, y): void {
        if (win.clone)
            WidgetClones.setSpot("usercard", win.wantedScreen, x, y, win.uiScale)
        else
            UserCardService.setPosition(x, y, win.screen ? win.screen.name : "", win.uiScale)
    }

    function clearSpot(): void {
        if (win.clone) {
            WidgetClones.clearSpot("usercard", win.wantedScreen)
        } else {
            UserCardService.posX = -1
            UserCardService.posY = -1
        }
    }

    function fixSpotScale(): void {
        if (win.clone) {
            WidgetClones.setSpot("usercard", win.wantedScreen, win.spotX, win.spotY, win.uiScale)
        } else {
            UserCardService.posScale = win.uiScale
            UserCardService.persist()
        }
    }

    readonly property string wantedScreen: win.monitor !== "" ? win.monitor : UserCardService.screenName
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
        widgetId: "usercard"
        screenName: win.screen ? win.screen.name : ""
    }

    readonly property bool switchedOn: UserCardService.shown && UserCardService.loaded
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
        running: UserCardService.loaded
        onTriggered: win.armed = true
    }

    // `live`: the card is on, or still being swallowed.
    readonly property bool live: win.want || win.reveal > 0.001

    // On screen, or switched on and not suspended by Focus Mode (see ClockWidget.qml).
    readonly property bool working: win.live || (win.switchedOn && !gate.suspended)

    // Not mapped while the widget is off: a full-screen transparent layer that is only
    // sitting there still costs the compositor a blend on every frame.
    visible: UserCardService.loaded && (win.live || EditMode.active)

    // Always BELOW the dock: the widgets rest on Background (mapped after the wallpaper,
    // so over it) and the dock is on Bottom or Top, so the dock is never behind a widget.
    // Up a layer while this widget is edited or moved (EditChrome.raised), so the one
    // edited last is in front of the other widgets (see EditChrome.qml); Bottom is as far
    // up as it goes, because the dock is on Top while editing (see Dock.qml).
    WlrLayershell.layer: (chrome.raised || WallpaperService.restacking) ? WlrLayer.Bottom : WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-usercard"
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

    // ===== who you are =====
    readonly property string userName: Quickshell.env("USER") || "user"
    property string hostName: ""

    readonly property string shellName: {
        const n = (Quickshell.env("SHELL") || "").split("/").pop()
        return n !== "" ? n : "sh"
    }

    readonly property string deskName: Quickshell.env("XDG_CURRENT_DESKTOP") || "Wayland"

    Process {
        running: true
        command: ["uname", "-n"]   // `hostname` is not installed by default on Arch (inetutils)
        stdout: StdioCollector {
            onStreamFinished: win.hostName = text.trim()
        }
    }

    // Seconds the machine has been up. Read at start, again whenever the card
    // comes back, and every 30 s while it is showing.
    property real uptimeSecs: -1

    Process {
        id: uptimeProc
        running: true
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = parseFloat(text.split(" ")[0])
                if (isFinite(s))
                    win.uptimeSecs = s
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: win.working
        onTriggered: {
            if (!uptimeProc.running)
                uptimeProc.running = true
        }
    }

    // Coming back (or Focus Mode letting it work again): the uptime is stale, read it once.
    onWorkingChanged: {
        if (win.working && !uptimeProc.running)
            uptimeProc.running = true
    }

    readonly property string uptimeText: {
        if (win.uptimeSecs < 0)
            return "--"
        const m = Math.floor(win.uptimeSecs / 60)
        const h = Math.floor(m / 60)
        const d = Math.floor(h / 24)
        if (d > 0)
            return d + "d " + (h % 24) + "h"
        if (h > 0)
            return h + "h " + (m % 60) + "m"
        return m + "m"
    }

    // Only ticks while the widget is on screen (or Edit Desktop is on, so the
    // shelf's picture of a card that is switched off is current), once a minute.
    SystemClock {
        id: clock
        enabled: win.working || EditMode.active
        precision: SystemClock.Minutes
    }

    readonly property date now: clock.date
    readonly property int hours24: win.now.getHours()
    readonly property int mins: win.now.getMinutes()
    readonly property real dayFrac: (win.hours24 * 60 + win.mins) / 1440

    readonly property string greeting: win.hours24 >= 5 && win.hours24 < 12 ? "GOOD MORNING"
        : win.hours24 >= 12 && win.hours24 < 17 ? "GOOD AFTERNOON"
        : win.hours24 >= 17 && win.hours24 < 21 ? "GOOD EVENING"
        : "NIGHT OWL"

    // ===== placement =====
    function place(force) {
        if (win.roomW <= 0 || win.roomH <= 0)
            return
        // Not before the saved spot has been read, and not while the window is
        // still smaller than the card (the clamp below would put it at 0, 0).
        if (!force && (!UserCardService.loaded || win.roomW < card.width || win.roomH < card.height))
            return
        let x = win.spotX
        let y = win.spotY
        if (x < 0 || y < 0) {
            x = 384
            y = 96
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
                win.place(!win.placed && UserCardService.loaded)
        }
    }

    onWidthChanged: { win.place(); settle.restart() }
    onHeightChanged: { win.place(); settle.restart() }
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
        target: UserCardService
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
        function onUsercardOutChanged() {
            if (PresetMotion.usercardOut) {
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
        }
    }

    // Edit Desktop's shelf shows the card as it really looks: a picture of it,
    // taken every second while the mode is on (EditPreview.qml).
    EditPreview {
        widgetId: win.clone ? "" : "usercard"
        target: card
        pixelRatio: win.uiScale
    }


    // ===== parts =====

    component MaskedPhoto: Item {
        id: mp

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property url source: ""
        // Which part of it shows (PanelImages.framingFor: the same framing as the Quick
        // Panel's, drawn into this slot's own shape); null = centred.
        property var framing: null
        property real radius: 10                       // radius of this item's own edge (the outline's inner edge)
        property real bleed: 2                         // how far the picture runs under the outline
        property real frameWidth: mt.borderWidth    // the Pill's outline width
        property real frameRadius: mp.radius + mp.frameWidth
        property color frameColor: mt.pLine

        readonly property bool ready: img.status === Image.Ready
        readonly property real texel: win.uiScale * (win.screen ? win.screen.devicePixelRatio : 1)
        readonly property real oversample: 2

        Item {
            id: photoLayer
            x: -mp.bleed
            y: -mp.bleed
            width: mp.width + mp.bleed * 2
            height: mp.height + mp.bleed * 2
            visible: mp.ready

            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.max(1, Math.ceil(width * mp.texel * mp.oversample)),
                                       Math.max(1, Math.ceil(height * mp.texel * mp.oversample)))
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: photoMask
            }

            FramedImage {
                id: img
                anchors.fill: parent
                source: mp.source
                framing: mp.framing
                clipped: false
                // One pixel of picture per texture pixel, as the layer is drawn.
                decodeScale: mp.texel * mp.oversample
            }
        }

        // The rounded mask, at the same texture density as the picture so its
        // edge is as sharp as the picture.
        Item {
            id: photoMask
            x: photoLayer.x
            y: photoLayer.y
            width: photoLayer.width
            height: photoLayer.height
            visible: false

            layer.enabled: true
            layer.smooth: true
            layer.textureSize: photoLayer.layer.textureSize

            Rectangle {
                anchors.fill: parent
                radius: mp.radius + mp.bleed
                color: "black"
                antialiasing: true
            }
        }

        // The Pill's navy outline again, on top of the picture.
        Rectangle {
            visible: mp.ready
            z: 2
            x: -mp.frameWidth
            y: -mp.frameWidth
            width: mp.width + mp.frameWidth * 2
            height: mp.height + mp.frameWidth * 2
            radius: mp.frameRadius
            color: "transparent"
            border.width: mp.frameWidth
            border.color: mp.frameColor
            antialiasing: true
        }
    }

    // One key: a Pill cap with a tiny label over a value. The navy chip, or the
    // mint-to-cyan gradient. It hard-shadows down-right and presses in
    // whenever its value changes (Pill's own press / spring), like the
    // clock's keycaps.
    component StatKey: Item {
        id: sk

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string label: ""
        property string value: ""
        property bool gradientFill: false
        property real tilt: 0

        width: 90                              // 87 cap + 3 shadow
        height: 58                             // 54 cap + 4 shadow
        rotation: sk.tilt
        transformOrigin: Item.Center

        onValueChanged: {
            keyPill.pressed = true
            keyRelease.restart()
        }

        Timer {
            id: keyRelease
            interval: 90
            onTriggered: keyPill.pressed = false
        }

        Gradient {
            id: keyFill
            GradientStop { position: 0.0; color: mt.accentMint }
            GradientStop { position: 1.0; color: mt.accentCyan }
        }

        Pill {
            id: keyPill
            anchors.fill: parent
            cornerRadius: 15
            ringWidth: mt.borderWidth + mt.whiteLine
            shadowDx: 3
            shadowDy: 4
            fillColor: mt.chipFill
            fillGradient: sk.gradientFill ? keyFill : null

            Column {
                anchors.centerIn: parent
                width: parent.width - 6
                spacing: 1

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: sk.label
                    color: sk.gradientFill ? mt.colBorder : mt.chipInk
                    opacity: 0.7
                    font.family: mt.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 1.5
                }

                // Long values (a desktop called "Hyprland", an uptime of
                // "12d 23h") shrink to fit instead of running off the key.
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: sk.value
                    color: sk.gradientFill ? mt.colBorder : mt.chipInk
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 10
                    font.family: mt.fontFamily
                    font.pixelSize: 19
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }
        }
    }

    // A diamond on the banner: it pops once a minute, each one a beat after
    // the one before (`order`), so the minute tick runs across the banner.
    component SparkDiamond: Rectangle {
        id: sp

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property int order: 0
        property real size: 12
        property bool solid: false
        property real pop: 1

        width: sp.size
        height: sp.size
        radius: sp.size / 4
        rotation: 45
        scale: sp.pop
        color: sp.solid ? mt.colBorder : "#ffffff"
        border.width: 2
        border.color: mt.colBorder
        antialiasing: true

        SequentialAnimation {
            id: sparkTick

            PauseAnimation { duration: sp.order * 50 }

            NumberAnimation {
                target: sp
                property: "pop"
                from: 1.7
                to: 1
                duration: 380
                easing.type: Easing.OutBack
                easing.overshoot: 2.2
            }
        }

        Connections {
            target: win
            function onMinsChanged() {
                sparkTick.restart()
            }
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

                // The same footprint as the clock's KEYS card: its content is
                // 286 x 238, and the housing adds the inset on every side plus
                // the hard shadow underneath.
                // The 1 x 1 size (UserCardService.size) is a quarter of it: 120 x 94 of content,
                // 154 x 132 with the housing.
                readonly property bool tiny: UserCardService.tiny
                readonly property int contentW: card.tiny ? 120 : 286
                readonly property int contentH: card.tiny ? 94 : 238
                readonly property int inset: mt.borderWidth + mt.outerRingWidth + 10

                width: card.contentW + card.inset * 2
                height: card.contentH + card.inset * 2 + mt.shadowOffset

                // How much attitude the keys have. 0 / 0 = a flat, level row.
                readonly property real tilt: 2.5       // degrees, outer keys
                readonly property int stagger: 6       // px the middle key sits lower (the V)

                // On the navy chip: bright accent in the dark modes, navy ink in
                // Light (where the chip is pale and mint would vanish).
                readonly property color glow: mt.dark ? mt.accentMint : mt.colBorder

                scale: Math.max(0, win.reveal) * (win.placed ? 1 : 0) * (0.7 + 0.3 * Math.max(0, win.swapK))
                opacity: Math.max(0, Math.min(1, win.swapK))
                transformOrigin: Item.Center

                // Is this point (in card pixels) on the avatar? Works through the
                // avatar's tilt and scale.
                function isOverAvatar(px, py) {
                    // The 1 x 1 face has its own avatar (null until it is built).
                    const slot = card.tiny ? (tinyLoader.item ? tinyLoader.item.avatar : null) : avatarSlot
                    if (!slot)
                        return false
                    const p = slot.mapFromItem(dragArea, px, py)
                    return p.x >= 0 && p.y >= 0 && p.x <= slot.width && p.y <= slot.height
                }

                readonly property bool avatarHover: dragArea.containsMouse && card.isOverAvatar(dragArea.mouseX, dragArea.mouseY)
                property bool avatarDown: false

                // The click: the avatar squashes and springs back, and eight
                // diamonds fly out of it.
                function popBurst() {
                    if (card.tiny) {
                        if (tinyLoader.item)
                            tinyLoader.item.pop()
                        return
                    }
                    hitAnim.restart()
                    burstAnim.restart()
                }

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
                    widgetId: "usercard"
                    target: card
                    roomW: win.roomW
                    roomH: win.roomH
                    screenName: win.screen ? win.screen.name : ""
                    onMoved: win.saveSpot(card.x, card.y)
                    onRemoveRequested: EditMode.removeFrom("usercard", win.screen ? win.screen.name : "")
                }

                // Left button: drag the card on the normal desktop, unless Lock all
                // is on (EditMode.desktopDragAllowed; while editing, the shield in
                // EditChrome.qml does the moving instead, until the card is
                // selected for editing: then this does). A click on the avatar
                // (one that did not turn into a drag) is the burst.
                MouseArea {
                    id: dragArea
                    z: 10
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    cursorShape: EditMode.desktopDragAllowed || chrome.selected
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                        : (card.avatarHover ? Qt.PointingHandCursor : Qt.ArrowCursor)

                    drag.target: EditMode.desktopDragAllowed || chrome.selected ? card : null
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: Math.max(0, win.roomW - card.width)
                    drag.minimumY: 0
                    drag.maximumY: Math.max(0, win.roomH - card.height)

                    onPressed: mouse => card.avatarDown = card.isOverAvatar(mouse.x, mouse.y)
                    onReleased: card.avatarDown = false
                    onCanceled: card.avatarDown = false

                    onClicked: mouse => {
                        if (card.isOverAvatar(mouse.x, mouse.y))
                            card.popBurst()
                    }

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
                    onToggled: UserCardService.toggleSize()
                }

                // ===== the 1 x 1 face =====
                // ONLY your avatar, as a button: no plate, no name, no backdrop. The picture
                // itself is the key (the same navy outline and hard shadow as every other
                // button in the shell): it sinks into its shadow while pressed, tips the other
                // way when pointed at, and a click squashes it and throws the burst. Built
                // only while the card is 1 x 1.
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

                    Item {
                        id: tface
                        width: card.contentW
                        height: card.contentH

                        // The avatar is the whole key: the card's hit test (isOverAvatar) and
                        // the click (the burst) use it.
                        readonly property Item avatar: tAvatar

                        function pop() {
                            tHit.restart()
                            tBurst.restart()
                        }

                        TinyFoot {
                            id: tFoot
                            anchors.fill: parent

                            // The key: as tall as the card's footprint allows, in its middle.
                            readonly property real keySize: tFoot.capH - 4

                            SequentialAnimation {
                                id: tHit
                                NumberAnimation { target: tAvatar; property: "hit"; to: 0.9; duration: 70; easing.type: Easing.OutQuad }
                                NumberAnimation { target: tAvatar; property: "hit"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 3.2 }
                            }

                            Item {
                                id: tAvatar
                                x: (tFoot.capW - tFoot.keySize) / 2
                                y: 2
                                width: tFoot.keySize + 3                  // + the shadow's 3
                                height: tFoot.keySize + 4                 // + the shadow's 4
                                transformOrigin: Item.Center
                                rotation: card.avatarHover ? 3 : -3

                                property real hit: 1
                                scale: tAvatar.hit

                                Behavior on rotation {
                                    NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                }

                                Pill {
                                    id: tPill
                                    anchors.fill: parent
                                    cornerRadius: 38
                                    ringWidth: mt.borderWidth   // no white ring: the picture meets the outline
                                    shadowDx: 3
                                    shadowDy: 4
                                    pressed: card.avatarDown
                                    fillColor: mt.chipFill

                                    // No picture picked yet: your initial.
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !tPhoto.ready
                                        text: win.userName.charAt(0).toUpperCase()
                                        color: card.glow
                                        font.family: mt.fontFamily
                                        font.pixelSize: 64
                                        font.weight: Font.ExtraBold
                                        font.styleName: mt.fontStyleBold
                                    }

                                    // The Quick Panel's avatar picture.
                                    MaskedPhoto {
                                        id: tPhoto
                                        anchors.fill: parent
                                        source: PanelImages.avatar
                                        framing: PanelImages.framingFor("avatar")
                                        radius: Math.max(0, tPill.cornerRadius - tPill.ringWidth)
                                        frameWidth: tPill.borderWidth
                                        frameRadius: tPill.cornerRadius
                                        frameColor: tPill.classicScope ? mt.pLine : mt.line
                                    }
                                }
                            }

                            // The burst: the same eight diamonds as the big card's, from the
                            // middle of the avatar, flying out past its edge. One number, `t`,
                            // 0 -> 1.
                            Item {
                                id: tBurst
                                z: 6
                                x: tFoot.capW / 2
                                y: tAvatar.y + tFoot.keySize / 2
                                visible: tBurst.t < 1

                                property real t: 1

                                function restart() {
                                    tBurstAnim.restart()
                                }

                                NumberAnimation {
                                    id: tBurstAnim
                                    target: tBurst
                                    property: "t"
                                    from: 0
                                    to: 1
                                    duration: 560
                                    easing.type: Easing.OutCubic
                                }

                                Repeater {
                                    model: 8

                                    Rectangle {
                                        required property int index

                                        readonly property real ang: (index * 45 + 22.5) * Math.PI / 180
                                        readonly property real dist: tFoot.keySize / 2 + 4 + tBurst.t * (index % 2 === 0 ? 16 : 11)

                                        width: index % 2 === 0 ? 10 : 8
                                        height: width
                                        radius: 3
                                        rotation: 45
                                        x: Math.cos(ang) * dist - width / 2
                                        y: Math.sin(ang) * dist - height / 2
                                        scale: 1.15 - tBurst.t * 0.85
                                        opacity: 1 - tBurst.t * tBurst.t
                                        color: index % 3 === 0 ? mt.accentMint : (index % 3 === 1 ? mt.accentCyan : "#ffffff")
                                        border.width: 2
                                        border.color: mt.colBorder
                                        antialiasing: true
                                    }
                                }
                            }
                        }
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

                    // ===== the banner =====
                    Pill {
                        id: banner
                        z: 1
                        width: card.contentW
                        height: 88                     // 84 cap + 4 shadow
                        cornerRadius: 16
                        ringWidth: mt.borderWidth   // no white ring: the picture meets the outline
                        fillGradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: mt.accentMint }
                            GradientStop { position: 1.0; color: mt.accentCyan }
                        }

                        // The Quick Panel's banner picture, when one is picked.
                        MaskedPhoto {
                            id: bannerPhoto
                            anchors.fill: parent
                            source: PanelImages.banner
                            framing: PanelImages.framingFor("banner")
                            radius: Math.max(0, banner.cornerRadius - banner.ringWidth)
                            frameWidth: banner.borderWidth
                            frameRadius: banner.cornerRadius
                            frameColor: banner.classicScope ? mt.pLine : mt.line
                        }

                        // Otherwise: diamonds, kept clear of the avatar (bottom
                        // left) and mostly of the greeting chip (top right).
                        Item {
                            anchors.fill: parent
                            visible: !bannerPhoto.ready

                            SparkDiamond { order: 0; size: 14; x: 118; y: 44 }
                            SparkDiamond { order: 1; size: 9;  x: 146; y: 56; solid: true }
                            SparkDiamond { order: 2; size: 12; x: 172; y: 44 }
                            SparkDiamond { order: 3; size: 8;  x: 198; y: 54; solid: true }
                            SparkDiamond { order: 4; size: 15; x: 226; y: 46 }
                            SparkDiamond { order: 5; size: 9;  x: 252; y: 54; solid: true }
                            SparkDiamond { order: 6; size: 10; x: 28;  y: 14 }
                            SparkDiamond { order: 7; size: 8;  x: 66;  y: 22; solid: true }
                            SparkDiamond { order: 8; size: 11; x: 100; y: 12 }
                        }
                    }

                    // The greeting: a tilted navy chip on the banner's top-right.
                    Pill {
                        id: greetChip
                        z: 3
                        width: greetText.implicitWidth + 26
                        height: 30
                        x: card.contentW - greetChip.width - 14
                        y: 10
                        cornerRadius: 10
                        ringWidth: mt.borderWidth + mt.whiteLine
                        fillColor: mt.chipFill
                        rotation: 3
                        transformOrigin: Item.Center

                        Text {
                            id: greetText
                            anchors.centerIn: parent
                            text: win.greeting
                            color: mt.chipInk
                            font.family: mt.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                            font.letterSpacing: 1.2
                        }
                    }

                    // ===== the avatar sticker =====
                    Item {
                        id: avatarSlot
                        z: 4
                        x: 10
                        y: 46
                        width: 87                      // 84 cap + 3 shadow
                        height: 88                     // 84 cap + 4 shadow
                        transformOrigin: Item.Center

                        // Tips the other way and swells a little on hover; the
                        // click squashes it (`hit`). Separate numbers so the
                        // hover spring and the click spring don't fight.
                        property real lift: card.avatarHover ? 1.05 : 1
                        property real hit: 1

                        rotation: card.avatarHover ? 3 : -4
                        scale: avatarSlot.lift * avatarSlot.hit

                        Behavior on rotation {
                            NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        }

                        Behavior on lift {
                            NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }

                        SequentialAnimation {
                            id: hitAnim
                            NumberAnimation { target: avatarSlot; property: "hit"; to: 0.88; duration: 70; easing.type: Easing.OutQuad }
                            NumberAnimation { target: avatarSlot; property: "hit"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 3.2 }
                        }

                        Pill {
                            id: avatarPill
                            anchors.fill: parent
                            cornerRadius: 26
                            ringWidth: mt.borderWidth   // no white ring: the picture meets the outline
                            shadowDx: 3
                            shadowDy: 4
                            fillColor: mt.chipFill
                            pressed: card.avatarDown

                            // No picture picked yet: your initial.
                            Text {
                                anchors.centerIn: parent
                                visible: !avatarPhoto.ready
                                text: win.userName.charAt(0).toUpperCase()
                                color: card.glow
                                font.family: mt.fontFamily
                                font.pixelSize: 46
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }

                            // The Quick Panel's avatar picture.
                            MaskedPhoto {
                                id: avatarPhoto
                                anchors.fill: parent
                                source: PanelImages.avatar
                            framing: PanelImages.framingFor("avatar")
                                radius: Math.max(0, avatarPill.cornerRadius - avatarPill.ringWidth)
                                frameWidth: avatarPill.borderWidth
                                frameRadius: avatarPill.cornerRadius
                                frameColor: avatarPill.classicScope ? mt.pLine : mt.line
                            }
                        }
                    }

                    // The burst: eight diamonds that fly out of the avatar and
                    // fade, on a click. One number, `t`, 0 -> 1; each diamond
                    // works out its own place from it.
                    Item {
                        id: burst
                        z: 6
                        x: 53
                        y: 90
                        visible: burst.t < 1

                        property real t: 1

                        NumberAnimation {
                            id: burstAnim
                            target: burst
                            property: "t"
                            from: 0
                            to: 1
                            duration: 560
                            easing.type: Easing.OutCubic
                        }

                        Repeater {
                            model: 8

                            Rectangle {
                                required property int index

                                readonly property real ang: (index * 45 + 22.5) * Math.PI / 180
                                readonly property real dist: 36 + burst.t * (index % 2 === 0 ? 62 : 44)

                                width: index % 2 === 0 ? 12 : 9
                                height: width
                                radius: 3
                                rotation: 45
                                x: Math.cos(ang) * dist - width / 2
                                y: Math.sin(ang) * dist - height / 2
                                scale: 1.15 - burst.t * 0.85
                                opacity: 1 - burst.t * burst.t
                                color: index % 3 === 0 ? mt.accentMint : (index % 3 === 1 ? mt.accentCyan : "#ffffff")
                                border.width: 2
                                border.color: mt.colBorder
                                antialiasing: true
                            }
                        }
                    }

                    // ===== the name =====
                    Text {
                        x: 112
                        y: 91
                        z: 2
                        width: card.contentW - 112
                        elide: Text.ElideRight
                        text: win.userName
                        color: mt.pInk
                        font.family: mt.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }

                    Text {
                        x: 112
                        y: 119
                        z: 2
                        width: card.contentW - 112
                        elide: Text.ElideRight
                        text: win.hostName !== "" ? "@" + win.hostName : ""
                        color: mt.pInkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    // ===== three keys in a shallow V =====
                    Item {
                        id: keyRow
                        y: 140
                        width: card.contentW
                        height: 64

                        StatKey {
                            x: 0
                            y: 0
                            label: "UPTIME"
                            value: win.uptimeText
                            tilt: -card.tilt
                        }

                        StatKey {
                            x: 98
                            y: card.stagger
                            gradientFill: true
                            label: "SHELL"
                            value: win.shellName
                        }

                        StatKey {
                            x: 196
                            y: 0
                            label: "DESKTOP"
                            value: win.deskName
                            tilt: card.tilt
                        }
                    }

                    // ===== the lane =====
                    Item {
                        id: lane
                        y: 208
                        width: card.contentW
                        height: 30

                        Pill {
                            id: pct
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            height: 30
                            cornerRadius: 10
                            ringWidth: 3
                            fillColor: mt.chipFill
                            rotation: 3
                            transformOrigin: Item.Center

                            Text {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Math.round(win.dayFrac * 100) + "%"
                                color: card.glow
                                font.family: mt.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.ExtraBold
                                font.styleName: mt.fontStyleBold
                            }
                        }

                        Text {
                            id: laneCap
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -2
                            text: "TODAY"
                            color: mt.pInkSub
                            font.family: mt.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                            font.letterSpacing: 1.5
                        }

                        Item {
                            id: track
                            anchors.left: laneCap.right
                            anchors.leftMargin: 10
                            anchors.right: pct.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -2
                            height: 20

                            readonly property real headSize: 12
                            readonly property real pos: track.width * win.dayFrac
                            readonly property real headX: Math.min(track.width - track.headSize, Math.max(0, track.pos - track.headSize / 2))

                            // At midnight the lane just resets instead of sweeping backwards.
                            readonly property bool sweeps: win.hours24 !== 0 || win.mins !== 0

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 12
                                radius: 6
                                color: mt.pSurfaceDivider
                                border.width: 2
                                border.color: mt.pLine
                            }

                            // What is gone of today.
                            Rectangle {
                                x: 2
                                anchors.verticalCenter: parent.verticalCenter
                                height: 8
                                radius: 4
                                width: Math.max(0, track.headX + track.headSize / 2 - 2)

                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: mt.accentMint }
                                    GradientStop { position: 1.0; color: mt.accentCyan }
                                }

                                Behavior on width {
                                    enabled: track.sweeps
                                    NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                }
                            }

                            // Gates at 6 / 12 / 18 h.
                            Repeater {
                                model: 3

                                Rectangle {
                                    required property int index
                                    x: track.width * (index + 1) / 4 - 1.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 12
                                    radius: 1.5
                                    color: mt.pLine
                                    opacity: 0.45
                                }
                            }

                            // The playhead: a diamond note.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: track.headSize
                                height: track.headSize
                                radius: 3
                                rotation: 45
                                color: mt.accentMint
                                border.width: 2
                                border.color: mt.pLine
                                x: track.headX

                                Behavior on x {
                                    enabled: track.sweeps
                                    NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
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
