.pragma library

// The phone mirror's rules, with no Quickshell in them (tests/phone-mirror-test runs this
// file in node). services/PhoneMirrorService.qml asks it what the phone's state is, which
// scrcpy options to build and what an error means; the window only draws the answers.
//
// The scrcpy part of this is a port of p3drovfx's illogical-impulse phone mirror
// (PhoneScrcpyService / PhoneMirrorService), without KDE Connect: the phone is found with
// `adb devices` alone, over USB or over Wi-Fi.

// ---------- adb ----------

// `adb devices -l`:
//   List of devices attached
//   R5CT1234ABC            device usb:1-2 product:x model:SM_S918B device:dm3q transport_id:1
//   192.168.1.20:5555      device product:x model:Pixel_8 device:shiba transport_id:2
//   emulator-5554          offline
//   0123456789ABCDEF       unauthorized usb:1-2 transport_id:3
// Returns [{ serial, state, model, wireless }]. `state` is adb's word for it: "device"
// (ready), "unauthorized", "offline", "no permissions", ...
function parseDevices(text) {
    var out = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line === "" || line.indexOf("List of") === 0 || line.charAt(0) === "*")
            continue
        var parts = line.split(/\s+/)
        if (parts.length < 2)
            continue
        var serial = parts[0]
        var state = parts[1]
        // "no permissions (user in plugdev group; ...)" is one state of several words.
        if (state === "no" && parts[2] === "permissions")
            state = "no permissions"
        var model = ""
        for (var j = 2; j < parts.length; j++) {
            if (parts[j].indexOf("model:") === 0)
                model = parts[j].substring(6).replace(/_/g, " ")
        }
        out.push({
            serial: serial,
            state: state,
            model: model,
            // 192.168.1.20:5555 or an mDNS name ("adb-XXXX._adb-tls-connect._tcp")
            wireless: serial.indexOf(":") >= 0 || serial.indexOf("._adb-tls-") >= 0
        })
    }
    return out
}

// The phone to mirror: the one the user named, else the first that is ready, a cable
// before Wi-Fi (a wireless-debugging port goes stale, a cable does not).
function pickDevice(devices, wanted) {
    var ready = (devices || []).filter(function (d) { return d.state === "device" })
    if (wanted) {
        for (var i = 0; i < ready.length; i++) {
            if (ready[i].serial === wanted)
                return ready[i]
        }
    }
    for (var k = 0; k < ready.length; k++) {
        if (!ready[k].wireless)
            return ready[k]
    }
    return ready.length > 0 ? ready[0] : null
}

// Why there is no phone to mirror: "ready" | "unauthorized" | "offline" | "none".
function deviceStatus(devices, wanted) {
    if (pickDevice(devices, wanted))
        return "ready"
    var list = devices || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].state === "unauthorized" || list[i].state === "no permissions")
            return "unauthorized"
    }
    return list.length > 0 ? "offline" : "none"
}

// `adb shell wm size`: "Physical size: 1080x2340" and, when set, "Override size: ...".
// The override is what is on the screen, so the last one counts.
function parseSize(text) {
    var found = String(text || "").match(/(\d+)x(\d+)/g)
    if (!found || found.length === 0)
        return null
    var last = found[found.length - 1].split("x")
    var w = parseInt(last[0]), h = parseInt(last[1])
    return (w > 0 && h > 0) ? { w: w, h: h } : null
}

// "scrcpy 3.1 <https://github.com/Genymobile/scrcpy>" -> { major, minor }.
function parseVersion(line) {
    var m = String(line || "").match(/^scrcpy\s+v?(\d+)\.(\d+)(?:\.(\d+))?/)
    return m ? { major: parseInt(m[1]), minor: parseInt(m[2]) } : null
}

// "192.168.1.20" -> "192.168.1.20:5555"; "host:port" stays; anything else is refused.
function normalizeAddress(text) {
    var s = String(text || "").trim()
    if (s === "")
        return ""
    var m = s.match(/^([A-Za-z0-9._-]+)(?::(\d{2,5}))?$/)
    if (!m)
        return ""
    return m[1] + ":" + (m[2] || "5555")
}

// ---------- scrcpy ----------

// The keys the phone's side buttons and the key row send (`adb shell input keyevent`).
var keycodes = {
    back: "KEYCODE_BACK",
    home: "KEYCODE_HOME",
    recents: "KEYCODE_APP_SWITCH",
    power: "KEYCODE_POWER",
    volumeUp: "KEYCODE_VOLUME_UP",
    volumeDown: "KEYCODE_VOLUME_DOWN"
}

// Options for any session, from the options the user set (SettingsService, `phoneMirror.*`).
// `o` = { stayAwake, turnScreenOff, audio, maxFps, bitRate, keyboard, clipboardSync }.
function commonArgs(o) {
    var args = []
    if (o.stayAwake) args.push("--stay-awake")
    if (o.turnScreenOff) args.push("--turn-screen-off")
    if (!o.audio) args.push("--no-audio")
    if (o.maxFps > 0) args.push("--max-fps=" + Math.round(o.maxFps))
    if (o.bitRate) args.push("--video-bit-rate=" + o.bitRate)
    // A UHID keyboard is a real hardware keyboard to the phone: accents, dead keys and the
    // PC's layout work. "sdk" is scrcpy's older injected text, for phones that refuse UHID.
    // The mouse stays scrcpy's default on purpose: a UHID mouse would capture the pointer.
    if (o.keyboard === "uhid") args.push("--keyboard=uhid")
    if (!o.clipboardSync) args.push("--no-clipboard-autosync")
    return args
}

