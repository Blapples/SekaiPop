import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The lyrics source picker: where the words of the song come from, and what each place
// found for the song that is on now.
//
//   Auto        the best provider for each song (word by word over synced, then the one
//               cut to the song's length). This is the way it starts.
//   a provider  use that one whenever it has the song (the best of the others when it does
//               not). Each row says what it found: WORD BY WORD, SYNCED, Not found, or
//               Unreachable (a click on "Try again" asks them all again). The rows are in the
//               order the providers are liked: Boidu first (see LyricsService.providers).
//               The same choice is in Settings -> Desktop, under the Lyrics switch.
//
// Opened by the "sources" key that appears when you point at the lyrics (LyricsWidget.qml)
// or `qs -c sekaipop ipc call lyrics picker`. It is the same card as the desktop's
// right-click menu (DesktopMenu.qml) in a full-screen transparent Overlay window that
// exists only while it is open, so a click anywhere else (or Esc) closes it. The service
// side is services/LyricsService.qml (`preferred`, `sourceStates`, `providers`).
PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

    readonly property string wantedScreen: LyricsService.pickerScreen
    screen: Quickshell.screens.find(s => s.name === win.wantedScreen) ?? DesktopMonitors.fallbackScreen

    readonly property real uiScale: ShellScale.forScreen(win.screen)
    readonly property real roomW: win.width / win.uiScale
    readonly property real roomH: win.height / win.uiScale

    // Stays up while the card pops away, so it can leave the way it came.
    visible: LyricsService.pickerOpen || card.popProgress > 0.001

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sekaipop-lyrics-sources"
    WlrLayershell.keyboardFocus: LyricsService.pickerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Click anywhere outside the card: close.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: LyricsService.closePicker()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: LyricsService.closePicker()
    }

    // A new full-screen layer window is a small one for its first frames, and a card centred in
    // it would slide from the top-left corner to its place while it popped. So the pop waits
    // until the window is the size of the screen (or, if that never reads true, a moment).
    readonly property bool sized: win.visible && win.width > 0 && win.height > 0
        && (!win.screen || (win.width >= win.screen.width - 2 && win.height >= win.screen.height - 2))

    function startPop(): void {
        if (win.sized)
            card.pop()
        else
            popFallback.restart()
    }

    onSizedChanged: {
        if (win.sized && LyricsService.pickerOpen && popFallback.running) {
            popFallback.stop()
            card.pop()
        }
    }

    Timer {
        id: popFallback
        interval: 300
        repeat: false
        onTriggered: {
            if (LyricsService.pickerOpen && card.popProgress === 0)
                card.pop()
        }
    }

    Connections {
        target: LyricsService

        function onPickerOpenChanged(): void {
            if (LyricsService.pickerOpen)
                win.startPop()
            else
                card.away()
        }
    }

    Component.onCompleted: {
        if (LyricsService.pickerOpen)
            win.startPop()
    }

    // One line of the list: a round radio, the name, and on the right what it found.
    component SourceRow: Item {
        id: row

        // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
        readonly property var mt: Theme.of(QsWindow.window)

        property string name: ""
        property string note: ""          // under the name, small
        property string kind: ""          // "word" | "synced" | "loading" | "none" | "offline" | ""
        property bool selected: false
        property bool inUse: false
        signal picked
        signal retry

        readonly property bool dim: row.kind === "none"

        height: 40

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            radius: 9
            color: mt.surfaceHover
            opacity: area.containsMouse ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 110 }
            }
        }

        // the radio
        Rectangle {
            id: radio
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: "transparent"
            border.width: 2
            border.color: row.selected ? mt.accentCyan : Qt.rgba(mt.ink.r, mt.ink.g, mt.ink.b, row.dim ? 0.28 : 0.5)

            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: mt.accentCyan
                scale: row.selected ? 1 : 0
                opacity: row.selected ? 1 : 0

                Behavior on scale {
                    NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 100 }
                }
            }
        }

        Column {
            anchors.left: radio.right
            anchors.leftMargin: 12
            anchors.right: status.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: row.name
                elide: Text.ElideRight
                color: mt.ink
                opacity: row.dim ? 0.45 : 1
                font.family: mt.fontFamily
                font.pixelSize: 15
                font.weight: row.inUse ? Font.ExtraBold : Font.DemiBold
                font.styleName: row.inUse ? mt.fontStyleBold : ""
            }

            Text {
                visible: row.note !== ""
                width: parent.width
                text: row.note
                elide: Text.ElideRight
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 11
            }
        }

        // what it found
        Row {
            id: status
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                visible: row.kind === "offline"
                anchors.verticalCenter: parent.verticalCenter
                text: "Unreachable"
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 12
            }

            Text {
                visible: row.kind === "offline"
                anchors.verticalCenter: parent.verticalCenter
                text: "Try again"
                color: mt.accentCyan
                font.family: mt.fontFamily
                font.pixelSize: 12
                font.underline: retryArea.containsMouse

                MouseArea {
                    id: retryArea
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.retry()
                }
            }

            Text {
                visible: row.kind === "none"
                anchors.verticalCenter: parent.verticalCenter
                text: "Not found"
                color: mt.inkSub
                opacity: 0.7
                font.family: mt.fontFamily
                font.pixelSize: 12
            }

            Text {
                visible: row.kind === "loading"
                anchors.verticalCenter: parent.verticalCenter
                text: "asking..."
                color: mt.inkSub
                font.family: mt.fontFamily
                font.pixelSize: 12
            }

            Rectangle {
                visible: row.kind === "word" || row.kind === "synced"
                anchors.verticalCenter: parent.verticalCenter
                width: badge.implicitWidth + 16
                height: 22
                radius: 11
                color: row.kind === "word"
                    ? Qt.rgba(mt.accentCyan.r, mt.accentCyan.g, mt.accentCyan.b, 0.2)
                    : Qt.rgba(mt.ink.r, mt.ink.g, mt.ink.b, 0.12)

                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: row.kind === "word" ? "WORD BY WORD" : "SYNCED"
                    color: row.kind === "word" ? mt.accentCyan : mt.ink
                    font.family: mt.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 0.8
                }
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: row.picked()
        }
    }

    ScaleHost {
        anchors.fill: parent
        factor: win.uiScale
        // Nothing is clickable while the card is shrinking away.
        enabled: LyricsService.pickerOpen

        Pill {
            id: card

            readonly property real innerWidth: 360
            readonly property real wantX: LyricsService.pickerX < 0 ? win.roomW / 2 : LyricsService.pickerX
            readonly property real wantY: LyricsService.pickerY < 0 ? (win.roomH - card.height) / 2 : LyricsService.pickerY + 6

            // Centred under the lyrics (or on the screen), pushed back in when it would
            // hang off.
            x: Math.max(8, Math.min(card.wantX - card.width / 2, win.roomW - card.width - 8))
            y: Math.max(8, Math.min(card.wantY, win.roomH - card.height - 8))

            cornerRadius: mt.radiusOuter
            ringWidth: mt.borderWidth
            innerRing: mt.cardRing
            fillColor: mt.surface
            implicitWidth: card.innerWidth + 10 + card.ringWidth * 2
            implicitHeight: col.implicitHeight + 10 + card.ringWidth * 2 + mt.shadowOffset
            width: implicitWidth
            height: implicitHeight

            // 0 = gone, 1 = open. The same motion as the bar's popup pills (SekaiPopup.qml): it
            // grows out of nothing in its own middle with a small bounce, and shrinks all the
            // way back into it.
            property real popProgress: 0

            function pop() {
                awayAnim.stop()
                popAnim.restart()
            }

            function away() {
                popAnim.stop()
                awayAnim.restart()
            }

            NumberAnimation {
                id: popAnim
                target: card
                property: "popProgress"
                to: 1
                duration: 340
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }

            NumberAnimation {
                id: awayAnim
                target: card
                property: "popProgress"
                to: 0
                duration: 170
                easing.type: Easing.InCubic
            }

            // It fades in a touch as it starts, but never out: it is whole until it has gone
            // into its middle.
            opacity: LyricsService.pickerOpen ? Math.min(1, card.popProgress * 8) : 1
            transformOrigin: Item.Center
            scale: Math.max(0, card.popProgress)

            // Takes the clicks that land on the card, so they do not close it.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            }

            Column {
                id: col
                x: 5
                y: 5
                width: card.innerWidth

                Text {
                    x: 12
                    height: 30
                    verticalAlignment: Text.AlignVCenter
                    text: "Lyrics source"
                    color: mt.inkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 0.6
                    font.capitalization: Font.AllUppercase
                }

                SourceRow {
                    width: col.width
                    name: "Auto"
                    note: LyricsService.source !== "" && LyricsService.status === "ready"
                        ? "using " + LyricsService.providerName(LyricsService.source)
                        : "the best one for each song"
                    selected: LyricsService.preferred === "auto"
                    onPicked: LyricsService.setPreferred("auto")
                }

                Repeater {
                    model: LyricsService.providers

                    delegate: SourceRow {
                        id: line

                        required property var modelData

                        width: col.width
                        name: line.modelData.name
                        note: line.modelData.hint
                        selected: LyricsService.preferred === line.modelData.id
                        inUse: LyricsService.source === line.modelData.id && LyricsService.status === "ready"
                        kind: {
                            const s = LyricsService.sourceStates[line.modelData.id]
                            if (s !== undefined)
                                return s
                            // from the cache: only the one that was used is known
                            return LyricsService.source === line.modelData.id ? LyricsService.sourceKind : ""
                        }
                        onPicked: LyricsService.setPreferred(line.modelData.id)
                        onRetry: LyricsService.refresh()
                    }
                }
            }
        }
    }
}
