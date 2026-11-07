// Ported from dhrruvsharma/shell (GPL-3.0-or-later), recoloured for SekaiPop.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

Item {
    id: browseView

    readonly property string fontDisplay: Theme.fontFamily
    readonly property string fontBody:    Theme.fontFamily

    signal novelSelected(string novelId)

    property string currentFilter: "hot"

    function _switchFilter(f) {
        if (currentFilter === f) return
        currentFilter = f
        searchBar.clear()
        Novel.clearNovelList()
        if (f === "hot") Novel.fetchHot()
        else             Novel.fetchLatest(true)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Search + provider ─────────────────────────────────────────────────
        Item {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            // Above the grid, so the provider card drops over it.
            z: 5

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 18 }
                spacing: 12

                SearchPill {
                    id: searchBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    placeholder: "Search novels…"
                    onTextChanged: searchDebounce.restart()
                }

                // Provider key, with its card dropping under it
                Item {
                    id: providerBox
                    Layout.preferredWidth: providerKey.implicitWidth
                    Layout.preferredHeight: 40

                    ReaderChip {
                        id: providerKey
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -1
                        enabled: !Novel.isSwitchingProvider
                        icon: providerPopup.open ? "expand_less" : "expand_more"
                        lit: providerPopup.open
                        text: {
                            if (Novel.isSwitchingProvider)
                                return "Switching…"
                            for (var i = 0; i < Novel.availableProviders.length; i++) {
                                if (Novel.availableProviders[i].name === Novel.activeProvider)
                                    return Novel.availableProviders[i].label
                            }
                            return Novel.activeProvider
                        }
                        onClicked: providerPopup.open = !providerPopup.open
                    }

                    // ── Provider card ─────────────────────────────────────────
                    // Pops open from its corner and is swallowed back, like the shell's popups.
                    Pill {
                        id: providerPopup

                        property bool open: false

                        visible: providerPopup.open || providerPopup.scale > 0.02
                        anchors { top: parent.bottom; right: parent.right; topMargin: 4 }
                        width: 176
                        height: popupColumn.implicitHeight + 16 + Theme.shadowOffset
                        cornerRadius: 15
                        ringWidth: Theme.borderWidth
                        innerRing: Theme.cardRing
                        fillColor: Theme.surface
                        z: 100

                        transformOrigin: Item.TopRight
                        scale: providerPopup.open ? 1 : 0.6
                        opacity: providerPopup.open ? 1 : 0
                        Behavior on scale {
                            NumberAnimation {
                                duration: providerPopup.open ? 300 : 150
                                easing.type: providerPopup.open ? Easing.OutBack : Easing.InCubic
                                easing.overshoot: 1.6
                            }
                        }
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        Column {
                            id: popupColumn
                            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 5 }
                            spacing: 3

                            Repeater {
                                model: Novel.availableProviders

                                delegate: Item {
                                    id: optionRow
                                    width: popupColumn.width
                                    height: 34
                                    readonly property bool current: modelData.name === Novel.activeProvider

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 11
                                        antialiasing: true
                                        color: optionRow.current ? Theme.accentMint
                                            : (optionArea.containsMouse ? Theme.surfaceTint : "transparent")
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        spacing: 9

                                        DiamondDot {
                                            anchors.verticalCenter: parent.verticalCenter
                                            size: 8
                                            lit: optionRow.current
                                            litColor: Theme.colBorder
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: optionRow.current ? Theme.colBorder : Theme.ink
                                            font.family: browseView.fontBody
                                            font.pixelSize: 12
                                            font.weight: Font.ExtraBold
                                            font.styleName: Theme.fontStyleBold
                                        }
                                    }

                                    MouseArea {
                                        id: optionArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            providerPopup.open = false
                                            Novel.switchProvider(modelData.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Timer {
                id: searchDebounce
                interval: 380
                onTriggered: {
                    var q = searchBar.text.trim()
                    if (q.length > 0) {
                        browseView.currentFilter = "search"
                        Novel.searchNovels(q, "", "All", true)
                    } else if (browseView.currentFilter === "search") {
                        browseView.currentFilter = "hot"
                        Novel.fetchHot()
                    }
                }
            }
        }

        // ── Filter chips (Hot / Latest) ───────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            clip: true

            ListView {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                model: ListModel {
                    ListElement { label: "Hot";    fid: "hot"    }
                    ListElement { label: "Latest"; fid: "latest" }
                }

                delegate: Item {
                    width: chip.implicitWidth
                    height: ListView.view.height

                    ReaderChip {
                        id: chip
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: label
                        lit: browseView.currentFilter === fid
                        onClicked: browseView._switchFilter(fid)
                    }
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Novel grid ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            Rectangle { anchors.fill: parent; color: Colors.background }

            // Close the provider popup when clicking outside it
            MouseArea {
                anchors.fill: parent
                enabled: providerPopup.open
                onClicked: providerPopup.open = false
                z: 50
            }

            // Loading overlay: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                active: (Novel.isFetchingNovel || Novel.isSwitchingProvider)
                    && Novel.novelList.length === 0
                cellWidth: (width - 30) / 4
                ratio: 1.65
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: Novel.isFetchingNovel && Novel.novelList.length > 0
            }

            // Error overlay
            Rectangle {
                anchors.fill: parent; color: Colors.background; z: 9
                visible: Novel.novelError.length > 0 && !Novel.isFetchingNovel

                Column {
                    anchors.centerIn: parent; spacing: 10
                    Text { text: "⚠"; font.pixelSize: 32; color: Colors.error; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: Novel.novelError; color: Colors.on_surface_variant
                        font.pixelSize: 12; font.family: browseView.fontBody
                        wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                    }
                }
            }

            GridView {
                id: novelGrid
                anchors.fill: parent; anchors.margins: 10
                cellWidth: (width - 10) / 4
                cellHeight: cellWidth * 1.65
                clip: true; boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: Novel.novelList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2)
                        Novel.fetchNextPage()
                }

                delegate: Item {
                    width: novelGrid.cellWidth; height: novelGrid.cellHeight

                    CoverCard {
                        anchors.fill: parent
                        source: modelData.coverUrl || ""
                        title: modelData.title || ""
                        subtitle: modelData.author || ""
                        bodyFont: browseView.fontBody

                        // Status stamp
                        ReaderBadge {
                            visible: modelData.status && modelData.status.length > 0
                            anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                            rotation: -4
                            text: (modelData.status || "").toUpperCase()
                            fill: modelData.status === "Ongoing" ? Theme.accentMint : Theme.accentCyan
                        }

                        onClicked: {
                            Novel.fetchNovelDetail(modelData.id)
                            browseView.novelSelected(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
