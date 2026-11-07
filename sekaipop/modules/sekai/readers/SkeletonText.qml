pragma ComponentBehavior: Bound
// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.

import QtQuick
import qs.modules.sekai.readers

// Placeholder page of prose while a chapter loads: a heading, the accent rule
// and paragraphs of ragged lines, set in the reader's measure and line height
// so the text replaces it in place. Ripples top to bottom. Fades out once
// `active` drops.
Rectangle {
    id: root

    property bool active: false
    property real fontSize: 17
    property real lineHeight: 1.75
    property real topInset: 56
    property real bottomInset: 56
    property real maxWidth: 720
    property color blockColor: Qt.rgba(1, 1, 1, 0.07)

    readonly property real _line: fontSize * lineHeight
    readonly property real _measure: Math.min(width - 48, maxWidth)
    // Lines per paragraph, the last of each one short.
    readonly property var _paragraphs: [5, 3, 6, 4, 2, 5, 4]

    color: "transparent"
    clip: true
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    Column {
        id: page
        width: root._measure
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topInset + 36
        spacing: 0

        // Heading
        Rectangle {
            id: heading
            width: page.width * 0.55
            height: (root.fontSize + 7) * 0.9
            radius: 5
            color: root.blockColor
        }

        Item { width: 1; height: 16 }

        Row {
            spacing: 5
            Rectangle { width: 8;  height: 2; radius: 1; color: Colors.primary; opacity: 0.2 }
            Rectangle { width: 32; height: 2; radius: 1; color: Colors.primary; opacity: 0.45 }
            Rectangle { width: 8;  height: 2; radius: 1; color: Colors.primary; opacity: 0.2 }
        }

        Item { width: 1; height: 32 }

        Repeater {
            // More than a screenful; the clip trims the rest.
            model: root.visible ? root._paragraphs.length : 0

            delegate: Column {
                id: para
                required property int index
                readonly property int lines: root._paragraphs[index]
                // Lines above this paragraph, for the ripple delay.
                readonly property int firstLine: {
                    let n = 0
                    for (let i = 0; i < index; i++) n += root._paragraphs[i]
                    return n
                }

                width: page.width
                bottomPadding: Math.round(root._line * 0.75)

                Repeater {
                    model: para.lines

                    delegate: Item {
                        id: line
                        required property int index
                        readonly property bool last: index === para.lines - 1

                        width: para.width
                        height: root._line

                        Rectangle {
                            id: bar
                            anchors.verticalCenter: parent.verticalCenter
                            width: line.last
                                ? parent.width * [0.42, 0.66, 0.3, 0.55][para.index % 4]
                                : parent.width * (0.94 + 0.06 * ((line.index + para.index) % 2))
                            height: Math.round(root.fontSize * 0.62)
                            radius: height / 2
                            color: root.blockColor
                        }

                        SkeletonPulse {
                            target: bar
                            delay: (para.firstLine + line.index) * 60
                            period: 1600
                            low: 0.35
                            running: root.visible
                        }
                    }
                }
            }
        }
    }
}
