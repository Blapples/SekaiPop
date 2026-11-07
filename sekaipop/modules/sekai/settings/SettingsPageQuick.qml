import QtQuick
import Quickshell
import qs.services

// Quick: the things you reach for most, so they're a tap away instead of a
// page deep. Everything here is also somewhere else (the Quick Panel's
// tiles, the bar's buttons, the General / Bar / Desktop pages); it's the
// same state, so changing it here shows up there at once.
SettingsPage {
    id: page

    readonly property var src: host ? host.source : null
    // The monitor the phone is on: with one theme per monitor, Colours picks for it
    // (ThemeService.pickTheme; the main monitor's is the shell's theme).
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? String(QsWindow.window.screen.name) : ""

    SectionCard {
        title: "Look"

        SettingChoice {
            label: "Mode"
            sublabel: "Light, dark, or near-black"
            current: ThemeService.mode
            options: [
                { id: "light", label: "Light", icon: "light_mode" },
                { id: "dark", label: "Dark", icon: "dark_mode" },
                { id: "darker", label: "Darker", icon: "bedtime" }
            ]
            onPicked: id => ThemeService.setModeAndSystem(id)
        }

        SettingChoice {
            label: "Colours"
            sublabel: "Whose colours the shell wears"
            current: ThemeService.themeFor(page.screenName)
            options: ThemeService.groups.map(g => ({
                id: g.id,
                label: g.name,
                swatch: [g.c.border, g.c.A, g.c.B]
            }))
            onPicked: id => ThemeService.pickTheme(page.screenName, id)
        }

        SettingAction {
            tileWidth: 310
            icon: "palette"
            label: "Palette tool"
            detail: "Colours from the wallpaper, music or luck. Nothing changes until you apply"
            onActivated: PaletteService.requestOpen()
        }
    }

    SectionCard {
        title: "Quick Panel"

        SettingChoice {
            label: "Phone"
            sublabel: "Tilted 2.5D, or flat 2D, for this panel and the Settings (always flat in Game Mode)"
            current: SettingsService.flag("quick.flat") ? "flat" : "tilted"
            options: [
                { id: "tilted", label: "2.5D", icon: "view_in_ar" },
                { id: "flat", label: "2D", icon: "crop_portrait" }
            ]
            onPicked: id => SettingsService.set("quick.flat", id === "flat")
        }

        SettingToggle {
            icon: "blur_on"
            label: "Phone shadow"
            detail: "A soft shadow under the phone (Quick Panel, Apps, Wallpapers, Settings)"
            checked: SettingsService.flag("quick.phoneShadow")
            onToggled: SettingsService.toggle("quick.phoneShadow")
        }
    }

    SectionCard {
        title: "Shell"

        SettingToggle {
            icon: page.src && page.src.notificationsOn ? "notifications_active" : "notifications_off"
            label: "Notifications"
            checked: page.src ? page.src.notificationsOn : true
            onToggled: if (page.src) page.src.toggleNotifications()
        }

        SettingToggle {
            icon: "nightlight"
            label: "Night Light"
            checked: page.src ? page.src.nightLightOn : false
            onToggled: if (page.src) page.src.toggleNightLight()
        }

        SettingToggle {
            icon: "coffee"
            label: "Keep Awake"
            checked: page.src ? page.src.keepAwakeOn : false
            onToggled: if (page.src) page.src.toggleKeepAwake()
        }

        SettingToggle {
            icon: "sports_esports"
            label: "Game Mode"
            checked: page.src ? page.src.gameModeOn : false
            onToggled: if (page.src) page.src.toggleGameMode()
        }

        SettingAction {
            icon: "wallpaper"
            label: "Wallpapers"
            detail: "Open the picker"
            onActivated: if (page.host) page.host.wallpapersRequested()
        }

        SettingStepper {
            icon: "aspect_ratio"
            label: "Shell size"
            from: 0.5
            to: 3
            step: 0.05
            decimals: 2
            suffix: "×"
            value: page.host ? ShellScale.effectiveFor(page.host.screenName) : 1
            onMoved: v => { if (page.host) ShellScale.setScale(page.host.screenName, v) }
        }

        SettingToggle {
            icon: "dock_to_bottom"
            label: "Dock"
            checked: SettingsService.flag("dock.visible")
            onToggled: SettingsService.toggle("dock.visible")
        }

        SettingToggle {
            icon: "visibility"
            label: "Bar"
            checked: SettingsService.flag("bar.visible")
            onToggled: SettingsService.toggle("bar.visible")
        }
    }

    SectionCard {
        title: "Bar"

        SettingChoice {
            label: "Style"
            current: BarStyleService.style
            options: [
                { id: "float", label: "Float", edge: "top", variant: "float" },
                { id: "straight", label: "Straight", edge: "top", variant: "straight" },
                { id: "transparent", label: "Transparent", edge: "top", variant: "transparent" },
                { id: "capsule", label: "Capsule", edge: "top", variant: "capsule" }
            ]
            onPicked: id => BarStyleService.setStyle(id)
        }

        SettingChoice {
            label: "Position"
            current: BarPositionService.position
            options: [
                { id: "top", label: "Top", edge: "top" },
                { id: "right", label: "Right", edge: "right" },
                { id: "bottom", label: "Bottom", edge: "bottom" },
                { id: "left", label: "Left", edge: "left" }
            ]
            onPicked: id => BarPositionService.setPosition(id)
        }
    }

    SectionCard {
        title: "Desktop widgets"

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
            checked: WeatherCardService.shown
            onToggled: WeatherCardService.setShown(!WeatherCardService.shown)
        }

        SettingToggle {
            icon: "calendar_month"
            label: "Calendar card"
            checked: CalendarCardService.shown
            onToggled: CalendarCardService.setShown(!CalendarCardService.shown)
        }

        SettingToggle {
            icon: "palette"
            label: "Palette card"
            checked: PaletteService.shown
            onToggled: PaletteService.setShown(!PaletteService.shown)
        }

        SettingToggle {
            icon: "lyrics"
            label: "Lyrics"
            detail: "The words of the song that is playing, on the desktop"
            checked: LyricsService.shown
            onToggled: LyricsService.setShown(!LyricsService.shown)
        }

        SettingToggle {
            icon: "task_alt"
            label: "To-Do"
            checked: TodoService.shown
            onToggled: TodoService.setShown(!TodoService.shown)
        }

        SettingToggle {
            icon: "sticky_note_2"
            label: "Sticky notes"
            checked: NotesService.active
            onToggled: NotesService.setShown(!NotesService.active)
        }

        SettingToggle {
            icon: EditMode.widgetsLocked ? "lock" : "lock_open"
            label: "Lock widgets"
            checked: EditMode.widgetsLocked
            onToggled: EditMode.toggleWidgetsLocked()
        }
    }

    SectionCard {
        title: "Phone mirror"

        SettingToggle {
            icon: "smartphone"
            label: "Show my phone"
            detail: "Your Android phone, live, on a phone at the side of the screen (scrcpy)"
            checked: PhoneMirrorService.shown
            onToggled: PhoneMirrorService.toggle()
        }

        SettingToggle {
            icon: "play_arrow"
            label: "Start when opened"
            detail: "Off: the phone comes up with a Start key and nothing runs until you press it"
            checked: SettingsService.flag("phoneMirror.autoStart")
            onToggled: SettingsService.toggle("phoneMirror.autoStart")
        }

        SettingChoice {
            label: "Side"
            sublabel: "Where it comes up"
            current: SettingsService.get("phoneMirror.edge")
            options: [
                { id: "left", label: "Left", icon: "align_horizontal_left" },
                { id: "right", label: "Right", icon: "align_horizontal_right" }
            ]
            onPicked: id => SettingsService.set("phoneMirror.edge", id)
        }

        SettingStepper {
            icon: "height"
            label: "Height"
            from: 50
            to: 100
            step: 2
            suffix: " %"
            value: SettingsService.get("phoneMirror.height")
            onMoved: v => SettingsService.set("phoneMirror.height", Math.round(v))
        }

        SettingToggle {
            icon: "smartphone"
            label: "Notch"
            detail: "The Quick Panel phone's notch over the top of the picture"
            checked: SettingsService.flag("phoneMirror.notch")
            onToggled: SettingsService.toggle("phoneMirror.notch")
        }

        SettingText {
            label: "Phone on Wi-Fi"
            sublabel: "host:port from Wireless debugging; empty = cable"
            value: SettingsService.get("phoneMirror.address")
            placeholder: "192.168.1.20:5555"
            onSubmitted: text => {
                if (text.trim() === "")
                    PhoneMirrorService.forgetAddress()
                else
                    PhoneMirrorService.connectAddress(text)
            }
        }

        SettingToggle {
            icon: "volume_up"
            label: "Phone sound"
            detail: "Play the phone's sound on this computer (Android 11 or newer)"
            checked: SettingsService.flag("phoneMirror.audio")
            onToggled: SettingsService.toggle("phoneMirror.audio")
        }

        SettingToggle {
            icon: "lock_open"
            label: "Unlock the phone for me"
            detail: "Wake it and swipe the lock screen up; a PIN is typed in a small window"
            checked: SettingsService.flag("phoneMirror.autoUnlock")
            onToggled: SettingsService.toggle("phoneMirror.autoUnlock")
        }

        SettingToggle {
            icon: "coffee"
            label: "Keep the phone awake"
            detail: "While it is shown here"
            checked: SettingsService.flag("phoneMirror.stayAwake")
            onToggled: SettingsService.toggle("phoneMirror.stayAwake")
        }

        SettingToggle {
            icon: "phonelink_off"
            label: "Turn the phone's screen off"
            detail: "Saves its battery. Touch can feel slower on some phones"
            checked: SettingsService.flag("phoneMirror.turnScreenOff")
            onToggled: SettingsService.toggle("phoneMirror.turnScreenOff")
        }

        SettingChoice {
            label: "Keyboard"
            sublabel: "How your typing reaches the phone"
            current: SettingsService.get("phoneMirror.keyboard")
            options: [
                { id: "uhid", label: "Real keyboard", icon: "keyboard" },
                { id: "sdk", label: "Typed text", icon: "text_fields" }
            ]
            onPicked: id => SettingsService.set("phoneMirror.keyboard", id)
        }

        SettingStepper {
            icon: "timer"
            label: "Keep it ready"
            from: 0
            to: 600
            step: 30
            suffix: " s"
            value: SettingsService.get("phoneMirror.keepWarm")
            onMoved: v => SettingsService.set("phoneMirror.keepWarm", Math.round(v))
        }
    }
}
