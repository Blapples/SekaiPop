// node tests/display-test/hyprmon_unit.js   (run from the sekaipop folder)
const fs = require("fs")
const locate = require("../lib/locate.js")
const src = fs.readFileSync(locate("modules/common/functions/HyprmonMath.js"), "utf8").replace(".pragma library", "")
const H = new Function(src + "; return { hardwareId, hardwareIds, resolve, matchProfile, setKey, chooseProfile, bitDepthOf, COLOR_MODES, isHdr, extras, mirrorLoops, toProfileMonitor, mergeMonitors, findMonitor, summary, validName }")()

let fails = 0
function eq(a, b, msg) {
    const x = JSON.stringify(a), y = JSON.stringify(b)
    if (x !== y) { fails++; console.log("FAIL " + msg + "\n   got  " + x + "\n   want " + y) }
}

// hardware ids
eq(H.hardwareId("LG Display", "0x06B3", ""), "LG Display/0x06B3", "no serial")
eq(H.hardwareId(" Iiyama ", "PL3480WQ", "1000000000001"), "Iiyama/PL3480WQ/1000000000001", "trimmed, with serial")
eq(H.hardwareId("", "", "123"), "", "no make or model: no id")
eq(H.hardwareIds([
    { name: "DP-2", make: "Dell", model: "U27", serial: "" },
    { name: "DP-1", make: "Dell", model: "U27", serial: "" },
    { name: "eDP-1", make: "LG", model: "X", serial: "" }
]), { "DP-2": "Dell/U27/#2", "DP-1": "Dell/U27/#1", "eDP-1": "LG/X" }, "twins told apart by connector name")

// profiles shaped like real ones (a laptop, a home desk with the laptop screen off,
// two work desks with different units of the same monitor model)
const LAPTOP = "LG Display/0x06B3", MSI = "Microstep/MSI G241/0x00000001", SAM = "Samsung/Odyssey G93SD/SN0000001"
const IIY90 = "Iiyama/PL3480WQ/1000000000001", IIY89 = "Iiyama/PL3480WQ/1000000000002"
const mon = (name, hw, active) => ({ name, hardware_id: hw, Active: active })
const profiles = [
    { name: "Home-share", monitors: [mon("eDP-1", LAPTOP, false), mon("DP-3", MSI, true), mon("DP-4", SAM, true)] },
    { name: "Home", monitors: [mon("eDP-1", LAPTOP, false), mon("DP-3", MSI, true), mon("DP-4", SAM, true)] },
    { name: "Laptop", monitors: [mon("eDP-1", LAPTOP, true)] },
    { name: "Work-2", monitors: [mon("eDP-1", LAPTOP, true), mon("DP-7", IIY89, true)] },
    { name: "Work-3", monitors: [mon("eDP-1", LAPTOP, true), mon("DP-7", IIY90, true)] },
    { name: "Legacy", monitors: [{ name: "HDMI-A-1", Active: true }] }
]
const scr = (name, hwid) => ({ name, hwid })

// matching
const undocked = [scr("eDP-1", LAPTOP)]
eq(H.matchProfile(profiles[1], undocked), { ok: false, score: 0 }, "Home with nothing plugged in would leave no screen on")
eq(H.matchProfile(profiles[2], undocked), { ok: true, score: 3 }, "Laptop fits the bare laptop exactly")
const home = [scr("eDP-1", LAPTOP), scr("DP-3", MSI), scr("DP-4", SAM)]
eq(H.matchProfile(profiles[1], home), { ok: true, score: 3 }, "Home fits the home desk")
eq(H.matchProfile(profiles[2], home), { ok: true, score: 1 }, "Laptop at the home desk misses the externals")
const homeRenamed = [scr("eDP-1", LAPTOP), scr("DP-5", MSI), scr("DP-6", SAM)]
eq(H.matchProfile(profiles[1], homeRenamed), { ok: true, score: 3 }, "connector names do not matter")
const work90 = [scr("eDP-1", LAPTOP), scr("DP-7", IIY90)]
eq(H.matchProfile(profiles[4], work90), { ok: true, score: 3 }, "Work-3 fits its own Iiyama")
eq(H.matchProfile(profiles[3], work90), { ok: false, score: 0 }, "Work-2 wants another Iiyama unit")
eq(H.matchProfile(profiles[5], [scr("HDMI-A-1", "")]), { ok: true, score: 3 }, "a profile without ids matches by name")
eq(H.matchProfile({ name: "x", monitors: [] }, undocked).ok, false, "an empty profile is never ok")

// choosing
eq(H.chooseProfile(profiles, undocked, {}), "Laptop", "undocked -> Laptop")
eq(H.chooseProfile(profiles, home, {}), "Home-share", "two exact fits, nothing remembered: the first in the order")
eq(H.chooseProfile(profiles, home, { [H.setKey(home)]: "Home" }), "Home", "the one used last on these screens wins a tie")
eq(H.chooseProfile(profiles, home, { [H.setKey(home)]: "Laptop" }), "Home-share", "a remembered profile that is not among the best is ignored")
eq(H.chooseProfile(profiles, work90, {}), "Work-3", "the right work desk")
const unknownDesk = [scr("eDP-1", LAPTOP), scr("DP-7", "Iiyama/PL3480WQ/999")]
eq(H.chooseProfile(profiles, unknownDesk, {}), "Laptop", "an unknown desk: the profile that still fits (the new screen is left to Hyprland)")
eq(H.chooseProfile(profiles.slice(0, 2), undocked, {}), "", "nothing safe to apply -> none")
eq(H.setKey([scr("b", "Y"), scr("a", "X")]), "X+Y", "set key is sorted ids")

