pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/PhoneMirror.js" as PMir

// Your Android phone, live, on a phone at the left side of the screen (Settings > Quick >
// Phone mirror puts it on the right instead).
//
//   qs -c sekaipop ipc call phonemirror toggle | show | hide
//
// What is here is the window and its layout: a header (the phone's name, restart, open in a
// window, close), the phone itself (MirrorPhone.qml) and the Android keys under it. The
// session, adb, the scrcpy window and where it is put are services/PhoneMirrorService.qml; the
// header of that file explains how the picture and the touches reach the phone.
//
// The window is a layer-shell surface on the Overlay layer that never takes the keyboard
// itself. Clicking the screen goes to the scrcpy window under it, and Hyprland focuses that,
// so the PC's keyboard types into the phone from then on.
//
// One window, on one monitor: the one that was focused when the phone was opened.
Scope {
    id: root

    PanelWindow {
        id: win

        screen: PhoneMirrorService.targetScreen

        readonly property var mt: Theme.of(win)
        readonly property real s: ShellScale.forScreen(win.screen)
        readonly property bool onRight: SettingsService.get("phoneMirror.edge") === "right"

        // 0 hidden .. 1 shown, animated here so hiding can play out.
        property real revealed: 0

        visible: PhoneMirrorService.shown || win.revealed > 0.001
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "sekaipop-phonemirror"
        WlrLayershell.layer: WlrLayer.Overlay
        // Never: the keyboard goes to the scrcpy window under the picture, once it is clicked.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // ===== where it may stand =====
        // Clear of the bar, on whichever edge it is.
        readonly property string barSide: BarPositionService.position
        readonly property real barPx: BarPositionService.reserved * win.s
        readonly property real topInset: win.barSide === "top" ? win.barPx : 0
        readonly property real bottomInset: win.barSide === "bottom" ? win.barPx : 0
        readonly property real sideInset: (win.barSide === (win.onRight ? "right" : "left") ? win.barPx : 0)
            + 12 * win.s

        anchors {
            left: !win.onRight
            right: win.onRight
            top: true
            bottom: true
        }
        margins {
            left: win.onRight ? 0 : Math.round(win.sideInset)
            right: win.onRight ? Math.round(win.sideInset) : 0
            top: Math.round(win.topInset)
            bottom: Math.round(win.bottomInset)
        }

        // ===== sizes (pixels) =====
        readonly property real pad: Math.round(16 * win.s)
        readonly property real headerH: Math.round(50 * win.s)
        readonly property real keysH: Math.round(50 * win.s)
        readonly property real gap: Math.round(10 * win.s)

        readonly property real monitorW: win.screen ? win.screen.width : 1920
        readonly property real monitorH: win.screen ? win.screen.height : 1080
        readonly property real heightShare: Math.max(0.4, Math.min(1, SettingsService.get("phoneMirror.height") / 100))
        readonly property real totalH: (win.monitorH - win.topInset - win.bottomInset - 2 * win.pad) * win.heightShare
        readonly property real maxBodyH: Math.max(200, win.totalH - win.headerH - win.keysH - 2 * win.gap)
        readonly property real maxBodyW: win.monitorW * 0.34

        // The Quick Panel's phone is 654 x 1214 design units; its rim and glass keep that
        // proportion to the body here.
        readonly property real f: win.maxBodyH / 1214
        readonly property int inset: Math.max(8, Math.round(win.mt.phoneScreenInset * win.f))
        readonly property var fit: PMir.fitPhone(win.maxBodyW, win.maxBodyH, PhoneMirrorService.deviceAspect, win.inset)
        readonly property real stick: Math.max(3, Math.round(14 * win.f))
        // The real scrcpy window is a rectangle under the screen, and its corner is `inset` pixels
        // from the phone's edge. The outer curve cannot be rounder than that corner allows or the
        // corner shows outside it. The window is asked to round its own corners (and Hyprland's own
        // rounding, ~20 px, is the least it can be counted on to have), so the bound is worked out
        // for a window rounded by 20: the 45 degree point of its corner, less a border of 2, has to
        // stay inside the outer curve's.
        readonly property real safeRadius: Math.floor((win.inset + 0.2929 * 20 - 1.5) / 0.2929)
        readonly property real bodyRadius: Math.max(10, Math.min(Math.round(100 * win.f),
                                                                  Math.floor(win.fit.bodyW / 2) - 1,
                                                                  win.safeRadius))

        readonly property real contentW: win.fit.bodyW + 2 * win.stick
        readonly property real contentH: win.headerH + win.gap + win.fit.bodyH + win.gap + win.keysH

        implicitWidth: Math.ceil(win.contentW + 2 * win.pad)

        // ===== sliding in and out =====
        Connections {
            target: PhoneMirrorService

            function onShownChanged(): void {
                showAnim.stop()
                hideAnim.stop()
                if (PhoneMirrorService.shown) {
                    showAnim.restart()
                } else {
                    win.settled = false
                    hideAnim.restart()
                }
            }
        }

        NumberAnimation {
            id: showAnim
            target: win
            property: "revealed"
            to: 1
            duration: 280
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: hideAnim
            target: win
            property: "revealed"
            to: 0
            duration: 220
            easing.type: Easing.InCubic
        }

        // ===== where the picture is =====
        // The window goes exactly under the screen once that has stopped moving, and the cut-out
        // in this window's input region opens over it once there is a picture to cover it: a
        // cut-out with nothing painted over it would be a hole straight through to the desktop.
        //
        // An ancestor sliding this phone into place moves the screen without anything being told,
        // so its position is sampled until it stops changing and not bound to something that
        // never updates.
        property rect holeRect: Qt.rect(0, 0, 0, 0)
        property bool settled: false

        readonly property bool placementWanted: PhoneMirrorService.shown && win.settled && win.revealed > 0.999
        readonly property bool touchActive: win.placementWanted && phone.capturing && PhoneMirrorService.placementOk

        function sampleFrame(): void {
            const p = phone.screenFrame.mapToItem(null, 0, 0)
            const next = Qt.rect(Math.round(p.x), Math.round(p.y),
                                 Math.round(phone.screenFrame.width), Math.round(phone.screenFrame.height))
            if (next.x === win.holeRect.x && next.y === win.holeRect.y
                    && next.width === win.holeRect.width && next.height === win.holeRect.height)
                return
            win.holeRect = next
            win.settled = false
            settleTimer.restart()
        }

        // Stops on its own the moment the screen comes to rest, and only runs again when
        // something moves it.
        Timer {
            interval: 60
            repeat: true
            running: win.visible && (!win.settled || win.revealed < 1)
            onTriggered: win.sampleFrame()
        }

        Timer {
            id: settleTimer
            interval: 200
            repeat: false
            onTriggered: win.settled = true
        }

        onHoleRectChanged: PhoneMirrorService.touchRect = win.holeRect
        // A binding, not a handler: the service can restart its session (a Restart, a phone that
        // came back) without this panel changing at all, and the service reads this each time.
        Binding {
            target: PhoneMirrorService
            property: "touchWanted"
            value: win.placementWanted
        }

        Binding {
            target: PhoneMirrorService
            property: "pictureOk"
            value: phone.capturing
        }

        onWidthChanged: win.sampleFrame()
        onHeightChanged: win.sampleFrame()

        Component.onCompleted: {
            PhoneMirrorService.layerNamespace = "sekaipop-phonemirror"
            PhoneMirrorService.cornerRadius = Math.round(phone.screenRadius)
        }

        Connections {
            target: phone

            function onScreenRadiusChanged(): void {
                PhoneMirrorService.cornerRadius = Math.round(phone.screenRadius)
            }
        }

        // ===== the input region =====
        // Only the header, the phone and the keys take the mouse; the room around them lets
        // clicks through to what is below. Over the picture there is a hole in even that: a
        // real scrcpy window sits exactly there with this window painting its picture on top,
        // so a click has to fall through to it.
        Region {
            id: holeRegion
            intersection: Intersection.Subtract
            x: win.holeRect.x
            y: win.holeRect.y
            width: win.holeRect.width
            height: win.holeRect.height
        }

        mask: Region {
            item: content
            regions: win.touchActive ? [holeRegion] : []
        }

        // ===== the board: everything that slides =====
        Item {
            id: board
            width: win.width
            height: win.height
            // Not moved itself: the input region follows `content`, and a region only hears
            // about its own item's x / y. A parent sliding would leave the region where the
            // panel started (off screen), and every click would go to what is behind it.
            x: 0
            opacity: Math.min(1, win.revealed * 1.6)

            Item {
                id: content
                // The slide is in this item's own x, so the input region moves with it.
                x: Math.round((win.onRight ? board.width - win.pad - width : win.pad)
                    + (win.onRight ? 1 : -1) * (1 - win.revealed) * (win.contentW + win.pad + win.sideInset))
                y: Math.round((board.height - height) / 2)
                width: win.contentW
                height: win.contentH

                // ----- header -----
                // The name sits in a pill of its own, like the bar's: the panel is see-through
                // and a wallpaper can be anything. The three keys are the bar's round badges.
                Item {
                    id: header
                    // Room for the name, in the pill's own design units: what the keys leave,
                    // less the pill's padding and the dot.
                    readonly property real nameRoom: Math.max(40, (keysTop.x - Math.round(8 * win.s)) / win.s - 30 - 18)
                    x: win.stick
                    y: 0
                    width: win.fit.bodyW
                    height: win.headerH

                    Row {
                        id: keysTop
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Math.round(8 * win.s)

                        // Start / Stop scrcpy. Lit while it is on.
                        MirrorBadge {
                            unit: win.s
                            icon: PhoneMirrorService.stopped ? "play_arrow" : "stop"
                            lit: !PhoneMirrorService.stopped
                            hot: win.mt.accentMint
                            onClicked: PhoneMirrorService.toggleSession()
                        }

                        MirrorBadge {
                            unit: win.s
                            icon: "refresh"
                            hot: win.mt.attributeColors[2 % win.mt.attributeColors.length]
                            onClicked: PhoneMirrorService.restart()
                        }

                        MirrorBadge {
                            unit: win.s
                            icon: "open_in_new"
                            hot: win.mt.attributeColors[3 % win.mt.attributeColors.length]
                            enabled: PhoneMirrorService.adbReady && PhoneMirrorService.scrcpyAvailable
                            onClicked: PhoneMirrorService.openWindow()
                        }

                        MirrorBadge {
                            unit: win.s
                            icon: "close"
                            hot: win.mt.attributeColors[1 % win.mt.attributeColors.length]
                            onClicked: PhoneMirrorService.hide()
                        }
                    }

                    Pill {
                        id: namePill
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(nameRow.implicitWidth + 30, header.nameRoom + 48)
                        height: 36 + win.mt.shadowOffset
                        transformOrigin: Item.Left
                        scale: win.s
                        cornerRadius: win.mt.radiusBadge
                        ringWidth: 8
                        fillColor: win.mt.surface

                        Row {
                            id: nameRow
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                height: 10
                                radius: 5
                                color: phone.capturing ? "#4cd28a"
                                    : (PhoneMirrorService.embedLaunching ? "#f2b84b" : win.mt.ink)
                                opacity: phone.capturing || PhoneMirrorService.embedLaunching ? 1 : 0.5
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, header.nameRoom)
                                elide: Text.ElideRight
                                text: PhoneMirrorService.deviceName !== "" ? PhoneMirrorService.deviceName : "Phone"
                                color: win.mt.ink
                                font.family: win.mt.fontFamily
                                font.styleName: win.mt.fontStyleBold
                                font.pixelSize: 15
                            }
                        }
                    }
                }

                // ----- the phone -----
                MirrorPhone {
                    id: phone
                    x: win.stick
                    y: win.headerH + win.gap
                    screenW: win.fit.screenW
                    screenH: win.fit.screenH
                    inset: win.inset
                    f: win.f
                    bodyRadius: win.bodyRadius
                    stick: win.stick
                    unit: win.s
                    dpr: win.screen ? win.screen.devicePixelRatio : 1
                    notch: SettingsService.flag("phoneMirror.notch")

                    onRetry: {
                        if (PhoneMirrorService.windowRunning)
                            PhoneMirrorService.closeWindow()
                        else if (PhoneMirrorService.stopped)
                            PhoneMirrorService.start()
                        else
                            PhoneMirrorService.retry()
                    }
                    onXChanged: win.sampleFrame()
                    onYChanged: win.sampleFrame()
                }

                // ----- the Android keys -----
                Item {
                    id: keysBottom
                    x: win.stick
                    y: win.headerH + win.gap + win.fit.bodyH + win.gap
                    width: win.fit.bodyW
                    height: win.keysH

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.round(14 * win.s)
                        enabled: PhoneMirrorService.adbReady

                        MirrorBadge {
                            unit: win.s
                            icon: "arrow_back"
                            hot: win.mt.attributeColors[1 % win.mt.attributeColors.length]
                            onClicked: PhoneMirrorService.sendKey("back")
                        }

                        MirrorBadge {
                            unit: win.s
                            icon: "home"
                            hot: win.mt.attributeColors[2 % win.mt.attributeColors.length]
                            onClicked: PhoneMirrorService.sendKey("home")
                        }

                        MirrorBadge {
                            unit: win.s
                            icon: "crop_square"
                            hot: win.mt.attributeColors[3 % win.mt.attributeColors.length]
                            onClicked: PhoneMirrorService.sendKey("recents")
                        }

                        MirrorBadge {
                            unit: win.s
                            icon: "notifications"
                            hot: win.mt.attributeColors[4 % win.mt.attributeColors.length]
                            onClicked: PhoneMirrorService.openNotifications()
                        }
                    }
                }
            }
        }
    }
}
