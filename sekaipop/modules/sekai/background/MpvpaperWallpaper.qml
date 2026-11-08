import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Video wallpaper through mpvpaper instead of QtMultimedia.
//
// mpvpaper draws the video on its own Background-layer surface, so the shell's GPU work for a
// video wallpaper is zero and mpv can use hardware decoding. This item draws nothing itself: it
// only owns the mpvpaper process for one output. It has the same `path` / `paused` /
// `restartOnPause` interface as VideoWallpaper.qml, so WallpaperLayer can use either.
//
// When `paused` is set:
//   - restartOnPause false: mpv is paused through its own IPC socket, and continues where it
//     was when `paused` clears (nothing extra needs installing).
//   - restartOnPause true: the process is stopped (the still frame the shell already shows takes
//     over) and started again, from the beginning, when `paused` clears.
// If the IPC socket can't be reached, it behaves as restartOnPause until the item is reloaded.
//
// Edit Desktop (`hidden`): the surface can't shrink, so the process has to go. Just before it
// does, the current frame is saved through mpv's socket (`frameReady`) so the shell can freeze
// that frame inside the shrinking card; afterwards the video starts again at the point it was
// stopped (or from the start with restartOnPause).
Item {
    id: root

    property string path: ""
    property string screenName: ""
    property bool paused: false
    property bool restartOnPause: false

    // Edit Desktop: the wallpaper shrinks into a card, but mpvpaper's surface is full screen and
    // can't shrink, so it would sit over the whole edit screen. While `hidden` the process is
    // stopped (whatever restartOnPause says) so the shell's own picture shrinks instead.
    property bool hidden: false

    // Emitted with the path of a picture of the frame that was showing when `hidden` was set.
    signal frameReady(string path)

    // Emitted when mpvpaper could not be started (not installed, bad output name, ...), so the
    // caller can fall back to the built-in player.
    signal failed()

    // Extra mpv options; the defaults are the ones a wallpaper wants.
    property string mpvOptions: "no-audio loop=inf panscan=1.0 hwdec=auto-safe terminal=no screenshot-format=jpg screenshot-jpeg-quality=95"

    // mpv's control socket (one per output)
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
        + "/sekaipop-mpvpaper-" + root.screenName + ".sock"

    // Set when the socket never came up: pausing then means stopping the process.
    property bool ipcFailed: false
    readonly property bool stopOnPause: root.restartOnPause || root.ipcFailed

    // The saved frame, and where the video was when it was saved.
    readonly property string framePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
        + "/sekaipop-mpvpaper-" + root.screenName + "-frame.jpg"
    property real resumeAt: 0
    property real startAt: 0

    // True once the process may stop for Edit Desktop (after the frame is saved, or at once if
    // it can't be).
    property bool gone: false
    property bool capturing: false

    // Set for a moment after mpvpaper died although it was wanted (something killed it: a theme
    // script's `pkill mpvpaper`, an OOM kill, ...). `wanted` drops and comes back, which starts it again.
    property bool respawning: false
    property int respawnCount: 0

    readonly property bool wanted: root.path !== "" && root.screenName !== ""
        && !root.gone && !root.respawning && (!root.paused || !root.stopOnPause)

    property double startedAt: 0
    property int connectTries: 0

    // Kills any mpvpaper left over for this output (found by its control-socket path). A stopped
    // or reloaded mpvpaper does not always exit when asked, and every leftover keeps decoding the
    // video and holds its own copy of it in memory. Runs before each start, and 1.5 s after each
    // stop. pgrep -x only lists processes named mpvpaper, so this shell never matches itself.
    readonly property string reapCmd: "for p in $(pgrep -x mpvpaper); do tr '\\0' ' ' < /proc/$p/cmdline | grep -qF -- 'input-ipc-server="
        + root.socketPath + "' && kill -9 $p; done; true"

    // Starts mpvpaper so that it dies with the shell. The kernel kills it (SIGKILL) the moment
    // the quickshell process that started it exits, however that happens (`killall qs`, a crash,
    // a restart), so a restarted shell does not find the old video still on screen, and no
    // orphan keeps decoding. KILL rather than TERM: no cleanup is wanted (a SIGTERM'd mpvpaper
    // may delete a control socket the new one has already made), and a paused one is slow to
    // act on TERM. Without setpriv (util-linux) it is started plainly, as before.
    readonly property string execCmd: "if command -v setpriv >/dev/null 2>&1; then exec setpriv --pdeathsig KILL mpvpaper \"$@\"; else exec mpvpaper \"$@\"; fi"

    function sendCommand(args, id) {
        sock.write(JSON.stringify({ command: args, request_id: id }) + "\n")
    }

    function startCapture() {
        root.capturing = true
        root.resumeAt = 0
        root.sendCommand(["set_property", "pause", true], 10)
        root.sendCommand(["get_property", "time-pos"], 1)
        root.sendCommand(["screenshot-to-file", root.framePath, "video"], 2)
        sock.flush()
        captureTimer.restart()
    }

    function finishCapture(ok) {
        captureTimer.stop()
        if (!root.capturing)
            return
        root.capturing = false
        if (!root.hidden)
            return
        root.startAt = (!root.restartOnPause && root.resumeAt > 0.05) ? root.resumeAt : 0
        if (ok)
            root.frameReady(root.framePath)
        else
            console.warn("MpvpaperWallpaper: could not save the current frame for Edit Desktop; showing the first frame")
        // Ask mpv to exit by itself as well: a paused mpvpaper may be slow to act on SIGTERM.
        root.sendCommand(["quit"], 3)
        sock.flush()
        root.gone = true
    }

    onHiddenChanged: {
        if (root.hidden) {
            if (proc.running && sock.connected && !root.stopOnPause)
                root.startCapture()
            else
                root.gone = true
        } else {
            captureTimer.stop()
            root.capturing = false
            root.gone = false
        }
    }

    function onLine(line) {
        try {
            const r = JSON.parse(line)
            if (r.request_id === 1 && r.error === "success" && typeof r.data === "number")
                root.resumeAt = r.data
            else if (r.request_id === 2)
                root.finishCapture(r.error === "success")
        } catch (e) {
        }
    }

    Process {
        id: reaper
    }

    Timer {
        id: lateRestack
        interval: 800
        onTriggered: WallpaperService.restackWidgets()
    }

    Timer {
        id: laterRestack
        interval: 2500
        onTriggered: WallpaperService.restackWidgets()
    }

    // Safety net for a slow start (login, a big video): WallpaperService also restacks the
    // moment Hyprland reports mpvpaper's surface mapping, these two only matter if that event
    // never comes (a different compositor, a renamed namespace).
    Timer {
        id: slowRestack
        interval: 6000
        onTriggered: WallpaperService.restackWidgets()
    }

    Timer {
        id: slowerRestack
        interval: 14000
        onTriggered: WallpaperService.restackWidgets()
    }

    Timer {
        interval: 1500
        running: !root.wanted && root.path !== "" && root.screenName !== ""
        onTriggered: reaper.exec(["sh", "-c", root.reapCmd])
    }

    Timer {
        id: captureTimer
        interval: 1000
        onTriggered: root.finishCapture(false)
    }

    Timer {
        id: respawnTimer
        interval: 700
        onTriggered: root.respawning = false
    }

    // A run that lasted this long was healthy: the next death starts the count again.
    Timer {
        id: healthyTimer
        interval: 60000
        onTriggered: root.respawnCount = 0
    }

    function sendPause() {
        if (!sock.connected)
            return
        sock.write(JSON.stringify({ command: ["set_property", "pause", root.paused] }) + "\n")
        sock.flush()
    }

    onPausedChanged: root.sendPause()

    Process {
        id: proc

        running: root.wanted
        command: ["sh", "-c", root.reapCmd + "; " + root.execCmd, "sh", "-o",
            root.mpvOptions + " input-ipc-server=" + root.socketPath + (root.paused ? " pause=yes" : "")
                + (root.startAt > 0 ? " start=" + root.startAt.toFixed(3) : ""),
            root.screenName, root.path]

        onStarted: {
            root.startedAt = Date.now()
            root.connectTries = 0
            root.startAt = 0
            healthyTimer.restart()
            // mpvpaper maps its surface a little after it starts (and slower on
            // a big video): put the desktop widgets back on top once it is
            // there. Twice, so a slow start is caught too.
            lateRestack.restart()
            laterRestack.restart()
            slowRestack.restart()
            slowerRestack.restart()
        }
        onExited: (code, status) => {
            sock.connected = false
            // Asked to stop (paused, path changed, item destroyed): nothing to report.
            if (!root.wanted)
                return
            // Died almost at once while it was wanted: it never worked.
            if (code !== 0 && Date.now() - root.startedAt < 3000) {
                console.warn("MpvpaperWallpaper: mpvpaper exited with code " + code
                    + " right after starting (is it installed? `mpvpaper -d` lists outputs); using the built-in player")
                root.failed()
                return
            }
            // It had been running and was still wanted, so someone else ended it (switching light /
            // dark runs a script that can `pkill mpvpaper`). Nothing else would start it again, and
            // the wallpaper would stay frozen on its first frame. Start it again, unless it keeps
            // dying: then the built-in player takes over.
            root.respawnCount++
            if (root.respawnCount > 4) {
                console.warn("MpvpaperWallpaper: mpvpaper keeps exiting; using the built-in player")
                root.failed()
                return
            }
            console.warn("MpvpaperWallpaper: mpvpaper exited (code " + code + ") while still wanted; starting it again")
            root.respawning = true
            respawnTimer.restart()
        }
    }

    Socket {
        id: sock

        path: root.socketPath
        connected: false

        // The state may have changed while it was connecting.
        onConnectedChanged: if (connected) {
            root.sendPause()
            // mpv's socket is up, so its surface is too.
            WallpaperService.restackWidgets()
        }

        parser: SplitParser {
            onRead: data => root.onLine(data)
        }
    }

    // mpv creates its socket a moment after it starts; keep trying for a few seconds.
    Timer {
        interval: 500
        repeat: true
        running: proc.running && !sock.connected && !root.stopOnPause
        onTriggered: {
            root.connectTries++
            if (root.connectTries > 10) {
                console.warn("MpvpaperWallpaper: mpv's control socket never appeared; pausing will stop and restart the video instead")
                root.ipcFailed = true
                return
            }
            sock.connected = true
        }
    }
}
