import QtQuick
import qs.services
import qs.modules.common
import qs.modules.sekai.quickPanel

// Bar: whether it is there, where it sits and how it looks, which modules it
// carries (every pill and button can be switched off), and how big it is.
// Where each module sits (left / center / right), and taking one off the bar or
// putting it back, can also be done in Edit Desktop (the shelf's BAR tab).
SettingsPage {
    id: page

    // The monitor this Settings Panel is on (the one "Reset" below means when
    // the bars are separate).
    readonly property string screenName: page.host ? page.host.screenName : ""

    readonly property var modules: [
        { key: "bar.workspaces", icon: "grid_view", label: "Workspaces" },
        { key: "bar.activeWindow", icon: "web_asset", label: "Active window" },
        { key: "bar.media", icon: "music_note", label: "Media" },
        { key: "bar.weather", icon: "partly_cloudy_day", label: "Weather" },
        { key: "bar.date", icon: "calendar_month", label: "Date" },
        { key: "bar.clock", icon: "schedule", label: "Clock" },
        { key: "bar.resources", icon: "memory", label: "CPU & RAM" },
        { key: "bar.screenTime", icon: "hourglass", label: "Screen time" },
        { key: "bar.timer", icon: "timer", label: "Timer" },
        { key: "bar.netSpeed", icon: "arrow_downward", label: "Network speed" },
        { key: "bar.status", icon: "wifi", label: "Wi-Fi, Bluetooth & sound icons" },
        { key: "bar.battery", icon: "battery_android_full", label: "Battery" },
        { key: "bar.keyboardLayout", icon: "keyboard_alt", label: "Keyboard layout" },
        { key: "bar.notifications", icon: "notifications", label: "Notification bell" },
        { key: "bar.tray", icon: "apps", label: "Tray" },
        { key: "bar.utilButtons", icon: "construction", label: "Utility keys" },
        { key: "bar.privacy", icon: "shield_with_heart", label: "Privacy (mic / screen share)" },
        { key: "bar.updates", icon: "system_update_alt", label: "Package updates" },
        { key: "bar.discord", icon: "headset_mic", label: "Discord call" }
    ]

    readonly property var utilKeys: [
        { key: "util.screenshot", icon: "screenshot_region", label: "Screenshot" },
        { key: "util.colorPicker", icon: "colorize", label: "Colour picker" },
        { key: "util.keyboard", icon: "keyboard", label: "Keyboard" },
        { key: "util.mic", icon: "mic", label: "Microphone" },
        { key: "util.darkMode", icon: "dark_mode", label: "Dark / light" },
        { key: "util.profile", icon: "speed", label: "Performance" },
        { key: "util.record", icon: "screen_record", label: "Record" },
        { key: "util.wallpapers", icon: "wallpaper", label: "Wallpapers" }
    ]

    SectionCard {
        title: "Bar"

        SettingToggle {
            icon: "visibility"
            label: "Show bar"
            detail: SettingsService.flag("bar.visible") ? "ON" : "Hidden · gear in Quick Panel"
            checked: SettingsService.flag("bar.visible")
            onToggled: SettingsService.toggle("bar.visible")
        }

        SettingChoice {
            label: "Style"
            sublabel: "How the bar is drawn"
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
            sublabel: "Which edge it sits on"
            current: BarPositionService.position
            options: [
                { id: "top", label: "Top", edge: "top" },
                { id: "right", label: "Right", edge: "right" },
                { id: "bottom", label: "Bottom", edge: "bottom" },
                { id: "left", label: "Left", edge: "left" }
            ]
            onPicked: id => BarPositionService.setPosition(id)
        }

        SettingToggle {
            icon: "vertical_align_top"
            label: "Auto-hide"
            detail: SettingsService.get("bar.hideMode") === "auto"
                ? "Away until the pointer touches the edge · windows use the whole screen"
                : "Always shown"
            checked: SettingsService.get("bar.hideMode") === "auto"
            onToggled: SettingsService.set("bar.hideMode", checked ? "off" : "auto")
        }

        SettingToggle {
            icon: "monitor"
            label: "Separate bar per monitor"
            detail: BarLayoutService.perMonitor
                ? "Each monitor has its own layout · edit it in Edit Desktop"
                : "Same bar layout on every monitor"
            checked: BarLayoutService.perMonitor
            onToggled: SettingsService.toggle("bar.perMonitor")
        }

        SettingAction {
            icon: "restart_alt"
            label: BarLayoutService.perMonitor ? "Reset this monitor's bar layout" : "Reset bar layout"
            detail: BarLayoutService.customizedFor(page.screenName) ? "Back to the default order" : "Already the default"
            onActivated: BarLayoutService.reset(page.screenName)
        }
    }

    SectionCard {
        title: "Modules"

        Repeater {
            model: page.modules

            delegate: SettingToggle {
                required property var modelData

                icon: modelData.icon
                label: modelData.label
                checked: SettingsService.flag(modelData.key)
                onToggled: SettingsService.toggle(modelData.key)
            }
        }

        // The plugins' bar entries (docs/PLUGINS.md): one more module each, marked as a
        // plugin, with a key to its own settings (Settings > Desktop > Plugins). Their switch
        // is the plugin's (BarLayoutService.masterOn), off until turned on here.
        Repeater {
            model: PluginService.barModules

            delegate: Item {
                id: plugTile
                required property var modelData

                readonly property bool on: BarLayoutService.masterOn(modelData.id)

                width: toggle.implicitWidth
                height: toggle.implicitHeight

                SettingToggle {
                    id: toggle
                    icon: plugTile.modelData.icon
                    label: plugTile.modelData.label
                    checked: plugTile.on
                    detail: (plugTile.on ? "ON" : "OFF") + " · PLUGIN"
                    onToggled: BarLayoutService.setMaster(plugTile.modelData.id, !plugTile.on)
                }

                // Sits over the tile's corner, as a separate key: the tile's own click stays
                // the on / off switch.
                PluginBadge {
                    id: plugKey
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -4
                    anchors.topMargin: -10
                    kind: "cap"
                    icon: "settings"
                    text: "Settings"
                    scale: plugArea.pressed ? 0.94 : 1

                    MouseArea {
                        id: plugArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PluginService.askSettings(plugTile.modelData.id, page.screenName)
                    }
                }
            }
        }

        SettingSlider {
            visible: SettingsService.flag("bar.workspaces")
            width: page.halfWidth
            icon: "grid_view"
            label: "Workspaces on the bar"
            from: 1
            to: 10
            step: 1
            value: SettingsService.get("bar.workspaceCount")
            onMoved: v => SettingsService.set("bar.workspaceCount", Math.round(v))
        }
    }

    SectionCard {
        title: "Privacy & updates"

        SettingToggle {
            icon: "exposure_zero"
            label: "Show 0 updates"
            detail: PackageUpdatesService.breakdown
            checked: SettingsService.flag("updates.showZero")
            onToggled: SettingsService.toggle("updates.showZero")
        }

        SettingToggle {
            icon: "deployed_code"
            label: "Count AUR updates"
            detail: "paru or yay"
            checked: SettingsService.flag("updates.aur")
            onToggled: {
                SettingsService.toggle("updates.aur")
                PackageUpdatesService.refresh()
            }
        }

        SettingAction {
            icon: "refresh"
            label: "Check for updates"
            detail: PackageUpdatesService.breakdown
            busy: PackageUpdatesService.status === "checking"
            onActivated: PackageUpdatesService.refresh()
        }

        SettingSlider {
            width: page.halfWidth
            icon: "notification_important"
            label: "Nudge from"
            from: 0
            to: 100
            step: 5
            suffix: " updates"
            specialValue: 0
            specialText: "Never"
            value: SettingsService.get("updates.nudgeAt")
            onMoved: v => SettingsService.set("updates.nudgeAt", v)
        }

        SettingSlider {
            width: page.halfWidth
            icon: "update"
            label: "Look every"
            from: 5
            to: 240
            step: 5
            suffix: " min"
            value: SettingsService.get("updates.intervalMin")
            onMoved: v => SettingsService.set("updates.intervalMin", v)
        }

        SettingChoice {
            label: "Badge click opens"
            sublabel: "The terminal the update runs in"
            current: SettingsService.get("updates.terminal")
            options: [
                { id: "kitty", label: "kitty", icon: "terminal" },
                { id: "foot", label: "foot", icon: "terminal" },
                { id: "alacritty", label: "alacritty", icon: "terminal" }
            ]
            onPicked: id => SettingsService.set("updates.terminal", id)
        }
    }

    SectionCard {
        title: "Media, tray & scrolling"

        SettingChoice {
            label: "Media pill click"
            sublabel: "Left click on the pill"
            current: SettingsService.get("media.leftClick")
            options: [
                { id: "panel", label: "Open panel", icon: "queue_music" },
                { id: "playpause", label: "Play / pause", icon: "play_pause" }
            ]
            onPicked: id => SettingsService.set("media.leftClick", id)
        }

        SettingChoice {
            label: "Discord pill click"
            sublabel: "Left click on the pill"
            current: SettingsService.get("discord.leftClick")
            options: [
                { id: "panel", label: "Open panel", icon: "headset_mic" },
                { id: "mute", label: "Mute", icon: "mic_off" }
            ]
            onPicked: id => SettingsService.set("discord.leftClick", id)
        }

        SettingToggle {
            icon: "swap_vert"
            label: "Scroll on tray icons"
            detail: "Sent to the app"
            checked: SettingsService.flag("tray.scroll")
            onToggled: SettingsService.toggle("tray.scroll")
        }

        SettingToggle {
            icon: "unfold_more"
            label: "Scroll hints"
            detail: "A marker where the wheel works"
            checked: SettingsService.flag("bar.scrollHints")
            onToggled: SettingsService.toggle("bar.scrollHints")
        }
    }

    SectionCard {
        title: "Utility keys"

        Repeater {
            model: page.utilKeys

            delegate: Item {
                id: keyCell
                required property var modelData

                width: 112
                height: 75 + 30

                QuickToggle {
                    kind: "round"
                    roundWidth: 74
                    flatShadow: mt.quickFlat
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: keyCell.modelData.icon
                    on: SettingsService.flag(keyCell.modelData.key)
                    onClicked: SettingsService.toggle(keyCell.modelData.key)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 82
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: keyCell.modelData.label
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    SectionCard {
        title: "Size"

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

        SettingAction {
            icon: "restart_alt"
            label: "Reset size"
            detail: "Back to the default"
            onActivated: { if (page.host) ShellScale.resetScale(page.host.screenName) }
        }
    }
}
