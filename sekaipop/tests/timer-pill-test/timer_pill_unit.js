// node tests/timer-pill-test/timer_pill_unit.js   (run from the sekaipop folder)
//
// The bar's timer pill (modules/sekai/bar/TimerIndicator.qml, TimerPopup.qml) is a second face on
// services/TimerService.qml, the clocks the dock's Timer key already uses. The clocks themselves are
// not touched, so this only checks the wiring and the few lines TimerService gained for the pill.
const fs = require("fs"), assert = require("assert")
const locate = require("../lib/locate")
const qmlcheck = require("../lib/qmlcheck")
const read = f => fs.readFileSync(locate(f), "utf8")
let n = 0
const ok = (c, m) => { assert(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

const svc = read("services/TimerService.qml")
ok(/readonly property string shownClock/.test(svc) && /readonly property string shownTemplate/.test(svc) && /readonly property string shownTip/.test(svc), "TimerService has the pill's three texts")
ok(/root\.shownMode === "stopwatch" \|\| span >= 3600\) \? "0:00:00" : "00:00"/.test(svc), "the clock's room: hours for a stopwatch or a span of an hour or more")
ok(/function toggleTimer\(\)/.test(svc) && /function nextPhase\(keepRunning\)/.test(svc) && /interval: 200/.test(svc), "the clocks themselves are still there")

const ind = read("modules/sekai/bar/TimerIndicator.qml")
ok(/Math\.max\(probeZero\.implicitWidth, probeEight\.implicitWidth\)/.test(ind) && /width: root\.figuresWidth/.test(ind), "the clock sits in a fixed box measured from the widest clock")
ok(!/label\.implicitWidth/.test(ind), "nothing sizes the pill from the live text")
ok(/root\.running \? glyph\.width \+ root\.figuresWidth/.test(ind), "idle: just the icon; running: the icon and the clock's box")
ok(/mode === "stopwatch" \? "av_timer"/.test(ind) && /"nutrition"/.test(ind), "the icon says which one runs")

const pop = read("modules/sekai/bar/TimerPopup.qml")
for (const f of ["toggleTimer", "toggleStopwatch", "lapStopwatch", "togglePomodoro", "nextPhase", "resetPomodoro", "setTimerMinutes", "addTimerMinute"])
    ok(pop.includes("TimerService." + f), "the card drives TimerService." + f)
ok(pop.includes('import "../dock"'), "it uses the dock's buttons")
ok(/onOpenChanged:[\s\S]*TimerService\.shownMode/.test(pop), "it opens on what is already running")

const settings = read("services/SettingsService.qml")
ok(/"bar\.timer":\s*true/.test(settings) && /timer:\s*root\.flag\("bar\.timer"\)/.test(settings), "a setting, and one of the bar modules")
ok(read("modules/sekai/settings/SettingsPageBar.qml").includes('"bar.timer"'), "in Settings -> Bar -> Modules")
const layout = read("services/BarLayoutService.qml")
ok(/id: "timer"/.test(layout) && /right: \[[^\]]*"netSpeed", "screenTime", "timer", "battery"/.test(layout), "a layout module in the default right zone")
const sb = read("modules/sekai/bar/Status_Bar.qml")
ok(/right: \[[^\]]*"netSpeed", "screenTime", "timer", "battery"/.test(sb), "the bar's own default layout matches")
ok(sb.includes('case "timer": return [timerIndicator]') && sb.includes("TimerIndicator {") && sb.includes('status_Bar.shows("timer")'), "on the bar")
ok(sb.includes("readonly property Item timerToggle: timerIndicator") && sb.includes("signal timerClicked()"), "clickable and anchorable")

const bar = read("modules/sekai/bar/Bar.qml")
ok(bar.includes("function toggleTimerPopup()") && /TimerPopup \{/.test(bar) && bar.includes("statusBar.timerToggle") && bar.includes("onTimerClicked: win.toggleTimerPopup()"), "Bar opens the card from the pill")
ok(/win\.timerPopupOpen \|\|/.test(bar), "an open card keeps an auto-hidden bar up")
for (const fn of ["toggleBatteryPopup", "toggleResourcePopup", "toggleCalendarPopup", "toggleWeatherPopup", "toggleUtilPopup", "toggleMediaPopup", "toggleDiscordPopup", "togglePluginPopup", "openEqPopup", "toggleScreenTimePopup", "toggleNetSpeedPopup"]) {
    const m = new RegExp("function " + fn + "\\([^)]*\\) \\{([\\s\\S]*?)\\n    \\}\\n").exec(bar)
    ok(m && m[1].includes("timerPopupOpen = false"), fn + " puts the timer card away")
}
const mine = /function toggleTimerPopup\(\) \{([\s\S]*?)\n    \}\n/.exec(bar)[1]
for (const k of ["eqPopupOpen", "mediaPopupOpen", "discordPopupOpen", "batteryPopupOpen", "utilPopupOpen", "resourcePopupOpen", "screenTimePopupOpen", "netSpeedPopupOpen", "calendarPopupOpen", "weatherPopupOpen"])
    ok(mine.includes(k + " = false"), "the timer toggle puts " + k + " away")

for (const f of ["modules/sekai/bar/TimerIndicator.qml", "modules/sekai/bar/TimerPopup.qml", "modules/sekai/bar/Bar.qml", "modules/sekai/bar/Status_Bar.qml"])
    eq(qmlcheck(read(f), f), [], f + " has no duplicate ids / members and balanced braces")

console.log("timer_pill_unit: all " + n + " checks passed")
