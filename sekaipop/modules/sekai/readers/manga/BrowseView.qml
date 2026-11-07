// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

Item {
    id: browseView

    // ── Exposed API ──────────────────────────────────────────────────────────
    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    // Emitted when the user taps a manga card
    signal mangaSelected(string mangaId)
    // The puzzle key beside Source (only while Suwayomi is offered): open the Sources page
    signal sourcesRequested()

    // Covers per row: four on the side card, more as the panel gets wider (full window).
    readonly property int gridColumns: RM.gridColumns(mangaGrid.width, 190, 4, 10)

    property bool filtersOpen: false
    // Which filter's list is dropped down under the keys ("" = none)
    property string openFilter: ""

    // ── What the chips offer ─────────────────────────────────────────────────
    // Two ways in, side by side in one switch: Discover (AniList: trending, search, filters) is the
    // main one and the default; the second is the picked source's own lists (WeebCentral, MangaDex,
    // a Suwayomi source). The chips beside the switch are the sorts of whichever one is showing.
    readonly property bool sourceMode: Manga.browseMode === "source"

    // Discover's sorts (AniList's)
    readonly property var sortOptions: [
        { label: "Trending",  value: "TRENDING_DESC"   },
        { label: "Popular",   value: "POPULARITY_DESC" },
        { label: "Top rated", value: "SCORE_DESC"      },
        { label: "Favorites", value: "FAVOURITES_DESC" }
    ]

    // The source's sorts: only the ones it answered it has (WeebCentral: Popular and Latest;
    // MangaDex adds Top rated; a Suwayomi source adds rating / views when it can sort that way)
    readonly property var sourceSortLabels: ({
        popular: "Popular", latest: "Latest", rating: "Top rated", views: "Most viewed"
    })
    readonly property var sourceSortOptions: (Manga.sourceSorts || []).map(function(s) {
        return { label: browseView.sourceSortLabels[s] || s, value: s }
    })

    readonly property var genreOptions: [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror",
        "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance",
        "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"
    ].map(g => ({ label: g, value: g }))

    readonly property var formatOptions: [
        { label: "Any",      value: ""         },
        { label: "Manga",    value: "MANGA"    },
        { label: "One shot", value: "ONE_SHOT" }
    ]

    readonly property var countryOptions: [
        { label: "Any",             value: ""   },
        { label: "Japan (manga)",   value: "JP" },
        { label: "Korea (manhwa)",  value: "KR" },
        { label: "China (manhua)",  value: "CN" }
    ]

    // Any number can be on at once; none on means any status
    readonly property var statusOptions: [
        { label: "Releasing", value: "RELEASING"        },
        { label: "Finished",  value: "FINISHED"         },
        { label: "Hiatus",    value: "HIATUS"           },
        { label: "Upcoming",  value: "NOT_YET_RELEASED" },
        { label: "Cancelled", value: "CANCELLED"        }
    ]

    // AniList scores run 0-100 and the cards show them out of 10, so the chips do too.
    // Min: "7.0+" keeps 7.0 and over. Max: "Up to 8.0" keeps 8.0 and under.
    readonly property var scoreMinOptions: [
        { label: "Any",  value: 0  },
        { label: "5.0+", value: 50 },
        { label: "6.0+", value: 60 },
        { label: "7.0+", value: 70 },
        { label: "7.5+", value: 75 },
        { label: "8.0+", value: 80 },
        { label: "8.5+", value: 85 },
        { label: "9.0+", value: 90 }
    ]

    readonly property var scoreMaxOptions: [
        { label: "Any",       value: 0  },
        { label: "Up to 5.0", value: 50 },
        { label: "Up to 6.0", value: 60 },
        { label: "Up to 7.0", value: 70 },
        { label: "Up to 8.0", value: 80 },
        { label: "Up to 9.0", value: 90 }
    ]

    // Any, then this year and back 40 years
    readonly property var yearOptions: {
        const y = new Date().getFullYear()
        const out = [{ label: "Any", value: 0 }]
        for (let i = 0; i < 40; i++)
            out.push({ label: String(y - i), value: y - i })
        return out
    }

    // ── Dropdown helpers ─────────────────────────────────────────────────────
    function toggleOpen(key) { openFilter = openFilter === key ? "" : key }

    // "Genre" or "Genre · 3": the key of a filter that can have several on
    function summary(title, n) { return n > 0 ? title + " · " + n : title }

    // The key of a filter that has one value: its title, or the chosen option's label.
    // `none` is the value that means "any" (the "Any" option).
    function valueLabel(title, options, value, none) {
        if (value === none) return title
        for (let i = 0; i < options.length; i++)
            if (options[i].value === value) return title + " · " + options[i].label
        return title
    }

    // AniList's tags for the Tags list, with their category as the grey hint
    // (18+ tags only while 18+ is on)
    readonly property var tagOptions: (Manga.tagList || [])
        .filter(function(t) { return Manga.browseAdult || !t.isAdult })
        .map(function(t) { return { label: t.name, value: t.name, hint: (t.category || "").replace("-", " · ") } })

    onFiltersOpenChanged: if (!filtersOpen) openFilter = ""

    // Filters are Discover's, so they fold away when the source's own lists are showing
    Connections {
        target: Manga
        function onBrowseModeChanged() {
            if (Manga.browseMode === "source") browseView.filtersOpen = false
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Search + filters key ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                SearchPill {
                    id: searchBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: ReaderType.hField
                    placeholder: "Search titles…"
                    onTextChanged: searchDebounce.restart()
                }

                // Which source the chapters come from: WeebCentral, MangaDex or one of Suwayomi's
                // picked sources by name; a tap goes to the next one.
                ReaderChip {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: ReaderType.hField
                    icon: "swap_horiz"
                    text: Manga.sourceLabel
                    onClicked: Manga.cycleProvider()
                }

                // Suwayomi's extensions and sources, managed here instead of in its web page
                ReaderKey {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: ReaderType.hField
                    visible: Manga.swOffered
                    icon: "extension"
                    onClicked: browseView.sourcesRequested()
                }

                // Just the icon, as tall as the search pill beside it; a small count sits on its
                // corner while filters are on, so how many are on is still readable
                ReaderKey {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: ReaderType.hField
                    icon: "tune"
                    lit: browseView.filtersOpen || Manga.activeFilterCount > 0
                    onClicked: {
                        // Filters are AniList's: from a source's list, the key goes to Discover
                        if (browseView.sourceMode) { searchBar.clear(); Manga.showAniList() }
                        browseView.filtersOpen = !browseView.filtersOpen
                    }

                    Rectangle {
                        visible: Manga.activeFilterCount > 0
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
                            text: Manga.activeFilterCount
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
                interval: 350
                onTriggered: {
                    const t = searchBar.text.trim()
                    if (t === Manga.browseQuery) return
                    Manga.browseQuery = t
                    // Search is AniList's; a source's own Popular / Latest lists have none
                    if (Manga.browseMode === "source") Manga.browseMode = "anilist"
                    Manga.browse(true)
                }
            }
        }

        // ── Mode switch + sorts, one row ─────────────────────────────────────
        // Discover (AniList) is the main way in. The second segment is the picked source by name
        // and opens that source's own lists, like a source tab in Mihon. The chips after the
        // switch change with it: Trending / Popular / Top rated / Favorites for Discover, the
        // source's own sorts (Popular, Latest, ...) for the source.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46

            TextMetrics {
                id: sourceMetrics
                text: Manga.sourceLabel
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
                    { id: "source",  label: Manga.sourceLabel }
                ]
                current: Manga.browseMode
                onPicked: function(id) {
                    if (id === Manga.browseMode) return
                    searchBar.clear()
                    if (id === "source") Manga.setSourceSort(Manga.sourceSort)
                    else                 Manga.showAniList()
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
                model: browseView.sourceMode ? browseView.sourceSortOptions : browseView.sortOptions

                delegate: Item {
                    width: chip.implicitWidth
                    height: sortList.height

                    ReaderChip {
                        id: chip
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: modelData.label
                        // Discover: a typed search is ordered by best match, so no sort is lit then
                        lit: browseView.sourceMode
                             ? Manga.sourceSort === modelData.value
                             : (Manga.browseQuery.length === 0 && Manga.browseSort === modelData.value)
                        onClicked: {
                            searchBar.clear()
                            if (browseView.sourceMode) {
                                Manga.setSourceSort(modelData.value)
                            } else {
                                Manga.browseQuery = ""
                                Manga.browseSort = modelData.value
                                Manga.browse(true)
                            }
                        }
                    }
                }
            }
        }

        // ── Filters ──────────────────────────────────────────────────────────
        Item {
            id: filterPanel
            Layout.fillWidth: true
            Layout.preferredHeight: browseView.filtersOpen
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
                            text: browseView.summary("Genre", Manga.browseGenres.length)
                            icon: browseView.openFilter === "genre" ? "expand_less" : "expand_more"
                            lit: Manga.browseGenres.length > 0 || browseView.openFilter === "genre"
                            onClicked: browseView.toggleOpen("genre")
                        }
                        ReaderChip {
                            text: browseView.summary("Tags", Manga.browseTags.length)
                            icon: browseView.openFilter === "tags" ? "expand_less" : "expand_more"
                            lit: Manga.browseTags.length > 0 || browseView.openFilter === "tags"
                            onClicked: {
                                browseView.toggleOpen("tags")
                                if (browseView.openFilter === "tags") Manga.fetchTags()
                            }
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Origin", browseView.countryOptions, Manga.browseCountry, "")
                            icon: browseView.openFilter === "country" ? "expand_less" : "expand_more"
                            lit: Manga.browseCountry !== "" || browseView.openFilter === "country"
                            onClicked: browseView.toggleOpen("country")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Format", browseView.formatOptions, Manga.browseFormat, "")
                            icon: browseView.openFilter === "format" ? "expand_less" : "expand_more"
                            lit: Manga.browseFormat !== "" || browseView.openFilter === "format"
                            onClicked: browseView.toggleOpen("format")
                        }
                        ReaderChip {
                            text: browseView.summary("Status", Manga.browseStatuses.length)
                            icon: browseView.openFilter === "status" ? "expand_less" : "expand_more"
                            lit: Manga.browseStatuses.length > 0 || browseView.openFilter === "status"
                            onClicked: browseView.toggleOpen("status")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Min score", browseView.scoreMinOptions, Manga.browseScoreMin, 0)
                            icon: browseView.openFilter === "scoreMin" ? "expand_less" : "expand_more"
                            lit: Manga.browseScoreMin > 0 || browseView.openFilter === "scoreMin"
                            onClicked: browseView.toggleOpen("scoreMin")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Max score", browseView.scoreMaxOptions, Manga.browseScoreMax, 0)
                            icon: browseView.openFilter === "scoreMax" ? "expand_less" : "expand_more"
                            lit: Manga.browseScoreMax > 0 || browseView.openFilter === "scoreMax"
                            onClicked: browseView.toggleOpen("scoreMax")
                        }
                        ReaderChip {
                            text: browseView.valueLabel("Year", browseView.yearOptions, Manga.browseYear, 0)
                            icon: browseView.openFilter === "year" ? "expand_less" : "expand_more"
                            lit: Manga.browseYear > 0 || browseView.openFilter === "year"
                            onClicked: browseView.toggleOpen("year")
                        }
                        ReaderChip {
                            text: "18+"
                            icon: Manga.browseAdult ? "check" : ""
                            lit: Manga.browseAdult
                            onClicked: Manga.toggleAdult()
                        }
                        ReaderChip {
                            visible: Manga.activeFilterCount > 0
                            icon: "close"
                            text: "Clear"
                            onClicked: { browseView.openFilter = ""; Manga.clearFilters() }
                        }
                    }

                    // The tags that are on, to tap off without opening the list
                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: Manga.browseTags.length > 0

                        Repeater {
                            model: Manga.browseTags

                            delegate: ReaderChip {
                                text: modelData
                                icon: "close"
                                lit: true
                                onClicked: Manga.toggleTag(modelData)
                            }
                        }
                    }

                    // The open list: Genre, Tags and Status stay open while you tick several;
                    // the others pick one and close.
                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "genre"
                        options: browseView.genreOptions
                        selected: Manga.browseGenres
                        onPicked: function(value) { Manga.toggleGenre(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "tags"
                        searchable: true
                        placeholder: "Search tags…"
                        emptyText: Manga.tagsError.length > 0 ? Manga.tagsError
                                 : Manga.isFetchingTags ? "Loading tags…" : "No tag called that"
                        options: browseView.tagOptions
                        selected: Manga.browseTags
                        onPicked: function(value) { Manga.toggleTag(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "country"
                        options: browseView.countryOptions
                        selected: [Manga.browseCountry]
                        onPicked: function(value) { Manga.setCountry(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "format"
                        options: browseView.formatOptions
                        selected: [Manga.browseFormat]
                        onPicked: function(value) { Manga.setFormat(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "status"
                        options: browseView.statusOptions
                        selected: Manga.browseStatuses
                        onPicked: function(value) { Manga.toggleStatus(value) }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "scoreMin"
                        options: browseView.scoreMinOptions
                        selected: [Manga.browseScoreMin]
                        onPicked: function(value) { Manga.setScoreMin(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "scoreMax"
                        options: browseView.scoreMaxOptions
                        selected: [Manga.browseScoreMax]
                        onPicked: function(value) { Manga.setScoreMax(value); browseView.openFilter = "" }
                    }

                    FilterMenu {
                        width: parent.width
                        visible: browseView.openFilter === "year"
                        options: browseView.yearOptions
                        selected: [Manga.browseYear]
                        onPicked: function(value) { Manga.setYear(value); browseView.openFilter = "" }
                    }
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Main content area ────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle { anchors.fill: parent; color: Colors.background }

            // Loading state: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent
                z: 10
                active: Manga.isFetchingManga && Manga.mangaList.length === 0
                columns: browseView.gridColumns
                cellWidth: (width - 30) / browseView.gridColumns
                ratio: 1.58
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: Manga.isFetchingManga && Manga.mangaList.length > 0
            }

            // Nothing matched
            EmptyState {
                visible: Manga.serverReady && !Manga.isFetchingManga
                         && Manga.mangaError.length === 0 && Manga.mangaList.length === 0
                z: 8
                title: "Nothing found"
                subtitle: Manga.browseMode === "source"
                    ? "This source has nothing in this list"
                    : (Manga.activeFilterCount > 0
                       ? "Try different words or fewer filters"
                       : "Try different words")
                displayFont: browseView.fontDisplay
                bodyFont: browseView.fontBody
            }

            // Error state
            Rectangle {
                anchors.fill: parent
                color: Colors.background
                visible: Manga.mangaError.length > 0 && !Manga.isFetchingManga
                z: 9

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    StyledText {
                        text: "⚠"
                        font.pixelSize: 32
                        color: Colors.error
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        text: Manga.mangaError
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        font.family: browseView.fontBody
                        wrapMode: Text.Wrap
                        width: 260
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 1.4
                    }
                }
            }

            // ── Manga grid ───────────────────────────────────────────────────
            GridView {
                id: mangaGrid
                // While the panel changes width the grid is laid out at the width the move ends
                // at and keeps it: the card's edge uncovers or covers the covers, and none of
                // them is resized or re-wrapped on every frame (the cost of the stutter).
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 10 }
                width: ReaderEnv.panelResizing ? Math.max(0, Math.round(ReaderEnv.panelBodyTarget) - 20)
                                               : parent.width - 20
                cellWidth: (width - 10) / browseView.gridColumns
                cellHeight: cellWidth * 1.58
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: Manga.mangaList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2)
                        Manga.fetchNextMangaPage()
                }

                delegate: Item {
                    width: mangaGrid.cellWidth
                    height: mangaGrid.cellHeight

                    CoverCard {
                        anchors.fill: parent
                        source: modelData.thumbUrl || ""
                        title: modelData.title || ""
                        bodyFont: browseView.fontBody
                        fullTitle: true
                        holdTitle: false

                        // Type tag: a dark see-through tag, not a second pink stamp, so the score
                        // is the one bright thing on the cover and the cover's own title stays visible
                        ReaderBadge {
                            visible: modelData.type && modelData.type.length > 0
                            anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                            implicitHeight: 20
                            rotation: 0
                            text: (modelData.type || "").toUpperCase()
                            fill: ReaderType.tagFill
                            ink: ReaderType.tagInk
                            outline: "transparent"
                        }

                        // AniList's average score, when it has one
                        ReaderBadge {
                            visible: (modelData.score || 0) > 0
                            anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                            rotation: -4
                            text: "★ " + ((modelData.score || 0) / 10).toFixed(1)
                            fill: Theme.accentMint
                        }

                        onClicked: {
                            Manga.fetchMangaDetail(modelData.id)
                            browseView.mangaSelected(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
