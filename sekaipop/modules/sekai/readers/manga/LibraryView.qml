// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// The Library. With an AniList login it shows the user's own lists as tabs (Reading, Completed,
// Dropped, Planning, and Paused / Rereading while they hold something) as a table like AniList's
// own manga list (title, score, chapters, volumes, type), with a title filter, filters (genre,
// tags, origin, format, status, year) and a sort. The last tab, Saved, is the covers saved with
// + Library, as before. Without a login only Saved is there, with a key to log in.
// The data and the asking are Manga's (fetchList, setList*, toggleList*); the server cuts the
// tab, the filters and the sort out of one copy of the list (/al/list).
Item {
    id: libraryView

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    // Emitted when the user taps an entry — parent handles navigation
    signal mangaSelected(string mangaId)
    // The "Log in" key (the parent opens the AniList page)
    signal loginRequested()

    // The Saved tab is open. Without a login it always is.
    property bool showSaved: false
    readonly property bool listMode: Manga.alLoggedIn && !showSaved

    property bool filtersOpen: false
    // Which filter's list is dropped down under the keys ("" = none)
    property string openFilter: ""

    // Widths of the table's columns (the header row and every row share them)
    readonly property int cellScore: 54
    readonly property int cellProgress: 82
    readonly property int cellVolumes: 66
    readonly property int cellType: 64
    readonly property bool showVolumes: width >= 500
    // Covers per row in the Saved grid: four on the side card, more in a full window.
    readonly property int gridColumns: RM.gridColumns(libGrid.width - libGrid.leftMargin - libGrid.rightMargin, 190, 4, 10)

    // ── When the list is asked ───────────────────────────────────────────────
    // Once when the Library first shows with a login (a failed ask waits for Retry, so it
    // does not loop), and again whenever it shows after being away: a chapter read in the
    // meantime moved the list, and the backend dropped its copy.
    readonly property bool needsList:
        visible && listMode && !Manga.listLoaded && !Manga.listBusy && Manga.listError.length === 0
    onNeedsListChanged: if (needsList) Manga.fetchList()
    onVisibleChanged: if (visible && listMode && Manga.listLoaded) Manga.fetchList()
    onListModeChanged: {
        if (!listMode) { filtersOpen = false; openFilter = "" }
        else if (visible && Manga.listLoaded) Manga.fetchList()
    }
    onFiltersOpenChanged: if (!filtersOpen) openFilter = ""

    // ── What the tabs and the keys offer ─────────────────────────────────────
    // Reading, Completed, Dropped, Planning (no All), then Saved. A count follows the name
    // once the server has said it.
    readonly property var tabs: {
        const t = RM.visibleListTabs(Manga.listCounts, Manga.listStatus).map(function(x) {
            return { id: x.id, saved: false, label: x.count > 0 ? x.label + " · " + x.count : x.label }
        })
        t.push({ id: "SAVED", saved: true, label: "Saved" })
        return t
    }

    readonly property var sortOptions: [
        { label: "Score",        value: "SCORE"    },
        { label: "Title",        value: "TITLE"    },
        { label: "Progress",     value: "PROGRESS" },
        { label: "Last updated", value: "UPDATED"  },
        { label: "Last added",   value: "ADDED"    }
    ]

    readonly property var genreOptions: [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror",
        "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance",
        "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"
    ].map(g => ({ label: g, value: g }))

    readonly property var formatOptions: [
        { label: "Any",      value: ""         },
        { label: "Manga",    value: "MANGA"    },
        { label: "One shot", value: "ONE_SHOT" },
        { label: "Novel",    value: "NOVEL"    }
    ]

    readonly property var countryOptions: [
        { label: "Any",             value: ""   },
        { label: "Japan (manga)",   value: "JP" },
        { label: "Korea (manhwa)",  value: "KR" },
        { label: "China (manhua)",  value: "CN" }
    ]

    // The title's own status (not the list it is on); any number can be on at once
    readonly property var statusOptions: [
        { label: "Releasing", value: "RELEASING"        },
        { label: "Finished",  value: "FINISHED"         },
        { label: "Hiatus",    value: "HIATUS"           },
        { label: "Upcoming",  value: "NOT_YET_RELEASED" },
        { label: "Cancelled", value: "CANCELLED"        }
    ]

    // Any, then this year and back 40 years
    readonly property var yearOptions: {
        const y = new Date().getFullYear()
        const out = [{ label: "Any", value: 0 }]
        for (let i = 0; i < 40; i++)
            out.push({ label: String(y - i), value: y - i })
        return out
    }

    readonly property var tagOptions: (Manga.tagList || [])
        .map(function(t) { return { label: t.name, value: t.name, hint: (t.category || "").replace("-", " · ") } })

    function toggleOpen(key) { openFilter = openFilter === key ? "" : key }
    function summary(title, n) { return n > 0 ? title + " · " + n : title }
    function valueLabel(title, options, value, none) {
        if (value === none) return title
        for (let i = 0; i < options.length; i++)
            if (options[i].value === value) return title + " · " + options[i].label
        return title
    }
    function sortLabel(value) {
        for (let i = 0; i < sortOptions.length; i++)
            if (sortOptions[i].value === value) return sortOptions[i].label
        return ""
    }

    // ── Background ────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── No login: what the lists are, and the key to get them ─────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            visible: !Manga.alLoggedIn

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    text: "Log in to AniList to see your Reading, Completed, Dropped and Planning lists here"
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    font.family: libraryView.fontBody
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                ReaderChip {
                    Layout.alignment: Qt.AlignVCenter
                    icon: "account_circle"
                    text: "Log in"
                    onClicked: libraryView.loginRequested()
                }
            }
        }

        // ── The tabs: Reading / Completed / Dropped / Planning, then Saved ────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            visible: Manga.alLoggedIn
            clip: true

            ListView {
                id: tabList
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: libraryView.tabs

                delegate: Item {
                    width: tabChip.implicitWidth
                    height: tabList.height

                    ReaderChip {
                        id: tabChip
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: modelData.label
                        lit: modelData.saved
                            ? libraryView.showSaved
                            : (!libraryView.showSaved && Manga.listStatus === modelData.id)
                        onClicked: {
                            if (modelData.saved) {
                                libraryView.showSaved = true
                            } else {
                                libraryView.showSaved = false
                                Manga.setListStatus(modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ── Title filter + the Filters key ────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            visible: libraryView.listMode

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                SearchPill {
                    id: listSearch
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    placeholder: "Filter titles…"
                    onTextChanged: listDebounce.restart()
                }

                ReaderChip {
                    Layout.alignment: Qt.AlignVCenter
                    // As tall as the search pill beside it.
                    Layout.preferredHeight: 40
                    icon: "tune"
                    text: Manga.activeListFilterCount > 0 ? "Filters · " + Manga.activeListFilterCount : "Filters"
                    lit: libraryView.filtersOpen || Manga.activeListFilterCount > 0
                    onClicked: libraryView.filtersOpen = !libraryView.filtersOpen
                }
            }

            Timer {
                id: listDebounce
                interval: 300
                onTriggered: Manga.setListQuery(listSearch.text.trim())
            }
        }

        // ── Filters and the sort ──────────────────────────────────────────────
        Item {
            id: filterPanel
            Layout.fillWidth: true
            Layout.preferredHeight: libraryView.filtersOpen && libraryView.listMode
                ? Math.min(filterFlick.contentHeight + 6, libraryView.height * 0.6) : 0
            visible: Layout.preferredHeight > 0
            clip: true
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Flickable {
                id: filterFlick
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                contentWidth: width
                contentHeight: filterColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: StyledScrollBar {
                }

                Column {
                    id: filterColumn
                    width: filterFlick.width
                    spacing: 8
                    bottomPadding: 6

                    // One key per filter, like Browse: a key drops its list down under the row
                    // (one at a time) and is lit while it has something on or its list is open.
                    Flow {
                        width: parent.width
                        spacing: 8

                        ReaderChip {
                            text: "Sort · " + libraryView.sortLabel(Manga.listSort)
                            icon: libraryView.openFilter === "sort" ? "expand_less" : "expand_more"
                            lit: libraryView.openFilter === "sort"
                            onClicked: libraryView.toggleOpen("sort")
                        }
                        ReaderChip {
                            text: libraryView.summary("Genre", Manga.listGenres.length)
                            icon: libraryView.openFilter === "genre" ? "expand_less" : "expand_more"
                            lit: Manga.listGenres.length > 0 || libraryView.openFilter === "genre"
                            onClicked: libraryView.toggleOpen("genre")
                        }
                        ReaderChip {
                            text: libraryView.summary("Tags", Manga.listTags.length)
                            icon: libraryView.openFilter === "tags" ? "expand_less" : "expand_more"
                            lit: Manga.listTags.length > 0 || libraryView.openFilter === "tags"
                            onClicked: {
                                libraryView.toggleOpen("tags")
                                if (libraryView.openFilter === "tags") Manga.fetchTags()
                            }
                        }
                        ReaderChip {
                            text: libraryView.valueLabel("Origin", libraryView.countryOptions, Manga.listCountry, "")
                            icon: libraryView.openFilter === "country" ? "expand_less" : "expand_more"
                            lit: Manga.listCountry !== "" || libraryView.openFilter === "country"
                            onClicked: libraryView.toggleOpen("country")
                        }
                        ReaderChip {
                            text: libraryView.valueLabel("Format", libraryView.formatOptions, Manga.listFormat, "")
                            icon: libraryView.openFilter === "format" ? "expand_less" : "expand_more"
                            lit: Manga.listFormat !== "" || libraryView.openFilter === "format"
                            onClicked: libraryView.toggleOpen("format")
                        }
                        ReaderChip {
                            text: libraryView.summary("Status", Manga.listMStatuses.length)
                            icon: libraryView.openFilter === "status" ? "expand_less" : "expand_more"
                            lit: Manga.listMStatuses.length > 0 || libraryView.openFilter === "status"
                            onClicked: libraryView.toggleOpen("status")
                        }
                        ReaderChip {
                            text: libraryView.valueLabel("Year", libraryView.yearOptions, Manga.listYear, 0)
                            icon: libraryView.openFilter === "year" ? "expand_less" : "expand_more"
                            lit: Manga.listYear > 0 || libraryView.openFilter === "year"
                            onClicked: libraryView.toggleOpen("year")
                        }
                        ReaderChip {
                            visible: Manga.activeListFilterCount > 0
                            icon: "close"
                            text: "Clear"
                            onClicked: { libraryView.openFilter = ""; Manga.clearListFilters() }
                        }
                    }

                    // The tags that are on, to tap off without opening the list
                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: Manga.listTags.length > 0

                        Repeater {
                            model: Manga.listTags

                            delegate: ReaderChip {
                                text: modelData
                                icon: "close"
                                lit: true
                                onClicked: Manga.toggleListTag(modelData)
                            }
                        }
                    }

                    // The open list: Genre, Tags and Status stay open while you tick several;
                    // Sort and the others pick one and close.
                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "sort"
                        options: libraryView.sortOptions
                        selected: [Manga.listSort]
                        onPicked: function(value) { Manga.setListSort(value); libraryView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "genre"
                        options: libraryView.genreOptions
                        selected: Manga.listGenres
                        onPicked: function(value) { Manga.toggleListGenre(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "tags"
                        searchable: true
                        placeholder: "Search tags…"
                        emptyText: Manga.tagsError.length > 0 ? Manga.tagsError
                                 : Manga.isFetchingTags ? "Loading tags…" : "No tag called that"
                        options: libraryView.tagOptions
                        selected: Manga.listTags
                        onPicked: function(value) { Manga.toggleListTag(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "country"
                        options: libraryView.countryOptions
                        selected: [Manga.listCountry]
                        onPicked: function(value) { Manga.setListCountry(value); libraryView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "format"
                        options: libraryView.formatOptions
                        selected: [Manga.listFormat]
                        onPicked: function(value) { Manga.setListFormat(value); libraryView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "status"
                        options: libraryView.statusOptions
                        selected: Manga.listMStatuses
                        onPicked: function(value) { Manga.toggleListMStatus(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: libraryView.openFilter === "year"
                        options: libraryView.yearOptions
                        selected: [Manga.listYear]
                        onPicked: function(value) { Manga.setListYear(value); libraryView.openFilter = "" }
                    }
                }
            }
        }

        Divider { Layout.fillWidth: true; visible: Manga.alLoggedIn }

        // ── Content ───────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── The AniList list of the open tab ──────────────────────────────
            Item {
                id: listContent
                anchors.fill: parent
                visible: libraryView.listMode

                // Column titles
                Item {
                    id: listHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 28

                    RowLayout {
                        anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                        spacing: 10

                        Item { Layout.preferredWidth: 38 }
                        HeaderCell { Layout.fillWidth: true; text: "Title"; align: Text.AlignLeft }
                        HeaderCell { Layout.preferredWidth: libraryView.cellScore; text: "Score"; align: Text.AlignRight }
                        HeaderCell { Layout.preferredWidth: libraryView.cellProgress; text: "Chapters"; align: Text.AlignRight }
                        HeaderCell { Layout.preferredWidth: libraryView.cellVolumes; text: "Volumes"; align: Text.AlignRight
                                     visible: libraryView.showVolumes }
                        HeaderCell { Layout.preferredWidth: libraryView.cellType; text: "Type" }
                    }
                }

                Item {
                    anchors { top: listHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

                    ListView {
                        id: listView
                        anchors.fill: parent
                        topMargin: 2
                        bottomMargin: 10
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: Manga.listEntries

                        ScrollBar.vertical: StyledScrollBar {
                        }

                        delegate: Item {
                            id: row
                            width: listView.width
                            height: 66

                            Rectangle {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 3; bottomMargin: 3 }
                                // Flat, like the chapter list: a hairline between rows instead of a
                                // box round each one (boxes are for covers). Hover is a soft tint.
                                radius: 10
                                color: rowArea.containsPress ? Theme.surfaceTint
                                     : (rowArea.containsMouse ? Colors.withAlpha(Theme.surface, 0.8) : "transparent")
                                antialiasing: true
                                Behavior on color { ColorAnimation { duration: 110 } }

                                Rectangle {
                                    anchors {
                                        bottom: parent.bottom
                                        left: parent.left; right: parent.right
                                        leftMargin: 8; rightMargin: 8
                                    }
                                    height: 1; color: Colors.outline_variant; opacity: 0.25
                                }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    spacing: 10

                                    ClippingRectangle {
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 52
                                        radius: 6
                                        color: Theme.surfaceTint

                                        Image {
                                            id: rowCover
                                            anchors.fill: parent
                                            // Same retry as CoverCard: a failed load is tried again.
                                            property int attempt: 0
                                            property bool useOriginal: false
                                            readonly property string rawBase: modelData.image || ""
                                            readonly property string base: useOriginal ? rawBase : RM.hiResCover(rawBase)
                                            source: base.length === 0 ? ""
                                                  : (attempt === 0 ? base
                                                     : base + (base.indexOf("?") >= 0 ? "&" : "?") + "retry=" + attempt)
                                            onRawBaseChanged: { useOriginal = false; attempt = 0 }
                                            onStatusChanged: {
                                                if (status !== Image.Error || base.length === 0) return
                                                if (!useOriginal && base !== rawBase) { useOriginal = true; attempt = 0; return }
                                                if (attempt < 4) rowRetry.restart()
                                            }
                                            Timer {
                                                id: rowRetry
                                                interval: 800 * Math.pow(2, rowCover.attempt)
                                                onTriggered: rowCover.attempt++
                                            }
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            // Twice the 76x104 slot, so the cover stays sharp on a scaled or HiDPI screen
                                            sourceSize.width: 152
                                            sourceSize.height: 208
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        color: Theme.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: ReaderType.sizeBody
                                        font.weight: ReaderType.weightTitle
                                        font.styleName: ReaderType.styleTitle
                                    }

                                    // The numbers read lighter than the titles and line up on their
                                    // last digit; a number a title does not have is a dim dash.
                                    Text {
                                        Layout.preferredWidth: libraryView.cellScore
                                        horizontalAlignment: Text.AlignRight
                                        rightPadding: 8
                                        text: RM.formatScore(modelData.score, modelData.score100, Manga.scoreFormat) || "\u2014"
                                        color: RM.formatScore(modelData.score, modelData.score100, Manga.scoreFormat) !== "" ? Theme.ink : Theme.inkSub
                                        opacity: RM.formatScore(modelData.score, modelData.score100, Manga.scoreFormat) !== "" ? 1 : 0.5
                                        font.family: Theme.fontFamily
                                        font.pixelSize: ReaderType.sizeBody
                                        font.weight: ReaderType.weightTitle
                                        font.styleName: ReaderType.styleTitle
                                    }

                                    Text {
                                        Layout.preferredWidth: libraryView.cellProgress
                                        horizontalAlignment: Text.AlignRight
                                        rightPadding: 8
                                        text: RM.listProgressText(modelData.progress, modelData.chapters)
                                        color: Theme.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: ReaderType.sizeCaption + 1
                                        font.weight: ReaderType.weightBody
                                        font.styleName: ReaderType.styleBody
                                    }

                                    Text {
                                        readonly property bool _none: !(Number(modelData.progressVolumes) > 0)
                                                                      && !(Number(modelData.volumes) > 0)
                                        visible: libraryView.showVolumes
                                        Layout.preferredWidth: libraryView.cellVolumes
                                        horizontalAlignment: Text.AlignRight
                                        rightPadding: 8
                                        text: _none ? "\u2014" : RM.listProgressText(modelData.progressVolumes, modelData.volumes)
                                        color: Theme.inkSub
                                        opacity: _none ? 0.5 : 1
                                        font.family: Theme.fontFamily
                                        font.pixelSize: ReaderType.sizeCaption + 1
                                        font.weight: ReaderType.weightBody
                                        font.styleName: ReaderType.styleBody
                                    }

                                    Text {
                                        Layout.preferredWidth: libraryView.cellType
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.type
                                        color: Theme.inkSub
                                        font.family: Theme.fontFamily
                                        font.pixelSize: ReaderType.sizeCaption
                                        font.weight: ReaderType.weightTitle
                                        font.styleName: ReaderType.styleTitle
                                        font.letterSpacing: 0.3
                                    }
                                }

                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Manga.fetchMangaDetail(modelData.id)
                                        libraryView.mangaSelected(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // First read, or a new tab: ghost rows where the list will land
                    SkeletonList {
                        anchors.fill: parent
                        z: 10
                        active: Manga.listBusy && Manga.listEntries.length === 0
                        rowHeight: 66
                    }

                    // A new filter or sort while a list is on screen
                    LoadingBar {
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        z: 11
                        active: Manga.listBusy && Manga.listEntries.length > 0
                    }

                    EmptyState {
                        visible: Manga.listLoaded && !Manga.listBusy && Manga.listError.length === 0
                                 && Manga.listEntries.length === 0
                        z: 8
                        title: (Manga.activeListFilterCount > 0 || Manga.listQuery.length > 0)
                            ? "Nothing matches"
                            : "Nothing in " + RM.listTabLabel(Manga.listStatus)
                        subtitle: (Manga.activeListFilterCount > 0 || Manga.listQuery.length > 0)
                            ? "Try different words or fewer filters"
                            : "Titles on your AniList " + RM.listTabLabel(Manga.listStatus).toLowerCase() + " list show up here"
                        displayFont: libraryView.fontDisplay
                        bodyFont: libraryView.fontBody
                    }

                    // Error state
                    Rectangle {
                        anchors.fill: parent
                        color: Colors.background
                        visible: Manga.listError.length > 0 && !Manga.listBusy
                        z: 9

                        Column {
                            anchors.centerIn: parent
                            spacing: 12

                            StyledText {
                                text: Manga.listError
                                color: Colors.on_surface_variant
                                font.pixelSize: 12
                                font.family: libraryView.fontBody
                                wrapMode: Text.Wrap
                                width: 280
                                horizontalAlignment: Text.AlignHCenter
                                lineHeight: 1.4
                            }

                            ReaderChip {
                                anchors.horizontalCenter: parent.horizontalCenter
                                icon: "refresh"
                                text: "Retry"
                                onClicked: { Manga.listError = ""; Manga.fetchList() }
                            }
                        }
                    }
                }
            }

            // ── Saved: the covers saved with + Library ────────────────────────
            Item {
                id: savedContent
                anchors.fill: parent
                visible: !libraryView.listMode

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: Manga.libraryList.length === 0 && Manga.libraryLoaded

                    EmptyState {
                        title: "Nothing saved yet"
                        subtitle: "Open any manga and tap  + Library"
                        displayFont: libraryView.fontDisplay
                        bodyFont: libraryView.fontBody
                    }
                }

                // Loading (first open before file is read)
                SkeletonGrid {
                    anchors.fill: parent
                    visible: !Manga.libraryLoaded
                    active: !Manga.libraryLoaded
                    padding: 8
                    columns: libraryView.gridColumns
                    ratio: 1.72
                    footerHeight: 30
                }

                GridView {
                    id: libGrid
                    // Held at the width the move ends at while the panel changes width (see
                    // the Browse grid).
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: ReaderEnv.panelResizing ? Math.max(0, Math.round(ReaderEnv.panelBodyTarget))
                                                   : parent.width
                    visible: Manga.libraryList.length > 0
                    topMargin: 10
                    leftMargin: 8
                    rightMargin: 8
                    bottomMargin: 10
                    cellWidth: Math.floor((width - leftMargin - rightMargin) / libraryView.gridColumns)
                    cellHeight: cellWidth * 1.72
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Manga.libraryList

                    ScrollBar.vertical: StyledScrollBar {
                    }

                    delegate: Item {
                        width: libGrid.cellWidth
                        height: libGrid.cellHeight

                        readonly property var libEntry: modelData

                        CoverCard {
                            anchors.fill: parent
                            source: libEntry.coverUrl || ""
                            title: libEntry.title || ""
                            bodyFont: libraryView.fontBody
                            fullTitle: true
                            holdTitle: false
                            gradientHeight: 48
                            footerHeight: 30

                            CoverProgressBar {
                                height: 30
                                rowSpacing: 6
                                bodyFont: libraryView.fontBody
                                started: libEntry.lastReadChapterNum
                                label: libEntry.lastReadChapterNum
                                        ? "Ch. " + libEntry.lastReadChapterNum
                                        : "Not started"
                            }

                            // Which site this saved title is read from (its id says so)
                            ReaderBadge {
                                anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                                implicitHeight: 20
                                rotation: 0
                                text: Manga.labelForId(libEntry.id).toUpperCase()
                                fill: ReaderType.tagFill
                                ink: ReaderType.tagInk
                                outline: "transparent"
                            }

                            onClicked: {
                                Manga.fetchMangaDetail(libEntry.id)
                                libraryView.mangaSelected(libEntry.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // A column title of the table
    component HeaderCell: Text {
        property int align: Text.AlignHCenter
        horizontalAlignment: align
        color: Theme.inkSub
        rightPadding: align === Text.AlignRight ? 8 : 0
        font.family: Theme.fontFamily
        font.pixelSize: ReaderType.sizeCaption
        font.weight: ReaderType.weightTitle
        font.styleName: ReaderType.styleTitle
        font.letterSpacing: 0.3
    }
}
