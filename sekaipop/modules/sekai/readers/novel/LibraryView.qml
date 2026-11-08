// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM
import "../NovelMath.js" as NM

// The Library: the novels saved with + Library, as covers, built like the manga panel's Saved
// grid: the whole title over the foot of the art on a dark fade, the chapter you are at in the
// strip under it, and a small tag at the top right saying which source the novel is read from
// (a saved novel keeps the source it was saved from).
Item {
    id: libraryView

    // Covers per row: four on the side card, more as the panel gets wider (full window).
    readonly property int gridColumns: RM.gridColumns(libGrid.width - libGrid.leftMargin - libGrid.rightMargin, 190, 4, 10)

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal novelSelected(string novelId)

    Rectangle { anchors.fill: parent; color: Colors.background }

    // Empty state
    Item {
        anchors.fill: parent
        visible: Novel.libraryList.length === 0 && Novel.libraryLoaded

        EmptyState {
            title: "Your library is empty"
            subtitle: "Open any novel and tap  + Library"
            displayFont: libraryView.fontDisplay
            bodyFont: libraryView.fontBody
        }
    }

    // Loading (first open before the file is read)
    SkeletonGrid {
        anchors.fill: parent
        visible: !Novel.libraryLoaded
        active: !Novel.libraryLoaded
        columns: libraryView.gridColumns
        padding: 8
        ratio: 1.72
        footerHeight: 30
    }

    GridView {
        id: libGrid
        // Held at the width the move ends at while the panel changes width, so the covers are
        // already their final size on the first frame (the manga grids do the same).
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: ReaderEnv.panelResizing ? Math.max(0, Math.round(ReaderEnv.panelBodyTarget))
                                       : parent.width
        visible: Novel.libraryList.length > 0
        topMargin: 10; leftMargin: 8; rightMargin: 8; bottomMargin: 10
        cellWidth: Math.floor((width - leftMargin - rightMargin) / libraryView.gridColumns)
        cellHeight: cellWidth * 1.72
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: Novel.libraryList

        ScrollBar.vertical: StyledScrollBar {
        }

        delegate: Item {
            width: libGrid.cellWidth
            height: libGrid.cellHeight

            readonly property var libEntry: modelData

            CoverCard {
                anchors.fill: parent
                source: libEntry.coverUrl || ""
                title: libEntry.title || ""
                bodyFont: libraryView.fontBody
                fullTitle: true
                holdTitle: false
                gradientHeight: 48
                footerHeight: 30

                CoverProgressBar {
                    height: 30
                    rowSpacing: 6
                    bodyFont: libraryView.fontBody
                    started: libEntry.lastReadChapterNum
                    label: libEntry.lastReadChapterNum
                            ? "Ch. " + libEntry.lastReadChapterNum
                            : "Not started"
                }

                // Which source this saved novel is read from (its id says so)
                ReaderBadge {
                    readonly property string _tag: NM.sourceTag(Novel.sourceNameFor(libEntry.id))
                    visible: _tag.length > 0
                    anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                    implicitHeight: 20
                    rotation: 0
                    text: _tag
                    fill: ReaderType.tagFill
                    ink: ReaderType.tagInk
                    outline: "transparent"
                }

                onClicked: {
                    Novel.fetchNovelDetail(libEntry.id)
                    libraryView.novelSelected(libEntry.id)
                }
            }
        }
    }
}
