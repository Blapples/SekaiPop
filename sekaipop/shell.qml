import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common
import qs.modules.sekai.background
import qs.modules.sekai.bar
import qs.modules.sekai.cheatSheet
import qs.modules.sekai.keybinds
import qs.modules.sekai.desktopMenu
import qs.modules.sekai.desktopWidgets
import qs.modules.sekai.dock
import qs.modules.sekai.editMode
import qs.modules.sekai.framing
import qs.modules.sekai.keyboard
import qs.modules.sekai.launcher
import qs.modules.sekai.lock
import qs.modules.sekai.notificationPopup
import qs.modules.sekai.onScreenDisplay
import qs.modules.sekai.overview
import qs.modules.sekai.palette
import qs.modules.sekai.polkit
import qs.modules.sekai.quickPanel
import qs.modules.sekai.regionSelector
import qs.modules.sekai.visualizer
import qs.modules.sekai.welcome

ShellRoot {
    id: shellRoot

    // Keep hot reload for development, but pause the file watcher while an
    // update from Settings is writing files. Otherwise Quickshell reloads on
    // the first changed file, sees half old and half new QML and shows
    // "Failed to load configuration" (e.g. "UndoTile is not a type"). When the
    // update finishes, UpdateService does one hard reload from the new files.
    settings.watchFiles: !UpdateService.updating

    // The Wayland background itself — one per screen, owning
    // WlrLayer.Background directly (see WallpaperLayer.qml's header
    // comment for why it destroy()s texture slots instead of reusing
    // them). Declared first as "the thing everything else sits on
    // top of"; actual Wayland stacking comes from WlrLayershell.layer,
    // not this position.
    Variants {
        id: wallpaperLayers
        model: Quickshell.screens
        WallpaperLayer {}
    }

    // The framer (PanelImages.frame(): which part of the banner, avatar or phone picture
    // shows). Built only while a picture is being framed, on the monitor it was opened for.
    Variants {
        model: Quickshell.screens

        delegate: LazyLoader {
            id: framerLoader
            required property var modelData
            active: PanelImages.framing !== ""
                && (PanelImages.framingScreen === "" || framerLoader.modelData.name === PanelImages.framingScreen)
            FramerWindow { modelData: framerLoader.modelData }
        }
    }

    // (The old wallpaper picker board is gone: the Wallpapers are a screen of the
    // one phone now, see QuickPanel.qml. `ipc call wallpaperpicker ...` still works
    // and opens them there. The group-theme picker (the THEME tab of Edit Desktop)
    // has its own bind:
    //   bind = CTRL SHIFT, T, exec, qs -c sekaipop ipc call theme toggle)

    // First-run convenience only: if nothing's ever been saved (a
    // fresh config, or the saved wallpaper's file has since been
    // deleted), the desktop gets the wallpaper that ships with the shell
    // (assets/images/default-wallpaper.png, copied into the picker's own
    // directory by scripts/wallpapers/default-wallpaper.sh so it is listed there like
    // any other). Only if that can't be done does it fall back to whatever's
    // alphabetically first in the wallpaper directory, so the background
    // isn't just black.
    //
    // Waits on WallpaperService.restoring rather than just checking
    // currentPath.length === 0 directly: currentPath starts empty
    // either way, so racing straight off that would win against
    // WallpaperService's own async restore-from-disk on every single
    // launch and stomp your actual last pick — which was exactly the
    // bug this used to have. Both the folder listing finishing and
    // the onRestoringChanged handler get a turn at applying this, so
    // whichever settles second — the folder listing or the restore —
    // still gets caught.
    // (This used to be a Repeater whose index-0 delegate did the work. A
    // Repeater needs an Item parent, and ShellRoot isn't one, so every
    // delegate - one per wallpaper file - was created with no parent and
    // Qt logged a stackAfter warning for each. Only the first file ever
    // mattered, so a plain model and a function do the same job.)
    FolderListModel {
        id: fallbackWallpapers
        folder: WallpaperService.directoryUrl
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"]
        showDirs: false
        sortField: FolderListModel.Name

        // The folder listing finished (0 -> N files).
        onCountChanged: shellRoot.applyFallbackWallpaper()
    }

    Connections {
        target: WallpaperService
        function onRestoringChanged() {
            shellRoot.applyFallbackWallpaper();
        }

        function onReadyChanged() {
            shellRoot.applyFallbackWallpaper();
        }
    }

    // "" = not tried yet, "running", "done", "failed" (the shipped wallpaper
    // could not be used; the first file of the folder is taken instead).
    property string defaultSeed: ""

    readonly property string bundledWallpaper: Directories.asset("images/default-wallpaper.png")
    readonly property string seedScript: Directories.script("wallpapers/default-wallpaper.sh")

    function applyFallbackWallpaper() {
        // `ready` also waits for the saved settings, so a wallpaper folder chosen
        // earlier is known before the first-run picture is put anywhere.
        if (!WallpaperService.ready || WallpaperService.defaultPath.length > 0)
            return;
        if (shellRoot.defaultSeed === "") {
            shellRoot.defaultSeed = "running";
            seedDefaultWallpaper.running = true;
            return;
        }
        if (shellRoot.defaultSeed === "failed" && fallbackWallpapers.count > 0)
            WallpaperService.ensureDefault(fallbackWallpapers.get(0, "filePath"));
    }

    Process {
        id: seedDefaultWallpaper
        command: ["sh", shellRoot.seedScript, "seed", shellRoot.bundledWallpaper, WallpaperService.directory]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path !== "") {
                    shellRoot.defaultSeed = "done";
                    // Does nothing if something was picked in the meantime.
                    WallpaperService.ensureDefault(path);
                } else {
                    shellRoot.defaultSeed = "failed";
                    shellRoot.applyFallbackWallpaper();
                }
            }
        }
    }

    // Desktop Focus Mode (services/FocusService.qml) is a singleton, which only
    // exists once something reads it; this makes it start with the shell so its
    // `ipc call focus ...` works and the widgets are judged from the first frame.
    readonly property bool focusModeOn: FocusService.enabled

    // AppThemeService (kitty / foot / VS Code / fish / the terminal prompt / window
    // borders following the theme) is a singleton too. It used to be created only when
    // Settings -> Desktop was opened, so after every shell restart nothing kept those
    // apps in step with the theme or matugen until you opened that page. Reading it
    // here starts it with the shell.
    readonly property bool appThemingOn: AppThemeService.ready

    // One tray for the whole shell, so a pin made from one monitor's
    // bar shows up on every other monitor's bar too.
    TraySource {
        id: trayState
    }

    // The polkit prompt (see services/PolkitService.qml / PolkitPrompt.qml):
    // whenever something needs admin rights — installing a package,
    // mounting a disk, a settings app changing the system — this is what
    // asks for the password, on whichever monitor was focused when the
    // request came in. One for the whole shell, same as the lock screen.
    // Requires Quickshell's own polkit agent to be the only one running
    // (see the README's Polkit section) — stop hyprpolkitagent/
    // polkit-gnome/lxqt-policykit if hyprland.lua or your session
    // currently starts one of those.
    PolkitPrompt {}

    // The welcome screen (services/WelcomeService.qml / WelcomeScreen.qml):
    // a short first-start tour in the style of the reference video, shown
    // once by itself and replayable with `ipc call welcome show`. Nothing of
    // it exists (no windows, no animations) until it is on screen, and it
    // never opens while Game Mode is on.
    WelcomeScreen {}

    // The volume/mic/brightness OSD (services/OSDSource.qml /
    // OSDPopup.qml): a small flash under the bar whenever one of those
    // changes. Volume/mic react live to PipeWire itself, so hardware
    // keys work with no extra wiring; brightness only moves (and the
    // OSD only shows) from an explicit call — see OSDSource.qml's own
    // header comment for the exact hyprland.lua binds to add.
    OSDPopup {}

    // "● REC" in the top-right corner while the screen is being recorded
    // (RecordingIndicator.qml); click it to stop.
    RecordingIndicator {}

    // The reload report (ReloadPopup.qml): "Shell reloaded" after a
    // successful reload, and a card with Quickshell's error text when a
    // reload fails (a QML syntax error, a bad import...). It replaces
    // Quickshell's own reload popup.
    ReloadPopup {}

    // The screen-region picker (RegionSelector.qml, services/RegionService.qml):
    // copy, save, copy text (OCR), image search and record for a region you
    // drag on a frozen picture of the screen:
    //   qs -c sekaipop ipc call region screenshot|save|ocr|search|record|recordSound
    RegionSelector {}

    // The card that slides in after a Copy or Save from the region picker
    // (services/RegionService.qml): the picture, with Annotate (swappy),
    // Copy, Save and close.
    RegionPreview {}

    // The Quick Panel: one for the whole shell, opened on whichever
    // monitor you ask from (see QuickPanel.qml). QuickSource only checks
    // the system while the phone is up — opened by you, or raised by an
    // incoming notification (panel.up covers both, so the tiles are
    // fresh even when it only comes up to buzz) — and, for the
    // Brightness slider specifically, only controls whichever monitor
    // the panel is currently showing on (panel.targetScreen).
    QuickSource {
        id: quickState
        // The Settings show some of these tiles too.
        active: panel.up || panel.settingsShown
        targetScreen: panel.targetScreen
    }

    // Notifications: the shell is the notification daemon (only one
    // program on the system can be), so there's exactly one of these.
    // The Quick Panel's Notifications tile is its do-not-disturb switch.
    // A new notification announces itself one of two ways (Settings >
    // General > Notification alert): by the Quick Panel itself (the default:
    // it comes up, buzzes and shows the new one at the top of the phone), or
    // as a popup on the stack in the corner (NotificationPopup.qml).
    // The phone being up already shows the list, so no popups meanwhile.
    NotificationSource {
        id: notificationState
        doNotDisturb: !quickState.notificationsOn
        quietWhenFullscreen: SettingsService.flag("notify.quietFullscreen")
        alertStyle: SettingsService.get("notify.style")
        popupsSuppressed: panel.up
    }

    NotificationPopup {
        source: notificationState
    }

    // Low-battery warnings (20 / 15 / 10 / 5 %), sent as notifications through the
    // daemon above. Idle on a desktop with no battery. Settings > General > Time & alerts.
    BatteryAlertService {}

    // The idle times (lock, screen off, sleep), written for hypridle. A singleton only
    // exists once something reads it, and this one has to write its file at startup.
    readonly property bool idleTimesReady: IdleService.ready

    // The app fonts picked in the Settings are put back at start if something changed them,
    // so this singleton has to exist from the start as well.
    readonly property bool appFontsReady: AppFontService.ready

    // The Quick Panel is the front door of the ONE phone (see QuickPanel.qml's
    // header): Quick, the Apps screen and the Settings live in it, behind one
    // router, and `ipc call phone ...` drives all of it. The Wallpapers share the
    // Settings' phone.
    //   bind = SUPER, N, exec, qs -c sekaipop ipc call phone toggle
    //   bind = SUPER, A, exec, qs -c sekaipop ipc call phone go apps
    //   bind = SUPER, ESCAPE, exec, qs -c sekaipop ipc call phone go settings
    // (`quickpanel`, `launcherphone` and `settings` keep working; see CHANGELOG.)
    QuickPanel {
        id: panel
        coverCheat: cheatSheetEntry.shown
        source: quickState
        notificationSource: notificationState
        barWindows: bars.instances
        picker: wallpaperEntry
        appSource: appState
        launcher: launcherPhone
    }

    // The bar's wallpaper key (and `ipc call wallpaperphone ...`) open the
    // Wallpapers on the Quick Panel's phone: the same landscape phone as the Settings,
    // turned out of the Quick Panel the same way (QuickPanel.qml, SettingsStage.qml).
    // They only call openOn / toggleOn on `picker`, so this stands in for it.
    // (`ipc call wallpaperpicker ...`, the old board's name, is answered by the Quick
    // Panel too, see QuickPanel.qml.)
    QtObject {
        id: wallpaperEntry

        function openOn(screen, which) {
            panel.openWallpapers(screen, which)
        }

        function toggleOn(screen, which) {
            panel.toggleWallpapersOn(screen, which)
        }
    }

    // The Quick Panel and the corner phone are both phones that come up from the
    // bottom of the screen: whichever is asked for second takes over.
    Connections {
        target: panel

        function onOpenChanged() {
            if (panel.open)
                launcherPhone.close()
        }

        function onSettingsOpenChanged() {
            if (panel.settingsOpen)
                launcherPhone.close()
        }
    }

    // The settings are not a panel of their own: the gear on the Quick Panel's
    // header turns the Quick Panel's phone into them (it rolls a quarter turn
    // and its screen becomes the Settings, see QuickPanel.qml, SettingsStage.qml
    // and FlipMath.js). Without the Quick Panel up they come up on their own:
    //     qs -c sekaipop ipc call settings toggle

    // The Overview + App Launcher, one surface (see Overview.qml's
    // header comment). AppSource ranks installed apps against whatever's
    // typed in the search pill; the Overview under it — a live picture
    // of every window on every workspace, draggable between them — shows
    // until you type. AppSource has nothing to poll, so unlike
    // QuickSource there's no `active` gate; window data
    // (services/HyprlandData.qml) is refreshed only while it's open.
    AppSource {
        id: appState
    }

    // The board itself is built only while it is open (services/ComponentActivation.qml,
    // OverviewEntry.qml); `overview` below is its front door, with the same functions the
    // board had (`toggleOn`, `openOn`, `hide`, `close`).
    OverviewEntry {
        id: overview
    }

    LazyLoader {
        active: ComponentActivation.overviewActive

        Overview {
            id: overviewBoardItem
            Component.onCompleted: overview.attach(overviewBoardItem)
            Component.onDestruction: overview.detach(overviewBoardItem)
        }
    }

    //   qs -c sekaipop ipc call overview toggle | show | hide | style [board|scroll]
    IpcHandler {
        target: "overview"

        function toggle(): void {
            overview.toggleOn(overview.focusedScreen())
        }

        function show(): void {
            overview.openOn(overview.focusedScreen())
        }

        function hide(): void {
            overview.hide()
        }

        // `ipc call overview style` says which overview a key opens;
        // `... style scroll` / `... style board` switches it (remembered).
        function style(name: string): string {
            if (name === "scroll" || name === "board")
                SettingsService.set("overview.style", name)
            return SettingsService.get("overview.style")
        }
    }

    // The corner phone (LauncherPhone.qml): what is left of the old launcher phone
    // while Wallpapers move into the one phone. It has no hot corner and
    // no Home any more (that is the Apps screen of the Quick Panel's phone now); the
    // Apps screen's Wallpapers tile brings it up and Back returns there.
    // Wallpapers turns the phone, in place, into the flat landscape Wallpapers phone
    // (WallpaperStage.qml / WallpaperFace.qml). The Overview phone is gone. Bind a key
    // to it, e.g.:
    //   bind = CTRL SUPER, T, exec, qs -c sekaipop ipc call wallpaperphone toggle
    // (also `show` / `hide`). The Overview board above only shows the workspace
    // cards now (`ipc call overview ...`); `applauncher` and `wallpaperpicker` are
    // answered by the Quick Panel's phone.
    LauncherPhone {
        id: launcherPhone
        source: appState
        quickPanel: panel
        overviewBoard: overview
    }

    // The on-screen keyboard (OnScreenKeyboard.qml, services/KeyboardService.qml):
    // the bar's workspace badges as keys, typing through wtype. Opened by the
    // bar's Keyboard key, the Quick Panel's Keyboard tile, or
    //   qs -c sekaipop ipc call keyboard toggle | show | hide
    OnScreenKeyboard {}

    // The keybind cheatsheet (CheatSheet.qml): every Hyprland bind as paper
    // notes pinned to a cork board, read from `hyprctl -j binds` each time
    // it opens. Bind a key to it in hyprland.lua, e.g.:
    //   bind = SUPER, F1, exec, qs -c sekaipop ipc call cheatsheet toggle
    // (also `show` / `hide`). Files: CheatSheet.qml, CheatNote.qml,
    // CheatBinds.js.
    // Built only while it is open (services/ComponentActivation.qml, ActivationEntry.qml).
    ActivationEntry {
        id: cheatSheetEntry
        name: "cheatSheet"
    }

    LazyLoader {
        active: ComponentActivation.cheatSheetActive

        CheatSheet {
            id: cheatSheetBoard
            quickPanel: panel
            Component.onCompleted: cheatSheetEntry.attach(cheatSheetBoard)
            Component.onDestruction: cheatSheetEntry.detach(cheatSheetBoard)
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            cheatSheetEntry.toggle(cheatSheetEntry.focusedScreen())
        }

        function show(): void {
            cheatSheetEntry.open(cheatSheetEntry.focusedScreen())
        }

        function hide(): void {
            cheatSheetEntry.close()
        }
    }

    // The keybinds panel (modules/sekai/keybinds/KeybindsPanel.qml): a keyboard slab that
    // shows what every shortcut is on and changes SekaiPop's own. Settings > Hyprland has a
    // button for it, or bind a key:
    //   bind = SUPER, F2, exec, qs -c sekaipop ipc call keybinds toggle
    // (also `show` / `hide`). Built only while it is open, like the cheatsheet.
    ActivationEntry {
        id: keybindsEntry
        name: "keybinds"
    }

    LazyLoader {
        active: ComponentActivation.keybindsActive

        KeybindsPanel {
            id: keybindsSlab
            quickPanel: panel
            Component.onCompleted: keybindsEntry.attach(keybindsSlab)
            Component.onDestruction: keybindsEntry.detach(keybindsSlab)
        }
    }

    // Settings > Hyprland > Keybinds asks through the phone, not through `ipc call`.
    Connections {
        target: panel

        function onKeybindsOpenRequested(screen) {
            keybindsEntry.open(screen ? screen : keybindsEntry.focusedScreen())
        }
    }

    IpcHandler {
        target: "keybinds"

        function toggle(): void {
            console.log("[keybinds] ipc toggle")
            keybindsEntry.toggle(keybindsEntry.focusedScreen())
        }

        function show(): void {
            console.log("[keybinds] ipc show")
            keybindsEntry.open(keybindsEntry.focusedScreen())
        }

        function hide(): void {
            console.log("[keybinds] ipc hide")
            keybindsEntry.close()
        }
    }

    // The Palette tool (modules/sekai/palette/PaletteTool.qml): colours from the
    // wallpaper or the playing track's cover, or random harmonies, with favourites,
    // HEX copy and a live preview. Looking never changes the theme; only its
    // "Apply to theme" button does.
    //   qs -c sekaipop ipc call palette toggle | show | hide | shuffle
    // Also Settings -> Quick -> Look -> "Palette tool", and the corner key on the Palette
    // desktop card (PaletteWidget.qml, ipc target `palettecard`).
    // Built only while it is open, together with the MediaSource and the picture reader it
    // owns (services/ComponentActivation.qml, ActivationEntry.qml).
    ActivationEntry {
        id: paletteToolEntry
        name: "paletteTool"
    }

    LazyLoader {
        active: ComponentActivation.paletteToolActive

        PaletteTool {
            id: paletteToolBoard
            Component.onCompleted: paletteToolEntry.attach(paletteToolBoard)
            Component.onDestruction: paletteToolEntry.detach(paletteToolBoard)
        }
    }

    IpcHandler {
        target: "palette"

        function toggle(): void {
            paletteToolEntry.toggle(paletteToolEntry.focusedScreen())
        }

        function show(): void {
            paletteToolEntry.open(paletteToolEntry.focusedScreen())
        }

        function hide(): void {
            paletteToolEntry.close()
        }

        // A new random strip. Only the tool's own state changes, never the theme.
        function shuffle(): void {
            PaletteService.shuffle()
        }
    }

    // Settings and the Palette card's expand key ask through the service.
    Connections {
        target: PaletteService

        function onOpenRequested() {
            paletteToolEntry.open(paletteToolEntry.focusedScreen())
        }
    }

    // One bar per monitor, *per edge*. Each entry carries the edge the bar
    // is on, so moving the bar (BarPositionService.cycle()) doesn't
    // re-anchor and resize a live layer-shell window — which left the bar,
    // the space it reserves and the popups out of step until the shell was
    // restarted — it builds a fresh window on the new edge and drops the
    // old one: exactly what a restart does. Nothing is built until the
    // saved edge has been read, so startup doesn't create a "top" bar only
    // to move it a moment later.
    Variants {
        id: bars
        model: {
            const list = []
            // (Settings -> Bar -> Show bar.)
            // (Waits for GameModeService too: a start with Game Mode already on
            // builds the fixed bar straight away, not the full one first.)
            if (BarPositionService.loaded && GameModeService.loaded && SettingsService.flag("bar.visible")) {
                for (const s of Quickshell.screens)
                    list.push({ screen: s, position: BarPositionService.position })
            }
            return list
        }
        Bar {
            traySource: trayState
            quickPanel: panel
            picker: wallpaperEntry
        }
    }

    // The screen lock (Lockscreen.qml): one WlSessionLock for the whole
    // shell, a LockSurface per monitor. Locked via LockState.lock() —
    // the Quick Panel's Power menu does that, and so can a keybind or
    // hypridle:  qs -c sekaipop ipc call lock lock
    Lockscreen {}

    // The App Dock (Dock.qml). One dock, on the first monitor, or (Settings ->
    // Desktop -> Dock -> Dock on every monitor) one per monitor, like the bar.
    // The edge is part of the entry, as it is for the bar: moving the dock builds
    // a fresh window on the new edge instead of re-anchoring a live one.
    Variants {
        id: docks
        model: {
            const list = []
            // Game Mode: no dock at all (its windows are not built, so its apps,
            // folders, cards and hot edge are gone, and it comes back as it was).
            // Also none until the saved settings are read: built earlier, the dock would
            // stand up with the defaults (bottom, always shown) for a moment, then be
            // rebuilt / slide away once the real ones arrive.
            if (GameModeService.enabled || !GameModeService.loaded || !SettingsService.loaded)
                return list
            // The bars go first. A pinned dock reserves space at its edge (so windows fit
            // around it), and Hyprland hands out the free screen space to layer windows in
            // the order they appeared: a bar that appears AFTER the dock has the dock's
            // space cut out of it (a standing bar on the left stopped short of the bottom
            // edge when the dock was on the bottom). So the dock waits until every bar
            // exists, and is built again when a bar is (a new bar window = the entry
            // below holds the new window, so the dock is made again after it).
            const barsWanted = (BarPositionService.loaded && GameModeService.loaded && SettingsService.flag("bar.visible"))
                ? Quickshell.screens.length : 0
            if (bars.instances.length < barsWanted)
                return list
            const every = SettingsService.flag("dock.perMonitor")
            const saved = SettingsService.get("dock.position")
            const pos = (saved === "left" || saved === "right" || saved === "top") ? saved : "bottom"
            // With one dock, dock.screen (a monitor name, e.g. "HDMI-A-1") picks its monitor;
            // empty or not connected = the first one.
            const wantName = SettingsService.get("dock.screen")
            let only = 0
            for (let j = 0; j < Quickshell.screens.length; j++) {
                if (Quickshell.screens[j].name === wantName) {
                    only = j
                    break
                }
            }
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (!every && i !== only)
                    continue
                list.push({ screen: Quickshell.screens[i], position: pos, perMonitor: every,
                            afterBar: i < bars.instances.length ? bars.instances[i] : null })
            }
            return list
        }
        Dock {
            notificationSource: notificationState
            launcher: panel
            overviewBoard: overview
        }
    }

    // The bar's own IPC (one handler for every bar, like the dock's below).
    //   qs -c sekaipop ipc call bar toggle | show | hide   (Settings -> Bar -> Show bar)
    //                                  | peek               (an auto-hiding bar comes out for 2 s)
    //                                  | hidemode off|auto  (Settings -> Bar -> Auto-hide)
    // `toggle` is the "Toggle bar" action in Settings -> Keys (it ships without a key).
    IpcHandler {
        target: "bar"

        function toggle(): void {
            SettingsService.toggle("bar.visible")
        }

        function show(): void {
            SettingsService.set("bar.visible", true)
        }

        function hide(): void {
            SettingsService.set("bar.visible", false)
        }

        function peek(): void {
            for (const b of bars.instances)
                b.peek()
        }

        function hidemode(mode: string): void {
            if (mode === "off" || mode === "auto")
                SettingsService.set("bar.hideMode", mode)
        }
    }

    // The shell's own pictures (PanelImages.qml, docs/PICTURE-FRAMING.md).
    //   qs -c sekaipop ipc call pictures pick banner|avatar|phone     open the chooser
    //                                  | frame banner|avatar|phone    open the framer
    //                                  | unframe banner|avatar|phone  back to centred
    //                                  | close                        close the framer (as Cancel)
    IpcHandler {
        target: "pictures"

        function pick(kind: string): void {
            if (kind === "banner" || kind === "avatar" || kind === "phone")
                PanelImages.pick(kind, "")
        }

        function frame(kind: string): void {
            PanelImages.frame(kind, false, "")
        }

        function close(): void {
            PanelImages.closeFramer(false)
        }

        function unframe(kind: string): void {
            if (kind === "banner" || kind === "avatar" || kind === "phone")
                PanelImages.setFraming(kind, null)
        }
    }

    // The dock's own IPC (one handler for every dock; a handler inside Dock.qml
    // would be one per monitor with the same name).
    //   qs -c sekaipop ipc call dock peek | autohide true|false | hidemode off|auto|smart
    //                                   | position bottom|top|left|right | style float|transparent|capsule
    //                                   | layouts | layoutsave <name> | layoutload <name> | layoutdelete <name>
    //                                   | separator | foldernew <name> | folderrename <index> <name>
    //                                   | files        (open / close the Files folder stack)
    IpcHandler {
        target: "dock"

        // Pull the dock up for a moment (it hides again on its own).
        function peek(): void {
            for (const d of docks.instances)
                d.peek()
        }

        // The Files stack, on the first dock that has a Files key.
        function files(): void {
            for (const d of docks.instances) {
                if (d.toggleFiles())
                    break
            }
        }

        function autohide(on: bool): void {
            SettingsService.set("dock.autoHide", on)
        }

        function position(edge: string): void {
            if (edge === "bottom" || edge === "top" || edge === "left" || edge === "right")
                SettingsService.set("dock.position", edge)
        }

        function style(name: string): void {
            if (name === "float" || name === "transparent" || name === "capsule")
                SettingsService.set("dock.style", name)
        }

        function hidemode(mode: string): void {
            if (mode === "off" || mode === "auto" || mode === "smart") {
                SettingsService.set("dock.hideMode", mode)
                SettingsService.set("dock.autoHide", false)
            }
        }

        // Saved layouts ("Work", "Gaming"...): the pinned apps, folders and separators.
        function layouts(): string {
            return PinnedAppsService.presetNames.join("\n")
        }

        function layoutsave(name: string): void {
            PinnedAppsService.savePreset(name)
        }

        function layoutload(name: string): void {
            PinnedAppsService.loadPreset(name)
        }

        function layoutdelete(name: string): void {
            PinnedAppsService.deletePreset(name)
        }

        function separator(): void {
            PinnedAppsService.addSeparator()
        }

        function foldernew(name: string): void {
            PinnedAppsService.createFolder(name, undefined, [])
        }

        function folderrename(index: int, name: string): void {
            PinnedAppsService.renameFolder(index, name)
        }
    }

    // Desktop Focus Mode, aggressive option (Settings -> Desktop Focus -> Unload hidden
    // widgets): each loader below also lets go of its widget once that widget's gate says
    // it has been hidden for a while, and builds it again, staggered, when the desktop is
    // back. The gates use the same monitor the widget itself resolves (EditMode.homeScreen).
    //
    // These five desktop widgets are deliberately unloaded when hidden.
    // They are among the largest QML object trees in the rice, so merely setting
    // visible: false would keep all of their bindings, images, models and timers
    // resident. Edit Desktop temporarily loads them so their editing UI behaves
    // exactly as before.
    // Game Mode (services/GameModeService.qml): every desktop widget below is
    // unloaded, not just hidden, for as long as it is on (Edit Desktop included,
    // which will not open meanwhile). Their own "shown" switches are not touched,
    // so each one is built again exactly as it was when Game Mode goes off. Until
    // the Game Mode state has been read nothing is built, so a start with it on
    // never builds them at all.
    //
    // The lock screen (services/LockState.qml `desktopAsleep`): while the session lock is
    // engaged the compositor draws nothing but the lock surface, so the widgets are unloaded
    // too, freeing their trees, images, models and timers (and the visualizer's audio tap
    // with it). The moment the password is accepted they are built again, but ONE AFTER
    // ANOTHER (`wakeStep`, below), so the unlock ring that is opening up the desktop does not
    // stutter under ten widgets being created in the same frame. Their own "shown" switches,
    // positions and contents live in the services and are not touched.
    // Settings -> General -> Launcher & lock -> "Sleep the desktop while locked" turns it off.
    readonly property bool widgetsAllowed: GameModeService.loaded && !GameModeService.enabled && !LockState.desktopAsleep

    // How many widgets may be built so far after an unlock (see `woke`). 99 = all of them,
    // which is what it is at start, in Game Mode and with the lock sleep off: nothing waits.
    property int wakeStep: 99

    // Widget number n (0 = the first to come back) may be built.
    function woke(n) {
        return shellRoot.wakeStep >= n
    }

    readonly property bool desktopAsleep: LockState.desktopAsleep
    onDesktopAsleepChanged: {
        wakeTimer.stop()
        shellRoot.wakeStep = 0
        if (shellRoot.desktopAsleep) {
            // Give the widgets' loaders a moment to let go, then ask the JS engine to collect
            // what they held (it only runs while nothing is on screen, so it cannot be seen).
            gcTimer.restart()
        } else {
            gcTimer.stop()
            // Unlocking: widget 0 is built at once (its loader sees `woke(0)`), the rest follow.
            wakeTimer.restart()
        }
    }

    Timer {
        id: wakeTimer
        interval: 90
        repeat: true
        onTriggered: {
            shellRoot.wakeStep = shellRoot.wakeStep + 1
            if (shellRoot.wakeStep >= 12)
                wakeTimer.stop()
        }
    }

    Timer {
        id: gcTimer
        interval: 1500
        onTriggered: {
            try {
                gc()
            } catch (e) {
            }
        }
    }

    property bool todoResetRequested: false
    property bool clockResetRequested: false
    property bool visualizerResetRequested: false
    property bool userCardResetRequested: false
    property bool weatherCardResetRequested: false
    property bool calendarCardResetRequested: false
    property bool paletteCardResetRequested: false
    property bool lyricsResetRequested: false

    FocusGate {
        id: todoGate
        widgetId: "todo"
        unloads: true
        screenName: DesktopMonitors.homeFor("todo")
    }

    LazyLoader {
        id: todoWidgetLoader
        active: shellRoot.woke(4) && shellRoot.widgetsAllowed && DesktopMonitors.loaded && ((TodoService.loaded && TodoService.shown && !todoGate.gone) || EditMode.active || shellRoot.todoResetRequested)
        TodoWidget {}
    }

    FocusGate {
        id: clockGate
        widgetId: "clock"
        unloads: true
        screenName: EditMode.homeScreen(ClockService.screenName)
    }

    LazyLoader {
        id: clockWidgetLoader
        active: shellRoot.woke(0) && shellRoot.widgetsAllowed && ((ClockService.loaded && ClockService.shown && !clockGate.gone) || EditMode.active || shellRoot.clockResetRequested)
        ClockWidget {}
    }

    // The copies of it on the other monitors (services/WidgetClones.qml): a window each, with a
    // spot of its own. `screens` only changes when a copy is added or removed, so moving one
    // does not rebuild it.
    Variants {
        model: WidgetClones.screens["clock"] ?? []

        delegate: LazyLoader {
            id: clClockWidget
            required property string modelData
            active: shellRoot.woke(0) && shellRoot.widgetsAllowed && ClockService.loaded && ClockService.shown
            ClockWidget { clone: true; monitor: clClockWidget.modelData }
        }
    }

    FocusGate {
        id: visualizerGate
        widgetId: "visualizer"
        unloads: true
        screenName: EditMode.homeScreen(VisualizerService.screenName)
    }

    LazyLoader {
        id: visualizerWidgetLoader
        active: shellRoot.woke(7) && shellRoot.widgetsAllowed && ((VisualizerService.loaded && VisualizerService.shown && !visualizerGate.gone) || EditMode.active || shellRoot.visualizerResetRequested)
        VisualizerWidget {}
    }

    FocusGate {
        id: usercardGate
        widgetId: "usercard"
        unloads: true
        screenName: EditMode.homeScreen(UserCardService.screenName)
    }

    LazyLoader {
        id: userCardWidgetLoader
        active: shellRoot.woke(1) && shellRoot.widgetsAllowed && ((UserCardService.loaded && UserCardService.shown && !usercardGate.gone) || EditMode.active || shellRoot.userCardResetRequested)
        UserCardWidget {}
    }

    // The copies of it on the other monitors (services/WidgetClones.qml): a window each, with a
    // spot of its own. `screens` only changes when a copy is added or removed, so moving one
    // does not rebuild it.
    Variants {
        model: WidgetClones.screens["usercard"] ?? []

        delegate: LazyLoader {
            id: clUserCardWidget
            required property string modelData
            active: shellRoot.woke(1) && shellRoot.widgetsAllowed && UserCardService.loaded && UserCardService.shown
            UserCardWidget { clone: true; monitor: clUserCardWidget.modelData }
        }
    }

    FocusGate {
        id: weathercardGate
        widgetId: "weathercard"
        unloads: true
        screenName: EditMode.homeScreen(WeatherCardService.screenName)
    }

    LazyLoader {
        id: weatherCardWidgetLoader
        active: shellRoot.woke(2) && shellRoot.widgetsAllowed && ((WeatherCardService.loaded && WeatherCardService.shown && !weathercardGate.gone) || EditMode.active || shellRoot.weatherCardResetRequested)
        WeatherCardWidget {}
    }

    // The copies of it on the other monitors (services/WidgetClones.qml): a window each, with a
    // spot of its own. `screens` only changes when a copy is added or removed, so moving one
    // does not rebuild it.
    Variants {
        model: WidgetClones.screens["weathercard"] ?? []

        delegate: LazyLoader {
            id: clWeatherCardWidget
            required property string modelData
            active: shellRoot.woke(2) && shellRoot.widgetsAllowed && WeatherCardService.loaded && WeatherCardService.shown
            WeatherCardWidget { clone: true; monitor: clWeatherCardWidget.modelData }
        }
    }

    // The Custom Images: one window per picture in ImageService (see ImageWidget.qml), so any
    // number of them. The Variants gets a new window only when a picture is added or
    // removed (ImageService.ids), never when one is edited. Each window has its own
    // FocusGate, so Focus Mode hides them like the other widgets; unloading hidden
    // ones is left out, since a hidden picture costs nothing but its (paused) window.
    LazyLoader {
        id: imageWidgetsLoader
        active: shellRoot.woke(9) && shellRoot.widgetsAllowed && ImageService.loaded
            && ((ImageService.shown && ImageService.count > 0) || EditMode.active)

        Scope {
            Variants {
                model: ImageService.ids

                ImageWidget {}
            }
        }
    }

    // The Sticky Notes (StickyNotesWidget.qml, services/NotesService.qml): one widget, two
    // windows. The desktop layer draws the unpinned notes under your windows like the
    // widgets above (and is unloaded by Desktop Focus Mode the same way); the pinned
    // layer draws the pinned notes above your windows, so Focus Mode never takes it
    // away. Both are unloaded in Game Mode. There is no reset-position request: the
    // notes are kept on screen by themselves, and `ipc call notes arrange` tidies them.
    FocusGate {
        id: notesGate
        widgetId: "notes"
        unloads: true
        screenName: DesktopMonitors.homeFor("notes")
    }

    LazyLoader {
        id: notesWidgetLoader
        active: shellRoot.woke(8) && shellRoot.widgetsAllowed && DesktopMonitors.loaded && NotesService.loaded && NotesService.shown && !notesGate.gone
        StickyNotesWidget { pinnedLayer: false }
    }

    LazyLoader {
        id: pinnedNotesLoader
        active: shellRoot.woke(8) && shellRoot.widgetsAllowed && DesktopMonitors.loaded && NotesService.loaded && NotesService.shown && NotesService.pinnedCount > 0
        StickyNotesWidget { pinnedLayer: true }
    }

    FocusGate {
        id: calendarcardGate
        widgetId: "calendarcard"
        unloads: true
        screenName: EditMode.homeScreen(CalendarCardService.screenName)
    }

    LazyLoader {
        id: calendarCardWidgetLoader
        active: shellRoot.woke(3) && shellRoot.widgetsAllowed && ((CalendarCardService.loaded && CalendarCardService.shown && !calendarcardGate.gone) || EditMode.active || shellRoot.calendarCardResetRequested)
        CalendarCardWidget {}
    }

    // The copies of it on the other monitors (services/WidgetClones.qml): a window each, with a
    // spot of its own. `screens` only changes when a copy is added or removed, so moving one
    // does not rebuild it.
    Variants {
        model: WidgetClones.screens["calendarcard"] ?? []

        delegate: LazyLoader {
            id: clCalendarCardWidget
            required property string modelData
            active: shellRoot.woke(3) && shellRoot.widgetsAllowed && CalendarCardService.loaded && CalendarCardService.shown
            CalendarCardWidget { clone: true; monitor: clCalendarCardWidget.modelData }
        }
    }

    // The Palette card (modules/sekai/desktopWidgets/PaletteWidget.qml): the same colours
    // the Palette tool shows, living on the desktop. Off until you add it.
    FocusGate {
        id: palettecardGate
        widgetId: "palettecard"
        unloads: true
        screenName: EditMode.homeScreen(PaletteService.screenName)
    }

    LazyLoader {
        id: paletteCardWidgetLoader
        active: shellRoot.woke(5) && shellRoot.widgetsAllowed && ((PaletteService.loaded && PaletteService.shown && !palettecardGate.gone) || EditMode.active || shellRoot.paletteCardResetRequested)
        PaletteWidget {}
    }

    // The copies of it on the other monitors (services/WidgetClones.qml): a window each, with a
    // spot of its own. `screens` only changes when a copy is added or removed, so moving one
    // does not rebuild it.
    Variants {
        model: WidgetClones.screens["palettecard"] ?? []

        delegate: LazyLoader {
            id: clPaletteWidget
            required property string modelData
            active: shellRoot.woke(5) && shellRoot.widgetsAllowed && PaletteService.loaded && PaletteService.shown
            PaletteWidget { clone: true; monitor: clPaletteWidget.modelData }
        }
    }

    // The lyrics (modules/sekai/desktopWidgets/LyricsWidget.qml): the words of the song that is
    // playing, sung along on the desktop with no card behind them. Off until you add it.
    FocusGate {
        id: lyricsGate
        widgetId: "lyrics"
        unloads: true
        screenName: EditMode.homeScreen(LyricsService.screenName)
    }

    LazyLoader {
        id: lyricsWidgetLoader
        active: shellRoot.woke(6) && shellRoot.widgetsAllowed && ((LyricsService.loaded && LyricsService.shown && !lyricsGate.gone) || EditMode.active || shellRoot.lyricsResetRequested)
        LyricsWidget {}
    }

    // The copies of it on the other monitors (services/WidgetClones.qml): a window each, with a
    // spot of its own. `screens` only changes when a copy is added or removed, so moving one
    // does not rebuild it.
    Variants {
        model: WidgetClones.screens["lyrics"] ?? []

        delegate: LazyLoader {
            id: clLyricsWidget
            required property string modelData
            active: shellRoot.woke(6) && shellRoot.widgetsAllowed && LyricsService.loaded && LyricsService.shown
            LyricsWidget { clone: true; monitor: clLyricsWidget.modelData }
        }
    }

    // The desktop widget plugins (services/PluginService.qml, docs/PLUGINS.md): one window per
    // plugin found, built like the cards above, and its copies on the other monitors. `ids`
    // only changes when a plugin comes or goes, so nothing is rebuilt by a rescan that finds
    // the same ones.
    Variants {
        model: PluginService.ids

        delegate: Scope {
            id: plg
            required property string modelData
            readonly property var st: PluginService.stateFor(plg.modelData)
            readonly property string wid: "plugin:" + plg.modelData
            readonly property bool ready: !!plg.st && plg.st.loaded

            FocusGate {
                id: pluginGate
                widgetId: plg.wid
                unloads: true
                screenName: EditMode.homeScreen(plg.st ? plg.st.screenName : "")
            }

            LazyLoader {
                active: shellRoot.woke(10) && shellRoot.widgetsAllowed && plg.ready && ((plg.st.shown && !pluginGate.gone) || EditMode.active)
                PluginWidgetHost { pluginId: plg.modelData }
            }

            Variants {
                model: WidgetClones.screens[plg.wid] ?? []

                delegate: LazyLoader {
                    id: clPluginWidget
                    required property string modelData
                    active: shellRoot.woke(10) && shellRoot.widgetsAllowed && plg.ready && plg.st.shown
                    PluginWidgetHost { pluginId: plg.modelData; clone: true; monitor: clPluginWidget.modelData }
                }
            }
        }
    }

    // The lyrics source picker (modules/sekai/desktopWidgets/LyricsSources.qml): built only while open.
    LazyLoader {
        active: LyricsService.pickerOpen
        LyricsSources {}
    }

    // Keep IPC alive even when the heavy widget tree is unloaded. State-only
    // commands do not need to instantiate the widget at all.
    IpcHandler {
        target: "todo"
        function toggle(): void { TodoService.setShown(!TodoService.shown) }
        function show(): void { TodoService.setShown(true) }
        function hide(): void { TodoService.setShown(false) }
        // The card's size: 2x2 (the clock / user card / weather card footprint) or full.
        function size(mode: string): void { TodoService.setSize(mode) }
        function toggleSize(): void { TodoService.toggleSize() }
        function resetPosition(): void {
            shellRoot.todoResetRequested = true
            if (todoWidgetLoader.item) todoWidgetLoader.item.resetPosition()
            shellRoot.todoResetRequested = false
        }
    }

    IpcHandler {
        target: "clock"
        function toggle(): void { ClockService.setShown(!ClockService.shown) }
        function show(): void { ClockService.setShown(true) }
        function hide(): void { ClockService.setShown(false) }
        function toggleFormat(): void { ClockService.toggleFormat() }
        function nextDesign(): void { ClockService.cycleDesign() }
        function setDesign(index: int): void { ClockService.setDesign(index) }
        function resetPosition(): void {
            shellRoot.clockResetRequested = true
            if (clockWidgetLoader.item) clockWidgetLoader.item.resetPosition()
            WidgetClones.clearAll("clock")
            shellRoot.clockResetRequested = false
        }
    }

    IpcHandler {
        target: "visualizer"
        function toggle(): void { VisualizerService.setShown(!VisualizerService.shown) }
        function show(): void { VisualizerService.setShown(true) }
        function hide(): void { VisualizerService.setShown(false) }
        function nextSize(): void { VisualizerService.cycleSize() }
        // bands only: true = up the side of the screen, false = along the bottom
        function vertical(on: bool): void { VisualizerService.setVertical(on) }
        function toggleVertical(): void { VisualizerService.toggleVertical() }
        // sekai | tide | ribbons | scope | pulse (sekaipop's own) | bars | aurora | ring | dots | mirror (end4-pC's)
        function style(name: string): void { VisualizerService.setStyle(name) }
        function nextStyle(): void { VisualizerService.cycleStyle() }
        // the media pill's little visualizer: none | dots | wave
        function pillStyle(name: string): void { VisualizerService.setPillStyle(name) }
        function setSize(index: int): void { VisualizerService.setSize(index) }
        function stayPaused(on: bool): void { VisualizerService.setStayWhenPaused(on) }
        function colors(mode: int): void { VisualizerService.setColorMode(mode) }
        function sensitivity(value: real): void { VisualizerService.setSensitivity(value) }
        function listenAll(on: bool): void { VisualizerService.setAlwaysListen(on) }
        function analyzer(on: bool): void { VisualizerService.setAnalyzer(on) }
        function aubio(on: bool): void { VisualizerService.setUseAubio(on) }
        function performance(mode: int): void { VisualizerService.setPerf(mode) }
        function resetPosition(): void {
            shellRoot.visualizerResetRequested = true
            if (visualizerWidgetLoader.item) visualizerWidgetLoader.item.resetPosition()
            shellRoot.visualizerResetRequested = false
        }
    }

    IpcHandler {
        target: "usercard"
        function toggle(): void { UserCardService.setShown(!UserCardService.shown) }
        function show(): void { UserCardService.setShown(true) }
        function hide(): void { UserCardService.setShown(false) }
        function resetPosition(): void {
            shellRoot.userCardResetRequested = true
            if (userCardWidgetLoader.item) userCardWidgetLoader.item.resetPosition()
            WidgetClones.clearAll("usercard")
            shellRoot.userCardResetRequested = false
        }
    }

    IpcHandler {
        target: "weathercard"
        function toggle(): void { WeatherCardService.setShown(!WeatherCardService.shown) }
        function show(): void { WeatherCardService.setShown(true) }
        function hide(): void { WeatherCardService.setShown(false) }
        // "minimal" or "classic" (anything else, the old "full" too, is "classic").
        function style(mode: string): void { WeatherCardService.setStyle(mode) }
        // Ask Open-Meteo again now (only does something while the card is on screen).
        function refresh(): void { if (weatherCardWidgetLoader.item) weatherCardWidgetLoader.item.refresh() }
        function resetPosition(): void {
            shellRoot.weatherCardResetRequested = true
            if (weatherCardWidgetLoader.item) weatherCardWidgetLoader.item.resetPosition()
            WidgetClones.clearAll("weathercard")
            shellRoot.weatherCardResetRequested = false
        }
    }

    // State-only like the others: nothing here needs the windows to exist.
    IpcHandler {
        target: "image"
        function toggle(): void { ImageService.setShown(!ImageService.shown) }
        function show(): void { ImageService.setShown(true) }
        function hide(): void { ImageService.setShown(false) }
        // An empty frame on the desktop at once; drop picture files on it.
        function add(): void { ImageService.addEmpty("") }
        // A picture you already have (png, jpg, webp, gif, apng, bmp, svg). It is copied.
        function addPath(file: string): void { ImageService.addPath(file, "") }
        // One line per picture: id, mode and file.
        function list(): string {
            return ImageService.items.map(r => r.id + " " + r.mode + " " + r.path).join("\n")
        }
        function resetPosition(): void { ImageService.resetAllPositions() }
        // Every picture in front of the windows and games (click-through), or back on the desktop.
        function pin(): void { ImageService.setAllPinned(true) }
        function unpin(): void { ImageService.setAllPinned(false) }
    }

    IpcHandler {
        target: "notes"
        function toggle(): void { NotesService.setShown(!NotesService.active) }
        function show(): void { NotesService.setShown(true) }
        function hide(): void { NotesService.setShown(false) }
        // A new empty note (also shows the notes). Not called `new`: that is a JS keyword.
        function create(): void { NotesService.add("") }
        // Every note back into a tidy cascade (text, colour, size and pins are kept).
        function arrange(): void {
            const s = Quickshell.screens.find(x => x.name === DesktopMonitors.homeFor("notes")) ?? Quickshell.screens[0]
            if (!s) return
            const k = ShellScale.forScreen(s)
            NotesService.arrange(s.width / k, s.height / k)
        }
    }

    IpcHandler {
        target: "calendarcard"
        function toggle(): void { CalendarCardService.setShown(!CalendarCardService.shown) }
        function show(): void { CalendarCardService.setShown(true) }
        function hide(): void { CalendarCardService.setShown(false) }
        // The card's size: 2x2 (the clock / user card / weather card footprint) or full.
        function size(mode: string): void { CalendarCardService.setSize(mode) }
        function toggleSize(): void { CalendarCardService.toggleSize() }
        // An entry from a script: title, day (YYYY-MM-DD), time (HH:MM, or "" for all day),
        // kind (event | deadline). Does nothing when the day is not a real one or the title is empty.
        function add(title: string, date: string, time: string, kind: string): void {
            CalendarCardService.add({ title: title, date: date, time: time, kind: kind })
        }
        function resetPosition(): void {
            shellRoot.calendarCardResetRequested = true
            if (calendarCardWidgetLoader.item) calendarCardWidgetLoader.item.resetPosition()
            WidgetClones.clearAll("calendarcard")
            shellRoot.calendarCardResetRequested = false
        }
    }

    IpcHandler {
        target: "palettecard"
        function toggle(): void { PaletteService.setShown(!PaletteService.shown) }
        function show(): void { PaletteService.setShown(true) }
        function hide(): void { PaletteService.setShown(false) }
        // The card's size: 2x2 (the clock / user card / weather card footprint) or full.
        function size(mode: string): void { PaletteService.setSize(mode) }
        function toggleSize(): void { PaletteService.toggleSize() }
        // A new random strip. Only the palette's own colours change, never the theme.
        function shuffle(): void { PaletteService.shuffle() }
        function resetPosition(): void {
            shellRoot.paletteCardResetRequested = true
            if (paletteCardWidgetLoader.item) paletteCardWidgetLoader.item.resetPosition()
            WidgetClones.clearAll("palettecard")
            shellRoot.paletteCardResetRequested = false
        }
    }

    IpcHandler {
        target: "lyrics"
        function toggle(): void { LyricsService.setShown(!LyricsService.shown) }
        function show(): void { LyricsService.setShown(true) }
        function hide(): void { LyricsService.setShown(false) }
        // Show THIS song's lyrics this many milliseconds earlier (negative: later). Remembered
        // for the song. The widget's own "earlier" / "later" keys do the same.
        function nudge(ms: int): void { LyricsService.nudge(ms) }
        // The same for every song (a speaker or a player that is always a little off).
        function nudgeAll(ms: int): void { LyricsService.nudgeAll(ms) }
        // Back to no nudge: this song's, and the one for every song.
        function resetSync(): void { LyricsService.setTrackOffset(0); LyricsService.setSync(0) }
        // Look for the lyrics of what is playing again (skips the cache and the "nobody has
        // them" memory): after a wrong match, or once the network is back.
        function refresh(): void { LyricsService.refresh() }
        // Word-by-word timing, like karaoke, where a source has it (on by default); `off`
        // lights the whole line when it starts and jumps to the next one, no word hops.
        function words(on: bool): void { LyricsService.setWords(on) }
        // Same switch as `words`, kept so an older keybind still works: `lineMode on` is
        // Word by word off (the whole line lights at once), `lineMode off` is word by word.
        function lineMode(on: bool): void { LyricsService.setWords(!on) }
        // Show nothing in the middle for "no synced lyrics" and "instrumental" songs; the title
        // under the card stays (`off`: the messages again).
        function hideNotes(on: bool): void { LyricsService.setHideNotes(on) }
        // Where lyrics come from: `auto` takes the best provider for each song (word by word over
        // synced, Boidu first); or a provider's name (boidu, lyricsplus, lrclib, youtubemusic,
        // simpmusic, netease, qq, kugou; "neteasecloudmusic", "qqmusic" and the like work too) to use that one
        // whenever it has the song.
        function source(id: string): string { return LyricsService.setPreferred(id) ? "source: " + id : "unknown source: " + id }
        // The providers and what each found for the song on now.
        function sources(): string { return LyricsService.sourceReport() }
        // Open / close the source picker (a list of the providers, what each found, and which to use).
        function picker(): void { LyricsService.togglePicker("", -1, -1) }
        // Show the clock's numbers (how steady the player's readings are, which line is on,
        // how fast the song is sung) under the lyrics instead of the title; again to hide.
        function debug(): void { LyricsService.debug = !LyricsService.debug }
        function resetPosition(): void {
            shellRoot.lyricsResetRequested = true
            if (lyricsWidgetLoader.item) lyricsWidgetLoader.item.resetPosition()
            WidgetClones.clearAll("lyrics")
            shellRoot.lyricsResetRequested = false
        }
    }

    // Edit Desktop (services/EditMode.qml): right-click the bare desktop for
    // the menu (DesktopMenu.qml), press "Edit Desktop" and the desktop
    // shrinks into a framed card while EditTray.qml, the widget shelf, slides
    // up from the bottom edge. The wallpaper (WallpaperLayer.qml) and the
    // widgets above already know how to take part; a new desktop widget joins
    // by wrapping its content in EditStage.qml, dropping an EditChrome.qml and
    // an EditPreview.qml in its card / window (see ClockWidget.qml), and by
    // adding an entry to EditMode.widgetList (and its widgetOn / addWidget /
    // removeWidget).
    //   qs -c sekaipop ipc call desktopedit toggle   (or: open / close)
    DesktopMenu {}
    EditTray {}
    // A widget pulled up off the shelf follows the pointer in a window of its own.
    EditDragGhost {}

    // Game Mode takes the widgets away, so Edit Desktop (which is about them)
    // cannot stay open: it is closed as Game Mode comes on, and EditMode.open
    // refuses while it is on.
    Connections {
        target: GameModeService
        function onEnabledChanged() {
            if (GameModeService.enabled) {
                EditMode.closeMenu()
                EditMode.close()
            }
        }
    }

    // Edit Desktop's alignment grid and guides (EditGuides.qml, state in
    // services/EditGrid.qml, maths in EditGridMath.js): one click-through overlay
    // per monitor, mapped only while that monitor is being edited. A grid of
    // diamonds fades in while a widget is dragged, the widget is pulled onto the
    // grid and onto other widgets' lines, and for about a second after it is
    // dropped guide lines say what it lines up with (LEFT, TOP, CENTER ...,
    // same width / height). The snapping itself is in EditChrome.qml.
    //
    // Built only while Edit Desktop has a monitor (EditMode.screenName, which also stays
    // set while the card grows back, so the exit animation still plays): each one is a
    // screen-sized window with an 833-line tree and ten repeaters, and it was sitting built
    // and unmapped on every monitor the whole time you were not editing.
    LazyLoader {
        active: EditMode.screenName !== ""

        Scope {
            Variants {
                model: Quickshell.screens
                EditGuides {}
            }
        }
    }
}
