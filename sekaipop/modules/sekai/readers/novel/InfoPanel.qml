import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM
import "../NovelMath.js" as NM

// Everything known about the open novel, in a sheet that slides down into the chapter area (the
// cover and the strip above it stay where they are): whether it is ongoing or complete, when it
// came out, where it is read from, the ratings (everyone's and yours), whether it is on your AniList
// list, the other names, every genre and tag. It is the manga panel's Info sheet for a novel.
//
// What AniList says comes from Novel.matchInfo (the page of the AniList novel this one is matched
// to, found with or without a login), your list entry from Novel.trackEntry. A novel with no match
// still shows what its source says (status, author, genres, where it is read from).
//
// The panel fills the Item it sits in (which should clip); the sheet rides down from the top and
// the chapter list is pushed down ahead of it, so nothing is covered, it just moves. `progress`
// (0 shut .. 1 open) is what the parent reads to move the list.
//
//   InfoPanel { id: panel; anchors.fill: parent }
//   panel.toggle()   panel.open()   panel.close()   panel.shown   panel.progress
Item {
    id: root

    signal closed()
    signal trackRequested()

    // The novel as its source gives it, and AniList's page of it (null until it is found)
    readonly property var m: Novel.currentNovel
    readonly property var ai: Novel.infoKnown ? Novel.matchInfo : null
    readonly property var entry: Novel.trackEntry
    readonly property bool _aniList: ai !== null

    // ── The words of each row ─────────────────────────────────────────────────
    readonly property string _statusWord: NM.statusWord(ai ? ai.status : "") || NM.statusWord(m ? m.status : "")

    readonly property string _statusText: {
        if (!m) return ""
        // a finished novel says how big it ended up; an ongoing one gets a Size row instead
        const size = ai ? RM.sizeText(ai.chapters, ai.volumes) : ""
        return _statusWord === "Completed" && size !== "" ? _statusWord + " \u00b7 " + size : _statusWord
    }

    readonly property string _sizeText: {
        if (!ai || _statusWord === "Completed") return ""
        return RM.sizeText(ai.chapters, ai.volumes)
    }

    readonly property string _releasedText: ai ? NM.releasedText(ai.start, ai.end, ai.status, ai.year) : ""

    readonly property string _authorsText: {
        const fromAniList = ai ? NM.authorsText(ai.people) : ""
        return fromAniList !== "" ? fromAniList : (m ? m.author : "")
    }

    readonly property string _readingText: {
        if (!m) return ""
        const site = Novel.sourceNameFor(m.id)
        return site.length > 0 ? "English, from " + site : ""
    }

    readonly property string _ratingText: {
        if (!ai) return ""
        const a = NM.scoreStamp(ai.score)
        return a === "" ? "" : a + " / 10"
    }

    readonly property string _crowdText: {
        if (!ai) return ""
        const out = []
        const p = RM.shortCount(ai.popularity)
        const f = RM.shortCount(ai.favourites)
        if (p !== "") out.push(p + " readers")
        if (f !== "") out.push(f + " favourites")
        return out.join(" \u00b7 ")
    }

    readonly property string _trackText: {
        if (!Novel.alLoggedIn) return "Log in to AniList (the account key in the panel header) to track"
        if (!_aniList)         return Novel.alMatching || Novel.matchInfoBusy ? "Looking it up on AniList\u2026"
                                                                              : "Not matched to an AniList novel yet"
        if (!Novel.trackKnown) return "Checking your list\u2026"
        if (!entry)            return "Not tracked \u00b7 not on your AniList yet"
        const total = Novel.trackInfo.chapters || 0
        return "Tracked \u00b7 " + Novel.trackStatusLabel(entry.status)
            + " \u00b7 ch. " + entry.progress + (total > 0 ? " of " + total : "")
    }

    readonly property var _genres: ai && (ai.genres || []).length > 0 ? ai.genres : (m ? (m.genres || []) : [])
    readonly property var _tags: ai ? (ai.tags || []) : []
    readonly property var _otherNames: ai ? NM.otherNames(ai.names, m ? m.title : "") : []

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
        flick.contentY = 0
        shown = true
        closeAnim.stop()
        openAnim.duration = Math.round(560 * Math.max(0.35, 1 - progress))
        openAnim.start()
        // the page and your list entry may not have arrived yet (or the last ask failed)
        Novel.alMatchFetch()
        Novel.alInfoFetch()
        if (Novel.trackable) Novel.trackFetch()
    }

    function close() {
        shown = false
        openAnim.stop()
        closeAnim.duration = Math.round(320 * Math.max(0.4, progress))
        closeAnim.start()
        root.closed()
    }

    function toggle() { if (shown) close(); else open() }

    // Put away at once, with no animation (another novel, the page is hidden)
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
        property color fill: Theme.surfaceHover

        implicitHeight: ReaderType.hBadge
        implicitWidth: tagLabel.implicitWidth + 18
        radius: 9
        color: tag.fill
        border.width: 2
        border.color: Theme.colBorder
        antialiasing: true

        Text {
            id: tagLabel
            anchors.centerIn: parent
            text: tag.text
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.ExtraBold
            font.styleName: Theme.fontStyleBold
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
                        visible: root.ai !== null && (root.ai.siteUrl || "").length > 0
                        icon: "link"
                        text: "Open on AniList"
                        onClicked: Qt.openUrlExternally(root.ai.siteUrl)
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
                        visible: root.m !== null && !root._aniList && !Novel.alMatching && !Novel.matchInfoBusy
                        text: Novel.alLoggedIn
                            ? "This novel is not matched to an AniList novel, so there is less to show. Use the AniList key under the title to pick the match, and its ratings, tags and other names appear here."
                            : "This novel is not matched to an AniList novel, so there is less to show. Log in to AniList (the account key in the panel header) to pick the match by hand."
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    // ── The title ─────────────────────────────────────────────────
                    Heading { text: "THE TITLE" }

                    InfoRow {
                        label: "Status"
                        value: root._statusText
                    }
                    InfoRow {
                        label: "Released"
                        value: root._releasedText
                    }
                    InfoRow {
                        label: "Type"
                        value: root.ai ? root.ai.type : ""
                        note: root.ai && NM.originLanguage(root.ai.type).length > 0
                            ? "Original language: " + NM.originLanguage(root.ai.type) : ""
                    }
                    InfoRow {
                        label: "Size"
                        value: root._sizeText
                    }
                    InfoRow {
                        label: "Authors"
                        value: root._authorsText
                    }

                    // ── Translation ───────────────────────────────────────────────
                    Heading { text: "TRANSLATION"; visible: root._readingText.length > 0 }

                    InfoRow {
                        label: "Reading"
                        value: root._readingText
                        note: root.m ? (Novel.currentNovel.chapters.length + " chapters from this source") : ""
                    }

                    // ── Ratings ───────────────────────────────────────────────────
                    Heading { text: "RATINGS"; visible: root._aniList }

                    InfoRow {
                        label: "Everyone"
                        value: root._aniList ? (root._ratingText !== "" ? "\u2605 " + root._ratingText : "No score yet") : ""
                        note: root._crowdText
                    }
                    InfoRow {
                        label: "Yours"
                        value: {
                            if (!root._aniList) return ""
                            if (!Novel.alLoggedIn) return "Log in to AniList to see yours"
                            if (!Novel.trackKnown) return "Checking your list\u2026"
                            if (Novel.trackScoreText !== "") return "\u2605 " + Novel.trackScoreText
                            return root.entry ? "Not rated yet" : "Not on your list"
                        }
                        note: Novel.trackScoreText !== "" ? "Change it on AniList" : ""
                    }

                    // ── Tracking ──────────────────────────────────────────────────
                    Heading { text: "TRACKING" }

                    RowLayout {
                        Layout.fillWidth: true
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
                            visible: Novel.trackable
                            icon: root.entry ? "check_read" : "add"
                            lit: root.entry !== null
                            text: root.entry ? "Edit" : "Track"
                            onClicked: { root.close(); root.trackRequested() }
                        }
                    }

                    // ── Other names ───────────────────────────────────────────────
                    Heading {
                        text: "OTHER NAMES"
                        visible: root._otherNames.length > 0
                    }

                    Repeater {
                        model: root._otherNames

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
                        visible: root._genres.length > 0
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root._genres.length > 0

                        Repeater {
                            model: root._genres

                            delegate: Tag {
                                required property string modelData
                                text: modelData
                                fill: Theme.accentMint
                            }
                        }
                    }

                    // ── Tags ──────────────────────────────────────────────────────
                    Heading {
                        text: "TAGS \u00b7 " + root._tags.length
                        visible: root._tags.length > 0
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root._tags.length > 0

                        Repeater {
                            model: root._tags

                            delegate: Tag {
                                required property string modelData
                                text: modelData
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root._aniList && root._tags.length === 0 && root._genres.length === 0
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
