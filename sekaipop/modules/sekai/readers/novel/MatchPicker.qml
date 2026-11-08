import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// Picks which AniList novel the open novel is, for tracking. It opens with a search for the
// novel's own name; typing searches AniList's novels for that text instead. Only novels are
// listed (the backend asks AniList for the NOVEL format and refuses anything else). A pick is
// kept until you change it, and "Use automatic match" lets go of it.
//
//   MatchPicker { id: picker; anchors.fill: parent }
//   picker.open()
Item {
    id: root

    signal closed()

    property var    candidates: []
    property bool   searching: false
    property string error: ""
    property string _lastQuery: ""
    property int    _req: 0

    visible: false

    readonly property bool hasManual: Novel.alMatch !== null && Novel.alMatch.manual === true

    function _search(q) {
        const rid = ++root._req
        root.searching = true
        root.error = ""
        Novel.alSearch(q, function(list, err) {
            if (rid !== root._req) return
            root.searching = false
            root.error = err
            root.candidates = list
        })
    }

    function open() {
        root._lastQuery = ""
        search.clear()
        root.candidates = []
        visible = true
        root._search(Novel.currentNovel ? Novel.currentNovel.title : "")
    }

    function close() {
        visible = false
        root.closed()
    }

    // Swallows the clicks that would reach the page underneath
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
                    icon: "close"
                    onClicked: root.close()
                }

                Text {
                    Layout.fillWidth: true
                    text: "Which AniList novel?"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    color: Theme.ink
                    elide: Text.ElideRight
                }

                ReaderChip {
                    visible: root.hasManual
                    text: "Use automatic match"
                    onClicked: {
                        Novel.alClearMatch()
                        root.close()
                    }
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Search ────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58

            SearchPill {
                id: search
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 14
                anchors.rightMargin: 18
                height: 40
                placeholder: "Search AniList novels…"
                onTextChanged: debounce.restart()
            }

            Timer {
                id: debounce
                interval: 350
                onTriggered: {
                    const t = search.text.trim().length > 0 ? search.text.trim()
                        : (Novel.currentNovel ? Novel.currentNovel.title : "")
                    if (t === root._lastQuery) return
                    root._lastQuery = t
                    root._search(t)
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Candidates ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            SkeletonList {
                anchors.fill: parent
                z: 5
                active: root.searching
                rowHeight: 64
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 48
                z: 4
                visible: !root.searching && (root.error.length > 0 || root.candidates.length === 0)
                text: root.error.length > 0 ? root.error : "No novels found on AniList"
                color: root.error.length > 0 ? Colors.error : Colors.on_surface_variant
                font.pixelSize: 12
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            ListView {
                id: candList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.candidates

                ScrollBar.vertical: StyledScrollBar {
                }

                delegate: ClickableRect {
                    id: row
                    required property var modelData
                    width: candList.width
                    height: 64

                    readonly property bool current: Novel.alMatch !== null
                        && Novel.alMatch.anilistId === row.modelData.anilistId

                    color: row.pressed ? Theme.surfaceTint
                        : (row.hovered ? Colors.withAlpha(Theme.surface, 0.8) : "transparent")
                    Behavior on color { ColorAnimation { duration: 110 } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 48
                            radius: 6
                            color: Colors.surface_container_high
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: row.modelData.cover || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                width: parent.width
                                text: row.modelData.title
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                                color: Colors.on_surface
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: [row.modelData.year > 0 ? String(row.modelData.year) : "",
                                       row.modelData.chapters > 0 ? row.modelData.chapters + " ch." : "",
                                       row.modelData.volumes > 0 ? row.modelData.volumes + " vol." : "",
                                       String(row.modelData.status || "").replace(/_/g, " ").toLowerCase()]
                                    .filter(x => x && String(x).length > 0).join(" · ")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Colors.on_surface_variant
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }

                        MaterialIcon {
                            visible: row.current
                            name: "check"
                            size: 20
                            weight: 700
                            color: Colors.primary
                        }
                    }

                    onClicked: {
                        Novel.alSetMatch(row.modelData.anilistId, row.modelData.title, function(ok, err) {
                            if (ok) root.close()
                            else root.error = err
                        })
                    }
                }
            }
        }
    }
}
