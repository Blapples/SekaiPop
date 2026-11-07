// node tests/watertank-test/water_unit.js   (run from the sekaipop folder)
//
// The desktop Water Tank (services/WaterTankService.qml, modules/sekai/desktopWidgets/WaterTankWidget.qml,
// WaterTile.qml, WaterFill.qml). All of its numbers are in modules/common/functions/WaterMath.js, which
// this runs on its own; Quickshell can't be used here, so the QML is only checked for wiring.
//   1. a day key, the day before / after, the weekday
//   2. clamping the goal and the size of a glass
//   3. how full the tank is, the amount text
//   4. a new day: the count goes into the history, then starts at 0
//   5. the history is trimmed; the week bars; the streak
//   6. the QML is wired to it (service, widget, registry, edit mode, settings, ipc, icons)
const fs = require("fs"), assert = require("assert")
const locate = require("../lib/locate")
const read = f => fs.readFileSync(locate(f), "utf8")
const src = read("modules/common/functions/WaterMath.js").replace(".pragma library", "")
const W = {}
new Function("W", src + ";Object.assign(W,{dayKey,parseKey,shiftKey,weekday,clampGoal,clampGlass,fraction,reached,amountText,trimHistory,rollover,weekBars,streak,KEEP_DAYS});")(W)
let n = 0
const ok = (c, m) => { assert(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

// ---- 1. days ----
eq(W.dayKey(new Date(2026, 9, 27, 23, 59)), "2026-10-27")
eq(W.dayKey(new Date(2026, 0, 5, 0, 0)), "2026-01-05", "one-digit month and day are padded")
eq(W.shiftKey("2026-10-31", 1), "2026-11-01", "over a month end")
eq(W.shiftKey("2026-01-01", -1), "2025-12-31", "over a year end")
eq(W.shiftKey("2028-03-01", -1), "2028-02-29", "a leap day")
eq(W.shiftKey("nonsense", 1), "")
eq(W.weekday("2026-10-27"), 2, "Tuesday")
eq(W.weekday("2026-10-25"), 0, "Sunday")
eq(W.parseKey("2026-13-40") instanceof Date, true, "a made-up date still parses to something (never used as a key)")
eq(W.parseKey("x"), null)

// ---- 2. clamping ----
eq(W.clampGoal(8), 8)
eq(W.clampGoal(0), 1)
eq(W.clampGoal(99), 20)
eq(W.clampGoal("12"), 12)
eq(W.clampGoal("abc"), 8, "nonsense falls back to 8")
eq(W.clampGoal(7.6), 8)
eq(W.clampGlass(250), 250)
eq(W.clampGlass(240), 250, "steps of 50")
eq(W.clampGlass(10), 100)
eq(W.clampGlass(5000), 1000)
eq(W.clampGlass(undefined), 250)

// ---- 3. how full ----
eq(W.fraction(0, 8), 0)
eq(W.fraction(4, 8), 0.5)
eq(W.fraction(8, 8), 1)
eq(W.fraction(12, 8), 1, "more than the goal is just full")
eq(W.fraction(3, 0), 0, "no goal, no water")
eq(W.fraction(-2, 8), 0)
eq(W.fraction("x", 8), 0)
ok(W.reached(8, 8) && W.reached(9, 8) && !W.reached(7, 8) && !W.reached(1, 0))
eq(W.amountText(0, 250), "0 ml")
eq(W.amountText(3, 250), "750 ml")
eq(W.amountText(4, 250), "1 L", "whole litres have no .0")
eq(W.amountText(5, 250), "1.25 L")
eq(W.amountText(6, 250), "1.5 L")
eq(W.amountText(8, 250), "2 L")
eq(W.amountText(7, 300), "2.1 L")
eq(W.amountText(3, 333), "999 ml")
eq(W.amountText("x", 250), "0 ml")

// ---- 4. a new day ----
let r = W.rollover({ day: "2026-10-27", glasses: 5, history: { "2026-10-26": 7 } }, "2026-10-27")
eq(r.changed, false, "same day: nothing")
eq(r.glasses, 5)
r = W.rollover({ day: "2026-10-27", glasses: 5, history: { "2026-10-26": 7 } }, "2026-10-28")
eq(r.changed, true)
eq(r.glasses, 0, "the count starts again")
eq(r.day, "2026-10-28")
eq(r.history, { "2026-10-26": 7, "2026-10-27": 5 }, "yesterday goes into the history")
r = W.rollover({ day: "2026-10-27", glasses: 0, history: {} }, "2026-10-28")
eq(r.history, {}, "a day with no water is not written")
r = W.rollover({ day: "", glasses: 0, history: {} }, "2026-10-28")
eq(r.changed, true, "the very first run stamps the day")
eq(r.day, "2026-10-28")
r = W.rollover({ day: "2026-10-30", glasses: 3, history: {} }, "2026-10-28")
eq(r.changed, false, "a clock set back changes nothing")
eq(r.glasses, 3)
r = W.rollover({ day: "2026-10-01", glasses: 6, history: {} }, "2026-10-28")
eq(r.history, {}, "an old day (after a long time away) is past the 14 days and is dropped")
r = W.rollover({ day: "2026-10-26", glasses: 6, history: {} }, "2026-10-28")
eq(r.history, { "2026-10-26": 6 }, "two days away: the last day is still kept")

// ---- 5. history, bars, streak ----
const h = { "2026-10-01": 8, "2026-10-13": 4, "2026-10-14": 5, "2026-10-26": 9, "2026-10-28": 2, "bad": 3, "2026-10-20": -1, "2026-10-21": "x", "2026-10-22": 500 }
eq(W.trimHistory(h, "2026-10-28"), { "2026-10-14": 5, "2026-10-22": 99, "2026-10-26": 9 }, "only the last 14 days before today, sane numbers, today left out")
eq(W.trimHistory(null, "2026-10-28"), {})
const bars = W.weekBars({ "2026-10-26": 7, "2026-10-24": 3 }, 5, "2026-10-28", 7)
eq(bars.length, 7)
eq(bars[0].key, "2026-10-22")
eq(bars[6], { key: "2026-10-28", weekday: 3, count: 5, today: true }, "today is last and uses the live count")
eq(bars[2].count, 3, "the 24th")
eq(bars[4].count, 7, "the 26th")
eq(bars[1].count, 0, "a day with nothing (the 23rd) is 0")
ok(bars.filter(b => b.today).length === 1)
const run = { "2026-10-27": 8, "2026-10-26": 9, "2026-10-25": 8, "2026-10-24": 3, "2026-10-23": 8 }
eq(W.streak(run, 8, 8, "2026-10-28"), 4, "today reached + three days")
eq(W.streak(run, 2, 8, "2026-10-28"), 3, "today not reached yet: yesterday's run stands")
eq(W.streak({}, 0, 8, "2026-10-28"), 0)
eq(W.streak({}, 8, 8, "2026-10-28"), 1, "just today")
eq(W.streak({ "2026-10-26": 8 }, 3, 8, "2026-10-28"), 0, "a missed day breaks it")
eq(W.streak(run, 9, 9, "2026-10-28"), 1, "a higher goal than the old days: only today counts")
eq(W.streak(run, 8, 9, "2026-10-28"), 0, "8 of 9 today and no old day reached 9: no streak")

// ---- 6. the QML is wired to it ----
const svc = read("services/WaterTankService.qml")
const widget = read("modules/sekai/desktopWidgets/WaterTankWidget.qml")
const tile = read("modules/sekai/desktopWidgets/WaterTile.qml")
const fill = read("modules/sekai/desktopWidgets/WaterFill.qml")
const shell = read("shell.qml")
const edit = read("services/EditMode.qml")
const pw = read("services/PresetWidgets.qml")
const fm = read("modules/common/functions/FocusMath.js")
const settings = read("modules/sekai/settings/SettingsPageDesktop.qml")
const state = read("scripts/state/watertank-state.sh")
const icons = read("modules/common/functions/IconMap.js")

ok(/pragma Singleton/.test(svc), "the service is a singleton")
ok(/WaterMath\.js/.test(svc) && /WaterMath\.js/.test(widget), "service and widget use WaterMath")
for (const f of ["loaded", "shown", "size", "posX", "posY", "posScale", "screenName", "goal", "glassMl", "glasses", "day", "history"])
    ok(new RegExp("property \\w+ " + f + "\\b").test(svc), "service has " + f)
for (const f of ["addGlass", "removeGlass", "resetToday", "setGoal", "setGlassMl", "setPosition", "setShown", "setSize", "toggleSize", "checkDay", "snapshot", "restore", "persist"])
    ok(new RegExp("function " + f + "\\(").test(svc), "service has " + f + "()")
ok(/signal glassAdded\(\)/.test(svc))
ok(/watertank-state\.sh/.test(svc) && /watertank\.json/.test(state), "the state script is the one the service runs")
ok(/shown = s\.shown === true/.test(svc), "off until you add it (a first run shows only the clock)")
ok(fs.statSync(locate("scripts/state/watertank-state.sh")).mode & 0o100, "the state script is executable")
ok(/Behavior on shownLevel/.test(tile) && /property real shownLevel/.test(tile), "no Behavior on a readonly property in the tile")
ok(/WaterFill/.test(tile) && /WaterFill/.test(widget), "both sizes draw the water with WaterFill")
ok(/RoundClip/.test(fill))
ok(/onGlassAdded/.test(widget) && /onWheel/.test(widget) && /addGlass\(\)/.test(widget), "a click, the wheel and the signal are wired")
ok(/widgetId: "watertank"/.test(widget) && /EditChrome/.test(widget), "edit chrome")
ok(!/WeatherCard|weathercard|WidgetClones/.test(widget), "no weather card or clone code left in the widget")
ok(/WaterTankWidget \{\}/.test(shell) && /woke\(11\)/.test(shell) && /widgetId: "watertank"/.test(shell), "shell.qml loads it behind a FocusGate")
ok(/target: "watertank"/.test(shell), "an ipc handler")
ok(/id: "watertank"/.test(edit) && /WaterTankService\.shown/.test(edit) && /WaterTankService\.setPosition/.test(edit) && /WaterTankService\.setShown\(false\)/.test(edit), "Edit Desktop can add, drop and remove it")
ok(/id: "watertank", service: WaterTankService/.test(pw), "it is in the preset registry")
ok(/watertank: 10/.test(fm), "it has a wake-up slot")
ok(/WaterTankService\.shown/.test(settings) && /WaterTankService\.setGoal/.test(settings) && /WaterTankService\.setGlassMl/.test(settings), "settings: on / off, goal and glass size")
ok(/water_drop: "waterdrop"/.test(icons), "the droplet icon is a Solar icon")
for (const f of ["waterdrop", "flame", "cup", "flag", "add-circle", "minus-circle", "check-circle"])
    for (const style of ["outline", "bold", "broken", "line-duotone", "bold-duotone"])
        ok(fs.existsSync(locate("assets/icons/" + style + "/" + f + ".svg")), style + "/" + f + ".svg exists")

// The mistakes that stop Quickshell from loading a QML file (a second Component.onCompleted, the same id twice)
const qmlcheck = require("../lib/qmlcheck")
for (const f of ["modules/sekai/desktopWidgets/WaterTankWidget.qml", "modules/sekai/desktopWidgets/WaterTile.qml", "modules/sekai/desktopWidgets/WaterFill.qml", "services/WaterTankService.qml"]) {
    const problems = qmlcheck(read(f), f)
    ok(problems.length === 0, "QML structure: " + problems.join("; "))
}

console.log("water_unit: all " + n + " checks passed")
