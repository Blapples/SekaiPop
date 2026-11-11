pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// The shell's colours on other apps: terminals (kitty, foot), VS Code, the
// launcher (fuzzel and rofi), the fish prompt and Hyprland's own window borders. Each has its own switch (Settings -> Desktop ->
// App colours) and its own Revert, which takes everything it added away again.
// The work is scripts/theming/app-theme.sh (its header lists exactly what is written
// where); this file turns the active theme into the colours it needs and keeps
// them up to date while a switch is on:
//
//   - the theme, the light / dark mode or the wallpaper (matugen) changes ->
//     every switched-on app gets the new colours (a moment later, so a burst of
//     changes is one run);
//   - a switch turned on applies now; turned off, it reverts now.
//
// This is separate from the GTK / Qt / KDE colours (ThemeService's "system"
// part): those are written for every toolkit app; this is for apps that have
// their own colour settings.
//
//   qs -c sekaipop ipc call apptheme apply kitty|foot|vscode|fish|prompt|launcher|hyprland|all
//   qs -c sekaipop ipc call apptheme revert kitty|foot|vscode|fish|prompt|launcher|hyprland|all
//   qs -c sekaipop ipc call apptheme status
Singleton {
    id: root

    // Read once from shell.qml so this singleton exists from the first moment of every
    // shell start (Quickshell only creates a singleton when something reads it).
    readonly property bool ready: true

    // The theme the apps should get is known: the saved settings and the saved theme are
    // read and, for the matugen theme, matugen's colours are there. Until then the palette
    // is the built-in default, and copying THAT out would repaint the terminal and the
    // prompt in the default colours (the "matugen turned off" after a restart). While it is
    // false nothing is applied, so the apps simply keep the colours they already have.
    readonly property bool settled: SettingsService.loaded
        && (ThemeService.themeLoaded || ThemeService.touched)
        && !(ThemeService.current === "matugen" && ThemeService.matugenPalette === null)

    // What the switches are called, what each one does, and which script targets
    // it covers. Most use the saved "appTheme.<id>" switch; statusDriven targets
    // use their installed hook instead. Their syncAction never enables a missing hook,
    // and enableAction can install it before the shell's palette has settled.
    readonly property var targets: [
        { id: "kitty", label: "kitty", icon: "terminal", scripts: ["kitty"],
          statusDriven: true, syncAction: "sync", enableAction: "enable",
          installedStates: ["on", "blocked", "pending"],
          note: "Open windows recolour at once" },
        { id: "foot", label: "foot", icon: "terminal", scripts: ["foot"],
          note: "New windows (foot never re-reads its config)" },
        { id: "vscode", label: "VS Code", icon: "code", scripts: ["vscode"],
          note: "Code, Code - OSS, VSCodium · live" },
        { id: "fish", label: "fish", icon: "terminal", scripts: ["fish"],
          note: "Open shells and terminals recolour at once" },
        { id: "prompt", label: "Terminal prompt", icon: "terminal", scripts: ["prompt"],
          note: "Outlined sticker plates with a hard shadow · fish, new shells · needs a Nerd Font" },
        { id: "launcher", label: "Launcher", icon: "apps", scripts: ["fuzzel", "rofi"],
          note: "fuzzel and rofi" },
        { id: "hyprland", label: "Window borders", icon: "border_style", scripts: ["hyprland"],
          note: "Hyprland's active and inactive borders · live" }
    ]

    function target(id) {
        return root.targets.find(t => t.id === id) || null
    }

    function enabled(id) {
        const t = root.target(id)
        if (!t)
            return false
        if (t.statusDriven)
            return t.scripts.some(s => (t.installedStates || ["on"]).includes(root.status[s]))
        return SettingsService.flag("appTheme." + id)
    }

    // ===== the colours =====
    function mix(a, b, t) {
        const x = Qt.color(a), y = Qt.color(b)
        return Qt.rgba(x.r * (1 - t) + y.r * t, x.g * (1 - t) + y.g * t, x.b * (1 - t) + y.b * t, 1)
    }

    function hex(c) {
        return Qt.color(c).toString()
    }

    // key=#rrggbb for script, from the active palette. Dark and Darker get a dark
    // terminal in the theme's own tint; Light gets a pale one with deeper accents.
    function colours() {
        const p = ThemeService.palette
        const dark = ThemeService.dark
        const darker = ThemeService.darker
        const border = Qt.color(p.border)
        const bg = dark ? (darker ? Qt.darker(Qt.color(p.deep), 1.4) : Qt.color(p.deep))
                        : Qt.color(p.boardBg)
        const fg = dark ? Qt.color(p.divider) : border
        const accent = dark ? Qt.color(p.A) : Qt.color(p.wallMid || p.border)
        const accent2 = dark ? Qt.color(p.B) : Qt.darker(Qt.color(p.B), 1.9)
        const surface = dark ? Qt.lighter(bg, 1.25) : Qt.darker(bg, 1.05)
        const hover = dark ? Qt.lighter(bg, 1.6) : Qt.color(p.boardDot)
        const muted = root.mix(fg, bg, 0.45)
        const selbg = dark ? root.mix(bg, accent, 0.34) : root.mix(bg, accent, 0.28)

        // Terminal colours: the theme's own accents for green / blue / magenta /
        // cyan, fixed readable ones for red and yellow.
        const c = []
        if (dark) {
            c[0] = Qt.lighter(bg, 1.7)
            c[1] = Qt.color("#ff6f91")
            c[2] = accent2
            c[3] = Qt.color("#ffd166")
            c[4] = accent
            c[5] = p.mono === true ? root.mix(accent, accent2, 0.5) : root.mix(accent, "#ff75ac", 0.55)
            c[6] = p.mono === true ? accent2 : root.mix(accent2, "#4fd6e8", 0.45)
            c[7] = fg
            for (let i = 0; i < 8; i++)
                c[8 + i] = i === 0 ? Qt.lighter(c[0], 1.7) : (i === 7 ? root.mix(fg, "#ffffff", 0.6) : Qt.lighter(c[i], 1.18))
        } else {
            c[0] = border
            c[1] = Qt.color("#c2305a")
            c[2] = root.mix("#2f8f5b", accent2, 0.25)
            c[3] = Qt.color("#a8780a")
            c[4] = accent
            c[5] = p.mono === true ? root.mix(accent, border, 0.5) : root.mix(accent, "#a2408f", 0.5)
            c[6] = p.mono === true ? accent : root.mix("#1f8a9a", accent, 0.2)
            c[7] = root.mix(border, bg, 0.35)
            for (let i = 0; i < 8; i++)
                c[8 + i] = i === 0 ? root.mix(border, bg, 0.3) : (i === 7 ? Qt.darker(bg, 1.12) : Qt.lighter(c[i], 1.2))
        }

        // Hyprland's window borders (the "hyprland" target). Borders are thin, so
        // the theme's pastel accent is pushed to a stronger colour of the same
        // hue; the inactive one is the same hue, darker, instead of the grey
        // mix of text and background that `muted` is.
        const strong = (c, k, vmin) => {
            const q = Qt.color(c)
            if (q.hsvHue < 0)
                return q
            return Qt.hsva(q.hsvHue, Math.min(1, q.hsvSaturation * k), Math.max(q.hsvValue, vmin), 1)
        }
        const hlActive = dark ? strong(accent, 1.3, 0.9) : strong(accent, 1.25, 0.55)
        const hlInactive = dark ? strong(root.mix(accent, bg, 0.62), 1.45, 0.3)
                                : strong(root.mix(accent, bg, 0.6), 1.2, 0.6)

        // The fish prompt's pills (the "prompt" target): a container tone between the
        // background and the second accent, and the hard shadow under it, which like the
        // bar's is the theme's border colour pulled toward the background (visible on it).
        const pill = root.mix(bg, accent2, dark ? 0.40 : 0.30)
        const shadow = root.mix(bg, border, dark ? 0.55 : 0.40)

        // The terminal prompt's sticker plates (the "prompt" target): the theme's two bright
        // accents as plate fills (in light mode too, where `accent` is the muted mid-tone),
        // a white-ish "paper" plate, dark ink on all of them, and the outline: white in
        // Dark, the theme's navy in Darker and Light, like the shell's own outlines.
        const ptA = Qt.color(p.A)
        const ptB = Qt.color(p.B)
        const ptInk = Qt.color(p.deep)
        const ptFail = dark ? Qt.color("#ff6f91") : Qt.color("#ff7f9d")
        const ptPaper = dark ? Qt.color(p.divider) : Qt.color("#ffffff")
        const ptLine = (dark && !darker) ? Qt.color(p.divider) : border

        const out = [
            "ptA=" + hex(ptA), "ptB=" + hex(ptB), "ptInk=" + hex(ptInk),
            "ptPaper=" + hex(ptPaper), "ptLine=" + hex(ptLine), "ptFail=" + hex(ptFail),
            "hlactive=" + hex(hlActive), "hlinactive=" + hex(hlInactive),
            "pill=" + hex(pill), "onpill=" + hex(fg), "shadow=" + hex(shadow),
            "bg=" + hex(bg), "fg=" + hex(fg), "cursor=" + hex(accent),
            "selbg=" + hex(selbg), "selfg=" + hex(fg),
            "accent=" + hex(accent), "accent2=" + hex(accent2),
            "border=" + hex(border), "surface=" + hex(surface),
            "hover=" + hex(hover), "muted=" + hex(muted)
        ]
        for (let i = 0; i < 16; i++)
            out.push("c" + i + "=" + hex(c[i]))
        return out
    }

    // ===== running the script =====
    readonly property string script: Directories.script("theming/app-theme.sh")

    property var queue: []

    function enqueue(args) {
        root.queue = root.queue.concat([args])
        root.pump()
    }

    function pump() {
        if (runner.running || root.queue.length === 0)
            return
        const next = root.queue[0]
        root.queue = root.queue.slice(1)
        runner.job = next
        runner.exec(["sh", root.script].concat(next))
    }

    // Background sync must not replace or dismiss a failed explicit operation.
    // Installation and sync health come from status, not these operation records.
    property var failures: ({})

    function jobFinished(args, exitCode) {
        const action = args[0], script = args[1]
        const t = root.targets.find(t => t.statusDriven && t.scripts.includes(script))
        if (!t)
            return
        const previous = root.failures[script]
        if (action === t.syncAction && previous && previous.action !== t.syncAction)
            return
        const next = Object.assign({}, root.failures)
        if (exitCode !== 0)
            next[script] = { action: action }
        else
            delete next[script]
        root.failures = next
    }

    Process {
        id: runner
        property var job: []
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.log("[AppThemeService]", text.trim())
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.log("[AppThemeService]", text.trim())
            }
        }
        onExited: exitCode => {
            root.jobFinished(runner.job, exitCode)
            root.refreshStatus()
            root.pump()
        }
    }

    function applyScripts(scripts, action = "apply") {
        const col = root.colours()
        for (const s of scripts)
            root.enqueue([action, s].concat(col))
    }

    function revertScripts(scripts) {
        for (const s of scripts)
            root.enqueue(["revert", s])
    }

    // The switch: on applies now, off reverts now.
    function setEnabled(id, on) {
        const t = root.target(id)
        if (!t)
            return
        if (!t.statusDriven)
            SettingsService.set("appTheme." + id, on)
        if (on && t.enableAction && !root.settled) {
            for (const s of t.scripts)
                root.enqueue([t.enableAction, s])
        } else if (on)
            root.applyScripts(t.scripts, t.enableAction || "apply")
        else
            root.revertScripts(t.scripts)
    }

    // Revert: switch it off AND take its block out, even when the switch was
    // already off (a block left by an earlier run).
    function revert(id) {
        root.setEnabled(id, false)
    }

    function applyEnabled() {
        if (!root.settled)
            return
        for (const t of root.targets)
            if (t.statusDriven || root.enabled(t.id))
                root.applyScripts(t.scripts, t.syncAction || "apply")
    }

    // ===== keeping up with the theme =====
    Timer {
        id: debounce
        interval: 1200
        onTriggered: root.applyEnabled()
    }

    Connections {
        target: ThemeService
        function onThemeLoadedChanged() { debounce.restart() }
        function onPaletteChanged() { debounce.restart() }
        function onDarkChanged() { debounce.restart() }
        function onDarkerChanged() { debounce.restart() }
    }

    // After the settings are read (so the switches are known) and the palette has
    // settled at startup.
    Connections {
        target: SettingsService
        function onLoadedChanged() { debounce.restart() }
    }

    // ===== what is set up =====
    property var status: ({})

    function refreshStatus() {
        if (statusProc.running)
            statusProc.pending = true
        else {
            statusProc.failuresAtStart = root.failures
            statusProc.exec(["sh", root.script, "status"])
        }
    }

    function acceptStatus(st, failuresAtStart) {
        root.status = st
        const next = Object.assign({}, root.failures)
        for (const t of root.targets) {
            if (!t.statusDriven)
                continue
            for (const s of t.scripts) {
                const failure = next[s]
                // Config trouble is already represented by status, not a second
                // remembered error. Keep unknown IO failures while on/pending, and
                // explicit action failures until retried. Ignore older responses.
                if (failure && failure === failuresAtStart[s] && failure.action === t.syncAction
                        && ["blocked", "conflict", "off", "missing"].includes(st[s]))
                    delete next[s]
            }
        }
        root.failures = next
    }

    // The state of one switch's apps, for the Settings detail line:
    // "applied", "not installed", "conflict", "pending" or "off".
    function stateOf(id) {
        const t = root.target(id)
        if (!t)
            return ""
        let on = 0, missing = 0, pending = 0
        for (const s of t.scripts) {
            const v = root.status[s]
            if (root.failures[s] || v === "conflict" || v === "blocked")
                return "conflict"
            if (v === "on") on++
            else if (v === "pending") pending++
            else if (v === "missing") missing++
        }
        if (pending > 0)
            return "pending"
        if (on > 0)
            return "applied"
        if (missing === t.scripts.length)
            return "not installed"
        return "off"
    }

    Process {
        id: statusProc
        property bool pending: false
        property var failuresAtStart: ({})
        onExited: {
            if (pending) {
                pending = false
                root.refreshStatus()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const st = {}
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0)
                        st[line.slice(0, i)] = line.slice(i + 1).trim()
                }
                root.acceptStatus(st, statusProc.failuresAtStart)
            }
        }
    }

    Component.onCompleted: {
        root.refreshStatus()
        debounce.restart()
    }

    IpcHandler {
        target: "apptheme"

        function kittyProtocol(): string {
            return "enable-only"
        }

        function apply(id: string): void {
            const list = id === "all" ? root.targets : [root.target(id)].filter(t => t)
            for (const t of list)
                root.setEnabled(t.id, true)
        }

        function revert(id: string): void {
            const list = id === "all" ? root.targets : [root.target(id)].filter(t => t)
            for (const t of list)
                root.revert(t.id)
        }

        function syncKitty(): void {
            const t = root.target("kitty")
            if (root.settled)
                root.applyScripts(t.scripts, t.syncAction)
            else
                root.refreshStatus()
        }

        function status(): string {
            return JSON.stringify(root.status)
        }
    }
}