// colour depth, extras
eq(H.bitDepthOf("XRGB2101010"), 10, "10-bit format")
eq(H.bitDepthOf("XRGB8888"), 8, "8-bit format")
eq(H.extras({ transform: 0, vrr: 0, bitDepth: 8, cm: "srgb" }), [], "defaults say nothing")
eq(H.extras({ transform: 1, vrr: 2, bitDepth: 10, cm: "hdr", sdrBrightness: 1.2, sdrSaturation: 1 }),
   ["transform=1", "vrr=2", "bitdepth=10", "cm=hdr", "sdrbrightness=1.20"], "every extra, saturation at its default left out")
eq(H.extras({ cm: "wide", sdrBrightness: 1.5 }), ["cm=wide"], "SDR levels only with HDR")
eq(H.extras({ cm: "bogus" }), [], "an unknown colour mode is dropped")
eq(H.extras({ mirror: "DP-1", transform: 1, vrr: 1 }), ["mirror=DP-1"], "a mirror takes nothing else")

// mirror loops
const dr = [{ name: "A", mirror: "" }, { name: "B", mirror: "A" }, { name: "C", mirror: "B" }]
eq(H.mirrorLoops(dr, "A", "C"), true, "A -> C -> B -> A is a circle")
eq(H.mirrorLoops(dr, "A", "A"), true, "a screen cannot mirror itself")
eq(H.mirrorLoops(dr, "C", "A"), false, "C mirroring A is fine")
eq(H.mirrorLoops(dr, "A", ""), false, "no mirror, no circle")

// saving into a profile
const d = { name: "DP-7", desc: "Iiyama PL3480WQ 1000000000001", on: true, make: "Iiyama", model: "PL3480WQ", serial: "1000000000001",
            scale: 1, modes: [{ w: 3440, h: 1440, hz: 59.999 }], bitDepth: 8, cm: "srgb", sdrBrightness: 1, sdrSaturation: 1,
            vrr: 0, transform: 0, mirror: "" }
const pm = H.toProfileMonitor(d, IIY90, 7296, 0, { w: 3440, h: 1440, hz: 59.999 }, { alias: "Desk", use_desc_format: true })
eq([pm.name, pm.hardware_id, pm.alias, pm.use_desc_format, pm.PxW, pm.PxH, pm.Hz, pm.X, pm.Y, pm.Active, pm.EDIDName],
   ["DP-7", IIY90, "Desk", true, 3440, 1440, 59.999, 7296, 0, true, "Iiyama PL3480WQ 1000000000001"], "profile monitor fields, alias kept")
eq(Object.keys(JSON.parse(JSON.stringify(H.toProfileMonitor(Object.assign({}, d, { make: "", serial: "" }), "", 0, 0, null, null)))).indexOf("serial"), -1,
   "empty optional fields are left out of the file")
eq(pm.Modes, [{ W: 3440, H: 1440, Hz: 59.999 }], "modes in hyprmon's shape")
const merged = H.mergeMonitors(
    [mon("eDP-1", LAPTOP, true), mon("DP-7", IIY90, true), mon("HDMI-A-1", "Some/Projector", true)],
    [Object.assign({}, pm), { name: "eDP-1", hardware_id: LAPTOP, Active: true, IsMirrored: true, MirrorSource: "DP-7" }])
eq(merged.map(m => m.name), ["DP-7", "eDP-1", "HDMI-A-1"], "saved screens replace theirs, an unplugged one is kept")
eq(merged[0].MirrorTargets, ["eDP-1"], "mirror targets worked out again")
eq(merged[2].MirrorTargets, null, "no targets -> null")
eq(H.findMonitor(profiles[4], IIY90, "DP-9").name, "DP-7", "found by id whatever its name")
eq(H.findMonitor(profiles[5], "", "HDMI-A-1").name, "HDMI-A-1", "an old profile's screen by name")
eq(H.findMonitor(profiles[4], "nope", "nope"), null, "not there")

// summary, names
eq(H.summary({ monitors: [{ name: "eDP-1", Active: false }, { name: "DP-4", Active: true, PxW: 5120, PxH: 1440, Scale: 1.33 },
                          { name: "DP-3", alias: "Side", Active: true, IsMirrored: true, MirrorSource: "DP-4" }] }),
   "eDP-1 off  \u00b7  DP-4 5120x1440 @133%  \u00b7  Side mirrors DP-4", "summary line")
eq(["Work-3", "Home share", "a.b_c", "", ".hidden", "../x", "a/b", " pad", "x".repeat(65)].map(H.validName),
   [true, true, true, false, false, false, false, false, false], "profile names")

if (fails) { console.log(fails + " failed"); process.exit(1) }
console.log("hyprmon_unit: all passed")