// The mirror drawn inside the panel. The window is moved, sized and covered by the panel, so
// everything that would move or raise it is left out on purpose (no --fullscreen, no
// --always-on-top, no --max-size from the settings): `streamSize` caps what is encoded to what
// the panel shows.
function embedArgs(o, streamSize) {
    var args = ["--window-borderless"]
    if (streamSize > 0) args.push("--max-size=" + streamSize)
    return args.concat(commonArgs(o))
}

// The same phone in a window of its own (the "Open in a window" key).
function windowArgs(o) {
    return commonArgs(o)
}

// The encoded size is capped to what the panel shows: a phone streaming 2340 pixels into a
// 700-pixel frame spends its whole budget on pixels that are thrown away at the first scale.
// scrcpy caps the longer side, which is the height for a phone held upright.
function streamSize(rectW, rectH, devicePixelRatio) {
    var side = Math.round(Math.max(rectW, rectH))
    if (side <= 0)
        return 1024
    var dpr = Math.max(1, Math.min(2, devicePixelRatio || 1))
    return Math.max(480, Math.min(1440, Math.round(side * dpr)))
}

// The window's title, so Hyprland's rules and the shell can find it. Rules for it are in
// hypr/hyprland/rules.lua, keep them in step.
function windowTitle(sessionId) {
    return "sekai-phone-" + String(sessionId).replace(/:/g, "_")
}

// scrcpy's own messages are written for a terminal; say what to do.
function friendlyError(raw) {
    var text = String(raw || "").trim()
    var lower = text.toLowerCase()
    if (lower.length === 0)
        return "scrcpy closed unexpectedly"
    if (lower.indexOf("no such file") >= 0 && lower.indexOf("scrcpy") >= 0)
        return "scrcpy is not installed"
    if (lower.indexOf("unauthorized") >= 0)
        return "USB debugging is not allowed yet. Accept the question on the phone."
    if (lower.indexOf("could not find any adb device") >= 0 || lower.indexOf("no devices") >= 0
            || lower.indexOf("not reachable over adb") >= 0 || lower.indexOf("device offline") >= 0)
        return "The phone cannot be reached over ADB. Check the cable or the wireless debugging."
    if (lower.indexOf("stayed locked") >= 0)
        return "The phone stayed locked. Unlock it and try again."
    if (lower.indexOf("unlock window was closed") >= 0)
        return "The unlock window was closed before the phone was unlocked."
    if (lower.indexOf("device disconnected") >= 0 || lower.indexOf("connection lost") >= 0)
        return "The phone disconnected."
    if (lower.indexOf("encoder") >= 0 || lower.indexOf("mediacodec") >= 0 || lower.indexOf("video stream") >= 0)
        return "The phone's video encoder failed. Try a lower bit rate."
    if (lower.indexOf("audio") >= 0)
        return "Audio capture failed. Turn the phone's sound off in the settings."
    if (lower.indexOf("server connection failed") >= 0 || lower.indexOf("could not push") >= 0)
        return "Could not start scrcpy on the phone. Plug it in again and try once more."
    if (lower.indexOf("unrecognized option") >= 0 || lower.indexOf("invalid") >= 0)
        return "This scrcpy version refused an option: " + text
    return text
}

// What the manager says while it holds a launch back (`waiting` event).
function waitingText(msg) {
    if (!msg || msg.reason !== "locked")
        return "Waiting for the phone to reconnect…"
    if (!msg.unlockWindow)
        return "Waiting for the phone to be unlocked…"
    return msg.secure
        ? "Type your PIN in the window that opened. Android blanks the PIN screen, so it stays black."
        : "Unlock your phone in the window that just opened."
}

// ---------- the panel's shape ----------

// Fits a phone into a box: the screen has the phone's aspect (`aspect` = width / height of
// the real screen), the body is the screen plus `inset` on every side, and the whole body
// is at most `maxW` x `maxH`. All in pixels.
function fitPhone(maxW, maxH, aspect, inset) {
    var a = aspect > 0 ? aspect : 9 / 20
    var screenH = Math.max(80, maxH - 2 * inset)
    var screenW = screenH * a
    if (screenW + 2 * inset > maxW) {
        screenW = Math.max(40, maxW - 2 * inset)
        screenH = screenW / a
    }
    // Whole pixels: the scrcpy window is put on this rectangle, and a half pixel would
    // blur its edge against the frame.
    screenW = Math.round(screenW)
    screenH = Math.round(screenH)
    return { screenW: screenW, screenH: screenH, bodyW: screenW + 2 * inset, bodyH: screenH + 2 * inset }
}
