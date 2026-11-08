import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../NovelMath.js" as NM

// A Discover title's page: AniList's side of a novel (cover, score, genres, tags, what it is
// about) and, under it, the way to read it. AniList has no text to read, so the picked source is
// asked for the title's name and its answers are listed, the closest first and marked; picking one
// keeps the AniList match for it (so tracking is on from the first chapter) and opens it as any
// novel of the source. Another name for the title (AniList knows a few) or a typed one searches
// the source again.
//
//   DiscoverInfo { anchors.fill: parent; visible: open; card: someCard
//                  onClosed: ...; onSourcesRequested: ...; onNovelPicked: function(id) { ... } }
Item {
    id: root

    // The Discover card that was tapped: { anilistId, title, coverUrl, type, status, year, score, genres, volumes, chapters }
    property var card: null

    signal closed()
    // "Add sources": no source is installed, so there is nothing to look the title up in
    signal sourcesRequested()
    signal novelPicked(string novelId)

    // AniList's page for it (/al/info), asked for when the card changes
    property var    info: null
    property string infoError: ""
    property bool   loadingInfo: false
    property bool   moreText: false              // the whole description, not the first lines

    // The source's answers for the name in `query`
    property string query: ""
    property var    candidates: []
    property bool   searching: false
    property string lookupError: ""
    property string openingId: ""                // the row that was tapped, while its page opens

    property int _infoReq: 0
    property int _lookReq: 0

    readonly property string fontBody: Theme.fontFamily
    readonly property var names: info && info.names ? info.names : (card ? [card.title] : [])

    visible: false

    onCardChanged: if (card) root._load()

    // The picked source changed (from the Source key): ask the new one
    Connections {
        target: Novel
        function onActiveSourceChanged() {
            if (root.card && root.visible) root._lookup(root.query)
        }
    }

    function _load() {
        root.info = null
        root.infoError = ""
        root.moreText = false
        root.openingId = ""
        sourceBox.clear()
        const aid = root.card.anilistId
        const rid = ++root._infoReq
        root.loadingInfo = true
        Novel.discoverInfo(aid, function(d, err) {
            if (rid !== root._infoReq) return
            root.loadingInfo = false
            if (err) root.infoError = err
            else {
                root.info = d
                // the names are known now: a lookup that already came back is ordered by them
                root.candidates = NM.rankCandidates(root.candidates, root.names)
            }
        })
        root._lookup(root.card.title)
    }

    function _lookup(q) {
        const rid = ++root._lookReq
        root.query = q
        root.candidates = []
        root.lookupError = ""
        root.openingId = ""
        if (Novel.activeSource === "" || q.trim().length === 0) { root.searching = false; return }
        root.searching = true
        Novel.sourceLookup(q, function(list, err) {
            if (rid !== root._lookReq) return
            root.searching = false
            root.lookupError = err
            root.candidates = NM.rankCandidates(list, root.names).slice(0, 10)
        })
    }

    function _open(row) {
        if (root.openingId !== "" || !root.card) return
        root.openingId = row.id
        const aid = root.card.anilistId
        const title = root.info && root.info.title ? root.info.title : root.card.title
        Novel.openFromDiscover(row.id, aid, title, function() {
            root.openingId = ""
            root.novelPicked(row.id)
        })
    }

    // Swallows the clicks that would reach the grid underneath
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
                    Layout.alignment: Qt.AlignVCenter
                    icon: "arrow_back"
                    onClicked: root.closed()
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "On AniList"
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: root.fontBody
                    font.pixelSize: ReaderType.sizeTitle
                    font.weight: ReaderType.weightTitle
                    font.styleName: ReaderType.styleTitle
                }

                ReaderChip {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.info !== null && (root.info.siteUrl || "").length > 0
                    icon: "open_in_new"
                    text: "AniList page"
                    onClicked: Qt.openUrlExternally(root.info.siteUrl)
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Page ──────────────────────────────────────────────────────────────
        Flickable {
            id: page
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: body.implicitHeight + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: StyledScrollBar {
            }

            Column {
                id: body
                x: 16
                y: 14
                width: page.width - 32
                spacing: 16

                // The cover, and who it is
                Row {
                    width: parent.width
                    spacing: 16

                    Item {
                        width: 118
                        height: 118 * 1.5

                        Rectangle {
                            x: 3; y: 3
                            width: parent.width; height: parent.height
                            radius: 12
                            color: Theme.lineShadow
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Colors.surface_container_high
                            border.width: 2
                            border.color: Theme.colBorder

                            Image {
                                id: coverImage
                                anchors.fill: parent
                                source: root.card ? (root.card.coverUrl || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            CoverPlaceholder {
                                anchors.fill: parent
                                status: coverImage.status
                            }
                        }
                    }

                    Column {
                        width: parent.width - 118 - 16
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: root.card ? root.card.title : ""
                            wrapMode: Text.Wrap
                            color: Theme.ink
                            font.family: root.fontBody
                            font.pixelSize: 20
                            font.weight: ReaderType.weightTitle
                            font.styleName: ReaderType.styleTitle
                        }

                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: {
                                const p = []
                                if (root.card && root.card.type) p.push(root.card.type.charAt(0) + root.card.type.slice(1).toLowerCase())
                                const m = NM.cardMeta(root.card)
                                if (m.length > 0) p.push(m)
                                const l = NM.lengthText(root.card)
                                if (l.length > 0) p.push(l)
                                return p.join("  ·  ")
                            }
                            wrapMode: Text.Wrap
                            color: Theme.inkSub
                            font.family: root.fontBody
                            font.pixelSize: ReaderType.sizeBody
                            font.weight: ReaderType.weightBody
                            font.styleName: ReaderType.styleBody
                        }

                        Flow {
                            width: parent.width
                            spacing: 6

                            ReaderBadge {
                                visible: root.card !== null && (root.card.score || 0) > 0
                                rotation: -3
                                text: "★ " + (root.card ? (root.card.score / 10).toFixed(1) : "")
                            }
                            ReaderBadge {
                                visible: root.info !== null && root.info.popularity > 0
                                tonal: true
                                rotation: 0
                                text: root.info ? (root.info.popularity + " readers") : ""
                            }
                            ReaderBadge {
                                visible: root.info !== null && root.info.favourites > 0
                                tonal: true
                                rotation: 0
                                text: root.info ? ("♥ " + root.info.favourites) : ""
                            }
                        }

                        Text {
                            width: parent.width
                            visible: root.info !== null && root.info.people && root.info.people.length > 0
                            text: {
                                if (!root.info || !root.info.people) return ""
                                return root.info.people.map(function(p) {
                                    return p.role ? p.name + " (" + p.role + ")" : p.name
                                }).join("  ·  ")
                            }
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Theme.inkSub
                            font.family: root.fontBody
                            font.pixelSize: ReaderType.sizeCaption
                            font.weight: ReaderType.weightBody
                            font.styleName: ReaderType.styleBody
                        }
                    }
                }

                // Genres
                Flow {
                    width: parent.width
                    spacing: 6
                    visible: root.card !== null && root.card.genres && root.card.genres.length > 0

                    Repeater {
                        model: root.card && root.card.genres ? root.card.genres : []

                        delegate: ReaderBadge {
                            tonal: true
                            rotation: 0
                            text: modelData
                        }
                    }
                }

                // What it is about
                Column {
                    width: parent.width
                    spacing: 6
                    visible: root.loadingInfo || root.infoError.length > 0
                             || (root.info !== null && root.info.description.length > 0)

                    Text {
                        width: parent.width
                        visible: root.loadingInfo
                        text: "Loading…"
                        color: Theme.inkSub
                        font.family: root.fontBody
                        font.pixelSize: ReaderType.sizeBody
                    }

                    Text {
                        width: parent.width
                        visible: root.infoError.length > 0
                        text: root.infoError
                        wrapMode: Text.Wrap
                        color: Colors.error
                        font.family: root.fontBody
                        font.pixelSize: ReaderType.sizeBody
                    }

                    Text {
                        id: about
                        width: parent.width
                        visible: root.info !== null && root.info.description.length > 0
                        text: root.info ? root.info.description : ""
                        wrapMode: Text.Wrap
                        maximumLineCount: root.moreText ? 1000 : 6
                        elide: Text.ElideRight
                        lineHeight: 1.3
                        color: Theme.ink
                        font.family: root.fontBody
                        font.pixelSize: ReaderType.sizeBody
                        font.weight: ReaderType.weightBody
                        font.styleName: ReaderType.styleBody
                    }

                    ReaderChip {
                        visible: about.visible && (about.truncated || root.moreText)
                        icon: root.moreText ? "expand_less" : "expand_more"
                        text: root.moreText ? "Less" : "More"
                        onClicked: root.moreText = !root.moreText
                    }
                }

                // AniList's tags, in the order of how much they fit
                Flow {
                    width: parent.width
                    spacing: 6
                    visible: root.info !== null && root.info.tags && root.info.tags.length > 0

                    Repeater {
                        model: root.info && root.info.tags ? root.info.tags : []

                        delegate: ReaderBadge {
                            tonal: true
                            rotation: 0
                            outline: Theme.accentMint
                            text: modelData
                        }
                    }
                }

                Divider { width: parent.width }

                // ── Read it ───────────────────────────────────────────────────
                Text {
                    width: parent.width
                    text: Novel.activeSourceName.length > 0 ? "Read it from " + Novel.activeSourceName : "Read it"
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: root.fontBody
                    font.pixelSize: ReaderType.sizeTitle
                    font.weight: ReaderType.weightTitle
                    font.styleName: ReaderType.styleTitle
                }

                // No source installed: nothing to look it up in
                Column {
                    width: parent.width
                    spacing: 10
                    visible: Novel.serverReady && Novel.sourcesLoaded && Novel.sources.length === 0

                    Text {
                        width: parent.width
                        text: "Novels come from LNReader sources. Add one, and this title is looked up in it."
                        wrapMode: Text.Wrap
                        color: Theme.inkSub
                        font.family: root.fontBody
                        font.pixelSize: ReaderType.sizeBody
                        lineHeight: 1.3
                    }

                    ReaderChip {
                        text: "Add sources"
                        lit: true
                        onClicked: root.sourcesRequested()
                    }
                }

                // The other names AniList has for it: a source may spell it differently
                Column {
                    width: parent.width
                    spacing: 6
                    visible: Novel.activeSource !== "" && root.names.length > 1

                    Text {
                        text: "Search the source as"
                        color: Theme.inkSub
                        font.family: root.fontBody
                        font.pixelSize: ReaderType.sizeCaption
                        font.weight: ReaderType.weightStrong
                        font.styleName: ReaderType.styleStrong
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.names

                            delegate: ReaderChip {
                                required property string modelData
                                text: modelData
                                lit: modelData === root.query
                                onClicked: { sourceBox.clear(); root._lookup(modelData) }
                            }
                        }
                    }
                }

                SearchPill {
                    id: sourceBox
                    width: parent.width
                    height: ReaderType.hField
                    visible: Novel.activeSource !== ""
                    placeholder: "Or search the source for another name…"
                    onTextChanged: sourceDebounce.restart()

                    Timer {
                        id: sourceDebounce
                        interval: 450
                        onTriggered: {
                            const q = sourceBox.text.trim()
                            // an empty box is the title again; the same name is not asked twice
                            const want = q.length > 0 ? q : (root.card ? root.card.title : "")
                            if (want !== root.query) root._lookup(want)
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.searching
                    text: "Looking in " + Novel.activeSourceName + "…"
                    color: Theme.inkSub
                    font.family: root.fontBody
                    font.pixelSize: ReaderType.sizeBody
                }

                Text {
                    width: parent.width
                    visible: root.lookupError.length > 0
                    text: root.lookupError
                    wrapMode: Text.Wrap
                    color: Colors.error
                    font.family: root.fontBody
                    font.pixelSize: ReaderType.sizeBody
                }

                Text {
                    width: parent.width
                    visible: Novel.activeSource !== "" && !root.searching && root.lookupError.length === 0
                             && root.candidates.length === 0 && root.query.length > 0
                    text: "Nothing in " + Novel.activeSourceName + " is called that. Try another name above, or switch the source."
                    wrapMode: Text.Wrap
                    color: Theme.inkSub
                    font.family: root.fontBody
                    font.pixelSize: ReaderType.sizeBody
                    lineHeight: 1.3
                }

                // The source's answers, the closest first
                Column {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.candidates

                        delegate: Item {
                            id: row
                            required property var modelData
                            readonly property bool busy: root.openingId === row.modelData.id

                            width: body.width
                            height: 68

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: rowArea.containsMouse ? Theme.surfaceTint : Theme.surfaceHover
                                border.width: row.modelData.best ? 2 : 0
                                border.color: Theme.accentMint
                                antialiasing: true
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            ClippingRectangle {
                                id: thumb
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                width: 38; height: 54
                                radius: 6
                                color: Colors.surface_container_high

                                Image {
                                    id: thumbImage
                                    anchors.fill: parent
                                    source: row.modelData.coverUrl || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 76
                                }
                            }

                            Column {
                                anchors {
                                    left: thumb.right; leftMargin: 12
                                    right: pick.left; rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: row.modelData.title
                                    elide: Text.ElideRight
                                    color: Theme.ink
                                    font.family: root.fontBody
                                    font.pixelSize: ReaderType.sizeBody
                                    font.weight: ReaderType.weightTitle
                                    font.styleName: ReaderType.styleTitle
                                }

                                Text {
                                    width: parent.width
                                    text: {
                                        const p = []
                                        if (row.modelData.author) p.push(row.modelData.author)
                                        if (row.modelData.latestChapter) p.push(row.modelData.latestChapter)
                                        return p.join("  ·  ")
                                    }
                                    visible: text.length > 0
                                    elide: Text.ElideRight
                                    color: Theme.inkSub
                                    font.family: root.fontBody
                                    font.pixelSize: ReaderType.sizeCaption
                                    font.weight: ReaderType.weightBody
                                    font.styleName: ReaderType.styleBody
                                }
                            }

                            ReaderBadge {
                                id: pick
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                rotation: 0
                                tonal: !row.modelData.best
                                text: row.busy ? "OPENING…" : (row.modelData.best ? "BEST MATCH" : "READ")
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.openingId === ""
                                onClicked: root._open(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
