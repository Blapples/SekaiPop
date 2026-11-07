import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.sekai.readers

// Rows of labelled bars, the way the genres are drawn in Taste: a name, a bar as wide as the
// biggest row, and a note at the end. `rows` comes from RM.countBars ({ label, count, fraction,
// note, url }). A row with a `url` is a link: it is underlined under the pointer and opens it.
//
//   ProfileBars { Layout.fillWidth: true; rows: RM.countBars(mix.types, 6) }
ColumnLayout {
    id: root

    property var rows: []
    property int labelWidth: 96

    visible: rows.length > 0
    spacing: 8

    Repeater {
        model: root.rows

        delegate: RowLayout {
            id: line
            Layout.fillWidth: true
            spacing: 10

            readonly property bool link: modelData.url.length > 0

            Text {
                Layout.preferredWidth: root.labelWidth
                text: modelData.label
                color: Theme.ink
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: ReaderType.sizeCaption + 1
                font.weight: ReaderType.weightTitle
                font.styleName: ReaderType.styleTitle
                font.underline: line.link && tap.containsMouse

                MouseArea {
                    id: tap
                    anchors.fill: parent
                    enabled: line.link
                    hoverEnabled: true
                    cursorShape: line.link ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }

            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.preferredHeight: 12
                radius: 6
                color: Theme.surfaceHover
                antialiasing: true

                Rectangle {
                    width: Math.max(12, track.width * modelData.fraction)
                    height: parent.height
                    radius: 6
                    antialiasing: true
                    border.width: 2
                    border.color: Theme.line

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.accentMint }
                        GradientStop { position: 1.0; color: Theme.accentCyan }
                    }

                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
            }

            Text {
                Layout.preferredWidth: 84
                horizontalAlignment: Text.AlignRight
                text: modelData.note
                color: Theme.inkSub
                elide: Text.ElideLeft
                font.family: Theme.fontFamily
                font.pixelSize: ReaderType.sizeCaption
                font.weight: ReaderType.weightBody
                font.styleName: ReaderType.styleBody
            }
        }
    }
}
