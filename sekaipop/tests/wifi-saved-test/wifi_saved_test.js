// Saved Wi-Fi networks in the phone Quick Panel's Wi-Fi dialog: a saved network connects without a
// password and can be forgotten. Checks the wiring, and runs the helper that lists the saved
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
assert.ok(/wifiProfileUuid = password === "" \? .*profileUuid/.test(src), "connect uses the saved profile when there is no password")
assert.ok(/\["nmcli", "connection", "up", "uuid", root\.wifiProfileUuid\]/.test(src), "saved profile is brought up with nmcli connection up")
assert.ok(/\["nmcli", "connection", "delete", "uuid", root\.wifiProfileUuid\]/.test(src), "forget deletes the profile")
assert.ok(/onNetworkDialogOpenChanged: \{\s*if \(networkDialogOpen\)\s*fetchWifiSaved\(\)/.test(src), "saved list is read when the dialog opens")

// the dialog: tapping a saved network connects, right-click offers Forget, signal goes up
assert.ok(/row\.modelData\.saved === true \|\| !row\.modelData\.secured/.test(dlg), "tap on a saved network connects")
assert.ok(/acceptedButtons: Qt\.LeftButton \| Qt\.RightButton/.test(dlg), "rows take a right-click")
assert.ok(/root\.forgetRequested\(row\.modelData\.profileUuid\)/.test(dlg), "Forget button asks to forget")
assert.ok(/signal wifiForgetRequested\(string uuid\)/.test(face) && /onForgetRequested: uuid => face\.wifiForgetRequested\(uuid\)/.test(face), "Face passes forget up")
assert.ok(/onWifiForgetRequested: uuid => root\.source\.forgetWifi\(uuid\)/.test(panel), "QuickPanel runs forgetWifi")

// Exercise the profile helper with a fake nmcli.
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wifisaved-"))
try {
    fs.writeFileSync(path.join(dir, "nmcli"), `#!/bin/sh
case "$*" in
  *UUID,TYPE,ACTIVE*) printf 'old:wifi:no\\nactive:802-11-wireless:yes\\nenterprise:wifi:no\\nshare:wifi:no\\nwired:ethernet:yes\\n' ;;
  *"uuid old") printf 'Cafe:Lab|West\\nwpa-psk\\ninfrastructure\\n' ;;
  *"uuid active") printf 'Cafe:Lab|West\\nwpa-psk\\ninfrastructure\\n' ;;
  *"uuid enterprise") printf 'Cafe:Lab|West\\nwpa-eap\\ninfrastructure\\n' ;;
  *"uuid share") printf 'Cafe:Lab|West\\nwpa-psk\\nap\\n' ;;
  *) exit 1 ;;
esac
`, { mode: 0o755 })
    const output = execFileSync("python3", [path.join(root, "scripts/system/wifi-saved-profiles.py")],
        { env: { ...process.env, PATH: dir + ":" + process.env.PATH }, encoding: "utf8" })

    const ctx = {
        wifiSaved: {}, wifiNetworks: [],
        wifiSeen: [
            { ssid: "Cafe:Lab|West", securityKind: "personal", connected: true, secured: true, signal: 80 },
            { ssid: "Cafe:Lab|West", securityKind: "enterprise", connected: false, secured: true, signal: 60 },
            { ssid: "Cafe:Lab|West", securityKind: "open", connected: false, secured: false, signal: 40 },
        ],
    }
    for (const name of ["applyWifiSaved", "annotateWifi", "forgetWifi", "disconnectWifi"]) {
        const match = src.match(new RegExp("function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}"))
        assert.ok(match, name + " found")
        ctx[name] = new Function("ctx", ...match[1].split(",").map(s => s.trim()).filter(Boolean),
            "with (ctx) {" + match[2] + "}").bind(null, ctx)
    }
    ctx.applyWifiSaved(output)
    assert.deepStrictEqual(ctx.wifiNetworks.map(n => n.profileUuid), ["active", "enterprise", ""])
    assert.deepStrictEqual(ctx.wifiNetworks.map(n => n.activeProfileUuid), ["active", "", ""])
    assert.ok(!JSON.parse(output).some(p => p.uuid === "share" || p.uuid === "wired"))
    const shown = ctx.wifiNetworks
    ctx.applyWifiSaved("")
    assert.strictEqual(ctx.wifiNetworks, shown, "failed reads retain the previous profiles")
    Object.assign(ctx, {
        wifiActionRunning: false, actionGen: 0, wifiConnectError: "", wifiProfileUuid: "",
        wifiForgetAction: { running: false }, wifiDisconnectAction: { running: false },
    })
    ctx.forgetWifi("share")
    assert.strictEqual(ctx.wifiForgetAction.running, false, "unknown UUID cannot be deleted")
    ctx.forgetWifi("enterprise")
    assert.strictEqual(ctx.wifiProfileUuid, "enterprise", "Forget acts on the selected profile UUID")
    assert.strictEqual(ctx.wifiForgetAction.running, true)
    ctx.disconnectWifi("Cafe:Lab|West")
    assert.strictEqual(ctx.wifiProfileUuid, "active", "Disconnect acts on the active UUID")
} finally {
    fs.rmSync(dir, { recursive: true, force: true })
}
console.log("wifi_saved_test: ok")
