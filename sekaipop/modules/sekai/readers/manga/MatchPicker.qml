import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// Picks which WeebCentral series a title's chapters come from. It opens with the best name
// matches for the title; typing searches WeebCentral for that text instead. A pick is kept
// (anilist_matches.json) until you change it, and "Use automatic match" lets go of it.
//
//   MatchPicker { id: picker; anchors.fill: parent; anilistId: ...; hasManual: ... }
//   picker.open()
Item {
    id: root

    property int anilistId: 0
    // True when the current match was picked by hand (so there is one to let go of)
    property bool hasManual: false

    signal closed()

    property string _lastQuery: ""

    visible: false

    function open() {
        _lastQuery = ""
        search.clear()
        visible = true
        Manga.fetchMatchCandidates(root.anilistId, "")
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
                    text: "Which " + Manga.providerLabel + " series?"
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
                        Manga.clearMatch(root.anilistId)
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
                placeholder: "Search " + Manga.providerLabel + "…"
                onTextChanged: debounce.restart()
            }

            Timer {
                id: debounce
                interval: 350
                onTriggered: {
                    const t = search.text.trim()
                    if (t === root._lastQuery) return
                    root._lastQuery = t
                    Manga.fetchMatchCandidates(root.anilistId, t)
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
                active: Manga.isFetchingCandidates
                rowHeight: 64
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 48
                z: 4
                visible: !Manga.isFetchingCandidates
                         && (Manga.candidatesError.length > 0 || Manga.matchCandidates.length === 0)
                text: Manga.candidatesError.length > 0 ? Manga.candidatesError : "No series found"
                color: Manga.candidatesError.length > 0 ? Colors.error : Colors.on_surface_variant
                font.pixelSize: 12
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            ListView {
                id: candList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Manga.matchCandidates

                ScrollBar.vertical: StyledScrollBar {
                }

                delegate: ClickableRect {
                    id: row
                    width: candList.width
                    height: 64

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
                                source: modelData.thumbUrl || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                width: parent.width
                                text: modelData.title
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                                color: Colors.on_surface
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: [modelData.type, modelData.year, modelData.status]
                                    .filter(x => x && String(x).length > 0).join(" · ")
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Colors.on_surface_variant
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }

                        // How close the name is, when it was worked out
                        ReaderBadge {
                            visible: (modelData.score || 0) > 0
                            rotation: 0
                            text: Math.round((modelData.score || 0) * 100) + "%"
                            fill: modelData.score >= 0.88 ? Theme.accentMint : Theme.surfaceHover
                        }
                    }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left; right: parent.right
                            leftMargin: 62; rightMargin: 16
                        }
                        height: 1; color: Colors.outline_variant; opacity: 0.25
                    }

                    onClicked: {
                        Manga.setMatch(root.anilistId, modelData.id, modelData.title)
                        root.close()
                    }
                }
            }
        }
    }
}
