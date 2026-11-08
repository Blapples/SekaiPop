import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// The logged-in half of the AniList page: who you are, where you stopped, what you hearted.
//
//   ProfilePage { Layout.fillWidth: true; onMangaSelected: ... }
//
//   1. The profile card: banner, avatar, name, followers and following, and three numbers
//      (chapters read, mean score, titles tracked), drawn as one of the shell's own cards.
//   2. The stats strip (volumes read, completed, scored, chapters per title; ProfileStats),
//      the status bar (how the list splits between Reading, Completed, Dropped and Planning)
//      and "Can't decide?", a random title from Planning (ProfilePick).
//   3. Jump back in: the Library titles read most recently; a tap opens the title and goes
//      straight on to the chapter and page left off at (Manga.autoContinueId). Under it Recent
//      activity: your latest AniList list updates, newest first ("Ch. 52 - 2h").
//   4. Reading now: the AniList Reading list, last updated first, with the progress on each.
//      Under it Almost done (5 chapters or fewer left) and Stalled (30 days or more without
//      an update), then Up next: the Planning list by AniList's score (ProfileShelf).
//   5. Top rated: the titles scored highest, then "Because you rated X highly": what the other
//      readers of those titles recommend, a shelf for each of up to three of them.
//   6. Favourites: the manga hearted on AniList, as the same cover cards as everywhere else.
//   7. Scores: how your scores spread (ProfileScores), Breakdown: type, decade, tags and the
//      creators read most (ProfileBreakdown), then Taste: the genres read most and
//      the reading-activity heatmap with its streaks (ProfileTaste).
//   8. About: the AniList bio.
//   9. Account: the tracking switch, Open profile and Log out, with the small print folded.
//
// The profile colour you set on AniList (Manga.extras.color) tints the banner when there is no
// banner image of your own, and the ring round the avatar.
//
// The data is Manga's (profile, overview, activity, extras, recs and their fetches); the backend keeps the
// profile for two minutes and builds the overview from the list it already holds.
ColumnLayout {
    id: root

    // A cover was tapped: the parent shows that title
    signal mangaSelected(string mangaId)

    spacing: 24

    readonly property var profile: Manga.profile
    readonly property var stats: profile ? profile.stats : null
    readonly property var favourites: profile ? (profile.favourites || []) : []
    readonly property int favouritesTotal: profile ? (profile.favouritesTotal || 0) : 0

    // The avatar and the profile link are known from the login before the profile arrives
    // (the profile's own is the fresher: the login's copy is from when it was made)
    readonly property string avatarUrl:
        (profile && profile.avatar) ? profile.avatar : ((Manga.alViewer && Manga.alViewer.avatar) ? Manga.alViewer.avatar : "")
    readonly property string profileUrl:
        (Manga.alViewer && Manga.alViewer.siteUrl) ? Manga.alViewer.siteUrl : (profile ? (profile.siteUrl || "") : "")

    readonly property int cellW: 124
    readonly property int cellH: Math.round(cellW * 1.72)

    property bool detailsOpen: false

    readonly property bool favLoading: profile === null && Manga.profileBusy
    readonly property bool favFailed: profile === null && !Manga.profileBusy && Manga.profileError.length > 0
    readonly property bool favEmpty: profile !== null && favourites.length === 0

    // The Library titles that have been read, the most recent first (an entry from before the
    // time was kept stays in the Library's own order after the ones that have one).
    readonly property var recent: {
        const rows = []
        const lib = Manga.libraryList
        for (let i = 0; i < lib.length; i++) {
            const e = lib[i]
            if (e && e.lastReadChapterId && String(e.lastReadChapterNum || "").length > 0)
                rows.push({ e: e, i: i })
        }
        rows.sort(function(a, b) { return ((b.e.lastReadAt || 0) - (a.e.lastReadAt || 0)) || (a.i - b.i) })
        return rows.slice(0, 8).map(function(r) { return r.e })
    }

    readonly property var statCells: [
        { value: stats ? RM.groupDigits(stats.chaptersRead) : "\u2014", label: "Chapters read" },
        { value: stats ? (RM.meanScoreText(stats.meanScore, Manga.scoreFormat) || "\u2014") : "\u2014", label: "Mean score" },
        { value: stats ? RM.groupDigits(stats.count) : "\u2014", label: "Titles tracked" }
    ]

    // From the list (Manga.overview): the AniList Reading list and the highest scored titles
    readonly property var overview: Manga.overview
    readonly property var reading: overview ? (overview.reading || []) : []
    readonly property int readingTotal: overview ? (overview.readingTotal || 0) : 0
    readonly property var topRated: overview ? (overview.top || []) : []
    readonly property var almostDone: overview ? (overview.almostDone || []) : []
    readonly property int almostTotal: overview ? (overview.almostTotal || 0) : 0
    readonly property var stalled: overview ? (overview.stalled || []) : []
    readonly property int stalledTotal: overview ? (overview.stalledTotal || 0) : 0
    readonly property var planning: overview ? (overview.planning || []) : []
    readonly property int planningTotal: overview ? (overview.planningTotal || 0) : 0
    readonly property string scoreFormat: (overview && overview.scoreFormat) ? overview.scoreFormat : Manga.scoreFormat

    // From /al/extras and /al/recs (each left out when AniList would not answer)
    readonly property var extras: Manga.extras
    readonly property var feedRows: extras ? RM.feedRows(extras.feed || [], Date.now() / 1000) : []
    readonly property var recGroups: Manga.recs ? (Manga.recs.groups || []) : []
    readonly property bool tinted: extras !== null && String(extras.color || "").length > 0
    readonly property color tint: tinted ? extras.color : "transparent"

    readonly property string about: profile ? (profile.about || "") : ""
    property bool aboutOpen: false

    // "12 followers · 34 following" once the profile is here; the login's own line before
    readonly property string subtitle: profile
        ? RM.groupDigits(profile.followers) + (profile.followers === 1 ? " follower" : " followers")
          + " \u00b7 " + RM.groupDigits(profile.following) + " following"
        : "Logged in to AniList"

    function openTitle(id) {
        Manga.fetchMangaDetail(id)
        root.mangaSelected(id)
    }

    // The flag goes up first: opening the title for another id would clear it
    function resumeTitle(id) {
        Manga.autoContinueId = id
        Manga.fetchMangaDetail(id)
        root.mangaSelected(id)
    }

    // Asked whenever the page shows (opening it, or a login that has just come back)
    onVisibleChanged: if (visible) {
        Manga.fetchProfile()
        Manga.fetchOverview()
        Manga.fetchActivity()
        Manga.fetchExtras()
        Manga.fetchRecs()
    }

    // ── 1. The profile card ───────────────────────────────────────────────────
    Item {
        id: cardBox
        Layout.fillWidth: true

        // The banner keeps AniList's own proportions (its banners are 1900 x 400), so it shows
        // the way the website draws it instead of a thin strip cut out of the middle. Everything
        // under it follows its height.
        readonly property real bannerH: Math.max(72, Math.round((width - 2 * Theme.borderWidth) * 400 / 1900))

        Layout.preferredHeight: bannerH + 112 + 2 * Theme.borderWidth + Theme.shadowOffset

        Pill {
            id: card
            anchors.fill: parent
            cornerRadius: 18
            ringWidth: Theme.borderWidth
            innerRing: Theme.cardRing
            fillColor: Theme.surface

            ClippingRectangle {
                id: cardClip
                anchors.fill: parent
                radius: Math.max(0, card.cornerRadius - card.ringWidth)
                color: "transparent"

                // The banner: the user's own, over the accent until it arrives (or when they have none)
                Rectangle {
                    id: banner
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: cardBox.bannerH

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root.tinted ? root.tint : Theme.accentMint }
                        GradientStop { position: 1.0; color: root.tinted ? Qt.lighter(root.tint, 1.35) : Theme.accentCyan }
                    }

                    Image {
                        anchors.fill: parent
                        source: root.profile ? (root.profile.banner || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                }

                // The panel line under the banner
                Rectangle { y: cardBox.bannerH; width: parent.width; height: 2; color: Theme.line }

                // The avatar sits across the banner's edge, in its own ring
                Rectangle {
                    id: avatarRing
                    x: 16
                    y: cardBox.bannerH - 34
                    width: 80
                    height: 80
                    radius: 40
                    color: root.tinted ? root.tint : Theme.surface
                    border.width: Theme.borderWidth
                    border.color: Theme.line
                    antialiasing: true

                    RoundClip {
                        anchors.centerIn: parent
                        width: parent.width - 2 * Theme.borderWidth - 4
                        height: width
                        radii: [width / 2, width / 2, width / 2, width / 2]

                        Rectangle { anchors.fill: parent; color: Theme.surfaceTint }

                        Image {
                            anchors.fill: parent
                            source: root.avatarUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                }

                Text {
                    x: 112
                    y: cardBox.bannerH + 10
                    width: cardClip.width - x - 16
                    text: (root.profile && root.profile.name) ? root.profile.name : (Manga.alViewer ? Manga.alViewer.name : "")
                    color: Theme.ink
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                Text {
                    x: 112
                    y: cardBox.bannerH + 36
                    width: cardClip.width - x - 16
                    text: root.subtitle
                    color: Theme.inkSub
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: ReaderType.sizeCaption
                    font.weight: ReaderType.weightBody
                    font.styleName: ReaderType.styleBody
                }

                // The three numbers
                Rectangle { y: cardBox.bannerH + 50; width: parent.width; height: 2; color: Theme.line }

                Row {
                    y: cardBox.bannerH + 52
                    width: parent.width
                    height: 60

                    Repeater {
                        model: root.statCells

                        delegate: Item {
                            width: cardClip.width / 3
                            height: 60

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.value
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    font.weight: Font.ExtraBold
                                    font.styleName: Theme.fontStyleBold
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    color: Theme.inkSub
                                    font.family: Theme.fontFamily
                                    font.pixelSize: ReaderType.sizeCaption
                                    font.weight: ReaderType.weightBody
                                    font.styleName: ReaderType.styleBody
                                }
                            }

                            Rectangle {
                                visible: index < 2
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 2
                                height: 34
                                color: Theme.line
                                opacity: 0.3
                            }
                        }
                    }
                }
            }
        }
    }

    // ── 2. The stats strip, the status bar and the random pick ───────────────
    ProfileStats {
        Layout.fillWidth: true
    }

    ProfileStatusBar {
        Layout.fillWidth: true
    }

    ProfilePick {
        Layout.fillWidth: true
        onMangaSelected: function(id) { root.mangaSelected(id) }
    }

    // ── 3. Jump back in ───────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.recent.length > 0
        spacing: 6

        ProfileHeading {
            title: "Jump back in"
            hint: "Opens on the page you stopped at"
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cellH
            orientation: ListView.Horizontal
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.recent

            delegate: Item {
                width: root.cellW
                height: root.cellH

                readonly property var entry: modelData

                CoverCard {
                    anchors.fill: parent
                    source: entry.coverUrl || ""
                    title: entry.title || ""
                    gradientHeight: 48
                    footerHeight: 30

                    CoverProgressBar {
                        height: 30
                        rowSpacing: 6
                        started: true
                        label: "Ch. " + entry.lastReadChapterNum
                    }

                    onClicked: root.resumeTitle(entry.id)
                }
            }
        }
    }

    // Under Jump back in: what the list itself says you did last
    ProfileShelf {
        Layout.fillWidth: true
        kind: "feed"
        title: "Recent activity"
        hint: "Your latest AniList updates"
        rows: root.feedRows
        onPicked: function(id) { root.openTitle(id) }
    }

    // ── 4. Reading now ────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.reading.length > 0
        spacing: 6

        ProfileHeading {
            title: "Reading now"
            hint: "Your AniList Reading list, last updated first \u00b7 " + root.readingTotal
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cellH
            orientation: ListView.Horizontal
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.reading

            delegate: Item {
                width: root.cellW
                height: root.cellH

                readonly property var row: modelData

                CoverCard {
                    anchors.fill: parent
                    source: row.image || ""
                    title: row.title || ""
                    gradientHeight: 48
                    footerHeight: 30

                    CoverProgressBar {
                        height: 30
                        rowSpacing: 6
                        started: row.progress > 0
                        label: row.progress > 0 ? "Ch. " + RM.listProgressText(row.progress, row.chapters) : "Not started"
                    }

                    onClicked: root.openTitle(row.id)
                }
            }
        }
    }

    // Under Reading now: what is nearly finished, what has gone quiet, what to read next
    ProfileShelf {
        Layout.fillWidth: true
        kind: "almost"
        title: "Almost done"
        hint: "5 chapters or fewer to go" + (root.almostTotal > root.almostDone.length ? " \u00b7 " + root.almostTotal : "")
        rows: root.almostDone
        onPicked: function(id) { root.openTitle(id) }
    }

    ProfileShelf {
        Layout.fillWidth: true
        kind: "stalled"
        title: "Stalled"
        hint: "Reading, but not touched for 30 days or more" + (root.stalledTotal > root.stalled.length ? " \u00b7 " + root.stalledTotal : "")
        rows: root.stalled
        onPicked: function(id) { root.openTitle(id) }
    }

    ProfileShelf {
        Layout.fillWidth: true
        kind: "planning"
        title: "Up next"
        hint: "Your Planning list, best rated on AniList first" + (root.planningTotal > root.planning.length ? " \u00b7 " + root.planningTotal : "")
        rows: root.planning
        onPicked: function(id) { root.openTitle(id) }
    }

    // ── 5. Top rated ──────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.topRated.length > 0
        spacing: 6

        ProfileHeading {
            title: "Top rated"
            hint: "The titles you scored highest"
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cellH
            orientation: ListView.Horizontal
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.topRated

            delegate: Item {
                width: root.cellW
                height: root.cellH

                readonly property var row: modelData

                CoverCard {
                    anchors.fill: parent
                    source: row.image || ""
                    title: row.title || ""
                    subtitle: (row.type || "") + (row.year > 0 ? " \u00b7 " + row.year : "")
                    gradientHeight: 48

                    // The score is the one bright thing on the cover, as in Browse
                    ReaderBadge {
                        anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                        rotation: -4
                        text: RM.scoreStamp(row.score, row.score100, root.scoreFormat)
                        fill: Theme.accentMint
                    }

                    onClicked: root.openTitle(row.id)
                }
            }
        }
    }

    // Under Top rated: what the readers of those titles recommend, one shelf for each
    Repeater {
        model: root.recGroups

        delegate: ProfileShelf {
            Layout.fillWidth: true
            kind: "recs"
            title: "Because you rated " + RM.ellipsize(modelData.because, 36) + " highly"
            hint: "What its other readers recommend"
            rows: modelData.items
            onPicked: function(id) { root.openTitle(id) }
        }
    }

    // ── 6. Favourites ─────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ProfileHeading {
                Layout.fillWidth: true
                title: "Favourites"
                hint: root.favouritesTotal > 0 ? "Hearted on AniList \u00b7 " + root.favouritesTotal : "Hearted on AniList"
            }

            ReaderChip {
                Layout.alignment: Qt.AlignVCenter
                visible: root.favouritesTotal > root.favourites.length && root.profileUrl.length > 0
                icon: "link"
                text: "See all"
                onClicked: Qt.openUrlExternally(root.profileUrl + "/favorites")
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: (root.favourites.length > 0 || root.favLoading) ? root.cellH : 84
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            // Covers, as the cards of the Library
            ListView {
                anchors.fill: parent
                visible: root.favourites.length > 0
                orientation: ListView.Horizontal
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.favourites

                delegate: Item {
                    width: root.cellW
                    height: root.cellH

                    readonly property var fav: modelData

                    CoverCard {
                        anchors.fill: parent
                        source: fav.image || ""
                        title: fav.title || ""
                        subtitle: (fav.type || "") + (fav.year > 0 ? " \u00b7 " + fav.year : "")
                        gradientHeight: 48

                        onClicked: root.openTitle(fav.id)
                    }
                }
            }

            // First ask: ghost covers where the favourites will land
            Row {
                anchors.fill: parent
                visible: root.favLoading

                Repeater {
                    model: 4

                    delegate: Item {
                        width: root.cellW
                        height: root.cellH

                        Rectangle {
                            id: ghost
                            anchors { fill: parent; margins: 5 }
                            radius: 13
                            color: Theme.surface
                            antialiasing: true
                        }

                        SkeletonPulse {
                            target: ghost
                            low: 0.5
                            delay: index * 140
                            running: root.favLoading
                        }
                    }
                }
            }

            // Nothing hearted yet
            Rectangle {
                anchors { fill: parent; margins: 5 }
                visible: root.favEmpty
                radius: 13
                color: Theme.surface
                opacity: 0.7
                antialiasing: true

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "No favourites yet. Tap the heart on a manga's AniList page and it shows up here."
                    color: Theme.inkSub
                    font.family: Theme.fontFamily
                    font.pixelSize: ReaderType.sizeCaption + 1
                    font.weight: ReaderType.weightBody
                    font.styleName: ReaderType.styleBody
                    lineHeight: 1.3
                }
            }

            // It could not be asked
            Rectangle {
                anchors { fill: parent; margins: 5 }
                visible: root.favFailed
                radius: 13
                color: Theme.surface
                antialiasing: true

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    width: parent.width - 32

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: Manga.profileError
                        color: Colors.error
                        font.family: Theme.fontFamily
                        font.pixelSize: ReaderType.sizeCaption
                    }

                    ReaderChip {
                        anchors.horizontalCenter: parent.horizontalCenter
                        icon: "refresh"
                        text: "Retry"
                        onClicked: Manga.fetchProfile()
                    }
                }
            }
        }
    }

    // ── 7. Scores and taste ───────────────────────────────────────────────────
    ProfileScores {
        Layout.fillWidth: true
    }

    ProfileBreakdown {
        Layout.fillWidth: true
    }

    // ── Taste ──────────────────────────────────────────────────────────────
    ProfileTaste {
        Layout.fillWidth: true
    }

    // ── 8. About ──────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.about.length > 0
        spacing: 6

        ProfileHeading { title: "About" }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: aboutCol.implicitHeight + 24
            radius: 13
            color: Theme.surface
            antialiasing: true

            ColumnLayout {
                id: aboutCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8

                Text {
                    id: aboutText
                    Layout.fillWidth: true
                    text: root.about
                    color: Theme.ink
                    wrapMode: Text.Wrap
                    maximumLineCount: root.aboutOpen ? 1000 : 4
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: ReaderType.sizeBody
                    font.weight: ReaderType.weightBody
                    font.styleName: ReaderType.styleBody
                    lineHeight: 1.25
                }

                ReaderChip {
                    visible: aboutText.truncated || root.aboutOpen
                    icon: root.aboutOpen ? "expand_less" : "expand_more"
                    text: root.aboutOpen ? "Show less" : "Show more"
                    onClicked: root.aboutOpen = !root.aboutOpen
                }
            }
        }
    }

    // ── 9. Account ────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        ProfileHeading { title: "Account" }

        Flow {
            Layout.fillWidth: true
            spacing: 10

            // What is read goes on the list by itself
            ReaderChip {
                icon: Manga.trackAuto ? "check_read" : "eye_closed"
                text: "Update as I read: " + (Manga.trackAuto ? "On" : "Off")
                lit: Manga.trackAuto
                onClicked: Manga.setTrackAuto(!Manga.trackAuto)
            }

            // A title already begun on AniList opens with those chapters marked read
            ReaderChip {
                icon: Manga.trackAdopt ? "check_read" : "eye_closed"
                text: "Mark read from AniList: " + (Manga.trackAdopt ? "On" : "Off")
                lit: Manga.trackAdopt
                onClicked: Manga.setTrackAdopt(!Manga.trackAdopt)
            }

            ReaderChip {
                icon: "link"
                text: "Open profile"
                visible: root.profileUrl.length > 0
                onClicked: Qt.openUrlExternally(root.profileUrl)
            }

            ReaderChip {
                icon: "logout"
                text: "Log out"
                enabled: !Manga.alBusy
                onClicked: Manga.alLogout()
            }

            ReaderChip {
                icon: root.detailsOpen ? "expand_less" : "expand_more"
                text: "Details"
                lit: root.detailsOpen
                onClicked: root.detailsOpen = !root.detailsOpen
            }
        }

        // The small print, folded
        Item {
            Layout.fillWidth: true
            // Never hidden with `visible`: a hidden item is not given a width by the layout, the
            // text under it then measures zero tall and the fold could never open. It is only
            // clipped to nothing while closed.
            Layout.preferredHeight: root.detailsOpen ? detailsCol.implicitHeight : 0
            clip: true
            opacity: root.detailsOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Column {
                id: detailsCol
                width: parent.width
                spacing: 10

                StyledText {
                    width: parent.width
                    text: "When a chapter is finished, the highest chapter you have read is put on your AniList (Reading, then Completed at the last chapter). It only ever goes up. Open a title from Browse and use the AniList key under its cover to set it by hand."
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    opacity: 0.8
                }

                StyledText {
                    width: parent.width
                    text: "Logging out forgets the login on this computer. To cancel it on AniList too, remove SekaiPop under Apps in your AniList settings."
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    opacity: 0.8
                }

                StyledText {
                    width: parent.width
                    text: "The login is kept in ~/.local/share/sekaipop/readers/manga/anilist_auth.json, readable only by you."
                    color: Colors.on_surface_variant
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    opacity: 0.7
                }
            }
        }
    }
}
