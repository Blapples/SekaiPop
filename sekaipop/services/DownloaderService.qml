pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/DownloadMath.js" as DM
import qs.modules.common

// The desktop Downloader widget's state: where it sits, whether it is shown, how big it is, the
// options (video / audio / mute, quality, where files go, which engine), and the queue of
// downloads. Kept as its own singleton (like WaterTankService.qml) so anything else can start a
// download or flip the widget without touching DownloaderWidget.qml:
//
//   import qs.services
//   ...
//   DownloaderService.submit("https://example.org/video")
//
// DownloaderWidget.qml (and DownloaderTile.qml, its 1 x 1 face) are the only things that draw it.
//
// The engines (scripts/downloader/download.sh does the work, one link at a time):
//   yt-dlp      runs on this machine, no server in between: videos and sound from a very long list
//               of sites. Needs `yt-dlp` (and `ffmpeg` for the sound only and for joining video and audio).
//   gallery-dl  pictures and picture posts (Twitter / X, Instagram, Pinterest, Reddit ...), also on
//               this machine. Needs `gallery-dl`.
//   cobalt      asks a cobalt instance (https://github.com/imputnet/cobalt) for the file. You set the
//               instance's address (and its API key if it wants one) in Settings > Desktop >
//               Downloader. The public cobalt instances use bot protection and are not for other
//               programs to use: run your own, or ask the owner of one.
//   auto        tries what is installed, in that order, until one works (gallery-dl only for video
//               mode, cobalt only when an instance is set).
//
// A post with several items (a carousel): with "Ask which ones" on, and the widget at 2 x 2, the
// items are listed first (status "choosing"), the user ticks the ones they want, and a second run of
// the script ("fetch") saves just those. At 1 x 1, or with it off, all of them are saved.
//
// One download runs at a time; the rest wait in the queue. The running one's numbers (percent,
// speed, time left) live in `live*` and not in `jobs`, so the list is not rebuilt on every line
// the script prints. A restart forgets what was still going; the last finished downloads are kept.
//
// What a desktop preset holds (PresetWidgets.qml): the spot, the monitor, the size and on / off.
// The options, the cobalt address and key, and the finished downloads are yours, not the look's.
Singleton {
    id: root

    // False until the saved state has been read. Nothing is written before then, or a fresh
    // start would overwrite what's on disk with defaults.
    property bool loaded: false

    property bool shown: false       // off until you add it: ipc downloader toggle / Edit Desktop

    // The widget's size: "1x1" (154 x 132 with the housing: one key you press to download what
    // you copied) or "2x2" (320 x 276: the options, the queue and the finished downloads).
    property string size: "1x1"
    readonly property bool tiny: root.size === "1x1"

    property real posX: -1           // -1 = never placed; widget picks a default
    property real posY: -1
    // The shell scale (ShellScale) posX / posY were saved at (see WeatherCardService.qml).
    property real posScale: 0
    // The monitor (output name, e.g. "DP-1") it was last dropped on. Empty = the first screen.
    property string screenName: ""

    // ===== options =====
    property string engine: "auto"       // auto | ytdlp | cobalt
    property string mode: "video"        // video | audio | mute
    property string quality: "1080"      // max | 1080 | 720 | 480
    property string audioFormat: "mp3"   // mp3 | opus | m4a | flac | wav | best
    property string folder: ""           // "" = your Downloads folder
    property string cobaltUrl: ""        // the instance's address
    property string cobaltKey: ""        // its API key, if it wants one (kept in a file only you can read)
    property bool notify: true           // a notification when a download is finished
    property string cookies: ""          // a browser whose login to use (Instagram, age limits ...); "" = none
    property string cookiesFile: ""      // or a cookies.txt file (wins over the browser)
    property string subs: ""             // a language to save the subtitles in ("en"); "" = none
    property string names: "basic"       // file names: basic | pretty | classic | nerdy
    property bool askWhich: false        // a post with several items: ask which ones (2 x 2 only)

    // ===== what is installed =====
    property bool toolsChecked: false
    property bool haveYtdlp: false
    property bool haveGalleryDl: false
    property bool haveFfmpeg: false

    // "auto" when something can run and the engine is not named; "" when nothing can.
    readonly property string activeEngine: DM.pickEngine(root.engine, root.haveYtdlp, root.cobaltUrl, root.haveGalleryDl)
    // What to tell the user when nothing can download ("" = something can).
    readonly property string problem: root.toolsChecked ? DM.missingText(root.engine, root.haveYtdlp, root.cobaltUrl, root.haveGalleryDl) : ""

    // ===== the queue =====
    // { id, url, host, title, status, pct, speed, eta, file, error, mode, quality, engine, when }
    // (modules/common/functions/DownloadMath.js). Always a NEW array when anything changes.
    property var jobs: []
    readonly property var counts: DM.stats(root.jobs)
    readonly property bool busy: root.counts.running + root.counts.queued > 0
    // Newest first, for the lists.
    readonly property var recent: root.jobs.slice().reverse()

    // The running download: its id (0 = none) and what the script has said about it.
    property int runningId: 0
    property string liveEngine: ""       // which engine is working now (ytdlp, gallerydl, cobalt)
    property var liveItems: []           // the items of a post, while the script lists them
    property bool sawChoose: false
    property real livePct: -1            // -1 = not known yet
    property string liveSpeed: ""
    property string liveEta: ""
    property string liveTitle: ""
    property string liveFile: ""
    property string liveError: ""
    property bool sawDone: false
    property bool cancelling: false

    // The job that is waiting for the user to choose items (null = none), and which items are on.
    // The mask lives apart from `jobs` so ticking an item does not rebuild the list.
    property var pickMasks: ({})
    readonly property int pickIndex: DM.firstChoosing(root.jobs)
    readonly property var pickJob: root.pickIndex >= 0 ? root.jobs[root.pickIndex] : null
    readonly property var pickMask: root.pickJob && root.pickMasks[root.pickJob.id] ? root.pickMasks[root.pickJob.id] : []

    // For the widget's little animations and notes.
    signal jobAdded()
    // A post with several items is ready to choose from.
    signal pickReady()
    signal jobFinished(bool ok)
    // A link that could not be taken (nothing copied, not a link, nothing installed that can
    // download): the widget shows the reason.
    signal rejected(string why)

    readonly property string script: Directories.script("state/downloader-state.sh")
    readonly property string dlScript: Directories.script("downloader/download.sh")
    readonly property string openScript: Directories.script("downloader/open-folder.sh")

    // ===== taking a link =====

    // A link, or some text with one in it. Returns whether it was taken.
    function submit(text) {
        if (!root.loaded)
            return false
        const url = DM.firstUrl(text)
        if (url === "") {
            root.rejected(String(text || "").trim() === "" ? "Nothing copied: copy a link first" : "That isn't a link")
            return false
        }
        // Nothing can download yet: maybe yt-dlp was installed since the shell started. Look
        // again, and let that look start the queue (toolCheck) instead of failing the link now.
        const lookAgain = root.toolsChecked && root.activeEngine === ""
        const job = DM.newJob(DM.nextId(root.jobs), url, { mode: root.mode, quality: root.quality, engine: "" }, Date.now())
        root.jobs = DM.trimJobs(root.jobs.concat([job]))
        root.jobAdded()
        if (lookAgain)
            root.recheck()
        else
            root.pump()
        return true
    }

    // The link that is on the clipboard.
    function paste() {
        clip.exec(["wl-paste", "--no-newline"])
    }

    // Start the next waiting download, if nothing is running.
    function pump() {
        if (!root.loaded || !root.toolsChecked || runner.running)
            return
        const i = DM.nextQueued(root.jobs)
        if (i < 0)
            return
        const j = root.jobs[i]
        const fetching = j.fetch && j.fetch.length > 0
        const eng = fetching ? "fetch" : DM.pickEngine(root.engine, root.haveYtdlp, root.cobaltUrl, root.haveGalleryDl)
        if (eng === "") {
            const why = DM.missingText(root.engine, root.haveYtdlp, root.cobaltUrl, root.haveGalleryDl)
            root.jobs = DM.patch(root.jobs, j.id, { status: "failed", error: why !== "" ? why : "Nothing here can download that" })
            root.rejected(why)
            root.jobFinished(false)
            Qt.callLater(root.pump)
            return
        }
        root.runningId = j.id
        root.livePct = -1
        root.liveSpeed = ""
        root.liveEta = ""
        root.liveTitle = ""
        root.liveFile = ""
        root.liveError = ""
        root.liveEngine = ""
        root.liveItems = []
        root.sawChoose = false
        root.sawDone = false
        root.cancelling = false
        root.jobs = DM.patch(root.jobs, j.id, { status: "running", engine: eng })
        // Everything private goes in the environment, not on the command line (see download.sh).
        runner.environment = ({
            SEKAI_COBALT_URL: root.cobaltUrl,
            SEKAI_COBALT_KEY: root.cobaltKey,
            SEKAI_COOKIES: root.cookies,
            SEKAI_COOKIES_FILE: root.cookiesFile,
            SEKAI_SUBS: root.subs,
            SEKAI_NAMES: root.names,
            // Ask which items only when the card is big enough to show them, and not on the
            // second run (the items are already chosen).
            SEKAI_PICK: (root.askWhich && !root.tiny && !fetching) ? "1" : "",
            SEKAI_ITEMS: fetching ? DM.itemsText(j.fetch) : ""
        })
        runner.exec(["bash", root.dlScript, eng, j.mode, j.quality, root.audioFormat, root.folder, j.url])
    }

    // A line of what scripts/downloader/download.sh prints.
    function onLine(line) {
        const e = DM.parseLine(line)
        if (!e || root.runningId === 0)
            return
        if (e.kind === "title") {
            root.liveTitle = e.text
            root.jobs = DM.patch(root.jobs, root.runningId, { title: e.text })
        } else if (e.kind === "prog") {
            root.livePct = e.pct
            root.liveSpeed = e.speed
            root.liveEta = e.eta
        } else if (e.kind === "file") {
            root.liveFile = e.path
        } else if (e.kind === "err") {
            root.liveError = e.text
        } else if (e.kind === "done") {
            root.sawDone = true
        } else if (e.kind === "engine") {
            root.liveEngine = e.name
            root.livePct = -1
            root.jobs = DM.patch(root.jobs, root.runningId, { engine: e.name })
        } else if (e.kind === "item") {
            root.liveItems = DM.addItem(root.liveItems, e)
        } else if (e.kind === "choose") {
            root.sawChoose = true
        }
    }

    function onExit(code) {
        const id = root.runningId
        if (id === 0)
            return
        const i = DM.indexOfId(root.jobs, id)
        const old = i >= 0 ? root.jobs[i] : null
        const title = root.liveTitle !== "" ? root.liveTitle : (old ? old.title : "")
        root.runningId = 0
        if (!root.cancelling && code === 0 && root.sawChoose && root.liveItems.length > 1) {
            // A post with several items: wait for the user to choose (the next download can go on).
            const masks = Object.assign({}, root.pickMasks)
            masks[id] = DM.maskOf(root.liveItems.length, true)
            root.pickMasks = masks
            root.jobs = DM.patch(root.jobs, id, { status: "choosing", items: root.liveItems, pct: -1, speed: "", eta: "" })
            root.cancelling = false
            root.sawChoose = false
            root.pickReady()
            root.pump()
            return
        }
        if (root.cancelling) {
            root.jobs = DM.patch(root.jobs, id, { status: "cancelled", pct: -1, speed: "", eta: "" })
        } else if (root.sawDone && code === 0) {
            const name = title !== "" ? title : DM.fileName(root.liveFile)
            root.jobs = DM.patch(root.jobs, id, { status: "done", pct: 100, speed: "", eta: "", file: root.liveFile, title: name })
            if (root.notify)
                Quickshell.execDetached(["notify-send", "-a", "Downloader", "-i", "folder-download", "Downloaded", name])
            root.persist()
            root.jobFinished(true)
        } else {
            const why = root.liveError !== "" ? root.liveError : "It stopped (code " + code + ")"
            root.jobs = DM.patch(root.jobs, id, { status: "failed", pct: -1, speed: "", eta: "", error: why })
            root.jobFinished(false)
        }
        root.cancelling = false
        root.sawDone = false
        root.pump()
    }

    // ===== the list =====

    // Stop a running download, or take a waiting one out of the queue.
    function cancel(id) {
        if (id === root.runningId && id !== 0) {
            root.cancelling = true
            runner.signal(15)
            return
        }
        const i = DM.indexOfId(root.jobs, id)
        if (i < 0)
            return
        if (root.jobs[i].status === "queued") {
            root.jobs = root.jobs.filter(j => j.id !== id)
        } else if (root.jobs[i].status === "choosing") {
            root.dropMask(id)
            root.jobs = DM.patch(root.jobs, id, { status: "cancelled", items: [] })
        }
    }

    // Stop everything: the running one, the ones waiting, and a post waiting to be chosen from.
    function cancelAll() {
        root.jobs = root.jobs.filter(j => j.status !== "queued")
        const choosing = root.jobs.filter(j => j.status === "choosing").map(j => j.id)
        for (let k = 0; k < choosing.length; k++)
            root.cancel(choosing[k])
        if (root.runningId !== 0)
            root.cancel(root.runningId)
    }

    // ===== choosing items =====

    function dropMask(id) {
        const masks = Object.assign({}, root.pickMasks)
        delete masks[id]
        root.pickMasks = masks
    }

    // Tick or untick one item of the post that is waiting.
    function togglePick(id, index) {
        const m = root.pickMasks[id]
        if (!m)
            return
        const masks = Object.assign({}, root.pickMasks)
        masks[id] = DM.toggleMask(m, index)
        root.pickMasks = masks
    }

    // Every item on, or every item off.
    function pickAll(id, on) {
        const i = DM.indexOfId(root.jobs, id)
        if (i < 0)
            return
        const masks = Object.assign({}, root.pickMasks)
        masks[id] = DM.maskOf(root.jobs[i].items.length, on)
        root.pickMasks = masks
    }

    // Save the ticked items. (Nothing ticked: the post is let go.)
    function confirmPick(id) {
        const i = DM.indexOfId(root.jobs, id)
        const m = root.pickMasks[id]
        if (i < 0 || !m || root.jobs[i].status !== "choosing")
            return
        const chosen = DM.chosenItems(root.jobs[i].items, m)
        root.dropMask(id)
        if (chosen.length === 0) {
            root.jobs = DM.patch(root.jobs, id, { status: "cancelled", items: [] })
            return
        }
        root.jobs = DM.patch(root.jobs, id, { status: "queued", fetch: chosen, items: [], pct: -1 })
        root.pump()
    }

    // Try a failed or cancelled one again, as it was asked for.
    function retry(id) {
        const i = DM.indexOfId(root.jobs, id)
        if (i < 0)
            return
        const old = root.jobs[i]
        if (old.status !== "failed" && old.status !== "cancelled")
            return
        const job = DM.newJob(DM.nextId(root.jobs), old.url, { mode: old.mode, quality: old.quality, engine: "" }, Date.now())
        root.jobs = DM.trimJobs(root.jobs.filter(j => j.id !== id).concat([job]))
        root.jobAdded()
        root.pump()
    }

    // Take a finished, failed or cancelled one off the list (the file stays where it is).
    function remove(id) {
        const i = DM.indexOfId(root.jobs, id)
        if (i < 0 || DM.isLive(root.jobs[i]))
            return
        root.jobs = root.jobs.filter(j => j.id !== id)
        root.persist()
    }

    function clearFinished() {
        root.jobs = root.jobs.filter(j => DM.isLive(j))
        root.persist()
    }

    // Open a finished file (in your player or viewer).
    function openFile(id) {
        const i = DM.indexOfId(root.jobs, id)
        if (i < 0 || root.jobs[i].file === "")
            return
        Quickshell.execDetached(["xdg-open", root.jobs[i].file])
    }

    // Open the folder the files go to.
    function openFolder() {
        Quickshell.execDetached(["sh", root.openScript, root.folder])
    }

    // ===== options =====

    function setMode(value) {
        const v = DM.clampMode(value)
        if (v === root.mode)
            return
        root.mode = v
        root.persist()
    }

    function cycleMode() {
        root.setMode(DM.nextIn(DM.MODES, root.mode))
    }

    function setQuality(value) {
        const v = DM.clampQuality(value)
        if (v === root.quality)
            return
        root.quality = v
        root.persist()
    }

    function cycleQuality() {
        root.setQuality(DM.nextIn(DM.QUALITIES, root.quality))
    }

    function setAudioFormat(value) {
        const v = DM.clampAudio(value)
        if (v === root.audioFormat)
            return
        root.audioFormat = v
        root.persist()
    }

    function cycleAudio() {
        root.setAudioFormat(DM.nextIn(DM.AUDIO_FORMATS, root.audioFormat))
    }

    function setEngine(value) {
        const v = DM.clampEngine(value)
        if (v === root.engine)
            return
        root.engine = v
        root.persist()
    }

    function setFolder(value) {
        const v = String(value || "").trim()
        if (v === root.folder)
            return
        root.folder = v
        root.persist()
    }

    function setCobaltUrl(value) {
        const v = String(value || "").trim()
        if (v === root.cobaltUrl)
            return
        root.cobaltUrl = v
        root.persist()
    }

    function setCobaltKey(value) {
        const v = String(value || "").trim()
        if (v === root.cobaltKey)
            return
        root.cobaltKey = v
        root.persist()
    }

    function setCookies(value) {
        const v = DM.clampBrowser(String(value || "").trim().toLowerCase())
        if (v === root.cookies)
            return
        root.cookies = v
        root.persist()
    }

    function setCookiesFile(value) {
        const v = String(value || "").trim()
        if (v === root.cookiesFile)
            return
        root.cookiesFile = v
        root.persist()
    }

    function setSubs(value) {
        const v = DM.cleanLang(value)
        if (v === root.subs)
            return
        root.subs = v
        root.persist()
    }

    function setNames(value) {
        const v = DM.clampNames(value)
        if (v === root.names)
            return
        root.names = v
        root.persist()
    }

    function setAskWhich(value) {
        if (value === root.askWhich)
            return
        root.askWhich = value
        root.persist()
    }

    function setNotify(value) {
        if (value === root.notify)
            return
        root.notify = value
        root.persist()
    }

    // Saved straight away (no wait): a refresh or reload right after you drop the widget must
    // not be able to beat the save.
    function setPosition(x, y, screen, scale) {
        if (!root.loaded)
            return
        root.posX = x
        root.posY = y
        if (typeof scale === "number" && scale > 0)
            root.posScale = scale
        if (typeof screen === "string" && screen !== "")
            root.screenName = screen
        saveTimer.stop()
        saver.save(root.snapshot())
    }

    function setShown(value) {
        root.shown = value
        root.persist()
    }

    // "1x1" (or "tiny"); anything else is "2x2".
    function setSize(value) {
        const v = (value === "1x1" || value === "tiny") ? "1x1" : "2x2"
        if (v === root.size)
            return
        root.size = v
        root.persist()
    }

    function toggleSize() {
        root.setSize(root.tiny ? "2x2" : "1x1")
    }

    // ===== what is installed =====

    function recheck() {
        toolCheck.exec(["sh", "-c", root.toolsCommand])
    }

    // One short line of how things are, for `ipc call downloader status`.
    function statusText() {
        const c = root.counts
        return "engine " + (root.activeEngine !== "" ? root.activeEngine : "none") + ", " + root.mode + " " + root.quality
            + ", " + c.running + " running, " + c.queued + " waiting, " + c.choosing + " to choose, " + c.done + " done, " + c.failed + " failed"
            + (root.problem !== "" ? " (" + root.problem + ")" : "")
    }

    // ===== persistence =====

    // The cobalt key is in here, so the file is mode 600 (downloader-state.sh).
    function snapshot() {
        return JSON.stringify({
            x: root.posX,
            y: root.posY,
            scale: root.posScale,
            screen: root.screenName,
            shown: root.shown,
            size: root.size,
            engine: root.engine,
            mode: root.mode,
            quality: root.quality,
            audioFormat: root.audioFormat,
            folder: root.folder,
            cobaltUrl: root.cobaltUrl,
            cobaltKey: root.cobaltKey,
            notify: root.notify,
            cookies: root.cookies,
            cookiesFile: root.cookiesFile,
            subs: root.subs,
            names: root.names,
            askWhich: root.askWhich,
            done: DM.remember(root.jobs)
        })
    }

    function restore(text) {
        try {
            const s = JSON.parse(text)
            if (typeof s.x === "number")
                root.posX = s.x
            if (typeof s.y === "number")
                root.posY = s.y
            if (typeof s.scale === "number" && s.scale > 0)
                root.posScale = s.scale
            if (typeof s.screen === "string")
                root.screenName = s.screen
            // A preset (or a file) that says nothing about it leaves the widget off.
            root.shown = s.shown === true
            root.size = s.size === "2x2" ? "2x2" : "1x1"
            if (typeof s.engine === "string")
                root.engine = DM.clampEngine(s.engine)
            if (typeof s.mode === "string")
                root.mode = DM.clampMode(s.mode)
            if (s.quality !== undefined)
                root.quality = DM.clampQuality(s.quality)
            if (typeof s.audioFormat === "string")
                root.audioFormat = DM.clampAudio(s.audioFormat)
            if (typeof s.folder === "string")
                root.folder = s.folder
            if (typeof s.cobaltUrl === "string")
                root.cobaltUrl = s.cobaltUrl
            if (typeof s.cobaltKey === "string")
                root.cobaltKey = s.cobaltKey
            if (typeof s.notify === "boolean")
                root.notify = s.notify
            if (typeof s.cookies === "string")
                root.cookies = DM.clampBrowser(s.cookies)
            if (typeof s.cookiesFile === "string")
                root.cookiesFile = s.cookiesFile
            if (typeof s.subs === "string")
                root.subs = DM.cleanLang(s.subs)
            if (typeof s.names === "string")
                root.names = DM.clampNames(s.names)
            if (typeof s.askWhich === "boolean")
                root.askWhich = s.askWhich
            if (Array.isArray(s.done) && root.jobs.length === 0)
                root.jobs = DM.recall(s.done)
        } catch (e) {
            // No file yet (first run) or an unreadable one: keep the defaults.
        }
        root.loaded = true
        root.pump()
    }

    // Runs once, at startup.
    Process {
        running: true
        command: ["sh", root.script, "load"]
        stdout: StdioCollector {
            onStreamFinished: root.restore(text)
        }
    }

    readonly property string toolsCommand: "for t in yt-dlp gallery-dl ffmpeg; do command -v $t >/dev/null 2>&1 && echo have:$t; done; true"

    Process {
        id: toolCheck
        running: true
        command: ["sh", "-c", root.toolsCommand]
        stdout: StdioCollector {
            onStreamFinished: {
                root.haveYtdlp = text.indexOf("have:yt-dlp") >= 0
                root.haveGalleryDl = text.indexOf("have:gallery-dl") >= 0
                root.haveFfmpeg = text.indexOf("have:ffmpeg") >= 0
                root.toolsChecked = true
                root.pump()
            }
        }
    }

    // The link on the clipboard.
    Process {
        id: clip
        stdout: StdioCollector {
            onStreamFinished: root.submit(text)
        }
    }

    // The one running download.
    Process {
        id: runner
        stdout: SplitParser {
            onRead: line => root.onLine(line)
        }
        onExited: (code, status) => root.onExit(code)
    }

    function persist() {
        if (root.loaded)
            saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: saver.save(root.snapshot())
    }

    // Fire-and-forget save. Queues at most one pending snapshot behind an in-flight save rather
    // than dropping it, so the *last* state is what ends up on disk (same as WeatherCardService).
    // The JSON goes in the environment (it can hold the cobalt key), see downloader-state.sh.
    Process {
        id: saver

        property var pending: null

        function start(json) {
            saver.environment = ({ SEKAI_DL_STATE: json })
            saver.exec(["sh", root.script, "save"])
        }

        function save(json) {
            if (saver.running) {
                saver.pending = json
                return
            }
            saver.pending = null
            saver.start(json)
        }

        onExited: {
            if (saver.pending !== null) {
                const json = saver.pending
                saver.pending = null
                saver.start(json)
            }
        }
    }
}
