import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// About / Update: what this shell is, which version, whether a newer one
// exists (asked once, the first time this page is shown, and again whenever
// you press the button), what changed, and who made the parts.
SettingsPage {
    id: page

    // Opening this page is the "check for updates" gesture, when nothing has looked yet
    // (with the background look on, it usually has).
    Component.onCompleted: {
        if (UpdateService.status === "idle")
            UpdateService.check(true)
    }

    readonly property string statusTitle: {
        switch (UpdateService.status) {
        case "checking": return "Checking…"
        case "current": return "You're up to date"
        case "behind": return "An update is available"
        case "nosource": return "Nothing to compare with"
        case "error": return "Couldn't check"
        default: return "Not checked yet"
        }
    }

    readonly property string statusDetail: {
        switch (UpdateService.status) {
        case "checking": return "Asking the remote…"
        case "current": return UpdateService.latest !== "" ? "Latest is " + UpdateService.latest : "Nothing newer upstream"
        case "behind":
            if (UpdateService.updateError !== "")
                return "The update didn't apply: " + UpdateService.updateError + "."
            if (UpdateService.isGit)
                return UpdateService.behind + (UpdateService.behind === 1 ? " new commit" : " new commits") + " upstream"
            if (UpdateService.managed)
                return UpdateService.unknown
                    ? "These files carry no version mark yet, so Update now installs the latest from GitHub (" + UpdateService.latest + ")."
                    : "A newer commit is on GitHub (" + UpdateService.latest + ")."
            return "Version " + UpdateService.latest + " is out"
        case "nosource": return "Install git to update from GitHub, or put a link to a VERSION file in ~/.config/sekaipop/update-url."
        case "error": return UpdateService.reason
        default: return ""
        }
    }

    readonly property string statusIcon: {
        switch (UpdateService.status) {
        case "current": return "check_circle"
        case "behind": return "new_releases"
        case "error": return "error"
        case "nosource": return "link_off"
        default: return "update"
        }
    }

    SectionCard {
        id: heroCard
        title: "This shell"

        // The mark: the same cyan-mint ring the selected tab has, big.
        Item {
            width: 96
            height: 96

            Rectangle {
                x: mt.quickFlat ? 0 : 5
                y: 4
                width: 90
                height: 90
                radius: 45
                color: mt.pLineShadow
                antialiasing: true
            }

            Rectangle {
                width: 90
                height: 90
                radius: 45
                color: mt.pSurface
                border.width: 5
                border.color: mt.pLine
                antialiasing: true

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 11
                    radius: width / 2
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: mt.accentMint }
                        GradientStop { position: 1.0; color: mt.accentCyan }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        size: 38
                        name: "palette"
                        weight: mt.settingsIconWeight
                        fill: mt.iconFill
                        color: mt.colBorder
                    }
                }
            }
        }

        Column {
            width: page.fullWidth - 96 - 16
            height: 96
            spacing: 2

            Text {
                text: "SekaiPop"
                color: mt.pInk
                font.family: mt.fontFamily
                font.pixelSize: 34
                font.weight: Font.ExtraBold
                font.styleName: mt.fontStyleBold
            }

            Text {
                text: "A Quickshell shell for Hyprland, styled like a phone."
                color: mt.pInkSub
                font.family: mt.fontFamily
                font.pixelSize: 17
            }

            Row {
                spacing: 10
                topPadding: 8

                SettingChip {
                    label: "v" + (UpdateService.version !== "" ? UpdateService.version : "—")
                    icon: "sell"
                    selected: true
                    enabled: false
                }

                SettingChip {
                    visible: UpdateService.commit !== ""
                    label: UpdateService.branch + " @ " + UpdateService.commit
                    icon: "commit"
                }

                SettingChip {
                    label: SettingsService.changedCount === 0 ? "Default settings"
                        : SettingsService.changedCount + (SettingsService.changedCount === 1 ? " setting changed" : " settings changed")
                    icon: "tune"
                }
            }
        }
    }

    SectionCard {
        title: "Welcome tour"

        SettingAction {
            icon: "waving_hand"
            label: "Play welcome screen"
            detail: GameModeService.enabled ? "Not while Game Mode is on" : "Replay the first-start tour"
            onActivated: {
                // Close the settings phone first so the tour opens over the
                // desktop, not over a phone that is still flipping away.
                if (page.host)
                    page.host.closeRequested()
                WelcomeService.open()
            }
        }
    }

    SectionCard {
        title: "Update"

        // Status, as a big sentence with its icon.
        Row {
            width: page.fullWidth
            spacing: 18

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: 44
                name: page.statusIcon
                weight: mt.settingsIconWeight
                color: UpdateService.status === "behind" ? ScrapbookTheme.accentPink : mt.pInk
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 44 - 18

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: page.statusTitle
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 24
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    text: page.statusDetail
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 17
                }
            }
        }

        SettingAction {
            icon: "update"
            label: "Check for updates"
            detail: UpdateService.status === "checking" ? "Checking…"
                : (UpdateService.checkedAt > 0 ? "Checked " + Qt.formatTime(new Date(UpdateService.checkedAt), "hh:mm") : "")
            busy: UpdateService.status === "checking"
            onActivated: UpdateService.check(true)
        }

        SettingAction {
            visible: UpdateService.status === "behind" && UpdateService.canApply
            icon: "download"
            label: "Update now"
            detail: UpdateService.updating ? (UpdateService.isGit ? "Pulling…" : "Downloading…")
                : (UpdateService.updateError !== "" ? "Didn't apply, try again"
                : UpdateService.updateMessage !== "" ? UpdateService.updateMessage
                    : (UpdateService.isGit ? "Pull, then reload" : "Download, then reload"))
            busy: UpdateService.updating
            onActivated: UpdateService.update()
        }

        Text {
            width: page.fullWidth
            visible: UpdateService.systemNeeded
            wrapMode: Text.WordWrap
            text: "This version also needs things outside the shell's own files:\n"
                + UpdateService.systemNote.map(s => "\u2022 " + s).join("\n")
                + (UpdateService.canApply ? "" : "\nRun install.sh again to get them.")
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        SettingAction {
            visible: UpdateService.systemNeeded && UpdateService.canApply
            icon: "terminal"
            label: "Update system"
            detail: UpdateService.systemRunning ? "Running in a terminal…" : "Hyprland config and packages, in a terminal"
            busy: UpdateService.systemRunning
            onActivated: UpdateService.updateSystem()
        }

        Text {
            width: page.fullWidth
            wrapMode: Text.WordWrap
            text: "The shell's own update. Your plugins have their own card just below, with the same check, commits and Update; the two settings here are theirs too."
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        SettingToggle {
            icon: "notifications_active"
            label: "Tell me about updates"
            checked: SettingsService.flag("updates.shellNotify")
            onToggled: SettingsService.toggle("updates.shellNotify")
        }

        SettingSlider {
            width: page.halfWidth
            visible: SettingsService.flag("updates.shellNotify")
            icon: "schedule"
            label: "Look every"
            from: 1
            to: 48
            step: 1
            suffix: " h"
            value: SettingsService.get("updates.shellHours")
            onMoved: v => SettingsService.set("updates.shellHours", v)
        }

        // The commits an update would bring.
        Column {
            visible: UpdateService.pending.length > 0
            width: page.fullWidth
            spacing: 6

            Repeater {
                model: UpdateService.pending

                delegate: Row {
                    required property var modelData
                    spacing: 12

                    Text {
                        width: 70
                        text: modelData.hash
                        color: mt.pInkSub
                        font.family: "monospace"
                        font.pixelSize: 15
                    }

                    Text {
                        width: page.fullWidth - 70 - 12 - 160 - 12
                        elide: Text.ElideRight
                        text: modelData.subject
                        color: mt.pInk
                        font.family: mt.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: 160
                        horizontalAlignment: Text.AlignRight
                        text: modelData.age
                        color: mt.pInkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 15
                    }
                }
            }
        }
    }

    // The plugins' own update and getting new ones (docs/PLUGIN-INSTALL.md).
    SettingsPluginsUpdate {
        id: pluginsCard
        settingsPage: page
    }

    SettingsGetPlugins {
        id: getCard
        settingsPage: page
    }

    // Desktop › Plugins' "Update in About" lands on the Plugins card.
    function takeTarget() {
        const t = PluginRepoService.aboutTarget
        if (t === "" || !page.visible)
            return
        PluginRepoService.aboutTarget = ""
        Qt.callLater(() => page.scrollToItem(t === "get" ? getCard : pluginsCard))
    }

    onVisibleChanged: if (visible) Qt.callLater(page.takeTarget)

    Connections {
        target: PluginRepoService
        function onAboutTargetChanged() { page.takeTarget() }
    }

    SectionCard {
        title: "What's new"

        Text {
            visible: UpdateService.changelog.length === 0
            text: "No CHANGELOG.md next to shell.qml."
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 17
        }

        Repeater {
            model: UpdateService.changelog.slice(0, 4)

            delegate: Column {
                id: entry
                required property var modelData
                required property int index

                width: page.halfWidth
                spacing: 5

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: entry.modelData.title
                    color: entry.index === 0 ? mt.pInk : mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 19
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Repeater {
                    model: entry.modelData.items

                    delegate: Row {
                        required property string modelData
                        spacing: 9

                        Rectangle {
                            y: 8
                            width: 6
                            height: 6
                            radius: 3
                            color: mt.pInkSub
                        }

                        Text {
                            width: page.halfWidth - 15
                            wrapMode: Text.WordWrap
                            text: modelData
                            color: mt.pInk
                            font.family: mt.fontFamily
                            font.pixelSize: 15
                        }
                    }
                }
            }
        }
    }

    SectionCard {
        title: "Credits"

        Repeater {
            model: [
                { who: "end4 · dots-hyprland", what: "The foundation of this shell: the Hyprland config, the Anti-Flashbang shaders and how the pages are organised (GPL-3.0)" },
                { who: "pCtrade · end4-pC", what: "Inspiration for the shell's customizability, his support, and the aurora, dots, mirror and ring visualizers" },
                { who: "p3dro", what: "The Discord Voice service, ported from his fork of Illogical Impulse" },
                { who: "ilyaMiro · Serpentium", what: "The equalizer engine behind the Sekai Pad, and the structure of the welcome screen" },
                { who: "Quickshell & Hyprland", what: "The toolkit and the compositor this runs on" },
                { who: "InioX · matugen", what: "Colours drawn from the wallpaper" },
                { who: "CapnKitten · refact0r", what: "Material Discord and system24, the base of the Discord theme" },
                { who: "Material Symbols & Google Sans Flex", what: "Every icon and every letter" },
                { who: "emojibase", what: "The emoji data in the launcher (MIT)" },
                { who: "yayuuu", what: "hyprland-scroll-overview, the optional scrolling Overview plugin" },
                { who: "Open-Meteo & lyric providers", what: "Weather, and lyrics from LRCLIB, LyricsPlus, NetEase, QQ Music and Kugou" }
            ]

            delegate: Column {
                required property var modelData
                width: page.halfWidth
                spacing: 1

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.who
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: modelData.what
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 15
                }
            }
        }
    }
}
