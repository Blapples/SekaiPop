import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// The title's place on the user's AniList list: the status (Reading, Planning, ...) and how
// many chapters are read. It is what Manga.trackInfo holds; Save sends exactly these two values
// (they may be lower than what AniList has, unlike the automatic update, which only goes up).
// It covers the detail page like MatchPicker.
//
//   TrackSheet { id: sheet; anchors.fill: parent }
//   sheet.open()
Item {
    id: root

    signal closed()

    property string draftStatus: "CURRENT"
    property int    draftProgress: 0

    readonly property var  _info: Manga.trackInfo
    readonly property int  _total: _info ? (_info.chapters || 0) : 0
    readonly property int  _cap: _total > 0 ? _total : 99999

    visible: false

    function open() {
        const e = root._info ? root._info.entry : null
        Manga.trackError = ""
        root.draftStatus = e && e.status ? e.status : "CURRENT"
        root.draftProgress = e ? (e.progress || 0)
            : (Manga.currentManga ? RM.trackProgress(Manga.currentManga.chapters, Manga.isChapterRead).progress : 0)
        visible = true
        Manga.trackFetch()
    }

    function close() {
        visible = false
        root.closed()
    }

    function _step(d) {
        root.draftProgress = Math.max(0, Math.min(root._cap, root.draftProgress + d))
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
                    text: "AniList"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    color: Theme.ink
                    elide: Text.ElideRight
                }

                ReaderChip {
                    visible: root._info !== null && (root._info.siteUrl || "").length > 0
                    icon: "link"
                    text: "Open on AniList"
                    onClicked: Qt.openUrlExternally(root._info.siteUrl)
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
            contentHeight: page.implicitHeight + 40

            ColumnLayout {
                id: page
                width: Math.min(flick.width - 48, 460)
                x: (flick.width - width) / 2
                y: 24
                spacing: 16

                StyledText {
                    Layout.fillWidth: true
                    text: Manga.currentManga ? Manga.currentManga.title : ""
                    font.pixelSize: 15
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root._info !== null && root._info.entry === null
                    text: "Not on your AniList yet. Saving puts it on your list."
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                StyledText {
                    text: "Status"
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: Manga.trackStatuses

                        delegate: ReaderChip {
                            required property var modelData
                            text: modelData.label
                            lit: root.draftStatus === modelData.id
                            onClicked: root.draftStatus = modelData.id
                        }
                    }
                }

                StyledText {
                    text: "Chapters read"
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ReaderKey {
                        label: "\u2212"
                        enabled: root.draftProgress > 0
                        onClicked: root._step(-1)
                    }

                    StickerText {
                        text: String(root.draftProgress)
                        pixelSize: 22
                        fillColor: Theme.accentMint
                    }

                    ReaderKey {
                        label: "+"
                        enabled: root.draftProgress < root._cap
                        onClicked: root._step(1)
                    }

                    StyledText {
                        visible: root._total > 0
                        text: "of " + root._total
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }

                    Item { Layout.fillWidth: true }

                    ReaderChip {
                        icon: "check_read"
                        text: "From read chapters"
                        onClicked: root.draftProgress = Math.min(root._cap,
                            RM.trackProgress(Manga.currentManga ? Manga.currentManga.chapters : [], Manga.isChapterRead).progress)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Manga.trackError.length > 0
                    text: Manga.trackError
                    color: Colors.error
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    spacing: 10

                    ReaderChip {
                        text: Manga.trackBusy ? "Saving\u2026" : "Save"
                        lit: true
                        enabled: !Manga.trackBusy
                        onClicked: Manga.trackSet(root.draftStatus, root.draftProgress,
                                                  function(ok) { if (ok) root.close() })
                    }

                    ReaderChip {
                        text: "Cancel"
                        onClicked: root.close()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Manga.trackAuto
                        ? "While \u201cUpdate as I read\u201d is on, finishing a chapter raises this number by itself and never lowers it."
                        : "\u201cUpdate as I read\u201d is off: nothing is sent unless you save here. Turn it on in the AniList page."
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    opacity: 0.8
                }
            }
        }
    }
}
