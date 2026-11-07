import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.phone

// The device list that drops down over the phone's screen when
// you right-click the Bluetooth tile — same idea as NetworkDialog.qml,
// simpler: no password step, so a tap just connects or disconnects.
//
// Opening it shows the paired devices at once and starts looking for
// nearby ones (`bluetoothctl scan on`, about 9 seconds); the list is
// read again every second, so devices appear as they are found. Paired
// devices come first, then the nearby ones. Tapping a nearby device
// pairs it and connects (QuickSource.qml: bluetoothPairScript) — that
// works for headphones, speakers and the like. A device that asks for
// a PIN (a keyboard, say) can't be paired from here: use "Advanced".
// "Scan" runs the search again. Right-clicking a paired device slides a
// Forget button (remove the pairing) in beside it; click again to put it away.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property bool open: false
    property var devices: []           // [{address, name, connected, paired, battery (-1 = unknown)}]
    property bool scanning: false
    // See NetworkDialog.qml's manualScanning: true while a search for
    // devices runs (from the moment this opens or "Scan" is pressed),
    // kept separate from `scanning` (which also covers every quiet
    // background read — see QuickSource.qml's bluetoothLiveRefresh) so
    // the button doesn't flash "Scanning…" on its own on every poll.
    property bool manualScanning: false
    property string connectingAddress: ""
    property string errorText: ""

    signal closeRequested()
    signal scanRequested()
    signal advancedRequested()
    signal connectRequested(string address)
    signal disconnectRequested(string address)
    signal forgetRequested(string address)

    // Which row (if any) is showing its Forget button. Cleared on close, and if the device leaves the list.
    property string expandedAddress: ""
    onOpenChanged: if (!open) expandedAddress = ""
    onDevicesChanged: {
        if (expandedAddress !== "" && !devices.some(d => d.address === expandedAddress))
            expandedAddress = ""
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.open ? 140 : 220
        }
    }

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

        MouseArea { anchors.fill: parent }

        Text {
            x: 28
            y: 26
            text: "Bluetooth"
            color: mt.pInk
            font.family: mt.fontFamily
            font.pixelSize: 26
            font.weight: Font.ExtraBold
            font.styleName: mt.fontStyleBold
        }

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

        Text {
            x: 28
            y: errorLabel.visible ? 90 : 66
            width: card.width - 56
            text: "Paired devices first, then nearby ones — tap a nearby device to pair."
            wrapMode: Text.Wrap
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 13
        }

        WheelScroll { scroller: list }
        ListView {
            id: list
            x: 14
            y: (errorLabel.visible ? 90 : 66) + 34
            width: card.width - 28
            height: card.height - y - 14
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices
            onContentYChanged: PanelActivity.touch()

            delegate: Item {
                id: row

                required property var modelData

                readonly property bool busy: root.connectingAddress === modelData.address
                // only a paired device has a pairing to forget
                readonly property bool hasActions: modelData.paired !== false
                readonly property bool forgetOpen: hasActions && root.expandedAddress === modelData.address

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

                width: list.width
                height: 64

                Rectangle {
                    y: 2
                    width: parent.width
                    height: 60
                    radius: 20
                    color: rowArea.containsMouse ? mt.pSurfaceHover : "transparent"
                    antialiasing: true
                }

                MaterialIcon {
                    x: 16
                    y: 20
                    size: 22
                    name: row.modelData.connected ? "bluetooth_connected" : "bluetooth"
                }

                // Battery level of a connected device that reports one:
                // the same frame glyphs as the bar's battery, then the
                // percentage. Red at 20% and under.
                readonly property int battery: row.modelData.connected && row.modelData.battery !== undefined
                                               ? row.modelData.battery : -1
                readonly property bool hasBattery: row.battery >= 0
                readonly property color batteryTone: row.battery <= 20 ? "#e0575b" : mt.pInk

                Row {
                    id: batteryTag
                    visible: row.hasBattery
                    anchors.right: parent.right
                    anchors.rightMargin: 18 + row.forgetShift
                    y: 21
                    spacing: 4

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 22
                        color: row.batteryTone
                        name: {
                            if (row.battery >= 100)
                                return "battery_android_frame_full"
                            const bucket = Math.ceil(row.battery / (100 / 6))
                            return "battery_android_frame_" + Math.max(1, Math.min(6, bucket))
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.battery + "%"
                        color: row.batteryTone
                        font.family: mt.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }
                }

                Text {
                    x: 50
                    y: 10
                    width: parent.width - 50 - 14 - row.forgetShift - (row.hasBattery ? batteryTag.width + 10 : 0)
                    elide: Text.ElideRight
                    text: row.modelData.name
                    color: mt.pInk
                    font.family: mt.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Text {
                    x: 50
                    y: 34
                    text: row.busy ? (row.modelData.connected ? "Disconnecting…"
                                          : row.modelData.paired === false ? "Pairing…" : "Connecting…")
                        : row.modelData.connected ? "Connected"
                        : row.modelData.paired === false ? "Nearby"
                        : "Paired"
                    color: mt.pInkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: rowArea
                    y: 2
                    width: parent.width
                    height: 60
                    hoverEnabled: true
                    enabled: !row.busy
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (row.hasActions)
                                root.expandedAddress = row.forgetOpen ? "" : row.modelData.address
                            return
                        }
                        root.expandedAddress = ""
                        if (row.modelData.connected)
                            root.disconnectRequested(row.modelData.address)
                        else
                            root.connectRequested(row.modelData.address)
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
                            root.expandedAddress = ""
                            root.forgetRequested(row.modelData.address)
                        }
                    }
                }
            }

            SekaiScrollBar {}
        }

        Text {
            visible: root.devices.length === 0 && (root.manualScanning || !root.scanning)
            anchors.centerIn: list
            text: root.manualScanning ? "Looking for devices…" : "No devices found"
            color: mt.pInkSub
            font.family: mt.fontFamily
            font.pixelSize: 16
        }
        antialiasing: true
    }
}
