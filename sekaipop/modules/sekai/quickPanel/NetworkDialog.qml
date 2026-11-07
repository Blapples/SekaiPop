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
// Tapping an open, unconnected network connects straight away, and so
// does tapping a secured one that is already saved (NetworkManager has
// its password). Tapping a secured network that is not saved yet
// expands a password field in place — Enter or the "Connect" button
// sends it. Tapping the already-connected network disconnects it.
// Right-clicking a saved network slides a Forget button (delete the
// saved profile) in beside it; click again to put it away.
// Opening this shows the networks NetworkManager already knows at
// once and starts a fresh `nmcli device wifi rescan` in the
// background; the list is read again every second for a few seconds,
// so new networks appear as they are found. The header's "Scan"
// button runs the same thing again if you want another sweep.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property bool open: false
    property var networks: []          // [{ssid, signal, secured, connected, saved}]
    property bool scanning: false
    // True while a rescan is running: from the moment this opens (or
    // "Scan" is pressed) until the last read of that rescan, a few
    // seconds. Separate from `scanning`, which also goes true for every
    // quiet background read (see QuickSource.qml's wifiLiveRefresh) —
    // the button used to bind straight to `scanning`, so it flashed
    // into "Scanning…" on its own on every one of those refreshes.
    property bool manualScanning: false
    property string connectingSsid: "" // which row is mid-connect, if any
    property string errorText: ""

    signal closeRequested()
    signal scanRequested()
    signal advancedRequested()
    signal connectRequested(string ssid, string password)
    signal disconnectRequested(string ssid)
    signal forgetRequested(string ssid)

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
    // Which row (if any) is showing its Forget button. Same clearing rules.
    property string forgetSsid: ""
    onOpenChanged: if (!open) {
        expandedSsid = ""
        forgetSsid = ""
    }
    onNetworksChanged: {
        if (expandedSsid !== "" && !networks.some(n => n.ssid === expandedSsid))
            expandedSsid = ""
        if (forgetSsid !== "" && !networks.some(n => n.ssid === forgetSsid))
            forgetSsid = ""
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

        // "Scan" — another rescan sweep. A plain text pill
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
                // A network NetworkManager already knows (saved) or is on (connected) never
                // needs a password typed; anything else may.
                readonly property bool hasActions: modelData.saved === true || modelData.connected
                // Only a saved network has a profile to forget.
                readonly property bool forgetOpen: modelData.saved === true && root.forgetSsid === modelData.ssid

                // 0 -> 1 as the Forget button comes in. One value drives the button's slide, fade
                // and scale and the row text making room for it, so they always move together.
                readonly property int forgetW: 84
                property real reveal: forgetOpen ? 1 : 0
                readonly property real forgetShift: (forgetW + 10) * Math.min(reveal, 1)
                Behavior on reveal {
                    NumberAnimation {
                        duration: row.forgetOpen ? 320 : 200
                        easing.type: row.forgetOpen ? Easing.OutBack : Easing.InCubic
                        easing.overshoot: 1.3
                    }
                }

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
                    width: parent.width - 46 - 40 - row.forgetShift
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
                        : row.modelData.connected ? "Connected"
                        : row.modelData.saved === true ? "Saved"
                        : row.modelData.secured ? "Secured"
                        : "Open"
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 13
                }

                MaterialIcon {
                    visible: row.modelData.secured
                    x: parent.width - 40 - row.forgetShift
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
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            // only a saved network has something to forget
                            if (row.modelData.saved === true)
                                root.forgetSsid = row.forgetOpen ? "" : row.modelData.ssid
                            return
                        }
                        root.forgetSsid = ""
                        if (row.modelData.connected) {
                            root.disconnectRequested(row.modelData.ssid)
                        } else if (row.modelData.saved === true || !row.modelData.secured) {
                            // saved: NetworkManager has the password, nothing to type
                            root.expandedSsid = ""
                            root.connectRequested(row.modelData.ssid, "")
                        } else {
                            root.expandedSsid = row.expanded ? "" : row.modelData.ssid
                        }
                    }
                }

                // Forget: slides in from the right edge (fade + a little scale) when the row is
                // right-clicked, and slides back out when it is dismissed. Declared after the
                // row's MouseArea so it sits on top and gets its own clicks.
                Rectangle {
                    id: forgetPill
                    visible: row.reveal > 0.01
                    x: row.width - row.forgetW - 14 + 36 * (1 - row.reveal)
                    y: 14
                    width: row.forgetW
                    height: 36
                    radius: 18
                    opacity: Math.min(row.reveal, 1)
                    scale: 0.82 + 0.18 * row.reveal
                    transformOrigin: Item.Right
                    color: forgetArea.containsMouse ? "#c0392b" : mt.pSurface
                    border.width: 2
                    border.color: forgetArea.containsMouse ? "#c0392b" : mt.pLine
                    antialiasing: true
                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Forget"
                        color: forgetArea.containsMouse ? "#ffffff" : "#c0392b"
                        font.family: mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: forgetArea
                        anchors.fill: parent
                        enabled: row.forgetOpen
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.forgetSsid = ""
                            root.forgetRequested(row.modelData.ssid)
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
            visible: root.networks.length === 0 && (root.manualScanning || !root.scanning)
            anchors.centerIn: list
            text: root.manualScanning ? "Looking for networks…" : "No networks found"
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 16
        }
        antialiasing: true
    }
}
