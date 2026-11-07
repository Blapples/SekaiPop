import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.sekai.editMode

// The Wayland background itself — no swww, no hyprpaper, no swaybg.
// This PanelWindow, on WlrLayer.Background, is the only thing on the
// whole system that's allowed to own that layer (see "sole
// background-layer client" below). Instantiated once per screen from
// shell.qml, the same way Bar.qml is. Each instance shows the wallpaper
// WallpaperService.pathFor() gives for its own monitor and runs its own
// transition, so with "One wallpaper per monitor" on, changing one
// monitor leaves the others alone:
//
//   Variants {
//       model: Quickshell.screens
//       WallpaperLayer {}
//   }
//
// *** Why this file destroy()s texture slots instead of reusing them ***
// end4-pC's background layer keeps two Image items alive for the
// whole session and just reassigns their `source` url on every
// wallpaper switch (modules/ii/background/Background.qml's
// `previousWallpaper`/`wallpaper`, both with `layer.enabled: true` so
// a ShaderEffect can sample them as textures). That layer is a real
// FBO + GPU texture Qt's scene graph allocates once and tries to reuse
// across `source` changes. The node itself never goes away, so nothing
// ever forces the scene graph to actually release the texture it held
// for the *previous* image — it just hopes reassigning `source` on a
// surviving node reclaims it. Fast repeated switches (arrow-key preview
// in a picker, a short slideshow interval) are exactly the case where
// that hope doesn't hold up and memory climbs.
//
// The fix: the two texture slots below (WallpaperTextureSlot.qml
// instances) are never long-lived. Every switch creates a brand new
// slot for the incoming image, and the moment a slot is done being
// blended out it is destroy()ed outright — Image, layer, FBO, scene
// graph node, all of it — rather than kept around for its `source` to
// be overwritten next time. See swapTo()/finishLocalTransition() below.
PanelWindow {
    id: win

    // This monitor's theme: Theme.of() gives the shell's own unless the monitor has one.
    readonly property var mt: Theme.of(screen)

readonly property bool wallpaperEnabled:SettingsService.flag("wallpaper.enabled")
onWallpaperEnabledChanged: {
    if (wallpaperEnabled)
        restoreWallpaperResources();
    else
        releaseWallpaperResources();
}
    required property var modelData
    screen: modelData

    // ===== sole background-layer client =====
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "sekaipop-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent" // shown before the first image finishes decoding

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Decode wallpapers at the monitor's required pixel size instead of
    // keeping an 4K/8K source fully decoded in RAM. The extra parallax
    // margin is intentional: it prevents the image from running out of
    // pixels while it slides across the monitor. If the QML window is
    // already expressed in physical pixels, the geometry/window ratio is
    // 1; otherwise it resolves to the monitor's device-pixel ratio.
    //
    // This is a decode-size cap, not a visual downscale of the window: Qt
    // still renders the wallpaper at the monitor's actual output size, but
    // the source texture contains only the pixels that can actually be
    // displayed. A source image smaller than this is never upscaled.
    readonly property real outputPixelRatio: {
        if (!win.screen)
            return 1;
        const logicalW = Math.max(1, width);
        const logicalH = Math.max(1, height);
        const geometry = win.screen.geometry;
        const geometryRatio = geometry
            ? Math.max(geometry.width / logicalW, geometry.height / logicalH)
            : 1;
        return Math.max(1, Math.min(win.screen.devicePixelRatio || 1, geometryRatio || 1));
    }
    readonly property size sourceSize: Qt.size(
        Math.ceil(width * win.parallaxZoom * win.outputPixelRatio),
        Math.ceil(height * win.parallaxZoom * win.outputPixelRatio))

    // ===== Parallax =====
    readonly property bool parallaxOn: SettingsService.flag("wallpaper.parallax")
    readonly property real parallaxZoom: parallaxOn ? 1 + SettingsService.get("wallpaper.parallaxAmount") / 100 : 1
    readonly property var hyprMonitor: win.screen ? Hyprland.monitorFor(win.screen) : null
    readonly property int workspaceId: hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : 1
    readonly property int workspaceCount: Math.max(2, SettingsService.get("wallpaper.parallaxWorkspaces"))
    // 0 .. 1 across the workspaces.
    readonly property real parallaxFraction: Math.max(0, Math.min(1, (win.workspaceId - 1) / (win.workspaceCount - 1)))

    // ===== Video wallpaper: pause while nobody can see it =====
    // The video decodes and draws every frame forever, so it is the one thing on the desktop
    // that keeps the GPU busy while you are idle. It is always paused while the lock screen is up.
    // Settings -> Desktop -> Wallpaper -> "Pause video when" picks the rest:
    //   never       only the lock screen pauses it
    //   fullscreen  also while a fullscreen window is on this monitor's active workspace (default)
    //   windows     also while that workspace has any window at all
    readonly property var activeWs: win.hyprMonitor ? win.hyprMonitor.activeWorkspace : null
    readonly property var wsInfo: win.activeWs && win.activeWs.lastIpcObject ? win.activeWs.lastIpcObject : null
    readonly property bool fullscreenCovered: !!(win.wsInfo && win.wsInfo.hasfullscreen)
    readonly property bool hasWindows: !!(win.wsInfo && win.wsInfo.windows > 0)
    readonly property string pauseMode: SettingsService.get("wallpaper.videoPause")
    // Desktop Focus Mode's "Reduce expensive effects": a window on this monitor pauses the video too.
    readonly property bool focusReduced: FocusService.effectsReducedOn(win.screenName)
    readonly property bool videoCoveredNow: win.focusReduced || (win.pauseMode === "windows" ? (win.hasWindows || win.fullscreenCovered)
        : win.pauseMode === "never" ? false
        : win.fullscreenCovered)
    // When the desktop comes back (the last window leaves this monitor) the desktop widgets pop in one
    // after another (FocusMath.STAGGER_MS apart, then their own pop-in). Resuming or restarting the video
    // in the same moment makes the two fight for the GPU and the pop-in stutters, so the video stays on
    // its paused frame a little longer and carries on once the widgets have settled.
    property bool wakeHold: false
    readonly property bool videoCovered: win.videoCoveredNow || win.wakeHold
    onVideoCoveredNowChanged: {
        if (win.videoCoveredNow) {
            wakeHoldTimer.stop()
            win.wakeHold = false
        } else if (videoLayer.active) {
            win.wakeHold = true
            wakeHoldTimer.restart()
        }
    }
    Timer {
        id: wakeHoldTimer
        // The last widget starts 770 ms after the first (FocusMath.SLOTS) and pops in for about 460 ms.
        interval: 1300
        onTriggered: win.wakeHold = false
    }

    // mpvpaper plays the video on its own surface (see MpvpaperWallpaper.qml); if it can't start
    // the built-in QtMultimedia player is used for the rest of this session.
    property bool mpvpaperFailed: false
    readonly property bool useMpvpaper: SettingsService.flag("wallpaper.mpvpaper") && !win.mpvpaperFailed
    // What pausing means: "pause" continues where it stopped, "restart" starts the video over.
    // While the screen is locked and the desktop sleeps (LockState.desktopAsleep) the mpvpaper process is
    // stopped as well, not just paused: a paused mpvpaper still holds the whole video in RAM and VRAM
    // (about 280 MiB each of them, per monitor). The still frame under it shows meanwhile, and the
    // process is started again as the unlock begins (paused, on its first frame, so it matches the still
    // one) and plays from the start once the unlock ring has finished. Only mpvpaper: the built-in player
    // lives in this window and is just paused.
    readonly property bool restartOnPause: SettingsService.get("wallpaper.videoResume") === "restart"
        || (win.useMpvpaper && LockState.desktopAsleep)
    // Edit Desktop shrinks this monitor's wallpaper into a card. The built-in player lives inside
    // that card, so pausing is enough (it freezes on the frame it was showing and shrinks with it).
    // mpvpaper is a separate full-screen surface that can't shrink, so while editing it saves the
    // frame it is on and stops (`hidden`); the card shows that frame ("frozen" below), and the
    // video carries on from there when editing ends.
    readonly property bool videoEditing: EditMode.editing(win.screenName)
    readonly property bool videoPausedBase: LockState.phase !== "idle" || win.videoCovered
    readonly property bool videoPaused: win.videoPausedBase || win.videoEditing

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "fullscreen" || event.name === "workspace" || event.name === "workspacev2"
                    || event.name === "focusedmon" || event.name === "openwindow" || event.name === "closewindow"
                    || event.name === "movewindow" || event.name === "movewindowv2")
                fullscreenRefresh.restart()
        }
    }

    Timer {
        id: fullscreenRefresh
        interval: 150
        onTriggered: {
            if (videoLayer.active)
                Hyprland.refreshWorkspaces()
        }
    }

    // Per-monitor: this layer shows whatever WallpaperService says THIS
    // monitor shows (one wallpaper everywhere unless "One wallpaper per
    // monitor" is on), and runs its own transition when that changes. There
    // is no shared progress value and no "primary" layer to elect: a switch
    // on one monitor never touches another monitor's layer.
    readonly property string wantedPath: WallpaperService.pathFor(win.screenName)
    // The picture to decode for it. A video is shown as its first frame, which
    // can be empty for a moment after a restart; an empty one is ignored and
    // the layer keeps what it has until the frame turns up.
    readonly property string wantedImage: WallpaperService.imageFor(win.wantedPath)
    // The picture currentSlot below was made for.
    property string shownImage: ""
    // 0 at the start of a switch, 1 once it has finished. Only this layer's
    // blendAnim writes it.
    property real progress: 1.0
    // The transition style THIS switch plays. Taken from WallpaperService when
    // the switch starts (show() below), so with "Random" every change gets its
    // own style, and a style or setting change mid-blend can't swap shaders
    // under a blend that is already running.
    property string activeStyle: "sekaiRing"
    // True while an outgoing picture is still being blended out.
    readonly property bool transitioning: win.previousSlot !== null

    property Item previousSlot: null
    property Item currentSlot: null

    Component {
        id: textureSlotComponent
        WallpaperTextureSlot {}
    }

    function createSlot(image) {
        // win is a real Wayland window (PanelWindow), not a plain
        // Item — declaring children of it directly in QML works
        // because the engine special-cases that at parse time, but
        // Component.createObject() doesn't get that treatment. Handing
        // it `win` just sets the new Image's `parent` property without
        // ever attaching it to the window's actual scene graph, so it
        // exists (bindings on it evaluate fine) but never draws —
        // exactly the "Created graphical object was not placed in the
        // graphics scene" warning. win.contentItem is the window's
        // real content root and the correct target for imperative
        // reparenting. (Here it is `stage`, a full-window Item that
        // Edit Desktop shrinks into its card; see below.)
        // sourceSize goes in with the initial properties so the decode
        // starts once, at the output's size. Setting it after `source`
        // used to make the Image throw away its first (full-size) decode
        // and start over, which made the wait for a big wallpaper longer.
        const obj = textureSlotComponent.createObject(pic, {
            sourceSize: win.sourceSize,
            source: image ? ("file://" + image) : ""
        });
        // The decode size follows the window only until the picture has
        // decoded (the window may still be getting its size at start-up).
        // After that it is FROZEN (see the statusChanged handler): an Image
        // that is told a new sourceSize throws its picture away and decodes
        // again, and shows nothing until that is done, which is what made the
        // wallpaper blink black while the Parallax settings were being
        // changed (they change the size the picture is decoded at). A change
        // of size on a settled picture is handled by redecode() below, which
        // decodes the new size UNDER the one on screen and swaps silently.
        obj.sourceSize = Qt.binding(() => win.sourceSize);
        // Start the blend once this slot has really decoded, or the
        // incoming wallpaper is still an empty texture and the wipe
        // reveals black. (Error counts too, or a bad file would stall
        // the switch until readyTimeout below.)
        obj.statusChanged.connect(() => {
            const done = obj.status === Image.Ready || obj.status === Image.Error;
            if (done)
                obj.sourceSize = Qt.size(obj.sourceSize.width, obj.sourceSize.height);
            if (obj === win.currentSlot && done)
                win.slotReady();
        });
        // Both conditions key off the same two pointers
        // (win.currentSlot / win.previousSlot), so a slot's visible
        // and layer.enabled state updates itself the instant its role
        // changes — current -> previous -> destroyed — with nothing
        // elsewhere needing to toggle it imperatively.
        win.bindRole(obj);
        return obj;
    }

    function bindRole(obj) {
        obj.visible = Qt.binding(() => obj === win.currentSlot && win.previousSlot === null);
        obj.layer.enabled = Qt.binding(() => obj === win.previousSlot
            || (obj === win.currentSlot && win.previousSlot !== null));
    }

    // ===== decode size changes =====
    property Item freshSlot: null

    function dropFresh() {
        freshTimer.stop();
        if (win.freshSlot) {
            win.freshSlot.destroy();
            win.freshSlot = null;
        }
    }
   function releaseWallpaperResources() {
        // Stop all pending wallpaper work.
        fullscreenRefresh.stop();
        resizeTimer.stop();
        freshTimer.stop();
        readyTimeout.stop();
        warmup.stop();
        blendAnim.stop();

        // Destroy any temporary image being decoded.
        dropFresh();

        // Destroy both wallpaper textures.
        if (win.previousSlot) {
            win.previousSlot.destroy();
            win.previousSlot = null;
        }

        if (win.currentSlot) {
            win.currentSlot.destroy();
            win.currentSlot = null;
        }

        win.progress = 1.0;
        win.shownImage = "";
    }

    function restoreWallpaperResources() {
        if (!win.wallpaperEnabled)
            return;

        const image = WallpaperService.imageFor(
            WallpaperService.pathFor(win.screenName)
        );

        if (image === "")
            return;

        win.shownImage = image;
        win.currentSlot = win.createSlot(image);
    }
    function redecode() {
        const cur = win.currentSlot;
        if (!cur || win.shownImage === "" || cur.status === Image.Error)
            return;
        // Busy (a blend is running, or the picture or the copy is still
        // decoding): look again shortly.
        if (win.previousSlot || cur.status !== Image.Ready || win.freshSlot) {
            resizeTimer.restart();
            return;
        }
        const want = win.sourceSize;
        if (want.width <= 0 || want.height <= 0)
            return;
        // Never allocate a second giant texture just because the requested
        // decode size became slightly smaller. The existing texture already
        // contains at least as many pixels, so keeping it is visually lossless
        // and avoids a large temporary RAM/GPU allocation during monitor/zoom
        // changes. A larger requested size still gets the existing seamless
        // fresh-slot path below.
        if (cur.sourceSize.width >= want.width && cur.sourceSize.height >= want.height)
            return;
        const obj = textureSlotComponent.createObject(pic, {
            sourceSize: want,
            source: "file://" + win.shownImage,
            visible: false
        });
        win.freshSlot = obj;
        obj.statusChanged.connect(() => {
            if (obj !== win.freshSlot)
                return;
            if (obj.status === Image.Error) {
                win.dropFresh();
            } else if (obj.status === Image.Ready) {
                // Drawn over the old one now, so its first texture upload
                // happens while the old one still covers the screen.
                obj.visible = true;
                freshTimer.restart();
            }
        });
    }

    onSourceSizeChanged: resizeTimer.restart()

    Timer {
        id: resizeTimer
        interval: 250
        onTriggered: win.redecode()
    }

    Timer {
        id: freshTimer
        interval: 100
        onTriggered: {
            const f = win.freshSlot;
            const old = win.currentSlot;
            if (!f)
                return;
            if (!old || win.previousSlot) {
                win.dropFresh();
                return;
            }
            win.freshSlot = null;
            win.currentSlot = f;
            win.bindRole(f);
            old.destroy();
            // The size may have changed again while the copy was decoding.
            resizeTimer.restart();
        }
    }

    function swapTo(image) {
        if (win.currentSlot && win.currentSlot.status !== Image.Ready) {
            // Switched again before the last wallpaper finished
            // decoding, so it was never on screen. Drop it; what is
            // actually showing is the outgoing slot (if there is one),
            // and that stays the thing we blend out of. Fading out of
            // the unfinished slot would be fading out of black.
            win.currentSlot.destroy();
            win.currentSlot = null;
            win.currentSlot = win.createSlot(image);
            return;
        }
        if (win.previousSlot) {
            // A switch landed mid-transition (fast picker navigation,
            // a short slideshow tick) — there's already an outgoing
            // slot nobody finished blending out. destroy() it now
            // instead of leaking it forward.
            win.previousSlot.destroy();
        }
        win.previousSlot = win.currentSlot;
        win.currentSlot = win.createSlot(image);
    }

    function finishLocalTransition() {
        if (win.previousSlot) {
            win.previousSlot.destroy();
            win.previousSlot = null;
        }
        win.progress = 1.0;
    }

    // This monitor's wallpaper changed.
    function show(image) {
    if (!win.wallpaperEnabled)
            return;
        if (image === "" || image === win.shownImage)
            return;
        win.shownImage = image;
        win.activeStyle = WallpaperService.styleForSwitch();
        win.dropFresh();
        // A new switch cancels a blend that was waiting or running.
        // (stop() doesn't fire onFinished, so this can't end the
        // transition by accident.)
        blendAnim.stop();
        warmup.stop();
        win.progress = 0.0;
        win.swapTo(image);
        // Nothing more happens here: the blend starts from slotReady()
        // once the incoming wallpaper has decoded. Until then the
        // ShaderEffect sits at progress 0, which shows the outgoing
        // wallpaper as-is (and with no outgoing slot the incoming one
        // just appears when it is ready).
        readyTimeout.restart();
    }

    onWantedImageChanged: win.show(win.wantedImage)

    function slotReady() {
        readyTimeout.stop();
        // One short beat so the first texture upload / mipmap pass
        // of the new wallpaper lands while progress is still 0
        // instead of stuttering the first frames of the wipe.
        warmup.restart();
    }

    readonly property string screenName: win.modelData ? win.modelData.name : ""

      Component.onCompleted: {
        if (win.wallpaperEnabled && win.wantedImage !== "") {
            win.shownImage = win.wantedImage;
            win.currentSlot = win.createSlot(win.wantedImage);
        }
    }

    // A file that never reports (corrupt, unreadable) mustn't leave the
    // switch hanging forever.
    Timer {
        id: readyTimeout
        interval: 5000
        onTriggered: win.slotReady()
    }

    Timer {
        id: warmup
        interval: 50
        onTriggered: {
            // No outgoing picture (the first wallpaper): nothing to blend from.
            if (win.previousSlot)
                blendAnim.restart();
        }
    }

    NumberAnimation {
        id: blendAnim
        target: win
        property: "progress"
        from: 0.0
        to: 1.0
        // sekaiIris gets its own forced duration/easing rather than
        // WallpaperService.transitionDuration/transitionEasing — its
        // shader (shaders/sekai_iris.frag) does its own easing along a
        // drop-through path and staggers the discs by fixed fractions
        // of progress, which only stays equal in real time if progress
        // advances at a constant rate. Forcing both here means
        // switching to sekaiIris always gets that right, and the other
        // styles keep using transitionDuration/transitionEasing for
        // their own feel.
        // sekaiRing does its own easing inside the shader too (fast start,
        // gentle slow-down), so it also wants Linear progress; its length
        // comes from WallpaperService.ringDuration.
        // "star" (sekai_star) and "diagonalBlocks" (sekai_blocks) share the
        // ring's easing and duration, so all three run at the same speed.
        duration: win.activeStyle === "sekaiIris" ? 2000
            : (win.activeStyle === "sekaiRing"
               || win.activeStyle === "star"
               || win.activeStyle === "diagonalBlocks") ? WallpaperService.ringDuration
            : WallpaperService.transitionDuration
        easing.type: (win.activeStyle === "sekaiIris"
            || win.activeStyle === "sekaiRing"
            || win.activeStyle === "star"
            || win.activeStyle === "diagonalBlocks") ? Easing.Linear : WallpaperService.transitionEasing
        onFinished: win.finishLocalTransition()
    }

    // This monitor's UI scale (scale.json / services/ShellScale.qml), for the
    // sizes Edit Desktop draws in design pixels.
    readonly property real uiScale: ShellScale.forScreen(win.screen)

    // ===== Edit Desktop =====
    Loader {
        anchors.fill: parent
        active: EditMode.editing(win.screenName)

        sourceComponent: EditBackdrop {
            screenObj: win.screen
            uiScale: win.uiScale
        }
    }

    // The picture itself. Out of edit mode it is the whole window, exactly
    // as before; in it, it is scaled about the top-left corner and moved to
    // where the card sits (the same numbers the widget windows use, see
    // EditStage.qml), and the ring in EditFrame hides its square corners.
    Item {
        id: stage
        visible: win.wallpaperEnabled
        width: parent.width
        height: parent.height
        x: EditMode.xFor(win.screenName, win.width, win.height, win.uiScale)
        y: EditMode.yFor(win.screenName, win.width, win.height, win.uiScale)
        scale: EditMode.scaleFor(win.screenName, win.width, win.height, win.uiScale)
        transformOrigin: Item.TopLeft
        // Parallax draws the picture past the window's edge: cut it off there
        // (in Edit Desktop that is the card's edge).
        clip: win.parallaxOn

        // The pictures and the transition, as one thing that parallax can slide.
        // (Without parallax it is exactly the stage.)
        Item {
            id: pic
            width: stage.width * win.parallaxZoom
            height: stage.height * win.parallaxZoom
            x: -(width - stage.width) * win.parallaxFraction
            y: -(height - stage.height) / 2

            Behavior on x {
                enabled: win.parallaxOn
                NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
            }

            // The last frame of the video, saved by mpvpaper when Edit Desktop opened. It shrinks
            // with the card. It stays up a moment after editing ends, until mpvpaper is back.
            Image {
                id: frozen
                anchors.fill: parent
                sourceSize: win.sourceSize
                z: 4
                visible: source !== "" && !win.transitioning
                cache: false
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
            }

            Timer {
                id: hideFrozen
                interval: 900
                onTriggered: frozen.source = ""
            }

            Connections {
                target: win

                function onVideoEditingChanged() {
                    if (win.videoEditing)
                        hideFrozen.stop()
                    else
                        hideFrozen.restart()
                }

                function onWantedPathChanged() {
                    hideFrozen.stop()
                    frozen.source = ""
                }
            }

            // The video, over the first-frame picture once the transition is
            // done. Not while a transition runs (it blends pictures). It keeps
            // playing through Edit Desktop (the card just shows it smaller):
            // unloading it for the mode stopped the video and swapped it for
            // its first frame at the moment the mode started. Built only for a
            // video wallpaper.
            Loader {
                id: videoLayer
                anchors.fill: parent
                z: 5
                 active: win.wallpaperEnabled
                    && WallpaperService.videoFor(win.screenName)
                    && !win.transitioning
                    && win.currentSlot !== null
                    && win.currentSlot.status === Image.Ready
                source: active ? Qt.resolvedUrl(win.useMpvpaper ? "MpvpaperWallpaper.qml" : "VideoWallpaper.qml") : ""
                onLoaded: {
                    item.hidden = win.videoEditing
                    item.screenName = win.screenName
                    item.restartOnPause = win.restartOnPause
                    item.path = win.wantedPath
                }
                onStatusChanged: {
                    if (status === Loader.Error)
                        console.warn("WallpaperLayer: video wallpapers need qt6-multimedia (and a backend such as qt6-multimedia-ffmpeg); showing the first frame instead")
                }

                Binding {
                    target: videoLayer.item
                    property: "path"
                    value: win.wantedPath
                    when: videoLayer.item !== null
                }

                Connections {
                    target: videoLayer.item
                    ignoreUnknownSignals: true

                    function onFailed() {
                        win.mpvpaperFailed = true
                    }

                    function onFrameReady(path) {
                        hideFrozen.stop()
                        frozen.source = "file://" + path
                    }
                }

                Binding {
                    target: videoLayer.item
                    property: "restartOnPause"
                    value: win.restartOnPause
                    when: videoLayer.item !== null
                }

                Binding {
                    target: videoLayer.item
                    property: "hidden"
                    value: win.videoEditing
                    when: videoLayer.item !== null
                }

                Binding {
                    target: videoLayer.item
                    property: "paused"
                    value: win.useMpvpaper ? win.videoPausedBase : win.videoPaused
                    when: videoLayer.item !== null
                }
            }

        ShaderEffect {
            id: blend
            anchors.fill: parent
            visible: win.previousSlot !== null

            // Bound to whichever shader win.activeStyle
            // picks. Property -> uniform matching is by NAME (see
            // shaders/README.md) — a property here with no matching
            // uniform in the currently-bound shader is just harmlessly
            // ignored, which is what lets this declare the full union of
            // what every style needs rather than swapping property sets
            // per style.
            //
            // Maps the style name to the compiled shader pair's shared
            // filename stem — "fade" is the Phase 2 placeholder, anything
            // else names a real .vert/.frag pair in shaders/ (see
            // shaders/README.md, "Adding a fourth style").
            readonly property string shaderBase: {
                switch (win.activeStyle) {
                case "sekaiIris": return "sekai_iris";
                case "sekaiRing": return "sekai_ring";
                case "star": return "sekai_star";
                case "diagonalBlocks": return "sekai_blocks";
                case "sekaiFlash": return "sekai_flash";
                default: return "fade";
                }
            }

            property var source1: win.previousSlot // outgoing
            property var source2: win.currentSlot  // incoming
            property real progress: win.progress
            property real aspect: height > 0 ? width / height : 1.0
            property color accentColor: mt.accentCyan
            // sekaiIris-only: fixed white/pink/green band colours, kept
            // separate from accentColor since the iris wipe stays the
            // same regardless of which group's accent is active elsewhere.
            //
            // The colours follow the theme (Theme.transitionColors, with the
            // Settings -> Desktop -> Wallpaper -> "Transition colours" switch).
            // With matugen they change when the new wallpaper's palette lands,
            // which can be halfway through a transition, so each one drifts to
            // its new value (the Behaviors below) instead of jumping.
            readonly property var tc: mt.transitionColors(ThemeService.palette)
            property color colorWhite: tc.white
            property color colorPink: tc.pink
            property color colorGreen: tc.green
            Behavior on colorWhite { ColorAnimation { duration: 450 } }
            Behavior on colorPink { ColorAnimation { duration: 450 } }
            Behavior on colorGreen { ColorAnimation { duration: 450 } }

            // sekaiRing-only. Its three colours are colorWhite and colorPink
            // (shared with sekaiIris above) plus colorCyan here. Every
            // ring-* value is tuned from WallpaperService (ring* properties),
            // never here. `transitionStyle` is the ring's variant number
            // (0 ring, 1 petal, 2 echo, 3 swirl), not WallpaperService's
            // style-name string of the same name.
            property color colorCyan: tc.cyan
            Behavior on colorCyan { ColorAnimation { duration: 450 } }
            property int transitionStyle: WallpaperService.ringVariant
            property real distortion: WallpaperService.ringDistortion
            property real speed: WallpaperService.ringSpeed
            property real ringWidth: WallpaperService.ringWidth

            // `colorIntensity` and `center` are shared by sekaiRing and star
            // (same uniform names in both shaders), so each takes its value
            // from whichever style is active.
            readonly property bool isStar: win.activeStyle === "star"
            property real colorIntensity: isStar ? WallpaperService.starColorIntensity
                                                 : WallpaperService.ringColorIntensity
            property vector2d center: isStar ? WallpaperService.starCenter
                                             : WallpaperService.ringCenter

            // star-only (shaders/sekai_star.*). Tuned from WallpaperService
            // (star* properties), never here. The style itself is picked by
            // win.activeStyle === "star", which is a name
            // for the shader pair, not a uniform: GLSL has no string type.
            property real thickness: WallpaperService.starThickness
            property real pointLength: WallpaperService.starPointLength
            property real curvature: WallpaperService.starCurvature
            property real elastic: WallpaperService.starElastic
            property real spin: WallpaperService.starSpin

            // diagonalBlocks-only (shaders/sekai_blocks.*). Its three colours
            // are colorWhite / colorPink / colorCyan above. Tuned from
            // WallpaperService (blocks* properties), never here. As with the
            // star, the style name "diagonalBlocks" only picks the shader
            // pair (see shaderBase); it is not a uniform.
            property vector2d direction: WallpaperService.blocksDirection
            property real bandThickness: WallpaperService.blocksBandThickness
            property real blockSize: WallpaperService.blocksBlockSize
            property real stagger: WallpaperService.blocksStagger

            fragmentShader: Directories.shader(blend.shaderBase + ".frag.qsb")
            vertexShader: Directories.shader(blend.shaderBase + ".vert.qsb")
        }
        } // pic
    }

    // Over the picture: the card's frame.
    Loader {
        anchors.fill: parent
        active: EditMode.editing(win.screenName)

        sourceComponent: EditFrame {
            screenObj: win.screen
            uiScale: win.uiScale
        }
    }

    // Edit Desktop: a click on the bare card (nothing but wallpaper under it)
    // stops editing the selected widget. Widgets, the bar and the dock are
    // all above this layer, so only a click that really lands on the
    // wallpaper gets here.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        enabled: EditMode.active
        onClicked: EditMode.select("")
    }

    // Right-click on the bare desktop: the Edit Desktop menu (DesktopMenu.qml).
    // Windows, the bar and the widgets are all above this layer, so only a
    // click that really lands on the wallpaper gets here.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        enabled: !EditMode.active
        onClicked: mouse => EditMode.openMenu(win.screenName, mouse.x, mouse.y)
    }
}
