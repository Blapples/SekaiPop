// Saved Wi-Fi networks in the phone Quick Panel's Wi-Fi dialog: a saved network connects without a
// password and can be forgotten. Checks the wiring, and runs the shell that lists the saved
// profiles against a fake nmcli.
const assert = require("assert")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")

const root = path.join(__dirname, "..", "..")
const read = p => fs.readFileSync(path.join(root, p), "utf8")
const src = read("services/QuickSource.qml")
const dlg = read("modules/sekai/quickPanel/NetworkDialog.qml")
const face = read("modules/sekai/quickPanel/QuickPanelFace.qml")
const panel = read("modules/sekai/quickPanel/QuickPanel.qml")

// a saved network is brought up through its profile, not asked for a password
assert.ok(/wifiConnectProfile = password === "" && wifiSaved\[ssid\] !== undefined/.test(src), "connect uses the saved profile when there is no password")
assert.ok(/\["nmcli", "connection", "up", "id", root\.wifiConnectProfile\]/.test(src), "saved profile is brought up with nmcli connection up")
assert.ok(/\["nmcli", "connection", "delete", "id", root\.wifiConnectProfile\]/.test(src), "forget deletes the profile")
assert.ok(/onNetworkDialogOpenChanged: \{\s*if \(networkDialogOpen\)\s*fetchWifiSaved\(\)/.test(src), "saved list is read when the dialog opens")

// the dialog: tapping a saved network connects, right-click offers Forget, signal goes up
assert.ok(/row\.modelData\.saved === true \|\| !row\.modelData\.secured/.test(dlg), "tap on a saved network connects")
assert.ok(/acceptedButtons: Qt\.LeftButton \| Qt\.RightButton/.test(dlg), "rows take a right-click")
assert.ok(/root\.forgetRequested\(row\.modelData\.ssid\)/.test(dlg), "Forget button asks to forget")
assert.ok(/signal wifiForgetRequested\(string ssid\)/.test(face) && /onForgetRequested: ssid => face\.wifiForgetRequested\(ssid\)/.test(face), "Face passes forget up")
assert.ok(/onWifiForgetRequested: ssid => root\.source\.forgetWifi\(ssid\)/.test(panel), "QuickPanel runs forgetWifi")

// the saved-profile shell, against a fake nmcli
const m = src.match(/wifiSavedScript: (\[[\s\S]*?\]\.join\("\\n"\))/)
assert.ok(m, "wifiSavedScript found")
const script = eval(m[1])
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wifisaved-"))
fs.writeFileSync(path.join(dir, "nmcli"), `#!/bin/sh
if [ "$1" = "-t" ]; then
  printf 'Home WiFi:802-11-wireless\\nwired:802-3-ethernet\\nCafe: Free:802-11-wireless\\nVPN:vpn\\nrenamed profile:802-11-wireless\\n'
elif [ "$1" = "-g" ]; then
  case "$6" in
    "Home WiFi") echo "Home WiFi" ;;
    "Cafe: Free") echo "Cafe: Free" ;;
    "renamed profile") echo "RealSSID" ;;
  esac
fi
`, { mode: 0o755 })
const out = execFileSync("sh", ["-c", script], { env: { ...process.env, PATH: dir + ":" + process.env.PATH } }).toString()
assert.strictEqual(out, "saved|Home WiFi|Home WiFi\nsaved|Cafe: Free|Cafe: Free\nsaved|renamed profile|RealSSID\n")
console.log("wifi_saved_test: ok")
