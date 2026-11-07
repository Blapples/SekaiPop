import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// The user's taste: the genres they read most (bars, from AniList's own statistics) and a
// heatmap of the days they updated their list over the last 26 weeks (Manga.activity). One
// card. Either half may be missing (a new account has no genres, the heatmap is asked on its
// own and may fail), and the card shows what there is.
//
//   ProfileTaste { Layout.fillWidth: true }
ColumnLayout {
    id: root

    readonly property var profile: Manga.profile
    readonly property var bars: RM.genreBars(profile ? profile.genres : null, 6, Manga.scoreFormat)
    readonly property var activity: Manga.activity
    // Built once per answer: the days are the machine's own, like the backend's
    readonly property var grid: activity ? RM.activityGrid(activity.counts || ({}), new Date(), 26) : null
    readonly property var marks: grid ? RM.monthMarks(grid) : []
    // Streaks and totals of the same days (list updates: AniList folds a run of chapters of one title into one)
    readonly property var dayStats: grid ? RM.activityStats(grid, new Date()) : null
    readonly property var dayCells: dayStats ? [
        { value: String(dayStats.current), label: "Day streak" },
        { value: String(dayStats.longest), label: "Longest" },
        { value: String(dayStats.week),    label: "This week" },
        { value: String(dayStats.month),   label: "This month" }
    ] : []

    visible: bars.length > 0 || grid !== null
    spacing: 6

    ProfileHeading {
        title: "Taste"
        hint: "What you read most, and when"
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

                // ── Genres ──
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.bars.length > 0
                    spacing: 8

                    Repeater {
                        model: root.bars

                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                Layout.preferredWidth: 86
                                text: modelData.genre
                                color: Theme.ink
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: ReaderType.sizeCaption + 1
                                font.weight: ReaderType.weightTitle
                                font.styleName: ReaderType.styleTitle
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
                                text: modelData.count + (modelData.meanText.length > 0 ? "  \u00b7  \u2605 " + modelData.meanText : "")
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

                // A line between the two halves
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    visible: root.bars.length > 0 && root.grid !== null
                    color: Theme.line
                    opacity: 0.3
                }

                // ── Heatmap ──
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.grid !== null
                    spacing: 8

                    Item {
                        id: heat
                        Layout.fillWidth: true

                        readonly property int weeks: root.grid ? root.grid.weeks : 26
                        readonly property real gap: 3
                        readonly property real labelsH: 14
                        // The cells grow with the card (between 8 and 20 px)
                        readonly property real cell: Math.max(8, Math.min(20, Math.floor((width - (weeks - 1) * gap) / weeks)))
                        readonly property real pitch: cell + gap
                        property var hovered: null

                        Layout.preferredHeight: labelsH + 7 * pitch - gap

                        // Month names over the first column of each month
                        Repeater {
                            model: root.marks

                            delegate: Text {
                                x: modelData.col * heat.pitch
                                y: 0
                                text: modelData.label
                                color: Theme.inkSub
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: ReaderType.weightBody
                                font.styleName: ReaderType.styleBody
                            }
                        }

                        Repeater {
                            model: root.grid ? root.grid.cells : []

                            delegate: Rectangle {
                                x: modelData.col * heat.pitch
                                y: heat.labelsH + modelData.row * heat.pitch
                                width: heat.cell
                                height: heat.cell
                                radius: Math.max(2, Math.round(heat.cell / 4))
                                antialiasing: true
                                visible: !modelData.future
                                color: modelData.level === 0
                                    ? Theme.surfaceHover
                                    : Qt.rgba(Theme.accentMint.r, Theme.accentMint.g, Theme.accentMint.b, 0.25 + 0.25 * modelData.level)
                                border.width: heat.hovered && heat.hovered.key === modelData.key ? 2 : 0
                                border.color: Theme.line
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton

                            onPositionChanged: function(m) {
                                const col = Math.floor(m.x / heat.pitch)
                                const row = Math.floor((m.y - heat.labelsH) / heat.pitch)
                                const cells = root.grid ? root.grid.cells : []
                                const c = (col >= 0 && col < heat.weeks && row >= 0 && row < 7) ? cells[col * 7 + row] : null
                                heat.hovered = (c && !c.future) ? c : null
                            }
                            onExited: heat.hovered = null
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: heat.hovered ? RM.dayText(heat.hovered)
                            : (root.grid ? RM.activityCaption(root.grid) + (root.activity && root.activity.capped ? " (the newest are shown)" : "") : "")
                        color: Theme.inkSub
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: ReaderType.sizeCaption
                        font.weight: ReaderType.weightBody
                        font.styleName: ReaderType.styleBody
                    }

                    // ── Streaks and totals ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: root.dayStats !== null && root.dayStats.longest > 0
                        spacing: 0

                        Repeater {
                            model: root.dayCells

                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 1

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.value
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.weight: Font.ExtraBold
                                    font.styleName: Theme.fontStyleBold
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

                    Text {
                        Layout.fillWidth: true
                        visible: root.dayStats !== null && root.dayStats.busiest !== null
                        horizontalAlignment: Text.AlignHCenter
                        text: root.dayStats && root.dayStats.busiest ? "Busiest day: " + RM.dayText(root.dayStats.busiest) : ""
                        color: Theme.inkSub
                        elide: Text.ElideRight
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
