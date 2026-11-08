import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The Sources page of the novel panel, laid over the Browse view (the puzzle key beside the Source
// key opens it). Three tabs, the same as the manga panel's, over LNReader's plugins:
//
//   Extensions    every plugin the repositories list: install, update and remove
//   Sources       which installed plugin Browse asks (one at a time)
//   Repositories  where the plugins come from (a repository is the address of a plugins.min.json)
//
// The work is the backend's (Novel.* and the /lnreader/* routes); this only shows where it stands.
// BrowseView shows it with `visible`, and it starts over on the Extensions tab each time.
Item {
    id: root

    signal closed()

    // "extensions" | "sources" | "repos"
    property string tab: "extensions"

    // Extension list filters
    property string query: ""
    // "" = every language, else one language as the plugins write it ("English", ...)
    property string langPick: ""
    property bool installedOnly: false

    onVisibleChanged: {
        if (!visible) return
        root.tab = "extensions"
        root.query = ""
        root.langPick = ""
        root.installedOnly = false
        searchField.clear()
        Novel.fetchRepos()
        if (Novel.catalog.length === 0) Novel.fetchCatalog(false)
    }

    function close() { root.closed() }

    // ── What the extension list shows ────────────────────────────────────────
    // The languages the repositories have, English first
    readonly property var langs: {
        const seen = {}
        const out = []
        for (let i = 0; i < Novel.catalog.length; i++) {
            const l = Novel.catalog[i].lang
            if (l && !seen[l]) { seen[l] = true; out.push(l) }
        }
        out.sort(function(a, b) {
            if (a === "English") return -1
            if (b === "English") return 1
            return a.localeCompare(b)
        })
        return out
    }

    function langLabel(l) { return l === "" ? "All languages" : l }

    function cycleLang() {
        const opts = [""].concat(root.langs)
        const i = opts.indexOf(root.langPick)
        root.langPick = opts[(i + 1) % opts.length]
    }

    function hostOf(site) {
        const m = String(site || "").match(/^https?:\/\/([^\/]+)/)
        return m ? m[1] : ""
    }

    // Installed ones always show (you want to see what you have); the rest follow the language.
    readonly property var shown: {
        const q = root.query.trim().toLowerCase()
        // The installed ones come first (with their Remove / Update keys), then the rest, each
        // group in the catalog's own order, like the manga panel's Extensions list.
        const have = []
        const rest = []
        for (let i = 0; i < Novel.catalog.length; i++) {
            const e = Novel.catalog[i]
            if (root.installedOnly && !e.installed) continue
            if (!e.installed && root.langPick !== "" && e.lang !== root.langPick) continue
            if (q.length > 0 && (e.name + " " + e.lang + " " + e.site).toLowerCase().indexOf(q) < 0) continue
            if (e.installed) have.push(e)
            else rest.push(e)
        }
        return have.concat(rest)
    }

    readonly property int updatesCount: {
        let n = 0
        for (let i = 0; i < Novel.catalog.length; i++)
            if (Novel.catalog[i].installed && Novel.catalog[i].update) n++
        return n
    }

    readonly property bool working: Novel.sourceBusyId !== ""

    // A line for what just happened (or went wrong), else what the setup is doing
    readonly property string statusLine: {
        if (Novel.sourceMessage.length > 0) return Novel.sourceMessage
        if (Novel.setupState === "installing" || Novel.setupState === "missing-node"
                || Novel.setupState === "missing-npm" || Novel.setupState === "error")
            return Novel.setupMessage
        if (Novel.catalogWarnings.length > 0)
            return Novel.catalogWarnings.length === 1 ? Novel.catalogWarnings[0]
                 : Novel.catalogWarnings.length + " repositories could not be read"
        return ""
    }
    readonly property bool statusIsError: Novel.sourceMessage.length > 0 || Novel.catalogWarnings.length > 0
        || Novel.setupState === "error" || Novel.setupState === "missing-node" || Novel.setupState === "missing-npm"

    function addRepo() {
        const url = repoField.text.trim()
        if (url.length === 0 || Novel.repoBusy) return
        Novel.changeRepos({ add: url })
        repoField.clear()
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
            visible: root.statusLine.length > 0
            text: root.statusLine
            color: root.statusIsError ? Colors.error : Colors.on_surface_variant
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
                    placeholder: "Search extensions or a language…"
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
                        visible: root.updatesCount > 0
                        icon: "system_update_alt"
                        text: "Update all · " + root.updatesCount
                        lit: true
                        enabled: !root.working
                        onClicked: Novel.updateAllSources()
                    }

                    ReaderChip {
                        icon: "refresh"
                        text: Novel.isFetchingCatalog ? "Asking repositories…" : "Refresh"
                        enabled: !Novel.isFetchingCatalog && !root.working
                        onClicked: Novel.fetchCatalog(true)
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
                        model: ScriptModel { values: root.shown }
                        visible: root.shown.length > 0

                        ScrollBar.vertical: StyledScrollBar {
                        }

                        delegate: Item {
                            id: row
                            required property var modelData
                            readonly property bool busy: Novel.sourceBusyId === modelData.id
                                || (Novel.sourceBusyId === "*" && modelData.installed && modelData.update)

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
                                        source: row.modelData.iconUrl || ""
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
                                        text: row.modelData.name
                                        font.pixelSize: ReaderType.sizeBody
                                        font.weight: ReaderType.weightTitle
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: [row.modelData.version ? "v" + row.modelData.version : "",
                                               row.modelData.lang, root.hostOf(row.modelData.site)]
                                                  .filter(function(x) { return x && x.length > 0 }).join(" · ")
                                            + (row.modelData.installed && row.modelData.update ? " · update available" : "")
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
                                    visible: row.busy
                                    running: row.busy
                                }

                                ReaderChip {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: !row.busy && row.modelData.installed && row.modelData.update
                                    lit: true
                                    text: "Update"
                                    enabled: !root.working
                                    onClicked: Novel.installSource(row.modelData.id)
                                }

                                ReaderChip {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: !row.busy && row.modelData.installed
                                    text: "Remove"
                                    enabled: !root.working
                                    onClicked: Novel.uninstallSource(row.modelData.id)
                                }

                                ReaderChip {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: !row.busy && !row.modelData.installed
                                    lit: true
                                    icon: "download"
                                    text: "Install"
                                    enabled: !root.working
                                    onClicked: Novel.installSource(row.modelData.id)
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
                        visible: root.shown.length === 0 && Novel.isFetchingCatalog

                        Spinner {
                            width: 22
                            running: parent.visible
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Asking the repositories…"
                            font.pixelSize: 13
                        }
                    }

                    // Nothing to show, and why
                    ColumnLayout {
                        width: Math.min(parent.width - 48, 420)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 28
                        spacing: 12
                        visible: root.shown.length === 0 && !Novel.isFetchingCatalog

                        StyledText {
                            Layout.fillWidth: true
                            text: Novel.repos.length === 0 ? "No repository yet"
                                : (Novel.catalog.length === 0
                                    ? (Novel.catalogError.length > 0 ? "The repositories could not be read"
                                                                     : "The repositories listed no extensions")
                                    : "Nothing matches")
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                            font.styleName: Theme.fontStyleBold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Novel.repos.length === 0
                                ? "Add a repository (a link to a plugins.min.json) and its extensions show up here to install."
                                : (Novel.catalog.length === 0
                                    ? (Novel.catalogError.length > 0 ? Novel.catalogError
                                                                     : "Press Refresh to ask them again, or check the links under Repositories.")
                                    : "Try another language, or switch off Installed.")
                            color: Colors.on_surface_variant
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                        }

                        ReaderChip {
                            visible: Novel.repos.length === 0
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
                    text: "Browse asks one source at a time: the one marked In use. The Source key in Browse goes through these in turn."
                    color: Colors.on_surface_variant
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
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
                        model: ScriptModel { values: Novel.sources }
                        visible: Novel.sources.length > 0

                        ScrollBar.vertical: StyledScrollBar {
                        }

                        delegate: Item {
                            id: srow
                            required property var modelData
                            readonly property bool current: modelData.id === Novel.activeSource

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
                                        text: [srow.modelData.lang, root.hostOf(srow.modelData.site),
                                               srow.modelData.version ? "v" + srow.modelData.version : ""]
                                                  .filter(function(x) { return x && x.length > 0 }).join(" · ")
                                        color: Colors.on_surface_variant
                                        font.pixelSize: ReaderType.sizeCaption
                                        font.weight: ReaderType.weightBody
                                        elide: Text.ElideRight
                                    }
                                }

                                ReaderChip {
                                    Layout.alignment: Qt.AlignVCenter
                                    lit: srow.current
                                    icon: srow.current ? "check" : ""
                                    text: srow.current ? "In use" : "Use"
                                    enabled: !srow.current && !root.working
                                    onClicked: Novel.selectSource(srow.modelData.id)
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
                        visible: Novel.sources.length === 0

                        StyledText {
                            Layout.fillWidth: true
                            text: "No sources installed"
                            font.pixelSize: 16
                            font.weight: Font.ExtraBold
                            font.styleName: Theme.fontStyleBold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Install an extension and it shows up here."
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
                        text: "A repository is a link to a list of extensions (a plugins.min.json, LNReader's format). Add a link, then install from Extensions."
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    // The ones in use
                    Repeater {
                        model: Novel.repos

                        delegate: RowLayout {
                            id: rrow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10

                            StyledText {
                                Layout.fillWidth: true
                                text: rrow.modelData.name
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }

                            ReaderKey {
                                icon: "delete"
                                enabled: !Novel.repoBusy
                                onClicked: Novel.changeRepos({ remove: rrow.modelData.id })
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: Novel.repos.length === 0
                        text: "No repository added."
                        font.pixelSize: 13
                    }

                    Divider { Layout.fillWidth: true }

                    ReaderField {
                        id: repoField
                        Layout.fillWidth: true
                        placeholder: "https://…/plugins.min.json"
                        onAccepted: root.addRepo()
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        ReaderChip {
                            lit: true
                            icon: "add_link"
                            text: "Add repository"
                            enabled: !Novel.repoBusy && repoField.text.trim().length > 0
                            onClicked: root.addRepo()
                        }

                        Repeater {
                            model: Novel.suggestedRepos

                            delegate: ReaderChip {
                                required property var modelData
                                icon: "add"
                                text: "Add " + modelData.name
                                enabled: !Novel.repoBusy
                                onClicked: Novel.changeRepos({ add: modelData.url })
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
}
