// Wi-Fi dialog in the phone Quick Panel: opening it must show the networks at once AND start a
// rescan by itself, and pressing "Scan" must never be swallowed by a read that is already running.
// Checks the wiring, and runs the list-sorting code from QuickSource.qml on sample scans.
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..", "..")
const read = p => fs.readFileSync(path.join(root, p), "utf8")
const src = read("services/QuickSource.qml")
const dlg = read("modules/sekai/quickPanel/NetworkDialog.qml")
const panel = read("modules/sekai/quickPanel/QuickPanel.qml")

// ---- wiring
// opening the dialog starts the rescan; so does the Scan button
assert.ok(/if \(networkDialogOpen\)\s*root\.source\.scanWifi\(true\)/.test(panel), "opening the Wi-Fi dialog starts a rescan")
assert.ok(/onWifiScanRequested: root\.source\.scanWifi\(true\)/.test(panel), "Scan button starts a rescan")
// the rescan is its own process: a read in flight can't swallow the press any more
assert.ok(/id: wifiRescanAction/.test(src), "rescan is its own process")
assert.ok(!/wifiForceRescan/.test(src), "no more shared 'force rescan' flag on the list process")
const startFn = src.match(/function startWifiRescan\(\) \{([\s\S]*?)\n    \}/)
assert.ok(startFn, "startWifiRescan found")
assert.ok(/wifiRescanAction\.running = true/.test(startFn[1]), "startWifiRescan asks for the rescan before anything can return early")
assert.ok(/fetchWifiList\(\)/.test(startFn[1]), "startWifiRescan shows the cached list at once")
assert.ok(/wifiBurstTimer\.restart\(\)/.test(startFn[1]), "startWifiRescan keeps reading while the radio scans")
// no blocking sleep in front of the list any more
assert.ok(!/sleep 2/.test(src), "no fixed 2 s sleep before the list")
// the burst ends, and closing the dialog ends it too
assert.ok(/root\.wifiBurstLeft <= 0\)\s*root\.stopWifiRescan\(\)/.test(src), "burst stops by itself")
assert.ok(/else\s*stopWifiRescan\(\)/.test(src), "closing the dialog stops the burst")
// only one handler for the dialog-open signal (QML refuses duplicates)
assert.strictEqual((src.match(/onNetworkDialogOpenChanged:/g) || []).length, 1, "one onNetworkDialogOpenChanged in QuickSource")
// live refresh waits while the burst runs
assert.ok(/running: root\.active && root\.networkDialogOpen && !root\.wifiManualScanning/.test(src), "live refresh pauses during the burst")
// the dialog says what it is doing
assert.ok(/Looking for networks…/.test(dlg), "empty list says it is looking while a scan runs")

// braces / brackets / parentheses balance (no qmllint here). QuickSource.qml is checked only
// over its Wi-Fi section: the rough counter is off by two on the rest of that big file already.
const wifiPart = src.slice(src.indexOf("// ===== Wi-Fi network list"), src.indexOf("    Process {\n        id: wifiConnectAction"))
for (const [name, text] of [["QuickSource.qml (Wi-Fi part)", wifiPart], ["NetworkDialog.qml", dlg], ["QuickPanel.qml", panel]]) {
    const stripped = text.replace(/\/\/.*$/gm, "").replace(/"(?:\\.|[^"\\])*"/g, '""')
    for (const [o, c] of [["{", "}"], ["[", "]"], ["(", ")"]])
        assert.strictEqual(stripped.split(o).length, stripped.split(c).length, name + ": " + o + c + " balance")
}

// ---- the list code, on sample scans
const fn = src.match(/function applyWifiList\(text\) \{([\s\S]*?)\n    \}\n\n    Process \{\n        id: wifiSavedAction/)
assert.ok(fn, "applyWifiList found")
function makeSource() {
    const ctx = { wifiSeen: [], annotateWifi() {} }
    // eslint-disable-next-line no-new-func
    ctx.applyWifiList = new Function("ctx", "text", "with (ctx) {" + fn[1] + "}").bind(null, ctx)
    return ctx
}
const line = (sig, sec, inuse, ssid) => `${sig}|${sec}|${inuse}|${ssid}`

// connected first, then strongest; the same name from two APs becomes one row (the connected / stronger one)
let s = makeSource()
s.applyWifiList([line(40, "WPA2", "", "Cafe"), line(80, "WPA2", "", "Cafe"), line(70, "", "", "Open"),
                 line(30, "WPA2", "*", "Home"), line(90, "WPA3", "", "Neighbor")].join("\n"))
assert.deepStrictEqual(s.wifiSeen.map(n => n.ssid), ["Home", "Neighbor", "Cafe", "Open"].sort((a, b) => 0) && ["Home", "Neighbor", "Cafe", "Open"])
assert.strictEqual(s.wifiSeen.find(n => n.ssid === "Cafe").signal, 80, "the stronger copy of a name is kept")
assert.strictEqual(s.wifiSeen.find(n => n.ssid === "Open").secured, false)
assert.strictEqual(s.wifiSeen.find(n => n.ssid === "Home").connected, true)

// a name with colons in it survives (the shell joins it back), an empty name is dropped
s = makeSource()
s.applyWifiList([line(50, "WPA2", "", "a:b:c"), line(60, "WPA2", "", "")].join("\n"))
assert.deepStrictEqual(s.wifiSeen.map(n => n.ssid), ["a:b:c"])

// a second read a second later: a signal moving a little does not shuffle the rows
s = makeSource()
s.applyWifiList([line(62, "WPA2", "", "One"), line(60, "WPA2", "", "Two"), line(61, "WPA2", "", "Three")].join("\n"))
const first = s.wifiSeen.map(n => n.ssid)
s.applyWifiList([line(58, "WPA2", "", "One"), line(63, "WPA2", "", "Two"), line(59, "WPA2", "", "Three")].join("\n"))
assert.deepStrictEqual(s.wifiSeen.map(n => n.ssid), first, "rows keep their place on small signal changes")

// a network found by the rescan shows up in the next read, in the right place
s.applyWifiList([line(58, "WPA2", "", "One"), line(63, "WPA2", "", "Two"), line(59, "WPA2", "", "Three"), line(95, "WPA3", "", "NewStrong")].join("\n"))
assert.strictEqual(s.wifiSeen[0].ssid, "NewStrong")
assert.strictEqual(s.wifiSeen.length, 4)

// the list the dialog shows is only replaced when something it shows changed (3 signal bars, lock, connected, saved)
const ann = src.match(/function annotateWifi\(\) \{([\s\S]*?)\n    \}\n\n    function fetchWifiSaved/)
assert.ok(ann, "annotateWifi found")
const a = { wifiSaved: { Home: "Home" }, wifiNetworks: [], wifiSeen: [] }
a.annotate = new Function("ctx", "with (ctx) {" + ann[1] + "}").bind(null, a)
const net = (ssid, signal, extra) => ({ ssid, signal, secured: true, connected: false, ...extra })
a.wifiSeen = [net("Home", 70), net("Cafe", 40)]
a.annotate()
const shown = a.wifiNetworks
assert.strictEqual(shown.length, 2)
assert.strictEqual(shown[0].saved, true)
a.wifiSeen = [net("Home", 72), net("Cafe", 38)]
a.annotate()
assert.strictEqual(a.wifiNetworks, shown, "a few points of signal is not a change")
a.wifiSeen = [net("Home", 72), net("Cafe", 20)]
a.annotate()
assert.notStrictEqual(a.wifiNetworks, shown, "a drop to fewer bars is a change")

console.log("wifi_scan_test: ok")
