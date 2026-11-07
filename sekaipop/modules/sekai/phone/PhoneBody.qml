import QtQuick
import Quickshell
import "../../common/functions/PhoneMath.js" as PM
import qs.modules.common
import qs.services

// The phone the Quick Panel lives in — its "hardware". Whatever you put
// inside a PhoneBody ends up on the phone's screen; this draws the body
// around it and puts the whole thing in a 2.5D pose, modelled on the
// Figma "REFERENCE 2.5 PHONE FOR QUICK PANEL" render:
//
//   - a real thickness: the frame is a solid, so the right-hand side (and
//     a sliver of the bottom) shows, with a bright edge along the front
//     rim fading darker toward the back
//   - side buttons on the right edge (the upper, slim one can be the live Power
//     button, see `powerButton`), and speaker / port holes on the bottom edge
//   - a notch with a camera lens
//   - perspective: the edge nearer the viewer is a little bigger
//
// How the 3D is done: nothing here is a 3D model. The screen is one flat
// layer, and the thickness is the same rounded rectangle repeated many
// times, each one pushed a little further back. Every layer goes through
// the same 4x4 matrix (PhoneMath.js) — a rotation plus perspective — and
// stacked, the offsets between them read as a solid side wall. Because
// they all share one matrix, taps and hover land on the right spot on the
// tilted screen, too.
//
// Pure UI (no Quickshell imports).
Item {
    id: root

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(QsWindow.window)

    // ===== the flat design this is built around =====
    property real faceWidth: 654
    property real faceHeight: 1214
    property real cornerRadius: 100
    // A landscape phone (the Settings Panel): the same body turned a quarter
    // turn anticlockwise, so the camera cut-out is on the LEFT edge, the
    // charging port and speaker holes are on the right-hand wall (the one the
    // yaw turns toward you), and it has no side buttons. The portrait phone is
    // unchanged.
    property bool landscape: false

    // ===== the Power button =====
    // The phone's own side button, for an owner that wants one (the Quick Panel:
    // it used to be a key in the header row). On: the upper, slim button on the
    // right edge is live (hover lights it, a tap sends `powerClicked`); when the
    // phone faces straight on (2D, `flat` / `faceDirect`) there is no side wall to
    // show it on, so it is drawn as a small button standing out of the right
    // edge at the same height instead. `powerOn` keeps it lit (the Power menu is
    // open). Off (the default): both are plain, as they always were.
    property bool powerButton: false
    property bool powerOn: false
    signal powerClicked()
    // Where it sits on the right edge (design units, from the top of the front)
    // and how far the flat one stands out past the front's edge.
    readonly property real powerY: 338
    readonly property real powerH: 150
    // How far the side buttons stand out of the body (design units), on the 2.5D
    // phone (a stack of `buttonSlices` copies) and, bigger, the flat one on the 2D
    // phone. Raise them to make the buttons stand out more.
    readonly property real buttonStick: 14
    readonly property int buttonSlices: 7
    readonly property real powerStick: 18

    // The press: 0 = standing out, 1 = pushed in. The Power button goes in while the pointer
    // is down on it (and for at least `powerHold` ms, so a quick tap still shows) and springs
    // back out on release. 2.5D: the whole stack of copies moves in toward the wall (it keeps
    // `powerKeep` of its height, so the side stays visible); 2D: the flat button slides into
    // the edge and its underside closes up under it.
    property bool powerHeld: false
    readonly property bool powerDown: root.powerHeld || powerHoldTimer.running
    property real powerPress: root.powerDown ? 1 : 0
    readonly property real powerKeep: 0.15
    readonly property real powerStickNow: root.buttonStick * (1 - (1 - root.powerKeep) * root.powerPress)
    readonly property real powerSlide: 11
    Behavior on powerPress {
        NumberAnimation {
            duration: root.powerDown ? 70 : 190
            easing.type: root.powerDown ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 2
        }
    }
    Timer {
        id: powerHoldTimer
        interval: 110
    }

    property real rimWidth: mt.phoneRimWidth          // outer outline, on the front edge
    property real bezelWidth: mt.phoneBezelWidth         // dark glass between rim and screen (was 16: too thick)
    readonly property real screenInset: rimWidth + bezelWidth
    // How far the notch reaches back into the dark glass past the screen's edge, so
    // it and the bezel are one shape (they are the same colour). Inside the glass:
    // it must stay under bezelWidth.
    readonly property real notchLead: Math.min(14, bezelWidth - 2)

    // ===== drop shadow =====
    // A soft, airbrushed shadow behind the whole body, and the cheapest kind there is: ONE
    // 9-sliced picture (assets/images/phone-shadow.png, 282x282, built once: a black rounded
    // rectangle fading out over 40 units), laid on the back face's plane. No blur, no shader,
    // no layer of its own, no extra rectangles; it is drawn outside the phone's multisampled
    // picture, so it does not make that picture any bigger. It sits low and barely to the
    // right (the phone rests on the desktop, lit from above). Design units, so it scales with
    // the phone. `shadow: false` leaves it out.
    //   shadow       follows Settings > Quick > Phone shadow (`quick.phoneShadow`, on by default)
    //   shadowColor  only its alpha is used: the darkest the shadow gets, at the body's edge
    //                (the picture itself is black)
    //   shadowDx/Dy  where it falls
    // The picture is baked for the default corner radius (100) and fade (40).
    property bool shadow: SettingsService.flag("quick.phoneShadow")
    property real shadowDx: 3
    property real shadowDy: 12
    property color shadowColor: Qt.rgba(0, 0, 0, 0.17)
    readonly property real shadowFade: 40
    readonly property real shadowEdge: 140    // 100 corner radius + the 40 fade: the slices

    // ===== pose =====
    property real thickness: 92
    // Degrees. yaw > 0 turns the right edge toward the viewer (showing the
    // right-hand wall); pitch > 0 tips the bottom edge toward the viewer
    // (showing a sliver of the bottom wall, and leaning the vertical
    // edges). roll spins it in the plane of the screen.
    property real yaw: 33
    property real pitch: 18
    property real roll: 0
    // Added on top of the pose above while drawing — but not to the size
    // the phone reports, so animating them (QuickPanel tilts the phone as
    // it comes out of the "pocket") never resizes anything.
    property real yawOffset: 0
    property real pitchOffset: 0
    property real rollOffset: 0

    // The most the offsets above will ever be turned to (and a bit past,
    // for a wobble). Only used to work out how far the phone swings out
    // beyond its resting size — see `swing` — so a window can be made big
    // enough that the turned phone isn't cut off by its edge.
    property real swingYaw: 0
    property real swingPitch: 0
    property real swingRoll: 0
    // How far the phone may be turned in the plane of the screen (degrees,
    // signed: negative is anticlockwise) — the Quick Panel turning into the
    // Settings phone rolls its body by up to 90 (see FlipMath.js). Unlike
    // the swing* values this never changes the size the phone reports (so it
    // can't resize a window); it only makes the picture the phone is drawn into
    // big enough that a phone rolled that far isn't cut off by its edges.
    // Leave it 0 whenever the phone isn't turning: the bigger picture costs
    // sharpness and memory (see `ss`).
    property real turnRoll: 0
    // Camera distance in design units. Bigger = flatter; smaller = more
    // dramatic near/far size difference.
    property real perspective: 3400

    // Texels per design unit at the size the phone ends up on screen.
    // QuickPanel sets this to (display scale x device pixel ratio). It is
    // the *on-screen* size, on purpose: making it bigger yourself (say,
    // plain device pixel ratio) hands the GPU a picture to shrink by some
    // odd factor, and plain bilinear shrinking skips texels, so the outline
    // turns to stair-steps and thin lines break into dashes. The extra
    // resolution comes from `superSample` below instead, which shrinks by
    // an exact factor.
    property real renderScale: 1

    // How much bigger than its on-screen size the whole phone is drawn
    // before the GPU shrinks it back by exactly that much (multisampled
    // on top). 2 = smooth edges, 1 = multisampling only, 0 = off (draw
    // straight to the window, the way it used to be: fine in the middle,
    // but the tilted face's outer edge and the side buttons come out
    // jagged). Costs some graphics memory; it's capped at about 10
    // megapixels at rest (8 while moving — see `moveMegapixels`) for very
    // big / high-DPI screens.
    property real superSample: 2

    // ===== draw quality =====
    property bool moving: false
    property bool busy: false
    property int settleDelay: 150
    property bool crisp: true
    // Was 4 -- the same as `restSamples` since that came down from 8, which
    // quietly made "moving" no lighter than resting on the multisampling side.
    // The body is already drawn at `superSample` x the screen's density and
    // shrunk by that exact factor, so for the second or so it is moving, 2
    // samples on top look the same and halve the bandwidth of the two big
    // passes redone every frame (the wall and the scene). Put it back to 4
    // for the old behaviour.
    property int moveSamples: 2
    // Anti-aliasing samples at rest. This was 8, and it is the biggest memory
    // cost in the whole shell: the phone's three big layers (scene, wall,
    // face) each keep a multisample buffer of  samples x layer size.  On top of
    // the 2x supersampling above, 4 looks the same and uses half the memory.
    // Set it back to 8 for the old look.
    property int restSamples: 4
    property real moveMegapixels: 8
    // While the phone is turning between the Quick Panel and the Settings
    // (turnRoll is not 0) there are two of them being redrawn every frame, each
    // in a bigger picture, so they draw lighter still: fewer samples and a
    // smaller picture. It is only for the second or so of the turn; the full
    // quality comes back once it has landed.
    property int turnSamples: 2
    property real turnMegapixels: 2.5
    readonly property bool turnLite: turnRoll !== 0
    property real restMegapixels: 10

    readonly property bool active: moving || busy

    // ===== graphics memory while it is out of sight (cold / warm) =====
    // Every layer below (scene, wall, face) keeps a multisample colour buffer, a
    // multisample depth/stencil buffer and a resolve texture, at `samples` x
    // the picture's size. Qt keeps them for as long as the layer is switched
    // on, and Quickshell hides a window with a plain setVisible(false), which
    // does not give them back. On an iGPU that memory is system RAM, so a
    // phone that was opened once would hold it for the rest of the session.
    //
    // `windowShown` is set by the owner: is the window this phone lives in
    // mapped? (true = the old behaviour, for an owner that does not say.) A
    // phone that has not been on screen for `coolDelay` ms goes cold: all its
    // layers are switched off and their buffers are freed. The moment it is on
    // screen again it is warm again, in the same event-loop turn, before the
    // first frame is drawn, and every layer is exactly what it was (same size,
    // same samples, same mipmaps). Opening again within `coolDelay` finds the
    // buffers still there. Set `coolDelay` to a huge number (or windowShown to
    // true) to get the old always-resident behaviour back.
    property bool windowShown: true
    property int coolDelay: 20000
    readonly property bool onScreen: windowShown && root.visible
    property bool warm: false

    onOnScreenChanged: {
        if (onScreen) {
            coolTimer.stop()
            warm = true
        } else {
            coolTimer.restart()
        }
    }

    Timer {
        id: coolTimer
        interval: root.coolDelay
        onTriggered: root.warm = root.onScreen
    }

    // What the layers below actually use right now. Only `moving` trims
    // this anymore — see the comment above.
    readonly property int samples: turnLite ? turnSamples : (moving ? moveSamples : restSamples)

    onActiveChanged: {
        if (active) {
            settleTimer.stop()
            crisp = false
        } else {
            settleTimer.restart()
        }
    }

    // A phone that starts out hidden / in motion begins on the light
    // settings, so its very first frame isn't the expensive one.
    Component.onCompleted: {
        crisp = !active
        wallFine = !moving
        warm = onScreen
    }

    // The fine side wall (see `sliceCount`) is only built once the phone
    // has stopped moving, a beat after it lands, so the pull-out itself
    // never has to draw it.
    onMovingChanged: {
        if (moving) {
            wallTimer.stop()
            wallFine = false
        } else {
            wallTimer.restart()
        }
    }

    Timer {
        id: wallTimer
        interval: 140
        onTriggered: root.wallFine = !root.moving
    }

    Timer {
        id: settleTimer
        interval: root.settleDelay
        onTriggered: root.crisp = true
    }

    // The factor actually used (see superSample). Only `moving` trims
    // this now (see the comment above `samples`).
    readonly property real ss: {
        if (superSample <= 0)
            return 1
        const px = scene.width * scene.height * renderScale * renderScale
        const mp = turnLite ? turnMegapixels : (moving ? moveMegapixels : restMegapixels)
        return Math.max(1, Math.min(superSample, Math.sqrt(mp * 1000000 / Math.max(1, px))))
    }

    // Same idea, but for `face` alone (the screen content: buttons,
    // sliders, text -- everything the cursor is actually over while
    // interacting, and what you're looking at while the phone pops in
    // or out). Neither `moving` nor `busy` trims this: it's the layer
    // you're actually focused on while dragging a slider, holding a
    // button, or watching the phone arrive/leave, so it always draws at
    // full quality. `contentTrimmed` is kept (always false) rather than
    // removed outright, so `layer.mipmap` below still reads as a single
    // toggle if a future case ever needs this tier back.
    //
    // Sharpness rule for this layer: the face is drawn flat into a
    // texture, tilted, and drawn into `scene`, which is then shrunk to
    // the monitor. Every one of those steps that isn't 1:1 softens the
    // text. Trilinear mipmapping makes it worse: it blends in the next,
    // half-size level whenever the tilt shrinks the picture even a
    // little (the far side always is), which is a plain blur. So the
    // face is drawn at the SAME texel density as the scene it lands in
    // (`faceOversample` 1, not "a bit more to be safe" -- 1.4 plus
    // mipmaps was measurably softer) and sampled with plain bilinear
    // (`faceMipmap` off): the tilt shrinks it by at most ~1.2x at rest,
    // which bilinear handles without aliasing. Raise `faceMipmap` again
    // only if thin lines shimmer while the phone flies in.
    property real faceOversample: 1
    property bool faceMipmap: false
    readonly property bool contentTrimmed: false
    readonly property real contentSS: {
        if (superSample <= 0)
            return 1
        const px = root.faceWidth * root.faceHeight * renderScale * renderScale
        const cap = Math.sqrt(restMegapixels * 1000000 / Math.max(1, px))
        // Never denser than the scene is at rest (same 10 MP cap, but
        // measured on the scene, which is the bigger picture).
        const sceneCap = Math.sqrt(restMegapixels * 1000000
                                   / Math.max(1, scene.width * scene.height * renderScale * renderScale))
        return Math.max(1, Math.min(superSample * faceOversample, cap, Math.max(1, sceneCap)))
    }
    readonly property int contentSamples: restSamples

    // ===== a flat front, drawn straight to the pixels (faceDirect) =====
    // For a phone that faces straight on and stays that way (the Overview phone
    // once it has landed). Its owner turns this on only while yaw, pitch and roll
    // are exactly 0 after the offsets above.
    //
    // Why: the tilted body draws the front through a 4x4 matrix, and even with
    // every angle at 0 that matrix still scales the front by `flatScale` (the
    // perspective, because the body is centred in its own thickness) and moves it
    // by the resting pose's odd, fractional offsets. So the front's texels never
    // land on the big picture's texels, and the picture is then shrunk to the
    // monitor from a second, unrelated grid: two softening resamples, drifting in
    // and out of phase across the screen.
    //
    // Here the front is instead drawn into a texture that is an exact whole number
    // of times the size it has on the monitor (`directW` x `directH` device pixels,
    // times a whole `directK`), shown with a plain scale and move (no perspective),
    // straight to the window with no big picture in between. The owner puts its
    // top-left on a whole device pixel (see LauncherPhone.qml `snapX`), so one
    // device pixel is exactly `directK` x `directK` texels: the only resample left
    // is a clean box filter.
    property bool faceDirect: false

    // What the 4x4 does to the front plane at yaw = pitch = roll = 0: its z is
    // thickness / 2 after the move to the body's middle, so w = 1 - z / perspective.
    readonly property real flatScale: 1 / (1 - (thickness / 2) / perspective)
    // The front's size on the monitor in whole device pixels. `renderScale` is
    // device pixels per design unit.
    readonly property int directW: Math.max(1, Math.round(faceWidth * flatScale * renderScale))
    readonly property int directH: Math.max(1, Math.round(faceHeight * flatScale * renderScale))
    // Whole number of texels per device pixel (`contentSS`, rounded down).
    readonly property int directK: Math.max(1, Math.floor(contentSS))
    // The same size and scale in design units (what the Matrix4x4 below uses).
    readonly property real directScaleX: directW / Math.max(0.0001, faceWidth * renderScale)
    readonly property real directScaleY: directH / Math.max(0.0001, faceHeight * renderScale)

    // Where the middle of the front lands under the pose being drawn right now
    // (the 4x4's answer for the front's middle, perspective included).
    readonly property var frontCenter: PM.apply(drawBase, faceWidth / 2, faceHeight / 2, 0)
    // Where `faceDirect` puts the middle of the front. It is the middle of the
    // resting screen (screenCenterX / Y) unless the owner says otherwise. Those
    // are NOT where a phone that has straightened from the tilted pose ends up:
    // the body turns about its own middle (half its thickness behind the front),
    // so the flat front's middle is some way from the tilted front's middle (27 and
    // 14 design units for the Settings' pose). An owner that eases a tilted phone
    // flat and then goes direct sets these to `frontCenter`, so that switching to
    // the direct draw does not move the phone.
    property real directCenterX: screenCenterX
    property real directCenterY: screenCenterY

    // The front plane's matrix: the tilted body's 4x4, or with `faceDirect` the
    // plain scale and move (see the front below). Shared with whatever has to
    // stand against the front's edge (the flat Power button).
    readonly property var frontMatrix: root.faceDirect
        ? Qt.matrix4x4(root.directScaleX, 0, 0, root.directCenterX - root.directScaleX * root.faceWidth / 2,
                       0, root.directScaleY, 0, root.directCenterY - root.directScaleY * root.faceHeight / 2,
                       0, 0, 1, 0,
                       0, 0, 0, 1)
        : root.matrix(PM.ident())

    // The phone as it shows right now, as a convex polygon in this item's own
    // coordinates (PM.silhouette): the body, the side buttons, or with the phone flat
    // the Power button standing out of its edge. For a click-away that follows the
    // phone instead of the box around it (QuickPanel.qml, `overPhone`).
    readonly property var outlinePoly: {
        const m = root.frontMatrix
        const base = [m.m11, m.m12, m.m13, m.m14, m.m21, m.m22, m.m23, m.m24,
                      m.m31, m.m32, m.m33, m.m34, m.m41, m.m42, m.m43, m.m44]
        const W = root.faceWidth, T = root.thickness
        let boxes = []
        if (root.landscape) {
            boxes = []
        } else if (root.flat || root.faceDirect) {
            if (root.powerButton)
                boxes = [[W - 4, root.powerY, 0, W + root.powerStick, root.powerY + root.powerH, 0]]
        } else {
            const stick = Math.max(root.buttonStick, root.powerStickNow)
            boxes = [[W, root.powerY, -T * 0.68, W + stick, root.powerY + root.powerH, -T * 0.24]]
            if (!root.plain)
                boxes.push([W, 704, -T * 0.68, W + root.buttonStick, 872, -T * 0.24])
        }
        return PM.silhouette(W, root.faceHeight, (root.flat || root.faceDirect) ? 0 : T,
                             root.cornerRadius, base, boxes)
    }

    // ===== palette =====
    property color rimColor: mt.colBorder             // #555473
    property color rimHighlight: mt.phoneRimHighlight
    property color bezelColor: mt.phoneBezel
    property color screenColor: mt.pSurface
    property color wallLight: mt.phoneWallLight                  // the bright edge
    property color wallMid: mt.phoneWallMid
    property color wallDark: mt.phoneWallDark
    property color hardwareDark: mt.phoneHardware               // holes, lens

    // Whatever is placed inside a PhoneBody goes on the screen.
    default property alias content: contentHost.data

    // Size on screen of the whole posed phone (plus a little padding).
    readonly property var pose: PM.build(faceWidth, faceHeight, thickness, cornerRadius,
                                         yaw, pitch, roll, perspective, 4)
    implicitWidth: pose.w
    implicitHeight: pose.h
    width: implicitWidth
    height: implicitHeight

    // Where the middle of the screen sits inside that size, so a window
    // can be centered on the screen rather than on the whole body.
    readonly property real screenCenterX: pose.cx
    readonly property real screenCenterY: pose.cy

    // How far (in the same units as implicitWidth) the phone reaches past
    // its resting size to the left, right and top while turned as far as
    // the swing* values say.
    readonly property var swing: {
        let minX = pose.pad, maxX = pose.w - pose.pad, minY = pose.pad
        for (const k of [1, 0.5, -0.4]) {
            const b = PM.boundsFor(faceWidth, faceHeight, thickness, cornerRadius,
                                   yaw + swingYaw * k, pitch + swingPitch * k,
                                   roll + swingRoll * k, perspective, pose)
            minX = Math.min(minX, b.minX)
            maxX = Math.max(maxX, b.maxX)
            minY = Math.min(minY, b.minY)
        }
        return { left: pose.pad - minX, right: maxX - (pose.w - pose.pad), top: pose.pad - minY }
    }

    // `swing` for the picture the phone is drawn into (see `scene`): the same,
    // plus the in-plane roll of `turnRoll`, plus the bottom edge (a window
    // never needs that one, the screen's edge is there, but a phone turning
    // about its middle swings out below its resting size as well, and the
    // picture has to hold it). Equal to `swing` (and 0 at the bottom) while
    // turnRoll is 0, so nothing changes until a turn is asked for.
    readonly property var layerSwing: {
        if (turnRoll === 0)
            return { left: swing.left, right: swing.right, top: swing.top, bottom: 0 }
        let minX = pose.pad, maxX = pose.w - pose.pad
        let minY = pose.pad, maxY = pose.h - pose.pad
        // How far along the turn (a little before its start and past its end,
        // for the wind-up and the overshoot) and how far into the entrance tilt.
        for (const kr of [-0.2, 0, 0.25, 0.5, 0.75, 1, 1.2]) {
            for (const k of [1, 0.5, -0.4]) {
                const b = PM.boundsFor(faceWidth, faceHeight, thickness, cornerRadius,
                                       yaw + swingYaw * k, pitch + swingPitch * k,
                                       roll + swingRoll * k + turnRoll * kr, perspective, pose)
                minX = Math.min(minX, b.minX)
                maxX = Math.max(maxX, b.maxX)
                minY = Math.min(minY, b.minY)
                maxY = Math.max(maxY, b.maxY)
            }
        }
        return { left: pose.pad - minX, right: maxX - (pose.w - pose.pad),
                 top: pose.pad - minY, bottom: maxY - (pose.h - pose.pad) }
    }

    // What actually gets drawn: the resting pose plus the offsets.
    readonly property var drawBase: PM.baseFor(faceWidth, faceHeight, thickness,
                                               yaw + yawOffset, pitch + pitchOffset,
                                               roll + rollOffset, perspective, pose)

    // The 4x4 for a plane of the design: `local` maps that plane's own x/y
    // into the design's 3D space (identity for the front face).
    function matrix(local) {
        const m = PM.mul(drawBase, local)
        return Qt.matrix4x4(m[0], m[1], m[2], m[3],
                            m[4], m[5], m[6], m[7],
                            m[8], m[9], m[10], m[11],
                            m[12], m[13], m[14], m[15])
    }

    // Same as matrix(PM.trans(0, 0, z)), for the one place that's called
    // sliceCount times a frame (the depth slices below): PM.zOffset skips
    // the general matrix multiply and the throwaway translation matrix
    // that mul(drawBase, trans(0, 0, z)) would otherwise redo per slice,
    // per frame, for the whole time the phone is tilting in or out.
    function matrixZ(z) {
        const m = PM.zOffset(drawBase, z)
        return Qt.matrix4x4(m[0], m[1], m[2], m[3],
                            m[4], m[5], m[6], m[7],
                            m[8], m[9], m[10], m[11],
                            m[12], m[13], m[14], m[15])
    }

    // Color of the body at depth s (0 = right behind the front rim, 1 =
    // the very back): a bright specular line by the front edge, then a
    // gentle fall-off to dark.
    function wallColor(s) {
        const L = wallLight, M = wallMid, D = wallDark
        const c = PM.ramp([[0.00, M.r * 255, M.g * 255, M.b * 255],
                           [0.05, L.r * 255, L.g * 255, L.b * 255],
                           [0.20, M.r * 255, M.g * 255, M.b * 255],
                           [1.00, D.r * 255, D.g * 255, D.b * 255]], s)
        return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 1)
    }

    // ===== the body =====
    property real wallStepPx: 0.5
    property int maxWallSlices: 200
    property bool wallFine: true

    readonly property int coarseSlices: Math.max(8, Math.round(thickness / 3))

    // How much of the depth turns up as screen distance: 0 when the
    // phone faces straight on, ~0.63 for the resting pose.
    readonly property real wallFoot: {
        const y = Math.sin(Math.abs(yaw) * Math.PI / 180)
        const p = Math.sin(Math.abs(pitch) * Math.PI / 180)
        return Math.max(0.3, Math.sqrt(y * y + p * p))
    }
    readonly property int fineSlices: Math.max(coarseSlices, Math.min(maxWallSlices,
        Math.ceil(thickness * renderScale * wallFoot / Math.max(0.1, wallStepPx))))
    // `flat`: the phone faces straight on and stays that way (the 2D Wallpapers
    // phone once it has landed), so its side wall is edge-on and hidden behind
    // the front; nothing of it is drawn then.
    property bool flat: false
    // Drawn like the flat 2D design: no bright line along the rim and no camera lens in
    // the notch (those two belong to the 2.5D render). The Quick Panel's 2D look sets it.
    property bool plain: false
    readonly property int sliceCount: flat ? 0 : (wallFine ? fineSlices : coarseSlices)

    // The drop shadow, painted first so everything else is on top of it. The back face's
    // plane (the Item x / y shift it after the pose has been applied); the picture is
    // `shadowFade` larger than the face on every side, so it is slid back by that to stay
    // centred under the matrix.
    BorderImage {
        x: root.shadowDx
        y: root.shadowDy
        width: root.faceWidth + 2 * root.shadowFade
        height: root.faceHeight + 2 * root.shadowFade
        visible: root.shadow && !root.flat
        opacity: root.shadowColor.a
        source: "file://" + Directories.asset("images/phone-shadow.png")
        smooth: true
        cache: true
        border.left: root.shadowEdge
        border.right: root.shadowEdge
        border.top: root.shadowEdge
        border.bottom: root.shadowEdge
        transform: Matrix4x4 {
            matrix: root.matrixZ(-root.thickness).times(
                        Qt.matrix4x4(1, 0, 0, -root.shadowFade,
                                     0, 1, 0, -root.shadowFade,
                                     0, 0, 1, 0,
                                     0, 0, 0, 1))
        }
    }

    // ===== the whole phone as one picture =====
    Item {
        id: scene

        readonly property real padL: root.layerSwing.left + 8
        // (+ what the side buttons stand out, so they are not cut off by the layer)
        readonly property real padR: root.layerSwing.right + 8 + Math.max(root.buttonStick, root.powerStick)
        readonly property real padT: root.layerSwing.top + 8
        readonly property real padB: 24 + root.layerSwing.bottom

        x: -padL
        y: -padT
        width: root.width + padL + padR
        height: root.height + padT + padB

        // Not while the front goes straight to the window (faceDirect): there is
        // nothing left to shrink, and the big picture would only be resampled.
        layer.enabled: root.warm && root.superSample > 0 && !root.faceDirect
        layer.samples: root.samples
        layer.smooth: true
        // Without this, shrinking the ss-times-oversized texture down to
        // screen size is a single bilinear tap per pixel — fine when ss
        // lands exactly on 2x, but `ss` is usually some non-integer value
        // (see the ss property above), and a non-integer minification with
        // no mip chain skips texels unevenly. That shows up as stair-steps,
        // worst on the diagonal edges the yaw/pitch tilt creates. Mipmap
        // gives the GPU a proper pre-filtered chain to sample from instead.
        //
        // Used to turn off while `moving`: this picture is redrawn every
        // frame of the pull-out, and rebuilding the mip chain each time
        // was a big part of what made the animation clunky against the
        // old 46-slice, individually-antialiased body -- but that traded
        // a whole second of visibly soft/stair-stepped edges during every
        // open/close for smoothness. Left on unconditionally now that the
        // slice count is down a third (see `sliceCount`) and most of
        // those slices no longer carry their own antialiasing pass (see
        // the depth-slice delegate below) -- there's less scene to rebuild
        // each frame, so the mip chain is cheaper to keep. If a very fast
        // pull-out ever feels choppy again on slower hardware, the first
        // thing to try is `layer.mipmap: !root.moving` back, before
        // touching sliceCount again.
        // Off while the phone turns between the Quick Panel and the Settings
        // (turnLite): two bodies are redrawn every frame then, and rebuilding
        // each one's mip chain every frame is wasted on something that is
        // moving that fast. It comes back, with the full quality, once it lands.
        layer.mipmap: !root.turnLite
        layer.textureSize: Qt.size(Math.ceil(width * root.renderScale * root.ss),
                                   Math.ceil(height * root.renderScale * root.ss))

        // The side wall, in its own layer: the (up to ~200) slices only
        // get redrawn when the pose changes, while the screen in front
        // of them changes all the time. Same size and texel density as
        // `scene`, so it lands in it 1:1 with no resampling.
        //
        // The layer only pays off while the phone is at rest (the pose does
        // not change, so the finished wall is drawn once and then just reused
        // under every hover and slider drag). While the phone moves the pose
        // changes every frame, so the cached wall is thrown away and redrawn
        // every frame anyway, and the layer is pure extra cost: a whole second
        // multisampled picture, its resolve, and a full-size quad to put it into
        // `scene`. So it is only a layer once the fine wall is built
        // (`wallFine`); until then the coarse slices are drawn straight into
        // `scene`'s own multisampled picture, which looks exactly the same
        // (the layer landed there 1:1, same density, same samples).
        Item {
            id: wall

            width: scene.width
            height: scene.height

            layer.enabled: root.warm && root.wallFine && !root.faceDirect && !root.flat
            layer.smooth: true
            layer.samples: Math.min(4, root.samples)
            layer.textureSize: Qt.size(Math.ceil(scene.width * root.renderScale * root.ss),
                                       Math.ceil(scene.height * root.renderScale * root.ss))

            Item {
                x: scene.padL
                y: scene.padT
                width: root.width
                height: root.height

                // A fixed pool of `maxWallSlices` rectangles, the first
                // `sliceCount` of them in use. The count used to be the
                // Repeater's model, so every switch between the coarse and the
                // fine wall (at the start and at the end of every move) created
                // or destroyed ~100-170 items at once: a stall of several
                // milliseconds right where the animation starts or lands. Now
                // the pool is built once and a switch only shows or hides items.
                // An unused one reads none of the pose, so it costs nothing
                // when the pose changes.
                Repeater {
                    model: Math.max(root.maxWallSlices, root.sliceCount)

                    // index 0 is the very back (painted first); the last slice sits
                    // just behind the front face.
                    delegate: Rectangle {
                        required property int index
                        readonly property bool used: index < root.sliceCount
                        readonly property real depth: (root.sliceCount - index) / Math.max(1, root.sliceCount)

                        visible: used
                        width: root.faceWidth
                        height: root.faceHeight
                        radius: root.cornerRadius
                        // Every slice is composited into `scene`'s own
                        // supersampled + MSAA'd layer already, so smoothing
                        // each one's corners individually on top of that is
                        // mostly redundant -- except near the front (depth <
                        // 0.20, the same breakpoint `wallColor`'s ramp uses),
                        // where a slice is both the widest visible sliver and
                        // furthest from being covered by the one in front of
                        // it. Past that the ramp is already most of the way
                        // to flat `wallDark` and each slice is almost fully
                        // hidden behind the next, so there's nothing here for
                        // per-rectangle AA to usefully smooth.
                        antialiasing: root.wallFine || depth < 0.2
                        color: used ? root.wallColor(depth) : "transparent"
                        transform: Matrix4x4 {
                            matrix: used ? root.matrixZ(-depth * root.thickness) : Qt.matrix4x4()
                        }
                    }
                }
            }
        }

        // Everything inside sits where it always did, relative to `root`.
        Item {
            x: scene.padL
            y: scene.padT
            width: root.width
            height: root.height

            // ===== right edge: two buttons =====
            // The base of both buttons, flat on the side wall...
            Item {
                visible: !root.landscape && !root.faceDirect && !root.flat
                width: root.thickness
                height: root.faceHeight
                layer.enabled: root.warm && !scene.layer.enabled
                layer.samples: root.samples
                layer.smooth: true
                transform: Matrix4x4 {
                    matrix: root.matrix([0, 0, 0, root.faceWidth,
                                         0, 1, 0, 0,
                                         -1, 0, 0, 0,
                                         0, 0, 0, 1])
                }

                // Upper: slim (the Power button when `powerButton` is on)
                Rectangle {
                    x: root.thickness * 0.34
                    y: root.powerY
                    width: root.thickness * 0.24
                    height: root.powerH
                    radius: width / 2
                    color: root.wallMid
                    border.width: 2
                    border.color: root.wallDark
                    antialiasing: true
                }

                // Lower: broad (the 2D design has no second button: it would pop up on the
                // side wall while the phone turns to the Settings and back)
                Rectangle {
                    visible: !root.plain
                    x: root.thickness * 0.24
                    y: 704
                    width: root.thickness * 0.44
                    height: 168
                    radius: width / 2
                    color: root.wallMid
                    border.width: 2
                    border.color: root.wallDark
                    antialiasing: true
                }
            }

            // ...and the part that stands out of it: the same two shapes again, each
            // copy moved a little further out of the wall (the way the thickness is
            // built, a stack of copies). The last copy is the button's face: light,
            // outlined, and it is the one that takes the mouse (so the click lands on
            // what you see). The ones under it are its side.
            Repeater {
                model: !root.landscape && !root.faceDirect && !root.flat && !root.plain ? root.buttonSlices : 0

                delegate: Item {
                    id: slice

                    required property int index
                    readonly property bool face: index === root.buttonSlices - 1

                    width: root.thickness
                    height: root.faceHeight
                    transform: Matrix4x4 {
                        matrix: root.matrix([0, 0, 0, root.faceWidth + (slice.index + 1) * root.buttonStick / root.buttonSlices,
                                             0, 1, 0, 0,
                                             -1, 0, 0, 0,
                                             0, 0, 0, 1])
                    }

                    Rectangle {
                        x: root.thickness * 0.24
                        y: 704
                        width: root.thickness * 0.44
                        height: 168
                        radius: width / 2
                        color: slice.face ? root.wallLight : root.wallMid
                        border.width: slice.face ? 2 : 0
                        border.color: root.wallDark
                        antialiasing: true
                    }
                }
            }

            // The Power button's own copies: the same stack as above, but with its own
            // depth, so pressing it moves just this button (`powerPress`).
            Repeater {
                model: !root.landscape && !root.faceDirect && !root.flat ? root.buttonSlices : 0

                delegate: Item {
                    id: pslice

                    required property int index
                    readonly property bool face: index === root.buttonSlices - 1

                    width: root.thickness
                    height: root.faceHeight
                    transform: Matrix4x4 {
                        matrix: root.matrix([0, 0, 0, root.faceWidth + (pslice.index + 1) * root.powerStickNow / root.buttonSlices,
                                             0, 1, 0, 0,
                                             -1, 0, 0, 0,
                                             0, 0, 0, 1])
                    }

                    Rectangle {
                        id: powerSlice

                        readonly property bool lit: root.powerButton && (root.powerOn || powerSliceArea.containsMouse)

                        x: root.thickness * 0.34
                        y: root.powerY
                        width: root.thickness * 0.24
                        height: root.powerH
                        radius: width / 2
                        color: !pslice.face ? root.wallMid
                               : (powerSliceArea.pressed ? mt.accentCyan : (lit ? mt.accentMint : root.wallLight))
                        border.width: pslice.face ? 2 : 0
                        border.color: root.wallDark
                        antialiasing: true

                        // A little wider than it looks: the button is thin on the wall.
                        MouseArea {
                            id: powerSliceArea

                            enabled: root.powerButton && pslice.face
                            anchors.fill: parent
                            // (The face moves in depth while pressed, a few pixels sideways in
                            // the picture, so a press near its edge still ends on it.)
                            anchors.leftMargin: -18
                            anchors.rightMargin: -18
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressedChanged: {
                                root.powerHeld = pressed
                                if (pressed)
                                    powerHoldTimer.restart()
                            }
                            onClicked: root.powerClicked()
                        }
                    }
                }
            }

            // ===== bottom edge =====
            Item {
                visible: !root.landscape && !root.faceDirect && !root.flat
                width: root.faceWidth
                height: root.thickness
                layer.enabled: root.warm && !scene.layer.enabled
                layer.samples: root.samples
                layer.smooth: true
                transform: Matrix4x4 {
                    matrix: root.matrix([1, 0, 0, 0,
                                         0, 0, 0, root.faceHeight,
                                         0, -1, 0, 0,
                                         0, 0, 0, 1])
                }

                readonly property real hole: root.thickness * 0.26
                readonly property real midY: root.thickness / 2

                // Charging port
                Rectangle {
                    x: root.faceWidth / 2 - 46
                    y: parent.midY - root.thickness * 0.21
                    width: 92
                    height: root.thickness * 0.42
                    radius: height / 2
                    color: root.hardwareDark
                    antialiasing: true
                }

                // Speaker holes, five on the right and three on the left
                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        width: parent.hole
                        height: parent.hole
                        radius: width / 2
                        x: root.faceWidth / 2 + 78 + index * 30
                        y: parent.midY - height / 2
                        color: root.hardwareDark
                        antialiasing: true
                    }
                }

                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: parent.hole
                        height: parent.hole
                        radius: width / 2
                        x: root.faceWidth / 2 - 78 - parent.hole - index * 30
                        y: parent.midY - height / 2
                        color: root.hardwareDark
                        antialiasing: true
                    }
                }
            }

            // ===== landscape =====
            Item {
                visible: root.landscape && !root.faceDirect && !root.flat
                width: root.thickness
                height: root.faceHeight
                layer.enabled: root.warm && !scene.layer.enabled
                layer.samples: root.samples
                layer.smooth: true
                transform: Matrix4x4 {
                    matrix: root.matrix([0, 0, 0, root.faceWidth,
                                         0, 1, 0, 0,
                                         -1, 0, 0, 0,
                                         0, 0, 0, 1])
                }

                readonly property real hole: root.thickness * 0.26
                readonly property real midY: root.faceHeight / 2

                // Charging port
                Rectangle {
                    x: root.thickness / 2 - root.thickness * 0.21
                    y: parent.midY - 46
                    width: root.thickness * 0.42
                    height: 92
                    radius: width / 2
                    color: root.hardwareDark
                    antialiasing: true
                }

                // Speaker holes, five below the port and three above it
                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        width: parent.hole
                        height: parent.hole
                        radius: width / 2
                        x: root.thickness / 2 - width / 2
                        y: parent.midY + 78 + index * 30
                        color: root.hardwareDark
                        antialiasing: true
                    }
                }

                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: parent.hole
                        height: parent.hole
                        radius: width / 2
                        x: root.thickness / 2 - width / 2
                        y: parent.midY - 78 - height - index * 30
                        color: root.hardwareDark
                        antialiasing: true
                    }
                }
            }

            // ===== the Power button, phone facing straight on =====
            // No side wall to show the 3D button on, so it stands out of the right
            // edge as a small lavender button at the same height. Moved with exactly
            // the front's matrix, and drawn BEFORE the front, so the front's edge
            // covers the few units of it that sit under the rim.
            Item {
                visible: root.powerButton && (root.flat || root.faceDirect) && !root.landscape
                width: root.faceWidth
                height: root.faceHeight
                transform: Matrix4x4 { id: fm1 }
                Binding { target: fm1; property: "matrix"; value: root.frontMatrix; delayed: true }

                // Its underside: the same shape a few units lower, dark, so the button
                // reads as standing out of the edge rather than lying on it.
                Rectangle {
                    x: root.faceWidth - 4 - root.powerSlide * root.powerPress
                    y: root.powerY + 5 * (1 - root.powerPress)
                    width: root.powerStick + 4
                    height: root.powerH
                    radius: 8
                    color: root.wallDark
                    antialiasing: true
                }

                Rectangle {
                    id: powerTab

                    readonly property bool lit: root.powerOn || powerTabArea.containsMouse

                    x: root.faceWidth - 4 - root.powerSlide * root.powerPress
                    y: root.powerY + 4 * root.powerPress
                    width: root.powerStick + 4
                    height: root.powerH
                    radius: 8
                    color: powerTabArea.pressed ? mt.accentCyan : (lit ? mt.accentMint : root.wallLight)
                    border.width: 2
                    border.color: root.wallDark
                    antialiasing: true
                }

                // The click area stays where the button rests (it is not the button's child):
                // the button slides in under the pointer, and a press near its outer edge
                // must still end on it.
                MouseArea {
                    id: powerTabArea

                    enabled: root.powerButton
                    x: root.faceWidth
                    y: root.powerY - 6
                    width: root.powerStick + 6
                    height: root.powerH + 12
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressedChanged: {
                        root.powerHeld = pressed
                        if (pressed)
                            powerHoldTimer.restart()
                    }
                    onClicked: root.powerClicked()
                }
            }

            // ===== the front =====
            Item {
                id: face

                width: root.faceWidth
                height: root.faceHeight
                // Normally the tilted body's 4x4. With `faceDirect` it is just the
                // plain scale and move the 4x4 comes to when everything is flat, with
                // the scale taken to a whole number of device pixels (see `directW`)
                // and the middle of the front where the owner wants it (directCenterX /
                // directCenterY, the resting screen's middle unless set). The owner
                // puts the result on a whole device pixel.
                transform: Matrix4x4 { id: fm2 }
                Binding { target: fm2; property: "matrix"; value: root.frontMatrix; delayed: true }

                // Drawn flat into a texture first (smoothed, at the size it will be
                // in the big picture above), then tilted: crisp edges and text on
                // the tilted plane.
                layer.enabled: root.warm
                layer.samples: root.contentSamples
                layer.smooth: true
                // This is the plane the yaw/pitch tilt actually rotates in
                // 3D, so the GPU samples it at a steep, non-uniform angle —
                // more foreshortened toward the far edge than the near one.
                // A flat bilinear tap can't minify that correctly (it's
                // exactly the "jagged distant floor texture" problem from
                // 3D rendering); mipmap gives it a filtered chain to draw
                // from at each point on the tilted quad instead. Always on
                // here (unlike `scene` below): this texture is captured
                // flat, before the tilt is applied (see `contentSS`'s
                // comment above for why that means it isn't rebuilt every
                // frame just because the phone is moving), so there's no
                // per-frame cost tied to keeping mipmap on that `moving`
                // would actually be saving.
                //
                // Resolution/samples here come from `contentSS`/
                // `contentSamples`, not the shared `ss`/`samples` the body
                // uses -- this is the actual screen content (what the
                // cursor sits over while interacting, and what you're
                // looking at while the phone pops in or out). Neither
                // `moving` nor `busy` trims it (see the comment up at
                // `contentTrimmed`), so opening/closing the panel, dragging
                // a slider, or holding a button down never blurs it.
                //
                // Mipmap always stays on for the same reason -- always on,
                // matching `contentTrimmed` always being false.
                layer.mipmap: root.faceMipmap && !root.contentTrimmed
                // `faceDirect`: a whole number of texels per device pixel, so the
                // shrink to the monitor is a clean box filter (see `directW`).
                layer.textureSize: root.faceDirect
                                   ? Qt.size(root.directW * root.directK, root.directH * root.directK)
                                   : Qt.size(Math.ceil(root.faceWidth * root.renderScale * root.contentSS),
                                             Math.ceil(root.faceHeight * root.renderScale * root.contentSS))

                // Outline (the front edge of the metal frame)
                Rectangle {
                    anchors.fill: parent
                    radius: root.cornerRadius
                    color: root.rimColor
                    antialiasing: true
                }

                // A thin bright line along it, like the highlight on the
                // reference render's rim
                Rectangle {
                    visible: !root.plain
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: root.cornerRadius - 2
                    color: "transparent"
                    border.width: 2
                    border.color: root.rimHighlight
                    antialiasing: true
                }

                // Dark glass
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.rimWidth
                    radius: root.cornerRadius - root.rimWidth
                    color: root.bezelColor
                    antialiasing: true
                }

                // Screen
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.screenInset
                    radius: root.cornerRadius - root.screenInset
                    color: root.screenColor
                    antialiasing: true
                }

                // The panel's own UI
                Item {
                    id: contentHost
                    anchors.fill: parent
                }

                // Notch: flat on the top edge, rounded at the bottom. Its flat edge
                // starts inside the dark glass (notchLead into the bezel, which is the
                // same colour) rather than exactly on the screen's edge: two shapes
                // that meet on one line leave a hairline of the screen showing
                // between them wherever the line is off the pixel grid (it shows when
                // the front is drawn straight to the pixels, see `faceDirect`).
                Item {
                    visible: !root.landscape
                    x: 202
                    y: root.screenInset - root.notchLead
                    width: 249
                    height: 49 + root.notchLead
                    clip: true

                    Rectangle {
                        y: -27
                        width: parent.width
                        height: parent.height + 27
                        radius: 27
                        color: root.bezelColor
                        antialiasing: true
                    }

                    // Camera lens
                    Rectangle {
                        visible: !root.plain
                        x: 24
                        y: 15 + root.notchLead
                        width: 22
                        height: 22
                        radius: 11
                        color: root.hardwareDark
                        antialiasing: true

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: mt.phoneLens
                            antialiasing: true

                            Rectangle {
                                x: 2
                                y: 2
                                width: 3
                                height: 3
                                radius: 1.5
                                color: mt.phoneLensGlint
                            }
                        }
                    }
                }
                // Landscape cut-out: the same notch turned to the LEFT edge. Flat
                // on the rim, rounded toward the screen, in the middle of the
                // edge, with the lens at the end the portrait phone's lens turns to.
                Item {
                    visible: root.landscape
                    x: root.screenInset - root.notchLead
                    y: (root.faceHeight - 249) / 2
                    width: 49 + root.notchLead
                    height: 249
                    clip: true

                    Rectangle {
                        x: -27
                        width: parent.width + 27
                        height: parent.height
                        radius: 27
                        color: root.bezelColor
                        antialiasing: true
                    }

                    // Camera lens: where the portrait notch has it (24 px in
                    // from the end that is its left), turned a quarter turn with
                    // it, so it sits at the bottom end of this one.
                    Rectangle {
                        visible: !root.plain
                        x: 15 + root.notchLead
                        y: 249 - 24 - 22
                        width: 22
                        height: 22
                        radius: 11
                        color: root.hardwareDark
                        antialiasing: true

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: mt.phoneLens
                            antialiasing: true

                            Rectangle {
                                x: 2
                                y: 2
                                width: 3
                                height: 3
                                radius: 1.5
                                color: mt.phoneLensGlint
                            }
                        }
                    }
                }

            }
        }
    }
}
