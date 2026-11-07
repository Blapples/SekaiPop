import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// "Pick something for me": one random title from the user's Planning list, shown as a cover card
// with its facts, with "Not this one" to draw another and "Open" to go to it. The Planning list
// is long enough that nobody scrolls it; this is the way out of it.
//
//   ProfilePick { Layout.fillWidth: true; onMangaSelected: ... }
//
// The draw is the backend's (Manga.fetchPick); nothing is asked until the user taps.
ColumnLayout {
    id: root

    // The picked title was opened: the parent shows it
    signal mangaSelected(string mangaId)

    readonly property var entry: Manga.pickEntry
    readonly property int planningCount: Manga.overview && Manga.overview.counts ? (Manga.overview.counts.PLANNING || 0) : 0
    property bool asked: false

    readonly property int cellW: 124
    readonly property int cellH: Math.round(cellW * 1.72)

    // "Manga \u00b7 Releasing \u00b7 2021", "Romance \u00b7 Drama \u00b7 Sports", "164/250 chapters read" ...
    readonly property string metaLine: {
        const e = entry
        if (!e) return ""
        const bits = []
        if (e.type) bits.push(e.type)
        if (e.status) bits.push(e.status)
        if (e.year > 0) bits.push(String(e.year))
        return bits.join(" \u00b7 ")
    }
    readonly property string sizeLine: entry ? RM.sizeText(entry.chapters, entry.volumes) : ""
    readonly property string genreLine: entry && entry.genres ? entry.genres.slice(0, 4).join(" \u00b7 ") : ""
    readonly property string avgLine: {
        const t = entry ? RM.communityScoreText(entry.avg) : ""
        return t.length > 0 ? "\u2605 " + t + " on AniList" : ""
    }

    visible: planningCount > 0 || entry !== null || Manga.pickBusy
    spacing: 6

    function pick() {
        asked = true
        Manga.fetchPick()
    }

    function openPicked() {
        if (!entry) return
        Manga.fetchMangaDetail(entry.id)
        root.mangaSelected(entry.id)
    }

    ProfileHeading {
        title: "Can't decide?"
        hint: root.planningCount > 0 ? "A random title from your Planning list \u00b7 " + RM.groupDigits(root.planningCount)
                                     : "A random title from your Planning list"
    }

    // Before the first draw (and when Planning turns out to be empty)
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 84
        visible: root.entry === null
        radius: 13
        color: Theme.surface
        antialiasing: true

        RowLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: Manga.pickError.length > 0 ? Manga.pickError
                    : (root.asked && !Manga.pickBusy ? "Nothing in your Planning list to pick from."
                                                     : "Not sure what to read next? Let the list decide.")
                color: Manga.pickError.length > 0 ? Colors.error : Theme.inkSub
                font.family: Theme.fontFamily
                font.pixelSize: ReaderType.sizeCaption + 1
                font.weight: ReaderType.weightBody
                font.styleName: ReaderType.styleBody
                lineHeight: 1.3
            }

            ReaderChip {
                Layout.alignment: Qt.AlignVCenter
                icon: "shuffle"
                text: Manga.pickBusy ? "Picking\u2026" : (Manga.pickError.length > 0 ? "Retry" : "Pick something for me")
                lit: true
                enabled: !Manga.pickBusy
                onClicked: root.pick()
            }
        }
    }

    // The pick
    RowLayout {
        Layout.fillWidth: true
        visible: root.entry !== null
        spacing: 10

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: root.cellW
            Layout.preferredHeight: root.cellH

            CoverCard {
                anchors.fill: parent
                source: root.entry ? (root.entry.image || "") : ""
                title: root.entry ? (root.entry.title || "") : ""
                subtitle: root.entry ? (root.entry.type || "") : ""
                gradientHeight: 48
                opacity: Manga.pickBusy ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }

                onClicked: root.openPicked()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 8
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: root.entry ? (root.entry.title || "") : ""
                color: Theme.ink
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: ReaderType.sizeTitle
                font.weight: ReaderType.weightTitle
                font.styleName: ReaderType.styleTitle
                lineHeight: 1.1
            }

            Repeater {
                model: [root.metaLine, root.sizeLine, root.genreLine, root.avgLine]

                delegate: Text {
                    Layout.fillWidth: true
                    visible: modelData.length > 0
                    text: modelData
                    color: Theme.inkSub
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: ReaderType.sizeBody
                    font.weight: ReaderType.weightBody
                    font.styleName: ReaderType.styleBody
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 10

                ReaderChip {
                    icon: "link"
                    text: "Open"
                    lit: true
                    onClicked: root.openPicked()
                }

                ReaderChip {
                    icon: "shuffle"
                    text: Manga.pickBusy ? "Picking\u2026" : "Not this one"
                    enabled: !Manga.pickBusy
                    onClicked: root.pick()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: Manga.pickError.length > 0
                text: Manga.pickError
                color: Colors.error
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: ReaderType.sizeCaption
            }
        }
    }
}
