pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.common

// The system side of the wallpaper switcher (same role as
// TraySource.qml for the tray, MediaSource.qml for MPRIS): pure
// state, no PanelWindow, no Image, no ShaderEffect. WallpaperLayer.qml
// is the only file that turns this into pixels. It keeps WHICH wallpaper
// each monitor shows (pathFor); every WallpaperLayer runs its own
// transition when its monitor's wallpaper changes.
//
// Auto-registered as a singleton under `qs.services` — same as this
// project's other Source files and Theme.qml, no qmldir needed;
// Quickshell treats the config's root directory as an implicit QML
// module and wires up `pragma Singleton` files itself. Anything that
// wants to change the wallpaper (the Wallpapers screen, a keybind,
// a slideshow timer) does:
//
//   import qs.services
//   ...
//   WallpaperService.setWallpaper("/path/to/image.png")            every monitor
//   WallpaperService.setWallpaper("/path/to/image.png", "DP-1")    one monitor
//
// and never touches WallpaperLayer.qml directly.
//
// The lockscreen has its own half of this (Settings -> Desktop -> Wallpaper ->
// Separate Lockscreen Wallpaper), kept apart from the desktop's on purpose:
//
//   WallpaperService.setLockWallpaper("/path/to/image.png")           every monitor
//   WallpaperService.setLockWallpaper("/path/to/image.png", "DP-1")   one monitor
//
// With the option off the lockscreen simply shows the desktop's wallpaper
// (lockPathFor() answers with pathFor()). With it on it shows its own picks,
// and nothing that changes the desktop wallpaper (a pick, the random timer,
// a per-monitor change) reaches them, and the other way round.
Singleton {
    id: root

    // ===== what is on each monitor =====
    readonly property bool perMonitor: SettingsService.flag("wallpaper.perMonitor")

    // The default wallpaper: what a monitor shows when it has none of its
    // own. That is every monitor while perMonitor is off, and a monitor
    // that was just plugged in while it is on. It is also what is saved as
    // "the" wallpaper, so it is what a restart brings back with perMonitor off.
    property string defaultPath: ""

    // monitor name (e.g. "DP-1") -> wallpaper path, only for monitors that
    // were given one. Replaced whole on every change, so bindings update.
    // Only meaningful while perMonitor is on: when the mode is off they are
    // forgotten (forgetScreenPicks), so turning it on again starts from the
    // main monitor's CURRENT wallpaper on every monitor instead of bringing
    // back picks from an earlier session of the mode.
    property var screenPaths: ({})

    function forgetScreenPicks() {
        if (Object.keys(root.screenPaths).length === 0)
            return;
        root.screenPaths = ({});
        screensSaver.saveAll();
    }

    // With the mode on, every monitor holds a pick of its own, so a change on
    // one monitor can never reach another (changing the main monitor's
    // wallpaper must not change the others). A monitor that has none yet (the
    // mode was just turned on, a monitor was just plugged in) is given one
    // here: the main monitor's CURRENT wallpaper (the default if the main
    // monitor has none), which is also what pathFor() shows for it until then,
    // so pinning it changes nothing on screen.
    function pinMissing() {
        if (!root.ready || !root.perMonitor)
            return;
        const base = root.screenPaths[root.themeScreen] || root.defaultPath;
        if (!base)
            return;
        let next = null;
        for (const s of Quickshell.screens) {
            if (!root.screenPaths[s.name]) {
                if (!next)
                    next = Object.assign({}, root.screenPaths);
                next[s.name] = base;
            }
        }
        if (next) {
            root.screenPaths = next;
            screensSaver.saveAll();
        }
    }

    // A monitor was plugged in or removed.
    readonly property var screenNames: Quickshell.screens.map(s => s.name)
    onScreenNamesChanged: root.pinMissing()

    // The wallpaper a monitor shows right now. Call it from a binding and
    // the binding follows every change (the picker and every WallpaperLayer
    // do exactly that).
    //
    // Until `ready` (below) it answers "" for every monitor: at start-up the
    // default, the per-monitor picks and the "One wallpaper per monitor"
    // switch all arrive from disk at different moments, and answering from
    // whichever half had arrived made every monitor show the default for a
    // moment (the main monitor's picture on the others) and then blend to
    // its own. An empty answer means "nothing to show yet", and a
    // WallpaperLayer simply waits for it.
    //
    // With "One wallpaper per monitor" on, a monitor shows its own pick. One
    // that has none yet (just plugged in, or the mode was just turned on)
    // starts from the main monitor (themeScreen): its current wallpaper is the
    // source of truth, not the old default, which goes stale in this mode.
    // pinMissing() then turns that into a pick of its own straight away, so
    // the monitor does NOT keep following the main one afterwards.
    function pathFor(name) {
        if (!root.ready)
            return "";
        if (!root.perMonitor)
            return root.defaultPath;
        if (name && root.screenPaths[name])
            return root.screenPaths[name];
        const main = root.screenPaths[root.themeScreen];
        return main ? main : root.defaultPath;
    }

    // True once everything pathFor() depends on has been read back from disk:
    // the saved default and per-monitor picks (`restoring`) and the settings
    // file that says whether the per-monitor mode is on. Both flip while the
    // shell is starting; this one only turns true when the LAST of them has,
    // so the first answer pathFor() gives is already the final one and no
    // monitor ever starts a blend at start-up.
    readonly property bool ready: !root.restoring && SettingsService.loaded

    // The monitor whose wallpaper drives the things that need ONE picture:
    // the theme colours (matugen) and `currentPath` / `imagePath` below.
    // The first monitor Quickshell lists, so it does not jump around.
    readonly property string themeScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""

    // That monitor's wallpaper. With perMonitor off it is simply "the
    // wallpaper". Read-only: change it with setWallpaper().
    readonly property string currentPath: root.pathFor(root.themeScreen)

    // Turning "One wallpaper per monitor" off must not change what you are
    // looking at: the wallpaper on the main monitor (themeScreen) becomes THE
    // wallpaper, i.e. the default, and is saved as such, so it is also what a
    // shell reload brings back while the mode stays off. The other monitors'
    // own picks are forgotten (see forgetScreenPicks).
    // A monitor without a pick of its own already shows the default, so there
    // is nothing to adopt then.
    function adoptMain() {
        const p = root.screenPaths[root.themeScreen];
        if (!p || p === root.defaultPath)
            return;
        root.defaultPath = p;
        saver.save(p);
    }

    // The switch in Settings -> Desktop -> Wallpaper. Off adopts the main
    // monitor's wallpaper BEFORE the flag flips, so no monitor ever shows the
    // old default for a moment (that would start a blend to it and another one
    // straight back).
    function setPerMonitor(on) {
        if (!on) {
            root.adoptMain();
            root.adoptMainLock();
        }
        SettingsService.set("wallpaper.perMonitor", !!on);
    }

    // Anything else that turns it off (`ipc call options set wallpaper.perMonitor
    // false`, an older saved layout) gets the same result, just after the flip.
    onPerMonitorChanged: {
        if (root.restoring)
            return;
        if (root.perMonitor) {
            // Turned on: every monitor starts on the main monitor's current
            // wallpaper (each as a pick of its own, so they diverge from here).
            root.pinMissing();
        } else {
            root.adoptMain();
            root.adoptMainLock();
            // The other monitors' own picks are not kept for later: they
            // would be stale by the time the mode is turned on again.
            root.forgetScreenPicks();
            root.forgetLockScreenPicks();
        }
    }

    // Picks saved by an older version (which kept them while the mode was off)
    // or left over from a session of the mode: with the mode off they are
    // stale, so drop them once everything has been read back.
    onReadyChanged: {
        if (!root.ready)
            return;
        if (root.perMonitor)
            root.pinMissing();
        else {
            root.forgetScreenPicks();
            root.forgetLockScreenPicks();
        }
        if (root.separateLock)
            root.seedLock();
    }

    // True until the startup "load" below has actually resolved (found
    // a saved path, or confirmed there isn't one). shell.qml's
    // first-run fallback checks this before deciding "nothing saved,
    // use the alphabetically-first wallpaper as a convenience default"
    // — without it, that fallback would win the race against this
    // file's own async restore below on every single launch, which
    // was exactly the bug (wallpaper always reverting to the first
    // file in the folder instead of the one you'd actually picked).
    property bool restoring: true

    // ===== the lockscreen's own wallpaper =====
    readonly property bool separateLock: SettingsService.flag("wallpaper.separateLock")

    // The lockscreen's wallpaper for every monitor that has none of its own.
    // "" until the option has been turned on once. Unlike the desktop's, the
    // picks are KEPT while the option is off: turning it off only makes the
    // lockscreen follow the desktop, it does not throw the choice away.
    property string lockDefaultPath: ""

    // monitor name -> the lockscreen wallpaper of that monitor, only for
    // monitors that were given one. Only meaningful with "One wallpaper per
    // monitor" on (turning that off forgets them, like screenPaths). A monitor
    // with no pick shows lockDefaultPath, so a pick on one monitor can never
    // reach another and no pinning is needed.
    property var lockScreenPaths: ({})

    function forgetLockScreenPicks() {
        if (Object.keys(root.lockScreenPaths).length === 0)
            return;
        root.lockScreenPaths = ({});
        lockScreensSaver.saveAll();
    }

    // The wallpaper the lockscreen shows on a monitor right now: what
    // LockSurface.qml (and LockRing.qml's copy of it) binds to.
    //
    // Option off: the desktop's wallpaper, so it follows every change.
    // Option on:  the monitor's own lock pick (per-monitor mode only), else
    //             the lockscreen's default, else (nothing picked yet, which
    //             seedLock() fixes a moment after the option is turned on)
    //             the desktop's, so there is never a gap.
    // Like pathFor() it answers "" until `ready`.
    function lockPathFor(name) {
        if (!root.ready)
            return "";
        if (!root.separateLock)
            return root.pathFor(name);
        if (root.perMonitor && name && root.lockScreenPaths[name])
            return root.lockScreenPaths[name];
        return root.lockDefaultPath !== "" ? root.lockDefaultPath : root.pathFor(name);
    }

    // That, for the theme monitor (the picker's "applied" ring on the Lockscreen tab).
    readonly property string lockCurrentPath: root.lockPathFor(root.themeScreen)

    // Turning the option on must not change what the lockscreen shows. The
    // first time (nothing picked yet) the lockscreen takes the desktop's
    // current wallpaper as its own, monitor by monitor in per-monitor mode, so
    // from then on it stays put when the desktop changes. Later times the
    // choice made earlier simply comes back. Does nothing without a desktop
    // wallpaper to copy yet (ensureDefault() calls it again once there is one).
    function seedLock() {
        if (!root.ready || root.lockDefaultPath !== "")
            return;
        const base = root.pathFor(root.themeScreen);
        if (!base)
            return;
        root.lockDefaultPath = base;
        lockSaver.save(base);
        if (root.perMonitor) {
            const picks = {};
            for (const s of Quickshell.screens)
                picks[s.name] = root.pathFor(s.name);
            root.lockScreenPaths = picks;
            lockScreensSaver.saveAll();
        }
    }

    // The same as adoptMain() for the lockscreen: turning "One wallpaper per
    // monitor" off keeps what the main monitor's lockscreen shows.
    function adoptMainLock() {
        const p = root.lockScreenPaths[root.themeScreen];
        if (!p || p === root.lockDefaultPath)
            return;
        root.lockDefaultPath = p;
        lockSaver.save(p);
    }

    // The switch in Settings -> Desktop -> Wallpaper. Seeds BEFORE the flag
    // flips, so the lockscreen never shows anything but what it showed.
    function setSeparateLock(on) {
        if (on)
            root.seedLock();
        SettingsService.set("wallpaper.separateLock", !!on);
    }

    // Anything else that turns it on (`ipc call options set wallpaper.separateLock true`).
    onSeparateLockChanged: {
        if (!root.restoring && root.separateLock)
            root.seedLock();
    }

    // ===== config =====
    property int transitionDuration: 900
    property int transitionEasing: Easing.InOutQuad

    // Which compiled shader WallpaperLayer.qml binds as the blend's
    // fragmentShader/vertexShader — a name, not a path, so this file
    // stays free of file-layout knowledge.
    // "sekaiIris" drops an onion of four nested green/pink/white
    // discs through the screen (shaders/sekai_iris.*), on its own forced
    // 2s/Linear timing — see the comment block at the top of
    // sekai_iris.frag for why.
    // "sekaiRing" is an expanding white/pink/cyan emblem ring with a
    // gently wobbling edge (shaders/sekai_ring.*, tuned by the ring*
    // properties below), on its own forced Linear timing.
    // "sekaiFlash" fades the outgoing wallpaper to accentColor then
    // fades the incoming one back up from it (shaders/sekai_flash.*);
    // "fade" is the Phase 2 placeholder straight crossfade — the only
    // one that works without compiling a .qsb first, so set this back
    // to "fade" if a shader fails to load (see shaders/README.md).
    // "star" is a four-point sparkle that covers the screen in colour, then
    // opens the new picture (shaders/sekai_star.*, tuned by the star*
    // properties below); same duration as sekaiRing.
    // "diagonalBlocks" is a staircase: the screen is cut into a few horizontal
    // rows (steps) and a pink / cyan / white band crosses it sideways, each row
    // set back a little from the one before (shaders/sekai_blocks.*, tuned by
    // the blocks* properties below); also the ring's timing.
    // "random" (a setting, not a shader) picks one of the styles above each time;
    // see randomStyles below.
    // (Settings -> Desktop -> Wallpaper.)
    // The raw choice in Settings. Any style name above, or "random".
    // ("sekaiSweep" was removed; a setting saved with it plays the ring.)
    readonly property string transitionSetting: {
        const s = SettingsService.get("wallpaper.transition");
        return s === "sekaiSweep" ? "sekaiRing" : s;
    }

    // "random" plays one of these, a different one from last time, on every
    // wallpaper change (WallpaperLayer.qml asks styleForSwitch() as each change
    // starts) and on every lock and unlock (LockState.qml calls rollLockStyle()).
    // Plain "fade" is left out on purpose: it is the no-shader fallback, not a
    // look of its own.
    readonly property var randomStyles: ["sekaiRing", "star", "sekaiIris", "sekaiFlash", "diagonalBlocks"]
    property string switchStyleRolled: "sekaiRing"
    property double switchRolledAt: 0
    property string lockStyleRolled: "sekaiRing"

    // The style the LOCK plays (LockState.qml / LockRing.qml read this): the
    // chosen style, or with "random" the one rollLockStyle() last picked.
    // Wallpaper changes do not read this: each WallpaperLayer.qml keeps the
    // style it was handed for its own change (see styleForSwitch).
    property string transitionStyle: root.transitionSetting === "random"
        ? root.lockStyleRolled : root.transitionSetting

    // A random style that is not `avoid` (the one played last).
    function pickRandomStyle(avoid) {
        const list = root.randomStyles.filter(s => s !== avoid);
        return list[Math.floor(Math.random() * list.length)];
    }

    // The style for a wallpaper change that is starting now. Not "random":
    // that style itself. "random": a fresh pick. Layers on several monitors
    // that change together (same wallpaper on every monitor) ask within a
    // moment of each other and get the same pick, so they play one transition.
    function styleForSwitch() {
        if (root.transitionSetting !== "random")
            return root.transitionSetting;
        const now = Date.now();
        if (now - root.switchRolledAt > 400) {
            root.switchStyleRolled = root.pickRandomStyle(root.switchStyleRolled);
            root.switchRolledAt = now;
        }
        return root.switchStyleRolled;
    }

    // Picks the style the next lock (or unlock) plays. Does nothing unless
    // the setting is "random".
    function rollLockStyle() {
        if (root.transitionSetting === "random")
            root.lockStyleRolled = root.pickRandomStyle(root.lockStyleRolled);
    }

    // ===== sekaiRing tuning =====
    property int ringDuration: SettingsService.get("wallpaper.duration")
    // 0 ring, 1 petal (6-lobed edge), 2 echo (trailing thin rings),
    // 3 swirl (spiral colour bands)
    property int ringVariant: 0
    // Edge wobble. 0 = perfectly round, 1 = default, ~2 is still elegant,
    // 3+ starts to look wobbly.
    property real ringDistortion: 1.0
    // 0 = plain wipe with no colour, 1 = normal, up to 1.5 = stronger glow.
    property real ringColorIntensity: 1.0
    // Speed of the edge wobble and the flowing bands (not the duration).
    property real ringSpeed: 1.0
    // Ring thickness in screen heights (0.44 = chunky bands; the leading edge keeps its speed, the bands grow inward).
    property real ringWidth: 0.44
    // Where the ring starts, in 0..1 screen coordinates (0,0 = top left).
    property vector2d ringCenter: Qt.vector2d(0.5, 0.5)

    // ===== star tuning =====
    // (The name is old.) How long after one band's edge starts the next one
    // follows, as a share of the whole transition. The star covers the whole
    // screen in colour and then opens the new picture in the middle; this is
    // the gap between the pink, white and cyan edges. 0.2 = covered for the
    // middle fifth. Kept between 0.17 and 0.3 in the shader (below 1/6 the
    // screen would never be fully covered). Bigger = a longer hold.
    property real starThickness: 0.2
    // How far the four points reach compared with the body: 2 = classic
    // astroid, 3 = long (default), 4+ = needles.
    property real starPointLength: 3.0
    // Extra hollowing of the concave sides. 1 = default, >1 = deeper
    // curves and thinner points, <1 = fuller, softer star.
    property real starCurvature: 1.0
    // 0 = no colour bands, 1 = normal, up to 2 = more saturated colours.
    property real starColorIntensity: 1.0
    // How much the points stretch and contract early on. 0 = none, 1 = default.
    property real starElastic: 1.0
    // How many turns the star spins, clockwise, over the whole transition.
    // The star looks the same every quarter turn, so 0.5 (half a turn) reads
    // as a clear spin; 0 = no spin, 1 = a full turn, negative = anticlockwise.
    // It turns fast while it grows and slows as the new picture opens.
    property real starSpin: 0.5
    // Where the star starts, in 0..1 screen coordinates (0,0 = top left).
    property vector2d starCenter: Qt.vector2d(0.5, 0.5)

    // ===== diagonalBlocks tuning (the staircase) =====
    // Only the signs count. (-1, -1) wipes to the left and starts at the
    // bottom, so the stairs climb up and to the left. (1, 1): to the right,
    // starting at the top.
    property vector2d blocksDirection: Qt.vector2d(-1, -1)
    // (The name is old.) How long after one band's edge starts the next one
    // follows, as a share of the whole transition. Blocks covers the whole
    // screen in colour and then uncovers the new picture; this is the gap
    // between the pink, cyan and white edges. 0.2 = covered for the middle fifth.
    // Kept between 0.17 and 0.3 in the shader (below 1/6 the screen would
    // never be fully covered). Bigger = a longer hold while it is covered.
    property real blocksBandThickness: 0.2
    // Height of one step, in screen heights. The rows are rounded so they fill
    // the screen: 0.34 = 3 steps, 0.25 = 4, 0.2 = 5.
    property real blocksBlockSize: 0.34
    // How far each step is set back from the one before, 1 = 0.28 of the
    // screen height; 0 = no stairs (one straight vertical wipe); 2 = long steps.
    property real blocksStagger: 1.0

    // ===== per-style timing =====
    function transitionMsFor(style) {
        if (style === "sekaiIris")
            return 2000;
        if (style === "sekaiRing" || style === "star" || style === "diagonalBlocks")
            return root.ringDuration;
        return root.transitionDuration;
    }

    function transitionLinearFor(style) {
        return style === "sekaiIris" || style === "sekaiRing"
            || style === "star" || style === "diagonalBlocks";
    }

    // The compiled lockscreen shader pair for a style: shaders/<stem>.frag.qsb
    // and .vert.qsb. Each is the wallpaper style's own maths again, but
    // blending ONE picture with transparency (see shaders/README.md).
    function lockShaderStemFor(style) {
        switch (style) {
        case "sekaiIris": return "sekai_iris_lock";
        case "sekaiRing": return "sekai_ring_lock";
        case "star": return "sekai_star_lock";
        case "diagonalBlocks": return "sekai_blocks_lock";
        case "sekaiFlash": return "sekai_flash_lock";
        default: return "fade_lock";
        }
    }

    // ===== desktop widgets over a live wallpaper =====
    // The desktop widgets (clock, to-do, user card, weather, visualizer) sit on the
    // Background layer, and surfaces on one layer stack in the order they were
    // mapped. mpvpaper (the video wallpaper) maps its own Background surface when
    // it starts, usually after the widgets, so it ended up OVER them. After it
    // has started, MpvpaperWallpaper.qml calls restackWidgets(): `restacking` is true for a
    // moment, every widget window moves to the Bottom layer and back, and moving
    // back puts it on top of the Background layer again, over the video.
    property bool restacking: false
    // The visualizer moves back down to Background a moment BEFORE the other widgets do, so it
    // is mapped first and ends up UNDER them (it only maps while music plays, so after a reload
    // it was otherwise the newest surface and sat over the clock, cards and so on).
    property bool restackingLow: false

    function restackWidgets() {
        root.restacking = true;
        root.restackingLow = true;
        restackLowOff.restart();
        restackOff.restart();
    }

    // mpvpaper maps its surface only once its first frame is ready, and at login (a big
    // video, hardware decoding starting up, a busy GPU) that can be many seconds after the
    // process started - long after the restacks MpvpaperWallpaper.qml schedules by timer. The
    // video then lands on top of the widgets and they look hidden until Edit Desktop stops it.
    // Hyprland says when a layer surface maps (`openlayer>>namespace`; mpvpaper's namespace is
    // "mpvpaper"), so restack at that moment instead of guessing a delay.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "openlayer" && String(event.data).toLowerCase().indexOf("mpvpaper") !== -1)
                mpvMappedRestack.restart()
        }
    }

    Timer {
        id: mpvMappedRestack
        // Lets Hyprland finish placing the new surface first; a second monitor's mpvpaper
        // mapping within this time just restarts it (one restack covers both).
        interval: 120
        onTriggered: root.restackWidgets()
    }

    Timer {
        id: restackLowOff
        interval: 70
        onTriggered: root.restackingLow = false
    }

    Timer {
        id: restackOff
        interval: 150
        onTriggered: root.restacking = false
    }

    // ===== signals =====
    signal transitionStarted(string from, string to)

    property string themeSeen: ""

    onCurrentPathChanged: {
        const from = root.themeSeen;
        root.themeSeen = root.currentPath;
        if (root.currentPath !== "")
            root.transitionStarted(from, root.currentPath);
    }

    // ===== video wallpapers =====
    function isVideo(path) {
        return /\.(mp4|webm|mkv|mov|avi)$/i.test(path || "");
    }

    // video path -> its first frame (made by wallpaper-thumbs.sh `still`)
    property var stills: ({})

    function imageFor(path) {
        if (!path)
            return "";
        return root.isVideo(path) ? (root.stills[path] || "") : path;
    }

    // The picture of `currentPath` (the theme monitor's wallpaper).
    readonly property string imagePath: root.imageFor(root.currentPath)

    // The picture of one monitor's wallpaper (the lock screen uses this).
    function imagePathFor(name) {
        return root.imageFor(root.pathFor(name));
    }

    // The picture of one monitor's LOCKSCREEN wallpaper (a video is its first
    // frame). LockSurface.qml uses this, and LockRing.qml through it.
    function lockImagePathFor(name) {
        return root.imageFor(root.lockPathFor(name));
    }

    // Should this monitor play a video right now? (False for a picture, or
    // with "Play video wallpapers" off.)
    function videoFor(name) {
        const p = root.pathFor(name);
        return root.isVideo(p) && SettingsService.flag("wallpaper.video") && root.imageFor(p) !== "";
    }

    // First frames are made one at a time. A job is {path, target, apply, lock}:
    // `apply` = change the wallpaper once the frame exists (a pick); not
    // apply = it is a saved wallpaper being restored, which only needs its frame.
    // `lock` = it is for the lockscreen, which only ever shows the frame (a
    // lockscreen does not play video).
    property var stillJobs: []
    property var stillRunning: null

    function queueStill(path, target, apply, lock) {
        lock = !!lock;
        // Only the latest pick for a monitor matters (fast clicking), for the
        // desktop and for the lockscreen separately.
        const jobs = root.stillJobs.filter(j => !(apply && j.apply && j.target === target && j.lock === lock));
        jobs.push({ path: path, target: target, apply: apply, lock: lock });
        root.stillJobs = jobs;
        root.runStillJobs();
    }

    function runStillJobs() {
        while (root.stillRunning === null && root.stillJobs.length > 0) {
            const job = root.stillJobs[0];
            root.stillJobs = root.stillJobs.slice(1);
            if (root.stills[job.path]) {
                root.finishStill(job);
                continue;
            }
            root.stillRunning = job;
            stillProc.exec(["sh", root.thumbScript, "still", job.path]);
        }
    }

    function finishStill(job) {
        if (job.apply && job.lock)
            root.applyLockWallpaper(job.path, job.target);
        else if (job.apply)
            root.applyWallpaper(job.path, job.target);
        else if (!job.lock && root.currentPath === job.path)
            // A restored video's frame turned up after the theme looked.
            root.transitionStarted("", job.path);
    }

    Process {
        id: stillProc
        stdout: StdioCollector {
            onStreamFinished: {
                const job = root.stillRunning;
                root.stillRunning = null;
                if (job) {
                    const p = text.trim();
                    if (p.length > 0) {
                        const next = Object.assign({}, root.stills);
                        next[job.path] = p;
                        root.stills = next;
                        root.finishStill(job);
                    } else {
                        console.warn("WallpaperService: couldn't get a first frame for " + job.path
                            + " (is ffmpeg installed?) — not changing the wallpaper");
                    }
                }
                root.runStillJobs();
            }
        }
    }

    // The one entry point everything else is meant to call.
    //
    //   setWallpaper(path)          every monitor
    //   setWallpaper(path, "DP-1")  that monitor only
    //
    // The second form needs "One wallpaper per monitor" to be on; with it
    // off there is only one wallpaper, so the call changes it for every monitor.
    function setWallpaper(path, screenName) {
        if (!path || path.length === 0)
            return;
        const target = (root.perMonitor && screenName) ? screenName : "";
        // A video needs its first frame before anything can blend to it.
        if (root.isVideo(path) && !root.stills[path]) {
            root.queueStill(path, target, true);
            return;
        }
        root.applyWallpaper(path, target);
    }

    // First-run fallback (shell.qml): give the default a value if it has none,
    // without touching any monitor's own pick.
    function ensureDefault(path) {
        if (root.defaultPath !== "" || !path)
            return;
        root.defaultPath = path;
        saver.save(path);
        root.pinMissing();
        // The option was already on but there was nothing to copy until now.
        if (root.separateLock)
            root.seedLock();
    }

    // The lockscreen's entry point, the counterpart of setWallpaper().
    //
    //   setLockWallpaper(path)          every monitor
    //   setLockWallpaper(path, "DP-1")  that monitor only
    //
    // The second form needs "One wallpaper per monitor" to be on, as with the
    // desktop. It never touches the desktop's wallpaper. The pick is stored
    // even while the option is off; it shows once the option is on.
    function setLockWallpaper(path, screenName) {
        if (!path || path.length === 0)
            return;
        const target = (root.perMonitor && screenName) ? screenName : "";
        // A video needs its first frame (that is all the lockscreen shows).
        if (root.isVideo(path) && !root.stills[path]) {
            root.queueStill(path, target, true, true);
            return;
        }
        root.applyLockWallpaper(path, target);
    }

    // target "" = every monitor, else one monitor's name.
    function applyLockWallpaper(path, target) {
        if (!root.ready)
            return;
        if (!root.perMonitor)
            target = "";
        // Make sure the other monitors are on something of their own first (a
        // no-op on screen), so a pick on one monitor can only reach that one.
        root.seedLock();
        if (target === "") {
            if (path !== root.lockDefaultPath) {
                root.lockDefaultPath = path;
                lockSaver.save(path);
            }
            // "every monitor" = no monitor keeps a pick of its own.
            root.forgetLockScreenPicks();
            HookService.emit("lockWallpaper", [path, ""]);
            return;
        }
        if (root.lockScreenPaths[target] === path)
            return;
        const next = Object.assign({}, root.lockScreenPaths);
        next[target] = path;
        root.lockScreenPaths = next;
        lockScreensSaver.saveAll();
        HookService.emit("lockWallpaper", [path, target]);
    }

    // target "" = every monitor, else one monitor's name.
    function applyWallpaper(path, target) {
        // With the mode off there is only one wallpaper (a queued video pick
        // can land after the mode was turned off).
        if (!root.perMonitor)
            target = "";
        if (target === "") {
            if (!root.perMonitor) {
                if (path === root.defaultPath)
                    return;
                root.defaultPath = path;
                saver.save(path);
                HookService.emit("wallpaper", [path, ""]);
                return;
            }
            // With the mode on, "every monitor" gives each monitor this
            // wallpaper as its own pick (in one step, so nothing blends twice).
            const unchanged = path === root.defaultPath
                && Quickshell.screens.every(s => root.screenPaths[s.name] === path);
            if (unchanged)
                return;
            root.defaultPath = path;
            saver.save(path);
            const all = {};
            for (const s of Quickshell.screens)
                all[s.name] = path;
            root.screenPaths = all;
            screensSaver.saveAll();
            HookService.emit("wallpaper", [path, ""]);
            return;
        }
        // One monitor. First make sure every other monitor holds a pick of its
        // own (a no-op on screen), so this change can only reach the monitor it
        // was made for, the main monitor included.
        root.pinMissing();
        // Compared with the monitor's OWN pick, not with what it shows.
        if (root.screenPaths[target] === path)
            return;
        const next = Object.assign({}, root.screenPaths);
        next[target] = path;
        root.screenPaths = next;
        screensSaver.saveAll();
        HookService.emit("wallpaper", [path, target]);
    }

    // ===== persistence =====
    readonly property string script: Directories.script("state/wallpaper-state.sh")

    // Runs once, at startup: the default first, then the per-monitor picks.
    // Whatever it finds (or doesn't) flips `restoring` to false when it's
    // done — see that property's own comment for why shell.qml's fallback
    // waits on it.
    Process {
        running: true
        command: ["sh", root.script, "load"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) {
                    root.defaultPath = path;
                    if (root.isVideo(path))
                        root.queueStill(path, "", false);
                }
                screensLoader.running = true;
            }
        }
    }

    Process {
        id: screensLoader
        command: ["sh", root.script, "loadscreens"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i <= 0)
                        continue;
                    const name = line.slice(0, i);
                    const path = line.slice(i + 1);
                    if (path.length > 0) {
                        next[name] = path;
                        if (root.isVideo(path))
                            root.queueStill(path, name, false);
                    }
                }
                root.screenPaths = next;
                // Then the lockscreen's own picks; restoring ends after them.
                lockLoader.running = true;
            }
        }
    }

    Process {
        id: lockLoader
        command: ["sh", root.script, "loadlock"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) {
                    root.lockDefaultPath = path;
                    if (root.isVideo(path))
                        root.queueStill(path, "", false, true);
                }
                lockScreensLoader.running = true;
            }
        }
    }

    Process {
        id: lockScreensLoader
        command: ["sh", root.script, "loadlockscreens"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i <= 0)
                        continue;
                    const name = line.slice(0, i);
                    const path = line.slice(i + 1);
                    if (path.length > 0) {
                        next[name] = path;
                        if (root.isVideo(path))
                            root.queueStill(path, name, false, true);
                    }
                }
                root.lockScreenPaths = next;
                root.restoring = false;
            }
        }
    }

    // Fire-and-forget save after every switch. Queues at most one
    // pending path behind an in-flight save rather than dropping it,
    // so clicking through several wallpapers quickly (e.g. the
    // picker's board) still ends with the *last* one actually
    // persisted, not whichever one happened to win a race.
    Process {
        id: saver

        property string pending: ""

        function save(path) {
            if (saver.running) {
                saver.pending = path;
                return;
            }
            saver.pending = "";
            saver.exec(["sh", root.script, "save", path]);
        }

        onExited: {
            if (saver.pending !== "") {
                const path = saver.pending;
                saver.pending = "";
                saver.exec(["sh", root.script, "save", path]);
            }
        }
    }

    // The same for the per-monitor picks. It always writes the whole map as
    // it is at that moment, so one pending flag is enough.
    Process {
        id: screensSaver

        property bool pending: false

        function saveAll() {
            if (screensSaver.running) {
                screensSaver.pending = true;
                return;
            }
            screensSaver.pending = false;
            const args = ["sh", root.script, "savescreens"];
            for (const name of Object.keys(root.screenPaths))
                args.push(name, root.screenPaths[name]);
            screensSaver.exec(args);
        }

        onExited: {
            if (screensSaver.pending)
                screensSaver.saveAll();
        }
    }

    // The lockscreen's picks are saved the same two ways, to their own files.
    Process {
        id: lockSaver

        property string pending: ""

        function save(path) {
            if (lockSaver.running) {
                lockSaver.pending = path;
                return;
            }
            lockSaver.pending = "";
            lockSaver.exec(["sh", root.script, "savelock", path]);
        }

        onExited: {
            if (lockSaver.pending !== "") {
                const path = lockSaver.pending;
                lockSaver.pending = "";
                lockSaver.exec(["sh", root.script, "savelock", path]);
            }
        }
    }

    Process {
        id: lockScreensSaver

        property bool pending: false

        function saveAll() {
            if (lockScreensSaver.running) {
                lockScreensSaver.pending = true;
                return;
            }
            lockScreensSaver.pending = false;
            const args = ["sh", root.script, "savelockscreens"];
            for (const name of Object.keys(root.lockScreenPaths))
                args.push(name, root.lockScreenPaths[name]);
            lockScreensSaver.exec(args);
        }

        onExited: {
            if (lockScreensSaver.pending)
                lockScreensSaver.saveAll();
        }
    }

    // ===== the folder, thumbnails, random =====
    // The folder the picker lists, the thumbnails are made for and "random" draws
    // from. Settings -> Desktop -> Wallpaper -> Wallpaper folder (or the folder
    // button in the picker's toolbar) sets `wallpaper.folder`; empty means the
    // default, ~/Pictures/Wallpapers. Only the LISTING moves with it: a wallpaper
    // that is already applied stays applied when you pick another folder.
    readonly property string defaultDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    function normalizeDir(p) {
        p = String(p || "").trim();
        const home = Quickshell.env("HOME");
        if (p === "~")
            p = home;
        else if (p.indexOf("~/") === 0)
            p = home + p.slice(1);
        if (p.length > 1)
            p = p.replace(/\/+$/, "");
        return p;
    }

    readonly property string customDirectory: root.normalizeDir(SettingsService.get("wallpaper.folder"))
    readonly property bool customFolder: root.customDirectory !== ""
    readonly property string directory: root.customFolder ? root.customDirectory : root.defaultDirectory

    // The same folder as a url for a FolderListModel (a name with a space, # or %
    // in it would not survive being used as a plain path there).
    readonly property string directoryUrl: "file://" + root.directory.split("/").map(encodeURIComponent).join("/")

    // The folder for people: ~ for the home folder.
    readonly property string directoryShort: {
        const home = Quickshell.env("HOME");
        const d = root.directory;
        if (home !== "" && d === home)
            return "~";
        return (home !== "" && d.indexOf(home + "/") === 0) ? "~" + d.slice(home.length) : d;
    }

    // Use `path` as the wallpaper folder. The default folder is stored as "" so
    // it keeps following the default. Does not touch any applied wallpaper.
    function setFolder(path) {
        const p = root.normalizeDir(path);
        if (p === "")
            return;
        SettingsService.set("wallpaper.folder", p === root.defaultDirectory ? "" : p);
    }

    function resetFolder() {
        SettingsService.set("wallpaper.folder", "");
    }

    // ----- the folder chooser -----
    // True while the chooser is open. The picker (and the Settings) step aside
    // for as long as it is: they close when it starts, so the dialog is not under
    // the phone and takes the keyboard, and open again when it is done
    // (`reopen`: "desktop" / "lock" = the Wallpapers on that side, "settings" =
    // the Settings, "" = stay closed).
    property bool folderPicking: false
    property string pickReopen: ""

    function pickFolder(reopen) {
        if (root.folderPicking)
            return;
        root.pickReopen = reopen || "";
        root.folderPicking = true;
        const chooser = SettingsService.get("files.chooser");
        const env = (chooser === "kdialog" || chooser === "zenity" || chooser === "yad")
            ? ["env", "SEKAIPOP_CHOOSER=" + chooser] : [];
        folderPicker.exec(env.concat(["sh", root.pickFolderScript, "pick", root.directory]));
    }

    readonly property string pickFolderScript: Directories.script("wallpapers/pick-folder.sh")

    Process {
        id: folderPicker
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path !== "")
                    root.setFolder(path);
                root.folderPicking = false;
                if (root.pickReopen !== "")
                    reopenTimer.restart();
            }
        }
    }

    // A beat after the dialog is gone, so a quick cancel does not land on the
    // phone's own closing animation.
    Timer {
        id: reopenTimer
        interval: 450
        onTriggered: {
            const side = root.pickReopen;
            root.pickReopen = "";
            if (side === "settings")
                Quickshell.execDetached(["qs", "-c", "sekaipop", "ipc", "call", "settings", "page", "desktop"]);
            else if (side === "lock")
                Quickshell.execDetached(["qs", "-c", "sekaipop", "ipc", "call", "wallpaperpicker", "showlock"]);
            else if (side === "desktop")
                Quickshell.execDetached(["qs", "-c", "sekaipop", "ipc", "call", "wallpaperpicker", "show"]);
        }
    }

    readonly property string thumbScript: Directories.script("thumbnails/wallpaper-thumbs.sh")

    FolderListModel {
        id: files
        folder: root.directoryUrl
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp",
                      "*.mp4", "*.webm", "*.mkv", "*.mov", "*.avi"]
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: scanDebounce.restart()
    }

    // path -> thumbnail file, for the ones that exist. Replaced whole, so
    // bindings on thumbUrl() update as thumbnails appear.
    property var thumbs: ({})

    // What a card in the picker should load: the small cached thumbnail when
    // there is one (and the cache is on), else the picture itself. A video with
    // no thumbnail yet has nothing to show.
    function thumbUrl(path) {
        if (!path)
            return "";
        const t = SettingsService.flag("wallpaper.thumbs") ? root.thumbs[path] : undefined;
        if (t)
            return "file://" + t;
        return root.isVideo(path) ? "" : "file://" + path;
    }

    // A scan asked for while another one is still running (a new folder was
    // chosen) is not dropped: it is run once that one is done.
    property bool rescanPending: false

    function scanThumbs() {
        if (!SettingsService.flag("wallpaper.thumbs"))
            return;
        if (scanner.running || maker.running) {
            root.rescanPending = true;
            return;
        }
        root.rescanPending = false;
        scanner.exec(["sh", root.thumbScript, "scan", root.directory]);
    }

    // A different folder: its thumbnails are made (the cache is keyed by file, so
    // the old folder's stay valid for when it comes back).
    onDirectoryChanged: scanDebounce.restart()

    Timer {
        id: scanDebounce
        interval: 700
        onTriggered: root.scanThumbs()
    }

    Process {
        id: scanner
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {};
                let missing = 0;
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p.length < 3)
                        continue;
                    if (p[2] === "1")
                        next[p[0]] = p[1];
                    else
                        missing++;
                }
                root.thumbs = next;
                if (missing > 0)
                    maker.exec(["sh", root.thumbScript, "make", root.directory]);
                else if (root.rescanPending)
                    scanDebounce.restart();
            }
        }
    }

    Process {
        id: maker
        onExited: {
            if (root.rescanPending)
                scanDebounce.restart();
        }
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t");
                if (p.length >= 3 && p[0] === "ok") {
                    const next = Object.assign({}, root.thumbs);
                    next[p[1]] = p[2];
                    root.thumbs = next;
                }
            }
        }
    }

    Connections {
        target: SettingsService
        function onLoadedChanged() {
            scanDebounce.restart();
        }
    }

    function clearThumbCache() {
        root.thumbs = ({});
        Quickshell.execDetached(["sh", root.thumbScript, "clear"]);
    }

    // A random wallpaper from the folder, never the one already on screen.
    //   random()        every monitor (each gets its own pick when perMonitor is on)
    //   random("DP-1")  that monitor only (needs perMonitor, else it is the same as random())
    function random(screenName) {
        const all = [];
        for (let i = 0; i < files.count; i++) {
            const p = files.get(i, "filePath");
            if (p)
                all.push(p);
        }
        if (all.length === 0)
            return;
        const choose = (avoid) => {
            let list = all.filter(p => avoid.indexOf(p) < 0);
            if (list.length === 0)
                list = all.filter(p => p !== avoid[0]);
            if (list.length === 0)
                return "";
            return list[Math.floor(Math.random() * list.length)];
        };

        if (!root.perMonitor) {
            root.setWallpaper(choose([root.defaultPath]));
            return;
        }
        if (screenName) {
            root.setWallpaper(choose([root.pathFor(screenName)]), screenName);
            return;
        }
        // Every monitor, each its own: avoid the monitor's own current one
        // first, then the ones already picked in this round.
        const taken = [];
        for (const s of Quickshell.screens) {
            const pick = choose([root.pathFor(s.name)].concat(taken));
            if (pick === "")
                continue;
            taken.push(pick);
            root.setWallpaper(pick, s.name);
        }
    }

    // Every N minutes (Settings -> Desktop -> Wallpaper -> Random wallpaper).
    Timer {
        interval: Math.max(1, SettingsService.get("wallpaper.randomMinutes")) * 60 * 1000
        running: SettingsService.get("wallpaper.randomMinutes") > 0 && !root.restoring
        repeat: true
        onTriggered: root.random("")
    }

    IpcHandler {
        target: "wallpaper"

        // Every monitor (or, with perMonitor on, one new pick for each).
        function random(): void {
            root.random("");
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        // The theme monitor's wallpaper.
        function get(): string {
            return root.currentPath;
        }

        // One monitor. Needs "One wallpaper per monitor" on; with it off
        // these act on every monitor. `monitors` lists name <TAB> wallpaper.
        function setmonitor(monitor: string, path: string): void {
            root.setWallpaper(path, monitor);
        }

        function getmonitor(monitor: string): string {
            return root.pathFor(monitor);
        }

        function randommonitor(monitor: string): void {
            root.random(monitor);
        }

        function monitors(): string {
            return Quickshell.screens.map(s => s.name + "\t" + root.pathFor(s.name)).join("\n");
        }

        function clearcache(): void {
            root.clearThumbCache();
        }

        // The folder the picker lists (default ~/Pictures/Wallpapers).
        // getfolder answers the folder in use; setfolder takes a path (~ works);
        // resetfolder goes back to the default; pickfolder opens the chooser.
        function getfolder(): string {
            return root.directory;
        }

        function setfolder(path: string): void {
            root.setFolder(path);
        }

        function resetfolder(): void {
            root.resetFolder();
        }

        function pickfolder(): void {
            root.pickFolder("");
        }

        // The lockscreen's own wallpaper (Settings -> Desktop -> Wallpaper ->
        // Separate Lockscreen Wallpaper). set* store the pick even while the
        // option is off; it shows once it is on. get* answer what the
        // lockscreen shows now (the desktop's wallpaper while the option is off).
        function setlock(path: string): void {
            root.setLockWallpaper(path);
        }

        function getlock(): string {
            return root.lockCurrentPath;
        }

        function setlockmonitor(monitor: string, path: string): void {
            root.setLockWallpaper(path, monitor);
        }

        function getlockmonitor(monitor: string): string {
            return root.lockPathFor(monitor);
        }
    }
}
