// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

Item {
    id: libraryView

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal novelSelected(string novelId)

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Novel.libraryList.length === 0 && Novel.libraryLoaded

            EmptyState {
                title: "Your library is empty"
                subtitle: "Open any novel and tap  + Library"
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
            }
        }


        SkeletonGrid {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !Novel.libraryLoaded
            active: !Novel.libraryLoaded
            padding: 8
            ratio: 1.72
            footerHeight: 30
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Novel.libraryList.length > 0
            topMargin: 10; leftMargin: 8; rightMargin: 8; bottomMargin: 10
            cellWidth: Math.floor((width - leftMargin - rightMargin) / 4)
            cellHeight: cellWidth * 1.72
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Novel.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                CoverCard {
                    anchors.fill: parent
                    source: modelData.coverUrl || ""
                    title: modelData.title || ""
                    bodyFont: libraryView.fontBody
                    gradientHeight: 52
                    footerHeight: 30

                    CoverProgressBar {
                        height: 30
                        rowSpacing: 6
                        bodyFont: libraryView.fontBody
                        started: modelData.lastReadChapterNum
                        label: modelData.lastReadChapterNum
                                ? "Ch. " + modelData.lastReadChapterNum
                                : "Not started"
                    }

                    onClicked: {
                        Novel.fetchNovelDetail(modelData.id)
                        libraryView.novelSelected(modelData.id)
                    }
                }
            }
        }
    }
}
