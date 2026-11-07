import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// A row of covers under a heading, for the shelves of the profile page (Almost done, Stalled,
// Up next, Recent activity, and the recommendations). Hidden while it has nothing to show.
//
//   ProfileShelf {
//       Layout.fillWidth: true
//       kind: "almost"; title: "Almost done"; hint: "5 chapters or fewer to go"
//       rows: Manga.overview.almostDone
//       onPicked: function(id) { ... }
//   }
//
// `kind` picks what is on the covers: "almost", "stalled" and "feed" put a strip with the note from
// RM.shelfNote under the cover (chapters left; the chapter you stopped at and the days idle; what
// the update said and how long ago); "planning" and "recs" put the community score on the cover as a
// stamp, with the type and year under it.
ColumnLayout {
    id: root

    property string kind: "almost"
    property string title: ""
    property string hint: ""
    property var rows: []

    readonly property int cellW: 124
    readonly property int cellH: Math.round(cellW * 1.72)
    // A note strip under the cover, or the score stamp with the type and year
    readonly property bool strip: kind === "almost" || kind === "stalled" || kind === "feed"

    signal picked(string mangaId)

    visible: rows.length > 0
    spacing: 6

    ProfileHeading {
        title: root.title
        hint: root.hint
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: root.cellH
        orientation: ListView.Horizontal
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows

        delegate: Item {
            id: cell
            width: root.cellW
            height: root.cellH

            readonly property var row: modelData

            CoverCard {
                anchors.fill: parent
                source: row.image || ""
                title: row.title || ""
                subtitle: root.strip ? "" : ((row.type || "") + (row.year > 0 ? " \u00b7 " + row.year : ""))
                gradientHeight: 48
                footerHeight: root.strip ? 30 : 0

                CoverProgressBar {
                    visible: root.strip
                    height: 30
                    rowSpacing: 6
                    started: true
                    label: RM.shelfNote(root.kind, row)
                }

                // The one bright thing on a Planning cover is AniList's own score
                ReaderBadge {
                    visible: !root.strip && RM.communityScoreText(row.avg).length > 0
                    anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                    rotation: -4
                    text: "\u2605 " + RM.communityScoreText(row.avg)
                    fill: Theme.accentMint
                }

                onClicked: root.picked(row.id)
            }
        }
    }
}
