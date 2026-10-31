import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Pure UI (no Quickshell imports): Bar.qml feeds this Hyprland/clock
// data through plain properties and turns its signals into actions.
//
// The outer bar frame is drawn here now instead of stretching
// status_Bar_BG.png with a BorderImage — same three-layer look as
// Pill.qml (navy outline, pale inset ring, white fill) on the same
// flat hard shadow, just without a press state since the bar itself
// never gets clicked. Drawing it means no more 9-slice seams at
// screen widths the export wasn't tiled for. The workspace badges
// stay as your exports/component — those are correct and already
// stretch/animate properly. Active Window, Media, Weather, and Clock
// are rebuilt on Pill.qml instead of the fixed-width raster pills,
// so they actually resize to fit real content (a real window title
// is rarely exactly as wide as "Workspace 1").
Item {
    id: status_Bar

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // Which modules to show, by name: { weather: false, ... }. Anything not
    // named is shown. Bar.qml fills it from the Settings Panel's Bar page
    // (services/SettingsService.qml); this file stays free of services.
    property var modules: ({})
    property var occupiedWorkspaces: []
    // Game Mode (fed by Bar.qml from GameModeService): a fixed bar with only the
    // date, the clock and the weather, whatever the modules above say. Written
    // as "only these three" rather than "hide the rest", so a module added later
    // stays out of Game Mode without anyone remembering to list it.
    property bool gameMode: false
    readonly property var gameModeModules: ["date", "clock", "weather"]

    function shows(name) {
        if (status_Bar.gameMode)
            return status_Bar.gameModeModules.indexOf(name) >= 0
        return status_Bar.modules[name] !== false
    }

    height: 61
    width: 1926 // design width from Figma; Bar.qml anchors this to the real screen width

    // True when the bar stands up on the left or right edge of the screen
    // (fed by Bar.qml, from BarPositionService.qml). Then every widget is
    // stacked in a column instead of a row: the LEFT zone becomes the top of
    // the column, the CENTER zone the middle and the RIGHT zone the bottom.
    // `barPosition` is which edge it's on ("top" / "bottom" / "left" / "right").
    property bool vertical: false
    property string barPosition: "top"

    // Layout alignment across the bar (the direction that isn't the bar's
    // length): centered up-and-down on a flat bar, left-and-right on a
    // standing one.
    readonly property int crossAlign: status_Bar.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
    // How far the non-badge widgets are lifted so they line up with the
    // badges (see otherWidgetsLift). Only a flat bar needs it.
    readonly property real liftY: status_Bar.vertical ? 0 : -status_Bar.otherWidgetsLift
    // Gap between stacked widgets on a standing bar. (Every pill has a 4px
    // hard shadow under it, so this reads as about 12 between the faces.)
    // (Capsule: the 4 px of shadow room under a pill plus this reads as the same 6 as between its dots.)
    readonly property real vGap: status_Bar.capsule ? mt.capGap - mt.shadowOffset : 8

    // A standing bar has a lot to stack. On a short screen (this is the
    // bar's own length, in design pixels, so it already accounts for the
    // monitor's scale) the least-needed buttons are left out so the
    // column still fits:
    //   tight:   the utility buttons become one tools key with a flyout (utilFlyout)
    //   tighter: CPU/RAM and the weather
    // The battery, the tray, the date and the clock are always there. Make
    // the shell size smaller on this monitor (Settings -> Bar -> Size) to
    // bring everything back.
    readonly property bool tightV: status_Bar.vertical && content.height < 1120
    readonly property bool tighterV: status_Bar.vertical && content.height < 880

    // The utility keys on a standing bar. Too short for the whole column (`tightV`) they
    // used to be left out; now the pill turns into one tools key that opens a flyout card
    // with all the keys (UtilPopup.qml, owned by Bar.qml). Set utilFlyoutAlways to use the
    // tools key on every standing bar, tall ones too.
    property bool utilFlyoutAlways: false
    readonly property bool utilFlyout: status_Bar.vertical && (status_Bar.tightV || status_Bar.utilFlyoutAlways)
    // Fed by Bar.qml: the flyout card is up (the tools key lights).
    property bool utilPopupOpen: false

    property int activeWorkspace: 1
    // How many workspace badges there are, 1-10 (fed by Bar.qml from the
    // `bar.workspaceCount` option).
    property int workspaceCount: 5

    // What a zone's modules take on a standing bar, the workspace badges left out,
    // with the gap between each and the badges. It goes by which modules are
    // switched on (`shows`) rather than by `visible`: a hidden zone makes all its
    // children report not visible, and the zone's own hiding depends on the badges
    // this sizes, so that would make the two chase each other. A module that is on
    // but not showing right now (no battery, nobody in a call) is counted anyway,
    // which only means the badges keep a little more room free.
    function othersHeight(zone) {
        let h = 0
        for (const id of (status_Bar.layout[zone] || [])) {
            if (id === "workspaces" || !status_Bar.shows(id))
                continue
            for (const it of status_Bar.itemsOf(id))
                h += Math.max(it.height, it.implicitHeight) + status_Bar.vGap
        }
        return h
    }

    // On a standing bar: how long the workspace column may be, i.e. what is left
    // of the bar's length after the other zones and the rest of its own zone
    // (WorkspaceBadges.maxLength). -1 on a flat bar. The 28 keeps a little over
    // the 24 the centre zone needs, so the zone does not drop itself.
    readonly property real badgesRoom: {
        if (!status_Bar.vertical)
            return -1
        const H = content.height
        const z = status_Bar.zoneMap["workspaces"]
        if (z === "left")
            return H - rightGroup.height - 28 - status_Bar.othersHeight("left")
        if (z === "right")
            return H - leftGroup.height - 28 - status_Bar.othersHeight("right")
        return H - leftGroup.height - rightGroup.height - 28 - status_Bar.othersHeight("center")
    }
    property string clockText: "00:00 AM"
    // "Mon, Sep 28" — fed by Bar.qml; the date pill sits left of the clock.
    property string dateText: ""
    property string windowApp: ""     // e.g. "Firefox" — first line
    property string windowTitle: ""   // e.g. the page/document title — second line
    property string windowIcon: ""    // the app's icon as a file url (standing bar's key); "" = none found

    // Media pill inputs, fed by Bar.qml (via MediaSource.qml).
    property bool mediaActive: false
    property bool mediaPlaying: false
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaArtUrl: ""
    // The media pill's little visualizer (MediaPill.qml): "none" | "dots" | "wave", and
    // cava's bands for it.
    property string mediaVisualizerStyle: "none"
    property var mediaPoints: []
    // From Bar.qml: does a left click open the media panel, and can this player
    // change its volume with the wheel?
    property bool mediaLeftOpensPanel: true
    property bool mediaVolumeAvailable: false

    // Tray toggle state, owned by Bar.qml (a live reflection, like the
    // active workspace) — TrayButton just shows it and asks to flip it.
    property bool trayOpen: false

    // False when there's nothing left for the dropdown to show (every
    // app is pinned, or none are running): the tray button goes away
    // until an app is unpinned. The pinned capsule stays, since that's
    // where you unpin from.
    property bool trayAvailable: true

    // The apps you've pinned to the bar (array of tray items). They sit
    // in a small capsule next to the tray button; empty hides it.
    property var trayPinned: []

    // The app whose right-click menu is open (its icon stays lifted), and
    // the one in the middle of being pinned / unpinned (its icon shrinks
    // away first). Both come from TrayPopups via Bar.qml.
    property var trayMenuItem: null
    property var trayLeavingItem: null
    // Some app in the dropdown is asking for attention (TraySource.unpinnedAttention).
    property bool trayAttention: false
    // The wheel over a pinned icon is sent to the app (Settings: Scroll on tray icons).
    property bool trayScrollEnabled: true

    // The tray button (the arrow cell of the pinned pill), so Bar.qml can
    // center the dropdown under it.
    readonly property Item trayToggle: pinnedTray.toggleItem

    // Same idea for the battery / resource popups (see Bar.qml).
    readonly property Item batteryToggle: batteryIndicator
    readonly property Item resourceToggle: resourceIndicator
    readonly property Item dateToggle: dateIndicator
    readonly property Item weatherToggle: weatherIndicator
    readonly property Item mediaToggle: media
    readonly property Item discordToggle: discordPill
    // The utility pill (what its flyout grows out of) and the UtilButtons the flyout's keys act on.
    readonly property Item utilToggle: utilKeys.toggleItem
    readonly property Item utilSource: utilKeys

    // Plugins' entries (PluginBarItem.qml), fed by Bar.qml: [{ key: "plugin:<id>", st }],
    // one per plugin with `bar` in its manifest, its PluginState as plain data. Where each
    // sits comes from `layout` like any module; whether it shows, from `modules`.
    property var pluginEntries: []
    // The key of the plugin whose popup is open ("" = none), from Bar.qml.
    property string pluginPopupOpen: ""
    // key -> its PluginBarItem, as the Instantiator below makes them.
    property var pluginItems: ({})

    // The entry a plugin's popup grows out of (Bar.qml), or null.
    function pluginToggle(key) {
        return status_Bar.pluginItems[key] ?? null
    }

    // This monitor's scale (1 = design size), fed by Bar.qml (the tray button
    // snaps its arrow to whole device pixels with it).
    property real scaleValue: 1

    // Where every module sits (BarLayoutService.qml, fed by Bar.qml):
    //   { left: [ids], center: [ids], right: [ids] }
    // in the order they run along the bar. Every module is named once; the
    // ids are the ones in BarLayoutService.modules. This is the default bar
    // (the same as BarLayoutService.defaults), until Bar.qml says otherwise.
    property var layout: ({
        left: ["activeWindow", "media", "tray"],
        center: ["status", "weather", "workspaces", "clock", "date"],
        right: ["utilButtons", "resources", "battery", "keyboardLayout", "privacy", "discord", "updates",
                "notifications"]
    })

    // module id -> its place in its zone, and module id -> its zone. The tray
    // used to be two items (the pinned capsule and a separate button, id +
    // "Button"); it is one pill now, and the spare slot is simply unused.
    readonly property var slotMap: {
        const m = ({})
        for (const z of ["left", "center", "right"]) {
            let i = 0
            for (const id of (status_Bar.layout[z] || [])) {
                m[id] = i++
                if (id === "tray")
                    m["trayButton"] = i++
            }
        }
        return m
    }
    readonly property var zoneMap: {
        const m = ({})
        for (const z of ["left", "center", "right"]) {
            for (const id of (status_Bar.layout[z] || [])) {
                m[id] = z
                if (id === "tray")
                    m["trayButton"] = z
            }
        }
        return m
    }

    function slotOf(key) {
        const v = status_Bar.slotMap[key]
        return v === undefined ? 0 : v
    }

    // The row/column of the zone the module lives in. (An item that was left
    // out of the layout by mistake lands at the end of the right zone.)
    function zoneItem(key) {
        const z = status_Bar.zoneMap[key]
        return z === "left" ? leftGroup : (z === "center" ? centerGroup : rightGroup)
    }

    // The gap between neighbours on a flat bar. The workspace badges spill
    // neighborShift (3px) past their layout box (the active badge zooms, the
    // rest shift out), so the gap you actually see next to them is the layout
    // gap minus that; the badges get that much extra margin back (see below),
    // and every zone uses the same 7.
    // (Capsule: a plain 6 between neighbours, the same as between its dots.)
    readonly property real zoneGap: status_Bar.capsule ? mt.capGap : 10 - badges.neighborShift

    // The bar's look (BarStyleService.qml, fed by Bar.qml):
    //   0 Float        rounded, outlined, inset from the screen edges
    //                  (Bar.qml insets this whole item by Theme.barFloatInset)
    //   1 Straight     no rounding, and the outline/ring are pushed past
    //                  both screen edges so only the top and bottom show
    //   2 Transparent  no bar background at all, just the pills
    //   3 Capsule      a slim fully rounded bar; the workspaces become ringed
    //                  dots and every other pill a flat chip (Pill.qml, MaterialIcon.qml
    //                  and WorkspaceBadges.qml redraw themselves, see Theme.capsuleFor).
    //                  On a standing bar the same bar is drawn upright, its chips stacked
    //                  (Theme.capVChip wide, see Pill.capsuleV).
    property int barStyle: 0

    // The Capsule style is up. `capsuleBar` is the name those widgets look for
    // up the tree (Theme.capsuleFor).
    readonly property bool capsule: status_Bar.barStyle === 3
    readonly property bool capsuleBar: status_Bar.capsule
    // ...standing on the left / right edge (Pill.capsuleV asks for this).
    readonly property bool capsuleVertical: status_Bar.capsule && status_Bar.vertical

    // CPU/RAM, fed by ResourceSource.qml via Bar.qml.
    property real cpuPercent: 0
    property real memPercent: 0

    // Battery, fed by BatterySource.qml via Bar.qml. batteryAvailable
    // is false on a desktop — BatteryIndicator then takes up no space.
    property bool batteryAvailable: false
    property int batteryPercentage: 0
    property bool batteryCharging: false
    property bool batteryLow: false

    // Keyboard layout code ("EN", "RU", ...), empty when there's only
    // one layout configured (see KeyboardLayoutService.code).
    property string keyboardLayoutCode: ""

    // Fed by WeatherSource.qml via Bar.qml. "--" until the first fetch
    // lands (or if curl/the network isn't available).
    property string weatherTemperature: "--"
    property string weatherIconName: "cloud"

    // Notifications: how many are waiting, and whether do-not-disturb
    // is on (fed from the Quick Panel's own state via Bar.qml).
    property int notificationCount: 0
    property bool notificationsMuted: false

    // Privacy (PrivacyService via Bar.qml): who has the microphone / the screen.
    property bool privacyMic: false
    property bool privacyAudio: false
    property bool privacyScreen: false
    property string privacyDetail: ""

    // Discord (DiscordVoiceService via Bar.qml): the voice call you are in.
    property bool discordInCall: false
    property bool discordNeedsAuth: false
    property bool discordAuthorizing: false
    property string discordChannel: ""
    property var discordParticipants: []
    property bool discordMuted: false
    property bool discordDeafened: false
    // A left click opens the Discord panel (Settings -> Bar), which Bar.qml owns.
    property bool discordLeftOpensPanel: true
    property bool discordPanelOpen: false

    // Status pill (StatusIconsService via Bar.qml): Wi-Fi / Bluetooth / speaker
    // as icons, with the details in a hover tag.
    property bool statusNetworkShown: false
    property string statusNetworkIcon: "wifi_off"
    property string statusNetworkState: "off"
    property bool statusBluetoothShown: false
    property string statusBluetoothIcon: "bluetooth_disabled"
    property string statusBluetoothState: "off"
    property bool statusSpeakerShown: false
    property string statusSpeakerIcon: "volume_off"
    property string statusSpeakerState: "off"
    property string statusDetail: ""

    // Pending package updates (PackageUpdatesService via Bar.qml).
    property int updatesCount: 0
    property bool updatesNudging: false
    property bool updatesShowZero: false
    property bool updatesBusy: false
    property bool updatesLoading: false
    property string updatesTip: ""

    // How wide the Active Window pill is allowed to grow before it
    // elides. Scales with the bar itself so it stays proportionate on a
    // small monitor, but never past `activeWindowCap` (design pixels): a long
    // window title (a browser tab, a terminal command) used to stretch it to
    // a fifth of the bar. Change the cap here to taste.
    readonly property real activeWindowCap: 260
    readonly property real maxActiveWindowWidth: Math.max(140, Math.min(status_Bar.activeWindowCap, status_Bar.width * 0.14))

    // Where the workspace badges actually sit, worked out from
    // WorkspaceBadges' own geometry: its wrapper is
    // activeSize+shadowOffset (46) tall and spans leftGroup's full
    // height (it's the tallest item there), so its top sits 23px
    // above bar-center. Inside that, the visible badge row is
    // idleSize+shadowOffset (40) tall and anchored bottomMargin (6)
    // up from the wrapper's bottom, landing it 3px above bar-center
    // overall. Active Window, Media, tray, Weather, and Clock are
    // otherwise dead-center by default, so lifting them by this same
    // amount lines them up with the badges. If WorkspaceBadges'
    // bottomMargin changes, update this to match: newOffset =
    // (activeSize + shadowOffset) / 2 - bottomMargin - (idleSize + shadowOffset) / 2.
    readonly property real otherWidgetsLift: status_Bar.capsule ? 0 : 3

    // The media pill can't yield to its neighbours, so it's the one that has
    // to stop growing: it may only take the room left over by the rest of the
    // bar. Which room that is depends on the zone it sits in (the layout is
    // the user's choice now):
    //   center   the wider of the two side clusters, mirrored across the
    //            middle (minus a 12px gap each side) and what else is in the
    //            center
    //   left     up to the center (or the right cluster, if the center is empty)
    //   right    the same, from the other end
    // Also capped at `mediaCap` (design pixels), so a long song or video title
    // elides instead of stretching the pill across the bar. Change it to taste.
    readonly property real mediaCap: 300
    readonly property real maxMediaWidth: {
        const z = status_Bar.zoneMap["media"]
        const half = content.width / 2
        let room
        if (z === "left") {
            room = content.width - rightGroup.width - 12 - status_Bar.othersWidth("left")
            if (centerGroup.width > 0)
                room = Math.min(room, half - centerGroup.width / 2 - 12 - status_Bar.othersWidth("left"))
        } else if (z === "right") {
            room = content.width - leftGroup.width - 12 - status_Bar.othersWidth("right")
            if (centerGroup.width > 0)
                room = Math.min(room, half - centerGroup.width / 2 - 12 - status_Bar.othersWidth("right"))
        } else {
            room = 2 * (Math.min(half - leftGroup.width, half - rightGroup.width) - 12)
                - status_Bar.othersWidth("center")
        }
        return Math.min(status_Bar.mediaCap, Math.max(0, room))
    }

    // The items that make up a module (the tray is two).
    function itemsOf(id) {
        switch (id) {
        case "workspaces": return [badges]
        case "activeWindow": return [activeWindow]
        case "media": return [mediaSlot]
        case "privacy": return [privacyIndicator]
        case "discord": return [discordPill]
        case "updates": return [updatesBadge]
        case "utilButtons": return [utilKeys]
        case "resources": return [resourceIndicator]
        case "status": return [statusPill]
        case "battery": return [batteryIndicator]
        case "keyboardLayout": return [kbLayoutIndicator]
        case "notifications": return [notificationBell]
        case "tray": return [pinnedTray]
        case "weather": return [weatherIndicator]
        case "date": return [dateIndicator]
        case "clock": return [clockButton]
        }
        const p = status_Bar.pluginItems[id]
        return p ? [p] : []
    }

    // How wide an item is as the layout sees it. (The layout's own result is
    // not read back: it would depend on the media pill, which is asking.)
    function slotWidth(it) {
        if (it === pinnedTray)
            return pinnedTray.shownWidth
        // These two grow in and shrink away too.
        if (it === privacyIndicator || it === updatesBadge || it === discordPill)
            return it.implicitWidth * it.reveal
        return it.implicitWidth
    }

    // How much room everything in a zone except the media pill takes, each
    // with the gap between it and the pill.
    function othersWidth(zone) {
        let w = 0
        for (const id of (status_Bar.layout[zone] || [])) {
            if (id === "media")
                continue
            for (const it of status_Bar.itemsOf(id)) {
                if (it.visible)
                    w += status_Bar.slotWidth(it) + status_Bar.zoneGap
            }
        }
        return w
    }

    signal workspaceRequested(int workspace)
    signal mediaToggleRequested()
    signal mediaNextRequested()
    signal mediaPreviousRequested()
    signal mediaPanelRequested()
    signal mediaScrolled(int direction)
    signal trayToggleRequested()
    // A click on a pinned icon: the item, which mouse button, and the
    // icon itself (so a menu can open right under it).
    signal trayItemClicked(var item, int button, Item icon)
    // The wheel over a pinned icon: item, delta, sideways?
    signal trayItemScrolled(var item, real delta, bool horizontal)
    // New bar widgets.
    signal resourcesClicked()
    signal batteryClicked()
    signal utilClicked()
    signal statusClicked()
    signal keyboardLayoutClicked()
    // The date pill was clicked: open / close the calendar dropdown.
    signal dateClicked()
    signal weatherClicked()
    signal wallpapersToggleRequested()
    // Notification bell clicked: opens the Quick Panel.
    signal notificationsToggleRequested()
    // The updates badge: run the update / look again.
    signal updatesClicked()
    signal updatesRefreshRequested()
    // The Discord pill: mute / deafen yourself, or link Discord (first time).
    signal discordMuteRequested()
    signal discordDeafenRequested()
    signal discordAuthorizeRequested()
    signal discordPanelRequested()
    // A plugin's entry was clicked (the left button): open or close its popup.
    signal pluginClicked(string key)

    // The pale ring between the navy outline and the white fill —
    // sampled straight from the old status_Bar_BG.png export (it's
    // #d9d9d9 there too, the same gray QuickPanelFace's scrollbars use).
    // Values now live on Theme (colOuterRing/outerRingWidth) so Dock.qml
    // can match this exact look; kept as local aliases here so nothing
    // else in this file has to change.
    readonly property color bgRingColor: mt.surfaceRing
    readonly property real bgRingWidth: mt.outerRingWidth

    // Corner radius and how far the background reaches past the left and
    // right edges, per style. Both glide between styles instead of
    // snapping. Straight: radius 0, and the background is pushed out by
    // outline + ring (+1 so no seam shows) so the side outline and ring
    // land off screen and only the top and bottom edges are seen.
    property real bgRadius: status_Bar.barStyle === 0 ? mt.radiusOuter : 0
    property real bgBleed: status_Bar.barStyle === 1
        ? mt.borderWidth + status_Bar.bgRingWidth + 1 : 0

    Behavior on bgRadius {
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }
    Behavior on bgBleed {
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    // The whole bar background (shadow + face + fill) as one layer, so
    // Transparent can fade it out and leave only the pills.
    Item {
        id: bgLayer
        anchors.fill: parent
        opacity: (status_Bar.barStyle === 2 || status_Bar.capsule) ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }

        // Fixed hard shadow, same idea as Pill.qml's: a flat navy copy of
        // the bar's shape, offset straight down by Theme.shadowOffset and
        // peeking out from beneath the face.
        Rectangle {
            id: bgShadow
            anchors.fill: parent
            anchors.topMargin: mt.shadowOffset - (status_Bar.vertical ? status_Bar.bgBleed : 0)
            anchors.bottomMargin: status_Bar.vertical ? -status_Bar.bgBleed : 0
            anchors.leftMargin: status_Bar.vertical ? 0 : -status_Bar.bgBleed
            anchors.rightMargin: status_Bar.vertical ? 0 : -status_Bar.bgBleed
            radius: status_Bar.bgRadius
            color: mt.lineShadow
        }

        // The face: navy outline, then the pale ring, then white fill —
        // same structure Pill.qml uses for every pill in the bar, just
        // static (the bar itself doesn't press).
        Rectangle {
            id: bgFace
            anchors.fill: parent
            anchors.topMargin: status_Bar.vertical ? -status_Bar.bgBleed : 0
            anchors.bottomMargin: mt.shadowOffset - (status_Bar.vertical ? status_Bar.bgBleed : 0)
            anchors.leftMargin: status_Bar.vertical ? 0 : -status_Bar.bgBleed
            anchors.rightMargin: status_Bar.vertical ? 0 : -status_Bar.bgBleed
            radius: status_Bar.bgRadius
            color: status_Bar.bgRingColor
            border.width: mt.borderWidth
            border.color: mt.line
        }

        Rectangle {
            id: bgFill
            anchors.fill: bgFace
            anchors.margins: mt.borderWidth + status_Bar.bgRingWidth
            radius: Math.max(0, status_Bar.bgRadius - mt.borderWidth - status_Bar.bgRingWidth)
            color: mt.surface
        }
    }

    // The Capsule bar: a fully rounded body in a 3 px rim, over a hard shadow
    // 3 px below it. All three colours come from the theme (Theme.capBody / capRim /
    // capShade). The rim is a plain Rectangle under the body, not a border, so the two
    // curves stay concentric.
    Item {
        id: capsuleLayer
        anchors.fill: parent
        opacity: status_Bar.capsule ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }

        Rectangle {
            x: 0
            y: mt.capShadowDy
            width: parent.width
            height: parent.height - mt.capShadowDy
            radius: Math.min(width, height) / 2
            color: mt.capShade
            antialiasing: true
        }

        Rectangle {
            id: capFace
            width: parent.width
            height: parent.height - mt.capShadowDy
            radius: Math.min(width, height) / 2
            color: mt.capRim
            antialiasing: true
        }

        Rectangle {
            anchors.fill: capFace
            anchors.margins: mt.capRimWidth
            radius: Math.min(width, height) / 2
            color: mt.capBody
            antialiasing: true
        }
    }

    Item {
        id: content
        anchors.fill: parent
        // Theme.barFloatInset: the gap outside the workspaces. The Float
        // bar is inset from the screen by this same amount.
        // Capsule: the rim plus 7 each side, and the shadow's 3 px off the bottom so the
        // pills centre on the rimmed bar, not on bar + shadow.
        anchors.leftMargin: status_Bar.vertical ? 0
            : (status_Bar.capsule ? mt.capRimWidth + mt.capPadX : mt.barFloatInset)
        anchors.rightMargin: status_Bar.vertical ? 0
            : (status_Bar.capsule ? mt.capRimWidth + mt.capPadX : mt.barFloatInset)
        anchors.topMargin: status_Bar.vertical
            ? (status_Bar.capsule ? mt.capRimWidth + mt.capVPadY : mt.barFloatInset) : 0
        // (Capsule, standing: the last pill brings 4 px of shadow room of its own, the bar's shadow is
        // 3, so the margin is one less than the top's.)
        anchors.bottomMargin: status_Bar.vertical
            ? (status_Bar.capsule ? mt.capRimWidth + mt.capVPadY - 1 : mt.barFloatInset)
            : (status_Bar.capsule ? mt.capShadowDy : 0)

        // ===== the three zones =====

        GridLayout {
            id: leftGroup
            anchors.left: status_Bar.vertical ? undefined : parent.left
            anchors.top: status_Bar.vertical ? parent.top : undefined
            anchors.verticalCenter: status_Bar.vertical ? undefined : parent.verticalCenter
            anchors.horizontalCenter: status_Bar.vertical ? parent.horizontalCenter : undefined
            columns: status_Bar.vertical ? 1 : 100
            columnSpacing: status_Bar.zoneGap
            rowSpacing: status_Bar.vertical ? status_Bar.vGap : status_Bar.zoneGap
        }

        // Fixed dead-center on the bar, so it can't drift when the left or
        // right zone changes width. On a standing bar it sits between the two
        // zones, so it steps aside when they leave no room for it.
        GridLayout {
            id: centerGroup
            anchors.centerIn: parent
            visible: !status_Bar.vertical
                || content.height > leftGroup.height + rightGroup.height + centerGroup.implicitHeight + 24
            columns: status_Bar.vertical ? 1 : 100
            columnSpacing: status_Bar.zoneGap
            rowSpacing: status_Bar.vertical ? status_Bar.vGap : status_Bar.zoneGap
        }

        GridLayout {
            id: rightGroup
            anchors.right: status_Bar.vertical ? undefined : parent.right
            anchors.bottom: status_Bar.vertical ? parent.bottom : undefined
            anchors.verticalCenter: status_Bar.vertical ? undefined : parent.verticalCenter
            anchors.horizontalCenter: status_Bar.vertical ? parent.horizontalCenter : undefined
            columns: status_Bar.vertical ? 1 : 100
            columnSpacing: status_Bar.zoneGap
            rowSpacing: status_Bar.vertical ? status_Bar.vGap : status_Bar.zoneGap
        }

        // ===== the modules =====
        WorkspaceBadges {
            id: badges
            parent: status_Bar.zoneItem("workspaces")
            visible: status_Bar.shows("workspaces")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("workspaces") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("workspaces")
            Layout.alignment: status_Bar.crossAlign
            Layout.rightMargin: status_Bar.vertical ? 0 : badges.neighborShift
            vertical: status_Bar.vertical
            active: status_Bar.activeWorkspace
            count: status_Bar.workspaceCount
            maxLength: status_Bar.badgesRoom
            onRequested: workspace => status_Bar.workspaceRequested(workspace)
            occupied: status_Bar.occupiedWorkspaces
            // "Scroll to change workspace".
            ScrollHint {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.rightMargin: -2
                glyph: "unfold_more"
                // (Not on the Capsule bar: the dots are too small to carry it.)
                active: !status_Bar.capsule
            }
        }

        // Active Window: app name on top (bold), window title under
        // it (lighter) — same two-line treatment and text sizes as
        // the media pill. Ring is 5px like the media pill's rather
        // than the usual 8, since two lines don't fit in the
        // 20px-tall fill an 8px ring leaves.
        Pill {
            id: activeWindow
            parent: status_Bar.zoneItem("activeWindow")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("activeWindow") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("activeWindow")
            // Two lines of text do not fit beside a screen edge: a standing
            // bar shows ActiveWindowKey (just below) instead.
            visible: !status_Bar.vertical && status_Bar.shows("activeWindow")
            Layout.alignment: status_Bar.crossAlign
            cornerRadius: mt.radiusBadge
            ringWidth: 5

            // Nothing focused on this bar's workspace (empty
            // workspace, or the globally active window lives on
            // a different monitor/workspace) -> no app, no title,
            // and the pill just names the workspace.
            readonly property bool hasWindow: status_Bar.windowApp !== "" || status_Bar.windowTitle !== ""

            // First line: the app; if we couldn't work out the app,
            // the title takes its place.
            readonly property string line1: !hasWindow
                ? "Workspace " + status_Bar.activeWorkspace
                : (status_Bar.windowApp !== "" ? status_Bar.windowApp : status_Bar.windowTitle)

            // Second line: the title, unless it would just repeat
            // line 1 (terminals often title themselves after the app).
            readonly property string line2: (hasWindow
                && status_Bar.windowApp !== ""
                && status_Bar.windowTitle !== ""
                && status_Bar.windowTitle.toLowerCase() !== status_Bar.windowApp.toLowerCase())
                ? status_Bar.windowTitle : ""

            // Capped so a long window title elides instead of
            // growing the pill without bound.
            implicitWidth: Math.min(status_Bar.maxActiveWindowWidth,
                Math.max(status_Bar.capsule ? 80 : 140,
                    Math.max(awLine1.implicitWidth, awLine2.visible ? awLine2.implicitWidth : 0) + (status_Bar.capsule ? 20 : 30)))
            transform: Translate { y: status_Bar.liftY }
            fillGradient: Gradient {
                GradientStop { position: 0.0; color: mt.accentMint }
                GradientStop { position: 1.0; color: mt.accentCyan }
            }

            Behavior on implicitWidth {
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
            }

            // Each line has a box of its own with a fixed line height. A title
            // with a symbol, emoji or CJK in it (a Discord channel, a browser
            // tab) is drawn with a fallback font whose lines are taller, which
            // used to make that line taller, so the Column grew and the centred
            // block slid up (the app name against the top edge) and the title
            // dropped. With fixed boxes the two lines stay put, whatever the
            // title holds, and a long one is cut with "...".
            Column {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 1

                Text {
                    id: awLine1
                    width: parent.width
                    height: lineHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    textFormat: Text.PlainText
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.25)
                    text: activeWindow.line1.replace(/\s+/g, " ")
                    color: status_Bar.capsule ? mt.capInk : mt.colBorder
                    font.family: mt.fontFamily
                    font.pixelSize: status_Bar.capsule ? mt.fontSizeInfo
                        : (activeWindow.hasWindow ? mt.fontSizeTitle : mt.fontSizeIdle)
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Text {
                    id: awLine2
                    width: parent.width
                    height: lineHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    textFormat: Text.PlainText
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.25)
                    // (Capsule: one line, the app; the title is in the media / window popups.)
                    visible: activeWindow.line2 !== "" && !status_Bar.capsule
                    text: activeWindow.line2.replace(/\s+/g, " ")
                    color: mt.colSubText
                    font.family: mt.fontFamily
                    font.pixelSize: mt.fontSizeSub
                    font.weight: Font.Medium
                }
            }
        }

        // Active Window on a standing bar: a square key with the app's icon,
        // the full name and title in its hover tag (ActiveWindowKey.qml).
        ActiveWindowKey {
            id: activeWindowKey
            parent: status_Bar.zoneItem("activeWindow")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("activeWindow") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("activeWindow")
            Layout.alignment: status_Bar.crossAlign
            visible: status_Bar.vertical && status_Bar.shows("activeWindow")
            hasWindow: activeWindow.hasWindow
            app: status_Bar.windowApp !== "" ? status_Bar.windowApp : status_Bar.windowTitle
            title: status_Bar.windowApp !== "" ? status_Bar.windowTitle : ""
            icon: status_Bar.windowIcon
            workspace: status_Bar.activeWorkspace
            barPosition: status_Bar.barPosition
        }

        // Media pill. It sizes itself (width follows the text, between
        // minWidth and maxWidth), which a layout would override, so a plain
        // Item stands in for it as the layout's child and follows its width.
        // It grows and shrinks to fit its text without moving the zone's
        // other end.
        Item {
            id: mediaSlot
            parent: status_Bar.zoneItem("media")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("media") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("media")
            Layout.alignment: status_Bar.crossAlign
            visible: status_Bar.shows("media")
            implicitWidth: media.width
            implicitHeight: media.implicitHeight
            transform: Translate { y: status_Bar.liftY }

            MediaPill {
                id: media
                vertical: status_Bar.vertical
                active: status_Bar.mediaActive
                playing: status_Bar.mediaPlaying
                title: status_Bar.mediaTitle
                artist: status_Bar.mediaArtist
                artUrl: status_Bar.mediaArtUrl
                visualizerStyle: status_Bar.mediaVisualizerStyle
                points: status_Bar.mediaPoints

                maxWidth: status_Bar.maxMediaWidth
                minWidth: Math.min(220, status_Bar.maxMediaWidth)

                leftOpensPanel: status_Bar.mediaLeftOpensPanel
                volumeAvailable: status_Bar.mediaVolumeAvailable
                onToggleRequested: status_Bar.mediaToggleRequested()
                onNextRequested: status_Bar.mediaNextRequested()
                onPreviousRequested: status_Bar.mediaPreviousRequested()
                onPanelRequested: status_Bar.mediaPanelRequested()
                onScrolled: direction => status_Bar.mediaScrolled(direction)
            }
        }

        // Mic live / screen shared: icons only, the details are in its hover
        // tag. Takes no room (and is not even visible) while nothing is in use.
        PrivacyIndicator {
            id: privacyIndicator
            parent: status_Bar.zoneItem("privacy")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("privacy") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("privacy")
            Layout.alignment: status_Bar.crossAlign
            // The slot opens and closes with `reveal` (the same as the tray
            // button's) and takes the gap back as it closes.
            Layout.preferredWidth: status_Bar.vertical ? privacyIndicator.implicitWidth : privacyIndicator.implicitWidth * privacyIndicator.reveal
            Layout.preferredHeight: status_Bar.vertical ? privacyIndicator.implicitHeight * privacyIndicator.reveal : -1
            Layout.leftMargin: status_Bar.vertical ? 0 : -status_Bar.zoneGap * (1 - privacyIndicator.reveal)
            Layout.topMargin: status_Bar.vertical ? -status_Bar.vGap * (1 - privacyIndicator.reveal) : 0
            transform: Translate { y: status_Bar.liftY }
            // (`visible` is the indicator's own: live, or still shrinking away.)
            vertical: status_Bar.vertical
            barPosition: status_Bar.barPosition
            micLive: status_Bar.privacyMic && status_Bar.shows("privacy")
            audioLive: status_Bar.privacyAudio && status_Bar.shows("privacy")
            screenLive: status_Bar.privacyScreen && status_Bar.shows("privacy")
            detailText: status_Bar.privacyDetail
        }

        // In a Discord voice channel: who is in the call, mute / deafen. Takes
        // no room (and is not even visible) while there is no call.
        DiscordPill {
            id: discordPill
            parent: status_Bar.zoneItem("discord")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("discord") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("discord")
            Layout.alignment: status_Bar.crossAlign
            // The slot opens and closes with `reveal`, like the privacy pill's.
            Layout.preferredWidth: status_Bar.vertical ? discordPill.implicitWidth : discordPill.implicitWidth * discordPill.reveal
            Layout.preferredHeight: status_Bar.vertical ? discordPill.implicitHeight * discordPill.reveal : -1
            Layout.leftMargin: status_Bar.vertical ? 0 : -status_Bar.zoneGap * (1 - discordPill.reveal)
            Layout.topMargin: status_Bar.vertical ? -status_Bar.vGap * (1 - discordPill.reveal) : 0
            transform: Translate { y: status_Bar.liftY }
            vertical: status_Bar.vertical
            barPosition: status_Bar.barPosition
            allowed: status_Bar.shows("discord")
            inCall: status_Bar.discordInCall
            needsAuth: status_Bar.discordNeedsAuth
            authorizing: status_Bar.discordAuthorizing
            channelName: status_Bar.discordChannel
            participants: status_Bar.discordParticipants
            muted: status_Bar.discordMuted
            deafened: status_Bar.discordDeafened
            leftOpensPanel: status_Bar.discordLeftOpensPanel
            panelOpen: status_Bar.discordPanelOpen
            onMuteRequested: status_Bar.discordMuteRequested()
            onDeafenRequested: status_Bar.discordDeafenRequested()
            onAuthorizeRequested: status_Bar.discordAuthorizeRequested()
            onPanelRequested: status_Bar.discordPanelRequested()
        }

        // Pending package updates: a badge with the count.
        UpdatesBadge {
            id: updatesBadge
            parent: status_Bar.zoneItem("updates")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("updates") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("updates")
            Layout.alignment: status_Bar.crossAlign
            // Same as the privacy pill: the slot opens and closes with `reveal`.
            Layout.preferredWidth: status_Bar.vertical ? updatesBadge.implicitWidth : updatesBadge.implicitWidth * updatesBadge.reveal
            Layout.preferredHeight: status_Bar.vertical ? updatesBadge.implicitHeight * updatesBadge.reveal : -1
            Layout.leftMargin: status_Bar.vertical ? 0 : -status_Bar.zoneGap * (1 - updatesBadge.reveal)
            Layout.topMargin: status_Bar.vertical ? -status_Bar.vGap * (1 - updatesBadge.reveal) : 0
            transform: Translate { y: status_Bar.liftY }
            barPosition: status_Bar.barPosition
            count: status_Bar.updatesCount
            nudging: status_Bar.updatesNudging
            showZero: status_Bar.updatesShowZero
            busy: status_Bar.updatesBusy
            loading: status_Bar.updatesLoading
            tipText: status_Bar.updatesTip
            // (A module that is switched off takes no room: `allowed`, and the
            // badge's own `visible` follows its `reveal`.)
            allowed: status_Bar.shows("updates")
            onClicked: status_Bar.updatesClicked()
            onRefreshRequested: status_Bar.updatesRefreshRequested()
        }

        UtilButtons {
            id: utilKeys
            parent: status_Bar.zoneItem("utilButtons")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("utilButtons") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("utilButtons")
            visible: status_Bar.shows("utilButtons")
            vertical: status_Bar.vertical
            compact: status_Bar.utilFlyout
            popupOpen: status_Bar.utilPopupOpen
            barPosition: status_Bar.barPosition
            onToggleRequested: status_Bar.utilClicked()
            Layout.alignment: status_Bar.crossAlign
            onWallpapersRequested: status_Bar.wallpapersToggleRequested()
            transform: Translate { y: status_Bar.liftY }
        }

        ResourceIndicator {
            id: resourceIndicator
            parent: status_Bar.zoneItem("resources")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("resources") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("resources")
            visible: !status_Bar.tighterV && status_Bar.shows("resources")
            vertical: status_Bar.vertical
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            cpuPercent: status_Bar.cpuPercent
            memPercent: status_Bar.memPercent
            barPosition: status_Bar.barPosition
            onClicked: status_Bar.resourcesClicked()
        }

        // Wi-Fi / Bluetooth / speaker, icons only; the details are in the hover
        // tag. (Hides itself when none of the three has anything to show.)
        StatusPill {
            id: statusPill
            parent: status_Bar.zoneItem("status")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("status") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("status")
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            vertical: status_Bar.vertical
            barPosition: status_Bar.barPosition
            networkShown: status_Bar.statusNetworkShown && status_Bar.shows("status")
            networkIcon: status_Bar.statusNetworkIcon
            networkState: status_Bar.statusNetworkState
            bluetoothShown: status_Bar.statusBluetoothShown && status_Bar.shows("status")
            bluetoothIcon: status_Bar.statusBluetoothIcon
            bluetoothState: status_Bar.statusBluetoothState
            speakerShown: status_Bar.statusSpeakerShown && status_Bar.shows("status")
            speakerIcon: status_Bar.statusSpeakerIcon
            speakerState: status_Bar.statusSpeakerState
            detailText: status_Bar.statusDetail
            onClicked: status_Bar.statusClicked()
        }

        BatteryIndicator {
            id: batteryIndicator
            parent: status_Bar.zoneItem("battery")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("battery") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("battery")
            // (BatteryIndicator hides itself with no battery; setting
            // `visible` here replaces that, so it is repeated.)
            visible: available && status_Bar.shows("battery")
            vertical: status_Bar.vertical
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            available: status_Bar.batteryAvailable
            percentage: status_Bar.batteryPercentage
            isCharging: status_Bar.batteryCharging
            isLow: status_Bar.batteryLow
            barPosition: status_Bar.barPosition
            onClicked: status_Bar.batteryClicked()
        }

        KeyboardLayoutIndicator {
            id: kbLayoutIndicator
            parent: status_Bar.zoneItem("keyboardLayout")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("keyboardLayout") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("keyboardLayout")
            // (Hides itself with nothing to show; repeated, see battery.)
            visible: layoutCode !== "" && status_Bar.shows("keyboardLayout")
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            layoutCode: status_Bar.keyboardLayoutCode
            barPosition: status_Bar.barPosition
            onClicked: status_Bar.keyboardLayoutClicked()
        }

        NotificationBadge {
            id: notificationBell
            parent: status_Bar.zoneItem("notifications")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("notifications") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("notifications")
            visible: status_Bar.shows("notifications")
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            count: status_Bar.notificationCount
            doNotDisturb: status_Bar.notificationsMuted
            barPosition: status_Bar.barPosition
            onClicked: status_Bar.notificationsToggleRequested()
        }

        // The tray pill, at the bar's 36px pill height: the pinned apps
        // and, as its last cell, the arrow button that opens the
        // dropdown. Pinning an app pops its icon into this one pill.
        //
        // Its slot is sized by shownWidth (a quick glide), and the
        // negative left margin takes back the layout's gap around it
        // at the same pace, so the neighbours follow instead of
        // jumping.
        TrayCollection {
            id: pinnedTray
            parent: status_Bar.zoneItem("tray")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("tray") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("tray")
            Layout.alignment: status_Bar.crossAlign
            // Flat bar: it grows along the bar's length, which is its
            // width. Standing bar: its height. (-1 = leave it alone.)
            Layout.preferredWidth: status_Bar.vertical ? pinnedTray.fullWidth : pinnedTray.shownWidth
            Layout.preferredHeight: status_Bar.vertical ? pinnedTray.shownHeight : -1
            Layout.leftMargin: status_Bar.vertical ? 0 : -status_Bar.zoneGap * (1 - pinnedTray.reveal)
            Layout.topMargin: status_Bar.vertical ? -status_Bar.vGap * (1 - pinnedTray.reveal) : 0
            transform: Translate { y: status_Bar.liftY }

            compact: true
            vertical: status_Bar.vertical
            // One pill: the pinned apps plus the dropdown's arrow button.
            // It's there while there is either something pinned or
            // something for the dropdown to show.
            showToggle: status_Bar.trayAvailable
            toggleOpen: status_Bar.trayOpen
            toggleAttention: status_Bar.trayAttention
            glyphRotation: !status_Bar.vertical ? 0 : (status_Bar.barPosition === "left" ? -90 : 90)
            texel: status_Bar.scaleValue * Screen.devicePixelRatio
            onToggleRequested: status_Bar.trayToggleRequested()
            present: count > 0 || showToggle
            visible: (present || shownWidth > 0.5 || shownHeight > 0.5) && status_Bar.shows("tray")
            model: status_Bar.trayPinned
            activeItem: status_Bar.trayMenuItem
            leavingItem: status_Bar.trayLeavingItem
            onItemClicked: (item, button, icon) => status_Bar.trayItemClicked(item, button, icon)
            onItemScrolled: (item, delta, horizontal) => status_Bar.trayItemScrolled(item, delta, horizontal)
            scrollEnabled: status_Bar.trayScrollEnabled
        }

        // Conditions icon + temperature; click opens the weather
        // dropdown (WeatherPopup.qml, hung off this by Bar.qml).
        WeatherIndicator {
            id: weatherIndicator
            parent: status_Bar.zoneItem("weather")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("weather") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("weather")
            visible: !status_Bar.tighterV && status_Bar.shows("weather")
            vertical: status_Bar.vertical
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            text: status_Bar.weatherTemperature
            iconName: status_Bar.weatherIconName
            barPosition: status_Bar.barPosition
            onClicked: status_Bar.weatherClicked()
        }

        // The plugins' entries: one per plugin with a bar entry, each placed in its zone and
        // slot like the pills above. (An Instantiator, not a Repeater: each entry is parented
        // to its own zone, which a Repeater's delegates must not be.)
        Instantiator {
            model: status_Bar.pluginEntries

            delegate: PluginBarItem {
                required property var modelData
                key: modelData.key
                st: modelData.st
                parent: status_Bar.zoneItem(modelData.key)
                Layout.row: status_Bar.vertical ? status_Bar.slotOf(modelData.key) : 0
                Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf(modelData.key)
                Layout.alignment: status_Bar.crossAlign
                transform: Translate { y: status_Bar.liftY }
                enabledHere: status_Bar.shows(modelData.key) && !status_Bar.tighterV
                vertical: status_Bar.vertical
                barPosition: status_Bar.barPosition
                popupOpen: status_Bar.pluginPopupOpen === modelData.key
                onClicked: status_Bar.pluginClicked(modelData.key)
            }

            onObjectAdded: (index, object) => {
                const m = Object.assign({}, status_Bar.pluginItems)
                m[object.key] = object
                status_Bar.pluginItems = m
            }

            onObjectRemoved: (index, object) => {
                const m = Object.assign({}, status_Bar.pluginItems)
                if (m[object.key] === object)
                    delete m[object.key]
                status_Bar.pluginItems = m
            }
        }

        // Today's date; click opens the calendar dropdown
        // (CalendarPopup.qml, hung off this by Bar.qml).
        DateIndicator {
            id: dateIndicator
            parent: status_Bar.zoneItem("date")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("date") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("date")
            visible: status_Bar.shows("date")
            vertical: status_Bar.vertical
            Layout.alignment: status_Bar.crossAlign
            transform: Translate { y: status_Bar.liftY }
            text: status_Bar.dateText
            barPosition: status_Bar.barPosition
            onClicked: status_Bar.dateClicked()
        }

        // The clock: display only. It used to open the Quick Panel,
        // but the notification bell does that now, so it has no
        // click, press effect or pointer cursor.
        Item {
            id: clockButton
            parent: status_Bar.zoneItem("clock")
            Layout.row: status_Bar.vertical ? status_Bar.slotOf("clock") : 0
            Layout.column: status_Bar.vertical ? 0 : status_Bar.slotOf("clock")
            visible: status_Bar.shows("clock")
            Layout.alignment: status_Bar.crossAlign
            implicitWidth: clockPill.implicitWidth
            implicitHeight: clockPill.implicitHeight
            transform: Translate { y: status_Bar.liftY }

            Pill {
                id: clockPill
                anchors.fill: parent
                cornerRadius: mt.radiusBadge
                fillColor: mt.chipFill
                ringWidth: 6   // the bar's pills all share the Utility pill's ring
                // Standing bar: "09:05" over "PM", so it's two lines tall.
                implicitWidth: status_Bar.vertical ? clockPill.barVWidth : cLabel.implicitWidth + (status_Bar.capsule ? 20 : 28)
                implicitHeight: status_Bar.vertical ? clockColumn.implicitHeight + (clockPill.capsule ? 16 : 24) : mt.pillHeight + mt.shadowOffset

                Column {
                    id: clockColumn
                    visible: status_Bar.vertical
                    anchors.centerIn: parent

                    Repeater {
                        model: status_Bar.clockText.split(" ")
                        Text {
                            required property string modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            color: mt.chipInk
                            font.family: mt.fontFamily
                            font.pixelSize: mt.fontSizeInfo
                            font.weight: Font.ExtraBold
                            font.styleName: mt.fontStyleBold
                        }
                    }
                }

                Text {
                    id: cLabel
                    visible: !status_Bar.vertical
                    anchors.centerIn: parent
                    text: status_Bar.clockText
                    color: mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: status_Bar.capsule ? mt.capClockSize : mt.fontSizeInfo
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }
            }
        }
    }
}
