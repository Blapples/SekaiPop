import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.modules.common

// The phone your Android phone is shown on: the Quick Panel phone's flat look (a rim, a dark
// bezel, a camera in it, side buttons that stand out of the edge) with the live scrcpy picture
// where the screen is. Flat on purpose: the touches go to a REAL scrcpy window that sits
// exactly under this screen (services/PhoneMirrorService.qml), and a window cannot be tilted.
//
// Everything here is in pixels. The owner (PhoneMirror.qml) works the sizes out and hands them
// down, so the screen's rectangle is a whole number of pixels, which is what the window is
// put on.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // The size of the real screen inside the body (pixels), the frame around it, and the
    // design-unit scale the frame was worked out from (the Quick phone is 654 x 1214 units).
    property int screenW: 300
    property int screenH: 650
    property int inset: 14
    property real f: 0.6
    property real bodyRadius: 60
    property real stick: 8
    // The shell's own UI scale on this monitor, for text.
    property real unit: 1
    property real dpr: 1
    // The Quick phone's notch over the top of the picture (Settings > Quick > Phone mirror).
    property bool notch: true

    readonly property int rim: Math.max(3, Math.round(mt.phoneRimWidth * f))
    readonly property real screenRadius: Math.max(8, bodyRadius - inset)

    // Read by the owner: where the picture is, and whether there is one yet.
    property alias screenFrame: frame
    readonly property bool capturing: PhoneMirrorService.toplevel !== null && screencopy.hasContent
    readonly property bool wired: PhoneMirrorService.embedRunning && PhoneMirrorService.attached

    signal retry()

    implicitWidth: screenW + 2 * inset
    implicitHeight: screenH + 2 * inset
    width: implicitWidth
    height: implicitHeight

    // ===== what stands under the picture =====
    // The text the screen shows while there is no picture: the first thing in the list that
    // is true. `hint` says what to do about it.
    readonly property var notice: {
        const svc = PhoneMirrorService
        if (!svc.scrcpyAvailable)
            return { "title": "scrcpy is not installed", "hint": "sudo pacman -S scrcpy android-tools", "retry": true, "busy": false }
        if (svc.adbMissing)
            return { "title": "adb is not installed", "hint": "sudo pacman -S android-tools", "retry": true, "busy": false }
        if (svc.stopped)
            return { "title": "Phone mirror is off", "hint": "Press Start to mirror your phone. Nothing runs on the phone while it is off.", "retry": true, "busy": false, "button": "Start", "buttonIcon": "play_arrow" }
        if (svc.deviceStatus === "unauthorized")
            return { "title": "Allow USB debugging", "hint": "Look at the phone: accept the question about this computer.", "retry": false, "busy": false }
        if (svc.deviceStatus === "offline")
            return { "title": "The phone is not answering", "hint": "Unplug it and plug it in again, or unlock it.", "retry": true, "busy": false }
        if (svc.deviceStatus === "none")
            return { "title": "No phone found", "hint": "Plug it in and turn on USB debugging. For Wi-Fi: ipc call phonemirror connect <ip>:5555", "retry": true, "busy": false }
        if (svc.placementError !== "")
            return { "title": "Cannot reach the phone's window", "hint": svc.placementError, "retry": true, "busy": false }
        if (svc.embedError !== "")
            return { "title": "Could not mirror the phone", "hint": svc.embedError, "retry": true, "busy": false }
        if (svc.waitingText !== "")
            return { "title": "Waiting for the phone", "hint": svc.waitingText, "retry": false, "busy": true }
        // Which step it is waiting on (see PhoneMirrorService._heal for what is done about it).
        if (svc.windowRunning)
            return { "title": "The phone is in its own window", "hint": "Bring it back here, or press Stop.", "retry": true, "busy": false, "button": "Bring back", "buttonIcon": "close_fullscreen" }
        if (!svc.embedRunning)
            return { "title": "Starting scrcpy…", "hint": "", "retry": false, "busy": true }
        if (!svc.toplevel)
            return { "title": "Waiting for scrcpy's window…", "hint": "", "retry": false, "busy": true }
        if (!svc.attached)
            return { "title": "Putting the window in place…", "hint": "", "retry": false, "busy": true }
        return { "title": "Waiting for the picture…", "hint": "", "retry": false, "busy": true }
    }

    // ===== side buttons =====
    // The flat Quick phone's Power button (PhoneBody.qml): a small lavender tab standing out of
    // the right edge, a dark underside a few units lower so it reads as standing out and not
    // lying on the edge, mint under the pointer and cyan pressed. Drawn before the body, so the
    // body's edge covers the few units of it that sit under the rim. Here it sends the real key
    // to the phone; the volume keys are the same tab on the left edge.
    component SideKey: Item {
        id: key
        property string action: ""
        property bool onRight: true
        property real f: 1
        property real stick: 18
        property color light
        property color dark
        property color hover
        property color down

        // Design units (x f), like the Quick phone's: 4 under the rim, `stick` out of it.
        width: Math.round((key.stick + 4) * key.f)

        Rectangle {
            x: 0
            y: Math.round(5 * key.f * (1 - (area.pressed ? 1 : 0)))
            width: parent.width
            height: parent.height
            radius: Math.max(2, 8 * key.f)
            color: key.dark
            antialiasing: true
        }

        Rectangle {
            x: 0
            y: Math.round(4 * key.f * (area.pressed ? 1 : 0))
            width: parent.width
            height: parent.height
            radius: Math.max(2, 8 * key.f)
            color: area.pressed ? key.down : (area.containsMouse ? key.hover : key.light)
            border.width: Math.max(1, Math.round(2 * key.f))
            border.color: key.dark
            antialiasing: true
        }

        // Only the part that stands out of the body takes the pointer: the rest is under it.
        MouseArea {
            id: area
            x: key.onRight ? Math.round(4 * key.f) : -2
            y: -3
            width: Math.round(key.stick * key.f) + 4
            height: parent.height + 6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: PhoneMirrorService.sendKey(key.action)
        }
    }

    SideKey {
        action: "power"
        onRight: true
        f: root.f
        light: root.mt.phoneWallLight
        dark: root.mt.phoneWallDark
        hover: root.mt.accentMint
        down: root.mt.accentCyan
        x: root.width - Math.round(4 * root.f)
        y: Math.round(338 * root.f)
        height: Math.round(150 * root.f)
    }

    SideKey {
        action: "volumeUp"
        onRight: false
        f: root.f
        stick: 14
        light: root.mt.phoneWallLight
        dark: root.mt.phoneWallDark
        hover: root.mt.accentMint
        down: root.mt.accentCyan
        x: -Math.round(14 * root.f)
        y: Math.round(250 * root.f)
        height: Math.round(100 * root.f)
    }

    SideKey {
        action: "volumeDown"
        onRight: false
        f: root.f
        stick: 14
        light: root.mt.phoneWallLight
        dark: root.mt.phoneWallDark
        hover: root.mt.accentMint
        down: root.mt.accentCyan
        x: -Math.round(14 * root.f)
        y: Math.round(366 * root.f)
        height: Math.round(100 * root.f)
    }

    // ===== the body =====
    Rectangle {
        id: rimBody
        anchors.fill: parent
        radius: root.bodyRadius
        color: root.mt.colBorder
        antialiasing: true

        // The dark glass between the rim and the screen.
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.rim
            radius: Math.max(2, root.bodyRadius - root.rim)
            color: root.mt.phoneBezel
            antialiasing: true
        }
    }

    // ===== the screen =====
    ClippingRectangle {
        id: frame
        x: root.inset
        y: root.inset
        width: root.screenW
        height: root.screenH
        radius: root.screenRadius
        antialiasing: true
        // Opaque: the scrcpy window is directly behind this rectangle, and anything see-through
        // here would let it smear through.
        color: root.capturing ? "#000000" : root.mt.pSurface

        // Only once the window is on screen. Asking to copy one that is parked off the side of
        // every monitor gets a capture session with nothing to copy, and it does not pick
        // itself up again when the window finally arrives.
        property bool captureArmed: true

        Timer {
            id: captureRetry
            interval: 400
            repeat: false
            onTriggered: frame.captureArmed = true
        }

        Timer {
            id: sizeGuard
            interval: 500
            repeat: false
            onTriggered: PhoneMirrorService.reassertGeometry()
        }

        // A capture that has been running for a while without a single frame is one that started
        // on a window that was not ready. Start it again, until a frame arrives.
        Timer {
            interval: 2000
            repeat: true
            running: PhoneMirrorService.attached && PhoneMirrorService.placementOk
                && PhoneMirrorService.toplevel !== null && !screencopy.hasContent
            onTriggered: {
                frame.captureArmed = false
                captureRetry.restart()
            }
        }

        ScreencopyView {
            id: screencopy
            anchors.fill: parent
            // Only once Hyprland has been seen to have the window in place: a capture started
            // while it is still being moved gets nothing to copy, says nothing, and never tries
            // again (what closing and opening the panel used to fix by starting a new one).
            // `captureReady` stays up while the window is checked again later (a workspace
            // change, a layer opening), so the picture is not torn down by those.
            captureSource: (PhoneMirrorService.attached && PhoneMirrorService.captureReady && frame.captureArmed)
                ? PhoneMirrorService.toplevel : null
            live: true
            paintCursor: false
            onStopped: {
                frame.captureArmed = false
                captureRetry.restart()
            }
            // One device pixel per displayed pixel is the whole of it: the frame already has
            // the phone's aspect ratio.
            constraintSize: Qt.size(Math.max(1, Math.round(frame.width * root.dpr)),
                                    Math.max(1, Math.round(frame.height * root.dpr)))
            // Hyprland's resize_on_border: a drag at the very edge of the picture grabs the
            // window underneath it. The capture's source size is the window's size, so the
            // moment it stops matching the frame, the window has been pulled out from under it.
            // The guard waits a moment, and only acts if it is still wrong then: a window being
            // resized into place reports every size on the way.
            onSourceSizeChanged: {
                if (!PhoneMirrorService.placementOk || sourceSize.width <= 0)
                    return
                const w = Math.round(frame.width * root.dpr)
                if (Math.abs(sourceSize.width - w) <= 3 * root.dpr
                        || Math.abs(sourceSize.width - frame.width) <= 3)
                    sizeGuard.stop()
                else
                    sizeGuard.restart()
            }
        }

        // A picture that was there a moment ago and blinks (the capture starting over) must not
        // flash the "Waiting" card: while it is only waiting on a step, and had a picture in this
        // session, the card comes back only if the picture stays away for a while.
        property bool hadPicture: false
        property bool lostLong: false

        Connections {
            target: root

            function onCapturingChanged(): void {
                if (root.capturing) {
                    frame.hadPicture = true
                    frame.lostLong = false
                    lostTimer.stop()
                }
            }
        }

        Connections {
            target: PhoneMirrorService

            function onToplevelChanged(): void {
                if (!PhoneMirrorService.toplevel) {
                    frame.hadPicture = false
                    frame.lostLong = false
                }
            }

            function onEmbedRunningChanged(): void {
                if (!PhoneMirrorService.embedRunning) {
                    frame.hadPicture = false
                    frame.lostLong = false
                }
            }
        }

        Timer {
            id: lostTimer
            interval: 1200
            repeat: false
            running: !root.capturing && frame.hadPicture && root.notice.busy
            onTriggered: frame.lostLong = true
        }

        // Shown until the first frame lands, so the screen is never a dark rectangle with no
        // explanation.
        Item {
            anchors.fill: parent
            visible: opacity > 0
            opacity: ((root.capturing || (frame.hadPicture && root.notice.busy && !frame.lostLong))
                      && PhoneMirrorService.placementError === "") ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Over a live picture the message needs something to stand on.
            Rectangle {
                anchors.fill: parent
                color: root.mt.pSurface
            }

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 36 * root.unit, 280 * root.unit)
                spacing: 10 * root.unit

                Item {
                    visible: root.notice.busy
                    width: parent.width
                    height: 30 * root.unit

                    // Three dots, one after the other: the shell has no spinner of its own.
                    Row {
                        anchors.centerIn: parent
                        spacing: 8 * root.unit

                        Repeater {
                            model: 3

                            Rectangle {
                                id: dot
                                required property int index
                                width: 9 * root.unit
                                height: width
                                radius: width / 2
                                color: root.mt.pInk
                                opacity: 0.25

                                SequentialAnimation on opacity {
                                    running: root.notice.busy && root.visible
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: dot.index * 160 }
                                    NumberAnimation { to: 1; duration: 260 }
                                    NumberAnimation { to: 0.25; duration: 260 }
                                    PauseAnimation { duration: (2 - dot.index) * 160 }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.notice.title
                    color: root.mt.pInk
                    font.family: root.mt.fontFamily
                    font.styleName: root.mt.fontStyleBold
                    font.pixelSize: Math.max(13, Math.round(18 * root.unit))
                }

                Text {
                    visible: root.notice.hint !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.notice.hint
                    color: root.mt.pInkSub
                    font.family: root.mt.fontFamily
                    font.pixelSize: Math.max(11, Math.round(13 * root.unit))
                }

                Item {
                    visible: root.notice.retry
                    width: parent.width
                    height: retryKey.implicitHeight

                    MirrorBadge {
                        id: retryKey
                        anchors.horizontalCenter: parent.horizontalCenter
                        unit: root.unit
                        icon: root.notice.buttonIcon ?? "refresh"
                        label: root.notice.button ?? "Try again"
                        hot: root.mt.attributeColors[1]
                        onClicked: root.retry()
                    }
                }
            }
        }
    }

    // ===== the glass over the picture's corners =====
    // The screen is a rounded rectangle, and the picture is a square: the capture is a texture
    // that the clipping above does not always cut at the curve, and the real scrcpy window
    // under the panel has square corners of its own. So the glass is drawn once more over the
    // picture: a ring in the glass's colour whose inner edge is exactly the screen's curve and
    // whose outer edge is exactly the glass's, so nothing that is not inside the curve can show.
    Rectangle {
        // One pixel into the screen: the ring's inner edge is smoothed, and that smoothing would
        // otherwise let a hairline of whatever is under the corner through.
        readonly property real ring: Math.max(2, root.inset - root.rim) + 1
        x: root.inset - ring + 1
        y: root.inset - ring + 1
        width: root.screenW + 2 * ring - 2
        height: root.screenH + 2 * ring - 2
        radius: root.screenRadius + ring - 1
        color: "transparent"
        border.width: ring
        border.color: root.mt.phoneBezel
        antialiasing: true
    }

    // ===== the notch =====
    // The Quick phone's: flat on the top edge, rounded at the bottom, in the colour of the
    // glass. Its flat edge starts inside the glass (`lead` into the bezel) rather than exactly
    // on the screen's edge, so no hairline of the screen shows between the two shapes. In
    // design units x f, the same numbers as PhoneBody.qml, so it is the same notch.
    Item {
        visible: root.notch
        readonly property real lead: Math.min(14, root.mt.phoneBezelWidth - 2) * root.f
        x: Math.round((root.width - 249 * root.f) / 2)
        y: root.inset - lead
        width: Math.round(249 * root.f)
        height: Math.round(49 * root.f + lead)
        clip: true

        Rectangle {
            y: -Math.round(27 * root.f)
            width: parent.width
            height: parent.height + Math.round(27 * root.f)
            radius: Math.round(27 * root.f)
            color: root.mt.phoneBezel
            antialiasing: true
        }
    }
}
