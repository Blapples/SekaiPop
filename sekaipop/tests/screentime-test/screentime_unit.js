// node tests/screentime-test/screentime_unit.js   (run from the sekaipop folder)
//
// The bar's screen time pill (services/ScreenTimeService.qml, modules/sekai/bar/ScreenTimeIndicator.qml,
// ScreenTimePopup.qml). All of its numbers are in modules/common/functions/ScreenTimeMath.js, which this
// runs on its own; Quickshell can't be used here, so the QML is only checked for wiring.
//   1. day keys
//   2. which ticks count, what an app is filed under
//   3. adding time; the top apps
//   4. a new day: the total goes into the history, then starts at 0
//   5. history / apps are trimmed to sane numbers
//   6. the text ("3h 12m"), the week bars, the average
//   7. the QML is wired to it (setting, layout, bar, popup, service, ipc)
const fs = require("fs"), assert = require("assert")
const locate = require("../lib/locate")
const qmlcheck = require("../lib/qmlcheck")
const read = f => fs.readFileSync(locate(f), "utf8")
const src = read("modules/common/functions/ScreenTimeMath.js").replace(".pragma library", "")
const S = {}
new Function("S", src + ";Object.assign(S,{dayKey,parseKey,shiftKey,weekday,elapsed,appKey,prettyApp,addTime,topApps,trimApps,trimHistory,rollover,parts,shortText,longText,normalizeFormat,nextFormat,formatText,formatTemplate,weekBars,average,KEEP_DAYS,MAX_APPS,MAX_GAP});")(S)
let n = 0
const ok = (c, m) => { assert(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

// ---- 1. days ----
eq(S.dayKey(new Date(2026, 9, 27, 23, 59)), "2026-10-27")
eq(S.dayKey(new Date(2026, 0, 5, 0, 0)), "2026-01-05", "one-digit month and day are padded")
eq(S.shiftKey("2026-10-31", 1), "2026-11-01", "over a month end")
eq(S.shiftKey("2026-01-01", -1), "2025-12-31", "over a year end")
eq(S.shiftKey("nonsense", 1), "", "a bad key gives nothing")
eq(S.weekday("2026-11-03"), 2, "a Tuesday")

// ---- 2. ticks and app keys ----
eq(S.elapsed(1000, 6000), 5, "five seconds between ticks")
eq(S.elapsed(6000, 1000), 0, "a clock set back counts nothing")
eq(S.elapsed(1000, 1000), 0, "no time, no count")
eq(S.elapsed(0, (S.MAX_GAP + 1) * 1000), 0, "a long gap (sleep, a hang) is not counted")
eq(S.elapsed(0, S.MAX_GAP * 1000), S.MAX_GAP, "right at the limit still counts")
eq(S.elapsed("x", 5), 0, "garbage counts nothing")
eq(S.appKey("Firefox"), "firefox", "case does not split an app in two")
eq(S.appKey("  kitty "), "kitty", "trimmed")
eq(S.appKey(undefined), "", "no window")
eq(S.appKey(null), "", "no window")
eq(S.prettyApp("org.mozilla.firefox"), "Firefox")
eq(S.prettyApp("code-oss"), "Code-oss")
eq(S.prettyApp(""), "")

// ---- 3. adding time ----
let r = S.addTime(0, {}, "kitty", 5)
eq(r, { total: 5, apps: { kitty: 5 } })
r = S.addTime(r.total, r.apps, "kitty", 5)
r = S.addTime(r.total, r.apps, "firefox", 20)
eq(r, { total: 30, apps: { kitty: 10, firefox: 20 } })
const before = { kitty: 10 }
S.addTime(10, before, "kitty", 5)
eq(before, { kitty: 10 }, "the object passed in is not changed")
eq(S.addTime(10, { kitty: 10 }, "", 5), { total: 15, apps: { kitty: 10 } }, "no focused window: counts towards the day, not an app")
eq(S.addTime(10, { kitty: 10 }, "kitty", -3), { total: 10, apps: { kitty: 10 } }, "nothing negative")
eq(S.addTime(10, { kitty: 10 }, "kitty", NaN), { total: 10, apps: { kitty: 10 } }, "nothing from garbage")
eq(S.topApps({ a: 5, b: 50, c: 20 }, 0).map(x => x.key), ["b", "c", "a"], "longest first")
eq(S.topApps({ a: 5, b: 50, c: 20 }, 2).map(x => x.key), ["b", "c"], "limited")
eq(S.topApps({ a: 1, b: 1 }, 0).map(x => x.key), ["a", "b"], "ties go by name")
eq(S.topApps({ a: 0, b: -4, c: "x", "": 9 }, 0), [], "zero, negative, garbage and the no-app key are left out")
eq(S.topApps(null, 0), [])

// ---- 4. a new day ----
let st = { day: "2026-11-02", total: 7200.4, apps: { kitty: 7000 }, history: { "2026-11-01": 3600 } }
eq(S.rollover(st, "2026-11-02").changed, false, "the same day: nothing")
let nx = S.rollover(st, "2026-11-03")
ok(nx.changed, "a later day changes")
eq(nx.day, "2026-11-03")
eq(nx.total, 0, "the new day starts at 0")
eq(nx.apps, {}, "and with no apps")
eq(nx.history, { "2026-11-01": 3600, "2026-11-02": 7200 }, "yesterday's total goes into the history, in whole seconds")
nx = S.rollover({ day: "", total: 0, apps: {}, history: {} }, "2026-11-03")
eq([nx.changed, nx.day, nx.total], [true, "2026-11-03", 0], "the first run just stamps the day")
nx = S.rollover({ day: "2026-11-05", total: 100, apps: { a: 100 }, history: {} }, "2026-11-03")
eq([nx.changed, nx.day, nx.total], [false, "2026-11-05", 100], "a clock set back changes nothing")
nx = S.rollover({ day: "2026-11-02", total: 0, apps: {}, history: {} }, "2026-11-03")
eq(nx.history, {}, "an empty day is not written into the history")
nx = S.rollover({ day: "2026-10-01", total: 500, apps: {}, history: {} }, "2026-11-03")
eq(nx.history, {}, "a day older than the kept ones falls out straight away")
nx = S.rollover({ day: "garbage", total: 5, apps: {}, history: {} }, "2026-11-03")
eq([nx.changed, nx.day], [true, "2026-11-03"], "an unreadable day is replaced")

// ---- 5. trimming ----
const today = "2026-11-03"
const h = S.trimHistory({ "2026-11-02": 3600.6, "2026-11-03": 99, "2026-11-04": 99, "2026-09-01": 100, "nonsense": 5, "2026-11-01": -5, "2026-10-31": "x", "2026-10-30": 999999 }, today)
eq(h, { "2026-11-02": 3601, "2026-10-30": 86400 }, "today, the future, too-old, bad keys and bad numbers go; a day is at most 24 h")
eq(S.trimHistory(null, today), {})
const many = {}
for (let i = 0; i < 60; i++) many["app" + i] = i + 1
const kept = S.trimApps(many)
eq(Object.keys(kept).length, S.MAX_APPS, "only the biggest apps are kept")
ok(kept.app59 === 60 && !("app0" in kept), "the smallest go first")
eq(S.trimApps({ a: 5.4, b: -1, c: "x" }), { a: 5 }, "whole seconds, sane numbers only")

// ---- 6. text, bars, average ----
eq(S.parts(11520), { h: 3, m: 12 })
eq(S.parts(59), { h: 0, m: 0 }, "under a minute is 0 m")
eq(S.parts(-5), { h: 0, m: 0 })
eq(S.parts("x"), { h: 0, m: 0 })
eq(S.shortText(11520), "3h 12m")
eq(S.shortText(7200), "2h 0m")
eq(S.shortText(2520), "42m")
eq(S.shortText(0), "0m")
eq(S.longText(11520), "3 hr 12 min")
eq(S.longText(7200), "2 hr")
eq(S.longText(2520), "42 min")
// the three ways of writing it (right-click cycles them)
eq(S.formatText(11565, "short"), "3h 12m")
eq(S.formatText(2520, "short"), "0h 42m", "short always shows the hours, so its length does not jump at the first hour")
eq(S.formatText(0, "short"), "0h 00m", "and pads the minutes")
eq(S.formatText(37500, "short"), "10h 25m")
eq(S.formatText(11565, "clock"), "03:12", "clock: hours and minutes, padded")
eq(S.formatText(11565, "seconds"), "03:12:45", "seconds: and the seconds")
eq(S.formatText(0, "clock"), "00:00")
eq(S.formatText(0, "seconds"), "00:00:00")
eq(S.formatText(3599.9, "seconds"), "00:59:59", "seconds are rounded down, never up into the next minute")
eq(S.formatText(86399, "seconds"), "23:59:59")
eq(S.formatText(-5, "seconds"), "00:00:00", "nothing negative")
eq(S.formatText(11565, "nonsense"), "3h 12m", "an unknown format falls back to short")
eq(S.formatText(11565, undefined), "3h 12m")
eq(S.normalizeFormat("clock"), "clock")
eq(S.normalizeFormat(42), "short")
eq([S.nextFormat("short"), S.nextFormat("clock"), S.nextFormat("seconds")], ["clock", "seconds", "short"], "short -> clock -> seconds -> short")
eq(S.nextFormat("nonsense"), "clock", "an unknown format counts as short")
// The pill is as wide as the widest text of its format and no wider (so no pill beside it ever moves).
eq([S.formatTemplate("short"), S.formatTemplate("clock"), S.formatTemplate("seconds"), S.formatTemplate("x")], ["00h 00m", "00:00", "00:00:00", "00h 00m"])
for (const mode of ["short", "clock", "seconds"]) {
    const tpl = S.formatTemplate(mode).length
    for (const secs of [0, 59, 60, 3599, 3600, 36000, 86399, 86400])
        ok(S.formatText(secs, mode).length <= tpl, mode + " at " + secs + " s fits the reserved width")
    ok(S.formatText(5 * 3600 + 7 * 60 + 9, mode).length >= tpl - 1, mode + ": an ordinary time is within a character of the reserved width (no big empty gap)")
}

const hist = { "2026-11-02": 7200, "2026-10-31": 3600, "2026-10-28": 1800 }
const bars = S.weekBars(hist, 1800, today, 7)
eq(bars.length, 7, "seven days")
eq(bars.map(b => b.key), ["2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"], "oldest first, ending today")
ok(bars[6].today && !bars[5].today, "only the last is today")
eq(bars[6].secs, 1800, "today is the live count")
eq(bars[5].frac, 1, "the longest day shown fills the chart (a floor of one hour keeps quiet weeks short)")
eq(bars[3].frac, 0.5, "half as long, half as tall")
eq(bars[1].frac, 0, "a day with nothing has no bar")
const quiet = S.weekBars({}, 60, today, 7)
ok(quiet[6].frac >= 0.04 && quiet[6].frac < 0.1, "a minute on a quiet week is a stub, not a full bar")
eq(S.weekBars({}, 0, today).length, 7, "seven by default")
eq(S.average({ "2026-11-02": 7200, "2026-11-01": 3600, "2026-10-31": 0 }, today, 7), 5400, "days with nothing are not averaged in")
eq(S.average({}, today, 7), 0, "no history, no average")
eq(S.average({ "2026-11-03": 9999 }, today, 7), 0, "today is not part of the average")

// ---- 7. the QML is wired to it ----
const svc = read("services/ScreenTimeService.qml")
ok(/pragma Singleton/.test(svc), "the service is a singleton")
ok(svc.includes('"state/screentime-state.sh"'), "it persists through its state script")
ok(fs.existsSync(locate("scripts/state/screentime-state.sh")), "the state script exists")
ok(svc.includes('SettingsService.flag("bar.screenTime")'), "counting follows the pill's switch")
ok(svc.includes("LockState.locked"), "a locked session is not counted")
ok(/IdleMonitor/.test(svc) && /try\s*\{/.test(svc), "idle detection is optional (guarded)")
ok(svc.includes("function resetToday"), "today can be reset")
ok(svc.includes("function cycleFormat") && svc.includes('"bar.screenTimeFormat"'), "the format is chosen in a remembered setting")
ok(/interval:\s*root\.format === "seconds" \? 1000 : 5000/.test(svc), "it ticks every second only while the seconds are shown")

const settings = read("services/SettingsService.qml")
ok(/"bar\.screenTime":\s*true/.test(settings), "the switch has a default")
ok(/"bar\.screenTimeFormat":\s*"short"/.test(settings), "the format has a default")
ok(/screenTime:\s*root\.flag\("bar\.screenTime"\)/.test(settings), "and is one of the bar modules")
ok(read("modules/sekai/settings/SettingsPageBar.qml").includes('"bar.screenTime"'), "it is in Settings -> Bar -> Modules")

const layout = read("services/BarLayoutService.qml")
ok(/id: "screenTime"/.test(layout), "a layout module")
ok(/right: \[[^\]]*"screenTime"/.test(layout), "in the default bar's right zone")
const sb = read("modules/sekai/bar/Status_Bar.qml")
ok(/right: \[[^\]]*"screenTime"/.test(sb), "the bar's own default layout matches")
ok(sb.includes('case "screenTime": return [screenTimeIndicator]'), "Status_Bar knows its items")
ok(sb.includes("ScreenTimeIndicator {") && sb.includes('status_Bar.shows("screenTime")'), "the pill is on the bar")
ok(sb.includes("signal screenTimeFormatRequested()") && sb.includes("onFormatRequested: status_Bar.screenTimeFormatRequested()"), "a right-click reaches Bar")
ok(sb.includes("signal screenTimeClicked()") && sb.includes("readonly property Item screenTimeToggle"), "it can be clicked and anchored to")

const bar = read("modules/sekai/bar/Bar.qml")
ok(bar.includes("function toggleScreenTimePopup()"), "Bar opens the card")
ok(/ScreenTimePopup \{/.test(bar) && bar.includes("statusBar.screenTimeToggle"), "the card hangs off the pill")
ok(bar.includes("onScreenTimeClicked: win.toggleScreenTimePopup()"), "a click opens it")
ok(bar.includes("onScreenTimeFormatRequested: ScreenTimeService.cycleFormat()") && bar.includes("screenTimeText: ScreenTimeService.pillText"), "a right-click changes the format and the pill shows it")
const ind = read("modules/sekai/bar/ScreenTimeIndicator.qml")
ok(ind.includes("Qt.LeftButton | Qt.RightButton") && ind.includes("root.formatRequested()"), "the pill takes a right-click")
ok(/implicitWidth: root\.vertical \? pill\.barVWidth : glyph\.width \+ root\.figuresWidth/.test(ind), "the pill's width comes from the reserved text, not from the digits shown")
ok(!/label\.implicitWidth/.test(ind), "nothing sizes the pill from the live text")
ok(/width: root\.figuresWidth/.test(ind), "the figures sit in a fixed box")
ok(sb.includes("sizeText: status_Bar.screenTimeSizeText") && bar.includes("screenTimeSizeText: ScreenTimeService.pillTemplate"), "the reserved text reaches the pill")
ok(/win\.screenTimePopupOpen \|\|/.test(bar), "an open card keeps an auto-hidden bar up")
// Every other popup's toggle puts this one away, and this one puts the others away: two never stack.
for (const fn of ["toggleBatteryPopup", "toggleResourcePopup", "toggleCalendarPopup", "toggleWeatherPopup", "toggleUtilPopup", "toggleMediaPopup", "toggleDiscordPopup", "togglePluginPopup", "openEqPopup"]) {
    const m = new RegExp("function " + fn + "\\([^)]*\\) \\{([\\s\\S]*?)\\n    \\}\\n").exec(bar)
    ok(m && m[1].includes("screenTimePopupOpen = false"), fn + " puts the screen time card away")
}
const mine = /function toggleScreenTimePopup\(\) \{([\s\S]*?)\n    \}\n/.exec(bar)[1]
for (const k of ["eqPopupOpen", "mediaPopupOpen", "discordPopupOpen", "batteryPopupOpen", "utilPopupOpen", "resourcePopupOpen", "calendarPopupOpen", "weatherPopupOpen"])
    ok(mine.includes(k + " = false"), "the screen time toggle puts " + k + " away")
ok(read("shell.qml").includes('target: "screentime"'), "there is an ipc handler")
ok(read("shell.qml").includes("ScreenTimeService.loaded"), "the service exists from the start")

for (const f of ["services/ScreenTimeService.qml", "modules/sekai/bar/ScreenTimeIndicator.qml", "modules/sekai/bar/ScreenTimePopup.qml", "modules/sekai/bar/Bar.qml", "modules/sekai/bar/Status_Bar.qml", "shell.qml"]) {
    const problems = qmlcheck(read(f), f)
    eq(problems, [], f + " has no duplicate ids / members and balanced braces")
}

console.log("screentime_unit: all " + n + " checks passed")
