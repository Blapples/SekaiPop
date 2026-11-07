import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers
import "../ReaderMath.js" as RM

// The reading settings, a card that drops from the bar: the reading mode, the manhwa switch,
// the page colour, the zoom, saving the page on screen. The reader (`host`) does the work;
// what is kept between sessions is MangaPrefs'.
Item {
    id: root

    property var host: null
    property bool shown: false

    readonly property real cardWidth: 304
    readonly property real maxHeight: root.parent ? root.parent.height - 96 : 640

    width: cardWidth
    height: Math.min(col.implicitHeight + 32 + Theme.shadowOffset, root.maxHeight)

    opacity: root.shown ? 1 : 0
    visible: root.opacity > 0.01
    scale: root.shown ? 1 : 0.94
    transformOrigin: Item.TopRight
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

    component SectionLabel: Text {
        width: parent ? parent.width : 100
        topPadding: 6
        color: Theme.inkSub
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 1.4
        font.weight: Font.ExtraBold
        font.styleName: Theme.fontStyleBold
    }

    // Swallow clicks that fall on the card, so they do not reach the page behind it.
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Pill {
        id: card
        anchors.fill: parent
        cornerRadius: 22
        ringWidth: Theme.borderWidth
        innerRing: Theme.cardRing
        fillColor: Theme.surface

        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: 16
            anchors.bottomMargin: 16 + Theme.shadowOffset
            contentHeight: col.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: scroller.width
                spacing: 4

                // ── Reading mode ──────────────────────────────────────────────
                SectionLabel { text: "READING MODE" }

                Repeater {
                    model: RM.MODES

                    delegate: ReaderMenuRow {
                        required property var modelData

                        width: col.width
                        icon: modelData.icon
                        text: modelData.label
                        checked: root.host !== null && root.host.modeId === modelData.id
                        onClicked: root.host.pickMode(modelData.id)
                    }
                }

                Text {
                    visible: root.host !== null && MangaPrefs.auto && root.host.kind === true
                    width: col.width
                    topPadding: 2
                    wrapMode: Text.Wrap
                    text: "This is a long-strip series, so the mode you pick is kept for those."
                    color: Theme.inkSub
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    lineHeight: 1.25
                }

                SectionLabel { text: "OPTIONS" }

                ReaderMenuRow {
                    width: col.width
                    icon: "bolt"
                    text: "Manhwa opens as a long strip"
                    checked: MangaPrefs.auto
                    onClicked: MangaPrefs.setAuto(!MangaPrefs.auto)
                }

                ReaderMenuRow {
                    width: col.width
                    icon: "book_bookmark"
                    text: "Tablet: first page alone"
                    checked: MangaPrefs.spreadCover
                    onClicked: MangaPrefs.setSpreadCover(!MangaPrefs.spreadCover)
                }

                // ── Background ────────────────────────────────────────────────
                SectionLabel { text: "BACKGROUND" }

                Row {
                    width: col.width
                    spacing: 0

                    Repeater {
                        model: RM.BACKGROUNDS

                        delegate: Item {
                            id: sw

                            required property var modelData

                            readonly property bool picked: MangaPrefs.background === sw.modelData.id

                            width: col.width / RM.BACKGROUNDS.length
                            height: 58

                            Rectangle {
                                id: dot
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 3
                                width: 32
                                height: 32
                                radius: 16
                                antialiasing: true
                                color: root.host ? root.host.bgColorFor(sw.modelData.id) : "black"
                                border.width: sw.picked ? 3 : 2
                                border.color: sw.picked ? Theme.accentMint : Theme.line
                                scale: swArea.containsMouse ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: sw.picked
                                    name: "check_circle"
                                    fill: 1
                                    size: 16
                                    color: dot.color.hslLightness > 0.55 ? "#1a1a1f" : "white"
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 40
                                text: sw.modelData.label
                                color: sw.picked ? Theme.ink : Theme.inkSub
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: sw.picked ? Font.ExtraBold : Font.Bold
                            }

                            MouseArea {
                                id: swArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MangaPrefs.setBackground(sw.modelData.id)
                            }
                        }
                    }
                }

                // ── Zoom ──────────────────────────────────────────────────────
                SectionLabel { text: "ZOOM" }

                Row {
                    spacing: 8
                    height: 40

                    ReaderKey {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "magnifer_zoom_out"
                        enabled: root.host !== null && root.host.zoom > root.host.minZoom + 0.001
                        onClicked: root.host.zoomBy(-1)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        horizontalAlignment: Text.AlignHCenter
                        text: root.host ? Math.round(root.host.zoom * 100) + "%" : "100%"
                        color: Theme.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.ExtraBold
                        font.styleName: Theme.fontStyleBold
                    }

                    ReaderKey {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "magnifer_zoom_in"
                        enabled: root.host !== null && root.host.zoom < root.host.maxZoom - 0.001
                        onClicked: root.host.zoomBy(1)
                    }

                    ReaderChip {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "restart"
                        text: "Reset"
                        enabled: root.host !== null && Math.abs(root.host.zoom - 1) > 0.001
                        onClicked: root.host.resetZoom()
                    }
                }

                // ── Page ──────────────────────────────────────────────────────
                SectionLabel { text: "PAGE" }

                ReaderChip {
                    icon: "download_minimalistic"
                    text: root.host && root.host.shown.length > 1 ? "Save these pages" : "Save this page"
                    enabled: root.host !== null && root.host.count > 0
                    onClicked: root.host.saveCurrent()
                }

                Text {
                    width: col.width
                    topPadding: 8
                    wrapMode: Text.Wrap
                    text: "Ctrl + wheel zoom \u00b7 M next mode \u00b7 B background \u00b7 [ ] chapters \u00b7 Ctrl + S save \u00b7 right-click a page"
                    color: Theme.inkSub
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    lineHeight: 1.25
                }
            }
        }
    }
}
