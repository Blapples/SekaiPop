import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// What the user's list is made of, in four small bar charts in one card: the type of what they
// read (manga, manhwa, manhua, one-shot, novel), the decade it started in, the tags read most, and
// the creators read most. The first two are counted from the list already held (planning is left
// out: not read yet); the tags and creators are AniList's own statistics for the user (Manga.extras).
// AniList does not say who drew and who wrote, so the creators are one list. A creator's name opens
// their AniList page. Any group may be missing, and the card is hidden when all are.
//
//   ProfileBreakdown { Layout.fillWidth: true }
ColumnLayout {
    id: root

    readonly property var mix: Manga.overview ? Manga.overview.mix : null
    readonly property var extras: Manga.extras
    readonly property string fmt: Manga.scoreFormat

    readonly property var types:   RM.countBars(mix ? mix.types : null, 6, fmt)
    readonly property var decades: RM.countBars(mix ? mix.decades : null, 7, fmt)
    readonly property var tags:    RM.countBars(extras ? extras.tags : null, 8, fmt)
    readonly property var staff:   RM.countBars(extras ? extras.staff : null, 8, fmt)

    // [title, rows] for the groups that have something, so the dividers only sit between two
    readonly property var groups: {
        const all = [
            { title: "Type",                    rows: types,   wide: false },
            { title: "Decade",                  rows: decades, wide: false },
            { title: "Tags you read most",      rows: tags,    wide: false },
            { title: "Creators you read most",  rows: staff,   wide: true  }
        ]
        return all.filter(function(g) { return g.rows.length > 0 })
    }

    visible: groups.length > 0
    spacing: 6

    ProfileHeading {
        title: "Breakdown"
        hint: "What your list is made of"
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: inner.implicitHeight + 32 + Theme.shadowOffset

        Pill {
            anchors.fill: parent
            cornerRadius: 18
            ringWidth: Theme.borderWidth
            innerRing: Theme.cardRing
            fillColor: Theme.surface

            ColumnLayout {
                id: inner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 14

                Repeater {
                    model: root.groups

                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // A line between one group and the next
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 2
                            Layout.bottomMargin: 6
                            visible: index > 0
                            color: Theme.line
                            opacity: 0.3
                        }

                        Text {
                            text: modelData.title
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            font.styleName: Theme.fontStyleBold
                        }

                        ProfileBars {
                            Layout.fillWidth: true
                            rows: modelData.rows
                            labelWidth: modelData.wide ? 130 : 96
                        }
                    }
                }
            }
        }
    }
}
