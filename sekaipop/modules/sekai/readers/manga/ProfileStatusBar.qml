import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// How the user's AniList list splits between Reading, Completed, Dropped, Planning (and Paused /
// Rereading while they hold something): one segmented bar, as wide as the page, and a legend with
// the counts under it. Display only; the counts are the Library tabs' own (Manga.overview).
//
//   ProfileStatusBar { Layout.fillWidth: true }
ColumnLayout {
    id: root

    readonly property var split: RM.statusSegments(Manga.overview ? Manga.overview.counts : null)

    visible: split.total > 0
    spacing: 8

    // Two accent colours are all a theme has, so the other lists are tonal: the accent for what is
    // being read, the second stop for what is done, greys for the ones set aside. The legend
    // names every segment, so no meaning rests on the colour alone.
    function colorFor(id) {
        switch (id) {
        case "CURRENT":   return Theme.accentMint
        case "COMPLETED": return Theme.accentCyan
        case "DROPPED":   return Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.4)
        case "PLANNING":  return Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.16)
        case "PAUSED":    return Qt.tint(Theme.accentMint, Qt.rgba(1, 1, 1, 0.55))
        case "REPEATING": return Qt.tint(Theme.accentCyan, Qt.rgba(1, 1, 1, 0.55))
        default:          return Theme.surfaceHover
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 18
        radius: 9
        color: Theme.surface
        border.width: 2
        border.color: Theme.line
        antialiasing: true

        ClippingRectangle {
            anchors { fill: parent; margins: 2 }
            radius: 7
            color: "transparent"

            // The widths are shares of 1000, so the layout hands out the room in proportion
            // (a tiny list still gets a sliver wide enough to see)
            RowLayout {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: root.split.segments

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: modelData.fraction * 1000
                        Layout.minimumWidth: 6
                        color: root.colorFor(modelData.id)

                        Rectangle {
                            visible: index > 0
                            width: 2
                            height: parent.height
                            color: Theme.line
                        }
                    }
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 16

        Repeater {
            model: root.split.segments

            delegate: Row {
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 3
                    color: root.colorFor(modelData.id)
                    border.width: 2
                    border.color: Theme.line
                    antialiasing: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: Theme.inkSub
                    font.family: Theme.fontFamily
                    font.pixelSize: ReaderType.sizeCaption
                    font.weight: ReaderType.weightBody
                    font.styleName: ReaderType.styleBody
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: RM.groupDigits(modelData.count)
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: ReaderType.sizeCaption
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                }
            }
        }
    }
}
