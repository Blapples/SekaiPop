import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.editMode
import qs.modules.sekai.equalizer
import qs.modules.sekai.mediaControls

// One of the files that talk to the system (the others: MediaSource.qml
// for MPRIS, TraySource.qml + TrayPopups.qml for the tray,
// NotificationSource.qml for notifications).
// Status_Bar.qml stays pure UI: this feeds it Hyprland + clock + media
// + tray data and turns its signals into actions.
PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    // One entry of shell.qml's bar model: { screen, position }. The edge is
    // part of the entry on purpose — this window is built for one edge and
    // never moves: when the bar is moved, the entry changes, this window
    // is dropped and a fresh one is built on the new edge (see the
    // comment on `bars` in shell.qml).
    required property var modelData
    screen: modelData.screen

    // The shell-wide tray (see shell.qml): what apps have put in the
    // system tray, and which ones are pinned.
    required property var traySource

    // The shell-wide Quick Panel (see shell.qml); the notification bell opens it.
    required property var quickPanel

    // The shell-wide wallpaper picker (see shell.qml); the utility
    // buttons' Wallpapers button opens it on this monitor.
    required property var picker

    // Which edge this bar is on (services/BarPositionService.qml chooses
    // it; it arrives here through modelData and is fixed for the life of
    // the window). The window sticks to that edge and both neighbouring
    // edges, so it runs the full length of the screen: top/bottom bars
    // lie flat, left/right bars stand up.
    readonly property string barPosition: modelData.position
    readonly property bool vertical: win.barPosition === "left" || win.barPosition === "right"
    anchors {
        top: win.barPosition !== "bottom"
        bottom: win.barPosition !== "top"
        left: win.barPosition !== "right"
        right: win.barPosition !== "left"
    }
    // The bar's design thickness is 63 when it lies flat and 74 when it
    // stands up; the whole bar is drawn inside a ScaleHost (see the end
    // of this file) so the window has to be that much thicker or thinner
    // for this monitor's scale (scale.json / services/ShellScale.qml).
    // Only the thickness is set: the other direction comes from the
    // anchors.
    // (This edge's own thickness, not BarPositionService.thickness: that
    // follows the *current* edge, and would resize this window while it
    // is being replaced.)
    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real thickness: BarPositionService.thicknessFor(win.barPosition)
    // (The Capsule style is a slimmer bar: it reserves Theme.capStrip, or Theme.capStripV on
    // a standing bar, whatever the edge's usual thickness is.)
    readonly property real stripSize: Math.round((win.barStyle === 3 ? (win.vertical ? mt.capStripV : mt.capStrip)
    : win.thickness) * win.uiScale)

    // ===== Edit Desktop =====
    readonly property bool editing: win.screen !== null && EditMode.editing(win.screen.name)
    // The window is only the strip plus a few pixels of room, except while this monitor is in
    // Edit Desktop (EditStage below shrinks the whole picture into a card and needs the
    // whole screen). Why: a Qt window reports its whole surface as changed whenever it
    // draws, so a screen-sized transparent bar made Hyprland re-composite (and re-blur, if
    // blur is on) the entire screen for every frame the bar drew, and kept it busy at idle
    // (measured: Hyprland ~22 % of the iGPU with the bar, ~3 % without it, qs itself <1 %).
    // The window stays anchored to its edge and to both neighbouring edges, so the strip is
    // in the same place on screen and every position in this file (mask, popupX / popupY,
    // the status bar's x / y) keeps working in window pixels: they are all measured from
    // the edge the bar sits on. The room is for the popups' anchor points, which sit a few
    // pixels past the strip. `ipc call options set bar.compactWindow false` goes back to
    // the screen-sized window.
    //
    // Only for a bar on the TOP or LEFT edge. A layer-shell window anchored to the bottom or the
    // right edge that changes size shows its old picture at the new surface's top-left corner for
    // a frame or two, so a bottom bar jumped to the top of the screen (and a right bar to the
    // left) every time Edit Desktop started or ended and the window grew / shrank. A top or left
    // window grows away from its own origin, so the old picture is still in the right place.
    // The bottom and right edges therefore keep the screen-sized window (see EditMode.qml's
    // header: the same reason the bar and the dock never resized before this).
    readonly property bool growsFromOrigin: win.barPosition === "top" || win.barPosition === "left"
    // The equalizer opens in the middle of the screen, far from the strip: a popup's
    // anchor point has to lie inside its parent window, so while that card is up (and
    // for a moment after it has shrunk away) the window is the whole screen, as when
    // `bar.compactWindow` is off. The mask still lets only the strip take input.
    property bool eqWindowFull: false
    onEqPopupOpenChanged: {
        if (win.eqPopupOpen) {
            eqFullHold.stop()
            win.eqWindowFull = true
        } else {
            eqFullHold.restart()
        }
    }
    Timer {
        id: eqFullHold
        interval: 700
        onTriggered: win.eqWindowFull = false
    }
    readonly property bool compactWindow: SettingsService.flag("bar.compactWindow") && !win.editing && win.growsFromOrigin && !win.eqWindowFull
    // (Only the popups' anchor points and the hover tags' anchor boxes sit past the strip, and
    // those are separate popup windows now, so a few pixels is enough. Smaller = less for
    // Hyprland to composite; if a popup ever looks mis-placed, raise the 8.)
    readonly property real windowRoom: Math.ceil(8 * win.uiScale)
    implicitHeight: win.vertical ? 0 : (win.screen
    ? (win.compactWindow ? Math.min(Math.round(win.screen.height), win.stripSize + win.windowRoom)
    : Math.round(win.screen.height))
    : win.stripSize)
    implicitWidth: win.vertical ? (win.screen
    ? (win.compactWindow ? Math.min(Math.round(win.screen.width), win.stripSize + win.windowRoom)
    : Math.round(win.screen.width))
    : win.stripSize) : 0
    // Auto would reserve the whole window: spell out the strip.
    exclusionMode: ExclusionMode.Normal
    // The equalizer card has text fields (preset name, Last.fm key). A popup only
    // gets the keyboard through its parent layer surface, which by default takes
    // none: ask for it while the card is open (and only then).
    WlrLayershell.keyboardFocus: win.eqPopupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // Transparent style: the pills sit straight on the wallpaper, so the space
    // under (or beside) them should be small. Two things are taken off what the
    // bar reserves:
    //  - Hyprland's `general.gaps_out`, which it adds between the reserved strip
    //    and the windows. The pills are centred in the strip, so this alone
    //    makes the gap to the windows equal to the gap to the screen edge.
    //  - `transparentExtraGap` more, so the windows sit a little closer than
    //    that. Make this number bigger for a smaller gap, 0 for the equal one.
    // Float and Straight keep the full strip (the bar is a visible object
    // there). Follows the Hyprland setting live.
    readonly property real transparentExtraGap: 5
    // Capsule takes only the gaps_out off (no extra): its strip already holds an 8 px
    // gap under the bar, so the windows end up that far below the bar's shadow.
    readonly property real transparentTrim: win.barStyle === 2
    ? Math.min(Math.max(0, HyprlandSettings.num("general.gaps_out")) + Math.round(win.transparentExtraGap * win.uiScale),
               Math.round(win.stripSize * 0.6))
    : (win.barStyle === 3
    ? Math.min(Math.max(0, HyprlandSettings.num("general.gaps_out")), Math.round(win.stripSize * 0.6))
    : 0)
    // An auto-hiding bar reserves nothing: the windows use the whole screen and the bar
    // slides in over them.
    exclusiveZone: win.autoHide ? 0 : win.stripSize - win.transparentTrim
    color: "transparent"

    // Game Mode (GameModeService.qml): the bar is a fixed strip of date / clock /
    // weather that only shows. Nothing on it can be clicked or hovered, so every
    // click goes through to the game (the same 1 px as while editing).
    readonly property bool gameMode: GameModeService.enabled
    readonly property bool passive: win.editing || win.gameMode
    // What the bar shows in Game Mode, in this order (Status_Bar.qml only shows
    // these three, see its `gameMode`).
    readonly property var gameLayout: ({ left: [], center: ["date", "clock", "weather"], right: [] })

    // Only the strip takes input, and nothing while editing or in Game Mode (1 px
    // in the corner, which is never part of the card).
    // A bar on the bottom edge also gives up the Quick Panel's hot edge (the strip at the
    // bottom centre, QuickPanel.qml): that spot is cut out of the bar's input region, so the
    // pointer reaches the hot-edge window under it. (Same width / height / centring as that
    // window; the bar's pills never reach the last 4 px of the strip.)
    mask: Region {
        item: barMask
        regions: [ Region { item: hotCut; intersection: Intersection.Subtract } ]
    }
    Item {
        id: hotCut
        readonly property bool on: win.barPosition === "bottom" && !win.passive
        && win.quickPanel !== null && win.quickPanel.hotEdge
        width: on ? Math.min(win.width, win.quickPanel.hotWidth) : 0
        height: on ? win.quickPanel.hotHeight : 0
        x: (win.width - width) / 2
        y: win.height - height
    }
    // Tucked away (auto-hide), only a thin line on the very edge takes input: the pointer
    // touching it brings the bar out.
    Item {
        id: barMask
        readonly property real across: win.tucked ? win.hotThick : win.stripSize
        x: win.passive ? 0 : (win.barPosition === "right" ? win.width - across : 0)
        y: win.passive ? 0 : (win.barPosition === "bottom" ? win.height - across : 0)
        width: win.passive ? 1 : (win.vertical ? across : win.width)
        height: win.passive ? 1 : (win.vertical ? win.height : across)
    }

    // ===== auto-hide (issue #61) =====
    // Settings -> Bar -> Auto-hide ("bar.hideMode": off | auto). The bar slides off its
    // edge and comes back while the pointer is on the edge or on the bar, while one of its
    // popups is open, in Edit Desktop, and for a moment on `ipc call bar peek`.
    readonly property bool autoHide: SettingsService.get("bar.hideMode") === "auto"
    property bool hoverWin: false
    readonly property bool popupOpen: win.trayOpen || trayPopups.showing || win.batteryPopupOpen
        || win.utilPopupOpen || win.resourcePopupOpen || win.calendarPopupOpen || win.weatherPopupOpen
        || win.mediaPopupOpen || win.eqPopupOpen || win.discordPopupOpen || win.pluginPopup !== ""
    readonly property bool revealed: !win.autoHide || win.editing || win.hoverWin || win.popupOpen
        || hideGrace.running || peekHold.running
    // How deep the line on the edge is, real pixels.
    readonly property real hotThick: Math.max(2, Math.round(3 * win.uiScale))
    // 0 = out, 1 = away; drawn as "whichever pushes it further" with a preset's slide.
    property real hideSlide: win.revealed ? 0 : 1
    Behavior on hideSlide {
        enabled: win.animReady
        NumberAnimation { duration: 220; easing.type: win.revealed ? Easing.OutCubic : Easing.InCubic }
    }
    readonly property bool tucked: win.autoHide && !win.revealed && win.hideSlide > 0.99
    // A bar built hidden (a shell start, a new monitor) is simply away; the slide starts
    // to animate once it is on screen.
    property bool animReady: false
    Timer {
        interval: 600
        running: win.visible && !win.animReady
        onTriggered: win.animReady = true
    }
    // So moving the pointer off the bar toward a window doesn't flick it away at once.
    Timer {
        id: hideGrace
        interval: 450
    }
    onHoverWinChanged: {
        if (!win.hoverWin && win.autoHide)
            hideGrace.restart()
    }
    onPopupOpenChanged: {
        if (!win.popupOpen && win.autoHide)
            hideGrace.restart()
    }
    Timer {
        id: peekHold
        interval: 2000
    }
    // Bring the bar out for a moment (`ipc call bar peek`); it hides again by itself.
    function peek() {
        peekHold.restart()
    }

    // Going into Game Mode puts every open popup away (nothing on the bar can
    // open or close one any more).
    Connections {
        target: GameModeService
        function onEnabledChanged() {
            if (!GameModeService.enabled)
                return
                win.trayOpen = false
                win.batteryPopupOpen = false
                win.utilPopupOpen = false
                win.resourcePopupOpen = false
                win.calendarPopupOpen = false
                win.weatherPopupOpen = false
                win.mediaPopupOpen = false
                win.eqPopupOpen = false
                win.discordPopupOpen = false
                win.pluginPopup = ""
        }
    }

    // Popups are closed as the mode starts.
    Connections {
        target: EditMode
        function onActiveChanged() {
            if (!EditMode.active || !win.editing)
                return
                win.trayOpen = false
                win.batteryPopupOpen = false
                win.utilPopupOpen = false
                win.resourcePopupOpen = false
                win.calendarPopupOpen = false
                win.weatherPopupOpen = false
                win.mediaPopupOpen = false
                win.eqPopupOpen = false
                win.discordPopupOpen = false
                win.pluginPopup = ""
        }
    }

    // ===== where popups go =====
    // (Capsule: its strip already holds an 8 px gap beside the bar, so no extra.)
    readonly property real popupGap: win.barStyle === 3 ? 0 : 4
    function popupX(cx, cy, w, h) {
        if (win.vertical)
            return win.barPosition === "left" ? win.stripSize + win.popupGap : win.width - win.stripSize - win.popupGap
            const maxX = win.width - w - 8
            return Math.max(8, Math.min(cx - w / 2, maxX))
    }
    function popupY(cx, cy, w, h) {
        if (!win.vertical)
            return win.barPosition === "bottom" ? win.height - win.stripSize : win.stripSize
            const maxY = win.height - h - 8
            return Math.max(8, Math.min(cy - h / 2, maxY))
    }
    readonly property int popupGravity: {
        if (win.vertical)
            return win.barPosition === "left" ? (Edges.Bottom | Edges.Right)
            : (Edges.Bottom | Edges.Left)
            return win.barPosition === "bottom" ? (Edges.Top | Edges.Right)
            : (Edges.Bottom | Edges.Right)
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Whether the tray dropdown is open. The button flips it; the popup
    // shows/hides from it and sets it back to false after you pick
    // something or click away — the button pulses by itself when that
    // happens.
    property bool trayOpen: false

    // Something left for the dropdown to show? (See Status_Bar.)
    readonly property bool trayAvailable: traySource.unpinnedItems.length > 0
    onTrayAvailableChanged: {
        if (!trayAvailable)
            trayOpen = false
    }

    // The dropdown + right-click menu, and what clicks on tray icons do.
    TrayPopups {
        id: trayPopups
        parentWindow: win
        source: win.traySource
        toggleAnchor: statusBar.trayToggle
        open: win.trayOpen
        onCloseRequested: win.trayOpen = false
    }

    // Whatever is playing (Spotify, mpv, a YouTube tab in the browser...)
    MediaSource {
        id: mediaSource
    }

    // CPU/RAM and battery — each Bar instance polls its own copy, same
    // as MediaSource (cheap enough not to bother sharing across
    // monitors; see ResourceSource.qml / BatterySource.qml).
    ResourceSource {
        id: resourceSource
        // Nothing reads the numbers while the module is switched off for this bar.
        wanted: statusBar.shows("resources") || win.resourcePopupOpen
    }

    // The status pill's Wi-Fi / Bluetooth look (StatusIconsService) runs only while some bar
    // shows the pill: it is one look for the whole shell, so each bar adds itself to a count
    // while its pill is on. `counted` makes adding and removing safe in any order of signals
    // (the first evaluation, a change, this bar being rebuilt or destroyed).
    QtObject {
        id: statusDemand

        property bool counted: false
        readonly property bool want: statusBar.shows("status")

        onWantChanged: statusDemand.sync()

        function sync() {
            if (statusDemand.want === statusDemand.counted)
                return
                statusDemand.counted = statusDemand.want
                StatusIconsService.watch(statusDemand.want ? 1 : -1)
        }

        Component.onCompleted: statusDemand.sync()
        Component.onDestruction: {
            if (statusDemand.counted) {
                statusDemand.counted = false
                StatusIconsService.watch(-1)
            }
        }
    }

    BatterySource {
        id: batterySource
    }

    WeatherSource {
        id: weatherSource
    }

    // Whether the battery / resource popup is open. Same pattern as
    // trayOpen above: owned here, the indicator asks to flip it, the
    // popup's own click-away sets it back to false. Opening one closes
    // the other so they don't stack.
    property bool batteryPopupOpen: false
    property bool resourcePopupOpen: false
    property bool calendarPopupOpen: false
    property bool weatherPopupOpen: false
    property bool mediaPopupOpen: false
    property bool eqPopupOpen: false
    property bool discordPopupOpen: false
    // The utility keys' flyout (UtilPopup.qml), for a short standing bar.
    property bool utilPopupOpen: false
    // The plugin whose popup is open, as "plugin:<id>" ("" = none): one at a time, like the rest.
    property string pluginPopup: ""

    // The plugins' bar entries (docs/PLUGINS.md), for Status_Bar: each with its state.
    readonly property var pluginEntries: PluginService.barPlugins
        .map(f => ({ key: "plugin:" + f.plugin.id, st: PluginService.states[f.plugin.id] ?? null }))
        .filter(e => e.st !== null)

    // A plugin entry's left click: its popup, when it has one.
    function togglePluginPopup(key) {
        const e = win.pluginEntries.find(x => x.key === key)
        if (!e || !e.st.plugin.files.popup)
            return
        const opening = win.pluginPopup !== key
        eqPopupOpen = false
        mediaPopupOpen = false
        discordPopupOpen = false
        batteryPopupOpen = false
        utilPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        pluginPopup = opening ? key : ""
    }

    // `ipc call plugins popup <id>`: only the focused monitor's bar answers, and only when
    // the entry is on it.
    Connections {
        target: PluginService
        function onPopupWanted(key) {
            const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            if (win.screen === null || (name !== "" && win.screen.name !== name))
                return
            const it = statusBar.pluginToggle(key)
            if (it && it.visible)
                win.togglePluginPopup(key)
        }
    }

    // A plugin that goes away (removed, or its entry switched off) takes its popup with it.
    onPluginEntriesChanged: {
        if (win.pluginPopup !== "" && !win.pluginEntries.some(e => e.key === win.pluginPopup))
            win.pluginPopup = ""
    }

    function toggleMediaPopup() {
        if (eqPopupOpen) {
            EqualizerService.discardIfPending()
            eqPopupOpen = false
            return
        }
        batteryPopupOpen = false
        utilPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        discordPopupOpen = false
        pluginPopup = ""
        mediaPopupOpen = !mediaPopupOpen
    }

    // The equalizer card (EqualizerPopup.qml) takes the media panel's place under
    // the same pill: the turntable's EQ key opens it, its album key goes back.
    function openEqPopup() {
        batteryPopupOpen = false
        utilPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        discordPopupOpen = false
        mediaPopupOpen = false
        pluginPopup = ""
        eqPopupOpen = true
    }

    function backToTurntable() {
        eqPopupOpen = false
        mediaPopupOpen = true
    }

    // `qs -c sekaipop ipc call eq open`: on the focused monitor's bar only.
    Connections {
        target: EqualizerService
        function onOpenRequested() {
            const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            if (win.screen === null || (name !== "" && win.screen.name !== name))
                return
                if (win.eqPopupOpen) {
                    EqualizerService.discardIfPending()
                    win.eqPopupOpen = false
                } else {
                    win.openEqPopup()
                }
        }
    }

    // The Discord panel under the Discord pill (only while you are in a call).
    function toggleDiscordPopup() {
        eqPopupOpen = false
        mediaPopupOpen = false
        batteryPopupOpen = false
        utilPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        pluginPopup = ""
        discordPopupOpen = DiscordVoiceService.inVoice && !discordPopupOpen
    }

    // The call ended: put the panel away.
    Connections {
        target: DiscordVoiceService
        function onInVoiceChanged() {
            if (!DiscordVoiceService.inVoice)
                win.discordPopupOpen = false
        }
    }

    function toggleBatteryPopup() {
        eqPopupOpen = false
        mediaPopupOpen = false
        discordPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        utilPopupOpen = false
        pluginPopup = ""
        batteryPopupOpen = !batteryPopupOpen
    }
    function toggleResourcePopup() {
        eqPopupOpen = false
        mediaPopupOpen = false
        discordPopupOpen = false
        batteryPopupOpen = false
        utilPopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        pluginPopup = ""
        resourcePopupOpen = !resourcePopupOpen
    }
    function toggleCalendarPopup() {
        eqPopupOpen = false
        mediaPopupOpen = false
        discordPopupOpen = false
        batteryPopupOpen = false
        utilPopupOpen = false
        resourcePopupOpen = false
        weatherPopupOpen = false
        pluginPopup = ""
        calendarPopupOpen = !calendarPopupOpen
    }
    function toggleWeatherPopup() {
        eqPopupOpen = false
        mediaPopupOpen = false
        discordPopupOpen = false
        batteryPopupOpen = false
        utilPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        pluginPopup = ""
        weatherPopupOpen = !weatherPopupOpen
    }
    // The tools key of a short standing bar (Status_Bar `utilFlyout`).
    function toggleUtilPopup() {
        eqPopupOpen = false
        mediaPopupOpen = false
        discordPopupOpen = false
        batteryPopupOpen = false
        resourcePopupOpen = false
        calendarPopupOpen = false
        weatherPopupOpen = false
        pluginPopup = ""
        utilPopupOpen = !utilPopupOpen
    }

    // The media panel under the media pill: a card per player.
    LazyLoader {
        id: mediaPopupLazy
        // Built the first time it is asked for (not at start-up on every monitor), then kept.
        property bool want: win.mediaPopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        MediaPopup {
            // Starts closed and opens a beat later, so its open-handlers (focus grab,
            // refresh, ...) run exactly as they do when the button is clicked.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: mediaPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.mediaToggle
            source: mediaSource
            onCloseRequested: win.mediaPopupOpen = false
            onEqRequested: win.openEqPopup()
        }
    }

    // The equalizer card: a record with ten pegs round it. Built the first time
    // it is asked for, then kept.
    LazyLoader {
        id: eqPopupLazy
        property bool want: win.eqPopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        EqualizerPopup {
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: eqPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.mediaToggle
            source: mediaSource
            onCloseRequested: {
                EqualizerService.discardIfPending()
                win.eqPopupOpen = false
            }
            onTurntableRequested: win.backToTurntable()
        }
    }

    // The Discord call panel under the Discord pill: who is in the call,
    // mute / deafen, open Discord.
    LazyLoader {
        id: discordPopupLazy
        // Built the first time it is asked for (not at start-up on every monitor), then kept.
        property bool want: win.discordPopupOpen && DiscordVoiceService.inVoice
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        DiscordPopup {
            // Starts closed and opens a beat later, so its open-handlers (focus grab,
            // refresh, ...) run exactly as they do when the button is clicked.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: discordPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.discordToggle
            onCloseRequested: win.discordPopupOpen = false

            channelName: DiscordVoiceService.channel ? (DiscordVoiceService.channel.name || "") : ""
            backendLabel: DiscordVoiceService.backendLabel
            guildName: DiscordVoiceService.channel ? (DiscordVoiceService.channel.guild_name || "") : ""
            guildIconUrl: DiscordVoiceService.channel ? (DiscordVoiceService.channel.guild_icon_url || "") : ""
            participants: DiscordVoiceService.participants
            selfId: DiscordVoiceService.selfId
            muted: DiscordVoiceService.muted
            deafened: DiscordVoiceService.deafened
            hint: SettingsService.get("discord.leftClick") === "panel"
            ? "Right-click the pill to deafen · middle-click to mute"
            : "Left-click the pill to mute · right-click to deafen"
            onMuteRequested: DiscordVoiceService.setMuted(!DiscordVoiceService.muted)
            onDeafenRequested: DiscordVoiceService.setDeafened(!DiscordVoiceService.deafened)
            onOpenClientRequested: {
                if (DiscordVoiceService.focusClient())
                    win.discordPopupOpen = false
            }
        }
    }

    LazyLoader {
        id: batteryPopupLazy
        // Built the first time it is asked for (not at start-up on every monitor), then kept.
        property bool want: win.batteryPopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        BatteryPopup {
            // Starts closed and opens a beat later, so its open-handlers (focus grab,
            // refresh, ...) run exactly as they do when the button is clicked.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: batteryPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.batteryToggle
            onCloseRequested: win.batteryPopupOpen = false

            percentage: batterySource.percentage
            statusLabel: batterySource.statusLabel
            timeRemaining: batterySource.timeRemaining
        }
    }

    // The utility keys' flyout, from the tools key of a short standing bar. Built the first
    // time it is asked for, then kept (like the battery card above).
    LazyLoader {
        id: utilPopupLazy
        property bool want: win.utilPopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        UtilPopup {
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: utilPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.utilToggle
            source: statusBar.utilSource
            onCloseRequested: win.utilPopupOpen = false
        }
    }

    // The bar grew tall enough (or the keys' setting changed) that the long pill is back:
    // the flyout has nothing to grow out of any more.
    Connections {
        target: statusBar
        function onUtilFlyoutChanged() {
            if (!statusBar.utilFlyout)
                win.utilPopupOpen = false
        }
    }

    // The month card under the date pill. `today` follows the bar's
    // SystemClock, so the highlighted day rolls over at midnight.
    LazyLoader {
        id: calendarPopupLazy
        // Built the first time it is asked for (not at start-up on every monitor), then kept.
        property bool want: win.calendarPopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        CalendarPopup {
            // Starts closed and opens a beat later, so its open-handlers (focus grab,
            // refresh, ...) run exactly as they do when the button is clicked.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: calendarPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.dateToggle
            today: clock.date
            onCloseRequested: win.calendarPopupOpen = false
        }
    }

    // The plugins' popups, one per plugin entry that has a Popup.qml (PluginPopup.qml builds
    // the plugin's card the first time it opens).
    Instantiator {
        model: win.pluginEntries.filter(e => e.st.plugin.files.popup)

        delegate: PluginPopup {
            required property var modelData
            key: modelData.key
            st: modelData.st
            // Starts closed and opens a beat later, like the built-in popups.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: win.pluginPopup === modelData.key && ready && !!anchorItem && anchorItem.visible
            parentWindow: win
            anchorItem: statusBar.pluginItems[modelData.key] ?? null
            onCloseRequested: {
                if (win.pluginPopup === modelData.key)
                    win.pluginPopup = ""
            }
        }
    }

    // The weather card under the weather pill.
    LazyLoader {
        id: weatherPopupLazy
        // Built the first time it is asked for (not at start-up on every monitor), then kept.
        property bool want: win.weatherPopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        WeatherPopup {
            // Starts closed and opens a beat later, so its open-handlers (focus grab,
            // refresh, ...) run exactly as they do when the button is clicked.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: weatherPopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.weatherToggle
            source: weatherSource
            onCloseRequested: win.weatherPopupOpen = false
        }
    }

    LazyLoader {
        id: resourcePopupLazy
        // Built the first time it is asked for (not at start-up on every monitor), then kept.
        property bool want: win.resourcePopupOpen
        property bool seen: false
        onWantChanged: if (want) seen = true
        active: seen

        ResourcePopup {
            // Starts closed and opens a beat later, so its open-handlers (focus grab,
            // refresh, ...) run exactly as they do when the button is clicked.
            property bool ready: false
            Component.onCompleted: Qt.callLater(() => ready = true)
            open: resourcePopupLazy.want && ready
            parentWindow: win
            anchorItem: statusBar.resourceToggle
            onCloseRequested: win.resourcePopupOpen = false

            cpuPercent: resourceSource.cpuPercent
            memPercent: resourceSource.memPercent
            memUsedLabel: resourceSource.memUsedLabel
            memTotalLabel: resourceSource.memTotalLabel
        }
    }

    // This monitor's own workspace, falling back to the focused one
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeWorkspace: NiriWorkspaces.running ? NiriWorkspaces.activeOn(screen?.name ?? "") : monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1

    // Ids of workspaces that currently have windows. Lets the badges show the
    // ones above the configured count only while they are in use.
    readonly property var occupiedWorkspaces: NiriWorkspaces.running ? NiriWorkspaces.occupiedOn(screen?.name ?? "") : Hyprland.workspaces.values
    .filter(w => w.id > 0 && w.toplevels.values.length > 0)
    .map(w => w.id)

    // Hyprland.usingLua is documented as a real property, but on some
    // Quickshell builds it comes back as plain `undefined` rather than
    // `false` (property missing, not just "not yet initialized").
    // Treating that as "not Lua" sent old hyprlang syntax to a
    // Lua-mode Hyprland and every dispatch failed with a Lua parse
    // error. Only trust an explicit `false`; anything else (true, or
    // undefined because the property doesn't exist) is treated as
    // Lua mode, since that's Hyprland's current default and what
    // every dispatch below is written for.
    readonly property bool usingLua: Hyprland.usingLua !== false

    // Hyprland.activeToplevel is global — the same value on every
    // monitor's bar — so only treat it as *this* bar's window if it's
    // actually on this monitor's active workspace.
    readonly property var focusedWindow: Hyprland.activeToplevel?.workspace?.id === activeWorkspace
    ? Hyprland.activeToplevel
    : null

    // The window's class / app id ("org.mozilla.firefox", "kitty"...)
    readonly property string windowClass: focusedWindow
    ? (focusedWindow.wayland?.appId
    || focusedWindow.lastIpcObject?.class
    || focusedWindow.lastIpcObject?.initialClass
    || "")
    : ""

    // Display name for it: the .desktop entry's Name when there is one
    // ("Firefox", "Visual Studio Code"), else a tidied-up class.
    function appDisplayName(cls) {
        if (cls === "")
            return ""
            try {
                const entry = DesktopEntries.heuristicLookup(cls)
                if (entry && entry.name)
                    return entry.name
            } catch (e) {}
            // "org.mozilla.firefox" -> "Firefox", "code-oss" -> "Code-oss"
            const last = cls.split(".").pop()
            return last.charAt(0).toUpperCase() + last.slice(1)
    }

    // The same app's icon as a file url, for the standing bar's Active window
    // key. "" when the class has no .desktop entry or the icon is not found
    // (the key then shows the app's first letter).
    readonly property string windowIconSource: {
        if (win.windowClass === "")
            return ""
            try {
                const entry = DesktopEntries.heuristicLookup(win.windowClass)
                if (entry && entry.icon)
                    return IconCursorService.path(entry.icon, "application-x-executable")
            } catch (e) {}
            return ""
    }

    function pad(n) {
        return ("0" + n).slice(-2)
    }

    // "09:05 PM", same shape as the Figma "00:00 AM" (12-hour, zero-padded)
    function formatClock(d) {
        // 24-hour time (Settings -> General): "21:05".
        if (SettingsService.flag("time.use24h"))
            return pad(d.getHours()) + ":" + pad(d.getMinutes())
            const h = d.getHours()
            const h12 = h % 12 === 0 ? 12 : h % 12
            return pad(h12) + ":" + pad(d.getMinutes()) + " " + (h < 12 ? "AM" : "PM")
    }

    // "Mon, Sep 28" for the date pill.
    function formatDate(d) {
        return d.toLocaleDateString(Qt.locale(), "ddd, MMM d")
    }

    // The bar's look (BarStyleService.qml): 0 Float, 1 Straight,
    // 2 Transparent, 3 Capsule. Float and Capsule are inset from the screen
    // edges, by the same gap the bar keeps outside its workspace badges
    // (Theme.barFloatInset); it glides in and out when the style changes.
    // Straight also sits flush with the screen edge the bar is on, and Capsule
    // keeps Theme.capEdgeGap off it.
    // Capsule is drawn on any edge: on a bar that stands up it is the same slim rounded bar, with
    // its chips stacked (Theme.capVChip wide).
    readonly property int barStyle: BarStyleService.index
    // (Held on a plain Item so the Behavior has an Item to animate on.)
    Item {
        id: geometry
        property real sideInset: (win.barStyle === 0 || win.barStyle === 3) ? mt.barFloatInset : 0
        Behavior on sideInset {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }

        // Wearing a desktop preset that changes the bar: it slides off the
        // edge it is on, the preset goes on, and it slides back (see
        // PresetMotion.qml). 0 = in place, 1 = away. Two fixed animations
        // started from the flag, not one Behavior (see ClockWidget's reveal).
        property real slide: 0
        NumberAnimation {
            id: slideOut
            target: geometry
            property: "slide"
            to: 1
            duration: PresetMotion.outMs
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            id: slideIn
            target: geometry
            property: "slide"
            to: 0
            duration: PresetMotion.inMs
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }
        Connections {
            target: PresetMotion
            function onBarOutChanged() {
                if (PresetMotion.barOut) {
                    slideIn.stop()
                    slideOut.restart()
                } else {
                    slideOut.stop()
                    slideIn.restart()
                }
            }
        }
        // A bar built in the middle of a swap (a new edge builds a new
        // window) starts away and comes in once the others do.
        Component.onCompleted: {
            if (PresetMotion.barBusy) {
                geometry.slide = 1
                if (!PresetMotion.barOut)
                    slideIn.restart()
            }
        }
    }

    // The bar's picture. Out of edit mode it is exactly the window (scale 1, no
    // offset). While editing it is the same picture scaled down and moved to
    // where the card is, like the wallpaper's.
    EditStage {
        id: stage
        screenObj: win.screen
        uiScale: win.uiScale
        // The card is worked out from the SCREEN's size, not the window's: the window is only
        // the strip until it has grown for Edit Desktop, and for those first frames a card
        // worked out from the strip's size is in the wrong place (a top / left window's corner
        // is the screen's corner, so no origin is needed).
        refWidth: win.screen ? win.screen.width : win.width
        refHeight: win.screen ? win.screen.height : win.height
        // Cuts off what the Straight style bleeds past the screen edge (it was
        // the window's edge that hid that); here the card's edge does.
        clip: true

        ScaleHost {
            anchors.fill: parent
            factor: win.uiScale

            Status_Bar {
                id: statusBar
                vertical: win.vertical
                barPosition: win.barPosition
                // The bar hugs the screen edge it's on (1px off it, except
                // Straight which is flush), and runs along the edge inset by
                // sideInset (only Float has an inset).
                readonly property real edgeGap: win.barStyle === 1 ? 0 : (win.barStyle === 3 ? mt.capEdgeGap : 1)
                // How far it is pushed off its edge while a preset swaps it
                // (geometry.slide, 0..1): its own thickness, the gap and room
                // for the shadow.
                readonly property real slideDist: (win.vertical ? width : height) + edgeGap + 20
                readonly property real slideBy: Math.max(geometry.slide, win.hideSlide) * statusBar.slideDist
                x: win.vertical
                ? (win.barPosition === "right" ? parent.width - width - edgeGap + slideBy : edgeGap - slideBy)
                : geometry.sideInset
                y: win.vertical
                ? geometry.sideInset
                : (win.barPosition === "bottom" ? parent.height - height - edgeGap + slideBy : edgeGap - slideBy)
                width: win.vertical ? (win.barStyle === 3 ? mt.capVBarFace : mt.barVBody) : parent.width - 2 * geometry.sideInset
                height: win.vertical ? parent.height - 2 * geometry.sideInset : (win.barStyle === 3 ? mt.capBarHeight : 61)
                barStyle: win.barStyle

                activeWorkspace: win.activeWorkspace
                occupiedWorkspaces: win.occupiedWorkspaces
                workspaceCount: Math.max(1, Math.min(10, Math.round(Number(SettingsService.get("bar.workspaceCount")) || 5)))
                gameMode: win.gameMode
                modules: BarLayoutService.modulesFor(win.screen ? win.screen.name : "")
                clockText: win.formatClock(clock.date)
                dateText: win.formatDate(clock.date)
                onDateClicked: win.toggleCalendarPopup()
                scaleValue: win.uiScale
                layout: win.gameMode ? win.gameLayout : BarLayoutService.layoutFor(win.screen ? win.screen.name : "")
                onWallpapersToggleRequested: win.picker.toggleOn(win.screen)

                mediaActive: mediaSource.present
                mediaPlaying: mediaSource.playing
                mediaTitle: mediaSource.title
                mediaArtist: mediaSource.artist
                mediaArtUrl: mediaSource.artUrl
                mediaVisualizerStyle: VisualizerService.pillStyle
                mediaPoints: PcCavaService.points
                mediaLeftOpensPanel: SettingsService.get("media.leftClick") === "panel"
                mediaVolumeAvailable: mediaSource.volumeAvailable
                onMediaPanelRequested: win.toggleMediaPopup()
                onMediaScrolled: direction => mediaSource.changeVolume(direction)
                onMediaToggleRequested: mediaSource.togglePlaying()
                onMediaNextRequested: mediaSource.next()
                onMediaPreviousRequested: mediaSource.previous()

                onNotificationsToggleRequested: win.quickPanel.toggleOn(win.screen)

                cpuPercent: resourceSource.cpuPercent
                memPercent: resourceSource.memPercent
                onResourcesClicked: win.toggleResourcePopup()

                // "--" until the first fetch lands (or if curl/the network
                // isn't available) rather than showing a blank pill.
                weatherTemperature: weatherSource.temperatureText !== "" ? weatherSource.temperatureText : "--"
                weatherIconName: weatherSource.iconName
                onWeatherClicked: win.toggleWeatherPopup()
                pluginEntries: win.pluginEntries
                pluginPopupOpen: win.pluginPopup
                onPluginClicked: key => win.togglePluginPopup(key)

                batteryAvailable: batterySource.available
                batteryPercentage: batterySource.percentage
                batteryCharging: batterySource.isCharging
                batteryLow: batterySource.isLow
                onBatteryClicked: win.toggleBatteryPopup()
                utilPopupOpen: win.utilPopupOpen
                onUtilClicked: win.toggleUtilPopup()

                // Wi-Fi / Bluetooth / speaker as icons (StatusIconsService);
                // a click opens the Quick Panel, where the switches are.
                statusNetworkShown: StatusIconsService.networkShown
                statusNetworkIcon: StatusIconsService.networkIcon
                statusNetworkState: StatusIconsService.networkState
                statusBluetoothShown: StatusIconsService.bluetoothShown
                statusBluetoothIcon: StatusIconsService.bluetoothIcon
                statusBluetoothState: StatusIconsService.bluetoothState
                statusSpeakerShown: StatusIconsService.speakerShown
                statusSpeakerIcon: StatusIconsService.speakerIcon
                statusSpeakerState: StatusIconsService.speakerState
                statusDetail: StatusIconsService.detail
                onStatusClicked: win.quickPanel.toggleOn(win.screen)

                keyboardLayoutCode: KeyboardLayoutService.code
                onKeyboardLayoutClicked: KeyboardLayoutService.cycle()

                notificationCount: win.quickPanel.notificationSource.count
                notificationsMuted: !win.quickPanel.source.notificationsOn

                // Who has the microphone, what is playing, or the screen (PrivacyService).
                privacyMic: PrivacyService.micLive
                privacyAudio: PrivacyService.audioLive
                privacyScreen: PrivacyService.screenLive
                // The hover tag: one line per thing in use.
                privacyDetail: {
                    const lines = []
                    if (PrivacyService.screenLive)
                        lines.push("Screen shared with: " + PrivacyService.screenApps.join(", "))
                    if (PrivacyService.micLive)
                        lines.push("Microphone in use by: " + PrivacyService.micApps.join(", "))
                    if (PrivacyService.audioLive)
                        lines.push("Desktop audio recorded by: " + PrivacyService.audioApps.join(", "))
                    return lines.join("\n")
                }

                // The Discord voice call you are in (DiscordVoiceService).
                discordInCall: DiscordVoiceService.inVoice
                discordNeedsAuth: DiscordVoiceService.needsAuth
                discordAuthorizing: DiscordVoiceService.status === "authorizing"
                discordChannel: DiscordVoiceService.channel ? (DiscordVoiceService.channel.name || "") : ""
                discordParticipants: DiscordVoiceService.participants
                discordMuted: DiscordVoiceService.muted
                discordDeafened: DiscordVoiceService.deafened
                onDiscordMuteRequested: DiscordVoiceService.setMuted(!DiscordVoiceService.muted)
                onDiscordDeafenRequested: DiscordVoiceService.setDeafened(!DiscordVoiceService.deafened)
                onDiscordAuthorizeRequested: DiscordVoiceService.authorizeAfterFocusRelease()
                discordLeftOpensPanel: SettingsService.get("discord.leftClick") === "panel"
                discordPanelOpen: win.discordPopupOpen
                onDiscordPanelRequested: win.toggleDiscordPopup()

                // Pending package updates (PackageUpdatesService).
                updatesCount: PackageUpdatesService.total
                updatesNudging: PackageUpdatesService.nudging
                updatesShowZero: SettingsService.flag("updates.showZero")
                updatesBusy: PackageUpdatesService.status === "checking" || PackageUpdatesService.upgrading
                updatesLoading: PackageUpdatesService.loadingBadge
                updatesTip: PackageUpdatesService.breakdown
                + (PackageUpdatesService.total > 0 ? " — click to update, right-click to recheck" : " — right-click to recheck")
                onUpdatesClicked: PackageUpdatesService.runUpdate()
                onUpdatesRefreshRequested: PackageUpdatesService.refresh(true)

                trayOpen: win.trayOpen
                trayAvailable: win.trayAvailable
                trayMenuItem: trayPopups.menuItem
                trayLeavingItem: trayPopups.leavingItem
                trayAttention: win.traySource.unpinnedAttention
                trayScrollEnabled: SettingsService.flag("tray.scroll")
                onTrayItemScrolled: (item, delta, horizontal) => trayPopups.handleScroll(item, delta, horizontal)
                onTrayToggleRequested: win.trayOpen = !win.trayOpen
                trayPinned: win.traySource.pinnedItems
                onTrayItemClicked: (item, button, icon) => trayPopups.handleClick(item, button, icon, false)

                // Both are empty when nothing is focused on this bar's own
                // workspace; Status_Bar then falls back to "Workspace N".
                windowApp: win.appDisplayName(win.windowClass)
                windowTitle: win.focusedWindow?.title ?? ""
                windowIcon: win.windowIconSource

                // Hyprland's "workspace" dispatcher always acts on whichever
                // monitor is currently *focused* — not necessarily this bar's
                // own monitor. On a single-monitor setup that's the same
                // thing, so this looked fine there; on multi-monitor it meant
                // clicking a badge on a non-focused monitor's bar silently
                // changed the *other* (focused) monitor's workspace instead,
                // which read as "clicking does nothing" on the monitor you
                // were actually looking at. Focus this monitor first so the
                // dispatch always lands where the click happened.
                //
                // Hyprland 0.55 replaced the old hyprlang dispatch syntax
                // ("workspace 5") with Lua calls ("hl.dsp.focus({ workspace =
                // 5 })") — sending the old form to a Lua-mode Hyprland gets
                // parsed as raw Lua and fails with a syntax error. Hyprland.usingLua
                // tells us which one this system is running, so both are
                // supported. (hl.dsp.focusmonitor has no Lua equivalent yet as
                // of this writing — that's an upstream gap, not something we
                // can paper over here — so on a Lua-mode multi-monitor system
                // this pre-focus step is skipped rather than sent, and only the
                // workspace switch itself is dispatched.)
                onWorkspaceRequested: workspace => {
                    if (NiriWorkspaces.running) {
                        NiriWorkspaces.focus(win.screen.name, workspace)
                        return
                    }

                    if (win.monitor && !win.monitor.focused) {
                        if (win.usingLua)
                            console.warn("Bar.qml: no Lua dispatcher for focusmonitor yet — skipping pre-focus on " + win.monitor.name)
                            else
                                Hyprland.dispatch("focusmonitor " + win.monitor.name)
                    }
                    Hyprland.dispatch(win.usingLua
                    ? "hl.dsp.focus({ workspace = " + workspace + " })"
                    : "workspace " + workspace)
                }
            }
        }
    }

    // Sees the pointer on the bar and on the line at the edge, for auto-hide (only the
    // masked parts get pointer events). Last, so it is on top: a mouse area above it
    // could take the pointer away. A HoverHandler is passive, so clicks still go through.
    Item {
        anchors.fill: parent
        HoverHandler {
            onHoveredChanged: win.hoverWin = hovered
        }
    }
}
