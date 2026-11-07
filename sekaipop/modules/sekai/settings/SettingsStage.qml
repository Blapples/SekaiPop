import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import "../../common/functions/FlipMath.js" as FM
import qs.modules.sekai.phone
import qs.modules.sekai.wallpaperSelector

// The landscape phone: a PhoneBody with SettingsFace.qml or WallpaperFace.qml on
// its screen (`content`). It is the Quick Panel's phone on its side, and it
// lives inside the Quick Panel's window (QuickPanel.qml), where it is one half of
// the turn that changes the one phone into the other. The Settings and the
// Wallpapers share it: same body, same 2.5D pose, same turn out of the Quick
// Panel and back. Going between the two while it is up does not turn it again;
// the screen just cross-fades. This file only knows how to draw
// itself at any point of that turn; QuickPanel.qml owns the timing, the window
// and everything that talks to the system. Pure UI.
//
// Where it is on the turn (`flip`, see FlipMath.js):
//   flip = 0   it is the Quick Panel: rolled a quarter turn so it stands up
//              straight, as small as the portrait body, and fully see-through
//   flip = 1   it is the Settings phone: lying down, full size, solid
// In between it rolls from one to the other and fades in over the portrait
// body, which rolls the opposite way and fades out underneath.
//
// It can also come up on its own, with no Quick Panel to turn out of (the
// `ipc call settings show` keybind): then flip stays 1 and `pop` / `alpha` /
// `tilt` do what SettingsPanel.qml used to do, shrinking in with an overshoot
// while the tilt rings out, and the reverse on the way out.
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // ===== 2D =====
    // The Quick Panel's 2D look (Theme.quickFlat: Settings -> Quick -> Quick Panel -> Phone,
    // and always while Game Mode is on), worn by this phone too. In 2D the Settings face
    // straight on the whole time, like the Wallpapers do once they have landed: no tilt,
    // no side wall, a plain rim and notch (PhoneBody `plain`), no tilt on the entrance, the
    // screen drawn straight to the device pixels (`direct`), and the front's own middle
    // (not the tilted pose's) on the middle of the monitor. The buttons' shadows drop
    // straight down (SekaiKey `flatShadow`, set by the Settings' own keys).
    readonly property bool flatLook: mt.quickFlat

    // Where this window's top-left corner is on the monitor, in design pixels. Only the 2D
    // pixel snap reads it (QuickPanel.qml sets it in 2D), so the screen's top-left is put on
    // a whole device pixel of the MONITOR rather than of the window.
    property real gridOffsetX: 0
    property real gridOffsetY: 0

    // ===== what it shows =====
    // "settings" or "wallpapers": which screen is on the phone. Changed while it
    // is up (and still), the screens cross-fade; changed while it is down or
    // turning, the new one is simply there.
    property string content: "settings"
    // Which side the wallpaper gallery starts on: "desktop" or "lock".
    property string initialTarget: "desktop"
    property var source: null
    property var notificationSource: null
    property string screenName: ""
    property string clockText: "00:00AM"
    property string dateText: "Sun, 20  Sep"
    // Only counts while the panel is on screen (the pages are warmed up then).
    property bool active: false

    // ===== the phone itself =====
    property real faceWidth: 1440
    property real faceHeight: 760
    property real cornerRadius: 92

    // How thick the body is. The Quick Panel's is 92 on a phone 654 wide (14%
    // of its width); this phone is more than twice as wide, so the same chunky
    // look needs a bigger number than the width alone would suggest.
    property real thickness: 135

    // How it stands when it's up. 0 / 0 / 0 is dead flat (the side walls
    // disappear). These show the same amount of its right-hand wall (about
    // 40 px) and bottom wall as the Quick Panel's phone does (33 / 18 on a
    // phone half the width); a wide phone turned that far would lean over like
    // a signpost, so it turns less and the camera is further away
    // (`perspective`) to keep the near/far difference between its two ends
    // about the same as the Quick Panel's.
    property real yaw: 24
    property real pitch: 12
    property real roll: 0
    property real perspective: 6000

    // How it arrives on its own: it starts smaller (popFrom of its size) and
    // turned by these many degrees, and pops up to full size with an overshoot
    // while the turn rings out like the Quick Panel's.
    property real popFrom: 0.55
    property real tiltYaw: -22
    property real tiltPitch: 14
    property real tiltRoll: 7
    // How much of that turn the entrance really uses: none in 2D. The numbers above stay the
    // same in 2D on purpose, because they are also the ROOM the phone's picture and the window
    // are made with (`swingYaw/Pitch/Roll` below): the wobble that rings out when the turn lands
    // rolls the phone by a few degrees, and without that room its top (the notch side) was cut
    // off by the edge of the picture while it rang.
    readonly property real tiltK: root.flatLook ? 0 : 1
    // The pop overshoots its size by up to this much.
    readonly property real grow: 1.1

    // ===== where it is and how big =====
    property real fit: 1
    property real centerX: 0
    property real centerY: 0
    // The monitor's device pixel ratio, for drawing the screen at the size it
    // ends up on it (PhoneBody.renderScale).
    property real pixelRatio: 1

    // The turn. `quickFit`, `quickYaw` and `quickPitch` are the Quick Panel
    // phone's own scale and pose, which the turn starts from; `dipDepth` is
    // how much smaller the phone is held in the middle of it.
    property real flip: 1
    property real quickFit: 1
    property real quickYaw: 33
    property real quickPitch: 18
    property real dipDepth: 0.12

    // The entrance on its own (see above); at rest: 1, 1, 0.
    property real pop: 1
    property real alpha: 1
    property real tilt: 0

    // The roll the turn rings out with when it lands (QuickPanel.qml's `ring`),
    // in degrees.
    property real wob: 0

    // The phone is moving (draw it on the light settings), it is busy (a
    // slider is dragged...), and it is part of a turn (make its picture big
    // enough to hold the roll).
    property bool moving: false
    property bool busy: false
    property bool turning: false
    // The turn has landed but is still ringing out: keep the picture and the light settings of
    // the turn (no input is blocked by this, unlike `turning`), so the phone is not redrawn
    // bigger in the middle of the ring (QuickPanel.ringKeepsLite).
    property bool turnHold: false

    // ===== what the others read =====
    readonly property alias phone: phone
    readonly property alias face: face
    // The wallpaper gallery, once it is built (null before and after).
    readonly property var wallpaperFace: wallLoader.item
    readonly property bool wallpapersUp: root.content === "wallpapers"

    // 0 = the Settings on the screen, 1 = the Wallpapers. It only animates when
    // the phone is up and still; at any other time it snaps, so opening the
    // phone straight onto the Wallpapers turns in with them already there.
    property real contentK: root.content === "wallpapers" ? 1 : 0
    Behavior on contentK {
        enabled: root.flip >= 1 && !root.turning && root.pop >= 1 && root.alpha >= 1
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    // ===== standing straight (the Wallpapers) =====
    // The tilted pose is what the Settings rest in, but a tilted screen is drawn
    // twice (once into the body's big picture, then shrunk to the monitor off the
    // pixel grid), which softens small text and thumbnails. The gallery is mostly
    // pictures and small type, so once it has landed and is still it faces straight
    // on and its screen goes straight to the device pixels, exactly like the
    // Overview phone (PhoneBody `faceDirect`). It is tilted the whole way in and out
    // (the turn, the entrance's ring-out), and every drag effect inside the
    // gallery (the wheel's swing and spin) is untouched by it.
    // Off: the gallery rests tilted like the Settings do.
    property bool straightOn: true
    // 2D: both screens face straight on. Otherwise only the Wallpapers do (`straightOn`).
    readonly property real straightGoal: root.flatLook || (root.straightOn && root.content === "wallpapers") ? 1 : 0
    // 0 = the Settings' own pose, 1 = facing straight on. Animates only while the
    // phone is up and still (the Settings <-> Wallpapers swap); at any other time it
    // snaps, so the turn into the Wallpapers simply lands straight.
    property real straightK: root.straightGoal
    Behavior on straightK {
        enabled: root.flip >= 1 && !root.turning && root.pop >= 1 && root.alpha >= 1
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    readonly property bool straightMoving: root.straightK !== root.straightGoal
    // How much of that applies right now: it grows with the turn, so the phone is
    // the Quick Panel's pose where it starts and `straightK` of the way to
    // upright where it lands (and the same on the way back).
    readonly property real straightEff: root.straightK * root.flip
    // The pose the turn lands in, for the Quick Panel's phone to ease toward in
    // step (QuickPanel.qml): the two bodies are the same picture all the way round.
    readonly property real yawEnd: root.yaw * (1 - root.straightK)
    readonly property real pitchEnd: root.pitch * (1 - root.straightK)

    // Design units from the middle of the screen to the far edge of the phone,
    // turned as far as the entrance turns it: what the window has to hold.
    readonly property real halfW: Math.max(phone.screenCenterX + phone.swing.left,
                                           phone.implicitWidth - phone.screenCenterX + phone.swing.right)
    readonly property real halfH: Math.max(phone.screenCenterY + phone.swing.top,
                                           phone.implicitHeight - phone.screenCenterY + phone.swing.top)

    // How see-through it is right now, all things counted.
    readonly property real shownOpacity: alpha * FM.settingsAlpha(flip)

    // The Settings phone drawn at the size of the portrait body it stands in
    // for during the turn is smaller than its resting size by this much; the
    // turn takes it from there to 1 (see FlipMath.quickScale).
    readonly property real turnSize: FM.quickScale(flip, quickFit, fit, dipDepth)
                                     / (FM.SIZE_RATIO * Math.max(0.0001, fit))

    // What it asks for.
    signal closeRequested()
    signal wallpapersRequested()
    signal lockWallpapersRequested()
    signal desktopEditRequested()
    signal keybindsRequested()
    // The Settings' search field is done with the keyboard.
    signal searchLeft()
    // The Wallpapers' X, or Escape on their gallery.
    signal wallpapersCloseRequested()
    // The gallery has been built (it is built a beat after it is asked for).
    signal wallpapersLoaded()

    // Build the gallery now even though it is not on the screen, so it is already
    // there (thumbnails loaded) when the turn into the Wallpapers lands instead of
    // being built after it (QuickPanel.qml sets this while the Apps screen, with
    // the Wallpapers tile, is up).
    property bool warmWallpapers: false

    // The phone is being opened onto a gallery that was built beforehand: its
    // spin-in already played unseen while it waited, so deal it again now.
    function dealIfWarm() {
        if (root.wallpaperFace && root.wallpaperFace.listed)
            root.wallpaperFace.replayDeal()
    }

    // Gives the Wallpapers the keyboard (Escape, arrows, Enter).
    function focusWallpapers() {
        if (root.wallpaperFace)
            root.wallpaperFace.forceActiveFocus()
    }

    // Puts the gallery on the Desktop / Lockscreen side (once it is built;
    // before that `initialTarget` is what it starts on).
    function setTarget(which) {
        root.initialTarget = which === "lock" ? "lock" : "desktop"
        if (root.wallpaperFace) {
            root.wallpaperFace.target = root.initialTarget
            // Every open starts on My folder, unless Wallhaven was asked for
            // (`ipc call wallpaperpicker wallhaven`).
            root.wallpaperFace.setSource(WallhavenService.takeSource())
        }
    }

    // ===== sharpness =====
    readonly property bool settled: flip >= 1 && pop >= 1 && tilt === 0 && wob === 0 && !turning
    readonly property real gridPx: Math.max(1, pixelRatio)
    // Which point of the body stands on the pivot: the tilted pose's screen middle, or in 2D
    // the front's own middle (they are 27 and 14 design units apart for this phone's pose, which
    // is what would otherwise leave a flat phone that far off the middle of the monitor).
    readonly property real anchorX: root.flatLook ? phone.frontCenter.x : phone.screenCenterX
    readonly property real anchorY: root.flatLook ? phone.frontCenter.y : phone.screenCenterY
    readonly property real sceneX: centerX - anchorX * fit - (phone.layerSwing.left + 8) * fit
    readonly property real sceneY: centerY - anchorY * fit - (phone.layerSwing.top + 8) * fit

    // Landed, still and facing straight on: the screen goes straight to the window
    // as a whole number of texels per device pixel (PhoneBody `faceDirect`) and it
    // is the SCREEN's top-left, not the big picture's, that is put on a whole
    // device pixel. `flip === 1` and `straightK >= 1` mean yaw and pitch are
    // exactly 0 after the offsets; `pop === 1` keeps it off while the entrance
    // overshoots.
    readonly property bool direct: root.settled && !root.moving && !root.straightMoving
                                   && root.flip === 1 && root.straightK >= 1
                                   && (root.contentK <= 0 || root.contentK >= 1) && root.pop === 1
    // The straightened phone's front is not where the tilted pose's middle was
    // (see PhoneBody `directCenterX`), and the direct draw lands exactly where the
    // straightening arrived: that is why switching to it moves nothing. The same
    // offset puts the screen's top-left on a whole device pixel below.
    readonly property real directDX: (phone.directCenterX - root.anchorX) * fit
    readonly property real directDY: (phone.directCenterY - root.anchorY) * fit
    readonly property real faceLeftDev: (centerX + directDX + gridOffsetX) * pixelRatio - phone.directW / 2
    readonly property real faceTopDev: (centerY + directDY + gridOffsetY) * pixelRatio - phone.directH / 2

    readonly property real snapX: direct ? (Math.round(faceLeftDev) - faceLeftDev) / pixelRatio
                                         : (settled ? Math.round(sceneX * gridPx) / gridPx - sceneX : 0)
    readonly property real snapY: direct ? (Math.round(faceTopDev) - faceTopDev) / pixelRatio
                                         : (settled ? Math.round(sceneY * gridPx) / gridPx - sceneY : 0)

    // The point everything grows from and turns about: the middle of the
    // screen.
    Item {
        id: pivot

        opacity: root.shownOpacity
        Binding { target: pivot; property: "scale"; value: (root.popFrom + (1 - root.popFrom) * root.pop) * root.turnSize; delayed: true }
        Binding { target: pivot; property: "y"; value: root.centerY + root.snapY; delayed: true }
        Binding { target: pivot; property: "x"; value: root.centerX + root.snapX; delayed: true }
        visible: opacity > 0.001

        PhoneBody {
            id: phone

            landscape: true
            faceWidth: root.faceWidth
            faceHeight: root.faceHeight
            cornerRadius: root.cornerRadius
            thickness: root.thickness
            perspective: root.perspective
            yaw: root.yaw
            pitch: root.pitch
            roll: root.roll

            // Not up: its layer buffers are given back after a while (PhoneBody `warm`).
            windowShown: root.active

            transformOrigin: Item.TopLeft
            Binding { target: phone; property: "scale"; value: root.fit; delayed: true }
            Binding { target: phone; property: "y"; value: -root.anchorY * root.fit; delayed: true }
            Binding { target: phone; property: "x"; value: -root.anchorX * root.fit; delayed: true }

            // (Drawn on the light settings while it straightens, too.)
            moving: root.moving || root.straightMoving
            busy: root.busy
            turnRoll: (root.turning || root.turnHold) ? 90 : 0

            // Standing straight and still: no side wall, and the screen goes
            // straight to the pixels (see `root.direct`).
            // (2D: edge-on the whole time, so the wall is never built, the entrance included.)
            flat: root.direct || (root.flatLook && root.straightK >= 1)
            faceDirect: root.direct
            // The flat design has a plain rim and a plain notch (as the Quick Panel's 2D phone).
            plain: root.flatLook
            // Where the flat front lands, not the tilted pose's middle: no hop when
            // the pixel path takes over.
            directCenterX: phone.frontCenter.x
            directCenterY: phone.frontCenter.y

            // The entrance's turn, plus the turn out of the Quick Panel: rolled
            // a quarter turn the other way and tipped like the portrait phone
            // while flip is 0, easing into its own pose as it comes round.
            rollOffset: root.tilt * root.tiltK * root.tiltRoll + FM.settingsRoll(root.flip) + root.wob
            // (`straightEff`: eased to facing straight on while the Wallpapers are up.)
            pitchOffset: root.tilt * root.tiltK * root.tiltPitch + (root.quickPitch - root.pitch) * (1 - root.flip) + root.wob * 0.5
                         - root.pitch * root.straightEff
            yawOffset: root.tilt * root.tiltK * root.tiltYaw + (root.quickYaw - root.yaw) * (1 - root.flip)
                       - root.yaw * root.straightEff

            // The window has to leave room for how far the entrance turns it.
            swingRoll: root.tiltRoll
            swingPitch: root.tiltPitch
            swingYaw: root.tiltYaw

            // Draw the screen at the size it ends up on the monitor.
            renderScale: root.fit * root.pixelRatio

            SettingsFace {
                id: face

                // Gives way to the Wallpapers (cross-fade); hidden, it costs nothing to draw.
                opacity: 1 - root.contentK
                visible: opacity > 0.001
                enabled: !root.wallpapersUp

                source: root.source
                notificationSource: root.notificationSource
                screenName: root.screenName
                clockText: root.clockText
                dateText: root.dateText
                active: root.active
                // (No page warm-up behind the gallery: it would stall the cross-fade.)
                calm: !root.moving && !root.wallpapersUp
                screenInset: phone.screenInset
                cornerRadius: root.cornerRadius
                renderScale: phone.renderScale

                onCloseRequested: root.closeRequested()
                onWallpapersRequested: root.wallpapersRequested()
                onLockWallpapersRequested: root.lockWallpapersRequested()
                onDesktopEditRequested: root.desktopEditRequested()
                onKeybindsRequested: root.keybindsRequested()
                onSearchLeft: root.searchLeft()
            }

            // The Wallpapers: the gallery (WallpaperFace.qml) on the same screen.
            // Built a beat after the phone starts turning (it reads the wallpaper
            // folder), fades in as it arrives, and goes away with the phone.
            Loader {
                id: wallLoader

                width: root.faceWidth
                height: root.faceHeight
                active: (root.active && (root.wallpapersUp || root.contentK > 0.001)) || root.warmWallpapers
                asynchronous: true

                readonly property real ready: wallLoader.status === Loader.Ready ? 1 : 0
                property real arrive: wallLoader.ready
                Behavior on arrive {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutQuad
                    }
                }

                opacity: root.contentK * wallLoader.arrive
                visible: opacity > 0.001
                enabled: root.wallpapersUp

                onLoaded: {
                    root.setTarget(root.initialTarget)
                    root.wallpapersLoaded()
                }

                sourceComponent: Component {
                    WallpaperFace {
                        screenName: root.screenName
                        clockText: root.clockText
                        dateText: root.dateText
                        screenInset: phone.screenInset
                        cornerRadius: root.cornerRadius
                        renderScale: phone.renderScale

                        onCloseRequested: root.wallpapersCloseRequested()
                    }
                }
            }
        }
    }
}
