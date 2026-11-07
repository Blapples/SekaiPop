.pragma library

// The numbers behind the network speed pill (services/NetSpeedService.qml,
// modules/sekai/bar/NetSpeedIndicator.qml). No QML in here, so it can be unit-tested with plain
// node (tests/netspeed-test/netspeed_unit.js).

// Interfaces whose traffic is somebody else's: loopback, containers and virtual machines, and
// tunnels (a VPN's traffic also passes through the real interface it rides on, so counting both
// would count it twice).
var IGNORED = ["lo", "docker", "veth", "br-", "virbr", "vnet", "tun", "tap", "wg", "tailscale",
               "zt", "vboxnet", "vmnet", "cni", "flannel", "kube", "podman", "lxc", "ifb", "dummy"]

function ignored(name) {
    var n = String(name || "")
    if (n === "")
        return true
    for (var i = 0; i < IGNORED.length; i++) {
        if (IGNORED[i] === "lo" ? n === "lo" : n.indexOf(IGNORED[i]) === 0)
            return true
    }
    return false
}

// The text of /proc/net/dev -> { rx, tx, ifaces }: the bytes received and sent so far, summed over
// the real interfaces, and which interfaces those were.
//
//   Inter-|   Receive                                                |  Transmit
//    face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets ...
//   wlan0: 123456   789 ...                                           98765    ...
function parseNetDev(text) {
    var rx = 0
    var tx = 0
    var ifaces = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var colon = lines[i].indexOf(":")
        if (colon < 0)
            continue
        var name = lines[i].slice(0, colon).trim()
        if (ignored(name))
            continue
        var f = lines[i].slice(colon + 1).trim().split(/\s+/)
        if (f.length < 9)
            continue
        var r = Number(f[0])
        var t = Number(f[8])
        if (!isFinite(r) || !isFinite(t))
            continue
        rx += r
        tx += t
        ifaces.push(name)
    }
    return { rx: rx, tx: tx, ifaces: ifaces }
}

// Bytes per second between two samples ({ rx, tx }) `seconds` apart. A counter that went down (an
// interface came or went, a counter wrapped) counts as 0 for that step rather than a huge number.
function rate(prev, cur, seconds) {
    if (!prev || !cur || !(seconds > 0))
        return { down: 0, up: 0 }
    var d = cur.rx - prev.rx
    var u = cur.tx - prev.tx
    return { down: d > 0 ? d / seconds : 0, up: u > 0 ? u / seconds : 0 }
}

// A speed as at most four characters, so the pill can keep a fixed width: "0K", "9.9K", "512K",
// "1.2M", "85M", "1.1G". Decimal units (1 K = 1000 B), as network speeds are quoted.
function speedText(bytesPerSec) {
    var b = Number(bytesPerSec)
    if (!isFinite(b) || b < 0)
        b = 0
    var units = ["K", "M", "G"]
    var v = b / 1000
    var u = 0
    // Round first, then pick the tier: 9.96 rounds to 10.0, which must read "10", not "10.0".
    while (u < units.length - 1 && Math.round(v) >= 1000) {
        v /= 1000
        u++
    }
    if (v < 10 && Math.round(v * 10) < 100)
        return (Math.round(v * 10) / 10).toFixed(v < 0.05 ? 0 : 1) + units[u]
    return String(Math.round(v)) + units[u]
}

// The widest text speedText can give, for the pill to measure.
var SPEED_TEMPLATE = "000M"

// "1.2 MB/s", "512 KB/s", "0 KB/s": for the hover tag.
function speedLong(bytesPerSec) {
    return speedText(bytesPerSec).replace(/([KMG])$/, " $1B/s")
}

// ---- for the pill: always KB/s ----
// The bar pill shows plain kilobytes per second, never stepping up to M or G: "0", "512", "1200",
// "85000". Decimal (1 KB = 1000 B), like speedText. Up to four digits (9999 KB/s, about 80 Mbit/s)
// fit the reserved width; anything faster just runs a digit wider.
var KB_TEMPLATE = "0000"

function kbText(bytesPerSec) {
    var b = Number(bytesPerSec)
    if (!isFinite(b) || b < 0)
        b = 0
    return String(Math.round(b / 1000))
}

// "512 KB/s", "1200 KB/s": for the hover tag.
function kbLong(bytesPerSec) {
    return kbText(bytesPerSec) + " KB/s"
}

// ---- for the card (NetSpeedPopup.qml) ----
var HISTORY = 60   // readings kept: 60 at one every two seconds is the last two minutes

// The list with `v` added at the end, at most HISTORY long (a new list; the old one is not changed).
function pushHistory(list, v) {
    var n = Number(v)
    var out = (list || []).slice(-(HISTORY - 1))
    out.push(isFinite(n) && n > 0 ? n : 0)
    return out
}

// The biggest in a list (0 for none).
function peak(list) {
    var m = 0
    for (var i = 0; i < (list || []).length; i++)
        if (list[i] > m)
            m = list[i]
    return m
}

// A history as heights 0..1 for a chart of HISTORY bars, the newest on the right. The longest
// reading is 1, but never lower than `floor` (bytes per second), so a quiet minute does not stretch
// a few kilobytes into full-height bars. A history shorter than HISTORY is padded with 0 on the left.
function fracs(list, floor) {
    var l = list || []
    var top = Math.max(peak(l), Number(floor) || 1)
    var out = []
    for (var i = 0; i < HISTORY - l.length; i++)
        out.push(0)
    for (var j = 0; j < l.length; j++)
        out.push(l[j] > 0 ? Math.min(1, l[j] / top) : 0)
    return out.slice(-HISTORY)
}

// "1.2M" -> { num: "1.2", unit: "MB/s" }: a speed as the big number and its unit.
function speedParts(bytesPerSec) {
    var t = speedText(bytesPerSec)
    return { num: t.slice(0, -1), unit: t.slice(-1) + "B/s" }
}

// A byte count: "0 KB", "512 KB", "1.2 MB", "34 GB", "1.5 TB". Decimal units, like the speeds.
function bytesText(b) {
    var v = Number(b)
    if (!isFinite(v) || v < 0)
        v = 0
    var units = ["KB", "MB", "GB", "TB"]
    v = v / 1000
    var u = 0
    while (u < units.length - 1 && Math.round(v) >= 1000) {
        v /= 1000
        u++
    }
    var r = Math.round(v * 10) / 10
    return (r < 10 ? r.toFixed(r < 0.05 ? 0 : 1) : String(Math.round(v))) + " " + units[u]
}
