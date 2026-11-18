pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/common/functions/DisplayMath.js" as DM
import "../modules/common/functions/HyprmonMath.js" as HM

// The Displays card's brain (Settings > Hyprland). Reads the screens from Hyprland,
// keeps a draft of what you are changing, applies it live, and asks "keep these?"
// with a countdown: if you do not answer (a black screen, say) it goes back by
// itself. Only "Keep" writes ~/.config/hypr/monitors.lua, the file nwg-displays
// writes and hyprland.lua loads (scripts/hyprland/displays.sh does the work).
//
// With hyprmon as the display handler (`hyprmon`, Settings' "Display handler") the
// card does the same, plus hyprmon's own settings (rotation, VRR, colour depth and
// mode, HDR levels, mirroring), and "Keep" saves the screens into a hyprmon profile
// (`saveTarget`) instead of monitors.lua (services/HyprmonService.qml).
//
//     DisplayService.setScale("HDMI-A-1", "1.25")
//     DisplayService.apply()          // shows it, starts the countdown
//     DisplayService.keep()           // saves
//
// The maths (modes, scale, where each screen sits) is modules/common/functions/DisplayMath.js.
Singleton {
    id: root

    // What Hyprland has now: [{ name, desc, on, w, h, hz, x, y, scale, transform, modes,
    // make, model, serial, bitDepth, cm, sdrBrightness, sdrSaturation, vrr, mirror }].
    property var live: []
    // What is being edited: [{ name, desc, on, modeId, scale, place, x, y, transform, modes,
    // make, model, serial, bitDepth, cm, sdrBrightness, sdrSaturation, vrr, mirror }].
    // x, y is where the screen sits in the layout (logical px); `place` is only which side
    // of the main screen that is, for the Left / Right / Above / Below keys.
    property var draft: []
    // The screen at the origin; the Placed keys put the others next to it.
    property string mainName: ""
    // The screens' names, replaced only when the set of screens changes, so the cards
    // are not rebuilt on every click.
    property var names: []
    property bool dirty: false

    // After Apply: the countdown to "keep these?".
    property bool confirming: false
    property int secondsLeft: 0
    readonly property int confirmSeconds: 15
    property var previous: []

    readonly property var scales: DM.SCALES
    readonly property int enabledCount: root.draft.filter(d => d.on).length
    readonly property var enabledNames: root.draft.filter(d => d.on).map(d => d.name)

    readonly property string script: Directories.script("hyprland/displays.sh")

    // hyprmon is the display handler: hyprmon's settings are shown and sent, and Keep
    // saves to the profile `saveTarget` ("" = keep for this session only).
    readonly property bool hyprmon: HyprmonService.on
    property string saveTarget: ""

    // ===== reading =====
    function refresh() {
        if (!reader.running)
            reader.running = true
    }

    Process {
        id: reader
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed
                try {
                    parsed = JSON.parse(text)
                } catch (e) {
                    console.warn("DisplayService: couldn't read `hyprctl -j monitors all`")
                    return
                }
                root.live = parsed.map(m => ({
                    name: String(m.name),
                    desc: String(m.description || ""),
                    on: m.disabled !== true,
                    w: m.width | 0,
                    h: m.height | 0,
                    hz: Number(m.refreshRate) || 0,
                    x: m.x | 0,
                    y: m.y | 0,
                    scale: Number(m.scale) || 1,
                    transform: m.transform | 0,
                    modes: DM.parseModes(m.availableModes || []),
                    make: String(m.make || ""),
                    model: String(m.model || ""),
                    serial: String(m.serial || ""),
                    bitDepth: HM.bitDepthOf(m.currentFormat),
                    cm: String(m.colorManagementPreset || "srgb"),
                    sdrBrightness: Number(m.sdrBrightness) || 1,
                    sdrSaturation: Number(m.sdrSaturation) || 1,
                    vrr: m.vrr === true ? 1 : 0,
                    mirror: m.mirrorOf && m.mirrorOf !== "none" ? String(m.mirrorOf) : ""
                }))
                // Never replace what you are in the middle of changing.
                if (!root.dirty && !root.confirming)
                    root.resetDraft()
            }
        }
    }

    // While the card is on screen something keeps it fresh (see SettingsPageHyprland).
    function resetDraft() {
        const L = root.live
        const main = L.find(m => m.on && m.x === 0 && m.y === 0) || L.find(m => m.on)
        const msz = main ? DM.logicalSize(main.w, main.h, main.scale, main.transform) : { w: 0, h: 0 }
        // An off screen has no place yet: it goes to the right of the screens that are on.
        let edge = 0
        L.forEach(m => {
            if (m.on)
                edge = Math.max(edge, m.x + DM.logicalSize(m.w, m.h, m.scale, m.transform).w)
        })
        // Hyprland only says whether VRR is on; the profile in use says "fullscreen only".
        const prof = root.hyprmon ? HyprmonService.profile(HyprmonService.active) : null
        const ids = HM.hardwareIds(L)
        const next = L.map(m => {
            const sz = DM.logicalSize(m.w, m.h, m.scale, m.transform)
            const pm = prof ? HM.findMonitor(prof, ids[m.name], m.name) : null
            return {
                name: m.name,
                desc: m.desc,
                on: m.on,
                modeId: DM.matchMode(m.modes, m.w, m.h, m.hz),
                scale: Math.round(m.scale * 100) / 100,
                place: main && m.on && m.name !== main.name ? DM.placeOf(m.x - main.x, m.y - main.y, sz.w, sz.h, msz.w, msz.h) : "right",
                x: m.on ? m.x : Math.round(edge),
                y: m.on ? m.y : 0,
                transform: m.transform,
                modes: m.modes,
                make: m.make || "",
                model: m.model || "",
                serial: m.serial || "",
                bitDepth: m.bitDepth || 8,
                cm: m.cm || "srgb",
                sdrBrightness: m.sdrBrightness || 1,
                sdrSaturation: m.sdrSaturation || 1,
                vrr: m.vrr && pm && pm.VRR === 2 ? 2 : (m.vrr | 0),
                mirror: m.mirror || ""
            }
        })
        // Only when something really differs: the controls are rebuilt by a new list,
        // and this runs every few seconds while the page is open.
        if (JSON.stringify(next) !== JSON.stringify(root.draft))
            root.draft = next
        root.mainName = main ? main.name : ""
        root.dirty = false
        const nameList = L.map(m => m.name)
        if (nameList.join("|") !== root.names.join("|"))
            root.names = nameList
    }

    // ===== editing =====
    function item(name) {
        return root.draft.find(d => d.name === name) || null
    }

    function edit(name, change) {
        root.draft = root.draft.map(d => d.name === name ? Object.assign({}, d, change) : d)
        root.dirty = true
    }

    // The size a draft screen takes in the layout, rounded UP to whole pixels: at 175 %
    // a 1920 px screen is 1097.14 wide, and a neighbour placed at 1097 would sit on top of
    // it, which Hyprland reports as "monitor layout is set up incorrectly". Rounding up
    // leaves a gap under a pixel instead.
    function sizeOf(d) {
        const mode = DM.modeById(d.modes, d.modeId)
        const sz = DM.logicalSize(mode ? mode.w : 0, mode ? mode.h : 0, d.scale, d.transform)
        return { w: Math.ceil(sz.w - 1e-6), h: Math.ceil(sz.h - 1e-6) }
    }

    // The screens that are on, as layout rectangles: [{ name, x, y, w, h }]. A mirrored
    // screen shows another one's picture and takes no room of its own.
    function rects() {
        return root.draft.filter(d => d.on && !d.mirror).map(d => {
            const sz = root.sizeOf(d)
            return { name: d.name, x: d.x, y: d.y, w: sz.w, h: sz.h }
        })
    }

    // After any move: slide the screens that are on so the smallest x and y are 0, and
    // work out again which side of the main screen each one is on.
    function settle() {
        const pos = {}
        root.rects().forEach(r => { pos[r.name] = [r.x, r.y] })
        const norm = DM.normalize(pos)
        const rs = root.rects()
        const main = rs.find(r => r.name === root.mainName)
        root.draft = root.draft.map(d => {
            if (!d.on || !norm[d.name])
                return d
            const r = rs.find(q => q.name === d.name)
            const place = main && r && d.name !== root.mainName
                ? DM.placeOf(norm[d.name][0] - (norm[root.mainName] ? norm[root.mainName][0] : 0),
                             norm[d.name][1] - (norm[root.mainName] ? norm[root.mainName][1] : 0),
                             r.w, r.h, main.w, main.h)
                : d.place
            return Object.assign({}, d, { x: norm[d.name][0], y: norm[d.name][1], place: place })
        })
    }

    // A screen changed size: the ones past it move by the difference.
    function resized(name, oldSize) {
        const moved = DM.reflow(root.rects(), name, oldSize.w, oldSize.h)
        root.draft = root.draft.map(d => {
            const r = moved.find(q => q.name === d.name)
            return d.on && r && r.name !== name ? Object.assign({}, d, { x: r.x, y: r.y }) : d
        })
        root.settle()
    }

    function setOn(name, on) {
        const d = root.item(name)
        if (!d || d.on === on)
            return
        // Never turn the last screen off.
        if (!on && root.enabledCount <= 1)
            return
        if (on) {
            // It joins on the right of the screens that are on, level with the top.
            let edge = 0
            root.rects().forEach(r => { edge = Math.max(edge, r.x + r.w) })
            root.edit(name, { on: true, x: Math.round(edge), y: 0 })
        } else {
            root.edit(name, { on: false, mirror: "" })
            // Screens that showed this one's picture get their own again.
            root.draft.filter(x => x.mirror === name).forEach(x => {
                let edge = 0
                root.rects().forEach(r => { edge = Math.max(edge, r.x + r.w) })
                root.edit(x.name, { mirror: "", x: Math.round(edge), y: 0 })
            })
        }
        if (!on && root.mainName === name) {
            const other = root.draft.find(x => x.on && x.name !== name)
            root.mainName = other ? other.name : ""
        } else if (on && root.mainName === "") {
            root.mainName = name
        }
        root.settle()
    }

    function setMain(name) {
        if (root.mainName === name)
            return
        root.mainName = name
        root.dirty = true
        root.settle()
    }

    function setResolution(name, res) {
        const d = root.item(name)
        if (!d)
            return
        const cur = DM.modeById(d.modes, d.modeId)
        const id = DM.modeForRes(d.modes, res, cur ? cur.hz : 60)
        if (id !== "") {
            const before = root.sizeOf(d)
            root.edit(name, { modeId: id })
            root.resized(name, before)
        }
    }

    function setMode(name, modeId) {
        const d = root.item(name)
        if (!d)
            return
        const before = root.sizeOf(d)
        root.edit(name, { modeId: modeId })
        root.resized(name, before)
    }

    function setScale(name, s) {
        const d = root.item(name)
        if (!d)
            return
        const before = root.sizeOf(d)
        root.edit(name, { scale: Number(s) })
        root.resized(name, before)
    }

    // Put a screen at a place in the layout (what dragging it does). It is slid off
    // any screen it would sit on; the layout is then moved so it starts at 0, 0.
    function setPosition(name, x, y) {
        const d = root.item(name)
        if (!d || !d.on)
            return
        const sz = root.sizeOf(d)
        const others = root.rects().filter(r => r.name !== name)
        const at = DM.separate({ x: Math.round(x), y: Math.round(y), w: sz.w, h: sz.h }, others)
        root.edit(name, { x: Math.round(at.x), y: Math.round(at.y) })
        root.settle()
    }

    // The Left / Right / Above / Below keys: flush against the main screen.
    function setPlace(name, place) {
        const d = root.item(name)
        const main = root.rects().find(r => r.name === root.mainName)
        if (!d || !d.on || !main || name === root.mainName)
            return
        const sz = root.sizeOf(d)
        const others = root.rects().filter(r => r.name !== name && r.name !== root.mainName)
        const at = DM.dock({ w: sz.w, h: sz.h }, main, place, others)
        root.edit(name, { x: Math.round(at.x), y: Math.round(at.y), place: place })
        root.settle()
    }

    // ===== hyprmon's settings (shown with hyprmon as the handler) =====
    // Rotation and flips, Hyprland's transform 0..7: turning a screen on its side
    // changes the room it takes, like a new mode does.
    function setTransform(name, t) {
        const d = root.item(name)
        const v = Number(t) | 0
        if (!d || v < 0 || v > 7 || d.transform === v)
            return
        const before = root.sizeOf(d)
        root.edit(name, { transform: v })
        root.resized(name, before)
    }

    // 0 off, 1 on, 2 only for fullscreen windows.
    function setVrr(name, v) {
        const n = Number(v) | 0
        if (root.item(name) && n >= 0 && n <= 2)
            root.edit(name, { vrr: n })
    }

    function setBitDepth(name, bits) {
        const n = Number(bits) | 0
        if (root.item(name) && (n === 8 || n === 10))
            root.edit(name, { bitDepth: n })
    }

    function setColorMode(name, cm) {
        if (root.item(name) && HM.COLOR_MODES.indexOf(cm) >= 0)
            root.edit(name, { cm: cm })
    }

    // HDR only: how bright and how saturated SDR content is drawn (1 = as is).
    function setSdr(name, which, v) {
        const n = Math.round(Number(v) * 100) / 100
        if (!root.item(name) || !(n > 0) || n > 3)
            return
        root.edit(name, which === "saturation" ? { sdrSaturation: n } : { sdrBrightness: n })
    }

    // Show another screen's picture ("" = its own again). A circle (A mirrors B mirrors
    // A) is refused; returns whether it was taken. A screen that stops mirroring joins on
    // the right of the others, as one that is switched on does.
    function setMirror(name, source) {
        const d = root.item(name)
        const src = source || ""
        if (!d || d.mirror === src)
            return true
        if (src !== "" && (HM.mirrorLoops(root.draft, name, src) || !root.item(src) || !root.item(src).on))
            return false
        if (src === "") {
            let edge = 0
            root.rects().forEach(r => { edge = Math.max(edge, r.x + r.w) })
            root.edit(name, { mirror: "", x: Math.round(edge), y: 0 })
        } else {
            root.edit(name, { mirror: src })
            if (root.mainName === name) {
                const other = root.draft.find(x => x.on && !x.mirror && x.name !== name)
                root.mainName = other ? other.name : root.mainName
            }
        }
        root.settle()
        return true
    }

    // Screens that may be mirrored by `name` (on, not itself, no circle).
    function mirrorSources(name) {
        return root.draft.filter(d => d.on && d.name !== name && !HM.mirrorLoops(root.draft, name, d.name)).map(d => d.name)
    }

    // Screens the pointer cannot get to from the main screen (a gap in the layout).
    function unlinkedNames() {
        const rs = root.rects()
        const main = rs.filter(r => r.name === root.mainName)
        return DM.unlinked(main.concat(rs.filter(r => r.name !== root.mainName)))
    }

    // What the card shows for one screen.
    function resolutionsOf(d) { return DM.resolutions(d.modes, d.modeId, 10) }
    function currentRes(d) { return DM.currentRes(d.modes, d.modeId) }
    function ratesOf(d) { return DM.rates(d.modes, DM.currentRes(d.modes, d.modeId)) }

    // ===== applying =====
    // The draft as displays.sh arguments (positions shifted so the smallest x and y are 0).
    function draftSpecs() {
        const pos = {}
        root.rects().forEach(r => { pos[r.name] = [r.x, r.y] })
        const norm = DM.normalize(pos)
        // A screen that is off is parked past the right edge of the others, so Hyprland
        // does not count it at 0, 0 on top of the screen that is there.
        let edge = 0
        root.rects().forEach(r => { edge = Math.max(edge, norm[r.name][0] + r.w) })
        return root.draft.map(d => {
            const p = norm[d.name] || [Math.round(edge), 0]
            const s = DM.spec(d.name, d.on, d.modeId, p[0], p[1], d.scale)
            return root.hyprmon && d.on ? s + "|" + HM.extras(d).join(",") : s
        })
    }

    // The screens as they are now, to go back to.
    function liveSpecs() {
        return root.live.map(m => {
            const s = DM.spec(m.name, m.on, DM.matchMode(m.modes, m.w, m.h, m.hz), m.on ? m.x : undefined, m.on ? m.y : undefined, m.scale)
            return root.hyprmon && m.on ? s + "|" + HM.extras(m).join(",") : s
        })
    }

    // The draft in hyprmon's profile shape (HM.toProfileMonitor), positions shifted so
    // the smallest x and y are 0; a screen that is off is written as hyprmon does (-1, -1).
    function hyprmonMonitors(profileName) {
        const pos = {}
        root.rects().forEach(r => { pos[r.name] = [r.x, r.y] })
        const norm = DM.normalize(pos)
        const ids = HM.hardwareIds(root.draft)
        const prof = HyprmonService.profile(profileName)
        return root.draft.map(d => {
            const mode = DM.modeById(d.modes, d.modeId) || (d.modes.length > 0 ? d.modes[0] : null)
            const p = d.on ? (norm[d.name] || [0, 0]) : [-1, -1]
            return HM.toProfileMonitor(d, ids[d.name], p[0], p[1], mode, HM.findMonitor(prof, ids[d.name], d.name))
        })
    }

    function apply() {
        if (!root.dirty || root.confirming)
            return
        root.previous = root.liveSpecs()
        HyprmonService.held = true
        runner.exec(["sh", root.script, "apply"].concat(root.draftSpecs()))
        root.secondsLeft = root.confirmSeconds
        root.confirming = true
        countdown.restart()
        readAgain.restart()
    }

    // Keep: write monitors.lua and stay as it is. With hyprmon: save into the profile
    // `saveTarget` (which hyprmon then writes to hyprmon.lua); with no profile picked the
    // screens just stay as they are for this session.
    function keep() {
        if (!root.confirming)
            return
        countdown.stop()
        root.confirming = false
        root.dirty = false
        HyprmonService.held = false
        if (root.hyprmon) {
            if (HM.validName(root.saveTarget))
                HyprmonService.saveProfile(root.saveTarget, root.hyprmonMonitors(root.saveTarget))
        } else {
            runner.exec(["sh", root.script, "save"].concat(root.draftSpecs()))
        }
        readAgain.restart()
    }

    // Go back to what it was before Apply (also what the countdown does).
    function revert() {
        if (!root.confirming)
            return
        countdown.stop()
        root.confirming = false
        runner.exec(["sh", root.script, "apply"].concat(root.previous))
        root.dirty = false
        HyprmonService.held = false
        readAgain.restart()
    }

    // Throw away what you changed without applying it.
    function discard() {
        if (root.confirming)
            return
        root.resetDraft()
    }

    Process {
        id: runner
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft -= 1
            if (root.secondsLeft <= 0)
                root.revert()
        }
    }

    // Hyprland needs a moment to settle before it reports the new modes.
    Timer {
        id: readAgain
        interval: 900
        onTriggered: root.refresh()
    }
}
