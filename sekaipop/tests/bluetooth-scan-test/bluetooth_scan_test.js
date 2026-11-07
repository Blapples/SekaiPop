// Bluetooth dialog in the phone Quick Panel: opening it shows the paired devices at once AND looks for
// nearby ones, a tap on a nearby device pairs it, and right-click on a paired one can forget it. Checks the wiring, runs the list script and the
// pairing script from QuickSource.qml against a fake bluetoothctl, and runs the list code on sample data.
const assert = require("assert")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")

const root = path.join(__dirname, "..", "..")
const read = p => fs.readFileSync(path.join(root, p), "utf8")
const src = read("services/QuickSource.qml")
const dlg = read("modules/sekai/quickPanel/BluetoothDialog.qml")
const panel = read("modules/sekai/quickPanel/QuickPanel.qml")

// ---- wiring
assert.ok(/if \(bluetoothDialogOpen\)\s*root\.source\.scanBluetooth\(true\)/.test(panel), "opening the dialog looks for devices")
assert.ok(/onBluetoothScanRequested: root\.source\.scanBluetooth\(true\)/.test(panel), "Scan looks for devices")
assert.ok(/id: bluetoothDiscoverAction/.test(src), "discovery is its own process")
const startFn = src.match(/function startBluetoothScan\(\) \{([\s\S]*?)\n    \}/)
assert.ok(startFn && /bluetoothDiscoverAction\.running = true/.test(startFn[1]) && /fetchBluetoothList\(\)/.test(startFn[1]) && /bluetoothBurstTimer\.restart\(\)/.test(startFn[1]), "start: discovery, cached list, burst")
assert.ok(/root\.bluetoothBurstLeft <= 0\)\s*root\.stopBluetoothScan\(\)/.test(src), "burst stops by itself")
assert.strictEqual((src.match(/onBluetoothDialogOpenChanged:/g) || []).length, 1, "one onBluetoothDialogOpenChanged in QuickSource")
assert.ok(/onBluetoothDialogOpenChanged: if \(!bluetoothDialogOpen\) stopBluetoothScan\(\)/.test(src), "closing the dialog stops the discovery")
assert.ok(/running: root\.active && root\.bluetoothDialogOpen && !root\.bluetoothManualScanning/.test(src), "live refresh pauses during the burst")
// a tap on a device that is not paired goes through the pairing process, a paired one through connect
const conn = src.match(/function connectBluetoothDevice\(address\) \{([\s\S]*?)\n    \}/)
assert.ok(conn && /d\.paired === false/.test(conn[1]) && /bluetoothPairAction\.running = true/.test(conn[1]) && /bluetoothConnectAction\.running = true/.test(conn[1]), "tap: pair when not paired, else connect")
assert.ok(/\["sh", "-c", root\.bluetoothPairScript, "sh", root\.bluetoothConnectAddress\]/.test(src), "address goes in as an argument, not into the script text")
// forget: dialog signal -> Face -> QuickPanel -> QuickSource; only a paired device can be forgotten
const face = read("modules/sekai/quickPanel/QuickPanelFace.qml")
assert.ok(/signal forgetRequested\(string address\)/.test(dlg) && /root\.forgetRequested\(row\.modelData\.address\)/.test(dlg), "dialog asks to forget")
assert.ok(/acceptedButtons: Qt\.LeftButton \| Qt\.RightButton/.test(dlg) && /Qt\.RightButton\) \{\s*if \(row\.hasActions\)/.test(dlg), "right-click opens the actions of a paired device")
assert.ok(/signal bluetoothForgetRequested\(string address\)/.test(face) && /onForgetRequested: address => face\.bluetoothForgetRequested\(address\)/.test(face), "Face passes forget up")
assert.ok(/onBluetoothForgetRequested: address => root\.source\.forgetBluetoothDevice\(address\)/.test(panel), "QuickPanel runs forgetBluetoothDevice")
const forgetFn = src.match(/function forgetBluetoothDevice\(address\) \{([\s\S]*?)\n    \}/)
assert.ok(forgetFn && /d\.paired !== true/.test(forgetFn[1]) && /bluetoothForgetAction\.running = true/.test(forgetFn[1]), "only a paired device is forgotten")
assert.ok(/\["sh", "-c", root\.bluetoothForgetScript, "sh", root\.bluetoothConnectAddress\]/.test(src), "forget: address goes in as an argument")
assert.ok(/Forget/.test(dlg) && /right-click to forget/.test(dlg), "dialog words for forget")
assert.ok(/Looking for devices…/.test(dlg) && /Nearby — tap to pair/.test(dlg) && /Pairing…/.test(dlg), "dialog words")

