import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.services
import "../../common/functions/PhoneMath.js" as PM
import "../../common/functions/FlipMath.js" as FM
import "PhoneRoute.js" as PR
import qs.modules.common
import qs.modules.sekai.launcher
import qs.modules.sekai.phone
import qs.modules.sekai.settings

// The Quick Panel: a phone-shaped panel (PhoneBody.qml around
// QuickPanelFace.qml) that comes up from the bottom-center of the screen,
// like a phone being pulled out of a pocket, and stays there with its
// lower part still below the screen edge (see `peek`).
//
// Like Bar.qml, this is one of the files that talks to the system. The
// two files it's built from stay pure UI; this feeds QuickPanelFace what
// QuickSource.qml knows and turns its signals into actions.
//
// Ways to open it:
//   - a keybind, e.g. SUPER + N — bind it to the command
//         qs -c sekaipop ipc call quickpanel toggle
//     (also `show` and `hide`); pressing it again closes the panel
//   - push the mouse into the bottom-center of the screen (the hot edge).
//     With "Peek first" on (panel.hotPeek) the hot edge only raises the tip of
//     the phone (the clock and date, see peekUp); a click on it brings the
//     whole phone up, and moving the mouse off it lets it drop again.
//   - click the notification bell in the bar (Bar.qml -> toggleOn)
//
// Ways to close it (however it was opened):
//   - click anywhere outside it (same as the tray dropdown)
//   - or press the keybind again
// Moving the mouse away does NOT close it.
//
// It opens on the monitor you pointed at (the focused one for the
// keybind), scaled down to fit that monitor's height.
//
// It's also the notification alert (there's no separate popup): when
// something arrives (and do-not-disturb is off, or it's critical) the
// phone comes up on the focused monitor if it isn't already, buzzes, and
// drops the new notification in as a card at the top of its screen for a
// few seconds (see NotificationSource.qml / QuickPanelFace's heads-up).
// It only rises as far as that card (just the top of the phone shows, see
// alertLift), not the whole `peek`, and it doesn't grab the keyboard or
// the pointer; it goes back down by itself. Click it (or the keybind / hot
// edge) and it slides up to the full panel and stays open like normal.
// Swipe it down or middle-click it and it goes back down at once (the
// notification stays in the list); right-click it and the notification is
// removed too. The same buttons as the corner popup cards (notify.style
// "popups"): middle hides, right removes. Anywhere on the phone, not just
// its card.
//
// The gear on the header turns the phone into the Settings (SettingsStage.qml)
// instead of opening another panel: the phone rolls a quarter turn
// anticlockwise, rises to the middle of the monitor, and its screen dissolves
// into the Settings', keeping the same body (see FlipMath.js). The Settings' X
// (or Escape on their menu) turns it back. The Settings also come up on their
// own, with no Quick Panel to turn out of:
//     qs -c sekaipop ipc call settings toggle   (also `show`, `hide`, and
//     `page <quick|general|bar|desktop|hyprland|about>`)
// Everything lives in this one window: its size is worked out once, up front,
// to hold the whole turn (see `flipRoom`), because a window that is resized
// while it animates stutters.
//
// This is also the ONE phone's front door (Concept D, "Phone + Stage"):
//   - Quick is the first screen. Apps (LauncherFace.qml) is a second screen of the
//     same body: the grid button on the header, typing a letter, or Super+A bring
//     it in (a short vertical slide, no new pose). Settings keep their turn.
//   - Back undoes the steps you took and never invents one (PhoneRoute.js): Escape
//     or the Back chip goes back one screen; at the screen the phone was opened on
//     it closes. Ctrl+1..4 jump (1 Quick, 2 Apps, 3 Wallpapers, 4 Settings).
//   - one IPC target for all of it:  qs -c sekaipop ipc call phone toggle | show | hide
//     | go <quick|apps|wallpapers|settings> | back | home
//     (`quickpanel`, `launcherphone` and `settings` keep working).
//   - The Wallpapers share the Settings' phone: same landscape body, same 2.5D pose,
//     same turn out of this phone and back (SettingsStage.qml hosts both screens).
//     From the Settings the gallery just cross-fades in on the same phone; Back
//     goes to whichever screen it came from.
Scope {
    id: root

    // QuickSource: what the tiles show and do.
    required property var source

    // NotificationSource: what the list under "Notifications" shows.
    required property var notificationSource

    // The bars' windows, so clicking the bell isn't mistaken for a click
    // away (which would close the panel and then reopen it).
    property var barWindows: []

    // The avatar and banner you pick by clicking them — a singleton (see
    // PanelImages.qml).

    property bool open: false
    // The cheatsheet board is on screen: the phone goes to the Overlay layer
    // too (the board steps down to Top meanwhile), so it is drawn over it.
    property bool coverCheat: false
    // The phone's window is on screen, which includes its slide-out after `open`
    // went false. The cheatsheet board stays one layer down until this is false
    // (not just until `up` is), or it jumps back over the phone the moment the
    // phone starts to leave and the phone seems to dive behind it.
    readonly property bool onScreen: win.visible

    // ===== the phone's screens =====
    // AppSource.qml: the app index the Apps screen searches and launches from.
    property var appSource: null
    // LauncherPhone.qml (the corner phone; only its own `wallpaperphone` IPC is left).
    property var launcher: null
    // PhoneRoute.js: the stack of screens, Quick at the bottom unless the phone was
    // opened on another one. Reset to just Quick whenever the phone goes away.
    property var phoneRoute: PR.open("quick")
    // The screen the face shows: Quick or Apps. (Settings is a turn of the whole
    // phone, not a face; it is on the stack so Back returns to the right face.)
    readonly property string faceScreen: {
        const st = root.phoneRoute.stack
        for (let i = st.length - 1; i >= 0; i--) {
            if (st[i] === "apps" || st[i] === "quick")
                return st[i]
        }
        return "quick"
    }
    // 0 = the Quick face, 1 = the Apps face; animated while the window is up.
    property real routeK: 0
    readonly property bool routing: routePrep.running || routeAnim.running

    // ===== the Settings =====
    property var picker: null

    // The landscape phone (SettingsStage.qml) is what the phone is showing, or
    // turning into. It carries the Settings or the Wallpapers (`landscape`); the
    // name is from when it only carried the Settings.
    property bool settingsOpen: false

    // Which screen the landscape phone carries: "settings" or "wallpapers". It is
    // left as it was while the phone turns back, so nothing flickers on the way.
    property string landscape: "settings"
    // The Wallpapers face straight on once the turn has landed and the phone is
    // still, so the gallery's small type and pictures are drawn sharp (straight to
    // the device pixels, like the Overview phone). They are tilted like the Settings
    // for the whole turn in and out. false = they rest tilted like the Settings do
    // (a little softer). See SettingsStage.qml.
    property bool wallpapersStraight: true
    readonly property bool wallpapersOpen: settingsOpen && landscape === "wallpapers"

    // The Settings' X / Escape has started turning the phone back into the Quick
    // Panel and it hasn't fully settled yet. While it is true the panel keeps its
    // keyboard focus and ignores a click-away grab that clears by itself: with
    // nothing mapped on the workspace, dropping the Settings' keyboard focus
    // makes Hyprland clear the grab (there is no window to hand focus to), and
    // that used to close the whole panel in the middle of the turn.
    property bool turningBack: false

    // The Settings phone is on screen for any reason, including while it is
    // still turning in or going away. QuickSource follows this, like `up`.
    readonly property bool settingsShown: settingsOpen || sstage.shownOpacity > 0.001

    // How the turn feels: how long it takes, how far it winds up and overshoots
    // (InOutBack's overshoot), and how much smaller the phone is held in the
    // middle of it (see FlipMath.dip).
    property int flipMs: 200
    // The turn's curve (a cubic bezier, Qt's [c1x, c1y, c2x, c2y, 1, 1]): it leaves gently,
    // is quickest through the middle and glides into place with a long soft end. The old turn
    // was 260 ms of Easing.OutCubic, which is half done after 55 ms and ~80 % after 110 ms, so
    // the whole thing, and above all the swap of the two screens on it, was over in a few
    // frames and read as a snap. Both directions use it (Quick -> Settings and back).
    readonly property var flipCurve: [0.30, 0.0, 0.20, 1.0, 1.0, 1.0]
    // Before anything moves, the phone is redrawn on the light settings and with room to be
    // rolled (PhoneBody `turnRoll`, `moving`): that redraw is heavy and used to land on the
    // first frames of the turn. The turn now waits until this many frames have really been
    // drawn (and never longer than flipPrepMaxMs), so it starts on a phone that is ready
    // instead of jumping ahead by however long the redraw took.
    property int flipPrepFrames: 2
    property int flipPrepMaxMs: 260
    // The Apps screen is a launcher, so its phone just slides, no bounce: up into
    // place in launchInMs on a sheet-style curve (it leaves gently, speeds up, then
    // glides to a long soft stop, the curve of a sheet on a phone), while the tilt
    // straightens a little behind it (launchTiltMs) so the phone seems to settle into
    // place rather than ride up as one stiff block; away in launchOutMs, an ease-in,
    // with no pull-up first. (The Quick Panel keeps its bounce.) `launching` is read
    // when the animation starts.
    readonly property bool launching: faceScreen === "apps" && !settingsShown
    property int launchInMs: 340
    property int launchTiltMs: 460
    property int launchOutMs: 300
    readonly property var launchCurve: [0.32, 0.72, 0, 1, 1, 1]
    // Away: it starts at once (no wait), picks up speed, and the lift and the tilt go
    // together on the same curve, a mirror of the way in.
    readonly property var launchOutCurve: [0.5, 0, 0.7, 0.35, 1, 1]
    // The turn INTO the Wallpapers is quicker than the Settings' (and so is its
    // ring-out), since the gallery is the point of going there. Leaving is the
    // normal speed. Equal to flipMs now: every turn of the phone has the same speed.
    property int wallpapersEnterMs: 200
    // Build the gallery while the Apps screen is up, so it is ready when you tap
    // the Wallpapers tile (a little work whenever Apps is on screen). false = build
    // it after the tap, which leaves the screen blank for a moment after the turn.
    property bool wallpapersWarm: true
    // The gallery is not built while the phone is still coming up (it reads the
    // wallpaper folder and loads thumbnails, and that landed in the middle of the
    // slide as a stall). `warmReady` turns true `warmDelayMs` after the phone has
    // landed on the Apps screen, and false again once it leaves that screen (the
    // Settings and Wallpapers are a turn of the phone, not another screen, so going
    // into them keeps it).
    property int warmDelayMs: 900
    property bool warmReady: false
    readonly property bool warmWanted: wallpapersWarm && open && faceScreen === "apps"
    onWarmWantedChanged: {
        if (warmWanted) {
            warmDelay.restart()
        } else {
            warmDelay.stop()
            warmReady = false
        }
    }
    Timer {
        id: warmDelay
        interval: root.warmDelayMs
        onTriggered: {
            if (!root.warmWanted)
                return
            // Still sliding or turning: try again a little later.
            if (enterAnim.running || root.routing || phone.moving)
                warmDelay.restart()
            else
                root.warmReady = true
        }
    }
    readonly property real enterSpeed: settingsOpen && landscape === "wallpapers" && flipAnim.to > 0.5
                                       ? wallpapersEnterMs / flipMs : 1
    property real flipDip: 0.12
    // The wobble that rings out when the turn lands, like the pull-out's tilt:
    // how far (degrees of roll) it swings past upright / flat at first, and
    // how long the whole ring takes (ms). 0 for a plain stop.
    property real flipWobble: 2.5
    property int flipRingMs: 380
    // The two phone bodies are drawn on their light turn settings (PhoneBody `turnLite`: a
    // smaller picture, 2 samples, no mip chain) while they turn. The turn itself is over
    // after flipMs, but the ring-out above keeps both bodies redrawing every frame for about
    // flipRingMs more, and that used to run on the heavier "moving" settings: at the moment
    // the turn landed both pictures were resized (graphics memory re-made) and redrawn
    // larger, with a mip chain, in the middle of the ring: the hitch you feel at the end of
    // the turn. true = stay on the light settings until the ring has finished, then go to
    // the full ones once, with everything still. false = the old behaviour.
    property bool ringKeepsLite: true
    // Which way the first swing goes (the way the phone was turning).
    property real ringSign: 1

    // Raised by an incoming notification rather than by you. Behaves like
    // `open` for showing the phone, but without the click-away grab (see
    // grabWanted) and it lowers itself again when the card's time is up.
    // Touching the phone turns it into a normal `open`.
    property bool alertUp: false

    // True from the moment an alert raises a phone that was down until
    // it's out of sight again (or you take hold of it): it's sitting
    // low, showing only the top of the phone (stage.rise). Kept separate
    // from alertUp so the phone doesn't jump up while it's leaving.
    property bool alertMode: false

    // Raised by the hot edge with "Peek first" on (panel.hotPeek): only the tip
    // of the phone shows (win.peekLift), so a pointer that strays to the bottom of
    // the screen doesn't throw the whole phone up. A click on it is a normal
    // `open` (claimPeek); leaving it alone lowers it again (peekLeave). Like
    // alertUp it takes neither the keyboard nor the click-away grab.
    property bool peekUp: false

    // The low resting spot while peeking, kept apart from peekUp for the same
    // reason as alertMode: the phone doesn't jump up while it's leaving.
    property bool peekMode: false

    // How far below its usual spot the phone rests: the alert's low spot, the
    // peek's lower one, or 0 for the normal panel (stage.rise, hitRect, the rail).
    readonly property real lowLift: alertMode ? win.alertLift : (peekMode ? win.peekLift : 0)

    // The phone is up, for any of those reasons. QuickSource follows this so the
    // tiles are fresh whenever it's showing.
    readonly property bool up: open || alertUp || peekUp

    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    // ===== things you're likely to change =====
    property url bannerSource: ""
    property url avatarSource: ""

    // The hot edge: a strip at the bottom-center of each screen. Set
    // hotEdge to false to turn it off; hotDwell is how long (ms) the mouse
    // has to stay in it, so brushing past doesn't open the panel.
    // (Settings -> General -> Quick Panel.)
    property bool hotEdge: SettingsService.flag("panel.hotEdge")
    property real hotWidth: 360
    property real hotHeight: 4
    property int hotDwell: SettingsService.get("panel.hotDwell")
    // Peek first (Settings -> General -> Quick Panel): the hot edge raises only the
    // tip of the phone, and a click brings the rest. Off by default.
    property bool hotPeek: SettingsService.flag("panel.hotPeek")
    // How far down the phone's face the peek shows, in design units: through
    // the clock and date (QuickPanelFace draws them at y 36..~90).
    property real peekTipY: 96
    // How long (ms) the peek waits with the mouse off both it and the hot
    // edge before it drops: enough to cross from the edge strip onto the tip.
    property int peekLeaveMs: 450
    // The mouse is in a hot edge strip right now (any screen's).
    property bool hotHovering: false

    // How much of the phone shows when it's up, as a fraction of its
    // height: 1 = all of it, 0.76 = the top three quarters or so, with the
    // rest below the bottom edge of the screen. Only changes how far it
    // comes up, not how big it is.
    property real peek: SettingsService.get("panel.peek") / 100

    // What is actually used. In 2D the face is a little more than a tenth taller on the
    // screen for the same cut: the tilted pose reveals more of it for the same `peek` (the
    // rail's lean also pulls the window taller), so 2D comes up a bit further to show as
    // much of the panel -- the same amount of notifications -- as the 2.5D one does.
    readonly property real peekEff: flat2d ? Math.min(1, peek * 1.10) : peek

    // Height reserved for the bar, and a little breathing room; the phone
    // is sized so that all of it would fit between the bar and the
    // screen's bottom edge (however much of it `peek` then shows). It is
    // the same 63 whichever edge the bar is on — a bar on the left or
    // right used to count as 0 here, which made the phone bigger there —
    // so the phone is the same size on every edge.
    property real barHeight: 63
    property real edgeMargin: 10
    // 1 = never bigger than the Figma frame; it only ever shrinks to fit.
    property real maxScale: 1

    // The pull-out. `bounce` is how far (px) it rises past its resting
    // spot before dropping back; `headroom` is the empty room above the
    // panel that overshoot needs. tiltRoll / tiltPitch / tiltYaw are the
    // degrees the phone is turned while it's still "in the pocket".
    property real bounce: 34
    property real headroom: 44
    // Gap (design units, scaled like everything else) between the
    // phone's own right edge and the Power rail that floats beside it
    // — see PowerMenu.qml and the `railHost` item below.
    // (2D: closer, as in the flat design.)
    property real railGap: flat2d ? 26 : 60
    // The 2D look (Settings -> Quick -> Quick Panel phone): the phone faces straight on, has no side
    // wall, and does not tilt as it comes out of the pocket; it just rises and settles. The Settings
    // turn is unchanged (the phone tips into the Settings pose on its way, as before).
    readonly property bool flat2d: Theme.quickFlat
    property real tiltRoll: flat2d ? 0 : 12
    property real tiltPitch: flat2d ? 0 : 10
    property real tiltYaw: flat2d ? 0 : -6

    // The vibration when a notification arrives. buzzAmount is how far
    // (px on screen) the phone shakes sideways, buzzHz how fast, and it
    // does buzzPulses bursts of buzzBurstMs each with buzzGapMs of quiet
    // between them, like a phone's "bzzt ... bzzt". buzzRiseMs is how
    // long it waits when the phone has to come up first (the pull-out
    // takes about 0.7s), so it buzzes once it has landed, not on the way.
    // Set buzzAmount to 0 to turn the shake off (the phone still comes up).
    // How much of the phone shows under the notification card when it
    // comes up only to alert, in px on screen (before the monitor's own
    // scaling). Bigger = more of the phone; 0 = the card's bottom edge
    // sits right on the screen edge.
    property real alertMargin: 26

    property real buzzAmount: SettingsService.flag("notify.buzz") ? 9 : 0
    property real buzzHz: 15
    property int buzzPulses: 2
    property int buzzBurstMs: 340
    property int buzzGapMs: 130
    property int buzzRiseMs: 700

    // The hot edge ignores the mouse until this time (ms since epoch), so
    // a panel that just closed under a resting cursor doesn't reopen.
    property double hotBlockedUntil: 0

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        for (const s of Quickshell.screens) {
            if (s.name === name)
                return s
        }
        return Quickshell.screens[0]
    }

    // Stops the wobble where it is and puts the phone straight.
    function stopRing() {
        ring.stop()
        stage.wob = 0
    }

    // `entry` is the screen it comes up on ("quick" unless asked otherwise). The
    // route is set before `open` flips so the face is already there on the first
    // frame instead of sliding in during the pull-out.
    function openOn(screen, entry) {
        stopRing()
        // Opened from nothing: it starts on `entry`, with that as the floor.
        if (!open)
            setRoute(PR.open(entry || "quick"))
        if (settingsOpen) {
            if (open && (!screen || screen === targetScreen)) {
                // The landscape phone is this very phone turned out of the
                // Quick Panel / Apps, which is still up behind it: turn it
                // back the way the Settings' X does (see settingsBack), rather
                // than snapping it upright.
                turningBack = true
                backSettle.stop()
                settingsOpen = false
                setRoute(PR.go(phoneRoute, faceScreen))
                turnTo(0)
            } else if (!open && (!screen || screen === targetScreen) && stage.flip > 0.5 && win.visible) {
                // The Settings stand on their own (SUPER + I) and the Quick Panel is asked
                // for (SUPER + N): the same turn back, not a cut. The Quick Panel's phone is
                // put at its resting spot, upright, without its pull-out (`skipEnter`), and
                // the Settings' phone turns into it the way the X does.
                turningBack = true
                backSettle.stop()
                settingsEnter.stop()
                settingsExit.stop()
                settingsOpen = false
                stage.sPop = 1
                stage.sAlpha = 1
                stage.sTilt = 0
                skipEnter = true
                turnTo(0)
            } else {
                // The phone is being asked for on another monitor: the Settings give
                // way at once, the phone is coming up in their place.
                settingsOpen = false
                settingsEnter.stop()
                settingsExit.stop()
                stage.flip = 0
            }
        }
        if (screen)
            targetScreen = screen
        open = true
    }

    // The Quick Panel comes up out of the standalone Settings by turning, so it does not
    // pull out of the pocket (see openOn and onUpChanged).
    property bool skipEnter: false

    function close() {
        alertUp = false
        peekUp = false
        turningBack = false
        open = false
        closeSettings()
    }

    // ===== turning into the landscape phone (Settings, Wallpapers) and back =====
    function openSettings(screen) {
        openLandscape("settings", screen, "")
    }

    // The Wallpapers: the same phone and the same turn as the Settings. `which` is
    // "lock" for the lockscreen side of the gallery.
    function openWallpapers(screen, which) {
        if (EditMode.active)
            return
        openLandscape("wallpapers", screen, which === "lock" ? "lock" : "desktop")
    }

    // The bar's wallpaper key: closes the Wallpapers if they are what is up (on
    // that side, when a side is asked for), otherwise opens them.
    function toggleWallpapersOn(screen, which) {
        const same = !screen || screen === targetScreen
        const side = which === "lock" ? "lock" : "desktop"
        const now = sstage.wallpaperFace ? sstage.wallpaperFace.target : sstage.initialTarget
        if (wallpapersOpen && same && (which === undefined || side === now))
            close()
        else
            openWallpapers(screen, which)
    }

    // The landscape phone is already up and still: no second turn, the other screen
    // just cross-fades in on it (Settings -> Wallpapers, and Back).
    function showLandscape(kind) {
        if (landscape === kind)
            return
        landscape = kind
        landscapeFocus.restart()
    }

    function swapLandscape(kind, side) {
        if (kind === "wallpapers")
            sstage.setTarget(side || "desktop")
        if (landscape !== kind) {
            setRoute(PR.go(phoneRoute, kind))
            showLandscape(kind)
        }
    }

    function openLandscape(kind, screen, side) {
        if (settingsOpen) {
            swapLandscape(kind, side)
            return
        }
        turningBack = false
        backSettle.stop()
        stopRing()
        // Before anything turns: the screen the phone turns into is already the
        // right one (it snaps while the phone is down or turning).
        landscape = kind
        if (kind === "wallpapers") {
            sstage.setTarget(side || "desktop")
            sstage.dealIfWarm()
        }
        landscapeFocus.restart()
        if (open && (!screen || screen === targetScreen)) {
            // Whatever the Quick Panel had open beside its screen is put away.
            panelFace.powerMenuOpen = false
            panelFace.networkDialogOpen = false
            panelFace.bluetoothDialogOpen = false
            panelFace.nightLightDialogOpen = false
            panelFace.audioDialogKind = ""
            setRoute(PR.go(phoneRoute, kind))
            settingsOpen = true
            // What Hyprland says now, in case a reload or a hand edit changed it.
            HyprlandSettings.refresh()
            settingsExit.stop()
            stage.sPop = 1
            stage.sAlpha = 1
            stage.sTilt = 0
            turnTo(1)
        } else {
            if (open)
                close()
            alertUp = false
            if (screen)
                targetScreen = screen
            setRoute(PR.open(kind))
            settingsOpen = true
            HyprlandSettings.refresh()
            settingsExit.stop()
            flipPrep.stop()
            flipAnim.stop()
            if (!win.visible) {
                stage.sPop = 0
                stage.sTilt = 1
                stage.sAlpha = 0
            }
            stage.flip = 1
            settingsEnter.restart()
        }
    }

    // Turn toward p = 1 (the Settings) or p = 0 (the Quick Panel). The turn
    // starts a beat later: it redraws the phone's picture bigger and on the
    // light settings, which is done a couple of frames *before* it moves rather
    // than during its first one (the same trick the pull-out's exit uses).
    function turnTo(p) {
        stopRing()
        flipAnim.stop()
        flipAnim.to = p
        armPrep(flipPrep)
    }

    // ===== waiting for the redraw before a move =====
    // Counts the frames that are really drawn while a turn (flipPrep) or a slide between
    // the Quick and Apps screens (routePrep) is waiting to start. A fixed 40 ms wait was
    // shorter than the redraw it was waiting for on a big or busy screen, so the move began
    // in the middle of a stall and its first frames were skipped (the move just appeared
    // part-way done). The frame counter follows the render loop, so it waits exactly as long
    // as the redraw takes.
    property real prepSince: 0
    FrameAnimation {
        id: prepFrames

        property int count: 0

        running: flipPrep.running || routePrep.running
        onTriggered: count++
    }

    function armPrep(timer) {
        prepFrames.count = 0
        prepSince = Date.now()
        timer.restart()
    }

    // The phone has been redrawn (enough frames), or it has waited long enough.
    function prepReady() {
        return prepFrames.count >= flipPrepFrames || Date.now() - prepSince >= flipPrepMaxMs
    }

    // The Settings' X, or Escape on their menu: the phone turns back into the
    // Quick Panel if that is where it came from, otherwise they just go away.
    function settingsBack() {
        if (!settingsOpen)
            return
        const r = PR.back(phoneRoute)
        // Back from the Wallpapers to the Settings they were opened from (or the
        // other way round) stays on the landscape phone: the screens cross-fade.
        if (!r.closed) {
            const next = PR.top(r.state)
            if (next === "settings" || next === "wallpapers") {
                setRoute(r.state)
                showLandscape(next)
                return
            }
        }
        if (!open) {
            closeSettings()
            return
        }
        turningBack = true
        backSettle.stop()
        settingsOpen = false
        // Back to the screen the phone was opened from (Quick or Apps).
        if (!r.closed)
            setRoute(r.state)
        turnTo(0)
    }

    // The Settings go away: they shrink and fade where they stand.
    function closeSettings() {
        if (!settingsOpen)
            return
        turningBack = false
        backSettle.stop()
        stopRing()
        settingsOpen = false
        flipPrep.stop()
        flipAnim.stop()
        if (stage.flip > 0.5) {
            stage.flip = 1
            settingsEnter.stop()
            settingsExit.restart()
        } else {
            // Caught in the first half of the turn: the phone is still the Quick
            // Panel, so it just stops turning.
            stage.flip = 0
        }
    }

    // A notification arrived (NotificationSource.alerted): bring the phone
    // up if it's down, then buzz. The card itself is driven straight off
    // the source's toast / toastActive (see the panelFace bindings).
    function alert() {
        // Only the tip is up: it becomes the alert's phone, which rises a bit
        // further to show the card. alertUp first, so `up` never drops.
        if (peekUp && !open) {
            alertMode = true
            alertUp = true
            peekMode = false
            peekUp = false
        }
        const wasUp = up
        if (!wasUp) {
            targetScreen = focusedScreen()
            // Before alertUp, so the phone's first frame is already the
            // low resting spot instead of jumping down to it.
            alertMode = true
            alertUp = true
        }
        buzzTimer.interval = wasUp ? 0 : buzzRiseMs
        buzzTimer.restart()
    }

    // You touched a phone that was only up for an alert: it's yours now.
    function claim() {
        if (alertUp && !open)
            open = true
    }

    // The hot edge with "Peek first" on: bring up just the tip, unless the phone
    // is already up for some other reason (then it is left as it is).
    function peekOn(screen) {
        if (up || settingsOpen)
            return
        stopRing()
        if (screen)
            targetScreen = screen
        // Before peekUp, so the first frame is already the low spot (see alert()).
        peekMode = true
        peekUp = true
    }

    // A click on the peeking tip: the whole phone, as a normal open.
    function claimPeek() {
        if (peekUp && !open)
            open = true
    }

    // The peek drops once the mouse has been off both it and the hot edge for a
    // moment (the gap is crossing from the edge strip onto the tip).
    Timer {
        id: peekLeave
        interval: root.peekLeaveMs
        running: root.peekUp && !root.open && !root.hotHovering && !peekTouch.containsMouse
        onTriggered: root.peekUp = false
    }

    // Clicking the bell on the monitor it's already open on closes it;
    // on another monitor it moves there.
    function toggleOn(screen) {
        // The Settings (or the Wallpapers) are up and the Quick Panel's key is pressed
        // (SUPER + I, then SUPER + N): the phone turns into the Quick Panel instead of
        // closing, whether it was turned out of the Quick Panel or came up on its own.
        if (settingsOpen && (!screen || screen === targetScreen)) {
            if (open)
                setRoute(PR.home(phoneRoute))
            openOn(screen)
            return
        }
        if (open && (!screen || screen === targetScreen))
            close()
        else
            openOn(screen)
    }

    // ===== the phone's screens: going between them =====
    function setRoute(state) {
        phoneRoute = state
    }

    // The face follows the route: it slides while the window is up and just
    // snaps while it is hidden. The slide starts a beat later because the phone is
    // redrawn on the light settings a couple of frames before anything moves
    // (the same trick the Settings turn uses).
    function syncFace() {
        const want = faceScreen === "apps" ? 1 : 0
        routeAnim.stop()
        routePrep.stop()
        if (!win.visible) {
            routeK = want
            return
        }
        if (routeK === want) {
            focusPhoneKeys()
            return
        }
        routeAnim.to = want
        armPrep(routePrep)
    }
    onFaceScreenChanged: syncFace()

    // Whatever the Quick screen had open beside it is put away.
    function closeQuickDialogs() {
        panelFace.closeDialogs()
    }

    // To the Apps screen, with `seed` already typed into its search box.
    function goApps(seed) {
        if (!open || settingsShown)
            return
        if (faceScreen === "apps") {
            if (seed)
                appsFace.appendText(seed)
            return
        }
        closeQuickDialogs()
        appsFace.reset()
        if (seed)
            appsFace.appendText(seed)
        setRoute(PR.go(phoneRoute, "apps"))
    }

    // Open on the Apps screen: the phone's floor is Apps, so Escape closes it
    // (a launcher, not a detour through Quick).
    function openAppsOn(screen) {
        if (open && !settingsShown && (!screen || screen === targetScreen)) {
            goApps("")
            return
        }
        const wasOpen = open
        appsFace.reset()
        openOn(screen, "apps")
        // Already up (on another monitor, say): it moves there and Apps is its floor.
        if (wasOpen)
            setRoute(PR.open("apps"))
    }

    // The Apps screen as a toggle: up on Apps -> away, otherwise open on Apps. This
    // is the old launcher phone's `toggleOn`, for the keys that still say
    // "launcher" (the dock's Search key; `ipc call launcherphone toggle` does the
    // same).
    function toggleAppsOn(screen) {
        if (open && !settingsShown && faceScreen === "apps" && (!screen || screen === targetScreen))
            close()
        else
            openAppsOn(screen)
    }

    // Apps with one of the extras' triggers already typed, so its card is up at once:
    // calc, clip, color, emoji or web (`ipc call launcherphone mode emoji`). Any other
    // name just opens Apps. With `toggle`, asking for the card that is already up puts
    // the phone away again (a key that opens the emoji picker closes it as well).
    readonly property var appsModes: ({
        calc: "calc ", clip: "clip ", color: "color ", emoji: "emoji ", web: "web "
    })

    function openAppsMode(screen, name, toggle) {
        const key = String(name || "").trim().toLowerCase()
        const seed = appsModes[key] || ""
        const here = open && !settingsShown && faceScreen === "apps" && (!screen || screen === targetScreen)
        if (here) {
            if (toggle && seed !== "" && appsFace.query.toLowerCase().indexOf(key) === 0) {
                close()
                return
            }
            appsFace.setText(seed)
            return
        }
        openAppsOn(screen)
        // reset() has run by now, so the box is empty and the seed is all it holds.
        if (seed !== "")
            appsFace.appendText(seed)
    }

    // Home always means Quick, with nothing under it.
    function homeNow() {
        if (!open)
            return
        setRoute(PR.home(phoneRoute))
        if (settingsOpen)
            settingsBack()
    }

    // Back: one screen back; at the floor, close.
    function back() {
        if (settingsOpen) {
            settingsBack()
            return
        }
        if (!open) {
            close()
            return
        }
        const r = PR.back(phoneRoute)
        if (r.closed) {
            close()
            return
        }
        setRoute(r.state)
    }

    // Ctrl+1..4.
    function jump(n) {
        const name = PR.byNumber(n)
        if (name === "quick")
            homeNow()
        else if (name === "apps")
            goApps("")
        else if (name === "settings")
            openSettings(targetScreen)
        else if (name === "wallpapers")
            openWallpapers(targetScreen)
    }

    // A tile on the Apps screen's first row: Settings and Wallpapers turn this
    // phone (Back returns to Apps).
    function runBuiltin(id) {
        if (id === "settings") {
            openSettings(targetScreen)
            return
        }
        if (id === "wallpapers")
            openWallpapers(targetScreen)
    }

    // The IPC `go`.
    function goOn(screen, name) {
        if (name === "quick") {
            if (open && (!screen || screen === targetScreen))
                homeNow()
            else
                openOn(screen)
        } else if (name === "apps") {
            openAppsOn(screen)
        } else if (name === "settings") {
            openSettings(screen)
        } else if (name === "wallpapers") {
            openWallpapers(screen)
        }else if (name === "power" || name === "session") {
            togglePowerOn(screen)
        }
    }
    function togglePowerOn(screen) {
        if (open && !settingsShown && panelFace.powerMenuOpen
            && (!screen || screen === targetScreen)) {
            close()
            return
            }
            if (!open || settingsShown || faceScreen !== "quick")
                openOn(screen)
                panelFace.powerMenuOpen = true
    }

    // Keys while Quick (or Apps, before its search box has the keyboard) has it.
    // A plain letter starts a search; Escape puts away a dialog, then goes back.
    function quickKeyPressed(event) {
        if (!open || settingsShown)
            return
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const alt = (event.modifiers & Qt.AltModifier) !== 0
        const meta = (event.modifiers & Qt.MetaModifier) !== 0
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            root.jump(event.key - Qt.Key_0)
            event.accepted = true
            return
        }
        if (faceScreen === "apps") {
            // The Apps screen is still coming in and its search box does not have
            // the keyboard yet: what is typed meanwhile is kept for it.
            if (event.key === Qt.Key_Escape) {
                appsFace.back()
                event.accepted = true
            } else if (PR.startsSearch(event.text, ctrl, alt, meta)) {
                appsFace.appendText(event.text)
                event.accepted = true
            }
            return
        }
     if (panelFace.powerMenuOpen) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                powerRail.move(-1)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                powerRail.move(1)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                if (powerRail.currentIndex >= 0)
                    powerRail.trigger(powerRail.currentIndex)
                event.accepted = true
                return
            }
        }
        if (event.key === Qt.Key_Escape) {
            if (panelFace.powerMenuOpen || panelFace.networkDialogOpen || panelFace.bluetoothDialogOpen
                    || panelFace.nightLightDialogOpen || panelFace.audioDialogKind !== "")
                closeQuickDialogs()
            else
                root.back()
            event.accepted = true
        } else if (SettingsService.flag("panel.typeToSearch") && PR.startsSearch(event.text, ctrl, alt, meta)) {
            root.goApps(event.text)
            event.accepted = true
        }
    }

    // The keyboard goes to whichever screen is up.
    function focusPhoneKeys() {
        if (!open || routing)
            return
        if (settingsOpen || turningBack)
            keys.forceActiveFocus()
        else if (faceScreen === "apps")
            appsFace.focusSearch()
        else
            keys.forceActiveFocus()
    }

    // The window takes the keyboard (on demand) while it is open and has
    // something to do with it: the Apps search box, or typing from Quick.
    readonly property bool phoneKeysWanted: open && !settingsShown
        && (faceScreen === "apps"|| panelFace.powerMenuOpen || SettingsService.flag("panel.typeToSearch")) 

    Timer {
        id: focusTimer
        // The keys must work at once on the Apps screen.
        interval: root.faceScreen === "apps" ? 20 : 140
        onTriggered: root.focusPhoneKeys()
    }

    // The keyboard goes to whichever screen the landscape phone carries: the
    // Settings' key scope, or the gallery (which has its own arrows, Enter, Tab
    // and Escape).
    function focusLandscape() {
        if (!settingsOpen && !turningBack)
            return
        if (landscape === "wallpapers" && sstage.wallpaperFace)
            sstage.focusWallpapers()
        else
            keys.forceActiveFocus()
    }

    Timer {
        id: landscapeFocus
        interval: 120
        onTriggered: root.focusLandscape()
    }

    Timer {
        id: routePrep
        interval: 16
        onTriggered: {
            // Same wait as the turn's (see armPrep).
            if (!root.prepReady()) {
                routePrep.restart()
                return
            }
            routeAnim.restart()
        }
    }

    // The slide between the Quick and Apps screens. It was 200 ms of Easing.OutCubic: the
    // faces cross-fade over routeK 0.3 .. 0.7, which that curve covers in about 40 ms, so
    // one face just replaced the other. Now it is a bit longer and starts and ends softly,
    // and the cross-fade lasts around 150 ms (the two faces' opacity ranges are below).
    property int routeMs: 200
    readonly property var routeCurve: [0.40, 0.0, 0.20, 1.0, 1.0, 1.0]

    NumberAnimation {
        id: routeAnim
        target: root
        property: "routeK"
        duration: root.routeMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.routeCurve
        onFinished: root.focusPhoneKeys()
    }

    // Once you've taken hold of it, it's a normal open panel.
    onOpenChanged: {
        // The keybinds panel may have paused every shortcut to record one: a panel
        // that goes away must never leave them paused.
        if (!open)
            KeybindService.resume()
        if (open) {
            focusTimer.restart()
            alertUp = false
            peekUp = false
            peekMode = false
            // Slides the phone up from the low alert spot to its full
            // resting spot (stage.rise animates back to 0).
            alertMode = false
        }
    }

    // Everything that used to hang off `open` — coming up, going down —
    // hangs off `up` now, so an alert raises and lowers the phone with
    // exactly the same pull-out.
    onUpChanged: {
        if (up) {
            exitDelay.stop()
            exitAnim.stop()
            // Turned out of the standalone Settings: it is already where it belongs.
            if (root.skipEnter) {
                root.skipEnter = false
                enterAnim.stop()
                stage.lift = 0
                stage.tilt = 0
                return
            }
            // Coming up from nothing starts fully out of sight; coming
            // back mid-way through leaving carries on from where it is.
            // (It starts from the old hidden spot, `enterFrom`, not from the deeper
            // `hiddenLift`: the pull-out is timed from there.)
            if (stage.lift > stage.enterFrom)
                stage.lift = stage.enterFrom
            enterAnim.restart()
        } else {
            enterAnim.stop()
            // Whole panel's on its way out — no reason to still see the
            // Power rail, or a network/Bluetooth list, out next time it's
            // pulled up.
            panelFace.powerMenuOpen = false
            panelFace.networkDialogOpen = false
            panelFace.bluetoothDialogOpen = false
            panelFace.nightLightDialogOpen = false
            panelFace.audioDialogKind = ""
            hotBlockedUntil = Date.now() + 1200
            // It is the Settings on screen, not the Quick Panel: the Quick
            // Panel's phone is already out of sight, so it just stays down (the
            // Settings go away by themselves, see closeSettings()).
            if (stage.flip > 0.5) {
                stage.lift = stage.hiddenLift
                return
            }
            // A small pull up first, unless it's still on its way up.
            const rising = stage.lift > 20
            stage.exitPeak = rising ? stage.lift : -bounce * 0.7
            stage.exitPeakMs = rising ? 1 : 130
            // Sitting still, the phone is drawn at full quality, which is
            // too heavy to animate on. Switching down to the light settings
            // redraws it once, so do that a couple of frames *before* it
            // starts to move rather than during the first frame of the
            // drop (which would show up as a hitch). If it's already on the
            // light settings (closed mid-pull-out), go straight away.
            // (Not on the Apps screen: the wait showed as a dead stretch before it
            // moved. Its start is so gentle that the redraw hides in it.)
            if (phone.crisp && !root.launching)
                exitDelay.restart()
            else
                exitAnim.restart()
        }
    }

    // The Refresh button (QuickPanelFace's header row): reload Hyprland's
    // config first, and once that has finished, reload this shell. The
    // order matters: reloading the shell tears down everything it started,
    // including a still-running hyprctl. Reloads the shell even if
    // hyprctl failed or isn't there, so the button never does nothing.
    // Quickshell.reload(true) is a hard reload (every window is rebuilt,
    // not reused), so it also clears out a window that got stuck.
    Process {
        id: refreshHyprland
        command: ["hyprctl", "reload"]
        onExited: Quickshell.reload(true)
    }

    IpcHandler {
        target: "quickpanel"

        function toggle(): void {
            root.toggleOn(root.focusedScreen())
        }

        function show(): void {
            root.openOn(root.focusedScreen())
        }

        function hide(): void {
            root.close()
        }
      function keepAwake(): void {
            root.source.toggleKeepAwake()
        }
    }

    // The one door: `phone` is the whole phone (see the header comment).
    IpcHandler {
        target: "phone"

        function toggle(): void {
            root.toggleOn(root.focusedScreen())
        }

        function show(): void {
            root.openOn(root.focusedScreen())
        }

        function hide(): void {
            root.close()
        }

        // go quick | apps | wallpapers | settings
        function go(name: string): void {
            root.goOn(root.focusedScreen(), name)
        }

        function back(): void {
            root.back()
        }

        function home(): void {
            root.homeNow()
        }
    }

    // The old name for the Apps screen (it used to be the corner phone's Home):
    // a keybind on it, e.g. SUPER + A, still works and opens Apps.
    IpcHandler {
        target: "launcherphone"

        function toggle(): void {
            if (root.open && !root.settingsShown && root.faceScreen === "apps")
                root.close()
            else
                root.openAppsOn(root.focusedScreen())
        }

        function show(): void {
            root.openAppsOn(root.focusedScreen())
        }

        function hide(): void {
            if (root.open && root.faceScreen === "apps")
                root.close()
        }

        // Apps with a card's trigger typed: calc, clip, color, emoji, web.
        function mode(name: string): void {
            root.openAppsMode(root.focusedScreen(), name, false)
        }

        // The same, but the key that opened it also closes it.
        function toggleMode(name: string): void {
            root.openAppsMode(root.focusedScreen(), name, true)
        }
    }

    // The old App Launcher board's name (it is gone: the launcher is the Apps screen of
    // this phone, with all of its extras). A keybind that still says `applauncher` opens it.
    IpcHandler {
        target: "applauncher"

        function toggle(): void {
            root.toggleAppsOn(root.focusedScreen())
        }

        function show(): void {
            root.openAppsOn(root.focusedScreen())
        }

        function hide(): void {
            if (root.open && root.faceScreen === "apps")
                root.close()
        }
    }

    // A bare Super tap, via Hyprland's global-shortcut protocol (what dots-hyprland's
    // keybinds.lua sends: hl.dsp.global("quickshell:searchToggleRelease")). It used to
    // open the old Overview + launcher board; it opens the Apps screen now. appid
    // defaults to "quickshell" for every Quickshell process, and registering the same
    // appid+name twice crashes the second one, so only one shell may run at a time.
    // onReleased alone decides nothing: the bind is a release bind (`release = true`),
    // and Hyprland is what drops it when Super was held for another key (issue #99).
    GlobalShortcut {
        appid: "quickshell"
        name: "searchToggleRelease"
        description: "Shell: Toggle search"
        onReleased: root.toggleAppsOn(root.focusedScreen())
    }

    // The old wallpaper picker board's name (it is gone: the Wallpapers are this
    // phone's landscape screen now). A keybind or the desktop menu that still says
    // `wallpaperpicker` opens them here, on the same side (desktop or lockscreen).
    IpcHandler {
        target: "wallpaperpicker"

        function toggle(): void {
            root.toggleWallpapersOn(root.focusedScreen())
        }

        function show(): void {
            root.openWallpapers(root.focusedScreen())
        }

        function hide(): void {
            if (root.wallpapersOpen)
                root.close()
        }

        function togglelock(): void {
            root.toggleWallpapersOn(root.focusedScreen(), "lock")
        }

        // The Wallpapers on Wallhaven (WallhavenService.qml) instead of your folder.
        function wallhaven(): void {
            WallhavenService.askedSource = "wallhaven"
            root.openWallpapers(root.focusedScreen())
        }

        function showlock(): void {
            root.openWallpapers(root.focusedScreen(), "lock")
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            if (root.settingsOpen)
                root.close()
            else
                root.openSettings(root.focusedScreen())
        }

        function show(): void {
            root.openSettings(root.focusedScreen())
        }

        function hide(): void {
            if (root.settingsOpen)
                root.close()
        }

        function page(name: string): void {
            const f = sstage.face
            for (let i = 0; i < f.pages.length; i++) {
                if (f.pages[i].id === name)
                    f.go(i)
            }
            root.openSettings(root.focusedScreen())
        }
    }

    // A plugin widget's Settings key in Edit Desktop (EditChrome.qml): Edit Desktop gets out
    // of the way first, then Settings opens on the Desktop page of that monitor, where the
    // Plugins card opens the plugin (PluginService.settingsTarget).
    Connections {
        target: PluginService

        function onSettingsWanted(screen) {
            pluginSettingsDelay.screenName = screen
            if (EditMode.active) {
                EditMode.close()
                pluginSettingsDelay.restart()
            } else {
                pluginSettingsDelay.triggered()
            }
        }
    }

    Timer {
        id: pluginSettingsDelay
        property string screenName: ""
        interval: 300
        onTriggered: {
            const f = sstage.face
            for (let i = 0; i < f.pages.length; i++) {
                if (f.pages[i].id === "desktop")
                    f.go(i)
            }
            let scr = root.focusedScreen()
            for (const s of Quickshell.screens) {
                if (s.name === screenName)
                    scr = s
            }
            root.openSettings(scr)
        }
    }

    // Edit Desktop runs on the desktop, so the panel gets out of the way first.
    Timer {
        id: editDelay
        interval: 300
        onTriggered: EditMode.open(root.targetScreen ? root.targetScreen.name : "")
    }

    // Settings > Hyprland > Keybinds: the phone goes away first, then shell.qml opens the
    // keybinds panel on the same monitor (no `ipc call` in between: it is asked directly).
    signal keybindsOpenRequested(var screen)

    Timer {
        id: keybindsDelay
        interval: 300
        onTriggered: {
            console.log("[keybinds] the phone asks for the panel")
            root.keybindsOpenRequested(root.targetScreen)
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: win.visible
    }

    // ===== frame-time probe =====
    readonly property real perfLogMs: {
        const v = parseFloat(Quickshell.env("SEKAIPOP_PERF") ?? "")
        return isNaN(v) ? 0 : (v > 1 ? v : 22)
    }

    FrameAnimation {
        id: perfTick

        running: root.perfLogMs > 0 && win.visible

        property int total: 0
        property int slow: 0
        readonly property string phase: stage.flipping ? "turn"
            : enterAnim.running ? "enter"
            : exitAnim.running ? "exit"
            : ring.running ? "ring"
            : (settingsEnter.running || settingsExit.running) ? "pop"
            : "idle"

        onTriggered: {
            total++
            const ms = frameTime * 1000
            if (ms > root.perfLogMs) {
                slow++
                console.log("[perf] " + phase + ": " + ms.toFixed(1) + " ms frame")
            }
        }

        onRunningChanged: {
            if (!running && total > 0) {
                console.log("[perf] panel hidden: " + total + " frames, " + slow
                            + " over " + root.perfLogMs + " ms")
                total = 0
                slow = 0
            }
        }
    }

    // A short beat between "close requested" and the drop actually
    // starting — see onUpChanged.
    Timer {
        id: exitDelay
        interval: 40
        onTriggered: {
            if (!root.up)
                exitAnim.restart()
        }
    }

    // ===== alerts =====
    Connections {
        target: root.notificationSource

        function onAlerted(entry) {
            root.alert()
        }

        // The card's time is up (or the notification was dismissed
        // elsewhere): a phone that only came up for it goes back down.
        function onToastActiveChanged() {
            if (!root.notificationSource.toastActive && root.alertUp && !root.open)
                root.alertUp = false
        }
    }

    Timer {
        id: buzzTimer
        onTriggered: buzzAnim.restart()
    }

    // ===== the animation =====
    ParallelAnimation {
        id: enterAnim

        SequentialAnimation {
            NumberAnimation {
                target: stage
                property: "lift"
                to: root.launching ? 0 : -root.bounce
                duration: root.launching ? root.launchInMs : 340
                easing.type: root.launching ? Easing.BezierSpline : Easing.OutCubic
                easing.bezierCurve: root.launchCurve
            }
            // The settle never goes below the resting spot (lift > 0 would
            // push the phone down and drag its lower part under the
            // screen edge for a moment, which read as the bottom being
            // clipped). It lands on the rest spot, then hops back up a
            // little and comes down again, so the bounce stays upward only.
            NumberAnimation {
                target: stage
                property: "lift"
                to: 0
                duration: root.launching ? 0 : 170
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: stage
                property: "lift"
                to: root.launching ? 0 : -root.bounce * 0.14
                duration: root.launching ? 0 : 110
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: stage
                property: "lift"
                to: 0
                duration: root.launching ? 0 : 110
                easing.type: Easing.InQuad
            }
        }

        NumberAnimation {
            target: stage
            property: "tilt"
            to: 0
            duration: root.launching ? root.launchTiltMs : 820
            easing.type: root.launching ? Easing.BezierSpline : Easing.OutElastic
            easing.bezierCurve: root.launchCurve
            easing.amplitude: 1
            easing.period: 0.4
        }
    }

    // Going back: a little pull up (like lifting it clear of the pocket),
    // then it drops away, speeding up, tilting back as it goes.
    ParallelAnimation {
        id: exitAnim

        SequentialAnimation {
            NumberAnimation {
                target: stage
                property: "lift"
                to: root.launching ? stage.lift : stage.exitPeak
                duration: root.launching ? 1 : stage.exitPeakMs
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: stage
                property: "lift"
                to: stage.hiddenLift
                duration: root.launching ? root.launchOutMs : 340
                easing.type: root.launching ? Easing.BezierSpline : Easing.InCubic
                easing.bezierCurve: root.launchOutCurve
            }
        }

        NumberAnimation {
            target: stage
            property: "tilt"
            to: 1
            duration: root.launching ? root.launchOutMs : 440
            easing.type: root.launching ? Easing.BezierSpline : Easing.InQuad
            easing.bezierCurve: root.launchOutCurve
        }
    }

    // The buzz: a sideways shake (with a little up-and-down) that dies out
    // over each burst, buzzPulses times. stage.buzzT runs 0 -> 1 across the
    // whole thing and stage.buzzX / buzzY are worked out from it — it only
    // moves the phone (a cheap re-position of the finished picture), not
    // what's drawn inside it.
    NumberAnimation {
        id: buzzAnim
        target: stage
        property: "buzzT"
        from: 0
        to: 1
        duration: root.buzzPulses * root.buzzBurstMs + Math.max(0, root.buzzPulses - 1) * root.buzzGapMs
        onFinished: stage.buzzT = 0
    }

    // ===== the turn into the Settings =====
    Timer {
        id: flipPrep
        interval: 16
        onTriggered: {
            // Wait for the redraw (see armPrep) before anything moves.
            if (!root.prepReady()) {
                flipPrep.restart()
                return
            }
            root.ringSign = flipAnim.to > 0.5 ? -1 : 1
            flipAnim.restart()
            ring.restart()
        }
    }

    // The ring-out: the turn carries a little past where it lands and swings
    // back, settling like the pull-out's tilt does. It is a roll added to both
    // bodies at once (they stay the same picture), and it starts just before
    // the turn lands so the two run into each other.
    SequentialAnimation {
        id: ring

        PauseAnimation {
            // The turn's curve is ~90 % there at 0.62 of its time.
            duration: Math.round(root.flipMs * 0.62 * root.enterSpeed)
        }

        // One soft swing past, a hint back the other way, then still: the
        // same feel as the pull-out's tilt, which is mostly one overshoot.
        NumberAnimation {
            target: stage
            property: "wob"
            to: root.ringSign * root.flipWobble
            duration: root.flipRingMs * 0.42 * root.enterSpeed
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: stage
            property: "wob"
            to: -root.ringSign * root.flipWobble * 0.1
            duration: root.flipRingMs * 0.38 * root.enterSpeed
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: stage
            property: "wob"
            to: 0
            duration: root.flipRingMs * 0.2 * root.enterSpeed
            easing.type: Easing.InOutSine
        }
    }

    // InOutBack: it winds up a little the wrong way, turns, and overshoots its
    // end and settles, so it reads as picked up and put down rather than slid.
    // `to` is set by turnTo().
    NumberAnimation {
        id: flipAnim
        target: stage
        property: "flip"
        to: 1
        duration: Math.round(root.flipMs * root.enterSpeed)
        // A soft bezier (see `flipCurve`): it does not jump away from rest and it glides
        // into place; the wobble rings out after it (see `ring`). The old OutCubic left at
        // full speed and was over in a few frames.
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.flipCurve
        onFinished: {
            // Back at the Quick Panel: the Settings stay on the page they were left on.
            if (!root.settingsOpen) {
                // Keyboard focus is let go a beat after the turn has landed.
                backSettle.restart()
            }
        }
    }

    // See `turningBack`.
    Timer {
        id: backSettle
        interval: 450
        onTriggered: {
            root.turningBack = false
            // The keyboard goes back to whichever screen the turn returned to.
            root.focusPhoneKeys()
        }
    }

    // The Settings coming up on their own (no Quick Panel to turn out of):
    // they pop up to full size with an overshoot while the turn rings out.
    ParallelAnimation {
        id: settingsEnter

        NumberAnimation {
            target: stage
            property: "sPop"
            to: 1
            duration: 560
            easing.type: Easing.OutBack
            easing.overshoot: 1.5
        }

        NumberAnimation {
            target: stage
            property: "sTilt"
            to: 0
            duration: 900
            easing.type: Easing.OutElastic
            easing.amplitude: 1
            easing.period: 0.45
        }

        NumberAnimation {
            target: stage
            property: "sAlpha"
            to: 1
            duration: 140
            easing.type: Easing.OutQuad
        }
    }

    // Going away: it eases out of rest, shrinks, and fades along the whole way,
    // then eases to a stop, so there is no sudden start and nothing solid
    // vanishing in the last moment. Once it is gone the phone is the Quick
    // Panel again (flip 0) and the Settings keep the page they were left on.
    ParallelAnimation {
        id: settingsExit

        onFinished: {
            stage.flip = 0
        }

        NumberAnimation {
            target: stage
            property: "sPop"
            to: 0
            duration: 340
            easing.type: Easing.InOutCubic
        }

        NumberAnimation {
            target: stage
            property: "sAlpha"
            to: 0
            duration: 290
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: stage
            property: "sTilt"
            to: 0.8
            duration: 340
            easing.type: Easing.InOutQuad
        }
    }

    // ===== click away =====
    readonly property var grabList: {
        const list = [win]
        for (let i = 0; i < barWindows.length; i++)
            list.push(barWindows[i])
        return list
    }

    // Not while a file chooser is open (avatar / banner picking): it takes
    // focus, which would count as a click away and close the panel.
    // (`open`, not `up`: a phone that only came up for an alert must not
    // take focus from whatever you're typing into.)
    //
    // Not on the Apps screen either: the launcher has a search box that must get the
    // keyboard the moment it opens, wherever the mouse is. Hyprland gives the keyboard
    // to one window of a focus grab when it starts (the panel or a bar, its pick), so
    // with the grab on, typing only worked after the mouse moved onto the phone. The
    // Apps screen has no grab: it takes the keyboard Exclusive (see keyboardFocus
    // below) and `catcher` (further down) closes it when you click anywhere else.
    //
    // Not while the cheatsheet board is up either: it holds the keyboard Exclusive on
    // its own full-screen window, which is not in `grabList`, so with the grab on the
    // compositor counted every press on the phone as focus leaving the grab and the
    // phone closed itself. Without the grab the phone just works over the board (it is
    // drawn above it, see `coverCheat`); the board's own click-away still closes the
    // board, and the grab comes back when the board is gone.
    readonly property bool grabWanted: (open || settingsOpen) && win.visible && !PanelImages.busy
                                       && !root.useCatcher && !root.coverCheat

    onGrabWantedChanged: {
        if (grabWanted) {
            grabDelay.restart()
        } else {
            grabDelay.stop()
            grab.active = false
        }
    }

    Timer {
        id: grabDelay
        interval: 80
        onTriggered: grab.active = root.grabWanted
    }

    // The wallpaper folder chooser (WallpaperService.pickFolder) is a window of its
    // own: the phone steps aside while it is open (on the Wallpapers or the Settings,
    // where the button is), so the dialog is not under it and gets the keyboard.
    // WallpaperService opens the same screen again afterwards.
    Connections {
        target: WallpaperService

        function onFolderPickingChanged() {
            if (WallpaperService.folderPicking && (root.wallpapersOpen || root.settingsOpen))
                root.close()
        }
    }

    // Same for the Windows cursor chooser (Settings -> Desktop -> Icons & cursor);
    // IconCursorService opens the Settings again afterwards.
    Connections {
        target: IconCursorService

        function onPickingChanged() {
            if (IconCursorService.picking && root.settingsOpen)
                root.close()
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: root.grabList
        onCleared: {
            // Not a click away: the focus moved while the phone was turning
            // back from the Settings. Keep the panel, and take hold again.
            if (root.turningBack || stage.flipping) {
                grab.active = false
                grabDelay.restart()
                return
            }
            root.close()
        }
    }

    // ===== click away, for the Apps screen =====
    // A transparent window over the whole screen, under the phone: any click on it
    // closes the launcher (the click itself is used up). It sits on the Top layer and
    // the phone's window is on Overlay while Apps is up, so the phone is always above it.
    readonly property bool useCatcher: open && launching

    PanelWindow {
        id: catcher

        screen: root.targetScreen
        visible: root.useCatcher && win.visible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sekaipop-quickpanel-clickaway"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: {
                console.log("sekaipop click-away: pressed on the click-away window")
                root.close()
            }
        }
    }

    // ===== the hot edge =====
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: hot

            required property var modelData

            screen: modelData
            // With the bar on the bottom edge the strip lies over the bar's own bottom
            // 4 px; Bar.qml cuts that spot out of its input region (hotCut) so the
            // pointer reaches this window there. The notification bell opens the panel too.
            visible: root.hotEdge
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors {
                bottom: true
            }
            implicitWidth: root.hotWidth
            implicitHeight: root.hotHeight

            // Only fires on a fresh arrival: the mouse has to leave the
            // strip before it can open the panel again.
            property bool armed: true

            Item {
                anchors.fill: parent

                HoverHandler {
                    onHoveredChanged: {
                        root.hotHovering = hovered
                        if (!hovered) {
                            hot.armed = true
                            dwell.stop()
                        } else if (root.open || root.settingsOpen || Date.now() < root.hotBlockedUntil) {
                            hot.armed = false
                        } else if (hot.armed) {
                            dwell.restart()
                        }
                    }
                }
            }

            Timer {
                id: dwell
                interval: Math.max(1, root.hotDwell)
                onTriggered: {
                    hot.armed = false
                    if (root.hotPeek)
                        root.peekOn(hot.modelData)
                    else
                        root.openOn(hot.modelData)
                }
            }

            // A click on the strip while the tip is peeking out over it opens
            // the phone too (whichever of the two windows is on top there).
            TapHandler {
                enabled: root.peekUp && !root.open
                onTapped: root.claimPeek()
            }
        }
    }

    // ===== the panel =====
    PanelWindow {
        id: win

        screen: root.targetScreen
        visible: root.up || stage.lift < stage.hiddenLift || root.settingsShown
        color: "transparent"

        // Sits on the bottom edge, centered (no left / right anchor), and
        // stays there whichever edge the bar is on. With the bar on the
        // bottom edge the phone comes up in front of it rather than from
        // above it. Two windows on the same layer have no guaranteed
        // stacking order, so in that case the phone goes one layer up
        // (the Overlay layer, same as the OSD) to be sure it is drawn
        // over the bar; with the bar anywhere else it stays on the
        // normal panel layer as before.
        exclusionMode: ExclusionMode.Ignore
        // The Settings (like they always were) go over everything, fullscreen
        // windows included.
        // Also while Apps is up: the click-away window (`catcher`) is on Top, so the phone
        // must be above it.
        // Also while Edit Desktop is on: its shelf and guides windows are on Overlay, and
        // the phone is opened after them, so on the same layer it is drawn over them.
        WlrLayershell.layer: (BarPositionService.position === "bottom" || root.settingsShown
                              || root.useCatcher || root.coverCheat
                              || EditMode.active) ? WlrLayer.Overlay
                                                  : WlrLayer.Top
        anchors {
            bottom: true
        }

        // The window reaches `bleed` px *past* the bottom of the screen
        // (a negative bottom margin, and the same amount added to
        // implicitHeight below, so the phone sits exactly where it did).
        // In a screen recording the bottom of the phone stopped ~7px short
        // of the screen edge for a few frames at the top of the bounce,
        // with the desktop showing under it: the timing (starts ~170ms
        // in, peaks ~230ms, gone by ~350ms) matches the compositor's own
        // layer-open animation overshooting, i.e. the whole surface being
        // lifted a few px off the edge, which nothing inside the window
        // can fix. With the surface extending past the edge, a lift of up
        // to `bleed` px still leaves it covering the screen's last row.
        // 4% of the part that shows (so it grows with a bigger monitor /
        // scale, where the lift would too), never under 24px.
        readonly property real bleed: Math.max(24, Math.ceil((topRoom + shownHeight) * 0.04))
        margins.bottom: -Math.ceil(bleed)
        WlrLayershell.namespace: "sekaipop-quickpanel"

        // The panel never wants keyboard input for itself (every other
        // tile is a click or a drag) — except the Wi-Fi password field
        // in NetworkDialog.qml, the one text entry anywhere in the Quick
        // Panel. OnDemand rather than Exclusive (what Overview.qml
        // uses for its always-visible search box): it only actually
        // takes the keyboard while that field itself holds focus, so
        // typing anywhere else on the desktop is unaffected the rest of
        // the time the panel's open.
        // The Settings take it too (Escape, the arrow keys, 1-7).
        // The Apps screen's search box and typing a letter on Quick take it too
        // (Settings > General > Quick Panel > Type to search).
        //
        // The Apps screen (the app launcher) is the exception: it is a search box
        // that must work the moment it opens, wherever the mouse is. OnDemand only
        // hands the keyboard over once the compositor focuses the window (pointer
        // over it / a click), so with the mouse elsewhere nothing could be typed.
        // While Apps is up it takes the keyboard Exclusive, like the Overview.
        // (The keybinds panel records combinations without it: the focus grab already
        // keeps the keyboard on the phone, and Exclusive would clear the grab,
        // which closes the phone.)
        WlrLayershell.keyboardFocus: (root.open && root.launching) ? WlrKeyboardFocus.Exclusive
                                   : (panelFace.networkDialogOpen || root.settingsOpen || root.turningBack
                                      || root.phoneKeysWanted) ? WlrKeyboardFocus.OnDemand
                                                               : WlrKeyboardFocus.None

        // Only the part of the phone that shows, plus the Power rail
        // beside it, takes the mouse; the empty room around them (for
        // the bounce and the tilt) lets clicks through to what's below.
        // (The Settings phone's own rectangle too, see setHit.)
        mask: Region {
            item: hitRect
            Region { item: railHost }
            Region { item: setHit }
        }

        // Click away, from inside the phone's own window. On some setups the
        // compositor keeps the pointer on the window that holds the keyboard
        // Exclusive (the Apps screen does), so a click beside the phone never
        // reaches `catcher`: it arrives here instead, at a place far outside
        // this small window. This area is far bigger than the window and sits
        // under everything; a press that is not on the phone, or the rail beside
        // it, closes the launcher.
        MouseArea {
            id: awayArea
            enabled: root.useCatcher
            x: -20000
            y: -20000
            width: 40000
            height: 40000
            z: -1000
            acceptedButtons: Qt.AllButtons

            function over(item, px, py) {
                const p = awayArea.mapToItem(item, px, py)
                return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height
            }

            onPressed: mouse => {
                if (over(hitRect, mouse.x, mouse.y) || over(railHost, mouse.x, mouse.y)
                        || over(setHit, mouse.x, mouse.y)) {
                    mouse.accepted = false
                    return
                }
                console.log("sekaipop click-away: pressed beside the phone (panel window)")
                root.close()
            }
        }

        // This monitor's scale (scale.json / services/ShellScale.qml).
        readonly property real uiScale: ShellScale.forScreen(root.targetScreen)

        // Shrink to fit the screen's height (never grow past maxScale) —
        // that is `natural`, and at a scale of 1 it is the whole answer.
        // The monitor's scale multiplies it, so 1.25 makes the phone
        // 25% bigger and 0.8 makes it 20% smaller, except that a phone
        // made bigger still may not outgrow the screen: `cap` is the size
        // at which the window (headroom + the part of the phone that
        // shows, or the Power rail if that reaches lower) would just
        // touch the bottom of the bar. Built only from static numbers
        // (never from `fit` itself) so it can't loop.
        readonly property real fit: {
            const h = root.targetScreen ? root.targetScreen.height : 1080
            const room = h - root.barHeight - 4 - root.edgeMargin - root.headroom
            const natural = Math.max(0.3, Math.min(root.maxScale, room / phone.implicitHeight))
            const tall = phone.swing.top + Math.max(
                phone.implicitHeight * Math.min(1, Math.max(0.2, root.peekEff)), railMaxY)
            const cap = (h - (root.barHeight + root.headroom) * uiScale) / Math.max(1, tall)
            return Math.max(0.3, Math.min(natural * uiScale, Math.max(natural, cap)))
        }

        // Room needed left of the phone's *screen* center (so the screen
        // — not the whole tilted body, side wall and all — is what's
        // centered against the rail on the other side), wide enough that
        // the phone, turned as far as it goes while coming out or going
        // back, isn't cut off by the window's edge.
        // 2D: nothing swings out any more, so the room on the right (the Power rail) would
        // pull the phone off the middle of the monitor. The left gets the same room as the
        // right instead (empty window, it takes no clicks), so the phone's screen sits in
        // the exact middle.
        readonly property real leftExtent: root.flat2d
            ? Math.max((phone.screenCenterX + phone.swing.left) * fit, rightExtent)
            : (phone.screenCenterX + phone.swing.left) * fit

        // Where the Power rail sits in the *phone's own raw design
        // coordinates* — the same 0..faceWidth x 0..faceHeight frame
        // QuickPanelFace.qml's buttons use — just past the right edge of
        // the face (`railGap` past faceWidth), starting level with the
        // the old header Power button's row (`railRawY` matches its y).
        readonly property real railRawX: phone.faceWidth + root.railGap
        // (2D: the flat design starts the column higher, level with the banner's lower part.)
        readonly property real railRawY: root.flat2d ? 197 : 276

        // Where the rail's four corners land, and so how much window room
        // it needs — worked out, like phone.swing just above, from the
        // phone's *static* config (its resting yaw/pitch/roll plus the
        // full tiltYaw/tiltPitch/tiltRoll turn, sampled at the same
        // k = 1, 0.5, -0.4 the elastic entrance bounce actually reaches)
        // rather than from phone.drawBase. drawBase carries the *live*
        // tilt — it changes every single frame of the open/close
        // animation — and implicitWidth/implicitHeight below depend on
        // railMaxX/railMaxY, so computing them from drawBase meant
        // resizing the window itself every frame of every open and
        // close: a real Wayland surface resize, not just a redraw, and
        // the actual cause of the severe stutter showing/hiding the
        // panel picked up. phone.matrix() (used for the rail's own
        // on-screen transform below) still reads the live drawBase —
        // that part is a cheap GPU transform on an already-sized
        // surface, not a resize, so it's fine for it to track the
        // animation exactly; this box just reserves the room for it
        // up front, once, the same way swing does for the body.
        readonly property var railStaticBounds: {
            // Pills are anchorRight now (see QuickToggle.qml / PowerMenu's
            // pillFixedRight): the RIGHT edge is what's pinned, and a
            // hovered pill's shadow spills out to the LEFT of it instead
            // of the right. So the reserved box hangs off pillFixedRight
            // going left by the full pillWidth, not off railRawX going
            // right by it.
            const x1 = railRawX + powerRail.pillFixedRight
            const x0 = x1 - powerRail.pillWidth
            const y0 = railRawY, y1 = railRawY + powerRail.implicitHeight
            let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9
            for (const k of [1, 0.5, -0.4]) {
                const b = PM.baseFor(phone.faceWidth, phone.faceHeight, phone.thickness,
                                     phone.yaw + root.tiltYaw * k,
                                     phone.pitch + root.tiltPitch * k,
                                     phone.roll + root.tiltRoll * k,
                                     phone.perspective, phone.pose)
                for (const c of [[x0, y0], [x1, y0], [x0, y1], [x1, y1]]) {
                    const p = PM.apply(b, c[0], c[1], 0)
                    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x)
                    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y)
                }
            }
            return { minX: minX, maxX: maxX, minY: minY, maxY: maxY }
        }
        readonly property real railMinX: railStaticBounds.minX
        readonly property real railMaxX: railStaticBounds.maxX
        readonly property real railMinY: railStaticBounds.minY
        readonly property real railMaxY: railStaticBounds.maxY

        // Room needed to the right: whichever reaches further out, the
        // phone's own tilted body (with its swing) or the tilted rail —
        // the yaw tips things further right than a flat width would
        // suggest, so this can't just add the rail's plain width anymore.
        readonly property real rightExtent: (Math.max(phone.implicitWidth + phone.swing.right, railMaxX)
                                             - phone.screenCenterX) * fit

        // Room above the resting spot for the bounce (and for the turned
        // phone's top corner). Assumes the rail's own projected top
        // (railMinY) never lands above y = 0 for reasonable railRawY /
        // railGap values — true for the defaults above; push this out
        // further if you change them enough to flip that.
        readonly property real topRoom: root.headroom * uiScale + phone.swing.top * fit

        // The part of the phone that shows, and so how tall the window is:
        // the rest is below the bottom edge of the screen. Tall enough for
        // the rail too, on the rare chance it projects lower than the
        // phone's own peek cutoff.
        readonly property real shownHeight: Math.max(
            phone.implicitHeight * fit * Math.min(1, Math.max(0.2, root.peekEff)),
            railMaxY * fit)

        // Where the bottom of the monitor cuts the phone off, in the flat
        // 654x1214 design's own y coordinates (the ones QuickPanelFace.qml
        // is drawn in) at design column x. The phone is posed in 3D and
        // only `peek` of it shows, so this is NOT simply peek * faceHeight:
        // it's found by working out which design row lands on the cutoff
        // line. The cutoff is level on the monitor but slanted on the face
        // (the tilt makes it lower on the left than on the right), so it
        // depends on x. QuickPanelFace uses the two ends below to size the
        // notification list so it runs right down to the screen edge and
        // scrolls instead of its lower cards hanging below where you can't
        // reach them. Static on purpose (resting pose, not the live
        // drawBase) for the same reason as railStaticBounds above.
        //
        // `extraPx` is how far (px on screen) the phone is raised above
        // its resting spot: the monitor edge then reaches that much
        // further down the face (see faceRevealLeft below).
        //
        // `turn` is how far the phone is still turned toward its pocket
        // pose (stage.tilt: 0 = upright, the default). Only the reveal
        // below needs it — see faceRevealLeft.
        function faceCutoffAt(x, extraPx, turn) {
            const k = turn || 0
            const m = PM.baseFor(phone.faceWidth, phone.faceHeight, phone.thickness,
                                 phone.yaw + root.tiltYaw * k,
                                 phone.pitch + root.tiltPitch * k,
                                 phone.roll + root.tiltRoll * k,
                                 phone.perspective, phone.pose)
            const Y = (shownHeight + (extraPx || 0)) / fit
            const den = Y * m[13] - m[5]
            if (Math.abs(den) < 1e-9)
                return phone.faceHeight
            return Math.min(phone.faceHeight, (m[4] * x + m[7] - Y * (m[12] * x + m[15])) / den)
        }
        readonly property real faceCutoffLeftY: faceCutoffAt(0)
        readonly property real faceCutoffRightY: faceCutoffAt(phone.faceWidth)

        // The pull-out overshoots: for a moment the phone is `bounce` px
        // higher than its resting spot (and the pull-up before leaving
        // does the same), which slides the part of the face that is
        // normally below the monitor edge into view. The notification
        // list only used to run down to the *resting* cutoff, so during
        // that moment it ended in a visible cut with blank card below it.
        // This is how many design units further down the face the edge
        // reaches at the top of the bounce (the lower, left end is the
        // largest); QuickPanelFace keeps the list going that far.
        //
        // The phone is not quite upright at the top of that bounce: the
        // elastic tilt is still ~5-7% of the way back (and the pull-up
        // before leaving is ~9% tilted at its peak). That small turn
        // lets the monitor edge reach a few design units further down
        // the left side than the upright pose does (the roll lowers the
        // left edge), which left the list ending in a thin visible cut
        // at the very top of the bounce. So the reach is the largest of
        // the upright one and a few slightly-turned ones (0..15%),
        // which covers both bounces with room to spare. Over-reaching
        // is harmless: the extra length sits under the monitor edge at
        // rest.
        readonly property real faceRevealLeft: {
            let reach = faceCutoffLeftY
            for (const k of [0, 0.05, 0.1, 0.15])
                reach = Math.max(reach, faceCutoffAt(0, root.bounce, k))
            return Math.max(0, reach - faceCutoffLeftY)
        }

        // How far down (px on screen) the phone rests when it only came up
        // to alert, so that just the notification card and a little of the
        // phone under it (alertMargin) show. The card is drawn at y 84..
        // 196 (+ its 4px shadow) across x 47..607 of the flat design (see
        // QuickPanelFace's alertCard); the tilt makes its lower-left
        // corner land lower on the monitor than the right one, so the
        // lower of the two is what has to clear the screen edge. Static
        // pose, same reason as faceCutoffAt above.
        readonly property real alertLift: liftShowing(204, root.alertMargin * uiScale)

        // The same for the hot edge's peek (root.peekUp): only down to
        // root.peekTipY of the face shows, the clock and date.
        readonly property real peekLift: liftShowing(root.peekTipY, 0)

        // How far down the phone rests so that its face shows down to design
        // y `faceY` (across the alert card's width, x 47..607), plus `margin`
        // px on screen.
        function liftShowing(faceY, margin) {
            const m = PM.baseFor(phone.faceWidth, phone.faceHeight, phone.thickness,
                                 phone.yaw, phone.pitch, phone.roll,
                                 phone.perspective, phone.pose)
            let low = 0
            for (const x of [47, 607])
                low = Math.max(low, PM.apply(m, x, faceY, 0).y)
            return Math.max(0, shownHeight - (low * fit + margin))
        }

        // Nothing left to see: forget the low alert spot so the next
        // opening is the usual one.
        onVisibleChanged: {
            if (!visible) {
                root.alertMode = false
                root.peekMode = false
                // Gone: the next time it comes up it is Quick again, with an empty
                // search box.
                routeAnim.stop()
                routePrep.stop()
                root.setRoute(PR.open("quick"))
                root.routeK = 0
                appsFace.reset()
            }
        }

        // ===== room for the turn into the Settings =====
        readonly property real monitorW: root.targetScreen ? root.targetScreen.width : 1920
        readonly property real monitorH: root.targetScreen ? root.targetScreen.height : 1080
        readonly property real baseW: Math.ceil(leftExtent + rightExtent)
        readonly property real baseH: Math.ceil(topRoom + shownHeight) + Math.ceil(bleed)

        // The Settings phone's scale: the Quick Panel's own (so a pill is the
        // same size on screen in both), never so big that it wouldn't fit the
        // monitor.
        readonly property real sFit: {
            const cap = Math.min((monitorW - 24) / (2 * sstage.halfW * sstage.grow),
                                 (monitorH - 24) / (2 * sstage.halfH * sstage.grow))
            return Math.max(0.3, Math.min(fit, cap))
        }

        // How far the phone reaches during the turn: `u` up from the window's
        // bottom edge, `halfW` sideways from the middle of the monitor. Found
        // by walking the whole turn (FlipMath.js, a little before its start and
        // past its end for the wind-up and the overshoot) and asking PhoneMath
        // where both bodies' outlines land at each step, so the window is as big
        // as the move needs and no bigger.
        readonly property var flipRoom: {
            const sp = sstage.phone
            const qcx = phone.screenCenterX, qcy = phone.screenCenterY
            const scx = sp.screenCenterX, scy = sp.screenCenterY
            // Where the Quick Panel's screen centre stands (x from the middle of
            // the monitor, u up from the window's bottom) and where the
            // Settings' will.
            const x0 = leftExtent - baseW / 2
            const u0 = baseH - (topRoom + qcy * fit)
            const u1 = Math.ceil(bleed) + monitorH / 2
            let needU = u0, needHalfW = Math.abs(x0)
            for (let i = -4; i <= 24; i++) {
                const p = i / 20
                const A = FM.quickScale(p, fit, sFit, root.flipDip)
                const As = A / FM.SIZE_RATIO
                const x = Math.abs(x0 * (1 - p))
                const u = u0 + (u1 - u0) * p
                const yw = phone.yaw + (sstage.yaw - phone.yaw) * p
                const pt = phone.pitch + (sstage.pitch - phone.pitch) * p
                const bq = PM.boundsFor(phone.faceWidth, phone.faceHeight, phone.thickness, phone.cornerRadius,
                                        yw, pt, phone.roll + FM.quickRoll(p), phone.perspective, phone.pose)
                const bs = PM.boundsFor(sp.faceWidth, sp.faceHeight, sp.thickness, sp.cornerRadius,
                                        yw, pt, sp.roll + FM.settingsRoll(p), sp.perspective, sp.pose)
                needU = Math.max(needU, u + (qcy - bq.minY) * A, u + (scy - bs.minY) * As)
                needHalfW = Math.max(needHalfW,
                                     x + Math.max(qcx - bq.minX, bq.maxX - qcx) * A,
                                     x + Math.max(scx - bs.minX, bs.maxX - scx) * As)
            }
            // The Settings standing in the middle, popped to their largest.
            needU = Math.max(needU, u1 + sstage.halfH * sFit * sstage.grow)
            needHalfW = Math.max(needHalfW, sstage.halfW * sFit * sstage.grow)
            // A window taller or wider than the monitor has nothing more to show.
            return { u: Math.min(needU + 4, monitorH + Math.ceil(bleed)),
                     halfW: Math.min(needHalfW + 4, monitorW / 2) }
        }
        readonly property real padX: Math.max(0, Math.ceil(flipRoom.halfW - baseW / 2))
        readonly property real padTop: Math.max(0, Math.ceil(flipRoom.u) - baseH)

        // The middle of the monitor, in the window's own coordinates: the
        // window is centred on the monitor and its bottom edge is `bleed` below
        // the monitor's.
        readonly property real setMidX: implicitWidth / 2
        readonly property real setMidY: implicitHeight - Math.ceil(bleed) - monitorH / 2

        // 2D: a whole, even number of device-independent pixels each way, so the
        // compositor centres it on whole pixels and the phone can be put on the pixel grid
        // (see `stage.direct`). 2.5D keeps its plain sizes.
        readonly property real dpr: root.targetScreen ? root.targetScreen.devicePixelRatio : 1
        implicitWidth: root.flat2d ? 2 * Math.ceil((baseW + 2 * padX) / 2) : baseW + 2 * padX
        implicitHeight: root.flat2d ? Math.ceil(baseH + padTop) : baseH + padTop

        // Keys while the Settings are up: 1-7 open a page; inside a page Left /
        // Right (or Up / Down, or Tab / Shift+Tab) move between the pages;
        // Escape (or Backspace) goes back to the menu of tiles, and from there
        // Escape turns the phone back into the Quick Panel.
        FocusScope {
            id: keys
            anchors.fill: parent
            focus: root.settingsOpen

            Keys.onPressed: event => {
                if (!root.settingsOpen) {
                    root.quickKeyPressed(event)
                    return
                }
                // The gallery has the keyboard itself; if it was missed, put it
                // right and let the next key reach it.
                if (root.landscape === "wallpapers") {
                    root.focusLandscape()
                    return
                }
                const face = sstage.face
                if (event.key === Qt.Key_Escape) {
                    if (face.hub)
                        root.settingsBack()
                    else
                        face.showHub()
                } else if (event.key === Qt.Key_Backspace) {
                    face.showHub()
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                    face.step(1)
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
                    face.step(-1)
                } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_7) {
                    face.go(event.key - Qt.Key_1)
                } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                           && event.text.length === 1 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127) {
                    face.typeIntoSearch(event.text)
                } else {
                    return
                }
                event.accepted = true
            }
        }

        Item {
            id: stage
            anchors.fill: parent

            // How far (px) the phone sits below its resting spot: 0 at
            // rest, hiddenLift once it's completely off the screen edge,
            // negative during the overshoot. The window clips at the
            // screen's edge, so "below" is simply gone.
            property real lift: 100000
            // 1 = turned the way it is in the pocket, 0 = upright.
            property real tilt: 1

            // The turn into the Settings (FlipMath.js): 0 = the Quick Panel,
            // 1 = the Settings phone. Goes a little outside 0..1 while it
            // winds up and overshoots.
            property real flip: 0
            // The roll the turn rings out with when it lands (see `ring`), in
            // degrees; added to both phones' rolls.
            property real wob: 0
            // The Settings coming up on their own, with no Quick Panel to turn
            // out of (SettingsStage.qml): at rest 1 / 1 / 0.
            property real sPop: 1
            property real sAlpha: 1
            property real sTilt: 0

            // On its way (or about to be: flipPrep).
            readonly property bool flipping: flipPrep.running || flipAnim.running

            // The Quick Panel's phone takes the mouse (and the click-away's
            // eyes) unless the Settings have settled in its place.
            readonly property bool quickInput: !(root.settingsOpen && flip >= 1 && !flipping)

            // The Quick Panel's phone during the turn: its size, how
            // opaque it is, and where its screen's middle is, going from where
            // it stands to the middle of the monitor (this item's coordinates).
            // The Settings phone follows the same path (flipCX / flipCY).
            readonly property real quickScale: FM.quickScale(flip, win.fit, win.sFit, root.flipDip)
            readonly property real quickAlpha: FM.quickAlpha(flip)
            readonly property real quickCX: restRect.x + phone.screenCenterX * win.fit
            readonly property real quickCY: restRect.y + phone.screenCenterY * win.fit
            readonly property real flipCX: quickCX + (win.setMidX - quickCX) * flip
            readonly property real flipCY: quickCY + (win.setMidY - quickCY) * flip

            // How far the phone rests below its usual spot: 0 for the
            // normal panel, alertLift while it's only up to show a
            // notification. Animated (only while it's on screen) so
            // touching the alert phone slides it up to the full panel;
            // while hidden it just snaps.
            property real rise: root.lowLift
            Behavior on rise {
                enabled: win.visible
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.OutCubic
                }
            }

            // The buzz (see buzzAnim): progress 0..1, and the shake that
            // works out to, in px. Both 0 when it isn't buzzing.
            property real buzzT: 0
            readonly property real buzzX: buzzOffset(0)
            readonly property real buzzY: buzzOffset(1) * 0.35

            // ===== sharpness (2D) =====
            // Facing front (which is the whole time except the turn into the Settings): the screen
            // is drawn as a whole number of texels per device pixel and put on a whole device pixel
            // (PhoneBody `faceDirect`), exactly as the Wallpapers phone does (WallpaperStage.qml
            // `direct`). That is what makes the text and icons sharp and the banner's corner smooth.
            // It holds while it moves too (the pull-out, the bounce, the buzz, the way out): nothing
            // is tilted or resized then, only moved up and down, and the snap below is worked out
            // from where it is every frame, so every frame lands on the pixel grid and the motion
            // just steps by whole pixels. (The 2.5D pipeline resamples a flat front twice, which is
            // fine tilted but soft on a front that faces the screen.)
            readonly property bool direct: root.flat2d && phone.flat && flip === 0 && wob === 0
            // The screen's middle in this window (what phone.x / phone.y below put it on), and so
            // where the front's top-left lands on the monitor, in device pixels.
            readonly property real faceMidX: buzzX + flipCX
            readonly property real faceMidY: lift + rise + buzzY + flipCY
            readonly property real faceLeftDev: ((win.monitorW - win.implicitWidth) / 2 + faceMidX) * win.dpr
                                                - phone.directW / 2
            readonly property real faceTopDev: (win.monitorH + Math.ceil(win.bleed) - win.implicitHeight + faceMidY) * win.dpr
                                               - phone.directH / 2
            readonly property real snapX: direct ? (Math.round(faceLeftDev) - faceLeftDev) / win.dpr : 0
            readonly property real snapY: direct ? (Math.round(faceTopDev) - faceTopDev) / win.dpr : 0

            function buzzOffset(axis) {
                if (buzzT <= 0 || root.buzzAmount === 0)
                    return 0
                const total = root.buzzPulses * root.buzzBurstMs
                            + Math.max(0, root.buzzPulses - 1) * root.buzzGapMs
                let t = buzzT * total          // ms into the whole buzz
                const period = root.buzzBurstMs + root.buzzGapMs
                const local = t % period       // ms into this burst
                if (local >= root.buzzBurstMs)
                    return 0                   // in the quiet gap
                const k = local / root.buzzBurstMs
                // Full strength at the start of each burst, easing off.
                const env = 1 - 0.55 * k * k
                const phase = 2 * Math.PI * root.buzzHz * local / 1000
                return root.buzzAmount * env * Math.sin(phase + axis * 1.3)
            }

            // Where the pull-out starts: the phone's top edge just under the screen's bottom.
            readonly property real enterFrom: win.shownHeight + 2

            // Where the phone ends when it is put away, and the window is let go of. This
            // used to be `enterFrom`, i.e. the window was unmapped the moment the phone's
            // top edge touched the screen's bottom. Two things then showed the upper part
            // of the phone cut off instead of sliding all the way down:
            //  - the way out is an ease-in, so at the end the phone moves ~100+ px per
            //    frame (more in 2D, which shows ~10% more of the phone): the last frame
            //    that was drawn still held the top strip of the phone, and that frame is
            //    what stayed on screen (and what the compositor's own layer-close
            //    animation played on) when the window went;
            //  - the phone is rolled back into its pocket pose on the way out in 2.5D, which
            //    raises one top corner above the unrotated top edge, so that corner was
            //    still on screen when `lift` reached the old target.
            // Now the phone goes on for `exitTail` more px below the screen (the window
            // is clipped at the screen's edge, so nothing shows) and the frames drawn
            // there are empty: the last frame the window shows is a clear one.
            readonly property real exitTail: Math.ceil(win.shownHeight * 0.3 + phone.swing.top * win.fit)
            readonly property real hiddenLift: enterFrom + exitTail

            // `lift` is a plain pixel count, but hiddenLift is as big as
            // the window, which follows this monitor's scale (and which
            // monitor the panel is on). A phone that was put away when
            // the window was small therefore sat at the *old* hiddenLift;
            // make the window bigger (scaling 80% -> 100%) and that old
            // number is suddenly less than the new one, which is exactly
            // what `win.visible` reads as "still on its way out" — so the
            // window came back and showed the phone. While it's put away
            // and nothing is animating, keep it at the current
            // hiddenLift so a resize can't leave it stranded above it.
            //
            // Not while `lift` still has its start-up value (100000 = never
            // shown, far off the screen already; onUpChanged pulls it down
            // to hiddenLift the first time the phone comes up). The first
            // hiddenLift comes out while win.visible is being worked out,
            // and writing `lift` from in here - which win.visible reads -
            // is what Qt logged as "Binding loop detected for property
            // visible" on every start.
            onHiddenLiftChanged: {
                if (stage.lift >= 100000)
                    return
                if (!root.up && !exitAnim.running && !exitDelay.running)
                    stage.lift = stage.hiddenLift
            }

            // Where the pull-up before leaving peaks, and how long it takes.
            property real exitPeak: 0
            property real exitPeakMs: 130

            // What takes the mouse: restRect, less the empty strip above
            // the phone while it's sitting low for an alert, so clicks
            // there still reach the windows underneath.
            Item {
                id: hitRect
                readonly property real drop: root.lowLift
                x: restRect.x
                y: restRect.y + drop
                // (The side buttons stand out of the right edge, past the padded box
                // (2D: the flat Power button, bigger), so the box takes the mouse that
                // far too.)
                width: stage.quickInput ? restRect.width + (root.flat2d ? phone.powerStick : phone.buttonStick) * win.fit : 0
                height: stage.quickInput ? Math.max(0, restRect.height - drop) : 0
            }

            // Click away inside hitRect: hitRect is the box around the tilted phone, so
            // its corners are empty, and a press there landed on this window and did
            // nothing (issue #47). Under everything; a press nothing on the phone took
            // reaches it, and closes the panel unless it is on the phone's own shape
            // (PhoneBody.outlinePoly, a few units of slack for the antialiased edge).
            MouseArea {
                id: besidePhone

                x: hitRect.x
                y: hitRect.y
                width: hitRect.width
                height: hitRect.height
                z: -100
                enabled: root.open
                acceptedButtons: Qt.AllButtons

                function overPhone(px, py) {
                    const p = besidePhone.mapToItem(phone, px, py)
                    return PM.insideConvex(phone.outlinePoly, p.x, p.y, 3)
                }

                onPressed: mouse => {
                    if (overPhone(mouse.x, mouse.y)) {
                        mouse.accepted = false
                        return
                    }
                    console.log("sekaipop click-away: pressed beside the phone, inside its box")
                    root.close()
                }
            }

            // The peeking tip (root.peekUp): over everything on it, so a click
            // opens the phone instead of pressing a tile you can barely see, and
            // its hover keeps the peek up (peekLeave).
            MouseArea {
                id: peekTouch

                x: hitRect.x
                y: hitRect.y
                width: hitRect.width
                height: hitRect.height
                z: 1000
                enabled: root.peekUp && !root.open
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                cursorShape: Qt.PointingHandCursor
                onPressed: root.claimPeek()
            }

            // Where the Settings phone stands when it's up, in the middle of the
            // monitor (it takes the mouse there, from the moment it starts
            // turning in until it has gone).
            Item {
                id: setHit
                x: win.setMidX - sstage.phone.screenCenterX * win.sFit
                y: win.setMidY - sstage.phone.screenCenterY * win.sFit
                width: root.settingsOpen ? sstage.phone.implicitWidth * win.sFit : 0
                height: root.settingsOpen ? sstage.phone.implicitHeight * win.sFit : 0
            }

            // The part of the phone that shows at rest. The window ends
            // at the screen's bottom edge, so whatever hangs below this
            // rectangle is simply off the screen.
            Item {
                id: restRect

                x: win.padX + win.leftExtent - phone.screenCenterX * win.fit
                y: win.padTop + win.topRoom
                width: phone.implicitWidth * win.fit
                height: win.shownHeight

                PhoneBody {
                    id: phone

                    // Resting pose: PhoneBody's own 33 / 18, or straight on in 2D.
                    // The Power button is the phone's own side button (it used to be a
                    // key in the header row): the upper side button on the 2.5D phone, a
                    // small button out of the right edge on the 2D one.
                    powerButton: true
                    powerOn: panelFace.powerMenuOpen
                    onPowerClicked: panelFace.togglePowerMenu()
                    // `flat` drops the side wall (and its layer) while it is at rest
                    // facing front; it comes back for the turn into the Settings.
                    yaw: root.flat2d ? 0 : 33
                    pitch: root.flat2d ? 0 : 18
                    flat: root.flat2d && stage.flip === 0 && !stage.flipping
                    // The flat design has a plain rim and a plain notch.
                    plain: root.flat2d
                    // Up and still: on the pixel grid (`stage.direct`). Moving: the same offscreen
                    // pictures as the 2.5D phone (supersampled, mipmapped), so it is as sharp in the
                    // pull-out and the bounce as that one is.
                    faceDirect: stage.direct

                    // Standing where it always does until the Settings turn it:
                    // then its screen's middle (flipCX / flipCY) travels to the
                    // middle of the monitor and its size follows the turn
                    // (all of it the plain old numbers while stage.flip is 0).
                    x: stage.buzzX + stage.flipCX - restRect.x - phone.screenCenterX * stage.quickScale + stage.snapX
                    y: stage.lift + stage.rise + stage.buzzY + stage.flipCY - restRect.y - phone.screenCenterY * stage.quickScale + stage.snapY
                    transformOrigin: Item.TopLeft
                    scale: stage.quickScale

                    // Gone once the Settings have taken its place.
                    opacity: stage.quickAlpha
                    visible: opacity > 0.001
                    enabled: stage.flip === 0 && !stage.flipping

                    // Closed for a while: the phone gives its layer buffers back
                    // (PhoneBody `warm`); they are back before the first frame.
                    windowShown: win.visible

                    // Drawn on the light settings while it moves (and while
                    // it's out of sight, so the first frame of the pull-out
                    // isn't the heavy one); the full-quality ones take over
                    // once it has settled. See PhoneBody's draw quality.
                    //
                    // Separately, PanelActivity.busy (a button press, a
                    // hover glow, a dragged slider) feeds the gentler
                    // `busy` tier instead of `moving`'s: dropping all the
                    // way to the pull-out's settings kept those buttons
                    // smooth but visibly pixelated the frame for
                    // something that small.
                    moving: enterAnim.running || exitAnim.running
                            || exitDelay.running || !win.visible || stage.flipping || ring.running
                            || root.routing
                    busy: PanelActivity.busy

                    // Rolled up to a quarter turn on its way into the Settings:
                    // its picture has to be big enough to hold that.
                    turnRoll: (stage.flipping || (root.ringKeepsLite && ring.running)) ? -90 : 0

                    // Turned while it's coming out of / going into the
                    // pocket. These change what's drawn, not the size...
                    // ...and, on the turn into the Settings, rolled a quarter turn
                    // anticlockwise and eased toward the Settings phone's pose.
                    rollOffset: stage.tilt * root.tiltRoll + FM.quickRoll(stage.flip) + stage.wob
                    // (`yawEnd` / `pitchEnd`: the pose the landscape phone lands in. The
                    // Wallpapers land facing straight on, the Settings in their tilt; the
                    // two bodies stay the same picture the whole way round.)
                    pitchOffset: stage.tilt * root.tiltPitch + (sstage.pitchEnd - phone.pitch) * stage.flip + stage.wob * 0.5
                    yawOffset: stage.tilt * root.tiltYaw + (sstage.yawEnd - phone.yaw) * stage.flip

                    // ...but the window has to leave room for how far
                    // that turns it out to the sides.
                    swingRoll: root.tiltRoll
                    swingPitch: root.tiltPitch
                    swingYaw: root.tiltYaw

                    // Draw the screen at the size it ends up on the monitor.
                    // Don't raise this to the plain pixel ratio: the GPU
                    // then shrinks a bigger texture without mipmaps and
                    // the edges come out jagged (see PhoneBody.renderScale).
                    renderScale: win.fit * (root.targetScreen ? root.targetScreen.devicePixelRatio : 1)

                    QuickPanelFace {
                        id: panelFace

                        // The Apps screen takes its place (a short vertical slide).
                        opacity: 1 - FM.smooth(0.0, 0.7, root.routeK)
                        y: -34 * root.routeK
                        visible: opacity > 0.001
                        enabled: root.faceScreen === "quick"
                        // Same on-screen texel density the phone itself is
                        // drawn at (see PhoneBody.renderScale above), for
                        // the face's own masked banner / avatar layers.
                        renderScale: phone.renderScale
                        wallpaperPath: PanelImages.phoneWallpaperFor(root.targetScreen ? root.targetScreen.name : "")
                        bannerSource: PanelImages.banner !== "" ? PanelImages.banner : root.bannerSource
                        avatarSource: PanelImages.avatar !== "" ? PanelImages.avatar : root.avatarSource
                        bannerFraming: PanelImages.banner !== "" ? PanelImages.framingFor("banner") : null
                        avatarFraming: PanelImages.avatar !== "" ? PanelImages.framingFor("avatar") : null
                        wallpaperFraming: PanelImages.phoneMode === "picture" ? PanelImages.framingFor("phone") : null
                        onBannerPickRequested: PanelImages.pick("banner", root.targetScreen ? root.targetScreen.name : "")
                        onAvatarPickRequested: PanelImages.pick("avatar", root.targetScreen ? root.targetScreen.name : "")
                        onBannerFrameRequested: PanelImages.frame("banner", false, root.targetScreen ? root.targetScreen.name : "")
                        onAvatarFrameRequested: PanelImages.frame("avatar", false, root.targetScreen ? root.targetScreen.name : "")
                        onBannerResetRequested: PanelImages.clear("banner")
                        onAvatarResetRequested: PanelImages.clear("avatar")

                        clockText: Qt.formatDateTime(clock.date, SettingsService.flag("time.use24h") ? "HH:mm" : "hh:mmAP")
                        dateText: Qt.formatDate(clock.date, "ddd, d  MMM")
                        userName: root.source.userName
                        hostName: root.source.hostName

                        downloadBps: root.source.downloadBps
                        uploadBps: root.source.uploadBps

                        networkKind: root.source.networkKind
                        networkOn: root.source.networkOn
                        networkDetail: root.source.networkDetail
                        bluetoothOn: root.source.bluetoothOn
                        bluetoothConnected: root.source.bluetoothDevice !== ""
                        bluetoothDetail: root.source.bluetoothDetail
                        microphoneOn: root.source.microphoneOn
                        speakerOn: root.source.speakerOn
                        microphoneVolume: root.source.microphoneVolume
                        speakerVolume: root.source.speakerVolume
                        brightness: root.source.brightness
                        gamma: root.source.gamma
                        keepAwakeOn: root.source.keepAwakeOn
                        notificationsOn: root.source.notificationsOn
                        editing: root.source.editing
                        nightLightOn: root.source.nightLightOn
                        nightLightTemperature: root.source.nightLightTemperature
                        nightLightAuto: root.source.nightLightAuto
                        nightLightAutoFrom: root.source.nightLightAutoFrom
                        nightLightAutoTo: root.source.nightLightAutoTo
                        gameModeOn: root.source.gameModeOn
                        darkModeOn: root.source.darkModeOn
                        darkModeName: root.source.darkModeName
                        easyEffectsOn: root.source.easyEffectsOn
                        warpOn: root.source.warpOn
                        warpConnecting: root.source.warpConnecting
                        warpInstalled: root.source.warpInstalled
                        keyboardOn: root.source.keyboardOn
                        powerProfileName: root.source.powerProfileName
                        musicListening: root.source.musicListening
                        antiFlashbangOn: root.source.antiFlashbangOn
                        antiFlashbangLevel: root.source.antiFlashbangLevel
                        tiles: root.source.tiles
                        tileColumns: root.source.tileColumns
                        notifications: root.notificationSource.entries
                        alertEntry: root.notificationSource.toast
                        alertShown: root.notificationSource.toastActive
                        alertOnly: root.alertUp && !root.open
                        visibleBottomLeft: win.faceCutoffLeftY
                        visibleBottomRight: win.faceCutoffRightY
                        visibleExtra: win.faceRevealLeft

                        wifiNetworks: root.source.wifiNetworks
                        wifiScanning: root.source.wifiScanning
                        wifiManualScanning: root.source.wifiManualScanning
                        wifiConnectingSsid: root.source.wifiConnectingSsid
                        wifiConnectError: root.source.wifiConnectError
                        bluetoothDevices: root.source.bluetoothDevices
                        bluetoothScanning: root.source.bluetoothScanning
                        bluetoothManualScanning: root.source.bluetoothManualScanning
                        bluetoothConnectingAddress: root.source.bluetoothConnectingAddress
                        bluetoothConnectError: root.source.bluetoothConnectError

                        speakerDevices: root.source.speakerDevices
                        microphoneDevices: root.source.microphoneDevices
                        speakerStreams: root.source.speakerStreams
                        microphoneStreams: root.source.microphoneStreams
                        audioDevicesScanning: root.source.audioDevicesScanning
                        audioDevicesManualScanning: root.source.audioDevicesManualScanning
                        audioDeviceSelectingId: root.source.audioDeviceSelectingId

                        onNetworkToggled: root.source.toggleNetwork()
                        onBluetoothToggled: root.source.toggleBluetooth()
                        onMicrophoneToggled: root.source.toggleMicrophone()
                        onSpeakerToggled: root.source.toggleSpeaker()
                        onMicrophoneVolumeMoved: value => root.source.setMicrophoneVolume(value)
                        onSpeakerVolumeMoved: value => root.source.setSpeakerVolume(value)
                        onBrightnessMoved: value => root.source.setBrightness(value)
                        onGammaMoved: value => root.source.setGamma(value)
                        onKeepAwakeToggled: root.source.toggleKeepAwake()
                        onNotificationsToggled: root.source.toggleNotifications()
                        onEditToggled: root.source.toggleEditing()
                        onNightLightToggled: root.source.toggleNightLight()
                        onNightLightTemperatureMoved: kelvin => root.source.setNightLightTemperature(kelvin)
                        onNightLightAutoRequested: on => root.source.setNightLightAuto(on)
                        onNightLightScheduleRequested: (from, to) => root.source.setNightLightSchedule(from, to)
                        onGameModeToggled: root.source.toggleGameMode()
                        onDarkModeToggled: root.source.toggleDarkMode()
                        onEasyEffectsToggled: root.source.toggleEasyEffects()
                        onWarpToggled: root.source.toggleWarp()
                        onKeyboardToggled: root.source.toggleKeyboard()
                        onPowerProfileCycled: root.source.cyclePowerProfile()
                        onMusicRecognitionToggled: root.source.toggleMusicRecognition()
                        onAntiFlashbangToggled: root.source.toggleAntiFlashbang()
                        onTileActionRequested: id => root.source.runTileAction(id)
                        onTileMoveRequested: (from, to) => root.source.moveTile(from, to)
                        onTileResizeRequested: index => root.source.resizeTile(index)
                        onTileRemoveRequested: index => root.source.removeTile(index)
                        onTileAddRequested: id => root.source.addTile(id)
                        onTileColumnsRequested: columns => root.source.setTileColumns(columns)
                        onRefreshRequested: refreshHyprland.running = true
                        // The phone turns into the Settings where it stands.
                        onSettingsRequested: root.openSettings(root.targetScreen)
                        // claim() first: hideToast() makes toastActive false,
                        // and onToastActiveChanged lowers a phone that is only
                        // up for the alert. A click never hit this (its press
                        // had already claimed the phone), but a hover has no
                        // press, so the phone was lowered before it was claimed.
                        onAlertActivated: {
                            // Not in the middle of a press or a swipe on the phone (the
                            // card's hover timer can run out while you drag it away).
                            if (alertTouch.busy)
                                return
                            root.claim()
                            root.notificationSource.hideToast()
                        }
                        onAlertDismissRequested: key => {
                            root.claim()
                            root.notificationSource.dismiss(key)
                            root.notificationSource.hideToast()
                        }
                        // A click on a card of the list: the app's own action (it also
                        // removes the notification, and the phone is put away so the app
                        // it opens is in view); with none, the card is dismissed.
                        onAlertClicked: key => {
                            if (root.notificationSource.activate(key)) {
                                root.notificationSource.hideToast()
                                root.close()
                            } else {
                                root.claim()
                                root.notificationSource.hideToast()
                            }
                        }
                        onNotificationActivated: key => {
                            if (root.notificationSource.activate(key))
                                root.close()
                            else
                                root.notificationSource.dismiss(key)
                        }
                        onNotificationDismissed: key => root.notificationSource.dismiss(key)
                        onNotificationsDismissed: keys => root.notificationSource.dismissMany(keys)
                        onNotificationsCleared: root.notificationSource.clearAll()
                        onPanelCloseRequested: root.close()

                        // A quick (non-forced) list the moment either dialog
                        // opens, so it's not sitting empty waiting for a
                        // manual "Scan"/"Refresh" tap. Also hands the open
                        // state down to QuickSource so wifiLiveRefresh/
                        // bluetoothLiveRefresh can keep polling (the cheap
                        // path, same as this initial call) for as long as
                        // the dialog stays open — same "live" reasoning as
                        // the audio mixer already had.
                        onNetworkDialogOpenChanged: {
                            root.source.networkDialogOpen = networkDialogOpen
                            if (networkDialogOpen)
                                root.source.scanWifi(false)
                        }
                        onBluetoothDialogOpenChanged: {
                            root.source.bluetoothDialogOpen = bluetoothDialogOpen
                            if (bluetoothDialogOpen)
                                root.source.scanBluetooth()
                        }
                        onWifiScanRequested: root.source.scanWifi(true, true)
                        onWifiAdvancedRequested: {
                            root.source.openNetworkSettings()
                            panelFace.networkDialogOpen = false
                            root.close()
                        }
                        onWifiConnectRequested: (ssid, password) => root.source.connectWifi(ssid, password)
                        onWifiDisconnectRequested: ssid => root.source.disconnectWifi(ssid)
                        onBluetoothScanRequested: root.source.scanBluetooth(true)
                        onBluetoothAdvancedRequested: {
                            root.source.openBluetoothSettings()
                            panelFace.bluetoothDialogOpen = false
                            root.close()
                        }
                        onBluetoothConnectRequested: address => root.source.connectBluetoothDevice(address)
                        onBluetoothDisconnectRequested: address => root.source.disconnectBluetoothDevice(address)

                        // Same "quick list the moment it opens" as the two
                        // above — one shared scan covers both sliders'
                        // device lists AND their per-app mixers (see
                        // scanAudioDevices() in QuickSource.qml). Unlike
                        // Wi-Fi/Bluetooth, it also keeps polling every 2s
                        // for as long as this stays open (audioMixerActive)
                        // — apps starting up or finishing is exactly what a
                        // live mixer needs to catch on its own.
                        onAudioDialogKindChanged: {
                            root.source.audioMixerActive = (audioDialogKind !== "")
                            if (audioDialogKind !== "")
                                root.source.scanAudioDevices()
                        }
                        onAudioDeviceScanRequested: root.source.scanAudioDevices(true)
                        onSpeakerDeviceSelected: id => root.source.setDefaultSink(id)
                        onMicrophoneDeviceSelected: id => root.source.setDefaultSource(id)
                        onSpeakerStreamVolumeChanged: (id, value) => root.source.setStreamVolume("sink-input", id, value)
                        onSpeakerStreamMuteToggled: (id, muted) => root.source.setStreamMuted("sink-input", id, muted)
                        onMicrophoneStreamVolumeChanged: (id, value) => root.source.setStreamVolume("source-output", id, value)
                        onMicrophoneStreamMuteToggled: (id, muted) => root.source.setStreamMuted("source-output", id, muted)
                        onSpeakerStreamDragStarted: id => root.source.beginStreamDrag("sink-input", id)
                        onSpeakerStreamDragEnded: id => root.source.endStreamDrag("sink-input", id)
                        onMicrophoneStreamDragStarted: id => root.source.beginStreamDrag("source-output", id)
                        onMicrophoneStreamDragEnded: id => root.source.endStreamDrag("source-output", id)
                    }

                    // The Apps screen (LauncherFace.qml): the same 654x1214 frame,
                    // in the same body. It comes up from a little below while the
                    // Quick screen slides away upward.
                    LauncherFace {
                        id: appsFace

                        opacity: FM.smooth(0.3, 1.0, root.routeK)
                        y: 34 * (1 - root.routeK)
                        visible: opacity > 0.001
                        enabled: root.faceScreen === "apps" && root.open

                        source: root.appSource
                        renderScale: phone.renderScale
                        // Its wallpaper is the one drawn behind the apps.
                        screenName: root.targetScreen ? root.targetScreen.name : ""
                        // Only this much of the phone shows at rest: the bottom
                        // button is laid out above the monitor's edge.
                        visibleBottom: Math.min(win.faceCutoffLeftY, win.faceCutoffRightY)
                        visibleReach: Math.max(win.faceCutoffLeftY, win.faceCutoffRightY) + win.faceRevealLeft
                        clockText: panelFace.clockText
                        dateText: panelFace.dateText
                        downloadBps: root.source.downloadBps
                        uploadBps: root.source.uploadBps

                        onAppActivated: app => {
                            root.close()
                            if (root.appSource)
                                root.appSource.launch(app)
                        }
                        onCloseRequested: root.back()
                        onJumpRequested: n => root.jump(n)
                        // An extra was run or copied (a system action, a command,
                        // a copied colour...): the phone goes away.
                        onDoneRequested: root.close()
                        // The colour eyedropper needs the screen; the phone comes
                        // back on the colour card once a colour is picked.
                        onPickerRequested: root.close()
                        onColorPickedBack: hex => {
                            root.openAppsOn(root.focusedScreen())
                            appsFace.setText("color " + hex)
                        }
                    }
                }

                // The Power rail: floats outside the phone's screen, past
                // its right edge, but tilted exactly like the rest of the
                // phone rather than sitting flat beside it. `railHost` is
                // a plain rectangular hit-box in real (`fit`-scaled)
                // pixels for the window's click mask — same trick
                // restRect uses for the phone, a generous axis-aligned box
                // around the actual (tilted, so not itself rectangular)
                // rendered shape; individual pills still hit-test exactly
                // since Matrix4x4 transforms hit-test correctly on their
                // own. `railTilt` carries the phone's own lift (so it
                // rises and settles together with it) and scale;
                // `powerRail` inside it is the one with the actual tilt,
                // via `phone.matrix()` — the exact function PhoneBody's
                // own screen content is projected with — offset to
                // `railRawX/railRawY` (the phone's raw design coordinates
                // just past its right edge) so it reads as an extension of
                // the same tilted plane, not a separately-angled object.
                Item {
                    id: railHost

                    // Static, the same way restRect above is: sized to
                    // hold the rail through the whole stage.lift bounce
                    // without tracking it frame by frame either — every
                    // frame of that would mean re-sending the window's
                    // input region to the compositor for the whole
                    // ~700ms bounce, on top of the resize this file used
                    // to also cause. restRect gets away with never
                    // following phone.y because topRoom already reserves
                    // room above it for the bounce; padding by
                    // root.bounce on both sides here does the same for
                    // the rail, which rises and falls by exactly that
                    // much too (railTilt.y: phone.y, below) but — unlike
                    // restRect — isn't itself pinned to a resting spot
                    // the bounce moves away from.
                    x: win.railMinX * win.fit
                    y: win.railMinY * win.fit - root.bounce * win.fit
                       + root.lowLift
                    width: stage.quickInput ? (win.railMaxX - win.railMinX) * win.fit : 0
                    height: stage.quickInput ? (win.railMaxY - win.railMinY) * win.fit + root.bounce * win.fit * 2 : 0
                }

                Item {
                    id: railTilt
                    // (Only exists for the Quick Panel itself: it is shut before
                    // the Settings turn and has no business on the way.)
                    visible: stage.flip === 0
                    x: phone.x
                    y: phone.y
                    transformOrigin: Item.TopLeft
                    scale: win.fit

                    PowerMenu {
                        id: powerRail
                        transform: Matrix4x4 {
                            matrix: phone.matrix(PM.trans(win.railRawX, win.railRawY, 0))
                        }
                        // Same value, same reason, as phone's own renderScale
                        // just above — see PowerMenu's own layer for why it
                        // needs it too now.
                        renderScale: phone.renderScale

                        open: panelFace.powerMenuOpen
                        onDismissRequested: panelFace.powerMenuOpen = false
                        onPowerOffRequested: root.source.powerOff()
                        onRebootRequested: root.source.reboot()
                        onLogoutRequested: root.source.logout()
                        onLockRequested: {
                            root.close()
                            root.source.lock()
                        }
                        // Sleep / Hibernate lock first (QuickSource.lockThen), so
                        // the panel closes the same way it does for Lock — the
                        // lock ring plays over the desktop, not over the phone.
                        onSleepRequested: {
                            root.close()
                            root.source.sleep()
                        }
                        onHibernateRequested: {
                            root.close()
                            root.source.hibernate()
                        }
                        onFirmwareRequested: root.source.firmwareReboot()
                        onSystemMonitorRequested: root.source.openSystemMonitor()
                    }
                }

                // A phone that only came up for a notification (on top of it, so it sees
                // every press first; off the moment the phone is a normal open one):
                //   click         it stays (claim()), on the release, and only when
                //                 nothing was dragged: the press still carries on to
                //                 the button / slider under it, so that click does its
                //                 job too. (It used to claim on the press, which left
                //                 no way to swipe it away.)
                //   swipe down    back down at once (the notification stays in the list)
                //   middle click  the same
                //   right click   back down, and the notification is removed
                Item {
                    id: alertTouch
                    anchors.fill: parent
                    enabled: root.alertUp && !root.open

                    // Down far enough to mean it (design px on the phone's face).
                    readonly property real swipeAway: 40
                    // A button is held or a swipe is going on: the card's hover-to-open
                    // waits (onAlertActivated).
                    readonly property bool busy: leftTap.pressed || middleTap.pressed || rightTap.pressed || alertSwipe.active

                    function putAway() {
                        root.notificationSource.hideToast()
                    }

                    function removeIt() {
                        const t = root.notificationSource.toast
                        if (t && t.key !== undefined)
                            root.notificationSource.dismiss(t.key)
                        root.notificationSource.hideToast()
                    }

                    // Passive: the button under it still gets the press, and a drag
                    // past the threshold cancels the tap.
                    TapHandler {
                        id: leftTap
                        acceptedButtons: Qt.LeftButton
                        gesturePolicy: TapHandler.DragThreshold
                        onTapped: root.claim()
                    }

                    // Exclusive: the card under it doesn't act on these as well.
                    TapHandler {
                        id: middleTap
                        acceptedButtons: Qt.MiddleButton
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: alertTouch.putAway()
                    }

                    TapHandler {
                        id: rightTap
                        acceptedButtons: Qt.RightButton
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: alertTouch.removeIt()
                    }

                    // Takes over only once the pointer has moved past the drag
                    // threshold (the button's press is then cancelled, and so is the
                    // tap above); let go far enough down and the phone goes away.
                    DragHandler {
                        id: alertSwipe
                        target: null
                        xAxis.enabled: false
                        property real lastY: 0
                        onActiveTranslationChanged: lastY = activeTranslation.y
                        onActiveChanged: {
                            if (active)
                                lastY = 0
                            else if (lastY > alertTouch.swipeAway)
                                alertTouch.putAway()
                        }
                    }
                }
            }

            // The Settings phone: the other half of the turn (SettingsStage.qml).
            // It stands in the middle of the monitor, and during the turn follows
            // the same path as the Quick Panel's phone, rolled the opposite way.
            SettingsStage {
                id: sstage

                source: root.source
                notificationSource: root.notificationSource
                screenName: root.targetScreen ? root.targetScreen.name : ""
                clockText: panelFace.clockText
                dateText: panelFace.dateText
                active: root.settingsShown
                content: root.landscape
                straightOn: root.wallpapersStraight
                // Built beforehand while the Apps screen (the Wallpapers tile) is up.
                warmWallpapers: root.wallpapersWarm && root.warmReady && root.open && !root.settingsOpen && root.faceScreen === "apps"
                pixelRatio: root.targetScreen ? root.targetScreen.devicePixelRatio : 1
                // 2D: where this window's corner is on the monitor, so the flat Settings
                // screen lands on a whole device pixel of the monitor (like `stage.direct`).
                gridOffsetX: root.flat2d ? (win.monitorW - win.implicitWidth) / 2 : 0
                gridOffsetY: root.flat2d ? win.monitorH + Math.ceil(win.bleed) - win.implicitHeight : 0

                fit: win.sFit
                centerX: stage.flipCX
                centerY: stage.flipCY
                flip: stage.flip
                quickFit: win.fit
                quickYaw: phone.yaw
                quickPitch: phone.pitch
                dipDepth: root.flipDip
                pop: stage.sPop
                alpha: stage.sAlpha
                tilt: stage.sTilt
                wob: stage.wob

                moving: settingsEnter.running || settingsExit.running || stage.flipping || ring.running || !win.visible
                busy: PanelActivity.busy
                turning: stage.flipping
                turnHold: root.ringKeepsLite && ring.running

                // Nothing on it takes a click until it has settled (or while it is going).
                enabled: root.settingsOpen && stage.flip >= 1 && !stage.flipping

                onCloseRequested: root.settingsBack()

                // The Settings' Wallpapers buttons: the gallery comes up on this same
                // phone (no second turn), and its X / Escape goes back to the Settings.
                onWallpapersRequested: root.swapLandscape("wallpapers", "desktop")

                onLockWallpapersRequested: root.swapLandscape("wallpapers", "lock")

                onWallpapersCloseRequested: root.settingsBack()

                onSearchLeft: root.focusLandscape()

                onWallpapersLoaded: landscapeFocus.restart()

                onDesktopEditRequested: {
                    root.close()
                    editDelay.restart()
                }

                onKeybindsRequested: {
                    root.close()
                    keybindsDelay.restart()
                }
            }
        }
    }
}
