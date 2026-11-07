// The phone mirror (services/PhoneMirrorService.qml, modules/sekai/phoneMirror/): its rules run
// here (PhoneMirror.js: adb parsing, the phone to pick, scrcpy options, errors, the frame's fit),
// and the wiring between the files is checked as text.
// Run: node tests/phone-mirror-test/mirror_unit.js
const fs = require("fs"), assert = require("assert")
const locate = require("../lib/locate")
const read = f => fs.readFileSync(locate(f), "utf8")
const M = new Function(read("modules/common/functions/PhoneMirror.js").replace(".pragma library", "")
    + "; return { parseDevices, pickDevice, deviceStatus, parseSize, parseVersion, normalizeAddress, keycodes,"
    + " commonArgs, embedArgs, windowArgs, streamSize, windowTitle, friendlyError, waitingText, fitPhone }")()

let n = 0
const ok = (c, m) => { assert.ok(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

// ---------- adb devices -l ----------
const out = `List of devices attached
R5CT1234ABC            device usb:1-2 product:x model:SM_S918B device:dm3q transport_id:1
192.168.1.20:5555      device product:x model:Pixel_8 device:shiba transport_id:2
emulator-5554          offline
0123456789ABCDEF       unauthorized usb:1-2 transport_id:3
* daemon started successfully *
`
const list = M.parseDevices(out)
eq(list.length, 4, "four phones, no header, no daemon line")
eq(list[0], { serial: "R5CT1234ABC", state: "device", model: "SM S918B", wireless: false }, "cable phone, model with spaces")
ok(list[1].wireless && list[1].model === "Pixel 8", "ip:port is wireless")
eq(list[2].state, "offline", "offline")
eq(M.parseDevices("List of devices attached\n\n"), [], "nothing attached")
eq(M.parseDevices("abc no permissions (user in plugdev group)\n")[0].state, "no permissions", "two-word state")
ok(M.parseDevices("adb-XYZ._adb-tls-connect._tcp device\n")[0].wireless, "mDNS name is wireless")

// ---------- which phone ----------
eq(M.pickDevice(list, "").serial, "R5CT1234ABC", "a cable beats Wi-Fi")
eq(M.pickDevice(list, "192.168.1.20:5555").serial, "192.168.1.20:5555", "the named one wins when it is ready")
eq(M.pickDevice(list, "emulator-5554").serial, "R5CT1234ABC", "a named phone that is offline is passed over")
eq(M.pickDevice([list[1]], "").serial, "192.168.1.20:5555", "Wi-Fi when it is all there is")
eq(M.pickDevice([], ""), null, "no phone")
eq(M.deviceStatus(list, ""), "ready", "ready")
eq(M.deviceStatus([list[3]], ""), "unauthorized", "asks to accept on the phone")
eq(M.deviceStatus([list[2]], ""), "offline", "offline")
eq(M.deviceStatus([], ""), "none", "none")
eq(M.deviceStatus([list[2], list[3]], ""), "unauthorized", "unauthorized is the one to act on")

// ---------- sizes, versions, addresses ----------
eq(M.parseSize("Physical size: 1080x2340\n"), { w: 1080, h: 2340 }, "wm size")
eq(M.parseSize("Physical size: 1080x2340\nOverride size: 720x1560\n"), { w: 720, h: 1560 }, "the override is what is on screen")
eq(M.parseSize("error"), null, "no size")
eq(M.parseVersion("scrcpy 3.1 <https://github.com/Genymobile/scrcpy>"), { major: 3, minor: 1 }, "version")
eq(M.parseVersion("scrcpy v2.7.1"), { major: 2, minor: 7 }, "version with a v and a patch")
eq(M.parseVersion("command not found"), null, "not scrcpy")
eq(M.normalizeAddress("192.168.1.20"), "192.168.1.20:5555", "default port")
eq(M.normalizeAddress(" 192.168.1.20:37123 "), "192.168.1.20:37123", "given port, trimmed")
eq(M.normalizeAddress("a b; rm -rf"), "", "anything odd is refused")
eq(M.normalizeAddress(""), "", "empty")

// ---------- scrcpy options ----------
const base = { stayAwake: false, turnScreenOff: false, audio: false, maxFps: 0, bitRate: "8M", keyboard: "uhid", clipboardSync: true }
eq(M.commonArgs(base), ["--no-audio", "--video-bit-rate=8M", "--keyboard=uhid"], "defaults")
eq(M.commonArgs(Object.assign({}, base, { audio: true, stayAwake: true, turnScreenOff: true, maxFps: 60, keyboard: "sdk", clipboardSync: false })),
    ["--stay-awake", "--turn-screen-off", "--max-fps=60", "--video-bit-rate=8M", "--no-clipboard-autosync"], "everything on")
const emb = M.embedArgs(base, 1200)
ok(emb[0] === "--window-borderless" && emb.includes("--max-size=1200"), "embedded: borderless and capped to the frame")
for (const bad of ["--fullscreen", "--always-on-top"]) ok(!emb.includes(bad), "embedded never moves or raises its window: " + bad)
ok(!M.embedArgs(base, 0).some(a => a.startsWith("--max-size")), "no cap when the size is unknown")
ok(!M.windowArgs(base).includes("--window-borderless"), "the separate window has its decorations")
eq(M.streamSize(0, 0, 1), 1024, "unknown frame")
eq(M.streamSize(400, 860, 1), 860, "height drives it")
eq(M.streamSize(400, 860, 2), 1440, "capped at 1440")
eq(M.streamSize(100, 100, 1), 480, "floor")
eq(M.windowTitle("embed"), "sekai-phone-embed", "title")
eq(M.windowTitle("app:x"), "sekai-phone-app_x", "colon never reaches a title")
eq(M.keycodes.home, "KEYCODE_HOME", "keys")

// ---------- messages ----------
ok(/not installed/.test(M.friendlyError("scrcpy: No such file or directory")), "scrcpy missing")
ok(/Accept/.test(M.friendlyError("Device unauthorized")), "unauthorized")
ok(/ADB/.test(M.friendlyError("Could not find any ADB device")), "no device")
ok(/disconnected/.test(M.friendlyError("Device disconnected")), "disconnect")
ok(/encoder/.test(M.friendlyError("MediaCodec error")), "encoder")
eq(M.friendlyError(""), "scrcpy closed unexpectedly", "empty")
eq(M.friendlyError("something odd"), "something odd", "unknown text is shown as it is")
ok(/PIN/.test(M.waitingText({ reason: "locked", unlockWindow: true, secure: true })), "PIN is blind")
ok(/Unlock your phone/.test(M.waitingText({ reason: "locked", unlockWindow: true, secure: false })), "unlock window")
ok(/reconnect/.test(M.waitingText({ reason: "unreachable" })), "unreachable")

// ---------- the frame ----------
const fit = M.fitPhone(600, 900, 9 / 20, 14)
eq(fit.screenH, 872, "height fills the box")
eq(fit.screenW, Math.round(872 * 9 / 20), "width follows the aspect")
eq(fit.bodyW, fit.screenW + 28, "body is the screen plus the frame")
const narrow = M.fitPhone(200, 900, 9 / 20, 14)
ok(narrow.bodyW <= 200 && Math.abs(narrow.screenW / narrow.screenH - 9 / 20) < 0.01, "a narrow box shrinks the phone and keeps its shape")
eq(M.fitPhone(600, 900, 0, 14).screenW, Math.round(872 * 9 / 20), "unknown aspect falls back to 20:9")
ok(Number.isInteger(fit.screenW) && Number.isInteger(fit.screenH), "whole pixels")

// ---------- wiring (text) ----------
const svc = read("services/PhoneMirrorService.qml"), win = read("modules/sekai/phoneMirror/PhoneMirror.qml")
const phone = read("modules/sekai/phoneMirror/MirrorPhone.qml"), shell = read("shell.qml")
const py = read("scripts/phone/scrcpy_session_manager.py"), rules = read("../hypr/hyprland/rules.lua")
const settings = read("services/SettingsService.qml"), keys = read("../hypr/hyprland/keybinds.lua")
ok(/PhoneMirror \{\}/.test(shell) && /import qs\.modules\.sekai\.phoneMirror/.test(shell), "shell starts the panel")
ok(/target: "phonemirror"/.test(svc), "ipc target")
ok(/phone\/scrcpy_session_manager\.py/.test(svc), "service starts the manager script")
ok(win.includes('WlrLayershell.namespace: "sekaipop-phonemirror"') && svc.includes('property string layerNamespace: "sekaipop-phonemirror"'), "same layer namespace on both sides")
ok(/intersection: Intersection\.Subtract/.test(win), "input hole")
ok(/captureSource/.test(phone) && /ScreencopyView/.test(phone), "picture is a capture of the window")
ok(/sekai-phone-/.test(py) && rules.includes("sekai-phone-embed") && rules.includes("sekai-phone-unlock"), "title prefix, manager and rules agree")
ok(py.includes('UNLOCK_WINDOW_TITLE = "sekai-phone-unlock"'), "unlock title")
ok(/phonemirror toggle/.test(keys), "keybind")
// every option the service or the panel reads is declared
const used = new Set()
for (const src of [svc, win, read("modules/sekai/settings/SettingsPageQuick.qml")])
    for (const m of src.matchAll(/"(phoneMirror\.[A-Za-z]+)"/g)) used.add(m[1])
ok(used.size >= 12, "options are read")
for (const k of used) ok(new RegExp('"' + k.replace(".", "\\.") + '":').test(settings), "declared in SettingsService: " + k)
ok(!/KdeConnect/.test(svc + win + phone), "no KDE Connect left over from the port")

// ---------- the picture is not interrupted (workspace change, a layer opening) ----------
const presets = read("services/DesktopPresetService.qml")
const rawBlock = svc.slice(svc.indexOf("function onRawEvent"), svc.indexOf("Timer {\n        id: recheckTimer"))
const arm = (x, name) => x.slice(x.indexOf('case "' + name + '"'))
ok(!/_placedAttached = false/.test(rawBlock.slice(rawBlock.indexOf('case "workspace"'))), "a workspace / layer event no longer throws the placement away")
ok(/case "workspace":[\s\S]*?_recheckSoon\(\)/.test(rawBlock) && /case "openlayer":/.test(rawBlock), "they only start a look")
ok(/case "monitoradded":[\s\S]*?_placedAttached = false/.test(rawBlock), "a monitor change still re-places")
ok(/function _readStill[\s\S]*?_placedAttached = false/.test(svc), "the window is put again only when the look shows it moved")
ok(/_recheckSoon\(\): void \{[\s\S]*?!root\.placementOk/.test(svc), "no look while a placement is being checked")
ok(/captureSource: \(PhoneMirrorService\.attached && PhoneMirrorService\.captureReady/.test(phone), "the capture follows captureReady")
ok(!/captureSource:[^\n]*placementOk/.test(phone), "the capture is not tied to placementOk")
ok(/touchActive: win\.placementWanted && phone\.capturing && PhoneMirrorService\.placementOk/.test(win), "the click-through hole still needs placementOk")
ok(/root\.placementOk = true\n\s*root\.captureReady = true/.test(svc), "captureReady is raised by a verified placement")
ok(/if \(!root\.shown\)\n\s*root\.captureReady = false/.test(svc), "captureReady drops when the panel goes away")
ok(/hadPicture/.test(phone) && /lostTimer/.test(phone), "a blink of the picture does not flash the waiting card")

// ---------- presets leave the phone mirror alone ----------
const keepPrefix = presets.slice(presets.indexOf("readonly property var keepPrefix"), presets.indexOf("// True for a Settings Panel key"))
ok(keepPrefix.includes('"phoneMirror."'), "a preset never reads or writes phoneMirror.* (sound, notch, address ...)")

console.log("phone mirror: " + n + " checks passed")
