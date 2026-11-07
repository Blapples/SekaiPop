import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.phone

// The Wi-Fi picker that drops down over the phone's screen when you
// right-click the Network tile — one of the two "tile opens a device
// list" gaps against the reference this was modeled on (see the
// README). Pure UI: QuickPanel.qml feeds it `networks` (from
// QuickSource.qml's nmcli poll) and turns its signals into nmcli calls.
//
// Tapping an open, unconnected network connects straight away. Tapping
// a saved one reuses its profile; a new secured one expands a password
// field in place — Enter or the "Connect" button sends it. Tapping the already-connected network
// disconnects it. The header's "Scan" button forces a fresh
// `nmcli device wifi rescan`, which is slow enough (a couple of
// seconds) that it's opt-in rather than run every time this opens.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property bool open: false
    property var networks: []          // [{ssid, signal, secured, connected, profileUuid}]
    property bool scanning: false
    // True only while a scan the "Scan" button itself asked for is in
    // flight — separate from `scanning`, which also goes true for the
    // quiet fetch this dialog fires on its own once it opens and (see
    // QuickSource.qml's wifiLiveRefresh) every few seconds after that
    // to keep the list live. The button used to bind straight to
    // `scanning`, so it visibly flashed into "Scanning…" and back on
    // its own on every one of those background refreshes — looking
    // like it was refreshing itself even when nobody touched it.
    property bool manualScanning: false
    property string connectingSsid: "" // which row is mid-connect, if any
    property string errorText: ""

    signal closeRequested()
    signal scanRequested()
    signal advancedRequested()
    signal connectRequested(string ssid, string password)
    signal disconnectRequested(string ssid)

    anchors.fill: parent
    // Only worth hit-testing (and only shows up in the phone's texture
    // at all) while at least partway open — same guard PowerMenuScrim
    // uses.
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.open ? 140 : 220
        }
    }

    // Which row (if any) has its password field expanded. Cleared on
    // close, and if a rescan drops that network from the list.
    property string expandedSsid: ""
    onOpenChanged: if (!open) expandedSsid = ""
    onNetworksChanged: {
        if (expandedSsid !== "" && !networks.some(n => n.ssid === expandedSsid))
            expandedSsid = ""
    }

    // Same dimming glass PowerMenuScrim uses (inset to the visible
    // glass, so it reads as part of the phone's own tilted screen)
    // rather than a new look of its own.
    Rectangle {
        anchors.fill: parent
        anchors.margins: mt.phoneScreenInset
        radius: mt.phoneCornerRadius - mt.phoneScreenInset
        color: mt.scrim
        opacity: root.open ? 0.55 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
        antialiasing: true
    }

    // The card: same white body / navy outline / hard shadow the
    // notifications card uses, just sized to sit over the toggles and
    // notifications area it covers.
    Rectangle {
        x: 40 + (mt.quickFlat ? 0 : 5)
        y: 200 + 4
        width: 575
        height: 940
        radius: 41
        color: mt.pLineShadow
        antialiasing: true
    }

    Rectangle {
        id: card
        x: 40
        y: 200
        width: 575
        height: 940
        radius: 41
        color: mt.pSurface
        border.width: 3
        border.color: mt.pLine
        clip: true

        // Swallows clicks so tapping empty space in the card doesn't
        // fall through to the scrim behind it.
        MouseArea { anchors.fill: parent }

        Text {
            x: 28
            y: 26
            text: "Wi-Fi"
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 26
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

        // "Scan" — forces the slow rescan+list path. A plain text pill
        // rather than a hand-drawn refresh glyph: one less icon this
        // project has to ship and keep legible at this size.
        Rectangle {
            id: scanButton
            x: card.width - 28 - width
            y: 22
            width: scanLabel.implicitWidth + 28
            height: 34
            radius: 17
            color: scanArea.containsMouse ? mt.pSurfaceHover : "transparent"
            border.width: 2
            border.color: mt.pLine
            opacity: root.manualScanning ? 0.5 : 1

            Text {
                id: scanLabel
                anchors.centerIn: parent
                text: root.manualScanning ? "Scanning…" : "Scan"
                color: mt.pInk
                font.family: mt.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: scanArea
                anchors.fill: parent
                enabled: !root.manualScanning
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.scanRequested()
            }
            antialiasing: true
        }

        // "Advanced": opens the full settings app (see scripts/system/open-settings-app.sh).
        Rectangle {
            id: advancedButton
            x: scanButton.x - 10 - width
            y: 22
            width: advancedLabel.implicitWidth + 28
            height: 34
            radius: 17
            color: advancedArea.containsMouse ? mt.pSurfaceHover : "transparent"
            border.width: 2
            border.color: mt.pLine

            Text {
                id: advancedLabel
                anchors.centerIn: parent
                text: "Advanced"
                color: mt.pInk
                font.family: mt.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: advancedArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.advancedRequested()
            }
            antialiasing: true
        }

        Text {
            id: errorLabel
            visible: root.errorText !== ""
            x: 28
            y: 62
            width: card.width - 56
            text: root.errorText
            wrapMode: Text.Wrap
            color: "#c0392b"
            font.family: mt.fontFamily
            font.pixelSize: 14
        }

        WheelScroll { scroller: list }
        ListView {
            id: list
            x: 14
            y: errorLabel.visible ? 92 : 68
            width: card.width - 28
            height: card.height - y - 14
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.networks
            onContentYChanged: PanelActivity.touch()

            delegate: Item {
                id: row

                required property var modelData

                readonly property bool expanded: root.expandedSsid === modelData.ssid
                readonly property bool busy: root.connectingSsid === modelData.ssid

                // Same forceActiveFocus() pattern Overview.qml's
                // search box uses — a plain `focus: expanded` binding
                // doesn't reliably pull the active focus item over the
                // first time a row not already in the chain expands.
                onExpandedChanged: if (expanded) Qt.callLater(() => passInput.forceActiveFocus())

                width: list.width
                height: 64 + (expanded ? 64 : 0)
                Behavior on height {
                    NumberAnimation {
                        duration: 140
                    }
                }

                Rectangle {
                    y: 2
                    width: parent.width
                    height: 60
                    radius: 20
                    color: mainArea.containsMouse ? mt.pSurfaceHover : "transparent"
                    antialiasing: true
                }

                // Signal strength: three bars, filled up to however many
                // thirds `signal` (0-100) clears. No per-tier icon asset
                // for this — drawn straight from Theme's colors instead,
                // the same call WorkspaceBadges.qml made.
                Row {
                    x: 14
                    y: 20
                    spacing: 3

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            readonly property bool lit: row.modelData.signal >= (index + 1) * 33
                            width: 5
                            height: 8 + index * 6
                            anchors.bottom: parent.bottom
                            radius: 1.5
                            color: lit ? mt.pInk : mt.pSurfaceDivider
                            antialiasing: true
                        }
                    }
                }

                Text {
                    x: 46
                    y: 10
                    width: parent.width - 46 - 40
                    elide: Text.ElideRight
                    text: row.modelData.ssid
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Text {
                    x: 46
                    y: 34
                    text: row.busy ? "Connecting…"
                        : row.modelData.connected ? "Connected — tap to disconnect"
                        : row.modelData.profileUuid ? "Saved — tap to connect"
                        : row.modelData.secured ? "Secured"
                        : "Open"
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 13
                }

                MaterialIcon {
                    visible: row.modelData.secured
                    x: parent.width - 40
                    y: 20
                    size: 20
                    name: "lock"
                }

                MouseArea {
                    id: mainArea
                    y: 2
                    width: parent.width
                    height: 60
                    hoverEnabled: true
                    enabled: !row.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.modelData.connected) {
                            root.disconnectRequested(row.modelData.ssid)
                        } else if (row.modelData.profileUuid) {
                            root.expandedSsid = ""
                            root.connectRequested(row.modelData.ssid, "")
                        } else if (row.modelData.secured) {
                            root.expandedSsid = row.expanded ? "" : row.modelData.ssid
                        } else {
                            root.connectRequested(row.modelData.ssid, "")
                        }
                    }
                }

                // The password field, only for a secured row that isn't
                // connected yet and that's been tapped open.
                Item {
                    visible: row.expanded
                    x: 46
                    y: 64
                    width: parent.width - 46 - 14
                    height: 52

                    Rectangle {
                        id: passField
                        width: parent.width - 90
                        height: 44
                        radius: 22
                        color: mt.pSurfaceHover
                        border.width: 2
                        border.color: passInput.activeFocus ? mt.pLine : "transparent"

                        TextInput {
                            id: passInput
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: mt.pInk
                            font.family: mt.fontFamily
                            font.pixelSize: 15
                            clip: true
                            focus: row.expanded
                            Keys.onReturnPressed: connectButton.go()
                            Keys.onEscapePressed: root.expandedSsid = ""

                            Text {
                                visible: passInput.text === "" && !passInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password"
                                color: mt.pInkSub
                                font.family: mt.fontFamily
                                font.pixelSize: 15
                            }
                        }
                        antialiasing: true
                    }

                    Rectangle {
                        id: connectButton
                        anchors.left: passField.right
                        anchors.leftMargin: 8
                        width: 82
                        height: 44
                        radius: 22
                        color: connectArea.containsMouse ? mt.accentMint : mt.pSurface
                        border.width: 2
                        border.color: mt.pLine

                        function go() {
                            root.connectRequested(row.modelData.ssid, passInput.text)
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Connect"
                            color: connectArea.containsMouse ? mt.colBorder : mt.pInk
                            font.family: mt.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: connectArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: connectButton.go()
                        }
                        antialiasing: true
                    }
                }
            }

            SekaiScrollBar {}
        }

        Text {
            visible: root.networks.length === 0 && !root.scanning
            anchors.centerIn: list
            text: "No networks found"
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 16
        }
        antialiasing: true
    }
}
