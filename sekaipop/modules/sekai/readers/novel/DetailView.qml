// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../NovelMath.js" as NM

Item {
    id: detailView

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal backRequested()
    signal chapterSelected(string chapterId)
    // The AniList chip while nobody is logged in: the panel opens its AniList page
    signal loginRequested()

    // ── Library state ─────────────────────────────────────────────────────────
    readonly property bool _inLibrary:
        Novel.currentNovel ? Novel.isInLibrary(Novel.currentNovel.id) : false

    // ── Where the chapters come from ──────────────────────────────────────────
    // The source the novel belongs to (a Library novel keeps the one it was added from)
    readonly property string _sourceName: Novel.currentNovel ? Novel.sourceNameFor(Novel.currentNovel.id) : ""
    readonly property string _sourceCaption: {
        if (!Novel.currentNovel || _sourceName.length === 0) return ""
        const volumes = Novel.currentNovel.chapters.some(ch => ch.kind === "volume")
        return (volumes ? "Volumes and chapters from " : "Chapters from ") + _sourceName
    }

    // ── What the header's stamps say ──────────────────────────────────────────
    // AniList's page of the matched novel (found with or without a login) gives the score, the year
    // and the wording of the status; a novel with no match still shows what its source says.
    readonly property var    _ai: Novel.infoKnown ? Novel.matchInfo : null
    readonly property string _statusWord: NM.statusWord(_ai ? _ai.status : "")
                                          || NM.statusWord(Novel.currentNovel ? Novel.currentNovel.status : "")
    readonly property string _score: _ai ? NM.scoreStamp(_ai.score) : ""
    readonly property string _year: _ai && _ai.year > 0 ? String(_ai.year) : ""

    // ── Filter / sort state ───────────────────────────────────────────────────
    property bool   _sortAscending: false
    property string _chapterFilter: ""

    function reset() {
        chapterSearch.clear()
        _chapterFilter = ""
        _sortAscending = false
        endSelect()
        _menuOpen = false
    }

    // ── Read / unread (like Mihon, and like the manga reader) ─────────────────
    // A long press or a right click on a chapter starts selecting; a click then toggles
    // chapters; the bar at the bottom marks the selection read or unread, or everything up to
    // the one chosen. The ... key by the sort key does the whole novel at once.
    property bool _selecting: false
    property var  _selected:  ({})          // chapterId -> true
    readonly property int _selectedCount: Object.keys(detailView._selected).length
    property bool  _menuOpen: false
    property point _menuPos: Qt.point(0, 0)

    readonly property string _novelId: Novel.currentNovel ? String(Novel.currentNovel.id) : ""
    on_NovelIdChanged: { endSelect(); _menuOpen = false; infoPanel.reset() }
    onVisibleChanged: {
        if (!visible) { endSelect(); _menuOpen = false; trackSheet.visible = false; matchPicker.visible = false; infoPanel.reset() }
    }

    function endSelect() {
        _selecting = false
        _selected  = ({})
    }

    // Starts selecting with `id`, or toggles it when already selecting.
    function pick(id) {
        const o = Object.assign({}, _selected)
        if (_selecting && o[id]) delete o[id]
        else                     o[id] = true
        _selected  = o
        _selecting = true
    }

    function toggleSelect(id) {
        pick(id)
        if (_selectedCount === 0) _selecting = false
    }

    function selectAll() {
        const o = {}
        for (let i = 0; i < _processedChapters.length; i++) o[_processedChapters[i].id] = true
        _selected = o
    }

    function markSelected(read) {
        Novel.setChaptersRead(Object.keys(_selected), read)
        endSelect()
    }

    // Everything from the first chapter up to the one selected, itself included
    function markUpToHere() {
        const ids = Object.keys(_selected)
        if (ids.length !== 1 || !Novel.currentNovel) return
        Novel.setChaptersRead(NM.idsUpTo(Novel.currentNovel.chapters, ids[0]), true)
        endSelect()
    }

    function markAll(read) {
        if (!Novel.currentNovel) return
        Novel.setChaptersRead(Novel.currentNovel.chapters.map(ch => ch.id), read)
        _menuOpen = false
    }

    readonly property int _readTotal: {
        const _dep = Novel.readMap          // read here so that marking a chapter moves the count
        return Novel.currentNovel ? Novel.readCount(Novel.currentNovel.chapters) : 0
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function formatChapter(ch) {
        if (!ch) return "?"
        const match = String(ch).match(/\d+(\.\d+)?/)
        return match ? match[0] : String(ch)
    }

    // The date a chapter was released, as its source says it: "Nov 4, 2026" when the source gave a
    // date, the source's own words ("3 months ago") when it gave one too loose to be a date, else "".
    function releaseText(ch) {
        if (!ch) return ""
        if (ch.publishAt) {
            const d = new Date(ch.publishAt)
            if (!isNaN(d.getTime())) {
                const t = Qt.formatDate(d, "MMM d, yyyy")
                if (t.length > 0) return t
            }
        }
        return ch.releasedText || ""
    }

    // ── Processed (filtered + sorted) chapter list ────────────────────────────
    readonly property var _processedChapters: {
        if (!Novel.currentNovel) return []
        let chapters = Novel.currentNovel.chapters.slice()

        if (detailView._chapterFilter.trim() !== "") {
            const f = detailView._chapterFilter.trim().toLowerCase()
            chapters = chapters.filter(ch => {
                const num   = detailView.formatChapter(ch.chapter).toLowerCase()
                const title = (ch.title || "").toLowerCase()
                return num.includes(f) || title.includes(f)
            })
        }

        // reading order (the source's own order where two share a number), then flipped if asked
        const ordered = NM.orderChapters(chapters)
        return detailView._sortAscending ? ordered : ordered.reverse()
    }

    // ── Continue reading ──────────────────────────────────────────────────────
    // Opens a chapter the way a tap on its row does.
    function openChapter(ch) {
        Novel.fetchChapter(ch.id)
        detailView.chapterSelected(ch.id)
        if (Novel.currentNovel && Novel.isInLibrary(Novel.currentNovel.id))
            Novel.updateLastRead(Novel.currentNovel.id, ch.id, ch.chapter)
    }

    // Where the reader left off, or null when there is nowhere to continue (nothing loaded, or
    // everything is read). Works on the reading order, whatever the list is sorted by or filtered to.
    readonly property var _continueTarget: {
        const n = Novel.currentNovel
        if (!n || !n.chapters || n.chapters.length === 0) return null
        const entry = Novel.getLibraryEntry(n.id)
        const _dep = Novel.readMap          // read here so that marking a chapter read moves the target
        return NM.continueTarget(n.chapters, entry ? entry.lastReadChapterId : "", Novel.isChapterRead)
    }

    // ═════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            z: 2

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 16 }
                spacing: 10

                ReaderKey {
                    icon: "arrow_back"
                    onClicked: {
                        if (detailView._selecting) { detailView.endSelect(); return }
                        Novel.clearDetail()
                        detailView.backRequested()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Novel.currentNovel ? Novel.currentNovel.title : ""
                    font.family: detailView.fontDisplay
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    color: Theme.ink
                    elide: Text.ElideRight
                }

                ReaderChip {
                    visible: Novel.currentNovel !== null
                    icon: detailView._inLibrary ? "check" : "add"
                    text: "Library"
                    lit: detailView._inLibrary
                    onClicked: {
                            if (detailView._inLibrary)
                                Novel.removeFromLibrary(Novel.currentNovel.id)
                            else
                                Novel.addToLibrary({
                                    id:       Novel.currentNovel.id,
                                    title:    Novel.currentNovel.title,
                                    coverUrl: Novel.currentNovel.coverUrl
                                })
                        }
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Hero ──────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Novel.currentNovel !== null ? 172 : 0
            clip: true
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Rectangle { anchors.fill: parent; color: Colors.background }

            // The cover, washed out behind everything
            Image {
                anchors.fill: parent
                source: Novel.currentNovel ? Novel.currentNovel.coverUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; opacity: 0.16
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.withAlpha(Colors.background, 0.35) }
                    GradientStop { position: 1.0; color: Colors.background }
                }
            }

            // The printed halftone of the shell's panels
            DotField {
                anchors.fill: parent
                corner: "tr"
                spacing: 14
                maxRadius: 3.2
                reach: 0.9
                dotColor: Qt.rgba(Theme.colBorder.r, Theme.colBorder.g, Theme.colBorder.b, 0.10)
                // not painted again for every width of a panel that is changing its width
                live: !ReaderEnv.panelResizing
                opacity: ReaderEnv.panelResizing ? 0.01 : 1
                Behavior on opacity { NumberAnimation { duration: ReaderEnv.panelResizing ? 0 : 220 } }
            }

            Row {
                anchors { fill: parent; margins: 16 }
                spacing: 18

                // The cover, a photo stuck on the page: outlined, ringed, with its hard
                // shadow, tilted a little, taped at the top
                Item {
                    width: 102
                    height: 146 + Theme.shadowOffset
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: -3

                    Pill {
                        anchors.fill: parent
                        cornerRadius: 13
                        ringWidth: Theme.borderWidth
                        innerRing: Theme.cardRing
                        fillColor: Theme.surface

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Colors.surface_container_high

                            Image {
                                anchors.fill: parent
                                source: Novel.currentNovel ? Novel.currentNovel.coverUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                    }

                    WashiTape {
                        x: 24
                        y: -9
                        width: 56
                        height: 18
                        rotation: -7
                    }
                }

                Column {
                    width: parent.width - 120
                    spacing: 7
                    anchors.verticalCenter: parent.verticalCenter

                    // Status, AniList score, your score, year and tracked stamps (the manga panel's)
                    Flow {
                        width: parent.width
                        spacing: 6

                        ReaderBadge {
                            visible: detailView._statusWord.length > 0
                            rotation: -3
                            text: detailView._statusWord.toUpperCase()
                            tonal: true
                            outline: Theme.accentMint
                        }

                        ReaderBadge {
                            visible: detailView._score.length > 0
                            rotation: 2
                            text: "\u2605 " + detailView._score
                            fill: Theme.accentCyan
                        }

                        ReaderBadge {
                            visible: Novel.trackScoreText.length > 0
                            rotation: -2
                            text: "YOU \u2605 " + Novel.trackScoreText
                            tonal: true
                            outline: Theme.accentCyan
                        }

                        ReaderBadge {
                            visible: detailView._year.length > 0
                            rotation: -2
                            text: detailView._year
                            tonal: true
                        }

                        ReaderBadge {
                            visible: Novel.trackEntry !== null
                            rotation: 3
                            text: "TRACKED"
                            tonal: true
                            outline: Theme.accentMint
                        }
                    }

                    // Author
                    StyledText {
                        width: parent.width
                        text: Novel.currentNovel ? Novel.currentNovel.author : ""
                        font.family: detailView.fontBody; font.pixelSize: 13
                        font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                        color: Theme.ink; elide: Text.ElideRight
                    }

                    // Genres
                    StyledText {
                        visible: Novel.currentNovel && Novel.currentNovel.genres.length > 0
                        width: parent.width
                        text: Novel.currentNovel ? Novel.currentNovel.genres.join(" · ") : ""
                        font.family: detailView.fontBody; font.pixelSize: 10
                        font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                        color: Theme.inkSub; elide: Text.ElideRight
                    }

                    // Description
                    StyledText {
                        width: parent.width
                        text: Novel.currentNovel ? Novel.currentNovel.description : ""
                        font.family: detailView.fontBody; font.pixelSize: 11
                        color: Theme.inkSub
                        wrapMode: Text.Wrap; maximumLineCount: 3
                        elide: Text.ElideRight; lineHeight: 1.3
                    }
                }
            }
        }

        Divider { Layout.fillWidth: true; visible: Novel.currentNovel !== null }

        // ── Chapter count, where they come from, and the novel's keys ─────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            visible: Novel.currentNovel !== null

            RowLayout {
                anchors { fill: parent; leftMargin: ReaderType.gutter; rightMargin: ReaderType.gutter }
                spacing: 8

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: !Novel.currentNovel ? ""
                            : Novel.currentNovel.chapters.length + " chapters"
                              + (detailView._readTotal > 0 ? " \u00b7 " + detailView._readTotal + " read" : "")
                        font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeBody
                        font.weight: ReaderType.weightTitle; font.styleName: ReaderType.styleTitle
                        color: Theme.ink
                        elide: Text.ElideRight
                    }

                    // The site stopped answering partway through the list
                    Text {
                        visible: Novel.currentNovel !== null && Novel.currentNovel.partial
                        width: parent.width
                        text: "List incomplete \u2014 tap to load the rest"
                        font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeCaption
                        font.weight: ReaderType.weightStrong; font.styleName: ReaderType.styleStrong
                        color: Theme.inkSub
                        elide: Text.ElideRight
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Novel.retryDetail()
                        }
                    }

                    Text {
                        visible: !(Novel.currentNovel !== null && Novel.currentNovel.partial)
                                 && detailView._sourceCaption.length > 0
                        width: parent.width
                        text: detailView._sourceCaption
                        font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeCaption
                        font.weight: ReaderType.weightBody; font.styleName: ReaderType.styleBody
                        color: Theme.inkSub
                        elide: Text.ElideRight
                    }
                }

                // Everything known about the novel (status, release, source, ratings, names, tags)
                ReaderChip {
                    visible: Novel.currentNovel !== null
                    icon: "info"
                    text: "Info"
                    lit: infoPanel.shown
                    onClicked: infoPanel.toggle()
                }

                // AniList (novels only): log in, match the novel to its AniList entry, or where it
                // is on your list (opens the track sheet). Not lit: it is a state to read, and the
                // one lit thing here is whatever is open.
                ReaderChip {
                    visible: Novel.currentNovel !== null && Novel.alMatching === false
                             && (!Novel.alLoggedIn || Novel.alMatchKnown)
                    icon: !Novel.alLoggedIn ? "link"
                        : (Novel.trackable ? (Novel.trackEntry ? "check_read" : "add") : "magnifer")
                    text: !Novel.alLoggedIn ? "AniList"
                        : (Novel.trackable
                            ? (Novel.trackEntry
                                ? "AniList \u00b7 " + Novel.trackStatusLabel(Novel.trackEntry.status) + " " + Novel.trackEntry.progress
                                : "Track")
                            : "Match AniList")
                    onClicked: {
                        if (!Novel.alLoggedIn) detailView.loginRequested()
                        else if (Novel.trackable) trackSheet.open()
                        else matchPicker.open()
                    }
                }

                // The chapter you opened last (not the newest one: that is the top of the list)
                ReaderBadge {
                    readonly property var _entry: Novel.currentNovel
                        ? Novel.getLibraryEntry(Novel.currentNovel.id) : null
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastReadChapterNum !== "" && _entry.lastReadChapterNum !== undefined
                    tonal: true
                    text: {
                        var e = Novel.currentNovel ? Novel.getLibraryEntry(Novel.currentNovel.id) : null
                        return e ? ("LAST READ \u00b7 CH. " + detailView.formatChapter(e.lastReadChapterNum)).toUpperCase() : ""
                    }
                }
            }
        }

        // ── Search, sort and the chapters. The Info sheet slides down into just this part and
        //    pushes the list down ahead of it, so the cover and the strip above stay in view ───
        Item {
            id: lowerArea
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Glued to the Info sheet's lower edge: it is carried down as the sheet comes in
                // (scroll position and selection are untouched) and back up as it goes.
                transform: Translate { y: infoPanel.progress * lowerArea.height }

                // ── Search & Sort bar ─────────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    visible: Novel.currentNovel !== null

                    RowLayout {
                        anchors { fill: parent; leftMargin: ReaderType.gutter; rightMargin: ReaderType.gutter }
                        spacing: 12

                        SearchPill {
                            id: chapterSearch
                            Layout.fillWidth: true
                            Layout.preferredHeight: ReaderType.hField
                            placeholder: "Filter chapters…"
                            onTextChanged: detailView._chapterFilter = text
                        }

                        ReaderKey {
                            id: moreKey
                            Layout.preferredHeight: ReaderType.hField
                            icon: "menu_dots"
                            lit: detailView._menuOpen
                            onClicked: {
                                detailView._menuPos = moreKey.mapToItem(detailView, moreKey.width, moreKey.height + 6)
                                detailView._menuOpen = !detailView._menuOpen
                            }
                        }

                        // Not lit: the order is a setting, not a selection (pink is for what is chosen)
                        ReaderKey {
                            Layout.preferredHeight: ReaderType.hField
                            icon: detailView._sortAscending ? "arrow_upward" : "arrow_downward"
                            onClicked: detailView._sortAscending = !detailView._sortAscending
                        }
                    }
                }

                Divider { Layout.fillWidth: true; visible: Novel.currentNovel !== null }

                // ── Chapter list ──────────────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true

                    Rectangle { anchors.fill: parent; color: Colors.background }

                    // Loading overlay
                    SkeletonList {
                        anchors.fill: parent; z: 5
                        active: Novel.isFetchingDetail
                        rowHeight: ReaderType.hRow
                    }

                    // Error state (the backend or the site refused the novel)
                    Rectangle {
                        anchors.fill: parent; z: 4
                        color: Colors.background
                        visible: Novel.detailError.length > 0 && !Novel.isFetchingDetail

                        Column {
                            anchors.centerIn: parent; spacing: 12

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "⚠"; font.pixelSize: 30; color: Colors.error; opacity: 0.8
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 280; horizontalAlignment: Text.AlignHCenter
                                text: "Couldn't load this novel\n" + Novel.detailError
                                color: Colors.on_surface_variant
                                font.family: detailView.fontBody; font.pixelSize: 12
                                wrapMode: Text.Wrap; lineHeight: 1.4
                            }
                            ReaderChip {
                                anchors.horizontalCenter: parent.horizontalCenter
                                icon: "refresh"
                                text: "Retry"
                                lit: true
                                onClicked: Novel.retryDetail()
                            }
                        }
                    }

                    ListView {
                        id: chapterList
                        anchors.fill: parent; clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: detailView._selecting ? 70 : (continueKey.wanted ? 64 : 0)
                        Behavior on bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        model: detailView._processedChapters   // ← filtered + sorted

                        ScrollBar.vertical: StyledScrollBar {
                        }

                        delegate: Rectangle {
                            id: chapterRow
                            width: chapterList.width; height: ReaderType.hRow

                            readonly property var _libEntry: Novel.currentNovel
                                ? Novel.getLibraryEntry(Novel.currentNovel.id) : null
                            readonly property bool isLastRead:
                                _libEntry !== null && _libEntry !== undefined
                                && _libEntry.lastReadChapterId === modelData.id
                            readonly property bool isRead: Novel.isChapterRead(modelData.id)
                            // When the source says this chapter came out (its own words when the date is
                            // too loose to be one): the same line the manga reader shows
                            readonly property string _dateText: detailView.releaseText(modelData)
                            // The stamp already says CH.47, so a title that only repeats it ("Chapter
                            // 47") is not written out: the row is the stamp and the date, and a chapter
                            // with a real name gets the name above the date.
                            readonly property bool _hasTitle: !NM.titleIsPlain(modelData.title)
                            readonly property bool isSelected: detailView._selected[modelData.id] === true
                            property bool _held: false

                            color: isSelected
                                ? Qt.tint(Colors.background, Colors.withAlpha(Theme.accentCyan, 0.30))
                                : isLastRead
                                    ? Qt.tint(Colors.background, Colors.withAlpha(Theme.accentMint, 0.28))
                                    : (rowArea.containsPress ? Theme.surfaceTint
                                        : (rowArea.containsMouse ? Colors.withAlpha(Theme.surface, 0.8) : "transparent"))
                            Behavior on color { ColorAnimation { duration: 110 } }

                            Rectangle {
                                anchors {
                                    bottom: parent.bottom
                                    left: parent.left; right: parent.right
                                    leftMargin: 92; rightMargin: 16
                                }
                                height: 1; color: Colors.outline_variant; opacity: 0.25
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                spacing: 14

                                // Chapter stamp ("VOL.2" for a row that is a whole volume)
                                // One width for every number, and an ink that can be read on the dark fill.
                                ReaderBadge {
                                    id: chapterBadge
                                    Layout.preferredWidth: Math.max(62, chapterBadge.implicitWidth)
                                    Layout.preferredHeight: 24
                                    rotation: 0
                                    text: NM.chapterTag(modelData)
                                    fill: isLastRead ? Theme.accentMint : Theme.surfaceHover
                                    ink: isLastRead ? Theme.colBorder : Theme.ink
                                    opacity: chapterRow.isRead && !chapterRow.isSelected ? 0.5 : 1
                                }

                                Column {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2
                                    // A chapter already read is dimmed, like in Mihon
                                    opacity: chapterRow.isRead && !chapterRow.isSelected ? 0.5 : 1
                                    Behavior on opacity { NumberAnimation { duration: 140 } }

                                    Text {
                                        width: parent.width
                                        text: chapterRow._hasTitle ? modelData.title
                                            : (chapterRow._dateText.length > 0 ? chapterRow._dateText
                                               : ((modelData.kind === "volume" ? "Volume " : "Chapter ") + detailView.formatChapter(modelData.chapter)))
                                        font.family: detailView.fontBody
                                        font.pixelSize: ReaderType.sizeBody
                                        color: Colors.on_surface; elide: Text.ElideRight
                                        font.weight: chapterRow._hasTitle ? ReaderType.weightTitle : ReaderType.weightBody
                                        font.styleName: chapterRow._hasTitle ? ReaderType.styleTitle : ReaderType.styleBody
                                    }
                                    Text {
                                        visible: chapterRow._hasTitle && chapterRow._dateText.length > 0
                                        width: parent.width
                                        text: chapterRow._dateText
                                        elide: Text.ElideRight
                                        font.family: detailView.fontBody
                                        font.pixelSize: ReaderType.sizeCaption
                                        font.weight: ReaderType.weightBody; font.styleName: ReaderType.styleBody
                                        color: Theme.inkSub
                                    }
                                }

                                // Right edge: the tick box while selecting, a check for a chapter that
                                // is read, else the chevron
                                Item {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: detailView._selecting
                                        name: chapterRow.isSelected ? "check_box" : "check_box_outline_blank"
                                        fill: chapterRow.isSelected ? 1 : 0
                                        size: 20
                                        color: chapterRow.isSelected ? Theme.accentCyan : Theme.inkSub
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: !detailView._selecting && chapterRow.isRead
                                        name: "check_read"
                                        size: 18
                                        color: Theme.accentMint
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !detailView._selecting && !chapterRow.isRead
                                        text: "\u203a"; font.pixelSize: 20; color: Theme.inkSub
                                        opacity: rowArea.containsMouse ? 1 : 0.7
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                    }
                                }
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor

                                onPressed: chapterRow._held = false
                                onPressAndHold: { chapterRow._held = true; detailView.pick(modelData.id) }
                                onClicked: mouse => {
                                    if (chapterRow._held) { chapterRow._held = false; return }
                                    if (mouse.button === Qt.RightButton) { detailView.pick(modelData.id); return }
                                    if (detailView._selecting) { detailView.toggleSelect(modelData.id); return }

                                    detailView.openChapter(modelData)
                                }
                            }
                        }
                    }

                    // ── Continue: bottom right, opens the chapter where the reader left off ──
                    Item {
                        id: continueKey
                        z: 15

                        readonly property bool wanted: detailView._continueTarget !== null
                            && !Novel.isFetchingDetail && !detailView._selecting
                        // keeps the last words while it slides away, so the text doesn't blank mid-exit
                        property var _last: null
                        function _keep() { _last = detailView._continueTarget }
                        onWantedChanged: if (wanted) _keep()
                        Connections {
                            target: detailView
                            function on_ContinueTargetChanged() { if (continueKey.wanted) continueKey._keep() }
                        }
                        Component.onCompleted: _keep()

                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 16; bottomMargin: 16 }
                        width: key.implicitWidth
                        height: key.implicitHeight + Theme.shadowOffset
                        opacity: wanted ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        transform: Translate {
                            y: continueKey.wanted ? 0 : 18
                            Behavior on y {
                                NumberAnimation {
                                    duration: continueKey.wanted ? 320 : 170
                                    easing.type: continueKey.wanted ? Easing.OutBack : Easing.InCubic
                                    easing.overshoot: 1.2
                                }
                            }
                        }

                        ReaderChip {
                            id: key
                            lit: true
                            icon: "play_arrow"
                            text: continueKey._last
                                ? (continueKey._last.started ? "Continue" : "Start")
                                  + " \u00b7 " + NM.chapterTag(continueKey._last.chapter)
                                : ""
                            onClicked: {
                                if (continueKey._last) detailView.openChapter(continueKey._last.chapter)
                            }
                        }
                    }

                    // ── Selection bar: slides up from the bottom while chapters are selected ──
                    ReaderBar {
                        id: selectBar
                        atBottom: true
                        shown: detailView._selecting
                        z: 20
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 7; rightMargin: 10; bottomMargin: Theme.shadowOffset }
                            spacing: 6

                            ReaderKey {
                                icon: "close"
                                onClicked: detailView.endSelect()
                            }

                            Text {
                                Layout.leftMargin: 2
                                text: detailView._selectedCount + " selected"
                                font.family: detailView.fontBody; font.pixelSize: 12
                                font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                                color: Theme.ink
                            }

                            Item { Layout.fillWidth: true }

                            ReaderChip {
                                icon: "checklist_minimalistic"
                                text: "All"
                                onClicked: detailView.selectAll()
                            }

                            ReaderChip {
                                visible: detailView._selectedCount === 1
                                icon: "check_read"
                                text: "Up to here"
                                onClicked: detailView.markUpToHere()
                            }

                            ReaderChip {
                                enabled: detailView._selectedCount > 0
                                icon: "check_read"
                                text: "Read"
                                lit: true
                                onClicked: detailView.markSelected(true)
                            }

                            ReaderChip {
                                enabled: detailView._selectedCount > 0
                                icon: "eye_closed"
                                text: "Unread"
                                onClicked: detailView.markSelected(false)
                            }
                        }
                    }
                }
            }

            InfoPanel {
                id: infoPanel
                anchors.fill: parent
                z: 20
                onTrackRequested: trackSheet.open()
            }
        }
    }

    // ── Whole-novel menu (the ... key) ────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 40
        enabled: detailView._menuOpen
        acceptedButtons: Qt.AllButtons
        onPressed: detailView._menuOpen = false
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: moreMenu
        z: 41
        width: 214
        height: moreCol.implicitHeight + 20 + Theme.shadowOffset
        x: Math.max(8, Math.min(detailView.width - width - 8, detailView._menuPos.x - width))
        y: detailView._menuPos.y
        opacity: detailView._menuOpen ? 1 : 0
        visible: opacity > 0.01
        scale: detailView._menuOpen ? 1 : 0.94
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

        Pill {
            anchors.fill: parent
            cornerRadius: 18
            ringWidth: Theme.borderWidth
            innerRing: Theme.cardRing
            fillColor: Theme.surface

            Column {
                id: moreCol
                x: 10
                y: 10
                width: parent.width - 20
                spacing: 2

                ReaderMenuRow {
                    width: moreCol.width
                    icon: "checklist_minimalistic"
                    text: "Select chapters"
                    enabled: Novel.currentNovel !== null && Novel.currentNovel.chapters.length > 0
                    onClicked: {
                        detailView._menuOpen = false
                        detailView._selecting = true
                    }
                }

                ReaderMenuRow {
                    width: moreCol.width
                    icon: "check_read"
                    text: "Mark all as read"
                    enabled: Novel.currentNovel !== null
                        && detailView._readTotal < Novel.currentNovel.chapters.length
                    onClicked: detailView.markAll(true)
                }

                ReaderMenuRow {
                    width: moreCol.width
                    icon: "eye_closed"
                    text: "Mark all as unread"
                    enabled: detailView._readTotal > 0
                    onClicked: detailView.markAll(false)
                }
            }
        }
    }

    TrackSheet {
        id: trackSheet
        anchors.fill: parent
        z: 50
        onMatchRequested: matchPicker.open()
    }

    MatchPicker {
        id: matchPicker
        anchors.fill: parent
        z: 50
    }
}
