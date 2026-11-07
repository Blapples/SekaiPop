.pragma library

// The rules of Desktop Focus Mode (services/FocusService.qml draws nothing and
// asks nothing of Hyprland by itself; it collects the facts and hands them to
// compute() below). Pure functions on plain objects, so they can be unit-tested
// with node: tests/focus-test/focus_unit.js.
//
// A "window" is what FocusService reads off Quickshell's Hyprland models:
//
//   { address, workspaceId, monitor, floating, mapped, hidden, pinned,
//     fullscreen, cls, known }
//
//   workspaceId  Hyprland's workspace id (negative for special workspaces)
//   monitor      the name of the monitor that workspace is on ("DP-1")
//   floating     true / false, or undefined while `hyprctl clients` has not been
//                read for this window yet (then `known` is false)
//   fullscreen   0 / 1 / 2 (or a boolean)
//   cls          the window class, for the shell's own windows (see `shellClasses`)
//
// A "monitor" is { name, workspaceId, specialId }: its active workspace, and the
// special workspace (scratchpad) shown over it right now, 0 when there is none.
//
// What counts as being "in the way" on a monitor:
//
//   - a window on the monitor's active workspace, or on the special workspace
//     shown over it, or a pinned floating window that sits on this monitor
//   - not a window that is not mapped or hidden (a minimised one lives on the
//     dock's hidden special workspace, which is never shown, so it is skipped
//     by the first rule already)
//   - not one of the shell's own windows (shellClasses)
//   - a window whose floating state is not known yet is skipped for the moment:
//     counting it either way would make the widgets flinch for a floating dialog
//     (or lag for a tiled window); FocusService asks Hyprland and recomputes the
//     instant the answer is in.
//
// A fullscreen / maximised window counts as TILED even when it is a floating one:
// it takes the whole workspace, whatever it was before.

// Windows that belong to the shell itself. Layer-shell surfaces (the bar, the
// panels, the notification popups ...) are not Hyprland clients at all, so this
// is only for a toplevel the shell might one day map (a FloatingWindow).
var SHELL_CLASSES = ["quickshell", "org.quickshell", "sekaipop"]

function isShell(cls, shellClasses) {
    if (typeof cls !== "string" || cls === "")
        return false
    var lower = cls.toLowerCase()
    var list = shellClasses || SHELL_CLASSES
    for (var i = 0; i < list.length; i++) {
        if (lower === String(list[i]).toLowerCase())
            return true
    }
    return false
}

function isFullscreen(w) {
    if (w.fullscreen === true)
        return true
    return typeof w.fullscreen === "number" && w.fullscreen > 0
}

// What one window counts as on a monitor: "tiled", "floating" or "" (nothing).
function kindOf(w, mon, shellClasses) {
    if (!w || !mon)
        return ""
    if (w.mapped === false || w.hidden === true)
        return ""
    if (isShell(w.cls, shellClasses))
        return ""
    if (w.known === false)
        return ""

    // 0 means "not known" on either side; two unknowns are not the same workspace.
    var here = !!mon.workspaceId && w.workspaceId === mon.workspaceId
    if (!here && mon.specialId && w.workspaceId === mon.specialId)
        here = true
    // A pinned window follows you from workspace to workspace on its monitor.
    if (!here && w.pinned === true && w.monitor === mon.name)
        here = true
    if (!here)
        return ""

    if (isFullscreen(w))
        return "tiled"
    return w.floating === true ? "floating" : "tiled"
}

// Counts per monitor: { "DP-1": { tiled, floating, workspaceId } }.
function census(windows, monitors, shellClasses) {
    var out = {}
    var mons = monitors || []
    var wins = windows || []
    for (var m = 0; m < mons.length; m++) {
        var mon = mons[m]
        if (!mon || typeof mon.name !== "string" || mon.name === "")
            continue
        var c = { tiled: 0, floating: 0, workspaceId: mon.workspaceId }
        for (var i = 0; i < wins.length; i++) {
            var k = kindOf(wins[i], mon, shellClasses)
            if (k === "tiled")
                c.tiled++
            else if (k === "floating")
                c.floating++
        }
        out[mon.name] = c
    }
    return out
}

// The decision for one monitor.
//   opts: { enabled, hideTiled, hideFloating }
// Tiled and floating together hide when EITHER rule says so; "tiled + floating"
// is hidden under the defaults because of the tiled window, not because of the
// floating one.
function hides(count, opts) {
    if (!opts || !opts.enabled || !count)
        return false
    if (opts.hideTiled && count.tiled > 0)
        return true
    if (opts.hideFloating && count.floating > 0)
        return true
    return false
}

// Everything FocusService publishes, per monitor name:
//   hidden  the desktop widgets should go
//   busy    any window is on the monitor (what "reduce effects" looks at; it
//           does not depend on the hide rules)
function compute(windows, monitors, opts, shellClasses) {
    var counts = census(windows, monitors, shellClasses)
    var out = {}
    for (var name in counts) {
        var c = counts[name]
        out[name] = {
            hidden: hides(c, opts),
            busy: c.tiled + c.floating > 0,
            tiled: c.tiled,
            floating: c.floating,
            workspaceId: c.workspaceId
        }
    }
    return out
}

// Two results the same? Used so nothing downstream re-evaluates (and no widget
// gets a signal) when a Hyprland event changed nothing that matters here.
function same(a, b) {
    var ka = Object.keys(a || {})
    var kb = Object.keys(b || {})
    if (ka.length !== kb.length)
        return false
    for (var i = 0; i < ka.length; i++) {
        var k = ka[i]
        var x = a[k]
        var y = b[k]
        if (!y || x.hidden !== y.hidden || x.busy !== y.busy)
            return false
    }
    return true
}

// Which of the desktop widgets wakes up after which, so coming back to the
// desktop does not start every widget's clock, fetch and first frame in the same
// frame. Index = position in the sequence; one step is STAGGER_MS.
var STAGGER_MS = 70
var SLOTS = { clock: 0, usercard: 1, weathercard: 2, todo: 3, visualizer: 4, image: 5, notes: 6, calendarcard: 7, palettecard: 8, lyrics: 9, watertank: 10, downloader: 11 }

function slotDelay(id) {
    var s = SLOTS[id]
    return typeof s === "number" ? s * STAGGER_MS : 0
}

// Hide at once, show again only after the answer has stayed "visible" for a
// moment: a window that closes and another that opens straight after (a tab
// moving, a dialog replaced) must not make the widgets pop out and in. Returns
// what to publish for each monitor, given what is published now (`shown`), what
// was just computed (`next`) and whether the settle time has elapsed.
//   a monitor that should hide        -> published at once
//   a monitor that may come back      -> published only when `settled`
function publish(shown, next, settled) {
    var out = {}
    for (var name in next) {
        var n = next[name]
        var old = shown ? shown[name] : null
        if (old && old.hidden && !n.hidden && !settled)
            out[name] = { hidden: true, busy: n.busy, tiled: n.tiled, floating: n.floating, workspaceId: n.workspaceId }
        else
            out[name] = n
    }
    return out
}

// True while `publish` is still holding a monitor back (so FocusService knows to
// run the settle timer).
function holding(shown, next) {
    for (var name in next) {
        var old = shown ? shown[name] : null
        if (old && old.hidden && !next[name].hidden)
            return true
    }
    return false
}
