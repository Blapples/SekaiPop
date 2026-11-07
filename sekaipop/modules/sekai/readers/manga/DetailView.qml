// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

Item {
    id: detailView

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal backRequested()
    signal chapterSelected(string chapterId)

    // ── Library state ─────────────────────────────────────────────────────────
    readonly property bool _inLibrary:
        Manga.currentManga ? Manga.isInLibrary(Manga.currentManga.id) : false

    // ── Where the chapters come from (titles opened from AniList) ─────────────
    readonly property bool _sourceBad: Manga.currentManga !== null
        && (Manga.currentManga.unmatched || Manga.currentManga.sourceError.length > 0)
    readonly property string _sourceText: {
        const m = Manga.currentManga
        if (!m) return ""
        if (m.unmatched) return "No " + Manga.providerLabel + " match found"
        if (m.sourceError.length > 0) return m.sourceError
        return m.match ? "Chapters from " + Manga.labelForId(m.match.id) + " · " + m.match.title : ""
    }

    // The short form under the chapter count: where the chapters come from, and the series' name
    // only when it is not the title already on this screen (a sequel, a different spelling).
    readonly property string _sourceCaption: {
        const m = Manga.currentManga
        if (!m) return ""
        if (m.unmatched) return "No " + Manga.providerLabel + " match found"
        if (m.sourceError.length > 0) return m.sourceError
        if (!m.match) return ""
        const norm = t => String(t || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
        const site = Manga.labelForId(m.match.id)
        return norm(m.match.title) === norm(m.title) ? "Chapters from " + site
                                                      : site + " · " + m.match.title
    }

    // ── Filter / sort state ───────────────────────────────────────────────────
    property bool   _sortAscending:  false
    property string _chapterFilter:  ""

    // ── Synopsis dropdown ─────────────────────────────────────────────────────
    // A long synopsis is three lines beside the cover with a More key; open, it drops down in full
    // under the cover (scrolling inside if it is longer than the window allows) and pushes the
    // chapters down with it. One number runs both the fold and the growth of the hero.
    property bool _descOpen: false
    property real _descProgress: _descOpen ? 1 : 0          // 0 folded .. 1 open
    Behavior on _descProgress {
        NumberAnimation {
            duration: 360
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]      // starts gently: no lurch on the first frames
        }
    }
    // the preview is cut off, so there is more to read
    readonly property bool _descLong: descPreview.truncated || _descOpen
    // how much taller the hero grows to show it all
    readonly property real _descExtra: Math.min(descFull.implicitHeight + 6, Math.max(90, detailView.height * 0.4))

    function reset() {
        chapterSearch.clear()
        _chapterFilter  = ""
        _sortAscending  = false
        _descOpen       = false
        endSelect()
        _menuOpen = false
    }

    // ── Read / unread (like Mihon) ────────────────────────────────────────────
    // A long press or a right click on a chapter starts selecting; a click then toggles
    // chapters; the bar at the bottom marks the selection read or unread, or everything up to
    // the one chosen. The ... key by the sort key does the whole series at once.
    property bool _selecting: false
    property var  _selected:  ({})          // chapterId -> true
    readonly property int _selectedCount: Object.keys(detailView._selected).length
    property bool  _menuOpen: false
    property point _menuPos: Qt.point(0, 0)

    readonly property string _seriesId: Manga.currentManga ? String(Manga.currentManga.id) : ""
    on_SeriesIdChanged: { endSelect(); _menuOpen = false; _descOpen = false; infoPanel.reset() }
    onVisibleChanged: { if (!visible) { endSelect(); _menuOpen = false; trackSheet.visible = false; infoPanel.reset() } }

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
        Manga.setChaptersRead(Object.keys(_selected), read)
        endSelect()
    }

    // Everything from the first chapter up to the one selected, itself included
    function markUpToHere() {
        const ids = Object.keys(_selected)
        if (ids.length !== 1 || !Manga.currentManga) return
        const ordered = RM.orderChapters(Manga.currentManga.chapters)
        const out = []
        for (let i = 0; i < ordered.length; i++) {
            out.push(ordered[i].id)
            if (ordered[i].id === ids[0]) { Manga.setChaptersRead(out, true); break }
        }
        endSelect()
    }

    function markAll(read) {
        if (!Manga.currentManga) return
        Manga.setChaptersRead(Manga.currentManga.chapters.map(ch => ch.id), read)
        _menuOpen = false
    }

    readonly property int _readTotal: Manga.currentManga ? Manga.readCount(Manga.currentManga.chapters) : 0

    // ── Continue reading ──────────────────────────────────────────────────────
    // Opens a chapter the way a tap on its row does.
    function openChapter(ch) {
        Manga.fetchChapterPages(ch.id)
        detailView.chapterSelected(ch.id)
        if (Manga.currentManga && Manga.isInLibrary(Manga.currentManga.id))
            Manga.updateLastRead(Manga.currentManga.id, ch.id, ch.chapter)
    }

    // The page Continue will open on (1-based), 0 when it opens on the first page
    readonly property int _continuePage: {
        const t = detailView._continueTarget
        return t && t.started ? Manga.savedPage(t.chapter.id) : 0
    }

    // Where the reader left off, or null when there is nowhere to continue (nothing loaded, or
    // everything is read). A chapter opened last and not finished is resumed; otherwise it is the
    // first unread chapter after the furthest one read; a title not started begins at chapter one.
    // Works on the reading order, whatever the list is sorted by or filtered to.
    readonly property var _continueTarget: {
        const m = Manga.currentManga
        if (!m || !m.chapters || m.chapters.length === 0) return null
        const ordered = RM.orderChapters(m.chapters)

        const entry = Manga.getLibraryEntry(m.id)
        if (entry && entry.lastReadChapterId) {
            for (let i = 0; i < ordered.length; i++) {
                if (ordered[i].id === entry.lastReadChapterId)
                    if (!Manga.isChapterRead(ordered[i].id)) return { chapter: ordered[i], started: true }
            }
        }

        let furthest = -1
        for (let i = 0; i < ordered.length; i++)
            if (Manga.isChapterRead(ordered[i].id)) furthest = i
        // a chapter begun and left (a title that is not in the Library keeps no "last opened"):
        // the furthest one, if it is beyond everything read
        for (let i = ordered.length - 1; i > furthest; i--)
            if (Manga.savedPage(ordered[i].id) > 0 && !Manga.isChapterRead(ordered[i].id))
                return { chapter: ordered[i], started: true }

        if (furthest < 0) return { chapter: ordered[0], started: false }

        for (let i = furthest + 1; i < ordered.length; i++)
            if (!Manga.isChapterRead(ordered[i].id)) return { chapter: ordered[i], started: true }
        return null
    }

    // A "Jump back in" card on the AniList page opened this title to carry straight on: once its
    // chapters are here and there is somewhere to continue, open it like a tap on Continue (on the
    // saved page). Only the page on screen acts, and the request is used up when it does.
    readonly property bool _autoContinueReady: detailView.visible && Manga.autoContinueId.length > 0
        && Manga.currentManga !== null && Manga.currentManga.id === Manga.autoContinueId
        && !Manga.isFetchingDetail && detailView._continueTarget !== null
    on_AutoContinueReadyChanged: {
        if (!detailView._autoContinueReady) return
        const t = detailView._continueTarget
        Manga.autoContinueId = ""
        Manga.resumeChapterId = t.chapter.id
        detailView.openChapter(t.chapter)
    }

    // ── Helper ────────────────────────────────────────────────────────────────
    function formatChapter(ch) {
        if (!ch) return "?"
        const match = ch.match(/\d+(\.\d+)?/)
        return match ? match[0] : ch
    }

    // "CH.12" for a chapter, "VOL.3" for a volume (some series are listed by volume)
    function chapterTag(ch) {
        return (ch.kind === "volume" ? "VOL." : "CH.") + formatChapter(ch.chapter)
    }

    // ── Processed (filtered + sorted) chapter list ────────────────────────────
    readonly property var _processedChapters: {
        if (!Manga.currentManga) return []
        let chapters = Manga.currentManga.chapters.slice()

        if (detailView._chapterFilter.trim() !== "") {
            const f = detailView._chapterFilter.trim().toLowerCase()
            chapters = chapters.filter(ch => {
                const num   = detailView.formatChapter(ch.chapter).toLowerCase()
                const title = (ch.title || "").toLowerCase()
                return num.includes(f) || title.includes(f)
            })
        }

        // Volumes (or a mix of volumes and chapters) share numbers, so a numeric sort
        // would interleave them: follow the site's own order for those series.
        const byIndex = chapters.some(ch => ch.kind === "volume")
        chapters.sort((a, b) => {
            const numA = byIndex ? a.index : (parseFloat(detailView.formatChapter(a.chapter)) || 0)
            const numB = byIndex ? b.index : (parseFloat(detailView.formatChapter(b.chapter)) || 0)
            return detailView._sortAscending ? numA - numB : numB - numA
        })

        return chapters
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
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                ReaderKey {
                    icon: "arrow_back"
                    onClicked: {
                        if (detailView._selecting) { detailView.endSelect(); return }
                        Manga.clearChapterList()
                        detailView.backRequested()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Manga.currentManga ? Manga.currentManga.title : ""
                    font.family: detailView.fontDisplay
                    font.pixelSize: ReaderType.sizeTitle
                    font.weight: ReaderType.weightTitle
                    font.styleName: ReaderType.styleTitle
                    color: Theme.ink
                    elide: Text.ElideRight
                }

                ReaderChip {
                    visible: Manga.currentManga !== null && Manga.currentManga.id !== ""
                    icon: detailView._inLibrary ? "check" : "add"
                    text: "Library"
                    lit: detailView._inLibrary
                    onClicked: {
                            if (detailView._inLibrary)
                                Manga.removeFromLibrary(Manga.currentManga.id)
                            else
                                Manga.addToLibrary({
                                    id:       Manga.currentManga.id,
                                    title:    Manga.currentManga.title,
                                    coverUrl: Manga.currentManga.coverUrl
                                })
                        }
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Hero ──────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            // 172 once a title is there (eased in), plus whatever the synopsis dropdown has opened
            property real _base: Manga.currentManga !== null ? 172 : 0
            Behavior on _base { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Layout.preferredHeight: _base + detailView._descProgress * detailView._descExtra
            clip: true

            Rectangle { anchors.fill: parent; color: Colors.background }

            // The cover, washed out behind everything
            Image {
                anchors.fill: parent
                property bool useOriginal: false
                readonly property string raw: Manga.currentManga ? Manga.currentManga.coverUrl : ""
                source: useOriginal ? raw : RM.hiResCover(raw)
                onRawChanged: useOriginal = false
                onStatusChanged: if (status === Image.Error && !useOriginal) useOriginal = true
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; opacity: 0.16
                smooth: true
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.withAlpha(Colors.background, 0.35) }
                    GradientStop { position: 1.0; color: Colors.background }
                }
            }

            // The printed halftone of the shell's panels
            // Drawn once at the size the hero reaches when the synopsis is open, and clipped by the
            // hero while it is folded: a DotField is repainted by script whenever its size changes,
            // which done on every frame of the drop-down made it stutter.
            DotField {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 172 + (detailView._descLong ? detailView._descExtra : 0)
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
                id: heroRow
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                height: 140
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
                                property bool useOriginal: false
                                readonly property string raw: Manga.currentManga ? Manga.currentManga.coverUrl : ""
                                source: useOriginal ? raw : RM.hiResCover(raw)
                                onRawChanged: useOriginal = false
                                onStatusChanged: if (status === Image.Error && !useOriginal) useOriginal = true
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                sourceSize.width: 204     // twice the 102x146 frame
                                sourceSize.height: 292
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
                    id: infoCol
                    width: parent.width - 120
                    spacing: 7
                    // Nothing in this column changes size or place while the synopsis opens: the
                    // preview only fades and the More key is slid up by a transform, so there is no
                    // re-layout of the badges, author and genres to make them jump.
                    anchors.verticalCenter: parent.verticalCenter

                    // Status, AniList score, your score, year and tracked stamps
                    Flow {
                        width: parent.width
                        spacing: 6

                        ReaderBadge {
                            visible: Manga.currentManga && (Manga.currentManga.statusLabel || Manga.currentManga.status).length > 0
                            rotation: -3
                            text: Manga.currentManga ? (Manga.currentManga.statusLabel || Manga.currentManga.status || "").toUpperCase() : ""
                            tonal: true
                            outline: Theme.accentMint
                        }

                        ReaderBadge {
                            visible: Manga.currentManga && Manga.currentManga.score > 0
                            rotation: 2
                            text: Manga.currentManga ? "\u2605 " + (Manga.currentManga.score / 10).toFixed(1) : ""
                            fill: Theme.accentCyan
                        }

                        ReaderBadge {
                            visible: Manga.trackScoreText.length > 0
                            rotation: -2
                            text: "YOU \u2605 " + Manga.trackScoreText
                            tonal: true
                            outline: Theme.accentCyan
                        }

                        ReaderBadge {
                            visible: Manga.currentManga && Manga.currentManga.year > 0
                            rotation: -2
                            text: Manga.currentManga ? String(Manga.currentManga.year) : ""
                            tonal: true
                        }

                        ReaderBadge {
                            visible: Manga.trackEntry !== null
                            rotation: 3
                            text: "TRACKED"
                            tonal: true
                            outline: Theme.accentMint
                        }
                    }

                    // Author
                    StyledText {
                        width: parent.width
                        text: Manga.currentManga ? (Manga.currentManga.authors || []).join(", ") : ""
                        font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeBody
                        font.weight: ReaderType.weightTitle; font.styleName: ReaderType.styleTitle
                        color: Theme.ink; elide: Text.ElideRight
                    }

                    // Genres
                    StyledText {
                        visible: Manga.currentManga && Manga.currentManga.tags.length > 0
                        width: parent.width
                        text: Manga.currentManga ? Manga.currentManga.tags.slice(0, 5).join(" · ") : ""
                        font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeCaption
                        font.weight: ReaderType.weightBody; font.styleName: ReaderType.styleBody
                        color: Theme.inkSub; elide: Text.ElideRight
                    }

                    // Description: three lines; it folds away while the full one is open below
                    Item {
                        width: parent.width
                        height: descPreview.implicitHeight
                        opacity: Math.max(0, 1 - detailView._descProgress * 2)      // gone by half-way

                        StyledText {
                            id: descPreview
                            width: parent.width
                            text: Manga.currentManga ? Manga.currentManga.description : ""
                            font.family: detailView.fontBody; font.pixelSize: 11
                            color: Theme.inkSub
                            wrapMode: Text.Wrap; maximumLineCount: 3
                            elide: Text.ElideRight; lineHeight: 1.3
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: detailView._descLong && !detailView._descOpen
                            cursorShape: Qt.PointingHandCursor
                            onClicked: detailView._descOpen = true
                        }
                    }

                    // More / Less: only when there is more than the three lines
                    Item {
                        visible: detailView._descLong
                        width: moreRow.implicitWidth
                        height: 16

                        // Rises into the space the preview leaves (drawn only, no layout)
                        transform: Translate {
                            y: -detailView._descProgress * (descPreview.implicitHeight + infoCol.spacing)
                        }

                        Row {
                            id: moreRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: detailView._descProgress > 0.5 ? "Less" : "More"
                                font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeCaption
                                font.weight: ReaderType.weightStrong; font.styleName: ReaderType.styleStrong
                                color: Theme.ink
                            }

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "expand_more"
                                size: 14
                                color: Theme.ink
                                rotation: detailView._descProgress * 180
                            }
                        }

                        MouseArea {
                            anchors { fill: parent; margins: -6 }
                            cursorShape: Qt.PointingHandCursor
                            onClicked: detailView._descOpen = !detailView._descOpen
                        }
                    }
                }
            }

            // The synopsis in full, dropped down under the cover and the text beside it
            Flickable {
                id: descFlick
                anchors { left: parent.left; right: parent.right; top: heroRow.bottom; margins: 16; topMargin: 4 }
                height: detailView._descProgress * detailView._descExtra - 4
                visible: detailView._descProgress > 0.001
                opacity: Math.max(0, Math.min(1, (detailView._descProgress - 0.25) / 0.6))
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: descFull.implicitHeight

                ScrollBar.vertical: StyledScrollBar {}

                StyledText {
                    id: descFull
                    width: descFlick.width
                    text: Manga.currentManga ? Manga.currentManga.description : ""
                    font.family: detailView.fontBody; font.pixelSize: 12
                    color: Theme.ink
                    wrapMode: Text.Wrap; lineHeight: 1.35
                }
            }
        }

        Divider { Layout.fillWidth: true; visible: Manga.currentManga !== null }

        // ── Chapter count, where they come from, and the title's keys ─────────
        // (the source line used to be a band of its own above this one)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            visible: Manga.currentManga !== null

            RowLayout {
                anchors { fill: parent; leftMargin: ReaderType.gutter; rightMargin: ReaderType.gutter }
                spacing: 8

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: !Manga.currentManga ? ""
                            : Manga.currentManga.chapters.length + " chapters"
                              + (detailView._readTotal > 0 ? " \u00b7 " + detailView._readTotal + " read" : "")
                        font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeBody
                        font.weight: ReaderType.weightTitle; font.styleName: ReaderType.styleTitle
                        color: Theme.ink
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 6
                        visible: detailView._sourceCaption.length > 0
                                 && Manga.currentManga !== null && Manga.currentManga.anilistId > 0

                        Text {
                            Layout.fillWidth: true
                            text: detailView._sourceCaption
                            font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeCaption
                            font.weight: ReaderType.weightBody; font.styleName: ReaderType.styleBody
                            color: detailView._sourceBad ? Colors.error : Theme.inkSub
                            elide: Text.ElideRight
                        }

                        // A matched series is changed from a plain text link; "Pick match" (nothing
                        // matched) is a lit chip further along, because it is what the page needs.
                        Text {
                            id: changeLink
                            visible: Manga.currentManga !== null && !Manga.currentManga.unmatched
                            text: "Change"
                            font.family: detailView.fontBody; font.pixelSize: ReaderType.sizeCaption
                            font.weight: ReaderType.weightStrong; font.styleName: ReaderType.styleStrong
                            color: Theme.ink
                            font.underline: changeArea.containsMouse
                            opacity: changeArea.containsMouse ? 1 : 0.8

                            MouseArea {
                                id: changeArea
                                anchors { fill: parent; margins: -6 }
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: matchPicker.open()
                            }
                        }
                    }
                }

                ReaderChip {
                    visible: Manga.currentManga !== null && Manga.currentManga.anilistId > 0
                             && Manga.currentManga.unmatched
                    text: "Pick match"
                    lit: true
                    onClicked: matchPicker.open()
                }

                // Everything known about the title (status, translation, ratings, names, tags)
                ReaderChip {
                    visible: Manga.currentManga !== null
                    icon: "info"
                    text: "Info"
                    lit: infoPanel.shown
                    onClicked: infoPanel.toggle()
                }

                // AniList: where this title is on your list; opens the track sheet. Not lit: it is
                // a state to read, and the one lit thing here is whatever is open.
                ReaderChip {
                    visible: Manga.trackable
                    icon: Manga.trackInfo && Manga.trackInfo.entry ? "check_read" : "add"
                    text: Manga.trackInfo && Manga.trackInfo.entry
                        ? "AniList \u00b7 " + Manga.trackStatusLabel(Manga.trackInfo.entry.status)
                          + " " + Manga.trackInfo.entry.progress
                        : "Track"
                    onClicked: trackSheet.open()
                }

                // The chapter you opened last (not the newest one: that is the top of the list)
                ReaderBadge {
                    readonly property var _entry: Manga.currentManga
                        ? Manga.getLibraryEntry(Manga.currentManga.id) : null
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastReadChapterNum !== "" && _entry.lastReadChapterNum !== undefined
                    tonal: true
                    text: {
                        var e = Manga.currentManga ? Manga.getLibraryEntry(Manga.currentManga.id) : null
                        return e ? ("LAST READ \u00b7 CH. " + detailView.formatChapter(e.lastReadChapterNum)).toUpperCase() : ""
                    }
                }
            }
        }

        // ── Search, sort and the chapters. The Info panel slides down into just this part and
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
                    visible: Manga.currentManga !== null

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

                Divider { Layout.fillWidth: true; visible: Manga.currentManga !== null }

                // ── Chapter list ──────────────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Rectangle { anchors.fill: parent; color: Colors.background }

                    // Loading overlay
                    SkeletonList {
                        anchors.fill: parent; z: 5
                        active: Manga.isFetchingDetail
                        rowHeight: ReaderType.hRow
                    }

                    EmptyState {
                        z: 4
                        visible: Manga.currentManga !== null && !Manga.isFetchingDetail
                                 && Manga.currentManga.unmatched
                        title: "No chapters yet"
                        subtitle: "Pick the " + Manga.providerLabel + " series this title is"
                        displayFont: detailView.fontDisplay
                        bodyFont: detailView.fontBody
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

                            readonly property var _libEntry: Manga.currentManga
                                ? Manga.getLibraryEntry(Manga.currentManga.id) : null
                            readonly property bool isLastRead:
                                _libEntry !== null && _libEntry !== undefined
                                && _libEntry.lastReadChapterId === modelData.id
                            readonly property bool isRead: Manga.isChapterRead(modelData.id)
                            // The stamp already says CH.47, so a title that only repeats it ("Chapter
                            // 47") is not written out: the row is the stamp and the date, and a
                            // chapter with a real name gets the name above the date.
                            readonly property string _dateText: modelData.publishAt
                                ? Qt.formatDate(new Date(modelData.publishAt), "MMM d, yyyy") : ""
                            readonly property bool _hasTitle: {
                                const t = String(modelData.title || "").trim()
                                return t.length > 0 && !/^(chapter|chap\.?|ch\.?|volume|vol\.?)\s*[\d.]+$/i.test(t)
                            }
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

                                // Chapter stamp
                                // One width for every number (CH.9 and CH.47 used to differ by a few
                                // pixels, and the titles after them with it), and an ink that can be
                                // read on the dark fill (the outline's navy was invisible on it).
                                ReaderBadge {
                                    id: chapterBadge
                                    Layout.preferredWidth: Math.max(62, chapterBadge.implicitWidth)
                                    Layout.preferredHeight: 24
                                    rotation: 0
                                    text: detailView.chapterTag(modelData)
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
                            && !Manga.isFetchingDetail && !detailView._selecting
                        // keeps the last words while it slides away, so the text doesn't blank mid-exit
                        property var _last: null
                        property int _lastPage: 0
                        function _keep() {
                            _last = detailView._continueTarget
                            _lastPage = detailView._continuePage
                        }
                        onWantedChanged: if (wanted) _keep()
                        Connections {
                            target: detailView
                            function on_ContinueTargetChanged() { if (continueKey.wanted) continueKey._keep() }
                            function on_ContinuePageChanged() { if (continueKey.wanted) continueKey._keep() }
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
                                  + " \u00b7 " + detailView.chapterTag(continueKey._last.chapter)
                                  + (continueKey._lastPage > 0 ? " \u00b7 p." + (continueKey._lastPage + 1) : "")
                                : ""
                            onClicked: {
                                if (!continueKey._last) return
                                // opens on the page it was left on
                                Manga.resumeChapterId = continueKey._last.chapter.id
                                detailView.openChapter(continueKey._last.chapter)
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

    // ── Whole-series menu (the ... key) ───────────────────────────────────────
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
                    onClicked: {
                        detailView._menuOpen = false
                        detailView._selecting = true
                    }
                }

                ReaderMenuRow {
                    width: moreCol.width
                    icon: "check_read"
                    text: "Mark all as read"
                    enabled: Manga.currentManga !== null
                        && detailView._readTotal < Manga.currentManga.chapters.length
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
    }


    MatchPicker {
        id: matchPicker
        anchors.fill: parent
        z: 50
        anilistId: Manga.currentManga ? Manga.currentManga.anilistId : 0
        hasManual: Manga.currentManga && Manga.currentManga.match ? Manga.currentManga.match.manual : false
    }
}
