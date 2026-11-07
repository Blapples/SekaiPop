pragma ComponentBehavior: Bound
// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.

import QtQuick
import qs.modules.sekai.readers

// Placeholder poster grid shown while a cover grid's first page loads. Lays
// out like the real grid (same columns, card ratio and inset) so the covers
// land where the ghosts were, and ripples in a diagonal wave. Fades out once
// `active` drops.
Rectangle {
    id: root

    property bool active: false
    property int columns: 4
    // Cell height / cell width, as the real grid's cellHeight.
    property real ratio: 1.58
    property real padding: 10
    property real cellWidth: (width - padding * 2) / columns
    // Height of an extra bottom strip (the library's progress row).
    property int footerHeight: 0

    readonly property real _cellHeight: cellWidth * ratio
    readonly property int _rows: _cellHeight > 0
        ? Math.ceil((height - padding) / _cellHeight) : 0

    color: Colors.background
    clip: true
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    Grid {
        x: root.padding
        y: root.padding
        columns: root.columns

        Repeater {
            model: root.visible ? root._rows * root.columns : 0

            delegate: Item {
                id: cell
                required property int index
                readonly property int col: index % root.columns
                readonly property int row: Math.floor(index / root.columns)

                width: root.cellWidth
                height: root._cellHeight

                Rectangle {
                    id: card
                    anchors { fill: parent; margins: 5 }
                    radius: 13
                    color: Colors.frame
                    // the same outline the real cards have
                    border.width: 3
                    border.color: Colors.line

                    // Cover
                    Rectangle {
                        anchors {
                            top: parent.top; left: parent.left; right: parent.right
                            bottom: lines.top; bottomMargin: 10
                            margins: 3
                        }
                        radius: card.radius - 3
                        color: Colors.surface_container_high
                    }

                    // Title
                    Column {
                        id: lines
                        anchors {
                            left: parent.left; right: parent.right
                            bottom: parent.bottom
                            leftMargin: 10; rightMargin: 10
                            bottomMargin: 10 + root.footerHeight
                        }
                        spacing: 6

                        Rectangle {
                            width: parent.width * (cell.index % 3 === 1 ? 0.9 : 0.75)
                            height: 7; radius: 3.5
                            color: Colors.surface_container_highest
                        }
                        Rectangle {
                            width: parent.width * (cell.index % 2 ? 0.4 : 0.55)
                            height: 7; radius: 3.5
                            color: Colors.surface_container_highest
                        }
                    }

                    // Progress row
                    Rectangle {
                        visible: root.footerHeight > 0
                        anchors {
                            left: parent.left; right: parent.right
                            bottom: parent.bottom
                            leftMargin: 10; rightMargin: 10
                            bottomMargin: (root.footerHeight - height) / 2
                        }
                        height: 3; radius: 1.5
                        color: Colors.surface_container_highest
                    }
                }

                SkeletonPulse {
                    target: card
                    delay: (cell.col + cell.row) * 110
                    running: root.visible
                }
            }
        }
    }
}
