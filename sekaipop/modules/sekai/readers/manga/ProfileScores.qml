import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// How the user scores things: one column per point of their own score scale (1 to 10, stars, or
// smileys, whichever their AniList uses), as tall as the number of titles that hold that score.
// The busiest score is lit. Hidden until something is scored.
//
//   ProfileScores { Layout.fillWidth: true }
ColumnLayout {
    id: root

    readonly property var overview: Manga.overview
    readonly property var dist: RM.scoreBars(overview ? overview.scoreDist : null, Manga.scoreFormat)
    readonly property real barMax: 84

    visible: dist.rated > 0
    spacing: 6

    ProfileHeading {
        title: "Scores"
        hint: "How you rate things \u00b7 " + RM.groupDigits(root.dist.rated) + " scored"
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

            RowLayout {
                id: inner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 6

                Repeater {
                    model: root.dist.bars

                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 4

                        readonly property bool peak: index === root.dist.peak

                        // The number of titles, over its column (blank for a score nobody has)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.count > 0 ? modelData.count : ""
                            color: parent.peak ? Theme.ink : Theme.inkSub
                            font.family: Theme.fontFamily
                            font.pixelSize: ReaderType.sizeCaption
                            font.weight: parent.peak ? Font.ExtraBold : ReaderType.weightBody
                            font.styleName: parent.peak ? Theme.fontStyleBold : ReaderType.styleBody
                        }

                        // The column grows up from a common floor
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.barMax

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: Math.min(34, parent.width - 4)
                                height: modelData.count > 0 ? Math.max(8, root.barMax * modelData.fraction) : 3
                                radius: 6
                                antialiasing: true
                                border.width: modelData.count > 0 ? 2 : 0
                                border.color: Theme.line
                                color: modelData.count === 0
                                    ? Theme.surfaceHover
                                    : Qt.rgba(Theme.accentMint.r, Theme.accentMint.g, Theme.accentMint.b, peak ? 1 : 0.55)

                                Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            color: Theme.inkSub
                            font.family: Theme.fontFamily
                            font.pixelSize: ReaderType.sizeCaption
                            font.weight: ReaderType.weightBody
                            font.styleName: ReaderType.styleBody
                        }
                    }
                }
            }
        }
    }
}
