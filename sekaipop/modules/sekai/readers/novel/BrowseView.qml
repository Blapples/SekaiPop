// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM
import "../NovelMath.js" as NM

Item {
    id: browseView

    // Covers per row: four on the side card, more as the panel gets wider (full window).
    readonly property int gridColumns: RM.gridColumns(novelGrid.width, 190, 4, 10)

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal novelSelected(string novelId)

    // Two ways in, side by side: Discover (AniList's novels: trending, search, filters) is the
    // main one and the default; Source is the picked source's own Hot / Latest lists. The chips
    // beside the switch are the sorts of whichever one is showing.
    readonly property bool discover: Novel.browseSource === "anilist"

    // Source mode: which of its lists is showing (hot, latest, or a typed search)
    property string currentFilter: "hot"
    // The Sources page (extensions, sources, repositories) over the whole view
    property bool sourcesOpen: false

    // Discover: the filter keys' lists, and the title whose page is open over the grid
    property bool filtersOpen: false
    property string openFilter: ""                    // which filter's list is dropped down ("" = none)
    property bool infoOpen: false
    property var  infoCard: null

    readonly property var genreOptions:  NM.GENRES.map(g => ({ label: g, value: g }))
    readonly property var yearOptions:   NM.yearOptions(new Date().getFullYear())
    // AniList's tags for the Tags list, with their category as the grey hint (18+ tags only
    // while 18+ is on)
    readonly property var tagOptions: (Novel.discoverTagList || [])
        .filter(function(t) { return Novel.discoverAdult || !t.isAdult })
        .map(function(t) { return { label: t.name, value: t.name, hint: (t.category || "").replace("-", " · ") } })

    function toggleOpen(key) { openFilter = openFilter === key ? "" : key }
    // "Genre" or "Genre · 3": the key of a filter that can have several on
    function summary(title, n) { return n > 0 ? title + " · " + n : title }
    // The key of a filter that has one value: its title, or the chosen option's label.
    // `none` is the value that means "any" (the "Any" option).
    function valueLabel(title, options, value, none) {
        if (value === none) return title
        for (let i = 0; i < options.length; i++)
            if (options[i].value === value) return title + " · " + (options[i].chip || options[i].label)
        return title
    }

    onFiltersOpenChanged: if (!filtersOpen) openFilter = ""
    // The filters are Discover's, so their list folds away when the source's own lists are showing
    // (the filters key stays, and takes you back to Discover)
    onDiscoverChanged: if (!discover) filtersOpen = false

    function _switchFilter(f) {
        if (currentFilter === f) return
        currentFilter = f
        searchBar.clear()
        Novel.clearNovelList()
        if (f === "hot") Novel.fetchHot()
        else             Novel.fetchLatest(true)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Search + source + filters key ────────────────────────────────────
        Item {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: 58

            RowLayout {
                id: topRow
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                SearchPill {
                    id: searchBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: ReaderType.hField
                    placeholder: browseView.discover ? "Search AniList novels…" : "Search novels…"
                    onTextChanged: searchDebounce.restart()
                }

                // Which source the chapters come from, by name; a tap goes to the next installed
                // one (with none installed it opens the Sources page).
                ReaderChip {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: ReaderType.hField
                    icon: "swap_horiz"
                    enabled: Novel.sourceBusyId === ""
                    text: {
                        if (Novel.sourceBusyId !== "") return "Switching…"
                        return Novel.sources.length === 0 ? "Add source" : Novel.sourceLabel
                    }
                    onClicked: {
                        if (Novel.sources.length === 0) browseView.sourcesOpen = true
                        else                            Novel.cycleSource()
                    }
                }

                // The extensions, sources and repositories, managed here
                ReaderKey {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: ReaderType.hField
                    icon: "extension"
                    onClicked: browseView.sourcesOpen = true
                }

                // Just the icon, as tall as the search pill beside it; a small count sits on its
                // corner while filters are on, so how many are on is still readable
                ReaderKey {
                    id: tuneKey
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: ReaderType.hField
                    icon: "tune"
                    lit: browseView.filtersOpen || Novel.discoverFilterCount > 0
                    onClicked: {
                        // Filters are AniList's: from the source's list, the key goes to Discover
                        if (!browseView.discover) {
                            searchBar.clear()
                            Novel.showDiscover()
                            Novel.setDiscoverSearch("")
                        }
                        browseView.filtersOpen = !browseView.filtersOpen
                    }

                    Rectangle {
                        visible: Novel.discoverFilterCount > 0
                        anchors { top: parent.top; right: parent.right; topMargin: -5; rightMargin: -5 }
                        width: Math.max(18, countText.implicitWidth + 8)
                        height: 18
                        radius: 9
                        color: ReaderType.tagFill
                        border.width: 1
                        border.color: Theme.accentMint

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: Novel.discoverFilterCount
                            color: ReaderType.tagInk
                            font.family: Theme.fontFamily
                            font.pixelSize: ReaderType.sizeCaption
                            font.weight: Font.ExtraBold
                            font.styleName: Theme.fontStyleBold
                        }
                    }
                }
            }

            Timer {
                id: searchDebounce
                interval: 380
                onTriggered: {
                    var q = searchBar.text.trim()
                    // Discover's search is AniList's
                    if (browseView.discover) { Novel.setDiscoverSearch(q); return }
                    if (q.length > 0) {
                        browseView.currentFilter = "search"
                        Novel.searchNovels(q, "", "All", true)
                    } else if (browseView.currentFilter === "search") {
                        browseView.currentFilter = "hot"
                        Novel.fetchHot()
                    }
                }
            }
        }

        // ── Mode switch + sorts, one row ──────────────────────────────────────
        // Discover (AniList) is the main way in; Source opens the picked source's own lists, like
        // a source tab in Mihon. The chips after the switch change with it: Trending / Popular /
        // Top rated / Favorites / Newest for Discover, Hot / Latest for the source.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46

            TextMetrics {
                id: sourceMetrics
                text: Novel.sourceLabel
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.ExtraBold
            }
            TextMetrics {
                id: discoverMetrics
                text: "Discover"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.ExtraBold
            }

            SegmentSwitch {
                id: modeSwitch
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
                height: ReaderType.hChip
                // Two equal slots, as wide as the longer name needs (a long source name is cut short)
                width: Math.min(320, Math.max(190, 2 * (Math.max(sourceMetrics.advanceWidth, discoverMetrics.advanceWidth) + 36)))
                options: [
                    { id: "anilist", label: "Discover" },
                    { id: "source",  label: Novel.sourceLabel }
                ]
                current: Novel.browseSource
                onPicked: function(id) {
                    if (id === Novel.browseSource) return
                    searchBar.clear()
                    if (id === "source") {
                        Novel.showSource()
                        // a search typed in the source's list is gone with the box: back to Hot
                        if (browseView.currentFilter === "search") {
                            browseView.currentFilter = "hot"
                            Novel.clearNovelList()
                            Novel.fetchHot()
                        }
                    } else {
                        Novel.showDiscover()
                        // likewise a search typed in Discover: its list goes back to the sort's
                        Novel.setDiscoverSearch("")
                    }
                }
            }

            Rectangle {
                id: modeDivider
                anchors { left: modeSwitch.right; leftMargin: 10; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
                width: 2
                height: 18
                radius: 1
                color: Colors.outline_variant
            }

            ListView {
                id: sortList
                anchors { left: modeDivider.right; leftMargin: 10; right: parent.right; rightMargin: 16; top: parent.top; bottom: parent.bottom }
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                model: browseView.discover ? NM.DISCOVER_SORTS : [
                    { label: "Hot",    value: "hot"    },
                    { label: "Latest", value: "latest" }
                ]

                delegate: Item {
                    width: chip.implicitWidth
                    height: sortList.height

                    ReaderChip {
                        id: chip
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: modelData.label
                        // Discover: a typed search is ordered by best match, so no sort is lit then
                        lit: browseView.discover
                             ? (Novel.discoverQuery.length === 0 && Novel.discoverSort === modelData.value)
                             : browseView.currentFilter === modelData.value
                        onClicked: {
                            if (browseView.discover) { searchBar.clear(); Novel.setDiscoverSort(modelData.value) }
                            else                     browseView._switchFilter(modelData.value)
                        }
                    }
                }
            }
        }

        // ── Filters (Discover's) ─────────────────────────────────────────────
        Item {
            id: filterPanel
            Layout.fillWidth: true
            Layout.preferredHeight: (browseView.discover && browseView.filtersOpen)
                ? Math.min(filterFlick.contentHeight + 6, browseView.height * 0.6) : 0
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

                    // One key per filter. A key opens its list right under the row (one at a
                    // time); a key is lit while it has something on or its list is open.
                    Flow {
                        width: parent.width
                        spacing: 8

                        ReaderChip {
                            text: browseView.summary("Genre", Novel.discoverGenres.length)
                            icon: browseView.openFilter === "genre" ? "expand_less" : "expand_more"
                            lit: Novel.discoverGenres.length > 0 || browseView.openFilter === "genre"
                            onClicked: browseView.toggleOpen("genre")
                        }
                        ReaderChip {
                            text: browseView.summary("Tags", Novel.discoverTags.length)
                            icon: browseView.openFilter === "tags" ? "expand_less" : "expand_more"
                            lit: Novel.discoverTags.length > 0 || browseView.openFilter === "tags"
                            onClicked: {
                                browseView.toggleOpen("tags")
                                if (browseView.openFilter === "tags") Novel.fetchDiscoverTags()
                            }
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Origin", NM.COUNTRIES, Novel.discoverCountry, "")
                            icon: browseView.openFilter === "country" ? "expand_less" : "expand_more"
                            lit: Novel.discoverCountry !== "" || browseView.openFilter === "country"
                            onClicked: browseView.toggleOpen("country")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Length", NM.LENGTHS, Novel.discoverLength, "")
                            icon: browseView.openFilter === "length" ? "expand_less" : "expand_more"
                            lit: Novel.discoverLength !== "" || browseView.openFilter === "length"
                            onClicked: browseView.toggleOpen("length")
                        }
                        ReaderChip {
                            text: browseView.summary("Status", Novel.discoverStatuses.length)
                            icon: browseView.openFilter === "status" ? "expand_less" : "expand_more"
                            lit: Novel.discoverStatuses.length > 0 || browseView.openFilter === "status"
                            onClicked: browseView.toggleOpen("status")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Min score", NM.SCORE_MIN, Novel.discoverScoreMin, 0)
                            icon: browseView.openFilter === "scoreMin" ? "expand_less" : "expand_more"
                            lit: Novel.discoverScoreMin > 0 || browseView.openFilter === "scoreMin"
                            onClicked: browseView.toggleOpen("scoreMin")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Max score", NM.SCORE_MAX, Novel.discoverScoreMax, 0)
                            icon: browseView.openFilter === "scoreMax" ? "expand_less" : "expand_more"
                            lit: Novel.discoverScoreMax > 0 || browseView.openFilter === "scoreMax"
                            onClicked: browseView.toggleOpen("scoreMax")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Year", browseView.yearOptions, Novel.discoverYear, 0)
                            icon: browseView.openFilter === "year" ? "expand_less" : "expand_more"
                            lit: Novel.discoverYear > 0 || browseView.openFilter === "year"
                            onClicked: browseView.toggleOpen("year")
                        }
                        ReaderChip {
                            text: "18+"
                            icon: Novel.discoverAdult ? "check" : ""
                            lit: Novel.discoverAdult
                            onClicked: Novel.toggleDiscoverAdult()
                        }
                        ReaderChip {
                            visible: Novel.discoverFilterCount > 0
                            icon: "close"
                            text: "Clear"
                            onClicked: { browseView.openFilter = ""; Novel.clearDiscoverFilters() }
                        }
                    }

                    // The tags that are on, to tap off without opening the list
                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: Novel.discoverTags.length > 0

                        Repeater {
                            model: Novel.discoverTags

                            delegate: ReaderChip {
                                text: modelData
                                icon: "close"
                                lit: true
                                onClicked: Novel.toggleDiscoverTag(modelData)
                            }
                        }
                    }

                    // The open list: Genre, Tags and Status stay open while you tick several;
                    // the others pick one and close.
                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "genre"
                        options: browseView.genreOptions
                        selected: Novel.discoverGenres
                        onPicked: function(value) { Novel.toggleDiscoverGenre(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "tags"
                        searchable: true
                        placeholder: "Search tags…"
                        emptyText: Novel.discoverTagsError.length > 0 ? Novel.discoverTagsError
                                 : Novel.isFetchingDiscoverTags ? "Loading tags…" : "No tag called that"
                        options: browseView.tagOptions
                        selected: Novel.discoverTags
                        onPicked: function(value) { Novel.toggleDiscoverTag(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "country"
                        options: NM.COUNTRIES
                        selected: [Novel.discoverCountry]
                        onPicked: function(value) { Novel.setDiscoverCountry(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "length"
                        options: NM.LENGTHS
                        selected: [Novel.discoverLength]
                        onPicked: function(value) { Novel.setDiscoverLength(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "status"
                        options: NM.STATUSES
                        selected: Novel.discoverStatuses
                        onPicked: function(value) { Novel.toggleDiscoverStatus(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "scoreMin"
                        options: NM.SCORE_MIN
                        selected: [Novel.discoverScoreMin]
                        onPicked: function(value) { Novel.setDiscoverScoreMin(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "scoreMax"
                        options: NM.SCORE_MAX
                        selected: [Novel.discoverScoreMax]
                        onPicked: function(value) { Novel.setDiscoverScoreMax(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "year"
                        options: browseView.yearOptions
                        selected: [Novel.discoverYear]
                        onPicked: function(value) { Novel.setDiscoverYear(value); browseView.openFilter = "" }
                    }
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Novel grid ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            Rectangle { anchors.fill: parent; color: Colors.background }

            // Loading overlay: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                active: browseView.discover
                    ? (Novel.isFetchingDiscover && Novel.discoverList.length === 0)
                    : ((Novel.isFetchingNovel || Novel.isSwitchingProvider) && Novel.novelList.length === 0)
                columns: browseView.gridColumns
                cellWidth: (width - 30) / browseView.gridColumns
                ratio: 1.65
            }

            // Nothing installed yet: say so, and offer the sources sheet
            Item {
                anchors.fill: parent; z: 8
                visible: !browseView.discover && Novel.serverReady && Novel.sourcesLoaded && Novel.sources.length === 0

                Rectangle { anchors.fill: parent; color: Colors.background }

                EmptyState {
                    id: noSourceCard
                    glyph: "+"
                    title: "No source yet"
                    subtitle: "Novels come from LNReader sources. Add one to start browsing."
                    displayFont: browseView.fontDisplay
                    bodyFont: browseView.fontBody
                }

                ReaderChip {
                    anchors { top: noSourceCard.bottom; topMargin: 20; horizontalCenter: parent.horizontalCenter }
                    text: "Add sources"
                    lit: true
                    onClicked: browseView.sourcesOpen = true
                }
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: browseView.discover
                    ? (Novel.isFetchingDiscover && Novel.discoverList.length > 0)
                    : (Novel.isFetchingNovel && Novel.novelList.length > 0)
            }

            // Discover found nothing (a filter set that nothing matches, or a search with no hit)
            EmptyState {
                visible: browseView.discover && Novel.serverReady && !Novel.isFetchingDiscover
                         && Novel.discoverError.length === 0 && Novel.discoverList.length === 0
                z: 8
                title: "Nothing found"
                subtitle: Novel.discoverFilterCount > 0 ? "Try different words or fewer filters"
                                                         : "Try different words"
                displayFont: browseView.fontDisplay
                bodyFont: browseView.fontBody
            }

            // Discover could not be loaded: its error where the first page would be, and a way to
            // ask again (a page that fails later is left out quietly, the list stays)
            Rectangle {
                anchors.fill: parent; color: Colors.background; z: 9
                visible: browseView.discover && Novel.discoverError.length > 0
                         && Novel.discoverList.length === 0 && !Novel.isFetchingDiscover

                Column {
                    anchors.centerIn: parent; spacing: 12
                    Text { text: "⚠"; font.pixelSize: 32; color: Colors.error; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: Novel.discoverError; color: Colors.on_surface_variant
                        font.pixelSize: 12; font.family: browseView.fontBody
                        wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                    }
                    ReaderChip {
                        anchors.horizontalCenter: parent.horizontalCenter
                        icon: "refresh"
                        text: "Try again"
                        onClicked: Novel.discoverBrowse(true)
                    }
                }
            }

            // Error overlay
            Rectangle {
                anchors.fill: parent; color: Colors.background; z: 9
                visible: !browseView.discover && Novel.novelError.length > 0 && !Novel.isFetchingNovel

                Column {
                    anchors.centerIn: parent; spacing: 10
                    Text { text: "⚠"; font.pixelSize: 32; color: Colors.error; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: Novel.novelError; color: Colors.on_surface_variant
                        font.pixelSize: 12; font.family: browseView.fontBody
                        wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                    }
                }
            }

            GridView {
                id: novelGrid
                // While the panel changes width the grid is laid out at the width the move ends at
                // and keeps it, so no cover is resized or re-wrapped on every frame (as in manga).
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 10 }
                width: ReaderEnv.panelResizing ? Math.max(0, Math.round(ReaderEnv.panelBodyTarget) - 20)
                                               : parent.width - 20
                cellWidth: (width - 10) / browseView.gridColumns
                cellHeight: cellWidth * 1.58
                clip: true; boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: browseView.discover ? Novel.discoverList : Novel.novelList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2) {
                        if (browseView.discover) Novel.discoverNextPage()
                        else                     Novel.fetchNextPage()
                    }
                }

                delegate: Item {
                    width: novelGrid.cellWidth; height: novelGrid.cellHeight

                    CoverCard {
                        anchors.fill: parent
                        source: modelData.coverUrl || ""
                        title: modelData.title || ""
                        bodyFont: browseView.fontBody
                        // The whole title over the foot of the art, like the manga grid; nothing
                        // else is written under it (no volumes / chapters, no author)
                        fullTitle: true
                        holdTitle: false

                        // The source's status stamp
                        ReaderBadge {
                            visible: !browseView.discover && modelData.status && modelData.status.length > 0
                            anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                            rotation: -4
                            text: (modelData.status || "").toUpperCase()
                            fill: modelData.status === "Ongoing" ? Theme.accentMint : Theme.accentCyan
                        }

                        // Discover: AniList's average score, when it has one ...
                        ReaderBadge {
                            visible: browseView.discover && (modelData.score || 0) > 0
                            anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                            rotation: -4
                            text: "★ " + ((modelData.score || 0) / 10).toFixed(1)
                            fill: Theme.accentMint
                        }

                        // ... and where it is from, in two letters (LN, KR, CN, TW): "LIGHT NOVEL" was
                        // wider than the card and sat on top of the score. A dark see-through tag,
                        // so the score is the one bright thing on the cover.
                        ReaderBadge {
                            visible: browseView.discover && NM.typeShort(modelData.type).length > 0
                            anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                            implicitHeight: 20
                            rotation: 0
                            text: NM.typeShort(modelData.type)
                            fill: ReaderType.tagFill
                            ink: ReaderType.tagInk
                            outline: "transparent"
                        }

                        onClicked: {
                            if (browseView.discover) {
                                // a title, not something to read yet: its page finds it in the source
                                browseView.infoCard = modelData
                                browseView.infoOpen = true
                            } else {
                                Novel.fetchNovelDetail(modelData.id)
                                browseView.novelSelected(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── A Discover title's page ───────────────────────────────────────────────
    // Over the whole view. Opening a novel from it goes on to the novel's own page (novelSelected),
    // and coming back from there lands on this page again, to try another match.
    DiscoverInfo {
        anchors.fill: parent
        z: 15
        visible: browseView.infoOpen
        card: browseView.infoCard
        onClosed: browseView.infoOpen = false
        onSourcesRequested: browseView.sourcesOpen = true
        onNovelPicked: function(novelId) { browseView.novelSelected(novelId) }
    }

    // ── Sources sheet ─────────────────────────────────────────────────────────
    SourcesView {
        anchors.fill: parent
        z: 20
        visible: browseView.sourcesOpen
        onClosed: browseView.sourcesOpen = false
    }
}
