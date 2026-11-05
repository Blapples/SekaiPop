pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

// The shell's own screen-region picker (RegionSelector.qml draws it): state and
// actions. Pick a rectangle (or click a window) on a frozen picture of the
// screen, then do one of:
//
//   copy     the region goes to the clipboard
//   save     saved to ~/Pictures/Screenshots and copied
//   ocr      the text in the region is copied (tesseract)
//   search   the region is uploaded and opened in an image search
//   record   the region is recorded to ~/Videos/Recordings (wf-recorder)
//   recordSound   the same with sound (Settings -> region.audio: what you hear
//                 (system) or the microphone)
//
// Right-drag a region (no toolbar): it is cropped and opened in swappy.
//
// After a Copy or Save (the screenshot actions) a small preview card slides in
// at the bottom-right corner (RegionPreview.qml) showing what was taken, with
// Annotate (swappy), Copy, Save and close. It goes away by itself after a few
// seconds (not while the pointer is on it). Settings -> General -> Screen
// region: "Preview after a screenshot", "Preview stays".
//
// The action a key or IPC call asks for is only the one highlighted first: the
// toolbar under the selection offers all of them, and Enter runs the lit one.
//
//   qs -c sekaipop ipc call region screenshot|save|ocr|search|record|recordSound
//   qs -c sekaipop ipc call region stop          (stop a running recording)
//   qs -c sekaipop ipc call region toggleRecord  (record the region / stop)
// Bind them in hyprland.lua, e.g.
//   bind = SUPER SHIFT, S, exec, qs -c sekaipop ipc call region screenshot
//   bind = SUPER SHIFT, T, exec, qs -c sekaipop ipc call region ocr
//   bind = SUPER SHIFT, R, exec, qs -c sekaipop ipc call region toggleRecord
Singleton {
    id: root

    // Is the picker up, and which action is lit first.
    property bool open: false
    property string action: "copy"
    // Which monitor it was asked from (focused one); the picker appears on every
    // monitor but only that one takes keyboard focus.
    property string focusScreen: ""

    // Where the docks along the bottom edge stand, so the picker's toolbar can
    // sit above one instead of on it. Each dock (Dock.qml) reports itself with
    // setDock(): `top` is how far its top edge is above its screen's bottom
    // edge, in px, and `half` is half its width (it is centered on its screen).
    // { "DP-1": { top, half } }, only for a dock that is showing.
    property var docks: ({})

    function setDock(screenName, top, half) {
        if (!screenName)
            return
        const cur = root.docks[screenName]
        if (top > 0 && cur && cur.top === top && cur.half === half)
            return
        if (!(top > 0) && !cur)
            return
        const next = Object.assign({}, root.docks)
        if (top > 0)
            next[screenName] = { top: top, half: half }
        else
            delete next[screenName]
        root.docks = next
    }

    // The folder of the frozen pictures (one per monitor) and the cropped files.
    readonly property string tmpDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sekaipop-region"

    readonly property string script: Directories.script("system/region-action.sh")

    // `keys`: the letters that pick the action inside the picker (the first one
    // is drawn on its toolbar button). X is also Copy text (it is SUPER+SHIFT+X
    // outside the picker); Shift+R is Record with sound as well as A (see
    // actionForKey).
    readonly property var actions: [
        { id: "copy", icon: "content_copy", label: "Copy", keys: ["C"] },
        { id: "save", icon: "save", label: "Save", keys: ["S"] },
        { id: "ocr", icon: "text_snippet", label: "Copy text", keys: ["T", "X"] },
        { id: "search", icon: "image_search", label: "Image search", keys: ["I"] },
        { id: "record", icon: "videocam", label: "Record", keys: ["R"] },
        { id: "recordSound", icon: "mic", label: "Record with sound", keys: ["A"] }
    ]

    // The action a letter key picks in the picker, "" for none. `shift`: Shift is
    // held (Shift+R = Record with sound).
    function actionForKey(letter, shift) {
        if (letter === "R" && shift)
            return "recordSound"
        for (let i = 0; i < root.actions.length; i++) {
            if (root.actions[i].keys.indexOf(letter) >= 0)
                return root.actions[i].id
        }
        return ""
    }

    function show(act, screenName) {
        root.action = act
        root.focusScreen = screenName || ""
        // A preview card still on screen would be in the frozen picture:
        // take it down at once and open the picker once it is really gone.
        if (root.previewShown || Date.now() - root.previewHiddenAt < 450) {
            root.hidePreview(true)
            openTimer.restart()
            return
        }
        root.open = true
    }

    Timer {
        id: openTimer
        interval: 180
        onTriggered: {
            root.previewInstant = false
            root.open = true
        }
    }

    function hide() {
        root.open = false
    }

    // For a button inside a panel that is about to close: wait for it to be
    // gone, so it is not in the frozen picture.
    property string laterAction: ""
    function showLater(act) {
        root.laterAction = act
        laterTimer.restart()
    }
    Timer {
        id: laterTimer
        interval: 700
        onTriggered: root.show(root.laterAction, "")
    }

    // The picker's overlay is mapped when it opens and unmapped when it closes,
    // and Hyprland plays its own layer animation on both: the dim zooms in and
    // out. The picker has no animation of its own, so the compositor's is
    // switched off for this namespace (and the preview card's): the dim then
    // appears at once, at full size, and goes the same way. The dim itself is
    // untouched. `region-action.sh rules` does it, same as, in hyprland.lua,
    //   hl.layer_rule({ match = { namespace = "^sekaipop-region$" }, no_anim = true })
    //   hl.layer_rule({ match = { namespace = "^sekaipop-region-preview$" }, no_anim = true })
    //
    // A rule added live only lasts until Hyprland reloads its config (hyprctl
    // reload, an edit of hyprland.lua, the anti-flashbang tile, the Hyprland
    // page in Settings ...), and the zoom would come back with nothing to say
    // so. So the rules are put back at start-up and again after every reload
    // (a short wait, since a reload can send several events). With
    // `pcall(require, "sekaipop_overrides")` in hyprland.lua they are also kept
    // in that file and come back by themselves.
    function ensureNoAnim() {
        if (!noAnim.running)
            noAnim.exec(["sh", root.script, "rules"])
        else
            reloadWait.restart()   // still busy: try again, a reload is never lost
    }

    Process { id: noAnim }

    Timer {
        id: reloadWait
        interval: 250
        onTriggered: root.ensureNoAnim()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded")
                reloadWait.restart()
        }
    }

    Component.onCompleted: {
        // A preview left behind by a shell that was restarted while its card was up.
        Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/preview-*.png", "sh", root.tmpDir])
        root.ensureNoAnim()
    }

    // ===== doing it =====
    function run(act, screenObj, x, y, w, h, picture, scale) {
        root.open = false
        if (w < 2 || h < 2)
            return
        if (act === "record" || act === "recordSound") {
            root.startRecording(act === "recordSound",
                Math.round(screenObj.x + x) + "," + Math.round(screenObj.y + y) + " "
                + Math.round(w) + "x" + Math.round(h))
            return
        }
        const out = root.tmpDir + "/crop-" + Date.now() + ".png"
        // A Copy or Save (a screenshot) gets a preview card afterwards.
        const wantPreview = (act === "copy" || act === "save") && SettingsService.flag("region.preview")
        jobs.push({ act: act, out: out, picture: picture, x: x, y: y, w: w, h: h, scale: scale,
                    preview: wantPreview, previewOk: false, screenName: screenObj.name,
                    previewOut: root.tmpDir + "/preview-" + Date.now() + ".png",
                    geom: Math.round(screenObj.x + x) + "," + Math.round(screenObj.y + y) + " "
                          + Math.round(w) + "x" + Math.round(h) })
        root.pump()
    }

    // One job at a time (crop, then act), so a quick second pick queues.
    property var jobs: []
    property var current: null

    function pump() {
        if (root.current !== null || root.jobs.length === 0)
            return
        root.current = root.jobs.shift()
        const j = root.current
        cropper.exec(["sh", root.script, "crop", j.picture, String(j.x), String(j.y),
                      String(j.w), String(j.h), String(j.scale), j.out])
    }

    Process {
        id: cropper
        onExited: code => {
            const j = root.current
            if (j === null)
                return
            if (code === 0) {
                root.afterCrop(j)
            } else {
                // No ImageMagick (or the crop failed): grab the region live. The
                // selector has already gone, so it is not in the picture.
                fallback.exec(["sh", "-c", "grim -g \"$1\" \"$2\"", "sh", j.geom, j.out])
            }
        }
    }

    Process {
        id: fallback
        onExited: code => {
            const j = root.current
            if (j !== null && code === 0) {
                root.afterCrop(j)
            } else {
                Quickshell.execDetached(["notify-send", "-a", "sekaipop", "-i", "material:error", "Screen region",
                    "Couldn't grab the region (is grim installed?)"])
                root.finishJob(false)
            }
        }
    }

    // The cropped picture is ready: keep a copy for the preview card (the
    // actions delete the file they are given), then do the action.
    function afterCrop(j) {
        if (j.preview)
            stasher.exec(["sh", root.script, "stash", j.out, j.previewOut])
        else
            acter.exec(["sh", root.script, j.act, j.out])
    }

    Process {
        id: stasher
        onExited: code => {
            const j = root.current
            if (j === null)
                return
            j.previewOk = (code === 0)
            acter.exec(["sh", root.script, j.act, j.out])
        }
    }

    Process {
        id: acter
        onExited: code => root.finishJob(code === 0)
    }

    function finishJob(ok) {
        const j = root.current
        root.current = null
        if (j) {
            Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"", "sh", j.out])
            if (j.preview && j.previewOk) {
                if (ok)
                    root.showPreview(j)
                else
                    Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"", "sh", j.previewOut])
            }
        }
        root.pump()
        cleanupTimer.restart()
    }

    // ===== the preview card =====
    property bool previewShown: false
    // A copy of the picture in the temp folder, and the monitor it was taken on.
    property string previewFile: ""
    property string previewScreen: ""
    // Already saved to ~/Pictures/Screenshots (the card's Save button is then done).
    property bool previewSaved: false
    // When the card was last told to go, and whether it should vanish with no animation.
    property real previewHiddenAt: 0
    property bool previewInstant: false

    function showPreview(j) {
        releaseTimer.stop()
        root.discardPreviewFile()
        root.previewInstant = false
        root.previewFile = j.previewOut
        root.previewScreen = j.screenName
        root.previewSaved = (j.act === "save")
        root.previewShown = true
    }

    function hidePreview(instant) {
        if (root.previewShown)
            root.previewHiddenAt = Date.now()
        root.previewInstant = (instant === true)
        root.previewShown = false
        releaseTimer.restart()
    }

    function discardPreviewFile() {
        if (root.previewFile !== "")
            Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"", "sh", root.previewFile])
        root.previewFile = ""
    }

    // The file goes once the card has finished leaving.
    Timer {
        id: releaseTimer
        interval: 700
        onTriggered: {
            if (!root.previewShown)
                root.discardPreviewFile()
        }
    }

    // What the card's buttons do: the picture is handed over as a fresh copy
    // each time, so the card can offer more than one thing.
    function previewAct(act) {
        if (root.previewFile === "")
            return
        Quickshell.execDetached(["sh", root.script, "reuse", act, root.previewFile])
        if (act === "save")
            root.previewSaved = true
        else
            root.hidePreview(false)
    }

    // The frozen pictures (one per monitor) are only needed while the picker is up
    // and a crop is being made. A few seconds after both are over they are deleted.
    onOpenChanged: if (!root.open) cleanupTimer.restart()

    Timer {
        id: cleanupTimer
        interval: 4000
        onTriggered: {
            if (root.open)
                return
            if (root.current !== null || root.jobs.length > 0) {
                cleanupTimer.restart()
                return
            }
            Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/shot-*.png \"$1\"/crop-*.png", "sh", root.tmpDir])
        }
    }

    // ===== recording =====
    property string recordFile: ""
    readonly property bool recording: recorder.running

    function startRecording(withSound, geometry) {
        if (recorder.running)
            return
        const dir = Quickshell.env("HOME") + "/Videos/Recordings"
        root.recordFile = dir + "/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4"
        const sound = withSound ? SettingsService.get("region.audio") : "none"
        recorder.exec(["sh", root.script, "record", geometry, sound, root.recordFile])
    }

    function stopRecording() {
        // SIGINT: wf-recorder needs it (not a kill) to finish the file.
        if (recorder.running)
            recorder.signal(2)
    }

    Process {
        id: recorder
        onExited: {
            if (root.recordFile !== "") {
                Quickshell.execDetached(["sh", "-c",
                    "if [ -s \"$1\" ]; then notify-send -a sekaipop -i material:videocam 'Recording saved' \"$1\"; "
                    + "else notify-send -a sekaipop -i material:error 'Recording failed' 'wf-recorder stopped before it saved anything. Run it in a terminal to see why.'; fi",
                    "sh", root.recordFile])
                root.recordFile = ""
            }
        }
    }

    IpcHandler {
        target: "region"

        function screenshot(): void { root.show("copy", "") }
        function save(): void { root.show("save", "") }
        function ocr(): void { root.show("ocr", "") }
        function search(): void { root.show("search", "") }
        function record(): void {
            if (root.recording) root.stopRecording()
            else root.show("record", "")
        }
        function recordSound(): void {
            if (root.recording) root.stopRecording()
            else root.show("recordSound", "")
        }
        function toggleRecord(): void {
            if (root.recording) root.stopRecording()
            else root.show("record", "")
        }
        function stop(): void { root.stopRecording() }
        function cancel(): void { root.hide() }
    }
}
