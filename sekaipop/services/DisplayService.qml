pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "../modules/common/functions/DisplayMath.js" as DM

// The Displays card's brain (Settings > Hyprland). Reads the screens from Hyprland,
// keeps a draft of what you are changing, applies it live, and asks "keep these?"
// with a countdown: if you do not answer (a black screen, say) it goes back by
// itself. Only "Keep" writes ~/.config/hypr/monitors.lua, the file nwg-displays
// writes and hyprland.lua loads (scripts/hyprland/displays.sh does the work).
//
//     DisplayService.setScale("HDMI-A-1", "1.25")
//     DisplayService.apply()          // shows it, starts the countdown
//     DisplayService.keep()           // saves
//
// The maths (modes, scale, where each screen sits) is modules/common/functions/DisplayMath.js.
Singleton {
    id: root

    // What Hyprland has now: [{ name, desc, on, w, h, hz, x, y, scale, transform, modes }].
    property var live: []
    // What is being edited: [{ name, desc, on, modeId, scale, place, x, y, transform, modes }].
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
    // After Apply: look again that Hyprland really did it, and try the other way if not.
    property bool checking: false
    property int tries: 0
    property string problem: ""

    // What hyprctl lists, the screens the kernel knows, and the two joined (see DM.mergeKnown).
    property var hyprLive: []
    property var known: []
    property double knownAt: 0

    readonly property var scales: DM.SCALES
    readonly property int enabledCount: root.draft.filter(d => d.on).length
    readonly property var enabledNames: root.draft.filter(d => d.on).map(d => d.name)

    readonly property string script: Directories.script("hyprland/displays.sh")

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
                root.hyprLive = parsed.map(m => ({
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
                    modes: DM.parseModes(m.availableModes || [])
                }))
                // The kernel's list changes rarely: look it up again only now and then.
                if (Date.now() - root.knownAt > 30000 && !knownReader.running)
                    knownReader.running = true
                else
                    root.mergeLive()
            }
        }
    }

    // Screens that are plugged in, whether or not Hyprland lists them.
    Process {
        id: knownReader
        command: ["sh", root.script, "known"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.known = DM.parseKnown(text)
                root.knownAt = Date.now()
                root.mergeLive()
            }
        }
    }

    function mergeLive() {
        root.live = DM.mergeKnown(root.hyprLive, root.known)
        // Never replace what you are in the middle of changing.
        if (!root.dirty && !root.confirming)
            root.resetDraft()
        root.checkApplied()
    }

    // After Apply: did Hyprland switch the screens the way the draft says? If not, try
    // `hyprctl keyword monitor` (displays.sh force), twice; after that say so.
    function checkApplied() {
        if (!root.checking || runner.running)
            return
        const bad = DM.mismatched(root.draft, root.live)
        if (bad.length === 0) {
            root.checking = false
            root.problem = ""
            return
        }
        if (root.tries < 2) {
            root.tries += 1
            const specs = root.draftSpecs().filter(s => bad.some(d => s.split("|")[0] === d.name))
            runner.exec(["sh", root.script, "force"].concat(specs))
            return
        }
        root.checking = false
        root.problem = "Hyprland did not switch " + bad.map(d => d.name).join(", ") + (bad[0].on ? " on" : " off") + ". What it said is in ~/.cache/sekaipop/displays.log"
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
        const next = L.map(m => {
            const sz = DM.logicalSize(m.w, m.h, m.scale, m.transform)
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
                hint: m.hint || null
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
        // A screen Hyprland does not list has no modes yet: draw it at the panel's own size.
        const base = mode || d.hint || { w: 0, h: 0 }
        const sz = DM.logicalSize(base.w, base.h, d.scale, d.transform)
        return { w: Math.ceil(sz.w - 1e-6), h: Math.ceil(sz.h - 1e-6) }
    }

    // The screens that are on, as layout rectangles: [{ name, x, y, w, h }].
    function rects() {
        return root.draft.filter(d => d.on).map(d => {
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
            root.edit(name, { on: false })
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
            return DM.spec(d.name, d.on, d.modeId, p[0], p[1], d.scale)
        })
    }

    // The screens as they are now, to go back to.
    function liveSpecs() {
        return root.live.map(m => DM.spec(m.name, m.on, DM.matchMode(m.modes, m.w, m.h, m.hz), m.on ? m.x : undefined, m.on ? m.y : undefined, m.scale))
    }

    function apply() {
        if (!root.dirty || root.confirming)
            return
        root.previous = root.liveSpecs()
        root.problem = ""
        root.tries = 0
        root.checking = true
        runner.exec(["sh", root.script, "apply"].concat(root.draftSpecs()))
        root.secondsLeft = root.confirmSeconds
        root.confirming = true
        countdown.restart()
        readAgain.restart()
    }

    // Keep: write monitors.lua and stay as it is.
    function keep() {
        if (!root.confirming)
            return
        countdown.stop()
        root.confirming = false
        root.checking = false
        root.dirty = false
        runner.exec(["sh", root.script, "save"].concat(root.draftSpecs()))
        readAgain.restart()
    }

    // Go back to what it was before Apply (also what the countdown does).
    function revert() {
        if (!root.confirming)
            return
        countdown.stop()
        root.confirming = false
        root.checking = false
        root.problem = ""
        runner.exec(["sh", root.script, "apply"].concat(root.previous))
        root.dirty = false
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
        // The script is done: give Hyprland a moment, then look at what it did.
        onExited: readAgain.restart()
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
