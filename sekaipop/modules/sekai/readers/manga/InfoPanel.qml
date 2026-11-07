import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// Everything known about the open title, in a sheet that slides down into the chapter area (the
// cover and the strip above it stay where they are): whether it is ongoing or complete, when it
// came out, the translation, the ratings (everyone's and yours), whether it is on your AniList
// list, the other names, every genre and tag. It reads Manga.currentManga (what AniList says) and
// Manga.trackInfo (your list entry). The panel fills the Item it sits in (which should clip); the
// sheet rides down from the top and the chapter list is pushed down ahead of it, so nothing is
// covered, it just moves. `progress` (0 shut .. 1 open) is what the parent reads to move the list.
//
//   InfoPanel { id: panel; anchors.fill: parent }
//   panel.toggle()   panel.open()   panel.close()   panel.shown   panel.progress
Item {
    id: root

    signal closed()
    signal trackRequested()

    property bool showSpoilers: false

    readonly property var m: Manga.currentManga
    readonly property var tr: m ? m.translation : null
    readonly property var entry: Manga.trackEntry
    readonly property bool _aniList: m !== null && m.anilistId > 0

    readonly property var _visibleTags: {
        if (!m || !m.tagList) return []
        return m.tagList.filter(t => root.showSpoilers || !t.spoiler)
    }
    readonly property int _spoilerCount: m && m.tagList ? m.tagList.filter(t => t.spoiler).length : 0

    // ── The words of each row ─────────────────────────────────────────────────
    readonly property string _statusText: {
        if (!m) return ""
        const s = m.statusLabel || m.status || ""
        // a finished series says how big it ended up; an ongoing one gets a Size row instead
        const size = RM.sizeText(m.chaptersTotal, m.volumesTotal)
        return s === "Completed" && size !== "" ? s + " \u00b7 " + size : s
    }

    readonly property string _releasedText: {
        if (!m) return ""
        if (m.startDate === "" && m.year > 0) return String(m.year)
        const done = m.statusLabel === "Completed" || m.statusLabel === "Cancelled"
        let t = m.startDate
        if (t !== "" && done && m.endDate !== "" && m.endDate !== m.startDate) t += "  \u2192  " + m.endDate
        else if (t !== "" && m.statusLabel === "Ongoing")                         t += "  \u2192  now"
        return t
    }

    readonly property string _translationText: {
        if (!tr) return ""
        return tr.label
    }

    readonly property string _readingText: {
        if (!m || !m.match) return ""
        return "English, from " + Manga.labelForId(m.match.id)
    }

    readonly property string _ratingText: {
        if (!m) return ""
        const a = RM.communityScoreText(m.score)
        return a === "" ? "" : a + " / 10"
    }

    readonly property string _crowdText: {
        if (!m) return ""
        const out = []
        const p = RM.shortCount(m.popularity)
        const f = RM.shortCount(m.favourites)
        if (p !== "") out.push(p + " readers")
        if (f !== "") out.push(f + " favourites")
        return out.join(" \u00b7 ")
    }

    readonly property string _trackText: {
        if (!Manga.alLoggedIn) return "Log in to AniList (the account key in the panel header) to track"
        if (!_aniList)         return "Not an AniList title, so it can't be tracked"
        if (!Manga.trackKnown) return "Checking your list\u2026"
        if (!entry)            return "Not tracked \u00b7 not on your AniList yet"
        const total = Manga.trackInfo.chapters || 0
        return "Tracked \u00b7 " + Manga.trackStatusLabel(entry.status)
            + " \u00b7 ch. " + entry.progress + (total > 0 ? " of " + total : "")
    }

    property bool shown: false

    // 0 = shut, 1 = open. Everything that moves (the sheet, the chapter list, the content
    // fade) is worked out from this one number, so they can never drift apart.
    property real progress: 0
    readonly property real _p: Math.max(0, Math.min(1, progress))

    // Nothing is drawn (or clicked) once the sheet is shut
    visible: progress > 0.001
    clip: true

    // Opening is a long ease-out (fast off the mark, then a soft landing); closing is a shorter
    // ease in and out. Both start from wherever the sheet is, so pressing the key again in the
    // middle of a slide turns it round instead of jumping.
    NumberAnimation {
        id: openAnim
        target: root; property: "progress"; to: 1
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
    }
    NumberAnimation {
        id: closeAnim
        target: root; property: "progress"; to: 0
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
    }

    function open() {
        showSpoilers = false
        flick.contentY = 0
        shown = true
        closeAnim.stop()
        openAnim.duration = Math.round(560 * Math.max(0.35, 1 - progress))
        openAnim.start()
        if (Manga.trackable) Manga.trackFetch()
    }

    function close() {
        shown = false
        openAnim.stop()
        closeAnim.duration = Math.round(320 * Math.max(0.4, progress))
        closeAnim.start()
        root.closed()
    }

    function toggle() { if (shown) close(); else open() }

    // Put away at once, with no animation (another series, the page is hidden)
    function reset() {
        openAnim.stop()
        closeAnim.stop()
        shown = false
        progress = 0
    }

    // One label/value row. `valueColor` lets a row speak up (tracked, an error).
    component InfoRow: RowLayout {
        id: row
        property string label: ""
        property string value: ""
        property string note: ""
        property color valueColor: Theme.ink

        Layout.fillWidth: true
        visible: value.length > 0
        spacing: 14

        StyledText {
            Layout.preferredWidth: 96
            Layout.alignment: Qt.AlignTop
            text: row.label
            color: Colors.on_surface_variant
            font.pixelSize: ReaderType.sizeCaption
            font.weight: ReaderType.weightTitle
            font.styleName: ReaderType.styleTitle
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: row.value
                color: row.valueColor
                font.pixelSize: ReaderType.sizeBody
                font.weight: ReaderType.weightTitle
                font.styleName: ReaderType.styleTitle
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: row.note.length > 0
                text: row.note
                color: Colors.on_surface_variant
                font.pixelSize: ReaderType.sizeCaption
                font.weight: ReaderType.weightBody
                font.styleName: ReaderType.styleBody
                wrapMode: Text.Wrap
            }
        }
    }

    // A section heading
    component Heading: StyledText {
        Layout.topMargin: 6
        color: Colors.on_surface_variant
        font.pixelSize: ReaderType.sizeCaption
        font.letterSpacing: 0.8
        font.weight: ReaderType.weightTitle
        font.styleName: ReaderType.styleTitle
    }

    // A tag or genre: outlined, not clickable
    component Tag: Rectangle {
        id: tag
        property string text: ""
        property string sub: ""
        property color fill: Theme.surfaceHover

        implicitHeight: ReaderType.hBadge
        implicitWidth: tagRow.implicitWidth + 18
        radius: 9
        color: tag.fill
        border.width: 2
        border.color: Theme.colBorder
        antialiasing: true

        Row {
            id: tagRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tag.text
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Text {
                visible: tag.sub.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: tag.sub
                color: Theme.inkSub
                font.family: Theme.fontFamily
                font.pixelSize: ReaderType.sizeCaption
                font.weight: ReaderType.weightBody
                font.styleName: ReaderType.styleBody
            }
        }
    }

    // The sheet: it keeps its full size and rides down from above the top edge, with the chapter
    // list glued to its lower edge (the parent moves the list by `progress`), so it pushes the
    // list down rather than laying over it.
    Item {
        id: sheet
        width: parent.width
        height: root.height
        y: -(1 - root._p) * height

        // Swallows the clicks that would reach the chapters underneath
        MouseArea { anchors.fill: parent; hoverEnabled: true }

        Rectangle { anchors.fill: parent; color: Colors.background }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Header ────────────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                opacity: Math.min(1, root._p / 0.45)

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: "Info"
                        font.family: Theme.fontFamily
                        font.pixelSize: ReaderType.sizeTitle
                        font.weight: ReaderType.weightTitle
                        font.styleName: ReaderType.styleTitle
                        color: Theme.ink
                        elide: Text.ElideRight
                    }


                    ReaderChip {
                        visible: root.m !== null && (root.m.siteUrl || "").length > 0
                        icon: "link"
                        text: "Open on AniList"
                        onClicked: Qt.openUrlExternally(root.m.siteUrl)
                    }

                    // Slides the sheet back up. Not an x (that is the window's close key, in the
                    // header above), and at the right end, so it is not mistaken for the Back
                    // arrow that sits at the left of the bar above.
                    ReaderKey {
                        icon: "expand_less"
                        onClicked: root.close()
                    }
                }
            }

            Divider { Layout.fillWidth: true }

            // ── Body ──────────────────────────────────────────────────────────────
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: page.implicitHeight + 48

                ScrollBar.vertical: StyledScrollBar {}

                ColumnLayout {
                    id: page
                    width: Math.min(flick.width - 32, 640)
                    x: (flick.width - width) / 2
                    y: 24 + (1 - opacity) * 18      // settles into place as it fades in
                    spacing: 12
                    // the words arrive a beat after the sheet, so the sheet moves first
                    opacity: Math.max(0, Math.min(1, (root._p - 0.25) / 0.6))

                    // (The title is not written out again here: it is in the bar above the sheet.)

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.m !== null && !root._aniList
                        text: "This series was not opened from AniList, so there is no more to show. Open it from Browse or from your AniList lists to see its genres, tags, ratings and other names."
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    // ── The title ─────────────────────────────────────────────────
                    Heading { text: "THE TITLE"; visible: root._aniList }

                    InfoRow {
                        label: "Status"
                        value: root._aniList ? root._statusText : ""
                    }
                    InfoRow {
                        label: "Released"
                        value: root._aniList ? root._releasedText : ""
                    }
                    InfoRow {
                        label: "Type"
                        value: root.m && root._aniList ? root.m.type : ""
                        note: root.tr && root.tr.original.length > 0 ? "Original language: " + root.tr.original : ""
                    }
                    InfoRow {
                        label: "Size"
                        value: root._aniList && root.m && root.m.status !== "Finished" && root.m.status !== ""
                            ? RM.sizeText(root.m.chaptersTotal, root.m.volumesTotal) : ""
                    }
                    InfoRow {
                        label: "Authors"
                        value: root.m ? (root.m.authors || []).join(", ") : ""
                    }

                    // ── Translation ───────────────────────────────────────────────
                    Heading { text: "TRANSLATION"; visible: root._aniList }

                    InfoRow {
                        label: "English"
                        value: root._aniList ? root._translationText : ""
                                            note: root.tr && root.tr.kind === "fan"
                            ? "From AniList's licence flag. AniList does not name scanlation groups." : ""
                    }
                    InfoRow {
                        label: "Reading"
                        value: root._aniList ? root._readingText : ""
                        note: root.m && root.m.match ? root.m.match.title : ""
                    }

                    // ── Ratings ───────────────────────────────────────────────────
                    Heading { text: "RATINGS"; visible: root._aniList }

                    InfoRow {
                        label: "Everyone"
                        value: root._aniList && root._ratingText !== "" ? "\u2605 " + root._ratingText : (root._aniList ? "No score yet" : "")
                        note: root._crowdText
                    }
                    InfoRow {
                        label: "Yours"
                        value: {
                            if (!root._aniList) return ""
                            if (!Manga.alLoggedIn) return "Log in to AniList to see yours"
                            if (!Manga.trackKnown) return "Checking your list\u2026"
                            if (Manga.trackScoreText !== "") return "\u2605 " + Manga.trackScoreText
                            return root.entry ? "Not rated yet" : "Not on your list"
                        }
                                            note: Manga.trackScoreText !== "" ? "Change it on AniList" : ""
                    }

                    // ── Tracking ──────────────────────────────────────────────────
                    Heading { text: "TRACKING"; visible: root._aniList }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root._aniList
                        spacing: 14

                        StyledText {
                            Layout.fillWidth: true
                            text: root._trackText
                            color: Theme.ink
                            font.pixelSize: ReaderType.sizeBody
                            font.weight: ReaderType.weightTitle
                            font.styleName: ReaderType.styleTitle
                            wrapMode: Text.Wrap
                        }

                        ReaderChip {
                            visible: Manga.trackable
                            icon: root.entry ? "check_read" : "add"
                            lit: root.entry !== null
                            text: root.entry ? "Edit" : "Track"
                            onClicked: { root.close(); root.trackRequested() }
                        }
                    }

                    // ── Other names ───────────────────────────────────────────────
                    Heading {
                        text: "OTHER NAMES"
                        visible: root.m !== null && (root.m.altNames || []).length > 0
                    }

                    Repeater {
                        model: root.m ? (root.m.altNames || []) : []

                        delegate: StyledText {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            font.pixelSize: ReaderType.sizeBody
                            font.weight: ReaderType.weightBody
                            font.styleName: ReaderType.styleBody
                            wrapMode: Text.Wrap
                        }
                    }

                    // ── Genres ────────────────────────────────────────────────────
                    Heading {
                        text: "GENRES"
                        visible: root.m !== null && (root.m.genres || []).length > 0
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.m !== null && (root.m.genres || []).length > 0

                        Repeater {
                            model: root.m ? (root.m.genres || []) : []

                            delegate: Tag {
                                required property string modelData
                                text: modelData
                                fill: Theme.accentMint
                            }
                        }
                    }

                    // ── Tags ──────────────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.m !== null && (root.m.tagList || []).length > 0
                        spacing: 10

                        Heading {
                            Layout.fillWidth: true
                            text: "TAGS \u00b7 " + root._visibleTags.length
                        }

                        ReaderChip {
                            visible: root._spoilerCount > 0
                            icon: root.showSpoilers ? "eye_closed" : "visibility"
                            lit: root.showSpoilers
                            text: root.showSpoilers ? "Hide spoilers" : "Show " + root._spoilerCount + " spoiler" + (root._spoilerCount === 1 ? "" : "s")
                            onClicked: root.showSpoilers = !root.showSpoilers
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root._visibleTags.length > 0

                        Repeater {
                            model: root._visibleTags

                            delegate: Tag {
                                required property var modelData
                                text: modelData.name
                                sub: modelData.rank > 0 ? modelData.rank + "%" : ""
                                fill: modelData.spoiler ? Colors.withAlpha(Theme.accentCyan, 0.35) : Theme.surfaceHover
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.m !== null && root._aniList && root.m.tagList.length === 0 && root.m.genres.length === 0
                        text: "AniList has no genres or tags for this title."
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                    }
                }
            }
        }

        // The sheet's lower edge, so it reads as sitting on top of the chapters
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 3
            color: Theme.colBorder
            opacity: 0.85
        }

        // A soft shadow cast onto the list it is pushing, fading out as the sheet settles
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.bottom }
            height: 16
            opacity: 1 - root._p * 0.6
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.28) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
    }
}
