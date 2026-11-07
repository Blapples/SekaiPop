.pragma library

// The numbers behind the temperatures and disks in the CPU & RAM card
// (services/SensorsService.qml, modules/sekai/bar/ResourcePopup.qml). No QML in here, so it can be
// unit-tested with plain node (tests/sensors-test/sensors_unit.js).

var MAX_TEMP = 150   // a reading above this (or below 0) is a broken sensor, not a temperature

var MAX_DISKS = 6   // the card shows at most this many

// What scripts/system/sensors.sh prints:
//   cpu=62          degrees C (missing when the machine has no readable sensor)
//   gpu=55
//   disk=/|112000000000|476000000000|/dev/nvme0n1p2   mount point | bytes used | bytes in total | device
//   home=/          the mount point of the filesystem $HOME is on
// -> { cpuTemp, gpuTemp, disks: [{ name, mount, mounts, used, total }] }  (a temperature is null when
// unknown; the disks are one per device, see groupDisks)
function parse(text) {
    var out = { cpuTemp: null, gpuTemp: null, disks: [] }
    var raw = []
    var home = ""
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var eq = lines[i].indexOf("=")
        if (eq < 0)
            continue
        var key = lines[i].slice(0, eq).trim()
        var val = lines[i].slice(eq + 1).trim()
        if (key === "cpu" || key === "gpu") {
            var t = temp(val)
            if (key === "cpu")
                out.cpuTemp = t
            else
                out.gpuTemp = t
        } else if (key === "disk") {
            var p = val.split("|")
            if (p.length < 3)
                continue
            var used = Number(p[1])
            var total = Number(p[2])
            if (p[0] === "" || !isFinite(used) || !isFinite(total) || total <= 0 || used < 0)
                continue
            raw.push({ mount: p[0], used: Math.min(used, total), total: total, device: p.length > 3 ? p.slice(3).join("|") : "" })
        } else if (key === "home") {
            home = val
        }
    }
    out.disks = groupDisks(raw, home)
    return out
}

// Mounts of one device are one disk (btrfs subvolumes, bind mounts, and a plain / with /home on the
// same filesystem). Its name is its mounts' names, "System / Home": the root's first, then /home,
// then the shortest paths, at most two. `home` is the mount point $HOME lives on: when it is one of
// the disk's mounts but not /home itself (a home that is just a folder of /), "Home" is added, so
// the one disk that holds both reads "System / Home" and not just "System". The root's disk is
// first, the rest in the order given, and at most MAX_DISKS of them.
function groupDisks(list, home) {
    var groups = []
    var byKey = {}
    for (var i = 0; i < list.length; i++) {
        var d = list[i]
        var key = d.device ? d.device : d.mount
        var g = byKey[key]
        if (!g) {
            g = { used: d.used, total: d.total, mounts: [] }
            byKey[key] = g
            groups.push(g)
        }
        g.mounts.push(d.mount)
    }
    var out = []
    for (var j = 0; j < groups.length; j++) {
        var gr = groups[j]
        gr.mounts.sort(function (a, b) {
            var ra = a === "/" ? 0 : (a === "/home" ? 1 : 2)
            var rb = b === "/" ? 0 : (b === "/home" ? 1 : 2)
            return ra - rb || a.length - b.length || (a < b ? -1 : 1)
        })
        var names = []
        for (var k = 0; k < gr.mounts.length; k++) {
            var nm = diskName(gr.mounts[k])
            if (names.indexOf(nm) < 0)
                names.push(nm)
        }
        if (home && gr.mounts.indexOf(home) >= 0 && names.indexOf("Home") < 0)
            names.push("Home")
        out.push({ name: names.slice(0, 2).join(" / "), mount: gr.mounts[0], mounts: gr.mounts, used: gr.used, total: gr.total })
    }
    out.sort(function (a, b) { return (a.mounts.indexOf("/") >= 0 ? 0 : 1) - (b.mounts.indexOf("/") >= 0 ? 0 : 1) })
    return out.slice(0, MAX_DISKS)
}

// "62" -> 62; "" / "abc" / 400 / -3 -> null.
function temp(v) {
    if (v === "" || v === null || v === undefined)
        return null
    var n = Number(v)
    return isFinite(n) && n >= 0 && n <= MAX_TEMP ? Math.round(n) : null
}

function tempText(c) {
    return c === null || c === undefined ? "--" : Math.round(c) + "°C"
}

// How a temperature reads: COOL below 60, WARM below 80, HOT from 80.
function tempWord(c) {
    if (c === null || c === undefined)
        return ""
    return c < 60 ? "COOL" : (c < 80 ? "WARM" : "HOT")
}

// 0..1 for a bar that runs 0-100 °C.
function tempFrac(c) {
    return c === null || c === undefined ? 0 : Math.max(0, Math.min(1, c / 100))
}

function tempHot(c) {
    return c !== null && c !== undefined && c >= 80
}

// Bytes as "112 GB" / "1.5 TB" / "640 MB" (1 GB = 1024^3, the way the memory is shown).
function bytesText(b) {
    var n = Math.max(0, Number(b) || 0)
    var gb = n / (1024 * 1024 * 1024)
    if (gb >= 1000)
        return (gb / 1024).toFixed(1) + " TB"
    if (gb >= 1)
        return (gb >= 100 ? Math.round(gb) : Math.round(gb * 10) / 10) + " GB"
    return Math.round(n / (1024 * 1024)) + " MB"
}

// "/" -> "System", "/home" -> "Home", anything else its last folder ("/mnt/games" -> "games").
function diskName(mount) {
    if (mount === "/")
        return "System"
    var last = String(mount || "").split("/").filter(function (s) { return s !== "" }).pop() || String(mount || "")
    return last.charAt(0).toUpperCase() + last.slice(1)
}

function diskFrac(d) {
    return d && d.total > 0 ? Math.max(0, Math.min(1, d.used / d.total)) : 0
}

// "364 GB free of 476 GB"
function diskText(d) {
    return d ? bytesText(d.total - d.used) + " free of " + bytesText(d.total) : ""
}

// A disk is nearly full from 90 %.
function diskFull(d) {
    return diskFrac(d) >= 0.9
}
