import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The frame both readers (manga on the left, novel on the right) are built in, so they read
// as one of the shell's own panels and not as a foreign app glued to the screen edge:
//
//   - a flat card, the same build as the bar's popups: navy outline, inner ring in the dark
//     modes, hard shadow underneath, floating a little off the screen edge;
//   - a header plate on it (SekaiPlate: accent gradient, halftone, slanted bands of stage
//     light) with the reader's name as a sticker, the Browse / Library switch and two keys:
//     minimize and close;
//   - it grows out of its screen edge from nothing, with no overshoot, and shrinks all
//     the way back into it when it goes away. It is a pure scale: no slide, no tilt, and no
//     fade in or out, so it is whole until it has gone into the edge.
//
// Two ways to put it away, both ending in the bare edge (there is no tab on the edge to click):
//
//   - minimize: the card is hidden but kept loaded, so the reader (and its server) keeps
//     running in the background and nothing is lost. The only way back is the shortcut (the
//     host's `toggle` / `show`), which grows the card from the edge again;
//   - close: the card is hidden and the host unloads it a moment later, which stops the reader
//     and its server completely.
//
// The host (ReaderHost.qml) drives it with `open` and reads `reveal` / `swallowed()`. Anything
// declared inside lands in the body under the plate.
Item {
    id: root

    // The screen edge it grows out of.
    property string side: "left"
    property string title: ""
    property color colorTop: Theme.accentMint
    property color colorBottom: Theme.accentCyan
    property int tabIndex: 0
    property var tabLabels: ["Browse", "Library"]
    property real panelWidth: 600
    // Taking the whole screen width (the novel reader's fullscreen).
    property bool wide: false
    // A chapter is being read: the header plate (name, Browse / Library switch, minimize and
    // close keys) slides away and the reader gets the whole card. The panel is still closed with
    // the same toggle that opened it.
    property bool hideHeader: false
    // An optional third window key, between minimize and close, that switches the reader between
    // the whole screen and a side card (the manga reader's). `sizeKeyFull` says which it is in now
    // (it shows the icon for the other one); the reader does the switching in `sizeKeyClicked`.
    property bool sizeKey: false
    property bool sizeKeyFull: false
    readonly property real margin: 12
    // This monitor's shell scale. The panel is laid out in design pixels inside the host's
    // ScaleHost, which draws it at this factor; it is only needed here to draw the card's
    // texture (while it moves) at the size it really is on screen, so it is not soft.
    readonly property real uiScale: ShellScale.forScreen(QsWindow.window ? QsWindow.window.screen : null)

    // Wanted open or not; `reveal` follows it: 0 = away, 1 = shown.
    property bool open: false
    property real reveal: 0
    // True from the moment the panel is asked to close until a moment after the card has shrunk
    // away: the host keeps its window mapped the whole time, and then a few frames longer showing
    // nothing, so the compositor's last picture is an empty one (see SekaiPopup.qml).
    // It has to be up BEFORE `reveal` reaches 0, not set by the animation's `finished` handler:
    // `reveal` hits 0 first, and for that instant nothing else said "still here", so the host
    // unmapped the window and mapped it again at once.
    property bool settling: false
    // Set until the first pop has started (see `onOpenChanged`).
    property bool fresh: true
    // Hidden but kept loaded (minimize): the host leaves it in memory, its server keeps running,
    // and the shortcut brings it back. Closing instead lets the host unload it.
    property bool minimized: false
    // minimize() was pressed and the card is still on its way into the edge: `minimized` is set
    // when it gets there, so the host never unloads it in between.
    property bool pendingMinimize: false
    // The card is being drawn into its texture before it starts to shrink or grow (see
    // `warmTimer` and `restoreWarm`).
    property bool warming: false
    // Drawing the card into a texture while it pops / shrinks. Start the shell with
    // SEKAIPOP_READER_NOLAYER=1 to draw it live instead (to tell whether a hitch is the texture).
    readonly property bool useLayer: Quickshell.env("SEKAIPOP_READER_NOLAYER") !== "1"

    // ── Where the card is, as a rectangle (this item's own coordinates) ───────────────────
    // `reveal` 1 = the card's full rectangle; 0 = the end rectangle: a point on the screen edge,
    // in the middle of the height. In between it is a straight line from one to the other, so
    // the card shrinks and moves as one.
    readonly property real m: Math.max(0, root.reveal)
    // The card's width when it is whole: the panel's width less its two margins.
    readonly property real cardW: Math.max(1, root.width - 2 * root.margin)
    // The width it is drawn at right now. Whole and still it is `cardW`; while the panel changes
    // width (the size key, a chapter going full-screen: see `resizing`) it goes from the old
    // card's width to the new one, and the card is only a picture being scaled meanwhile.
    readonly property real shownCardW: root.resizing ? root.morphFromW + (root.cardW - root.morphFromW) * root.morphE : root.cardW
    readonly property real endL: root.onLeft ? 0 : root.width
    readonly property real endR: root.endL
    readonly property real endT: root.height / 2
    readonly property real endB: root.endT
    readonly property real fullL: root.onLeft ? root.margin : root.width - root.margin - root.shownCardW
    readonly property real fullR: root.onLeft ? root.margin + root.shownCardW : root.width - root.margin
    readonly property real curL: root.endL + (root.fullL - root.endL) * root.m
    readonly property real curR: root.endR + (root.fullR - root.endR) * root.m
    readonly property real curT: root.endT + (root.margin - root.endT) * root.m
    readonly property real curB: root.endB + (root.height - root.margin - root.endB) * root.m

    // What the host lets the pointer touch: the card as it is drawn right now. It is a plain item
    // with real x / y / width / height, not the card itself: the window's input region follows an
    // item's geometry, but a Scale transform changes none of it, so masking the card left the
    // region stuck at the card's size when it was still nothing, and the pointer went straight
    // through the panel.
    readonly property Item hitItem: hit
    // The card is popping or shrinking. The input region stays the card's full rectangle for
    // that time: every change of the region is a request to the compositor, and one per frame
    // of the shrink is work at the moment the animation can least afford it. For 300 ms the
    // pointer is stopped over a card that is already on its way out, which does no harm.
    readonly property bool animating: popIn.running || swallow.running
    // The card is changing width (the size key, a chapter going full-screen). Same reasoning as
    // above: the region is held at the widest the card gets for the whole move, not changed on
    // every frame of it.
    readonly property real holdWidth: root.resizing ? Math.max(root.resizeFrom, root.resizeTo, root.width) : root.width
    readonly property bool holding: root.animating || root.resizing
    Item {
        id: hit
        // Nothing drawn, nothing to touch: when the card is gone (closed or minimized; the window
        // stays mapped) there is no rectangle at all, so a minimized reader takes no input.
        // (On the right edge the held rectangle is measured from the screen edge, so its place
        // on the screen stays put while the panel's own width changes.)
        x: root.holding ? (root.onLeft ? root.margin : root.width - root.holdWidth + root.margin) : root.curL
        y: root.holding ? root.margin : root.curT
        width: root.holding ? Math.max(0, root.holdWidth - 2 * root.margin)
                            : (root.reveal > 0.001 ? Math.max(0, root.curR - root.curL) : 0)
        height: root.holding ? Math.max(0, root.height - 2 * root.margin)
                             : (root.reveal > 0.001 ? Math.max(0, root.curB - root.curT) : 0)
    }
    readonly property bool onLeft: root.side !== "right"

    default property alias content: body.data
    // Keys a reader adds to its header, left of the Browse / Library switch (the manga panel's
    // AniList account key). Empty for a reader that has none.
    property alias headerData: headerExtra.data

    signal swallowed()
    signal sizeKeyClicked()

    // Put it away but keep it running: the card shrinks into the edge and stays loaded.
    // `minimized` itself is set when the card has reached the edge (swallow.onFinished).
    function minimize() {
        root.pendingMinimize = true
        root.open = false
    }

    // Put it away for good: the card shrinks into the edge and the host unloads the reader.
    function close() {
        root.pendingMinimize = false
        root.open = false
    }

    anchors {
        top: parent.top
        bottom: parent.bottom
    }
    // Where the width is going (the whole screen, or the side card), and the width the panel has
    // (`shownWidth`).
    //
    // The change of width is NOT walked a frame at a time any more. Laying the reader out again
    // at every width in between (a grid of dozens of covers, the header, the body) cost more than
    // a frame each, so the first frame stalled, the card sat still for a third of a second and
    // then jumped, and its edge slid over an empty grey card with the content already at its
    // final size. Now it is a picture that moves:
    //
    //   1. the card as it is now is drawn once into `oldSnap` (a few frames, nothing changes);
    //   2. the panel takes its new width at once, ONCE, behind that picture (the one costly
    //      layout; the pointer is held and nothing is on show that could hitch);
    //   3. the old picture and the card at its new size (drawn into a texture, see `card`) are
    //      scaled together from the old rectangle to the new one and cross-faded, which costs
    //      the same on every frame whatever is in the reader.
    //
    // The frame counter drives step 3, and a frame counts for at most 1/30 s of it, so the
    // stall of step 2 is not read as time passed.
    readonly property real targetWidth: (root.wide ? (parent && parent.parent ? parent.parent.width - 2 * root.margin : 1200) : root.panelWidth) + 2 * root.margin
    property real shownWidth: root.targetWidth
    implicitWidth: root.shownWidth
    // Taken by hand from the start: the binding above would otherwise move the width on its own
    // the first time the target changes, before the old card has been drawn.
    Component.onCompleted: root.shownWidth = root.targetWidth

    // The old card is being drawn into `oldSnap` (a few frames before the width changes).
    property bool morphWait: false
    property int morphFrames: 0
    // The move itself: the width is already the new one, the card is scaled from the old
    // rectangle to the new one. (Also what holds the pointer's region and the halftones.)
    property bool resizing: false
    // The old card's width (design pixels) and its picture's size (real pixels).
    property real morphFromW: 0
    property size snapSize: Qt.size(1, 1)
    // 0 -> 1 over `resizeSeconds`, and the same eased in and out.
    property real morphP: 0
    property real resizeFrom: 0
    property real resizeTo: 0
    property real resizeTime: 0
    readonly property real resizeSeconds: 0.36
    readonly property real morphE: root.morphP < 0.5 ? 4 * root.morphP * root.morphP * root.morphP
                                                       : 1 - Math.pow(-2 * root.morphP + 2, 3) / 2
    // How far the new card has faded in over the old picture (which stays whole underneath, so
    // nothing of the desktop shows through in between). Never 0: an item at opacity 0 is skipped,
    // and the new card has to be drawn from the first frame of the move.
    readonly property real fadeT: Math.max(0, Math.min(1, (root.morphP - 0.1) / 0.55))
    readonly property real morphAlpha: Math.max(0.01, root.fadeT * root.fadeT * (3 - 2 * root.fadeT))

    // Step 1.
    function beginMorph() {
        root.morphFromW = card.width
        root.resizeFrom = root.shownWidth
        root.resizeTo = root.targetWidth
        root.snapSize = Qt.size(Math.max(1, Math.ceil(card.width * root.uiScale)),
                                Math.max(1, Math.ceil(card.height * root.uiScale)))
        root.morphFrames = 0
        root.morphWait = true
        oldSnap.scheduleUpdate()
    }

    // Step 2. `resizing` goes up first, so the old rectangle and the texture are already in
    // place when the width changes.
    function applyMorph() {
        root.morphWait = false
        root.morphP = 0
        root.resizeTime = 0
        ReaderEnv.panelBodyTarget = root.targetWidth - 2 * root.margin
        root.resizing = true
        root.shownWidth = root.targetWidth
    }

    // Anything that cannot wait for the move (it is opened, closed or changed again in the
    // middle of one): the panel just takes the width.
    function cancelMorph() {
        root.morphWait = false
        root.resizing = false
        root.shownWidth = root.targetWidth
    }

    onResizingChanged: ReaderEnv.panelResizing = root.resizing

    // ── Desktop Focus Mode ───────────────────────────────────────────────────
    // A card that takes the whole screen is the one thing on that monitor, so Focus Mode counts
    // it as a maximized app: the desktop widgets there hide and stop working while it is up (and
    // a video wallpaper pauses, if "reduce effects" is on), and come back when it goes back to a
    // side card, is minimized or is closed. It follows the monitor it is on, not a workspace.
    readonly property string focusId: "reader:" + root.side
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    readonly property bool takesDesktop: root.wide && root.open && !root.minimized

    function syncFocus() {
        if (root.takesDesktop && root.screenName.length > 0)
            FocusService.claim(root.focusId, root.screenName)
        else
            FocusService.release(root.focusId)
    }
    onTakesDesktopChanged: root.syncFocus()
    // Moved to another monitor while it is up: the old one gets its widgets back
    onScreenNameChanged: { FocusService.release(root.focusId); root.syncFocus() }

    Component.onDestruction: {
        if (root.resizing)
            ReaderEnv.panelResizing = false
        FocusService.release(root.focusId)
    }

    onTargetWidthChanged: {
        ReaderEnv.panelBodyTarget = root.targetWidth - 2 * root.margin
        if (root.morphWait || root.resizing) {
            // changed again in the middle of a move: it takes the width at once
            root.cancelMorph()
            return
        }
        // Moved smoothly only while the card is whole and still; any other time (opening, going
        // away, a screen change) it just takes the width.
        if (root.reveal >= 0.999 && !root.animating && root.visible && root.height > 0
                && root.shownWidth !== root.targetWidth)
            root.beginMorph()
        else
            root.shownWidth = root.targetWidth
    }

    // The few frames the old card needs to be drawn into its picture.
    FrameAnimation {
        running: root.morphWait
        onTriggered: {
            root.morphFrames++
            if (root.morphFrames >= 3)
                root.applyMorph()
        }
    }

    // Step 3.
    FrameAnimation {
        running: root.resizing
        onTriggered: {
            root.resizeTime += Math.min(frameTime, 1 / 30)
            root.morphP = Math.min(1, root.resizeTime / root.resizeSeconds)
            if (root.morphP >= 1)
                root.resizing = false
        }
    }

    visible: root.reveal > 0.001 || root.minimized || root.pendingMinimize

    onOpenChanged: {
        // Opening or closing in the middle of a change of width: it takes the width at once.
        if (root.morphWait || root.resizing)
            root.cancelMorph()
        if (root.open) {
            swallow.stop()
            warmTimer.stop()
            root.warming = false
            settleTimer.stop()
            root.settling = false
            root.pendingMinimize = false
            // Coming back from a minimize: the card has not been drawn since it went away (it
            // was not visible), so its first drawing, the texture and all it holds, would stall
            // the first frames of the grow, and an animation that starts into a stall jumps
            // ahead. Draw it once, as faint as it can be and still be drawn (`opacity` below),
            // and start the grow a few frames later. `reveal` is a hair above 0 so the card is
            // visible for that drawing; it is raised before `minimized` is dropped, so the host
            // never sees the panel as gone in between.
            const fromMin = root.minimized
            if (fromMin && root.reveal < 0.002)
                root.reveal = 0.002
            root.minimized = false
            if (fromMin && !root.fresh) {
                root.warming = true
                restoreWarm.restart()
            } else if (root.fresh) {
                // Building the reader stalls the first frames, and an animation that starts into
                // a stall jumps ahead instead of playing: the very first pop waits a moment.
                // Later opens start at once.
                root.fresh = false
                firstDelay.restart()
            } else {
                popIn.restart()
            }
        } else {
            firstDelay.stop()
            popIn.stop()
            restoreWarm.stop()
            // Hold the host's window from now until the card is gone and a few frames past it
            // (the timer is started by the swallow's `finished`, not before).
            settleTimer.stop()
            root.settling = true
            if (root.reveal >= 0.999) {
                // Whole and still: draw it into its texture first, and shrink a few frames
                // later. Making a texture of a card this size (covers, text, the clipped body,
                // its mipmaps) takes a frame or two, and when that happened on the first frame
                // of the shrink the shrink started with a hitch.
                root.warming = true
                warmTimer.restart()
            } else {
                swallow.restart()
            }
        }
    }

    // The grow out of a minimize starts when the card has been drawn once (see onOpenChanged).
    Timer {
        id: restoreWarm
        interval: 40
        onTriggered: {
            root.warming = false
            if (root.open)
                popIn.restart()
        }
    }

    Timer {
        id: warmTimer
        interval: 34
        onTriggered: {
            swallow.restart()
            root.warming = false
        }
    }

    Timer {
        id: firstDelay
        interval: 60
        onTriggered: popIn.restart()
    }

    Timer {
        id: settleTimer
        interval: 80
        onTriggered: root.settling = false
    }

    // Both start from wherever `reveal` is, so toggling halfway just turns the card round.
    // Same timing and curves as SekaiPopup.qml.
    NumberAnimation {
        id: popIn
        target: root
        property: "reveal"
        to: 1
        // A plain, quick grow out of the edge (also when coming back from a minimize): no
        // overshoot, no bounce.
        duration: 260
        easing.type: Easing.OutCubic
    }

    // Eased at both ends. An ease-IN alone (the popups' own) is fastest at the very end, so a
    // big card was still a sizeable piece of itself on its last drawn frame and then vanished:
    // it looked like it never shrank all the way. This one slows into the point.
    NumberAnimation {
        id: swallow
        target: root
        property: "reveal"
        to: 0
        duration: 180
        easing.type: Easing.InOutCubic
        onFinished: {
            // The card is gone: hold the (now empty) window a few frames longer. `settling` has
            // been up since the close began, so this only starts the countdown.
            root.settling = true
            settleTimer.restart()
            if (root.pendingMinimize) {
                // Minimized: it stays loaded (and running), only hidden.
                root.minimized = true
                root.pendingMinimize = false
            }
            root.swallowed()
        }
    }

    // The card as it was before a change of width, drawn once (`live: false`, `scheduleUpdate()`
    // in `beginMorph`) and then only scaled: under the new card while the panel changes width.
    // Its size and source rectangle are held at the old card's for the whole move, whatever the
    // card itself is by then.
    ShaderEffectSource {
        id: oldSnap
        sourceItem: card
        sourceRect: Qt.rect(0, 0, root.morphFromW, card.height)
        textureSize: root.snapSize
        live: false
        smooth: true
        mipmap: false
        recursive: false
        // Kept in the scene (and a hair above 0, which is skipped) while the old card is drawn
        // into it, or it would not be drawn; the same size as the card then, so it cannot be seen.
        visible: root.morphWait || root.resizing
        opacity: root.morphWait ? 0.01 : 1
        x: root.curL
        y: root.curT
        width: root.morphFromW
        height: card.height
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: (root.curR - root.curL) / Math.max(1, root.morphFromW)
            yScale: (root.curB - root.curT) / Math.max(1, oldSnap.height)
        }
    }

    Pill {
        id: card

        x: root.curL
        y: root.curT
        width: root.width - 2 * root.margin
        height: root.height - 2 * root.margin
        cornerRadius: Theme.radiusOuter + 3
        ringWidth: Theme.borderWidth
        innerRing: Theme.cardRing
        fillColor: Theme.surface

        // Drawn once into a texture while it pops or shrinks, and the texture is what is scaled:
        // the cost of a frame no longer depends on how much is in the reader (dozens of covers,
        // text, a clipped body), which is what made the shrink present only a handful of frames
        // out of the ten it takes. Dropped when it is still again, so the text is drawn sharp.
        layer.enabled: root.useLayer && (popIn.running || swallow.running || root.warming || root.resizing)
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, Math.ceil(card.width * root.uiScale)), Math.max(1, Math.ceil(card.height * root.uiScale)))
        // No mipmaps: the filter that blends them smears the card even at 0.9 of its size, they
        // cost a pass when the texture is made, and the card is moving and fading by the time
        // it is small enough for the plain filter to alias.
        layer.mipmap: false

        // Whole the entire time (no opacity change either way), except for the one drawing that
        // warms it up before the grow out of a minimize: there it is 1 % (not 0: an item at
        // opacity 0 is skipped, so nothing would have been drawn), and at that size it cannot
        // be seen.
        opacity: (root.warming && root.open) ? 0.01 : (root.resizing ? root.morphAlpha : 1)
        visible: card.opacity > 0.001

        // Laid out at its full size, then squashed into the rectangle it is in right now. The
        // transform's origin is the card's own corner, so x / y above say where that corner is.
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: (root.curR - root.curL) / Math.max(1, card.width)
            yScale: (root.curB - root.curT) / Math.max(1, card.height)
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: Math.max(0, card.cornerRadius - card.ringWidth)
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ── Header plate ──────────────────────────────────────────────
                Item {
                    id: headerSlot
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.hideHeader ? 0 : 80
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    clip: true
                    enabled: !root.hideHeader

                    SekaiPlate {
                        id: plate
                        opacity: root.hideHeader ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        x: 10
                        y: 10
                        width: parent.width - 20
                        // (Painted live: the card is laid out once, behind the old picture, so the
                        // halftone is drawn at its new width before anything of it is shown.)
                        height: 56 + Theme.shadowOffset
                        cornerRadius: 16
                        colorTop: root.colorTop
                        colorBottom: root.colorBottom

                        StickerText {
                            id: sticker
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -1
                            text: root.title
                            pixelSize: 26
                            fillColor: plate.numberFill
                            ringColor: plate.numberRing
                            popOnChange: false
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Item {
                                id: headerExtra
                                visible: headerExtra.children.length > 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: childrenRect.width
                                height: 40
                            }

                            SegmentSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 168
                                height: 40
                                options: [
                                    { id: "0", label: root.tabLabels[0] },
                                    { id: "1", label: root.tabLabels[1] }
                                ]
                                current: String(root.tabIndex)
                                onPicked: id => root.tabIndex = parseInt(id)
                            }

                            // The window keys, a tight pair set a little apart from the rest.
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                leftPadding: 4

                                // Hide it but keep it running; only the shortcut brings it back.
                                HeaderKey {
                                    icon: "remove"
                                    onClicked: root.minimize()
                                }

                                // Whole screen <-> side card (only for a reader that asks for it).
                                HeaderKey {
                                    visible: root.sizeKey
                                    icon: root.sizeKeyFull ? "close_fullscreen" : "open_in_full"
                                    onClicked: root.sizeKeyClicked()
                                }

                                // Close it completely (the reader and its server are stopped).
                                HeaderKey {
                                    icon: "close"
                                    onClicked: root.close()
                                }
                            }
                        }
                    }
                }

                // ── Body ──────────────────────────────────────────────────────
                Item {
                    id: body
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }

        // Nothing is clickable while the card is being swallowed. A catcher over it, not
        // `enabled: false` on the card: that reaches every item inside at once, and the reader's
        // keys, chips and menu rows read it (they dim to 40 %), all on the first frame of the
        // shrink.
        MouseArea {
            anchors.fill: parent
            visible: !root.open
            // No hover: taking the hover from the keys and chips under it makes every one of
            // them play its un-hover animation, and each of those redraws the card's texture,
            // all in the first frames of the shrink.
            hoverEnabled: false
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }
    }
}
