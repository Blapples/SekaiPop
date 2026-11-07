import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// The row of big numbers under the profile card that the card itself has no room for: volumes
// read, titles completed, titles scored, and chapters per title. (The card already holds chapters
// read, mean score and titles tracked.) Display only; all of it is the profile's and the list's
// own figures (Manga.profile, Manga.overview), so it asks AniList for nothing.
//
//   ProfileStats { Layout.fillWidth: true }
Item {
    id: root

    readonly property var profile: Manga.profile
    readonly property var overview: Manga.overview
    readonly property var dist: RM.scoreBars(overview ? overview.scoreDist : null, Manga.scoreFormat)
    readonly property var cells: RM.statStripCells(profile ? profile.stats : null, overview ? overview.counts : null, dist.rated)

    // Nothing to show until either half has come
    visible: profile !== null || overview !== null

    implicitHeight: 64 + 2 * Theme.borderWidth + Theme.shadowOffset

    Pill {
        anchors.fill: parent
        cornerRadius: 18
        ringWidth: Theme.borderWidth
        innerRing: Theme.cardRing
        fillColor: Theme.surface

        Row {
            anchors { fill: parent; margins: Theme.borderWidth }
            anchors.bottomMargin: Theme.borderWidth + Theme.shadowOffset

            Repeater {
                model: root.cells

                delegate: Item {
                    width: parent.width / root.cells.length
                    height: parent.height

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
                        visible: index < root.cells.length - 1
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