// brackets balance over the Bluetooth part of QuickSource and the two QML files (no qmllint here)
const btPart = src.slice(src.indexOf("    property var bluetoothDevices: []"), src.indexOf("    // ===== Audio device picker"))
for (const [name, text] of [["QuickSource.qml (Bluetooth part)", btPart], ["BluetoothDialog.qml", dlg], ["QuickPanel.qml", panel]]) {
    const stripped = text.replace(/\/\/.*$/gm, "").replace(/"(?:\\.|[^"\\])*"/g, '""')
    for (const [o, c] of [["{", "}"], ["[", "]"], ["(", ")"]])
        assert.strictEqual(stripped.split(o).length, stripped.split(c).length, name + ": " + o + c + " balance")
}

// ---- the shell scripts, against a fake bluetoothctl
const grab = name => eval(src.match(new RegExp(name + ": (\\[[\\s\\S]*?\\]\\.join\\(\"\\\\n\"\\))"))[1])
const listScript = grab("bluetoothListScript")
const pairScript = grab("bluetoothPairScript")
assert.ok(/bluetoothDiscoverScript: "exec timeout \d+ bluetoothctl --timeout \d+ scan on/.test(src), "discovery command")

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "btscan-"))
fs.writeFileSync(path.join(dir, "bluetoothctl"), `#!/bin/sh
case "$1" in
  devices)
    case "$2" in
      Paired|Connected) printf 'Device AA:AA:AA:AA:AA:01 My Headset\\n' ;;
      *) printf 'Device AA:AA:AA:AA:AA:01 My Headset\\nDevice BB:BB:BB:BB:BB:02 Speaker | X\\nDevice CC:CC:CC:CC:CC:03 CC-CC-CC-CC-CC-03\\nDevice DD:DD:DD:DD:DD:04 \\n' ;;
    esac ;;
  info)
    case "$2" in
      AA:AA:AA:AA:AA:01) printf 'Paired: yes\\n\\tBattery Percentage: 0x50 (80)\\n' ;;
      BB:BB:BB:BB:BB:02) [ -f "$FAKE_DIR/paired" ] && printf 'Paired: yes\\n' || printf 'Paired: no\\n' ;;
    esac ;;
  remove)
    [ "$FAKE_REMOVE_OK" = 1 ] && echo "[DEL] Device $2 Speaker" && echo "Device has been removed" || echo "Failed to remove device: org.bluez.Error.DoesNotExist" ;;
  "")
    while read -r l; do
      case "$l" in "pair "*) [ "$FAKE_PAIR_OK" = 1 ] && touch "$FAKE_DIR/paired" ;; esac
      case "$l" in agent*|default-agent|pair*|trust*|connect*) echo "$l" >> "$FAKE_DIR/log" ;; esac
    done ;;
esac
`, { mode: 0o755 })
const env = extra => ({ ...process.env, PATH: dir + ":" + process.env.PATH, FAKE_DIR: dir, ...extra })

// paired first, then nearby named ones; the unnamed beacon and the nameless device are left out
const out = execFileSync("sh", ["-c", listScript], { env: env({}) }).toString()
assert.strictEqual(out, "AA:AA:AA:AA:AA:01|1|80|1|My Headset\nBB:BB:BB:BB:BB:02|0||0|Speaker | X\n")

