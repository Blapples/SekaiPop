// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

Item {
    id: detailView

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal backRequested()
    signal chapterSelected(string chapterId)

    // ── Library state ─────────────────────────────────────────────────────────
    readonly property bool _inLibrary:
        Novel.currentNovel ? Novel.isInLibrary(Novel.currentNovel.id) : false

    // ── Filter / sort state ───────────────────────────────────────────────────
    property bool   _sortAscending: false
    property string _chapterFilter: ""

    function reset() {
        chapterSearch.clear()
        _chapterFilter = ""
        _sortAscending = false
    }

    // ── Helper ────────────────────────────────────────────────────────────────
    function formatChapter(ch) {
        if (!ch) return "?"
        const match = String(ch).match(/\d+(\.\d+)?/)
        return match ? match[0] : String(ch)
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

        chapters.sort((a, b) => {
            const numA = parseFloat(detailView.formatChapter(a.chapter)) || 0
            const numB = parseFloat(detailView.formatChapter(b.chapter)) || 0
            return detailView._sortAscending ? numA - numB : numB - numA
        })

        return chapters
    }

    // ── Reading helpers (preserved from original) ─────────────────────────────
    function continueReading() {
        if (!Novel.currentNovel) return

        var entry = Novel.getLibraryEntry(Novel.currentNovel.id)
        var lastChapterId = entry ? entry.lastReadChapterId : null
        var targetChapter = null

        if (lastChapterId) {
            for (var i = 0; i < Novel.currentNovel.chapters.length; i++) {
                if (Novel.currentNovel.chapters[i].id === lastChapterId) {
                    targetChapter = Novel.currentNovel.chapters[i]
                    break
                }
            }
        }

        if (!targetChapter && Novel.currentNovel.chapters.length > 0)
            targetChapter = Novel.currentNovel.chapters[0]

        if (targetChapter) {
            Novel.fetchChapter(targetChapter.id)
            detailView.chapterSelected(targetChapter.id)
            if (detailView._inLibrary)
                Novel.updateLastRead(Novel.currentNovel.id, targetChapter.id, targetChapter.chapter)
        }
    }

    function readNext() {
        if (!Novel.currentNovel) return

        var entry = Novel.getLibraryEntry(Novel.currentNovel.id)
        var lastChapterId = entry ? entry.lastReadChapterId : null
        var targetChapter = null

        if (lastChapterId) {
            for (var i = 0; i < Novel.currentNovel.chapters.length - 1; i++) {
                if (Novel.currentNovel.chapters[i].id === lastChapterId) {
                    targetChapter = Novel.currentNovel.chapters[i + 1]
                    break
                }
            }
        }

        if (!targetChapter && Novel.currentNovel.chapters.length > 0)
            targetChapter = Novel.currentNovel.chapters[0]

        if (targetChapter) {
            Novel.fetchChapter(targetChapter.id)
            detailView.chapterSelected(targetChapter.id)
            if (detailView._inLibrary)
                Novel.updateLastRead(Novel.currentNovel.id, targetChapter.id, targetChapter.chapter)
        }
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
                    onClicked: { Novel.clearDetail(); detailView.backRequested() }
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

                    // Status stamp
                    ReaderBadge {
                        visible: Novel.currentNovel && Novel.currentNovel.status.length > 0
                        rotation: -3
                        text: Novel.currentNovel ? (Novel.currentNovel.status || "").toUpperCase() : ""
                        fill: Theme.accentMint
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

        // ── Chapter count + last-read strip ───────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            visible: Novel.currentNovel !== null

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 8

                Text {
                    text: Novel.currentNovel ? Novel.currentNovel.chapters.length + " chapters" : ""
                    font.family: detailView.fontBody; font.pixelSize: 12
                    font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                    color: Theme.inkSub
                }

                // The site stopped answering partway through the list
                Text {
                    visible: Novel.currentNovel !== null && Novel.currentNovel.partial
                    text: "· list incomplete — tap to load the rest"
                    font.family: detailView.fontBody; font.pixelSize: 10
                    font.weight: Font.ExtraBold; font.styleName: Theme.fontStyleBold
                    color: Theme.inkSub
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Novel.retryDetail()
                    }
                }

                Item { Layout.fillWidth: true }

                // Last-read stamp
                ReaderBadge {
                    readonly property var _entry: Novel.currentNovel
                        ? Novel.getLibraryEntry(Novel.currentNovel.id) : null
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastReadChapterNum !== "" && _entry.lastReadChapterNum !== undefined
                    fill: Theme.accentCyan
                    text: {
                        var e = Novel.currentNovel ? Novel.getLibraryEntry(Novel.currentNovel.id) : null
                        return e ? ("LAST · CH. " + e.lastReadChapterNum).toUpperCase() : ""
                    }
                }
            }
        }

        // ── Continue / Next Chapter buttons ───────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            visible: Novel.currentNovel !== null

            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: -1 }
                spacing: 10

                ReaderChip {
                    icon: "play_arrow"
                    text: "Continue"
                    lit: true
                    onClicked: detailView.continueReading()
                }

                ReaderChip {
                    icon: "skip_next"
                    text: "Next Chapter"
                    onClicked: detailView.readNext()
                }
            }
        }

        // ── Search & Sort bar ─────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            visible: Novel.currentNovel !== null

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 18 }
                spacing: 12

                SearchPill {
                    id: chapterSearch
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    placeholder: "Filter chapters…"
                    onTextChanged: detailView._chapterFilter = text
                }

                ReaderKey {
                    lit: true
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
                rowHeight: 62
                subtitle: false
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
                model: detailView._processedChapters   // ← filtered + sorted

                ScrollBar.vertical: StyledScrollBar {
                }

                delegate: ClickableRect {
                    id: rowAreaRect
                    width: chapterList.width; height: 62

                    readonly property var _libEntry: Novel.currentNovel
                        ? Novel.getLibraryEntry(Novel.currentNovel.id) : null
                    readonly property bool isLastRead:
                        _libEntry !== null && _libEntry !== undefined
                        && _libEntry.lastReadChapterId === modelData.id

                    color: isLastRead
                        ? Qt.tint(Colors.background, Colors.withAlpha(Theme.accentMint, 0.28))
                        : (rowAreaRect.pressed ? Theme.surfaceTint
                            : (rowAreaRect.hovered ? Colors.withAlpha(Theme.surface, 0.8) : "transparent"))
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 72; rightMargin: 16 }
                        height: 1; color: Colors.outline_variant; opacity: 0.25
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 14

                        // Chapter stamp
                        ReaderBadge {
                            rotation: 0
                            implicitHeight: 24
                            text: "CH." + detailView.formatChapter(modelData.chapter)
                            fill: isLastRead ? Theme.accentMint : Theme.surfaceHover
                        }

                        Column {
                            Layout.fillWidth: true; spacing: 3

                            StyledText {
                                width: parent.width
                                text: modelData.title || ("Chapter " + detailView.formatChapter(modelData.chapter))
                                font.family: detailView.fontBody; font.pixelSize: 12
                                color: Colors.on_surface; elide: Text.ElideRight
                            }

                            StyledText {
                                visible: false
                                font.family: detailView.fontBody; font.pixelSize: 10
                                color: Colors.on_surface_variant; opacity: 0.5; font.letterSpacing: 0.3
                            }
                        }

                        Text {
                            text: "›"; font.pixelSize: 20; color: Colors.outline
                            opacity: rowAreaRect.hovered ? 0.9 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }

                    onClicked: {
                            Novel.fetchChapter(modelData.id)
                            detailView.chapterSelected(modelData.id)
                            if (Novel.currentNovel && Novel.isInLibrary(Novel.currentNovel.id))
                                Novel.updateLastRead(Novel.currentNovel.id, modelData.id, modelData.chapter)
                        }
                }
            }
        }
    }
}
