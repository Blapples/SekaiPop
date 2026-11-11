import QtQuick
import qs.services
import qs.modules.common

// Desktop: the wallpaper and how it changes, the widgets on the desktop,
// the dock, and the effects that touch the whole screen.
SettingsPage {
    id: page

    readonly property var src: host ? host.source : null
    onVisibleChanged: if (visible) AppThemeService.refreshStatus()

    // The lockscreen wallpaper's name (no folder, no extension), for its tile.
    readonly property string lockName: {
        const p = WallpaperService.lockCurrentPath
        if (!p)
            return ""
        const f = p.slice(p.lastIndexOf("/") + 1)
        const i = f.lastIndexOf(".")
        return i > 0 ? f.slice(0, i) : f
    }

    SectionCard {
        title: "Wallpaper"

        SettingAction {
            icon: "wallpaper"
            label: "Wallpapers"
            detail: "Open the picker"
            onActivated: if (page.host) page.host.wallpapersRequested()
        }

        SettingAction {
            icon: "folder_open"
            label: "Wallpaper folder"
            detail: WallpaperService.directoryShort + (WallpaperService.customFolder ? "" : " (default)")
            onActivated: WallpaperService.pickFolder("settings")
        }

        SettingAction {
            visible: WallpaperService.customFolder
            icon: "restart_alt"
            label: "Use the default folder"
            detail: "Back to ~/Pictures/Wallpapers"
            onActivated: WallpaperService.resetFolder()
        }
        SettingToggle {
            icon: "image"
            label: "Desktop wallpaper"
            detail: "ON or OFF the desktop wallpaper"
            checked: SettingsService.flag("wallpaper.enabled")
            onToggled: SettingsService.toggle("wallpaper.enabled")
        }
        SettingChoice {
            label: "Transition"
            sublabel: "How one wallpaper replaces another (Random: a different one each time)"
            current: WallpaperService.transitionSetting
            options: [
                { id: "sekaiRing", label: "Ring", icon: "radio_button_unchecked" },
                { id: "star", label: "Star", icon: "star" },
                { id: "sekaiIris", label: "Iris", icon: "lens_blur" },
                { id: "sekaiFlash", label: "Flash", icon: "flash_on" },
                { id: "diagonalBlocks", label: "Blocks", icon: "grid_view" },
                { id: "fade", label: "Fade", icon: "blur_on" },
                { id: "random", label: "Random", icon: "shuffle" }
            ]
            onPicked: id => SettingsService.set("wallpaper.transition", id)
        }

        SettingToggle {
            icon: "palette"
            label: "Transition colours"
            detail: SettingsService.flag("wallpaper.themedTransition") ? "Follow the theme (or matugen)" : "Classic white, pink and cyan"
            checked: SettingsService.flag("wallpaper.themedTransition")
            onToggled: SettingsService.toggle("wallpaper.themedTransition")
        }

        SettingSlider {
            width: page.halfWidth
            icon: "timelapse"
            label: "Ring, star and blocks speed"
            from: 500
            to: 3000
            step: 100
            suffix: " ms"
            value: SettingsService.get("wallpaper.duration")
            onMoved: v => SettingsService.set("wallpaper.duration", v)
        }

        SettingToggle {
            icon: "desktop_windows"
            label: "One wallpaper per monitor"
            detail: SettingsService.flag("wallpaper.perMonitor") ? "The picker sets the monitor it is on" : "Same wallpaper on every monitor"
            checked: SettingsService.flag("wallpaper.perMonitor")
            onToggled: WallpaperService.setPerMonitor(!SettingsService.flag("wallpaper.perMonitor"))
        }

        // ThemeService, "one theme per monitor": the bar, dock, widgets and Quick Panel on a
        // monitor wear its theme; the theme pickers set the monitor they are open on.
        SettingToggle {
            icon: "palette"
            label: "One theme per monitor"
            detail: SettingsService.flag("theme.perMonitor") ? "The theme picker sets the monitor it is on" : "Same theme on every monitor"
            checked: SettingsService.flag("theme.perMonitor")
            onToggled: SettingsService.set("theme.perMonitor", !SettingsService.flag("theme.perMonitor"))
        }

        SettingToggle {
            icon: "lock"
            label: "Separate Lockscreen Wallpaper"
            detail: SettingsService.flag("wallpaper.separateLock") ? "The lockscreen keeps its own" : "Lockscreen shows the desktop's"
            checked: SettingsService.flag("wallpaper.separateLock")
            onToggled: WallpaperService.setSeparateLock(!SettingsService.flag("wallpaper.separateLock"))
        }

        // Only while the option is on: opens the picker on its Lockscreen tab.
        SettingAction {
            visible: SettingsService.flag("wallpaper.separateLock")
            icon: "wallpaper"
            label: "Lockscreen wallpaper"
            detail: page.lockName !== "" ? page.lockName : "Open the picker"
            onActivated: if (page.host) page.host.lockWallpapersRequested()
        }

        SettingToggle {
            icon: "photo_size_select_large"
            label: "Thumbnail cache"
            detail: "Small copies for the picker"
            checked: SettingsService.flag("wallpaper.thumbs")
            onToggled: {
                SettingsService.toggle("wallpaper.thumbs")
                WallpaperService.scanThumbs()
            }
        }

        SettingAction {
            icon: "delete_sweep"
            label: "Clear thumbnails"
            detail: "Made again when needed"
            onActivated: {
                WallpaperService.clearThumbCache()
                WallpaperService.scanThumbs()
            }
        }

        SettingAction {
            icon: "shuffle"
            label: "Random wallpaper"
            detail: "Pick one now"
            onActivated: WallpaperService.random()
        }

        SettingSlider {
            width: page.halfWidth
            icon: "autorenew"
            label: "Change randomly every"
            from: 0
            to: 240
            step: 5
            suffix: " min"
            specialValue: 0
            specialText: "Never"
            value: SettingsService.get("wallpaper.randomMinutes")
            onMoved: v => SettingsService.set("wallpaper.randomMinutes", v)
        }

        SettingToggle {
            icon: "movie"
            label: "Play video wallpapers"
            detail: !SettingsService.flag("wallpaper.video") ? "First frame only"
                : SettingsService.flag("wallpaper.mpvpaper") ? "Through mpvpaper" : "Needs qt6-multimedia"
            checked: SettingsService.flag("wallpaper.video")
            onToggled: SettingsService.toggle("wallpaper.video")
        }

        SettingToggle {
            icon: "speed"
            label: "Use mpvpaper for video"
            detail: SettingsService.flag("wallpaper.mpvpaper") ? "Hardware decoding, lighter" : "Built-in player"
            checked: SettingsService.flag("wallpaper.mpvpaper")
            onToggled: SettingsService.toggle("wallpaper.mpvpaper")
        }

        SettingChoice {
            label: "Pause video when"
            sublabel: "Stops the live wallpaper while it is covered, to save the GPU"
            current: SettingsService.get("wallpaper.videoPause")
            options: [
                { id: "never", label: "Never", icon: "play_arrow" },
                { id: "fullscreen", label: "Fullscreen", icon: "fullscreen" },
                { id: "windows", label: "Any window", icon: "web_asset" }
            ]
            onPicked: id => SettingsService.set("wallpaper.videoPause", id)
        }

        SettingChoice {
            label: "When it pauses"
            sublabel: "Pause continues where it stopped; Restart starts the video over"
            current: SettingsService.get("wallpaper.videoResume")
            options: [
                { id: "pause", label: "Pause", icon: "pause" },
                { id: "restart", label: "Restart", icon: "replay" }
            ]
            onPicked: id => SettingsService.set("wallpaper.videoResume", id)
        }

        SettingToggle {
            icon: "layers"
            label: "Parallax"
            detail: "Drifts with the workspace"
            checked: SettingsService.flag("wallpaper.parallax")
            onToggled: SettingsService.toggle("wallpaper.parallax")
        }

        SettingSlider {
            width: page.halfWidth
            icon: "zoom_out_map"
            label: "Parallax amount"
            from: 2
            to: 30
            step: 1
            suffix: " %"
            value: SettingsService.get("wallpaper.parallaxAmount")
            onMoved: v => SettingsService.set("wallpaper.parallaxAmount", v)
        }

        SettingSlider {
            width: page.halfWidth
            icon: "grid_view"
            label: "Parallax workspaces"
            from: 2
            to: 10
            step: 1
            value: SettingsService.get("wallpaper.parallaxWorkspaces")
            onMoved: v => SettingsService.set("wallpaper.parallaxWorkspaces", v)
        }
    }

    SectionCard {
        title: "Widgets"

        SettingChoice {
            label: "Default monitor"
            sublabel: "Where a widget goes when it has no monitor of its own, or its monitor is switched off. Chosen by name, so a restart cannot swap them"
            current: DesktopMonitors.defaultScreen
            options: DesktopMonitors.choices
            onPicked: id => DesktopMonitors.setDefault(id)
        }

        SettingChoice {
            label: "To-Do monitor"
            sublabel: "Automatic is the default monitor"
            current: DesktopMonitors.homes["todo"] ?? ""
            options: DesktopMonitors.choices
            onPicked: id => DesktopMonitors.setHome("todo", id)
        }

        SettingChoice {
            label: "Sticky Notes monitor"
            sublabel: "Automatic is the default monitor"
            current: DesktopMonitors.homes["notes"] ?? ""
            options: DesktopMonitors.choices
            onPicked: id => DesktopMonitors.setHome("notes", id)
        }

        SettingToggle {
            icon: "schedule"
            label: "Clock"
            checked: ClockService.shown
            onToggled: ClockService.setShown(!ClockService.shown)
        }

        SettingToggle {
            icon: "person"
            label: "User card"
            checked: UserCardService.shown
            onToggled: UserCardService.setShown(!UserCardService.shown)
        }

        SettingToggle {
            icon: "partly_cloudy_day"
            label: "Weather card"
            detail: "Place and unit: Settings > General > Weather"
            checked: WeatherCardService.shown
            onToggled: WeatherCardService.setShown(!WeatherCardService.shown)
        }

        SettingChoice {
            label: "Weather card style"
            sublabel: "Minimal keeps the plate and the next hours, nothing else. Same 2 x 2 size"
            current: WeatherCardService.style
            options: [
                { id: "classic", label: "Classic", icon: "dashboard" },
                { id: "minimal", label: "Minimal", icon: "crop_square" }
            ]
            onPicked: id => WeatherCardService.setStyle(id)
        }

        SettingToggle {
            icon: "calendar_month"
            label: "Calendar card"
            checked: CalendarCardService.shown
            onToggled: CalendarCardService.setShown(!CalendarCardService.shown)
        }

        SettingChoice {
            label: "Calendar card size"
            sublabel: "2 x 2 is the same size as the clock, user and weather cards"
            current: CalendarCardService.size
            options: [
                { id: "full", label: "Full", icon: "open_in_full" },
                { id: "2x2", label: "2 x 2", icon: "close_fullscreen" }
            ]
            onPicked: id => CalendarCardService.setSize(id)
        }

        SettingToggle {
            icon: "palette"
            label: "Palette card"
            checked: PaletteService.shown
            onToggled: PaletteService.setShown(!PaletteService.shown)
        }

        SettingChoice {
            label: "Palette card size"
            sublabel: "2 x 2 is the same size as the clock, user and weather cards"
            current: PaletteService.size
            options: [
                { id: "full", label: "Full", icon: "open_in_full" },
                { id: "2x2", label: "2 x 2", icon: "close_fullscreen" }
            ]
            onPicked: id => PaletteService.setSize(id)
        }

        SettingToggle {
            icon: "lyrics"
            label: "Lyrics"
            detail: "The words of the song that is playing, on the desktop"
            checked: LyricsService.shown
            onToggled: LyricsService.setShown(!LyricsService.shown)
        }

        SettingChoice {
            label: "Lyrics source"
            sublabel: "Auto takes the best one for each song, Boidu first. Pick one to use it whenever it has the song"
            current: LyricsService.preferred
            options: [{ id: "auto", label: "Auto", icon: "auto_awesome" }].concat(LyricsService.providers.map(p => ({ id: p.id, label: p.name })))
            onPicked: id => LyricsService.setPreferred(id)
        }

        SettingToggle {
            icon: "text_fields"
            label: "Word by word"
            detail: "Light each word when it is sung, where a source has the timing. Off lights the whole line at once"
            checked: LyricsService.wordsOn
            onToggled: LyricsService.setWords(!LyricsService.wordsOn)
        }

        SettingToggle {
            icon: "comments_disabled"
            label: "Hide no-lyrics messages"
            detail: "Show nothing in the middle when a song has no synced lyrics or is an instrumental. The track title stays"
            checked: LyricsService.hideNotes
            onToggled: LyricsService.setHideNotes(!LyricsService.hideNotes)
        }

        SettingToggle {
            icon: "task_alt"
            label: "To-Do"
            checked: TodoService.shown
            onToggled: TodoService.setShown(!TodoService.shown)
        }

        SettingChoice {
            label: "To-Do size"
            sublabel: "2 x 2 is the same size as the clock, user and weather cards"
            current: TodoService.size
            options: [
                { id: "full", label: "Full", icon: "open_in_full" },
                { id: "2x2", label: "2 x 2", icon: "close_fullscreen" }
            ]
            onPicked: id => TodoService.setSize(id)
        }

        SettingToggle {
            icon: "sticky_note_2"
            label: "Sticky notes"
            detail: "Move, resize, pin. Esc leaves the text"
            checked: NotesService.active
            onToggled: NotesService.setShown(!NotesService.active)
        }

        SettingToggle {
            icon: "graphic_eq"
            label: "Visualizer"
            detail: "Needs python3 + numpy (or cava)"
            checked: VisualizerService.shown
            onToggled: VisualizerService.setShown(!VisualizerService.shown)
        }

        SettingToggle {
            icon: "image"
            label: "Custom images"
            detail: ImageService.count === 0 ? "None yet: add a frame below" : ImageService.count + (ImageService.count === 1 ? " frame" : " frames") + ", edit them in Edit Desktop"
            checked: ImageService.shown
            onToggled: ImageService.setShown(!ImageService.shown)
        }

        SettingAction {
            icon: "add_photo_alternate"
            label: "Add an image frame"
            detail: "Appears on the desktop; drop PNG, JPG, WebP, SVG or GIF files on it"
            busy: ImageService.busy
            onActivated: {
                ImageService.setShown(true)
                ImageService.addEmpty(EditMode.homeScreen(""))
            }
        }

        SettingToggle {
            icon: EditMode.widgetsLocked ? "lock" : "lock_open"
            label: "Lock widgets"
            detail: EditMode.widgetsLocked ? "Move in Edit Desktop" : "Drag on the desktop"
            checked: EditMode.widgetsLocked
            onToggled: EditMode.toggleWidgetsLocked()
        }

        SettingChoice {
            label: "Clock design"
            current: String(ClockService.design)
            options: [
                { id: "0", label: "Keys", icon: "piano" },
                { id: "1", label: "Tower", icon: "view_column" },
                { id: "2", label: "Sticker", icon: "sticky_note_2" },
                { id: "3", label: "Stack", icon: "stacks" }
            ]
            onPicked: id => ClockService.setDesign(Number(id))
        }

        SettingChoice {
            label: "Visualizer style"
            sublabel: "Sekai keys, Tide, Ribbons, Scope, Pulse, or end4's"
            current: VisualizerService.style
            options: [
                { id: "sekai", label: "Sekai", icon: "piano" },
                { id: "bars", label: "Bars", icon: "equalizer" },
                { id: "aurora", label: "Aurora", icon: "blur_on" },
                { id: "ring", label: "Ring", icon: "radio_button_unchecked" },
                { id: "dots", label: "Dots", icon: "more_horiz" },
                { id: "mirror", label: "Mirror", icon: "vertical_align_center" },
                { id: "tide", label: "Tide", icon: "waves" },
                { id: "ribbons", label: "Ribbons", icon: "ssid_chart" },
                { id: "scope", label: "Scope", icon: "monitor_heart" },
                { id: "pulse", label: "Pulse", icon: "blur_on" }
            ]
            onPicked: id => VisualizerService.setStyle(id)
        }

        SettingChoice {
            label: "Media pill visualizer"
            sublabel: "Little bars or wave in the bar's media pill (needs cava)"
            current: VisualizerService.pillStyle
            options: [
                { id: "none", label: "Off" },
                { id: "dots", label: "Dots" },
                { id: "wave", label: "Wave" }
            ]
            onPicked: id => VisualizerService.setPillStyle(id)
        }

        SettingChoice {
            label: "Visualizer colors"
            current: String(VisualizerService.colorMode)
            options: [
                { id: "0", label: "Cover" },
                { id: "1", label: "Sekai" },
                { id: "2", label: "Theme" }
            ]
            onPicked: id => VisualizerService.setColorMode(Number(id))
        }

        SettingChoice {
            label: "Visualizer size"
            current: String(VisualizerService.sizeIndex)
            options: [
                { id: "0", label: "S" },
                { id: "1", label: "M" },
                { id: "2", label: "L" },
                { id: "3", label: "XL" }
            ]
            onPicked: id => VisualizerService.setSize(Number(id))
        }

        SettingChoice {
            label: "Visualizer direction"
            sublabel: "Bands only. Vertical goes up the right edge; drag it to the left in Edit Desktop"
            current: VisualizerService.vertical ? "v" : "h"
            options: [
                { id: "h", label: "Horizontal", icon: "swap_horiz" },
                { id: "v", label: "Vertical", icon: "swap_vert" }
            ]
            onPicked: id => VisualizerService.setVertical(id === "v")
        }

        SettingChoice {
            label: "Visualizer performance"
            sublabel: "Lite for weak laptops"
            current: String(VisualizerService.perf)
            options: [
                { id: "0", label: "Full" },
                { id: "1", label: "Balanced" },
                { id: "2", label: "Lite" }
            ]
            onPicked: id => VisualizerService.setPerf(Number(id))
        }

        SettingSlider {
            width: page.halfWidth
            icon: "equalizer"
            label: "Visualizer sensitivity"
            from: 0.5
            to: 2.5
            step: 0.1
            decimals: 1
            suffix: "x"
            value: VisualizerService.sensitivity
            onMoved: v => VisualizerService.setSensitivity(v)
        }

        SettingToggle {
            icon: "pause_circle"
            label: "Visualizer: stay when paused"
            detail: VisualizerService.stayWhenPaused ? "Press play on the card" : "Only while music plays"
            checked: VisualizerService.stayWhenPaused
            onToggled: VisualizerService.setStayWhenPaused(!VisualizerService.stayWhenPaused)
        }

        SettingToggle {
            icon: "hearing"
            label: "Visualizer: listen to all audio"
            detail: VisualizerService.alwaysListen ? "Games and any app" : "Only media players"
            checked: VisualizerService.alwaysListen
            onToggled: VisualizerService.setAlwaysListen(!VisualizerService.alwaysListen)
        }

        SettingToggle {
            icon: "music_note"
            label: "Visualizer: note analyzer"
            detail: VisualizerService.analyzer ? "Kick, snare, hats, bass, voice" : "Plain cava bands"
            checked: VisualizerService.analyzer
            onToggled: VisualizerService.setAnalyzer(!VisualizerService.analyzer)
        }

        SettingToggle {
            icon: "tune"
            label: "Visualizer: use aubio"
            detail: VisualizerService.useAubio ? "python-aubio, if installed" : "Built-in tracker"
            checked: VisualizerService.useAubio
            onToggled: VisualizerService.setUseAubio(!VisualizerService.useAubio)
        }

        SettingAction {
            icon: "stylus"
            label: "Edit Desktop"
            detail: "Drag widgets around"
            onActivated: if (page.host) page.host.desktopEditRequested()
        }
    }

    // Desktop widget plugins (services/PluginService.qml, docs/PLUGIN-SETTINGS.md): what is
    // installed, what did not load and why, and each plugin's settings.
    SettingsPluginsCard {
        settingsPage: page
    }

    // Desktop Focus Mode (services/FocusService.qml, modules/sekai/desktopWidgets/FocusGate.qml):
    // the widgets above go away while applications are on the workspace.
    SectionCard {
        title: "Desktop Focus"

        SettingToggle {
            icon: "center_focus_strong"
            label: "Desktop Focus Mode"
            detail: SettingsService.flag("focus.enabled") ? "Widgets leave while you work" : "OFF"
            checked: SettingsService.flag("focus.enabled")
            onToggled: SettingsService.toggle("focus.enabled")
        }

        SettingToggle {
            icon: "view_quilt"
            label: "Hide with tiled windows"
            detail: SettingsService.flag("focus.hideTiled") ? "A tiled window hides them" : "Tiled windows leave them"
            checked: SettingsService.flag("focus.hideTiled")
            opacity: SettingsService.flag("focus.enabled") ? 1 : 0.5
            onToggled: SettingsService.toggle("focus.hideTiled")
        }

        SettingToggle {
            icon: "picture_in_picture"
            label: "Hide with floating windows"
            detail: SettingsService.flag("focus.hideFloating") ? "A floating window hides them" : "Floating windows leave them"
            checked: SettingsService.flag("focus.hideFloating")
            opacity: SettingsService.flag("focus.enabled") ? 1 : 0.5
            onToggled: SettingsService.toggle("focus.hideFloating")
        }

        SettingToggle {
            icon: "pause_circle"
            label: "Suspend hidden widgets"
            detail: SettingsService.flag("focus.suspend") ? "Clocks and fetches pause" : "Hidden widgets keep working"
            checked: SettingsService.flag("focus.suspend")
            opacity: SettingsService.flag("focus.enabled") ? 1 : 0.5
            onToggled: SettingsService.toggle("focus.suspend")
        }

        SettingToggle {
            icon: "delete_sweep"
            label: "Unload hidden widgets"
            detail: !SettingsService.flag("focus.suspend") ? "Needs suspension on"
                : (SettingsService.flag("focus.unload") ? "Freed while hidden, rebuilt on return" : "Kept in memory while hidden")
            checked: SettingsService.flag("focus.unload")
            opacity: SettingsService.flag("focus.enabled") ? 1 : 0.5
            onToggled: SettingsService.toggle("focus.unload")
        }

        SettingToggle {
            icon: "graphic_eq"
            label: "Visualizer in background"
            detail: !SettingsService.flag("focus.suspend") ? "Listening (nothing is suspended)"
                : (SettingsService.flag("focus.visualizerBackground") ? "Keeps listening while hidden" : "Stops listening while hidden")
            checked: SettingsService.flag("focus.visualizerBackground")
            opacity: SettingsService.flag("focus.enabled") ? 1 : 0.5
            onToggled: SettingsService.toggle("focus.visualizerBackground")
        }

        SettingToggle {
            icon: "speed"
            label: "Reduce effects while focused"
            detail: SettingsService.flag("focus.reduceEffects") ? "Video wallpaper pauses" : "Effects stay as they are"
            checked: SettingsService.flag("focus.reduceEffects")
            opacity: SettingsService.flag("focus.enabled") ? 1 : 0.5
            onToggled: SettingsService.toggle("focus.reduceEffects")
        }
    }

    // One switch for the three savings that change how the desktop behaves (not how it looks);
    // services/SettingsService.qml `perf.lowEnd`, read by EditMode.qml and FocusService.qml.
    SectionCard {
        title: "Low-end mode"

        SettingToggle {
            icon: "battery_saver"
            label: "Low-end mode"
            detail: SettingsService.flag("perf.lowEnd")
                ? "Widget windows shrink to their cards, hidden widgets are freed, a video wallpaper pauses while a window is open"
                : "Off: nothing is changed"
            checked: SettingsService.flag("perf.lowEnd")
            onToggled: SettingsService.toggle("perf.lowEnd")
        }
    }

    SectionCard {
        title: "Dock"

        SettingToggle {
            icon: "dock_to_bottom"
            label: "Show dock"
            checked: SettingsService.flag("dock.visible")
            onToggled: SettingsService.toggle("dock.visible")
        }

        SettingToggle {
            icon: "monitor"
            label: "Dock on every monitor"
            detail: SettingsService.flag("dock.perMonitor")
                ? "One dock per monitor · apps on that monitor"
                : "One dock, on " + (SettingsService.get("dock.screen") || "the first monitor")
            checked: SettingsService.flag("dock.perMonitor")
            onToggled: SettingsService.toggle("dock.perMonitor")
        }

        SettingChoice {
            label: "Style"
            sublabel: "How the dock is drawn"
            current: SettingsService.get("dock.style")
            options: [
                { id: "float", label: "Float", edge: SettingsService.get("dock.position"), variant: "float" },
                { id: "transparent", label: "Transparent", edge: SettingsService.get("dock.position"), variant: "transparent" },
                { id: "capsule", label: "Capsule", edge: SettingsService.get("dock.position"), variant: "capsule" }
            ]
            onPicked: id => SettingsService.set("dock.style", id)
        }

        SettingChoice {
            label: "Position"
            sublabel: "Which edge the dock sits on"
            current: SettingsService.get("dock.position")
            options: [
                { id: "bottom", label: "Bottom", edge: "bottom" },
                { id: "top", label: "Top", edge: "top" },
                { id: "left", label: "Left", edge: "left" },
                { id: "right", label: "Right", edge: "right" }
            ]
            onPicked: id => SettingsService.set("dock.position", id)
        }

        SettingStepper {
            icon: "format_size"
            label: "Icon size"
            from: 28
            to: 56
            step: 1
            value: SettingsService.get("dock.iconSize")
            onMoved: v => SettingsService.set("dock.iconSize", Math.round(v))
        }

        SettingToggle {
            icon: "push_pin"
            label: "Keep above windows"
            detail: PinnedAppsService.dockPinned ? "Pinned" : "Under windows"
            checked: PinnedAppsService.dockPinned
            onToggled: PinnedAppsService.toggleDockPinned()
        }

        SettingChoice {
            label: "Hiding"
            sublabel: PinnedAppsService.dockPinned ? "Off while pinned"
                : "Auto-hide: away until you touch the edge. Smart: away only while a window is in the way"
            current: SettingsService.get("dock.hideMode") !== "off"
                ? SettingsService.get("dock.hideMode")
                : (SettingsService.flag("dock.autoHide") ? "auto" : "off")
            options: [
                { id: "off", label: "Always shown", icon: "visibility" },
                { id: "auto", label: "Auto-hide", icon: "vertical_align_bottom" },
                { id: "smart", label: "Smart hide", icon: "auto_awesome" }
            ]
            onPicked: id => {
                SettingsService.set("dock.hideMode", id)
                SettingsService.set("dock.autoHide", false)
            }
        }

        // Only while the dock hides (Auto-hide or Smart hide): how deep the strip along the
        // edge is that brings it back. Lower = you have to push closer to the edge.
        SettingSlider {
            width: page.halfWidth
            visible: (SettingsService.get("dock.hideMode") !== "off"
                      ? SettingsService.get("dock.hideMode")
                      : (SettingsService.flag("dock.autoHide") ? "auto" : "off")) !== "off"
            icon: "height"
            label: "Reveal zone"
            from: 10
            to: 100
            step: 5
            suffix: " %"
            value: SettingsService.get("dock.hotZone")
            onMoved: v => SettingsService.set("dock.hotZone", Math.round(v))
        }

        SettingToggle {
            icon: "keep"
            label: "Pin on startup"
            detail: "Starts every session kept shown"
            checked: SettingsService.flag("dock.pinOnStartup")
            onToggled: SettingsService.toggle("dock.pinOnStartup")
        }
    }

    SectionCard {
        title: "Dock look"

        SettingToggle {
            icon: "zoom_in"
            label: "Magnification"
            detail: "Keys grow under the pointer"
            checked: SettingsService.flag("dock.magnify")
            onToggled: SettingsService.toggle("dock.magnify")
        }

        SettingStepper {
            icon: "open_in_full"
            label: "Magnification size"
            from: 110
            to: 200
            step: 5
            suffix: " %"
            value: SettingsService.get("dock.magnifyAmount")
            onMoved: v => SettingsService.set("dock.magnifyAmount", Math.round(v))
        }

        SettingToggle {
            icon: "fiber_manual_record"
            label: "Running dots"
            detail: "A diamond under every open app"
            checked: SettingsService.flag("dock.indicators")
            onToggled: SettingsService.toggle("dock.indicators")
        }

        SettingToggle {
            icon: "notifications"
            label: "Notification badges"
            detail: "A count on the apps that have notifications"
            checked: SettingsService.flag("dock.badges")
            onToggled: SettingsService.toggle("dock.badges")
        }

        SettingToggle {
            icon: "minimize"
            label: "Click to minimize"
            detail: "Clicking the app you are in puts its window away"
            checked: SettingsService.flag("dock.clickMinimizes")
            onToggled: SettingsService.toggle("dock.clickMinimizes")
        }

        SettingToggle {
            icon: "music_note"
            label: "Media player"
            detail: "A small player at the end of the dock"
            checked: SettingsService.flag("dock.media")
            onToggled: SettingsService.toggle("dock.media")
        }
    }

    SectionCard {
        title: "Dock tools"

        SettingToggle {
            icon: "search"
            label: "Search"
            detail: "Opens the launcher"
            checked: PinnedAppsService.hasTool("search")
            onToggled: PinnedAppsService.toggleTool("search")
        }

        SettingToggle {
            icon: "folder"
            label: "Files"
            detail: SettingsService.get("dock.filesMode") === "manager"
                ? "Opens your file manager; right-click for Downloads, Documents..."
                : "Opens a stack of your files; right-click for Downloads, Documents..."
            checked: PinnedAppsService.hasTool("files")
            onToggled: PinnedAppsService.toggleTool("files")
        }

        SettingToggle {
            icon: "content_paste"
            label: "Clipboard"
            detail: "The last things you copied"
            checked: PinnedAppsService.hasTool("clipboard")
            onToggled: PinnedAppsService.toggleTool("clipboard")
        }

        SettingToggle {
            icon: "inventory_2"
            label: "Shelf"
            detail: "Drop files or text on it to keep them for later"
            checked: PinnedAppsService.hasTool("shelf")
            onToggled: PinnedAppsService.toggleTool("shelf")
        }

        SettingToggle {
            icon: "timer"
            label: "Timer"
            detail: "Timer, stopwatch and pomodoro"
            checked: PinnedAppsService.hasTool("timer")
            onToggled: PinnedAppsService.toggleTool("timer")
        }

        SettingStepper {
            icon: "nutrition"
            label: "Pomodoro focus"
            from: 5
            to: 90
            step: 5
            suffix: " min"
            value: SettingsService.get("timer.pomWork")
            onMoved: v => SettingsService.set("timer.pomWork", Math.round(v))
        }

        SettingStepper {
            icon: "coffee"
            label: "Short break"
            from: 1
            to: 30
            step: 1
            suffix: " min"
            value: SettingsService.get("timer.pomShort")
            onMoved: v => SettingsService.set("timer.pomShort", Math.round(v))
        }

        SettingStepper {
            icon: "weekend"
            label: "Long break"
            from: 5
            to: 60
            step: 5
            suffix: " min"
            value: SettingsService.get("timer.pomLong")
            onMoved: v => SettingsService.set("timer.pomLong", Math.round(v))
        }

        SettingStepper {
            icon: "repeat"
            label: "Rounds before the long break"
            from: 2
            to: 8
            step: 1
            value: SettingsService.get("timer.pomRounds")
            onMoved: v => SettingsService.set("timer.pomRounds", Math.round(v))
        }
    }

    SectionCard {
        title: "Files stack"

        SettingChoice {
            label: "Files key"
            sublabel: "What clicking it does (middle-click always opens the file manager)"
            current: SettingsService.get("dock.filesMode")
            options: [
                { id: "stack", label: "Folder stack", icon: "folder_open" },
                { id: "manager", label: "File manager", icon: "open_in_new" }
            ]
            onPicked: id => SettingsService.set("dock.filesMode", id)
        }

        SettingText {
            label: "Folder"
            sublabel: "Downloads, Documents, Pictures, Videos, Music, Desktop, Trash, or a path like ~/Projects"
            value: SettingsService.get("dock.files.folder")
            placeholder: "Downloads"
            onSubmitted: text => SettingsService.set("dock.files.folder", text.trim())
            onCleared: SettingsService.set("dock.files.folder", "")
        }

        SettingChoice {
            label: "View"
            current: SettingsService.get("dock.files.view")
            options: [
                { id: "grid", label: "Grid", icon: "grid_view" },
                { id: "list", label: "List", icon: "view_list" }
            ]
            onPicked: id => SettingsService.set("dock.files.view", id)
        }

        SettingChoice {
            label: "Sort by"
            current: SettingsService.get("dock.files.sort")
            options: [
                { id: "name", label: "Name", icon: "sort_by_alpha" },
                { id: "date", label: "Modified", icon: "schedule" },
                { id: "type", label: "Type", icon: "category" }
            ]
            onPicked: id => SettingsService.set("dock.files.sort", id)
        }

        SettingToggle {
            icon: "swap_vert"
            label: "Reverse order"
            detail: "Dates start with the newest, names with A"
            checked: SettingsService.flag("dock.files.reverse")
            onToggled: SettingsService.toggle("dock.files.reverse")
        }

        SettingToggle {
            icon: "visibility"
            label: "Show hidden files"
            detail: "Files and folders whose name starts with a dot"
            checked: SettingsService.flag("dock.files.hidden")
            onToggled: SettingsService.toggle("dock.files.hidden")
        }

        SettingToggle {
            icon: "folder"
            label: "Folders first"
            detail: "Keep folders above the files. Off sorts everything together"
            checked: SettingsService.flag("dock.files.foldersFirst")
            onToggled: SettingsService.toggle("dock.files.foldersFirst")
        }

        SettingChoice {
            label: "Modified"
            current: SettingsService.get("dock.files.modified")
            options: [
                { id: "any", label: "Any time", icon: "all_inclusive" },
                { id: "today", label: "Today", icon: "today" },
                { id: "week", label: "7 days", icon: "date_range" },
                { id: "month", label: "30 days", icon: "calendar_month" },
                { id: "year", label: "Year", icon: "event" }
            ]
            onPicked: id => SettingsService.set("dock.files.modified", id)
        }
    }

    SectionCard {
        title: "Dock layouts"

        SettingChoice {
            visible: PinnedAppsService.presetNames.length > 0
            label: "Layout"
            sublabel: "Switch the pinned apps, folders and separators"
            current: PinnedAppsService.activePreset
            options: PinnedAppsService.presetNames.map(n => ({ id: n, label: n }))
            onPicked: id => PinnedAppsService.loadPreset(id)
        }

        SettingAction {
            icon: "bookmark_add"
            label: "Save current dock as a layout"
            onActivated: PinnedAppsService.savePreset(PinnedAppsService.freshPresetName())
        }

        SettingAction {
            visible: PinnedAppsService.activePreset !== ""
            icon: "delete"
            label: "Delete this layout"
            onActivated: PinnedAppsService.deletePreset(PinnedAppsService.activePreset)
        }

        SettingAction {
            icon: "horizontal_rule"
            label: "Add a separator"
            onActivated: PinnedAppsService.addSeparator()
        }
    }

    SectionCard {
        title: "App colours"

        Repeater {
            model: AppThemeService.targets

            delegate: Item {
                id: appRow
                required property var modelData
                readonly property string themeState: AppThemeService.stateOf(modelData.id)
                width: parent ? parent.width : 600
                height: 78

                SettingToggle {
                    id: appToggle
                    icon: appRow.modelData.icon
                    label: appRow.modelData.label
                    detail: appRow.themeState === "not installed" ? "Not installed"
                            : appRow.themeState === "conflict" ? "Config needs review · see the shell log"
                            : appRow.themeState === "pending" ? "Waiting for the current palette"
                            : appRow.modelData.id === "hyprland" && HyprlandSettings.isLua && !HyprlandSettings.linked
                              ? "Live now; see the Hyprland page's one-time setup to keep it"
                              : appRow.modelData.note
                    checked: AppThemeService.enabled(appRow.modelData.id)
                    onToggled: AppThemeService.setEnabled(appRow.modelData.id, !checked)
                }

                SettingAction {
                    x: appToggle.width + 16
                    icon: "undo"
                    label: "Revert"
                    detail: appRow.themeState === "applied" || appToggle.checked
                            ? "Take our colours off" : "Nothing applied"
                    onActivated: AppThemeService.revert(appRow.modelData.id)
                }
            }
        }
    }

    SectionCard {
        title: "System colours"

        SettingToggle {
            icon: "palette"
            label: "Colour GTK and Qt apps"
            detail: checked ? "Follows the wallpaper and the palette" : "OFF"
            checked: ThemeService.systemSync
            onToggled: ThemeService.setSystemSync(!ThemeService.systemSync)
        }

        SettingToggle {
            icon: "sync"
            label: "Update open apps live"
            detail: checked ? "No restart needed" : "Apps repaint when restarted"
            checked: SettingsService.flag("systemTheme.live")
            onToggled: SettingsService.toggle("systemTheme.live")
        }

        SettingToggle {
            icon: "dark_mode"
            label: "Live for dark GTK4 apps too"
            detail: checked ? "Open GNOME apps flash for a moment" : "They repaint when restarted"
            checked: SettingsService.flag("systemTheme.bounceDark")
            onToggled: SettingsService.toggle("systemTheme.bounceDark")
        }

        SettingToggle {
            icon: "widgets"
            label: "GTK apps"
            detail: "GTK 3 and 4, libadwaita"
            checked: SettingsService.flag("systemTheme.gtk")
            onToggled: SettingsService.toggle("systemTheme.gtk")
        }

        SettingToggle {
            icon: "web_asset"
            label: "Qt apps"
            detail: "qt5ct and qt6ct palette"
            checked: SettingsService.flag("systemTheme.qt")
            onToggled: SettingsService.toggle("systemTheme.qt")
        }

        SettingToggle {
            icon: "folder_open"
            label: "KDE apps"
            detail: "Dolphin and friends"
            checked: SettingsService.flag("systemTheme.kde")
            onToggled: SettingsService.toggle("systemTheme.kde")
        }

        SettingAction {
            icon: "refresh"
            label: "Apply now"
            detail: "Recolour every open app again"
            onActivated: ThemeService.runSystem(true)
        }

        SettingAction {
            icon: "troubleshoot"
            label: "Check setup"
            detail: ThemeService.systemHints.length === 0
                    ? "Everything needed is in place"
                    : ThemeService.systemHints[0].short
                      + (ThemeService.systemHints.length > 1
                         ? " (+" + (ThemeService.systemHints.length - 1) + " more)" : "")
            onActivated: ThemeService.checkSystem()
        }
    }

    SectionCard {
        title: "Icons & cursor"

        // Rescan whenever this page is built, so a theme installed meanwhile shows up.
        Component.onCompleted: IconCursorService.refresh()

        SettingChoice {
            label: "Shell icon style"
            sublabel: "Filled icons are always Bold"
            current: SettingsService.get("appearance.iconStyle")
            options: [
                { id: "outline", label: "Outline", icon: "palette" },
                { id: "line-duotone", label: "Line Duotone", icon: "palette" },
                { id: "broken", label: "Broken", icon: "palette" },
                { id: "bold-duotone", label: "Bold Duotone", icon: "palette" }
            ]
            onPicked: id => SettingsService.set("appearance.iconStyle", id)
        }

        SettingChoice {
            label: "Icon theme"
            sublabel: IconCursorService.iconThemes.length === 0
                      ? "No icon themes found"
                      : (IconCursorService.resolveNote !== "" ? IconCursorService.resolveNote
                                                              : "Open apps change at once")
            current: IconCursorService.shownIcon
            options: IconCursorService.iconThemes.map(n => ({ id: n, label: n, icon: "interests" }))
            onPicked: id => IconCursorService.setIcons(id)
        }

        SettingChoice {
            label: "Cursor theme"
            sublabel: IconCursorService.cursorThemes.length === 0
                      ? "No cursor themes found" : "Wayland and XWayland"
            current: IconCursorService.shownCursor
            options: IconCursorService.cursorThemes.map(n => ({ id: n, label: n, icon: "mouse" }))
            onPicked: id => IconCursorService.setCursor(id, IconCursorService.shownSize)
        }

        SettingStepper {
            icon: "format_size"
            label: "Cursor size"
            from: 16
            to: 96
            step: 4
            suffix: " px"
            value: IconCursorService.shownSize
            onMoved: v => IconCursorService.setCursorSize(v)
        }

        SettingAction {
            icon: "refresh"
            label: "Rescan themes"
            detail: IconCursorService.iconThemes.length + " icon, "
                    + IconCursorService.cursorThemes.length + " cursor"
            busy: IconCursorService.busy
            onActivated: IconCursorService.refresh()
        }

        SettingAction {
            icon: "upload_file"
            label: "Import Windows cursors"
            detail: IconCursorService.importNote !== "" ? IconCursorService.importNote
                    : "Pick a .zip or install.inf (.cur / .ani); it is added and used"
            busy: IconCursorService.picking || IconCursorService.importing
            onActivated: IconCursorService.pickPack("settings")
        }

        SettingAction {
            icon: "undo"
            label: "Use the system's"
            detail: "Stop restoring the cursor at start"
            onActivated: IconCursorService.forgetChoice()
        }
    }

    // What was typed in the App fonts fields, for the matches under them.
    property string uiFontQuery: ""
    property string monoFontQuery: ""

    // GTK, Qt and KDE apps' font (AppFontService.qml, scripts/theming/app-fonts.sh says
    // where each kind of app reads it). Type part of a name, pick it from the matches.
    SectionCard {
        title: "App fonts"

        Component.onCompleted: AppFontService.refresh()

        Text {
            width: page.fullWidth
            text: "The font of your GTK, Qt and KDE apps (the shell's own comes with its theme). Open apps change at once, and a font picked here is put back at every start if something else changes it."
            color: Theme.pInkSub
            font.family: Theme.fontFamily
            font.pixelSize: 15
            wrapMode: Text.WordWrap
        }

        SettingText {
            id: uiFontField
            label: "Font"
            sublabel: AppFontService.note !== "" ? AppFontService.note
                : AppFontService.families.length === 0 ? "Looking for fonts…"
                : "Type part of a name, then pick it below"
            value: AppFontService.shownUi
            placeholder: "Type a font's name"
            clearable: false
            onEdited: text => page.uiFontQuery = text
            onSubmitted: text => {
                if (text === AppFontService.shownUi)
                    return
                const f = AppFontService.exact(text, false)
                if (f !== "") {
                    AppFontService.setUi(f)
                    page.uiFontQuery = ""
                } else {
                    page.uiFontQuery = text
                }
            }
        }

        SettingChoice {
            readonly property var found: AppFontService.matches(page.uiFontQuery, false, 8)
            visible: page.uiFontQuery.trim() !== ""
            label: found.length === 0 ? "No match" : "Matches"
            sublabel: found.length === 0 ? "No installed font has that in its name" : ""
            current: AppFontService.shownUi
            options: found.map(f => ({ id: f, label: f, icon: "font_download" }))
            onPicked: id => {
                AppFontService.setUi(id)
                page.uiFontQuery = ""
                uiFontField.reset()
            }
        }

        SettingStepper {
            icon: "format_size"
            label: "Size"
            from: 6
            to: 24
            step: 1
            suffix: " pt"
            value: AppFontService.shownUiSize
            onMoved: v => AppFontService.setUiSize(v)
        }

        SettingText {
            id: monoFontField
            label: "Monospace"
            sublabel: "Terminals and code editors that follow the system's"
            value: AppFontService.shownMono
            placeholder: "Type a font's name"
            clearable: false
            onEdited: text => page.monoFontQuery = text
            onSubmitted: text => {
                if (text === AppFontService.shownMono)
                    return
                const f = AppFontService.exact(text, true)
                if (f !== "") {
                    AppFontService.setMono(f)
                    page.monoFontQuery = ""
                } else {
                    page.monoFontQuery = text
                }
            }
        }

        SettingChoice {
            readonly property var found: AppFontService.matches(page.monoFontQuery, true, 8)
            visible: page.monoFontQuery.trim() !== ""
            label: found.length === 0 ? "No match" : "Matches"
            sublabel: found.length === 0 ? "No monospaced font has that in its name (a full name of any font works too)" : ""
            current: AppFontService.shownMono
            options: found.map(f => ({ id: f, label: f, icon: "code" }))
            onPicked: id => {
                AppFontService.setMono(id)
                page.monoFontQuery = ""
                monoFontField.reset()
            }
        }

        SettingStepper {
            icon: "format_size"
            label: "Monospace size"
            from: 6
            to: 24
            step: 1
            suffix: " pt"
            value: AppFontService.shownMonoSize
            onMoved: v => AppFontService.setMonoSize(v)
        }

        SettingAction {
            visible: AppFontService.chosen
            icon: "undo"
            label: "Use the system's"
            detail: "Stop putting these fonts back at start (the apps keep them until something else sets one)"
            onActivated: AppFontService.forget()
        }
    }

    SectionCard {
        title: "Effects"

        SettingToggle {
            icon: "sports_esports"
            label: "Game Mode"
            detail: page.src && page.src.gameModeOn ? "Bare bar, no dock or widgets" : "OFF"
            checked: page.src ? page.src.gameModeOn : false
            onToggled: if (page.src) page.src.toggleGameMode()
        }

        SettingToggle {
            icon: "contrast"
            label: "Anti-Flashbang"
            readonly property int level: page.src ? page.src.antiFlashbangLevel : 0
            detail: level === 0 ? "OFF" : (level === 1 ? "Weak" : "Strong")
            checked: level > 0
            onToggled: if (page.src) page.src.toggleAntiFlashbang()
        }

        SettingToggle {
            icon: "nightlight"
            label: "Night Light"
            detail: page.src && page.src.nightLightOn ? page.src.nightLightTemperature + "K" : "OFF"
            checked: page.src ? page.src.nightLightOn : false
            onToggled: if (page.src) page.src.toggleNightLight()
        }
    }
}
