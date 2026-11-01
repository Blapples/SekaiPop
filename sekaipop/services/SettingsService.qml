pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// The Settings Panel's own options, in one place.
//
// Most of what the panel changes already has an owner (ThemeService,
// BarStyleService, ClockService, ShellScale, ...) and the panel just calls
// that owner. This singleton holds the rest: switches and numbers that used
// to be fixed values inside some file (is the weather pill on the bar? how
// long does the Quick Panel's hot edge wait?) and so had nowhere to live.
//
// Reading is a plain function call, so a binding stays live:
//
//     visible: SettingsService.flag("bar.weather")
//     interval: SettingsService.get("panel.hotDwell")
//
// Only what differs from `defaults` is saved (scripts/state/settings-state.sh,
// ~/.config/sekaipop/settings.json), so adding a new key later never
// disturbs an old file, and removing a key from `defaults` just ignores it.
//
// From a keybind or a script:
//   qs -c sekaipop ipc call options get bar.weather
//   qs -c sekaipop ipc call options set bar.weather false
//   qs -c sekaipop ipc call options reset            (everything back to default)
// (`settings` is the panel itself: `ipc call settings toggle`, see QuickPanel.qml.)
Singleton {
    id: root

    // Every option, with the value it has when nothing is saved. The key is
    // `group.name`; the type of the default is the type of the option.
    readonly property var defaults: ({
        // ===== Bar =====
        "bar.visible": true,
        "bar.hideMode": "off",          // off | auto (slides off its edge until the pointer touches that edge; reserves no space)
        "bar.compactWindow": true,     // the bar window is the strip (+ room) instead of the whole screen; off = whole screen
        "bar.perMonitor": false,        // each monitor keeps its own bar layout (off = one layout on all of them)
        "bar.workspaces": true,
        "bar.activeWindow": true,
        "bar.media": true,
        "bar.utilButtons": true,
        "bar.resources": false,         // CPU & RAM pill: off in the default bar (switch it on here)
        "bar.battery": true,
        "bar.keyboardLayout": true,
        "bar.notifications": true,
        "bar.tray": true,
        "bar.weather": true,
        "bar.date": true,
        "bar.clock": true,
        // Two newer modules: who is using the mic / screen, and pending Arch updates.
        "bar.privacy": true,
        "bar.updates": false,           // pending-updates badge: off in the default bar (switch it on here)
        // The Discord voice call you are in (needs the Discord bridge, see scripts/discordVoice).
        "bar.discord": true,
        // What a left click on the Discord pill does: "panel" opens the call panel
        // (middle = mute, right = deafen), "mute" is the old behaviour (no panel).
        "discord.leftClick": "panel",
        // Wi-Fi / Bluetooth / speaker icons in one pill.
        "bar.status": true,
        // The eight keys of the utility strip.
        "util.screenshot": true,
        "util.colorPicker": true,
        "util.keyboard": true,
        "util.mic": true,
        "util.darkMode": true,
        "util.profile": true,
        "util.record": true,
        "util.wallpapers": true,
        // ===== General =====
        "time.use24h": false,
        "weather.fahrenheit": false,
        // How a new notification announces itself: phone (the Quick Panel's phone rises and buzzes; the default) | popups (a stack of cards in the corner).
        "notify.style": "phone",
        // The Quick Panel's Notifications tile: false is do-not-disturb (nothing announces itself).
        "notify.on": true,
        // Hold announcements back (no popup / rising phone / buzz) while the focused monitor shows a fullscreen window. Same as do-not-disturb otherwise: they still land in the list, critical ones still break through.
        "notify.quietFullscreen": false,
        "notify.buzz": true,
        // Low-battery notifications at 20 / 15 / 10 / 5 % while running on battery (services/BatteryAlertService.qml). A desktop with no battery never sees them.
        "battery.alerts": true,
        "panel.hotEdge": true,
        "panel.hotDwell": 140,
        // The hot edge raises only the tip of the Quick Panel phone (its clock and date); a click on it brings the whole phone up, and moving the mouse away lowers it. Off = the hot edge opens the whole phone at once.
        "panel.hotPeek": false,
        "panel.peek": 76,
        // The Quick Panel phone drawn flat (2D: no tilt, no side wall, buttons cast their shadow straight down like the bar's pills) instead of the 2.5D pose.
        "quick.flat": false,
        // The soft shadow under every phone (Quick Panel, Apps, Wallpapers, Settings). Off = no shadow at all.
        "quick.phoneShadow": true,
        // A plain letter typed while the phone is up on Quick starts a search on the Apps screen.
        "panel.typeToSearch": true,
        // Which window opens when you pick the avatar or banner: auto (kdialog, else zenity, else yad) | kdialog | zenity (the desktop portal's dialog) | yad.
        "files.chooser": "auto",
        "launcher.webSuggestions": true,
        "launcher.clipboard": true,
        // The Apps screen's order with nothing typed: "az" (A to Z) | "used" (most opened
        // lately first, then the rest A to Z; also breaks ties in search). AppSource.qml.
        "launcher.order": "az",
        // The Apps screen's old on / off switch for its wallpaper; read only while phone.wallpaper is "".
        "launcher.lcdWallpaper": true,
        // What the phone's screens show behind them: "off", "desktop" or "picture";
        // "" = not chosen yet, launcher.lcdWallpaper decides (PanelImages.phoneMode).
        "phone.wallpaper": "",
        "pictures.framing": "",         // JSON: which part of the banner / avatar / phone picture shows (PanelImages, Framing.js)
        "lock.blur": false,
        // The gacha lockscreen's endless sparkle animations. Off = they are not built, which saves GPU while locked.
        "lock.animations": true,
        // The Settings page you left off on (a page id from SettingsFace.qml), "" = the menu.
        "settings.page": "",
        // The lockscreen's look: gacha (the Project Sekai gacha screen) | calendar (framed pictures cut out of your wallpaper, the month, power keys).
        "lock.style": "gacha",
        // Calendar lockscreen: where each frame's picture comes from: auto (the interesting parts of the wallpaper) | fixed (always the same spots).
        "lock.crop": "auto",
        // Calendar lockscreen: the pictures in colour (your theme's colours around them) | mono (black and white).
        "lock.tone": "color",
        // Calendar lockscreen: Restart and Shut down keys beside the password field.
        "lock.powerButtons": true,
        // While the screen is locked nothing but the lockscreen can be seen, so the desktop widgets are unloaded (their memory and
        // work come back) and the bar's audio tap stops; unlocking builds them again. Off = leave everything running while locked.
        "lock.sleepDesktop": true,
        // Gacha lockscreen: the line of the song that is playing (and the next one) under the clock. Asks the lyrics providers for the song, like the desktop Lyrics widget.
        "lock.lyrics": false,
        // Fingerprint unlock: a second PAM context using pam_fprintd.so runs alongside
        // the password field. Off by default — machines without fprintd will skip it cleanly.
        "lock.fingerprint": false,
        // Idle: minutes of no input before the screen locks, the screen turns off and the
        // machine sleeps, 0 = never; and whether it sleeps by suspending or hibernating.
        // hypridle waits for them (IdleService.qml writes its file). Out of the box they
        // are what the shipped hypridle.conf always had: 5, 10 and 15.
        "idle.lock": 5,
        "idle.screenOff": 10,
        "idle.sleep": 15,
        "idle.sleepAction": "suspend",
        // ===== System updates =====
        "updates.nudgeAt": 30,          // from this many updates the badge asks for attention
        "updates.aur": true,            // count AUR updates too (yay / paru, when installed)
        "updates.showZero": false,      // keep the badge on the bar when nothing is pending
        "updates.intervalMin": 30,      // how often to look (minutes)
        "updates.terminal": "kitty",    // what a click on the badge opens: kitty | foot | alacritty
        // The shell's own updates (services/UpdateService.qml, About / Update): look on its own and send one notification per newer version.
        "updates.shellNotify": true,
        "updates.shellHours": 6,        // how often it looks (hours)
        // ===== Media pill =====
        "media.leftClick": "panel",
        // ===== Region selector =====
        "region.own": true,             // the bar's screenshot / record keys use the shell's own picker
        "region.audio": "system",       // "record with sound" records: system | mic
        "region.preview": true,         // a preview card (annotate / copy / save) after a Copy or Save
        "region.previewSeconds": 6,     // how long the preview card stays (not while the pointer is on it)
        // ===== Bar and tray =====
        "bar.workspaceCount": 5,        // how many workspace badges the bar shows, 1-10
        "bar.scrollHints": true,        // a small marker on modules that react to the scroll wheel
        "tray.scroll": true,            // the wheel over a tray icon is sent to the app
        // ===== Weather =====
        "weather.location": "",         // "" = a guess from your IP; else a city name ("Paris", "Springfield, Illinois") or lat,lon
        "weather.view": "days",         // the popup's second row: days | hourly
        // Stars stuck on days in the calendar popup: "2026-10-09:2,..." (date : attribute colour 1-5).
        "calendar.marks": "",
        // ===== Desktop =====
        // Desktop Focus Mode (services/FocusService.qml): the desktop widgets go away while
        // applications are on the workspace, and what they were doing pauses.
        "focus.enabled": true,          // master switch
        "focus.hideTiled": true,        // a tiled window hides the widgets
        "focus.hideFloating": false,    // a floating window hides them too
        "focus.visualizerBackground": false, // the visualizer keeps listening while hidden
        "focus.suspend": true,          // hidden widgets pause their clocks, fetches and effects
        "focus.unload": false,          // aggressive: hidden widgets are destroyed (memory back) and rebuilt on return
        "focus.reduceEffects": false,   // costly effects (a video wallpaper) pause while a window is open
        // Low-end mode (Settings -> Desktop -> Low-end mode): one switch for the three costs that are
        // off by default because they change how the desktop behaves, not how it looks: widget windows are
        // boxes around their cards, hidden widgets are freed, a video wallpaper pauses while a window is open.
        "perf.lowEnd": false,
        // Which overview `ipc call overview ...` opens: "board" (this shell's film strip)
        // or "scroll" (the ScrollOverview Hyprland plugin, niri-style; see ScrollOverviewService.qml).
        "overview.style": "board",
        // The film strip (Overview.qml): a vertical column of workspace cards.
        "overview.position": "center",  // which side of the screen it sits on: left | center | right
        "overview.workspaces": 5,       // how many workspace cards it shows, 1-10 (scrolls when they do not fit)
        // The ScrollOverview plugin's options as set from the panel. The default of
        // each means "not set here": the plugin's own config (hyprland.lua) is then
        // left alone. They are applied live by ScrollOverviewService, never written
        // to the Hyprland override file (the plugin is not loaded yet when that file
        // runs, and Hyprland reports an unknown key then).
        "overview.layout": "",
        "overview.scale": 0,
        "overview.gap": -1,
        "dock.visible": true,
        "dock.perMonitor": false,       // one dock on every monitor (off = one dock, on the first monitor)
        "dock.position": "bottom",      // the edge the dock sits on: bottom | top | left | right
        "dock.style": "float",          // how the dock is drawn: float (the rounded, outlined pill) | transparent (no background: just the keys) | capsule (a fully rounded body in a thin rim)
        "dock.autoHide": false,         // (old switch, still counts as hideMode "auto")
        "dock.hideMode": "off",         // off | auto (always away until the pointer hits the edge) | smart (away only while a window is in the way)
        "dock.hotZone": 100,            // how deep the strip that brings a hidden dock back is, percent of the dock's thickness (Auto-hide / Smart hide only)
        "dock.iconSize": 35,            // size of a key, design pixels
        "dock.magnify": true,           // keys grow under the pointer
        "dock.magnifyAmount": 160,      // how big the key under the pointer gets, percent
        "dock.indicators": true,        // the dot under a running app
        "dock.badges": true,            // notification counts on keys
        "dock.clickMinimizes": true,    // clicking the app you are in minimizes its window
        "dock.media": true,             // the small media player at the end of the dock
        "dock.filesCommand": "xdg-open \"$HOME\"",   // what the dock's Files key runs (through sh -c) when it is not set to open the folder stack
        "dock.filesMode": "stack",      // what the Files key does: stack (the folder card, DockFilesCard.qml) | manager (runs filesCommand)
        "dock.files.folder": "",        // the folder the stack starts in: "" = Downloads, a place (Documents, Pictures...) or a path
        "dock.files.view": "grid",      // grid | list
        "dock.files.sort": "name",      // name | date | type
        "dock.files.reverse": false,    // flip the order (dates start with the newest)
        "dock.files.hidden": false,     // show hidden files (dotfiles)
        "dock.files.foldersFirst": false, // keep folders above the files (off: everything is sorted together)
        "dock.files.modified": "any",   // only what was modified: any | today | week | month | year
        "timer.pomWork": 25,            // Pomodoro: minutes of focus
        "timer.pomShort": 5,            // minutes of short break
        "timer.pomLong": 15,            // minutes of long break
        "timer.pomRounds": 4,           // focus rounds before the long break
        "dock.pinOnStartup": false,     // start every session with the dock pinned (kept shown)
        "wallpaper.enabled": true,       // Show or hide the desktop wallpaper
      
        "wallpaper.perMonitor": false,  // each monitor keeps its own wallpaper (off = one wallpaper on all of them)
        "theme.perMonitor": false,      // a monitor can wear its own theme on the bar / dock / widgets (off = one theme everywhere)
        "theme.screens": "",            // with theme.perMonitor: { monitor: theme id } as JSON (ScreenThemes.js); the main monitor has none
        "wallpaper.separateLock": false, // the lockscreen has a wallpaper of its own (off = it shows the desktop's)
        "wallpaper.folder": "",         // the folder the picker lists ("" = ~/Pictures/Wallpapers)
        "wallpaper.transition": "sekaiRing",
        "wallpaper.duration": 1300,
        "wallpaper.themedTransition": true, // the transitions wear the theme's colours (off = the classic white / pink / cyan)
        "wallpaper.thumbs": true,       // cache small thumbnails for the picker
        "wallpaper.video": true,        // play video wallpapers (off = their first frame)
        "wallpaper.mpvpaper": true,
        "wallpaper.videoPause": "fullscreen",
        "wallpaper.videoResume": "pause",
        "wallpaper.randomMinutes": 0,   // change to a random wallpaper every N minutes (0 = never)
        "wallpaper.parallax": false,    // the wallpaper drifts with the workspace
        "wallpaper.parallaxAmount": 8,  // how much bigger than the screen it is (%)
        "wallpaper.parallaxWorkspaces": 5, // how many workspaces the drift is spread over
        // ===== Wallhaven in the Wallpapers picker (WallhavenService.qml, WallhavenMath.js) =====
        // Remembered between visits; not part of a desktop preset (browsing, not the look).
        // (A merge once dropped these and set() ignores a key with no default, so every
        // choice was thrown away: tests/settings-test/keys_have_defaults_test.js guards it.)
        "wallhaven.sort": "",           // "" = relevance for a search, the month's top without one
        "wallhaven.topRange": "1M",
        "wallhaven.categories": "general,anime,people",
        "wallhaven.shape": "landscape",
        "wallhaven.atLeast": "screen",  // "screen" = the monitor the picker is on
        "wallhaven.colour": "",
        // ===== Matugen =====
        // The Matugen theme's knobs (Edit Desktop > THEME > Matugen; MatugenMath.js): the
        // scheme, which wallpaper colour leads (-1 = Auto), the contrast (-1 to 1), and
        // accents kept fixed whatever the wallpaper says ("" = not pinned).
        "matugen.scheme": "scheme-tonal-spot",
        "matugen.seed": -1,
        "matugen.contrast": 0,
        "matugen.pinA": "",
        "matugen.pinB": "",
        // ===== App colours =====
        "appTheme.kitty": false,
        "appTheme.foot": false,
        "appTheme.vscode": false,
        "appTheme.fish": false,
        "appTheme.prompt": false,      // the fish prompt: capsule pills with a hard shadow, in the theme's colours
        "appTheme.launcher": false,
        "appTheme.hyprland": true,      // Hyprland's window border colours follow the theme (matugen's, with the Wallpaper theme); on for a first run
        // ===== System colours (GTK / Qt / KDE) =====
        "systemTheme.sync": true,
        "systemTheme.gtk": true,
        "systemTheme.qt": true,
        "systemTheme.kde": true,
        "systemTheme.live": true,
        "systemTheme.bounceDark": true,
        // ===== Icons & cursor (empty = leave whatever the system has) =====
        // The shell's own icons when they are not filled: outline | broken | line-duotone | bold-duotone (filled ones are always Bold).
        "appearance.iconStyle": "outline",
        "appearance.iconTheme": "",
        "appearance.cursorTheme": "",
        "appearance.cursorSize": 24,
        // The font GTK / Qt / KDE apps use (AppFontService.qml), picked in Settings > Desktop >
        // App fonts and put back at start. "" / 0: not picked here, the system's stays.
        "appFonts.ui": "",
        "appFonts.uiSize": 0,
        "appFonts.mono": "",
        "appFonts.monoSize": 0,
        // Shell hooks: executable path, empty means disabled.
        "hooks.wallpaper": "",
        "hooks.lockWallpaper": "",
        "hooks.theme": "",
        "hooks.lock": ""
    })

    // What has been changed from the defaults.
    property var values: ({})

    // True once the saved file has been read (or there is none).
    property bool loaded: false
    // Set once something was changed this session, so the startup load below
    // can't land late and undo it.
    property bool touched: false

    function get(key) {
        const v = root.values
        return (key in v) ? v[key] : root.defaults[key]
    }

    function flag(key) {
        return !!root.get(key)
    }

    // Which bar modules are on, by the names Status_Bar.qml uses. The utility
    // strip counts as off when every one of its keys is.
    readonly property var barModules: {
        const anyKey = ["screenshot", "colorPicker", "keyboard", "mic", "darkMode", "profile", "record", "wallpapers"]
            .some(k => root.flag("util." + k))
        return {
            workspaces: root.flag("bar.workspaces"),
            activeWindow: root.flag("bar.activeWindow"),
            media: root.flag("bar.media"),
            utilButtons: root.flag("bar.utilButtons") && anyKey,
            resources: root.flag("bar.resources"),
            battery: root.flag("bar.battery"),
            keyboardLayout: root.flag("bar.keyboardLayout"),
            notifications: root.flag("bar.notifications"),
            tray: root.flag("bar.tray"),
            weather: root.flag("bar.weather"),
            date: root.flag("bar.date"),
            clock: root.flag("bar.clock"),
            privacy: root.flag("bar.privacy"),
            updates: root.flag("bar.updates"),
            discord: root.flag("bar.discord"),
            status: root.flag("bar.status")
        }
    }

    // Number of keys that differ from the defaults (shown on About).
    readonly property int changedCount: Object.keys(root.values).length

    function set(key, value) {
        if (!(key in root.defaults))
            return
        root.touched = true
        // Nothing to do when the option already has this value. Sliders (SettingSlider.qml)
        // call this on every mouse-move event, and most of those land on the value the
        // slider already snapped to; each call used to replace `values`, which re-runs
        // every binding that reads an option (about 190 of them across the shell), and to
        // start a save of the settings file. Only once the saved file has been read, so a
        // change made before that still gets written.
        if (root.loaded && root.get(key) === value)
            return
        const next = Object.assign({}, root.values)
        if (value === root.defaults[key])
            delete next[key]
        else
            next[key] = value
        root.values = next
        saver.save(JSON.stringify(next))
    }

    function toggle(key) {
        root.set(key, !root.flag(key))
    }

    // Wears a preset's switches (DesktopPresetService.qml): every key the
    // preset is allowed to touch becomes what the preset says, or its default
    // if the preset doesn't mention it (a preset only stores what differs
    // from the defaults); the keys `keeps(key)` is true for stay as they are.
    // One write for the whole lot. Unknown keys and values of the wrong type
    // are dropped, the same way restore() does.
    function applyPreset(incoming, keeps) {
        root.touched = true
        const next = {}
        for (const k in root.values) {
            if (keeps(k))
                next[k] = root.values[k]
        }
        for (const k in incoming) {
            if (keeps(k) || !(k in root.defaults))
                continue
            if (typeof incoming[k] === typeof root.defaults[k] && incoming[k] !== root.defaults[k])
                next[k] = incoming[k]
        }
        root.values = next
        saver.save(JSON.stringify(next))
    }

    function reset() {
        root.touched = true
        root.values = ({})
        saver.save("{}")
    }

    // ===== persistence =====
    readonly property string script: Directories.script("state/settings-state.sh")

    function restore(text) {
        try {
            const j = JSON.parse(text)
            const next = {}
            for (const k in j) {
                // Only keys we know, of the type we expect.
                if (k in root.defaults && typeof j[k] === typeof root.defaults[k] && j[k] !== root.defaults[k])
                    next[k] = j[k]
            }
            root.values = next
        } catch (e) {
            console.warn("SettingsService: couldn't read settings.json (" + e + ") — using the defaults")
        }
    }

    Process {
        running: true
        command: ["sh", root.script, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.touched && text.trim() !== "")
                    root.restore(text)
                root.loaded = true
            }
        }
        onExited: root.loaded = true
    }

    Process {
        id: saver

        property string pending: ""

        function save(json) {
            if (saver.running) {
                saver.pending = json
                return
            }
            saver.pending = ""
            saver.exec(["sh", root.script, "save", json])
        }

        onExited: {
            if (saver.pending !== "") {
                const json = saver.pending
                saver.pending = ""
                saver.exec(["sh", root.script, "save", json])
            }
        }
    }

    IpcHandler {
        target: "options"

        function get(key: string): string {
            return key + " = " + JSON.stringify(root.get(key))
        }

        function set(key: string, value: string): void {
            if (!(key in root.defaults))
                return
            const d = root.defaults[key]
            if (typeof d === "boolean")
                root.set(key, value === "true" || value === "1" || value === "on")
            else if (typeof d === "number") {
                const n = Number(value)
                if (isFinite(n))
                    root.set(key, n)
            }
            else
                root.set(key, value)
        }

        function reset(): void {
            root.reset()
        }
    }
}