// pairing: speed the waits up for the test only
const fast = pairScript.replace("-lt 25", "-lt 3").replace("sleep 5", "sleep 0")
const run = (script, mac, extra) => {
    try { return { code: 0, err: "", out: execFileSync("sh", ["-c", script, "sh", mac], { env: env(extra), stdio: ["ignore", "pipe", "pipe"] }).toString() } }
    catch (e) { return { code: e.status, err: String(e.stderr) } }
}
let r = run(fast, "BB:BB:BB:BB:BB:02", { FAKE_PAIR_OK: "1" })
assert.strictEqual(r.code, 0, "a device that pairs: exit 0")
const log = fs.readFileSync(path.join(dir, "log"), "utf8")
assert.ok(/agent NoInputNoOutput\ndefault-agent\npair BB:BB:BB:BB:BB:02\ntrust BB:BB:BB:BB:BB:02\nconnect BB:BB:BB:BB:BB:02/.test(log), "agent, pair, trust, connect in that order")
fs.unlinkSync(path.join(dir, "paired"))
r = run(fast, "BB:BB:BB:BB:BB:02", { FAKE_PAIR_OK: "0" })
assert.strictEqual(r.code, 1, "a device that does not pair: exit 1")
assert.ok(/Could not pair/.test(r.err) && /Advanced/.test(r.err), "and says what to do")
r = run(fast, "x; touch " + path.join(dir, "pwned"), {})
assert.strictEqual(r.code, 2, "a bad address is refused")
assert.ok(!fs.existsSync(path.join(dir, "pwned")), "and nothing in it runs")

// forgetting
const forgetScript = grab("bluetoothForgetScript")
r = run(forgetScript, "BB:BB:BB:BB:BB:02", { FAKE_REMOVE_OK: "1" })
assert.strictEqual(r.code, 0, "forget: exit 0 when BlueZ says the device was removed")
r = run(forgetScript, "BB:BB:BB:BB:BB:02", { FAKE_REMOVE_OK: "0" })
assert.strictEqual(r.code, 1, "forget: exit 1 when it was not")
assert.ok(/Could not forget/.test(r.err), "and says so")
r = run(forgetScript, "x; touch " + path.join(dir, "pwned2"), {})
assert.strictEqual(r.code, 2, "forget: a bad address is refused")
assert.ok(!fs.existsSync(path.join(dir, "pwned2")), "and nothing in it runs")

// ---- the list code, on sample data
const fn = src.match(/function applyBluetoothList\(text\) \{([\s\S]*?)\n    \}\n\n    Process \{\n        id: bluetoothListAction/)
assert.ok(fn, "applyBluetoothList found")
function makeSource() {
    const ctx = { bluetoothDevices: [] }
    ctx.apply = new Function("ctx", "text", "with (ctx) {" + fn[1] + "}").bind(null, ctx)
    return ctx
}
let s = makeSource()
s.apply(["11|0||0|Zed", "22|0||1|Paired One", "33|1|55|1|Live", "44|0||0|Alpha", "bad line"].join("\n"))
assert.deepStrictEqual(s.bluetoothDevices.map(d => d.address), ["33", "22", "44", "11"], "connected, paired, then nearby by name")
assert.strictEqual(s.bluetoothDevices[0].battery, 55)
assert.strictEqual(s.bluetoothDevices[1].battery, -1)
assert.strictEqual(s.bluetoothDevices[2].paired, false)
// a new device found a second later goes to the end of its group; the others keep their place
s.apply(["11|0||0|Zed", "22|0||1|Paired One", "33|1|55|1|Live", "44|0||0|Alpha", "55|0||0|Beta"].join("\n"))
assert.deepStrictEqual(s.bluetoothDevices.map(d => d.address), ["33", "22", "44", "11", "55"])
// a device that just got paired moves up into the paired group
s.apply(["11|0||0|Zed", "22|0||1|Paired One", "33|1|55|1|Live", "44|0||1|Alpha", "55|0||0|Beta"].join("\n"))
assert.deepStrictEqual(s.bluetoothDevices.map(d => d.address), ["33", "22", "44", "11", "55"])

// the same read again: the list the dialog shows is not replaced (that would reset its scroll and opened row)
const keep = s.bluetoothDevices
s.apply(["11|0||0|Zed", "22|0||1|Paired One", "33|1|55|1|Live", "44|0||1|Alpha", "55|0||0|Beta"].join("\n"))
assert.strictEqual(s.bluetoothDevices, keep, "an identical read keeps the same list")
s.apply(["11|0||0|Zed", "22|0||1|Paired One", "33|1|54|1|Live", "44|0||1|Alpha", "55|0||0|Beta"].join("\n"))
assert.notStrictEqual(s.bluetoothDevices, keep, "a changed battery level is a new list")

console.log("bluetooth_scan_test: ok")
