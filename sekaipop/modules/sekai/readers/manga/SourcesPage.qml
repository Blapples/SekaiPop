import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The Sources page of the manga panel: what Suwayomi's own web page is for, inside the panel.
// Three tabs over the Suwayomi the backend runs:
//
//   Extensions    install, update and remove the extensions (one extension = one or more sources)
//   Sources       which installed sources Browse and Latest ask (automatic, or a pick)
//   Repositories  where the extensions come from (a repository is the URL of an index.min.json)
//
// The work is the backend's (Manga.sw*, the /sw/* routes); this only shows where it stands.
//
//   SourcesPage { id: sources; anchors.fill: parent }
//   sources.open()
Item {
    id: root

    signal closed()

    // "extensions" | "sources" | "repos"
    property string tab: "extensions"

    // Extension list filters
    property string query: ""
    // "" = the shell's language and multi-language ones, "*" = every language, else one code
    property string langPick: ""
    property bool installedOnly: false
    property bool showAdult: false

    visible: false

    function open() {
        root.tab = "extensions"
        root.query = ""
        root.langPick = ""
        root.installedOnly = false
        root.showAdult = false
        searchField.clear()
        visible = true
        Manga.swOpen()
    }

    function close() {
        visible = false
        root.closed()
    }

    // ── What the extension list shows ────────────────────────────────────────
    function langLabel(l) {
        if (l === "") return Manga.swLang.toUpperCase() + " + multi"
        if (l === "*") return "All languages"
        if (l === "all") return "Multi"
        return l.toUpperCase()
    }

    function cycleLang() {
        const opts = [""].concat(Manga.swLangs.filter(function(l) { return l !== Manga.swLang && l !== "all" }), ["*"])
        let i = opts.indexOf(root.langPick)
        root.langPick = opts[(i + 1) % opts.length]
    }

    function cleanName(n) {
        return String(n || "").replace(/^Tachiyomi:\s*/, "")
    }

    // Installed ones always show (you want to see what you have); the rest follow the language
    // and the 18+ switch.
    readonly property var shown: {
        const q = root.query.trim().toLowerCase()
        const list = Manga.swExtensions
        const out = []
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (root.installedOnly && !e.installed) continue
            if (!e.installed) {
                if (e.nsfw && !root.showAdult) continue
                if (root.langPick === "") {
                    if (e.lang !== Manga.swLang && e.lang !== "all") continue
                } else if (root.langPick !== "*" && e.lang !== root.langPick) continue
            }
            if (q.length > 0 && String(e.name).toLowerCase().indexOf(q) < 0) continue
            out.push(e)
        }
        return out
    }

    readonly property int updatesCount: {
        let n = 0
        for (let i = 0; i < Manga.swExtensions.length; i++)
            if (Manga.swExtensions[i].installed && Manga.swExtensions[i].update) n++
        return n
    }

    // Swallows the clicks that would reach the page underneath
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 16 }
                spacing: 10

                ReaderKey {
                    icon: "close"
                    onClicked: root.close()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Sources"
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    elide: Text.ElideRight
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Suwayomi is not set up ────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Manga.swReady && !Manga.swEnabled

            ColumnLayout {
                width: Math.min(parent.width - 48, 460)
                anchors.horizontalCenter: parent.horizontalCenter
                y: 32
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: "Suwayomi is not set up"
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Suwayomi is the program that runs the Mihon / Tachiyomi extensions, so one source can read hundreds of sites. Run install-deps.sh from the SekaiPop folder to add it (it brings Java and the Suwayomi jar), then restart the reader."
                    color: Colors.on_surface_variant
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Starting / loading (the first start of Suwayomi takes a few seconds) ─
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !Manga.swReady && Manga.swError.length === 0

            Row {
                anchors.centerIn: parent
                spacing: 12

                Spinner {
                    width: 22
                    running: parent.visible
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Asking Suwayomi…"
                    font.pixelSize: 13
                }
            }
        }

        // ── The page ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Manga.swReady && Manga.swEnabled
            spacing: 0

            // Tabs
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 54

                Row {
                    anchors { left: parent.left; leftMargin: ReaderType.gutter; verticalCenter: parent.verticalCenter }
                    spacing: 8

                    ReaderChip {
                        text: "Extensions"
                        lit: root.tab === "extensions"
                        onClicked: root.tab = "extensions"
                    }

                    ReaderChip {
                        text: "Sources"
                        lit: root.tab === "sources"
                        onClicked: root.tab = "sources"
                    }

                    ReaderChip {
                        text: "Repositories"
                        lit: root.tab === "repos"
                        onClicked: root.tab = "repos"
                    }
                }
            }

            // A line for what just happened (or went wrong)
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: ReaderType.gutter
                Layout.rightMargin: ReaderType.gutter
                Layout.bottomMargin: 6
                visible: Manga.swError.length > 0 || Manga.swNotice.length > 0
                text: Manga.swError.length > 0 ? Manga.swError : Manga.swNotice
                color: Manga.swError.length > 0 ? Colors.error : Colors.on_surface_variant
                font.pixelSize: 12
                font.weight: Font.Bold
                wrapMode: Text.Wrap
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.tab === "extensions" ? 0 : (root.tab === "sources" ? 1 : 2)

                // ══ Extensions ═══════════════════════════════════════════════════
                ColumnLayout {
                    spacing: 0

                    ReaderField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.leftMargin: ReaderType.gutter
                        Layout.rightMargin: ReaderType.gutter
                        Layout.preferredHeight: ReaderType.hField
                        placeholder: "Search extensions…"
                        onTextChanged: root.query = text
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: ReaderType.gutter
                        Layout.rightMargin: ReaderType.gutter
                        Layout.topMargin: 10
                        Layout.bottomMargin: 8
                        spacing: 8

                        ReaderChip {
                            icon: "language"
                            text: root.langLabel(root.langPick)
                            onClicked: root.cycleLang()
                        }

                        ReaderChip {
                            text: "Installed"
                            lit: root.installedOnly
                            onClicked: root.installedOnly = !root.installedOnly
                        }

                        ReaderChip {
                            text: "18+"
                            lit: root.showAdult
                            onClicked: root.showAdult = !root.showAdult
                        }

                        ReaderChip {
                            visible: root.updatesCount > 0
                            icon: "system_update_alt"
                            text: "Update all · " + root.updatesCount
                            lit: true
                            enabled: Manga.swWorking.length === 0
                            onClicked: Manga.swAction("update-all", "")
                        }

                        ReaderChip {
                            icon: "refresh"
                            text: Manga.swRefreshing ? "Asking repositories…" : "Refresh"
                            enabled: !Manga.swRefreshing && Manga.swWorking.length === 0
                            onClicked: Manga.swLoadExtensions(true)
                        }
                    }

                    Divider { Layout.fillWidth: true }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: extList
                            anchors.fill: parent
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.shown
                            visible: root.shown.length > 0

                            ScrollBar.vertical: StyledScrollBar {
                            }

                            delegate: Item {
                                id: row
                                required property var modelData
                                readonly property bool working: Manga.swWorking === modelData.pkg
                                    || (Manga.swWorking === "*" && modelData.installed && modelData.update)

                                width: extList.width
                                height: ReaderType.hRow + 8

                                RowLayout {
                                    anchors { fill: parent; leftMargin: ReaderType.gutter; rightMargin: ReaderType.gutter }
                                    spacing: 12

                                    RoundClip {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        width: 36
                                        height: 36
                                        radii: [10, 10, 10, 10]

                                        Rectangle {
                                            anchors.fill: parent
                                            color: Colors.surface_container_high
                                        }

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            visible: iconImage.status !== Image.Ready
                                            name: "extension"
                                            size: 20
                                            weight: 600
                                            color: Theme.ink
                                        }

                                        Image {
                                            id: iconImage
                                            anchors.fill: parent
                                            source: row.modelData.icon || ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            sourceSize.width: 72
                                            sourceSize.height: 72
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.cleanName(row.modelData.name)
                                            font.pixelSize: ReaderType.sizeBody
                                            font.weight: ReaderType.weightTitle
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: "v" + row.modelData.version
                                                + " · " + root.langLabel(row.modelData.lang)
                                                + (row.modelData.nsfw ? " · 18+" : "")
                                                + (row.modelData.installed && row.modelData.update ? " · update available" : "")
                                                + (row.modelData.obsolete ? " · obsolete" : "")
                                            color: Colors.on_surface_variant
                                            font.pixelSize: ReaderType.sizeCaption
                                            font.weight: ReaderType.weightBody
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Spinner {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 22
                                        width: 22
                                        visible: row.working
                                        running: row.working
                                    }

                                    ReaderChip {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: !row.working && row.modelData.installed && row.modelData.update
                                        lit: true
                                        text: "Update"
                                        enabled: Manga.swWorking.length === 0
                                        onClicked: Manga.swAction("update", row.modelData.pkg)
                                    }

                                    ReaderChip {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: !row.working && row.modelData.installed
                                        text: "Remove"
                                        enabled: Manga.swWorking.length === 0
                                        onClicked: Manga.swAction("uninstall", row.modelData.pkg)
                                    }

                                    ReaderChip {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: !row.working && !row.modelData.installed
                                        lit: true
                                        icon: "download"
                                        text: "Install"
                                        enabled: Manga.swWorking.length === 0
                                        onClicked: Manga.swAction("install", row.modelData.pkg)
                                    }
                                }

                                Divider {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: ReaderType.gutter
                                    anchors.rightMargin: ReaderType.gutter
                                }
                            }
                        }

                        // Loading the list
                        Row {
                            anchors.centerIn: parent
                            spacing: 12
                            visible: root.shown.length === 0 && (Manga.swLoading || Manga.swRefreshing)

                            Spinner {
                                width: 22
                                running: parent.visible
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Manga.swRefreshing ? "Asking the repositories…" : "Loading extensions…"
                                font.pixelSize: 13
                            }
                        }

                        // Nothing to show, and why
                        ColumnLayout {
                            width: Math.min(parent.width - 48, 420)
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 28
                            spacing: 12
                            visible: root.shown.length === 0 && !Manga.swLoading && !Manga.swRefreshing

                            StyledText {
                                Layout.fillWidth: true
                                text: Manga.swRepos.length === 0
                                    ? "No repository yet"
                                    : (Manga.swExtensions.length === 0 ? "The repositories listed no extensions" : "Nothing matches")
                                font.pixelSize: 16
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Manga.swRepos.length === 0
                                    ? "Suwayomi comes with no extensions. Add a repository (a link to an index.min.json) and its extensions show up here to install."
                                    : (Manga.swExtensions.length === 0
                                        ? "Press Refresh to ask them again, or check the links under Repositories."
                                        : "Try another language, or turn on 18+ or switch off Installed.")
                                color: Colors.on_surface_variant
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                            }

                            ReaderChip {
                                visible: Manga.swRepos.length === 0
                                lit: true
                                icon: "add_link"
                                text: "Add a repository"
                                onClicked: root.tab = "repos"
                            }
                        }
                    }
                }

                // ══ Sources ══════════════════════════════════════════════════════
                ColumnLayout {
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: ReaderType.gutter
                        Layout.rightMargin: ReaderType.gutter
                        Layout.bottomMargin: 8
                        text: Manga.swCustom
                            ? "Browse and Latest ask the sources you ticked. A source from a newly installed extension is ticked for you."
                            : "Automatic: Browse and Latest ask the installed " + Manga.swLang.toUpperCase() + " and multi-language sources (the first 8 by name). Tick one to choose them yourself."
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    ReaderChip {
                        Layout.leftMargin: ReaderType.gutter
                        Layout.bottomMargin: 10
                        visible: Manga.swCustom
                        icon: "auto_awesome"
                        text: "Back to automatic"
                        enabled: !Manga.swBusy
                        onClicked: Manga.swSourcesAuto()
                    }

                    Divider { Layout.fillWidth: true }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: srcList
                            anchors.fill: parent
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: Manga.swSources
                            visible: Manga.swSources.length > 0

                            ScrollBar.vertical: StyledScrollBar {
                            }

                            delegate: Item {
                                id: srow
                                required property var modelData

                                width: srcList.width
                                height: ReaderType.hRow

                                RowLayout {
                                    anchors { fill: parent; leftMargin: ReaderType.gutter; rightMargin: ReaderType.gutter }
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: srow.modelData.name
                                            font.pixelSize: ReaderType.sizeBody
                                            font.weight: ReaderType.weightTitle
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.langLabel(srow.modelData.lang)
                                                + (srow.modelData.latest ? "" : " · no Latest list")
                                                + (srow.modelData.nsfw ? " · 18+" : "")
                                            color: Colors.on_surface_variant
                                            font.pixelSize: ReaderType.sizeCaption
                                            font.weight: ReaderType.weightBody
                                            elide: Text.ElideRight
                                        }
                                    }

                                    ReaderChip {
                                        Layout.alignment: Qt.AlignVCenter
                                        lit: srow.modelData.used
                                        icon: srow.modelData.used ? "check" : ""
                                        text: srow.modelData.used ? "In use" : "Not used"
                                        enabled: !Manga.swBusy
                                        onClicked: Manga.swUseSource(srow.modelData.id, !srow.modelData.used)
                                    }
                                }

                                Divider {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: ReaderType.gutter
                                    anchors.rightMargin: ReaderType.gutter
                                }
                            }
                        }

                        ColumnLayout {
                            width: Math.min(parent.width - 48, 420)
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 28
                            spacing: 12
                            visible: Manga.swSources.length === 0

                            StyledText {
                                Layout.fillWidth: true
                                text: "No sources installed"
                                font.pixelSize: 16
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Install an extension and its sources show up here."
                                color: Colors.on_surface_variant
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                            }

                            ReaderChip {
                                lit: true
                                icon: "extension"
                                text: "Browse extensions"
                                onClicked: root.tab = "extensions"
                            }
                        }
                    }
                }

                // ══ Repositories ═════════════════════════════════════════════════
                Flickable {
                    id: repoFlick
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: repoPage.implicitHeight + 40

                    ScrollBar.vertical: StyledScrollBar {
                    }

                    ColumnLayout {
                        id: repoPage
                        width: repoFlick.width - 2 * ReaderType.gutter
                        x: ReaderType.gutter
                        spacing: 12

                        StyledText {
                            Layout.fillWidth: true
                            text: "A repository is a link to an extension index (an index.min.json). Suwayomi reads the extensions each one lists; add a link, then install from Extensions."
                            color: Colors.on_surface_variant
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }

                        // The ones in use
                        Repeater {
                            model: Manga.swRepos

                            delegate: RowLayout {
                                id: rrow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10

                                StyledText {
                                    Layout.fillWidth: true
                                    text: rrow.modelData
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                }

                                ReaderKey {
                                    icon: "delete"
                                    enabled: !Manga.swBusy
                                    onClicked: Manga.swChangeRepos({ remove: rrow.modelData })
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: Manga.swRepos.length === 0
                            text: "No repository added."
                            font.pixelSize: 13
                        }

                        Divider { Layout.fillWidth: true }

                        ReaderField {
                            id: repoField
                            Layout.fillWidth: true
                            placeholder: "https://…/index.min.json"
                            onAccepted: root.addRepo()
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            ReaderChip {
                                lit: true
                                icon: "add_link"
                                text: "Add repository"
                                enabled: !Manga.swBusy && repoField.text.trim().length > 0
                                onClicked: root.addRepo()
                            }

                            Repeater {
                                model: Manga.swSuggested.filter(function(s) { return Manga.swRepos.indexOf(s.url) < 0 })

                                delegate: ReaderChip {
                                    required property var modelData
                                    icon: "add"
                                    text: "Add " + modelData.name
                                    enabled: !Manga.swBusy
                                    onClicked: Manga.swChangeRepos({ add: modelData.url })
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Extensions are made by other people and run on this computer: add repositories you trust."
                            color: Colors.on_surface_variant
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            opacity: 0.8
                        }
                    }
                }
            }
        }

        // Before the page is up, if the backend could not be asked at all
        StyledText {
            Layout.fillWidth: true
            Layout.margins: ReaderType.gutter
            visible: !Manga.swReady && Manga.swError.length > 0
            text: Manga.swError
            color: Colors.error
            font.pixelSize: 12
            font.weight: Font.Bold
            wrapMode: Text.Wrap
        }
    }

    function addRepo() {
        const url = repoField.text.trim()
        if (url.length === 0 || Manga.swBusy) return
        Manga.swChangeRepos({ add: url })
        repoField.clear()
    }
}
