import Quickshell
import Quickshell.Io
import QtQuick
import "../modules/common/functions/Extras.js" as X
import "../modules/common/functions/ClipPins.js" as Pins
import qs.services
import qs.modules.common

// The system side of the launcher extras -- what AppSource.qml is to apps.
// Overview.qml stays UI; it hands this file the search box's text and reads
// back what the box is asking for (`mode`) plus everything the cards show.
//
//   mode "calc"    calculator     (CalculatorCard.qml, all maths in Calc.js)
//   mode "clip"    clipboard      (ClipboardCard.qml, needs cliphist + wl-clipboard)
//   mode "color"   colour         (ColorCard.qml, `hyprpicker` for the eyedropper)
//   mode "emoji"   emoji picker   (EmojiCard.qml, data in Emoji.js)
//   mode "web"     browser-style web search (WebCard.qml, opens with xdg-open)
//   mode "shell"   a command to run (a row in the results list)
//   mode ""        nothing special -- apps (and any matching actions) as usual
//
// Everything degrades quietly: a missing tool just leaves its card saying so.
Scope {
    id: root

    // The search box's text; Overview.qml binds this.
    property string query: ""

    // Only poll / fetch while the launcher is open.
    property bool active: false

    // Send what you type to DuckDuckGo's autocomplete while the web card is
    // showing (a real request per pause in typing). false = no suggestions
    // and no network use until you press Enter.
    property bool webSuggestions: SettingsService.flag("launcher.webSuggestions")


    // ===== what the box asks for =====
    readonly property var routed: X.route(root.query)
    readonly property string mode: routed.mode
    readonly property string arg: routed.arg
    readonly property string prefix: routed.prefix
    readonly property bool terminalCommand: routed.terminal

    // The web card's engine: what the trigger picked, unless you changed it
    // with Tab / a chip. Typing a different trigger resets it.
    property int engineOverride: -1
    readonly property int engine: engineOverride >= 0 ? engineOverride : routed.engine
    onModeChanged: engineOverride = -1
    readonly property var engines: X.ENGINES

    function cycleEngine(step) {
        engineOverride = (engine + step + X.ENGINES.length) % X.ENGINES.length
    }

    // ===== system actions + shell commands =====
    readonly property var listEntries: {
        const out = []
        if (root.mode === "shell") {
            const cmd = root.arg.trim()
            out.push({
                isAction: true, id: "shell", kind: "shell",
                title: cmd === "" ? (root.terminalCommand ? "Run in a terminal" : "Run a command") : cmd,
                sub: cmd === ""
                    ? "Type a command \u2014 > runs in the background, $ opens a terminal"
                    : (root.terminalCommand ? "Runs in a terminal that stays open" : "Runs in the background; output comes back as a notification"),
                glyph: root.terminalCommand ? "terminal" : "play_arrow",
                command: cmd, terminal: root.terminalCommand, confirm: false
            })
        }
        return out
    }

    // Actions that match the text, when it isn't a special mode.
    readonly property var actionMatches: root.mode === "" ? X.matchActions(root.query) : []

    function actionEntry(a) {
        return {
            isAction: true, id: a.id, kind: "action",
            title: a.title, sub: a.sub, glyph: a.glyph,
            confirm: a.confirm === true, def: a
        }
    }

    // Runs an action or command. `delay` waits for the launcher to leave the
    // screen first, so screenshots don't capture it and IPC calls land on
    // the window that has focus again.
    function run(entry) {
        if (!entry)
            return
        if (entry.kind === "shell") {
            if (entry.command === "")
                return
            root.spawn(entry.terminal ? X.terminalArgv(entry.command) : X.backgroundArgv(entry.command), 0.2)
            return
        }
        const a = entry.def
        if (!a)
            return
        if (a.ipc) {
            root.spawn(["qs", "-c", X.qsConfig, "ipc", "call"].concat(a.ipc), a.delay ?? 0.25)
        } else if (a.argv) {
            root.spawn(a.argv, a.delay ?? 0.25)
        }
    }

    function spawn(argv, delaySeconds) {
        Quickshell.execDetached(["sh", "-c", "sleep \"$1\"; shift; exec \"$@\"", "sh", String(delaySeconds)].concat(argv))
    }

    function copyText(text) {
        // wl-copy reads stdin; passing it as an argument would break on
        // text that starts with "-" or is very long.
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", text])
    }

    function openUrl(url) {
        Quickshell.execDetached(["xdg-open", url])
    }

    function typeText(text) {
        // wtype (optional) types into whatever window has focus once the
        // launcher has left; the copy already happened either way.
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; command -v wtype >/dev/null && wtype -- \"$1\"", "sh", text])
    }

    // ===== web suggestions =====
    property var suggestions: []
    property string suggestionsFor: ""

    readonly property string webQuery: root.mode === "web" ? root.arg.trim() : ""

    Timer {
        id: suggestDebounce
        interval: 220
        onTriggered: {
            if (root.webQuery === "" || X.looksLikeUrl(root.webQuery)) {
                root.suggestions = []
                return
            }
            suggestProc.wanted = root.webQuery
            suggestProc.running = false
            suggestProc.running = true
        }
    }

    onWebQueryChanged: {
        if (!root.webSuggestions || root.webQuery === "") {
            root.suggestions = []
            suggestDebounce.stop()
            return
        }
        suggestDebounce.restart()
    }

    Process {
        id: suggestProc
        property string wanted: ""
        command: ["curl", "-s", "--max-time", "3", "-G", "https://duckduckgo.com/ac/",
                  "--data-urlencode", "q=" + wanted, "--data-urlencode", "type=list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // The answer can arrive after you've typed on; only keep it if
                // it is still for what's in the box.
                if (suggestProc.wanted !== root.webQuery)
                    return
                try {
                    const json = JSON.parse(text)
                    root.suggestions = (json[1] || []).slice(0, 6)
                    root.suggestionsFor = suggestProc.wanted
                } catch (e) {
                    root.suggestions = []
                }
            }
        }
    }

    // ===== clipboard history =====
    property bool clipAvailable: false     // set true once the check below finds both tools
    // What the Clipboard card lists: the pins first (scripts/state/clip-pins.sh, kept
    // apart from cliphist so they outlive its cap, a wipe and a delete), then the
    // history without the copies of what is pinned (ClipPins.merge).
    property var clipHistory: []
    property var clipPins: []
    readonly property var clipEntries: Pins.merge(root.clipPins, root.clipHistory)
    property string clipFull: ""          // the full text of clipSelectedId
    property string clipImage: ""         // file:// path of a decoded image entry
    property string clipSelectedId: ""
    property string clipRaw: ""

    Process {
        running: true
        command: ["sh", "-c", "command -v cliphist >/dev/null && command -v wl-copy >/dev/null"]
        onExited: (code, status) => root.clipAvailable = (code === 0)
    }

    // Collect history from startup (text, and images). One pair for the whole shell:
    // ClipboardWatcher.qml (there are two launchers, each with an ExtrasSource).
    readonly property bool clipWatching: ClipboardWatcher.watching

    function refreshClip() {
        if (!clipAvailable)
            return
        if (!clipList.running)
            clipList.running = true
        root.refreshPins()
    }

    Process {
        id: clipList
        // cliphist only gives the first 100 characters of each entry as its preview;
        // ask for more so the filter finds words further in (older cliphist builds
        // without the flag fall back to the plain list).
        command: ["sh", "-c", "cliphist -preview-width 500 list 2>/dev/null || cliphist list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Only swap the list when it really changed, so the card's
                // scroll position isn't reset every poll.
                if (text === root.clipRaw)
                    return
                root.clipRaw = text
                root.clipHistory = X.parseClipList(text).slice(0, 300)
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.active && root.mode === "clip"
        triggeredOnStart: true
        onTriggered: root.refreshClip()
    }

    // The decoded copy of an image entry lives in the runtime dir, which is
    // RAM (tmpfs). clipDecode removes the previous one each time it writes the
    // next, so only the last one can be left behind: remove that too when the
    // selection is dropped, and at start-up (a crash or logout may have left one).
    function dropClipTemp() {
        Quickshell.execDetached(["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/tmp}\"/sekaipop-clip-*"])
    }

    Component.onCompleted: root.dropClipTemp()

    // Load the full text (or image) for the highlighted entry. `clipLoadedId` is the
    // entry whose full contents are in clipFull / clipImage now; until it matches the
    // pick, the card knows it is still waiting (and must not pass the short preview
    // off as the whole text). If nothing comes in time, `clipFailed` says so.
    property string clipLoadedId: ""
    property bool clipFailed: false
    property string clipError: ""          // what the decoder printed to stderr, for the card
    property var clipPending: null         // the pick waiting for the running decode to stop
    readonly property bool clipLoading: clipSelectedId !== "" && clipLoadedId !== clipSelectedId && !clipFailed

    // Latest pick wins. A Process that is still running ignores `running = true`
    // (setting it false only sends SIGTERM and the process is "running" until it has
    // really exited), so the old `running = false; running = true` pair silently
    // did nothing while a decode was in flight and the new pick never loaded.
    // Instead: remember the pick, stop the old decode, and start the new one from
    // onRunningChanged once the old one is gone.
    function startClipDecode() {
        const e = root.clipPending
        if (!e)
            return
        root.clipPending = null
        clipDecode.entry = e
        clipDecode.running = true
    }

    function clipDecodeEnded() {
        if (root.clipPending) {
            root.startClipDecode()
            return
        }
        // Nothing newer is waiting. If the pick still has not arrived, the decode
        // is over without an answer, so say so now instead of waiting for the timer.
        // (A late stdout answer still wins: it clears `clipFailed` itself.)
        if (root.clipSelectedId !== "" && root.clipLoadedId !== root.clipSelectedId)
            root.clipFailed = true
    }

    function selectClip(entry) {
        if (!entry) {
            if (root.clipImage !== "")
                root.dropClipTemp()
            root.clipSelectedId = ""
            root.clipLoadedId = ""
            root.clipFailed = false
            root.clipError = ""
            root.clipFull = ""
            root.clipImage = ""
            root.clipPending = null
            if (clipDecode.running)
                clipDecode.running = false
            clipGiveUp.stop()
            return
        }
        if (root.clipSelectedId === entry.id && (root.clipLoadedId === entry.id || root.clipLoading))
            return
        root.clipSelectedId = entry.id
        root.clipLoadedId = ""
        root.clipFailed = false
        root.clipError = ""
        root.clipFull = ""
        root.clipImage = ""
        root.clipPending = entry
        if (clipDecode.running)
            clipDecode.running = false      // onRunningChanged starts the pending pick
        else
            root.startClipDecode()
        clipGiveUp.restart()
    }

    Timer {
        id: clipGiveUp
        interval: 10000
        onTriggered: {
            if (root.clipSelectedId !== "" && root.clipLoadedId !== root.clipSelectedId)
                root.clipFailed = true
        }
    }

    // Decodes picture entry $1 into the runtime dir and prints the file's path. The
    // phone's picture view reads png / jpeg / gif / bmp; anything else the clipboard
    // may hold (webp, avif, tiff, ...) is turned into a png first when ImageMagick is
    // there, so the picture is not left blank.
    readonly property string clipImageScript: [
        'd="${XDG_RUNTIME_DIR:-/tmp}"; rm -f "$d"/sekaipop-clip-*; f="$d/sekaipop-clip-$1"',
        'cliphist decode "$1" > "$f" && [ -s "$f" ] || exit 1',
        't=$(file -b --mime-type "$f" 2>/dev/null)',
        'case "$t" in image/png|image/jpeg|image/gif|image/bmp) ;; *)',
        '  for c in magick convert; do',
        '    if command -v "$c" >/dev/null 2>&1 && "$c" "$f" "png:$f.png" 2>/dev/null && [ -s "$f.png" ]; then mv -f "$f.png" "$f"; break; fi',
        '  done;; esac',
        'rm -f "$f.png"',
        'printf %s "$f"'
    ].join("\n")

    // Every answer says which entry it is for (text: its id on the first line; image:
    // the id is in the file's name), and is only used while that entry is still the
    // pick. A decode that was stopped half way by the next pick can then never leave
    // its text (or a picture's path) in the wrong entry.
    Process {
        id: clipDecode
        property var entry: null
        command: entry === null ? ["true"]
            : entry.pinned ? ["sh", root.pinScript, "show", entry.pin]
            : (entry.image
                ? ["sh", "-c", clipImageScript, "sh", entry.id]
                : ["sh", "-c", "printf '%s\\n' \"$1\"; cliphist decode \"$1\"", "sh", entry.id])
        stdout: StdioCollector {
            onStreamFinished: {
                const sel = root.clipSelectedId
                if (sel === "")
                    return
                // text: "<id>\n<the entry exactly as it was copied>"
                const nl = text.indexOf("\n")
                if (nl > 0 && text.slice(0, nl) === sel) {
                    root.clipFull = text.slice(nl + 1)
                    root.clipLoadedId = sel
                    root.clipFailed = false
                    return
                }
                // picture: the path of the decoded file, which ends in this entry's id
                if (text.endsWith("/sekaipop-clip-" + sel)) {
                    root.clipImage = "file://" + text
                    root.clipLoadedId = sel
                    root.clipFailed = false
                }
            }
        }
        // The decoder's complaints (cliphist / magick), kept for the card, but only
        // while this decode is still for the pick.
        stderr: StdioCollector {
            onStreamFinished: {
                if (clipDecode.entry && clipDecode.entry.id === root.clipSelectedId)
                    root.clipError = text.trim()
            }
        }
        onRunningChanged: {
            if (!running)
                root.clipDecodeEnded()
        }
    }

    function copyClip(entry) {
        if (!entry)
            return
        if (entry.pinned) {
            Quickshell.execDetached(["sh", root.pinScript, "copy", entry.pin])
            return
        }
        if (entry.image) {
            // A picture goes back with its own type (png, jpeg...), found from the
            // file itself, so what you paste is the same picture.
            Quickshell.execDetached(["sh", "-c",
                "f=$(mktemp) && cliphist decode \"$1\" > \"$f\" && t=$(file -b --mime-type \"$f\" 2>/dev/null); "
                + "case \"$t\" in image/*) ;; *) t=image/png;; esac; wl-copy --type \"$t\" < \"$f\"; rm -f \"$f\"", "sh", entry.id])
            return
        }
        Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", entry.id])
    }

    // On a pin, Delete forgets the pin (the same as unpinning it): the card's
    // Delete always means "take this off the list".
    function deleteClip(entry) {
        if (!entry)
            return
        if (entry.pinned) {
            root.unpinClip(entry)
            return
        }
        // `cliphist delete` reads the list line (or just "<id>\t...") on stdin.
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "sh", entry.id])
        root.clipHistory = root.clipHistory.filter(e => e.id !== entry.id)
    }

    // ===== pinned clipboard entries =====
    readonly property string pinScript: Directories.script("state/clip-pins.sh")
    property string pinRaw: ""

    function refreshPins() {
        if (!pinList.running)
            pinList.running = true
    }

    Process {
        id: pinList
        command: ["sh", root.pinScript, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root.pinRaw)
                    return
                root.pinRaw = text
                root.clipPins = Pins.parsePinList(text)
            }
        }
    }

    // Pin and unpin write to disk, one at a time and in the order asked (a Process
    // that is still running ignores `running = true`, see startClipDecode), and the
    // list is read again after each.
    property var pinQueue: []

    function pinOp(args) {
        root.pinQueue = root.pinQueue.concat([args])
        if (!pinWrite.running)
            root.nextPinOp()
    }

    function nextPinOp() {
        if (root.pinQueue.length === 0) {
            root.refreshPins()
            return
        }
        pinWrite.args = root.pinQueue[0]
        root.pinQueue = root.pinQueue.slice(1)
        pinWrite.running = true
    }

    Process {
        id: pinWrite
        property var args: []
        command: ["sh", root.pinScript].concat(args)
        onRunningChanged: {
            if (!running)
                root.nextPinOp()
        }
    }

    function pinClip(entry) {
        if (!entry || entry.pinned)
            return
        root.pinOp(["pin", entry.id, entry.preview])
    }

    function unpinClip(entry) {
        if (!entry || !entry.pinned)
            return
        // Gone from the card at once; the list read after the write agrees.
        root.clipPins = root.clipPins.filter(e => e.id !== entry.id)
        root.pinOp(["unpin", entry.pin])
    }

    function togglePin(entry) {
        if (!entry)
            return
        if (entry.pinned)
            root.unpinClip(entry)
        else
            root.pinClip(entry)
    }

    // ===== recent emoji =====
    property var recentEmoji: []

    readonly property string stateScript: Directories.script("state/extras-state.sh")

    Process {
        running: true
        command: ["sh", root.stateScript, "load-emoji"]
        stdout: StdioCollector {
            onStreamFinished: root.recentEmoji = text.split("\n").filter(l => l.length > 0).slice(0, 32)
        }
    }

    function rememberEmoji(ch) {
        const next = [ch].concat(root.recentEmoji.filter(e => e !== ch)).slice(0, 32)
        root.recentEmoji = next
        Quickshell.execDetached(["sh", root.stateScript, "save-emoji"].concat(next))
    }

    // ===== eyedropper =====
    signal colorPicked(string hex)

    function pickColor() {
        picker.running = false
        picker.running = true
    }

    Process {
        id: picker
        command: ["sh", "-c", "sleep 0.4; exec hyprpicker --format=hex"]
        stdout: StdioCollector {
            onStreamFinished: {
                const hex = text.trim()
                if (/^#[0-9a-fA-F]{6}$/.test(hex))
                    root.colorPicked(hex)
            }
        }
    }
}
