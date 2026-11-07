import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// The Downloader at 1 x 1 (a quarter of the 2 x 2: 120 x 94 of content, 154 x 132 with the
// housing): ONE rounded key. Copy a link anywhere, press the key, and it is downloaded.
//
// Idle it says GET, with a download chip upper left and what it will save (VIDEO / AUDIO / MUTE)
// upper right. While a file comes in, the key fills with colour from the bottom and the percent
// is the big sticker numeral; the chip upper right shows the speed, or how many are waiting. When
// it is saved the key fills right up, says SAVED and throws a burst, then drains. A link that
// could not be taken (nothing copied, not a link, nothing installed that can download) says so
// in the little chip for a moment.
//
// Press (or click): download the link on the clipboard. The wheel changes what it saves (video,
// audio, mute). It sinks into its hard shadow while pressed and tips a little when pointed at
// (until it is pressed; it straightens and stays straight until the pointer has left for a
// moment, the same rule as CalendarTile.qml and WaterTile.qml).
//
//   DownloaderTile {
//       width: card.contentW; height: card.contentH
//       running: DownloaderService.runningId !== 0
//       pct: DownloaderService.livePct
//       waiting: DownloaderService.counts.queued
//       modeLabel: DM.modeText(DownloaderService.mode)
//       speed: DownloaderService.liveSpeed
//       hover: dragArea.containsMouse
//       pressed: dragArea.pressed
//   }
//   ... tile.pop() on a new link, tile.cheer() when one is saved, tile.failed() when one
//   fails, tile.note("NO LINK") for a link that was not taken.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    property bool running: false
    // 0..100, or -1 when it is not known yet (the key breathes instead of filling).
    property real pct: -1
    property int waiting: 0
    // A post with several items is waiting for you to choose: press to open the 2 x 2 and choose.
    property bool choosing: false
    property string modeLabel: "VIDEO"
    property string speed: ""
    property bool hover: false
    property bool pressed: false

    // ===== what it says for a moment after something happened =====
    // "" | "saved" | "failed" | "note"
    property string flash: ""
    property string noteText: ""

    function pop() {
        squish.restart()
        puff.fire()
    }

    function cheer() {
        root.flash = "saved"
        flashTimer.restart()
        squish.restart()
        cheerBurst.fire()
    }

    function failed() {
        root.flash = "failed"
        flashTimer.restart()
        squish.restart()
    }

    function note(text) {
        root.noteText = text
        root.flash = "note"
        flashTimer.restart()
    }

    Timer {
        id: flashTimer
        interval: 2400
        onTriggered: root.flash = ""
    }

    // The tip is for pointing, not for after a press (see CalendarTile.qml).
    property bool pressedSinceEnter: false
    readonly property int leaveWait: 400

    onPressedChanged: {
        if (root.pressed) {
            root.pressedSinceEnter = true
            leaveTimer.stop()
        } else if (!root.hover) {
            leaveTimer.restart()
        }
    }
    onHoverChanged: {
        if (root.hover)
            leaveTimer.stop()
        else if (!root.pressed)
            leaveTimer.restart()
    }

    Timer {
        id: leaveTimer
        interval: root.leaveWait
        onTriggered: {
            if (!root.hover && !root.pressed)
                root.pressedSinceEnter = false
        }
    }

    readonly property bool tipped: root.hover && !root.pressed && !root.pressedSinceEnter

    // ===== the fill =====
    // Not known how far it is yet: the colour breathes a little above the bottom.
    property real breath: 0

    SequentialAnimation on breath {
        running: root.running && root.pct < 0 && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
    }

    readonly property real level: root.flash === "saved" ? 1
        : (root.running ? (root.pct >= 0 ? root.pct / 100 : 0.18 + root.breath) : 0)

    // What the fill shows: it eases to `level` with an overshoot (a plain property: QML refuses
    // a Behavior on a readonly one).
    property real shownLevel: root.level

    Behavior on shownLevel {
        NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }

    // ===== the words =====
    readonly property bool isSaved: root.flash === "saved"
    readonly property bool isFailed: root.flash === "failed"
    readonly property bool isNote: root.flash === "note"

    readonly property string bigText: root.isSaved ? "SAVED"
        : (root.isFailed ? "OOPS"
        : (root.running ? (root.pct >= 0 ? Math.round(root.pct) + "%" : "\u00b7\u00b7\u00b7") : "GET"))
    readonly property int bigSize: root.isSaved ? 30 : (root.isFailed ? 36 : (root.running ? (root.pct >= 100 ? 36 : 44) : 54))

    readonly property string labelText: root.isNote ? root.noteText
        : (root.isFailed ? "FAILED"
        : (root.isSaved ? "DONE"
        : (root.running ? (root.waiting > 0 ? "+" + root.waiting + " WAITING" : (root.speed !== "" ? root.speed.toUpperCase() : root.modeLabel))
        : (root.choosing ? "PICK ITEMS" : (root.hover ? "PASTE LINK" : root.modeLabel)))))

    readonly property string chipIcon: root.isSaved ? "check_circle"
        : (root.isFailed || root.isNote ? "error" : (root.running ? "downloading" : "download"))

    // The sticker numerals' ink: a dark fill inside a white ring (as on the popups' plates).
    readonly property color numberFill: Qt.darker(mt.colBorder, 1.8)
    readonly property color numberRing: "#ffffff"

    TinyFoot {
        id: foot
        anchors.fill: parent

        Pill {
            id: key
            width: foot.capW
            height: foot.capH + foot.shadowDy
            cornerRadius: 30
            ringWidth: mt.borderWidth + mt.whiteLine
            pressed: root.pressed

            fillColor: mt.pSurface

            property real sx: 1
            property real sy: 1

            transformOrigin: Item.Center
            rotation: root.tipped ? -2 : 0

            Behavior on rotation {
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            }

            transform: Scale {
                origin.x: key.width / 2
                origin.y: key.height / 2
                xScale: key.sx
                yScale: key.sy
            }

            // The colour that comes up as the file comes in, clipped to the key's rounded inside.
            DownloadFill {
                anchors.fill: parent
                radius: key.cornerRadius - key.ringWidth
                level: root.shownLevel
            }

            // The chip, upper left: the arrow (a check once it is saved, a mark when it went wrong).
            Pill {
                id: iconChip
                x: 9
                y: 8
                width: 34
                height: 37
                shadowDy: 3
                cornerRadius: 17
                ringWidth: mt.borderWidth + mt.whiteLine
                fillColor: root.isSaved ? mt.accentMint : ((root.isFailed || root.isNote) ? mt.warnFill : mt.chipFill)

                MaterialIcon {
                    anchors.centerIn: parent
                    // The arrow nods down when the key is pointed at.
                    anchors.verticalCenterOffset: root.tipped ? 2 : 0
                    name: root.chipIcon
                    size: 22
                    color: (root.isSaved || root.isFailed || root.isNote) ? mt.colBorder : mt.chipInk

                    Behavior on anchors.verticalCenterOffset {
                        NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
                    }
                }
            }

            // What it will save, the speed, how many are waiting, or what went wrong, upper right.
            Pill {
                id: labelChip
                width: Math.min(key.width - iconChip.width - 30, label.implicitWidth + 24)
                height: 27
                x: parent.width - width - 9
                y: 10
                shadowDy: 3
                cornerRadius: 12
                ringWidth: mt.borderWidth + mt.whiteLine
                fillColor: root.isSaved ? mt.accentMint : ((root.isFailed || root.isNote) ? mt.warnFill : mt.chipFill)

                Text {
                    id: label
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.labelText
                    color: (root.isSaved || root.isFailed || root.isNote) ? mt.colBorder : mt.chipInk
                    font.family: mt.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                    font.letterSpacing: 1.2
                }
            }

            // The big word, lower right, over the colour: GET, the percent, SAVED.
            Item {
                id: group
                width: bigNum.width
                height: bigNum.height
                x: parent.width - group.width - 8
                y: parent.height - group.height + 2

                StickerText {
                    id: bigNum
                    text: root.bigText
                    pixelSize: root.bigSize
                    fillColor: root.numberFill
                    ringColor: root.numberRing
                }
            }
        }

        SequentialAnimation {
            id: squish
            ParallelAnimation {
                NumberAnimation { target: key; property: "sx"; to: 1.1; duration: 80; easing.type: Easing.OutQuad }
                NumberAnimation { target: key; property: "sy"; to: 0.9; duration: 80; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: key; property: "sx"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                NumberAnimation { target: key; property: "sy"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
            }
        }

        Burst {
            id: puff
            x: key.width / 2
            y: key.height / 2
            radius: 64
            count: 8
        }

        Burst {
            id: cheerBurst
            x: key.width / 2
            y: key.height / 2
            radius: 92
            count: 14
            size: 11
        }
    }
}
