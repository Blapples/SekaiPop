// node tests/netspeed-test/netspeed_unit.js   (run from the sekaipop folder)
//
// The bar's network speed pill (services/NetSpeedService.qml, modules/sekai/bar/NetSpeedIndicator.qml).
// Its numbers are in modules/common/functions/NetSpeedMath.js, which this runs on its own.
//   1. /proc/net/dev: which interfaces count, the sums
//   2. a speed from two readings
//   3. the text: the pill in plain KB/s (four digits at most in the normal range), the card's
//      speedText in at most four characters
//   4. history, chart bars, totals (the card)
//   5. the QML is wired to it
const fs = require("fs"), assert = require("assert")
const locate = require("../lib/locate")
const qmlcheck = require("../lib/qmlcheck")
const read = f => fs.readFileSync(locate(f), "utf8")
const src = read("modules/common/functions/NetSpeedMath.js").replace(".pragma library", "")
const N = {}
new Function("N", src + ";Object.assign(N,{ignored,parseNetDev,rate,speedText,speedLong,SPEED_TEMPLATE,kbText,kbLong,KB_TEMPLATE,pushHistory,peak,fracs,speedParts,bytesText,HISTORY});")(N)
let n = 0
const ok = (c, m) => { assert(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

// ---- 1. /proc/net/dev ----
const sample = `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  500000    1000    0    0    0     0          0         0   500000    1000    0    0    0     0       0          0
 wlan0: 1000000    2000    0    0    0     0          0         0   250000     900    0    0    0     0       0          0
  eth0:  2000000    3000    0    0    0     0          0         0   750000    1200    0    0    0     0       0          0
docker0:  99999     10    0    0    0     0          0         0    99999      10    0    0    0     0       0          0
veth1a2b: 5555      10    0    0    0     0          0         0     5555      10    0    0    0     0       0          0
   wg0:  77777     10    0    0    0     0          0         0    77777      10    0    0    0     0       0          0
br-1234: 4444      10    0    0    0     0          0         0     4444      10    0    0    0     0       0          0
`
const p = N.parseNetDev(sample)
eq(p.ifaces, ["wlan0", "eth0"], "only the real interfaces: not loopback, containers, bridges or tunnels")
eq([p.rx, p.tx], [3000000, 1000000], "their bytes are added up")
eq(N.parseNetDev("").ifaces, [], "an empty file is no interfaces")
eq(N.parseNetDev("garbage\nno colon here").rx, 0)
eq(N.parseNetDev("wlan0: 1 2 3").ifaces, [], "a line with too few fields is skipped")
eq(N.parseNetDev("wlan0: a b c d e f g h i").ifaces, [], "so is one with no numbers")
ok(N.ignored("lo") && !N.ignored("lowpan0"), "lo is the loopback, not every name that starts with it")
ok(N.ignored("") && N.ignored(null), "no name, no interface")
ok(!N.ignored("enp3s0") && !N.ignored("wlp2s0") && !N.ignored("wwan0"), "ordinary names count")

// ---- 2. a speed ----
eq(N.rate({ rx: 1000, tx: 500 }, { rx: 3000, tx: 700 }, 2), { down: 1000, up: 100 }, "bytes per second")
eq(N.rate({ rx: 5000, tx: 5000 }, { rx: 100, tx: 100 }, 2), { down: 0, up: 0 }, "a counter that went down (an interface left) is 0, not a huge number")
eq(N.rate({ rx: 0, tx: 0 }, { rx: 100, tx: 100 }, 0), { down: 0, up: 0 }, "no time passed")
eq(N.rate(null, { rx: 1, tx: 1 }, 2), { down: 0, up: 0 }, "the first reading has nothing to compare to")

// ---- 3. the text ----
const cases = [[0, "0K"], [30, "0K"], [60, "0.1K"], [500, "0.5K"], [9949, "9.9K"], [9960, "10K"], [10000, "10K"], [512000, "512K"],
               [999400, "999K"], [999600, "1.0M"], [1200000, "1.2M"], [9960000, "10M"], [85000000, "85M"], [999400000, "999M"],
               [1100000000, "1.1G"], [25000000000, "25G"], [-5, "0K"], [NaN, "0K"], ["x", "0K"]]
for (const [b, t] of cases) eq(N.speedText(b), t, b + " B/s")
for (let b = 0; b < 5e11; b = b * 1.7 + 13) ok(N.speedText(b).length <= N.SPEED_TEMPLATE.length, "never longer than the reserved width: " + N.speedText(b))
for (let i = 0; i < 20000; i++) ok(N.speedText(Math.random() * Math.pow(10, Math.random() * 12)).length <= 4, "four characters at most")
eq(N.speedLong(1200000), "1.2 MB/s")
eq(N.speedLong(0), "0 KB/s")
eq(N.speedLong(512000), "512 KB/s")

// The pill: always KB/s, never M or G.
const kb = [[0, "0"], [30, "0"], [499, "0"], [500, "1"], [60000, "60"], [512000, "512"], [999600, "1000"], [1200000, "1200"],
            [85000000, "85000"], [9999000, "9999"], [125000000, "125000"], [-5, "0"], [NaN, "0"], ["x", "0"], [null, "0"]]
for (const [b, t] of kb) eq(N.kbText(b), t, "pill: " + b + " B/s")
for (let b = 0; b < 9999500; b = b * 1.7 + 13) ok(N.kbText(b).length <= N.KB_TEMPLATE.length, "within the reserved width up to 9999 KB/s: " + N.kbText(b))
ok(/^\d+$/.test(N.kbText(Math.random() * 1e9)), "digits only: the unit is the pill's own label")
eq(N.kbLong(0), "0 KB/s"); eq(N.kbLong(512000), "512 KB/s"); eq(N.kbLong(1200000), "1200 KB/s"); eq(N.kbLong(NaN), "0 KB/s")

// ---- 4. the card ----
let h = []
for (let i = 1; i <= 70; i++) h = N.pushHistory(h, i)
eq([h.length, h[0], h[h.length - 1]], [N.HISTORY, 11, 70], "the last 60 readings, the oldest dropped")
const before = [1, 2]
N.pushHistory(before, 3)
eq(before, [1, 2], "the list passed in is not changed")
eq(N.pushHistory([], -5), [0], "nothing negative"); eq(N.pushHistory([], "x"), [0])
eq(N.peak([3, 9, 4]), 9); eq(N.peak([]), 0); eq(N.peak(null), 0)
let f = N.fracs([50000, 100000], 100000)
eq([f.length, f[58], f[59]], [60, 0.5, 1], "60 bars, the newest on the right, padded with 0 on the left")
eq(f.slice(0, 58).every(x => x === 0), true)
eq(N.fracs([1000], 100000)[59], 0.01, "a quiet minute stays short: the floor keeps it from filling the chart")
eq(N.fracs([2000000, 1000000], 100000).slice(58), [1, 0.5], "a busy one is scaled to its tallest")
eq(N.fracs([], 100000).length, 60); eq(N.fracs(null, 0).every(x => x === 0), true)
eq(N.fracs(Array(80).fill(5), 1).length, 60, "never more than 60 bars")
eq(N.speedParts(1200000), { num: "1.2", unit: "MB/s" }); eq(N.speedParts(0), { num: "0", unit: "KB/s" }); eq(N.speedParts(512000), { num: "512", unit: "KB/s" })
eq([N.bytesText(0), N.bytesText(512000), N.bytesText(1.2e6), N.bytesText(3.4e9), N.bytesText(34e9), N.bytesText(1.5e12), N.bytesText(999600), N.bytesText(-1), N.bytesText("x")],
   ["0 KB", "512 KB", "1.2 MB", "3.4 GB", "34 GB", "1.5 TB", "1.0 MB", "0 KB", "0 KB"])

// ---- 5. the QML is wired to it ----
const svc = read("services/NetSpeedService.qml")
ok(/pragma Singleton/.test(svc) && svc.includes('"/proc/net/dev"'), "a singleton reading /proc/net/dev")
ok(svc.includes('SettingsService.flag("bar.netSpeed")') && /running: root\.enabled/.test(svc), "it reads only while the pill is on")
const settings = read("services/SettingsService.qml")
ok(/"bar\.netSpeed":\s*true/.test(settings) && /netSpeed:\s*root\.flag\("bar\.netSpeed"\)/.test(settings), "a setting, and one of the bar modules")
ok(read("modules/sekai/settings/SettingsPageBar.qml").includes('"bar.netSpeed"'), "in Settings -> Bar -> Modules")
ok(/id: "netSpeed"/.test(read("services/BarLayoutService.qml")), "a layout module")
const sb = read("modules/sekai/bar/Status_Bar.qml")
ok(sb.includes('case "netSpeed": return [netSpeedIndicator]') && sb.includes("NetSpeedIndicator {") && sb.includes('status_Bar.shows("netSpeed")'), "on the bar")
const bar = read("modules/sekai/bar/Bar.qml")
ok(bar.includes("netDownText: NetSpeedService.downText") && bar.includes("onNetSpeedClicked: win.toggleNetSpeedPopup()"), "Bar feeds it and a click opens its own card")
ok(!/onNetSpeedClicked: win\.quickPanel/.test(bar), "and no longer the quick panel")
ok(/NetSpeedPopup \{/.test(bar) && bar.includes("statusBar.netSpeedToggle") && read("modules/sekai/bar/Status_Bar.qml").includes("readonly property Item netSpeedToggle: netSpeedIndicator"), "the card hangs off the pill")
ok(/win\.netSpeedPopupOpen \|\|/.test(bar), "an open card keeps an auto-hidden bar up")
// Every other popup's toggle puts this one away, and this one puts the others away: two never stack.
for (const fn of ["toggleBatteryPopup", "toggleResourcePopup", "toggleCalendarPopup", "toggleWeatherPopup", "toggleUtilPopup", "toggleMediaPopup", "toggleDiscordPopup", "togglePluginPopup", "openEqPopup", "toggleScreenTimePopup", "toggleTimerPopup"]) {
    const m = new RegExp("function " + fn + "\\([^)]*\\) \\{([\\s\\S]*?)\\n    \\}\\n").exec(bar)
    ok(m && m[1].includes("netSpeedPopupOpen = false"), fn + " puts the network card away")
}
const mine = /function toggleNetSpeedPopup\(\) \{([\s\S]*?)\n    \}\n/.exec(bar)[1]
for (const k of ["eqPopupOpen", "mediaPopupOpen", "discordPopupOpen", "batteryPopupOpen", "utilPopupOpen", "resourcePopupOpen", "screenTimePopupOpen", "timerPopupOpen", "calendarPopupOpen", "weatherPopupOpen"])
    ok(mine.includes(k + " = false"), "the network toggle puts " + k + " away")
const pop = read("modules/sekai/bar/NetSpeedPopup.qml")
ok(pop.includes("NetSpeedService.downFracs") && pop.includes("NetSpeedService.upFracs") && pop.includes("NetSpeedService.totalDown") && pop.includes("NetSpeedService.ifaces"), "the card shows the chart, totals and interfaces")
ok(/downText: NSM\.kbText\(root\.down\)/.test(svc) && /upText: NSM\.kbText\(root\.up\)/.test(svc) && /NSM\.kbLong\(root\.down\)/.test(svc), "the pill and its hover tag read in KB/s")
const svcSrc = read("services/NetSpeedService.qml")
ok(/NSM\.pushHistory\(root\.downHistory/.test(svcSrc) && /root\.totalDown \+= /.test(svcSrc), "the service keeps the history and the totals")
const ind = read("modules/sekai/bar/NetSpeedIndicator.qml")
ok(/width: root\.figuresWidth/.test(ind) && /Math\.max\(probeZero\.implicitWidth, probeEight\.implicitWidth\)/.test(ind), "the speeds sit in fixed boxes measured from the widest text")
ok(!/(downText|upText)\.implicitWidth/.test(ind), "nothing sizes the pill from the live text")
ok(ind.includes('property string sizeText: "0000"') && ind.includes('root.downText === "0"') && ind.includes('root.upText === "0"'), "the pill measures four digits and dims at 0")
ok((ind.match(/text: "KB\/s"/g) || []).length === 2, "the unit label is on both the flat and the standing bar")
ok(read("modules/sekai/bar/Status_Bar.qml").includes('property string netDownText: "0"'), "the bar's default is the plain 0")
for (const f of ["services/NetSpeedService.qml", "modules/sekai/bar/NetSpeedIndicator.qml", "modules/sekai/bar/NetSpeedPopup.qml", "modules/sekai/bar/Bar.qml"])
    eq(qmlcheck(read(f), f), [], f + " has no duplicate ids / members and balanced braces")

console.log("netspeed_unit: all " + n + " checks passed")
