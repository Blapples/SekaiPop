.pragma library

// The numbers behind the screen time pill (services/ScreenTimeService.qml,
// modules/sekai/bar/ScreenTimeIndicator.qml and ScreenTimePopup.qml). No QML in here, so it can
// be unit-tested with plain node (tests/screentime-test/screentime_unit.js).

var KEEP_DAYS = 30        // days of history kept on disk
var MAX_APPS = 40         // apps kept per day (the rest are dropped, smallest first)
var MAX_GAP = 30          // seconds: a bigger jump between two ticks (sleep, a hang) is not counted
var DAY_SECONDS = 86400

function pad(n) {
    return n < 10 ? "0" + n : String(n)
}

// A local date as "2026-10-27". The day changes at local midnight.
function dayKey(date) {
    var d = date instanceof Date ? date : new Date()
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

// "2026-10-27" -> a Date at local noon (noon: no daylight-saving edge can move it to another day).
function parseKey(key) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""))
    if (!m)
        return null
    return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12, 0, 0)
}

// The day before / after `key`, as a key.
function shiftKey(key, days) {
    var d = parseKey(key)
    if (!d)
        return ""
    d.setDate(d.getDate() + days)
    return dayKey(d)
}

// 0 = Sunday .. 6 = Saturday, for a key.
function weekday(key) {
    var d = parseKey(key)
    return d ? d.getDay() : 0
}

// The seconds that passed between two ticks (ms timestamps), or 0 when they should not count:
// the clock went back, or the gap is so long that the machine was asleep or the shell hung.
function elapsed(lastMs, nowMs) {
    var dt = (Number(nowMs) - Number(lastMs)) / 1000
    if (!isFinite(dt) || dt <= 0 || dt > MAX_GAP)
        return 0
    return dt
}

// What an app is filed under: its window class, trimmed and lower-cased ("Firefox" and
// "firefox" are one app). "" (no window has focus) stays "": it counts towards the day's
// total but not towards an app.
function appKey(cls) {
    return String(cls === undefined || cls === null ? "" : cls).trim().toLowerCase()
}

// "org.mozilla.firefox" -> "Firefox", "code-oss" -> "Code-oss" (used when there is no .desktop name).
function prettyApp(key) {
    var s = String(key || "")
    if (s === "")
        return ""
    var last = s.split(".").pop()
    return last.charAt(0).toUpperCase() + last.slice(1)
}

// Adds `secs` to the day. `apps` is { appKey: seconds }. Returns { total, apps } (new objects).
function addTime(total, apps, key, secs) {
    var s = Number(secs)
    var t = Number(total)
    if (!isFinite(s) || s <= 0)
        return { total: isFinite(t) ? t : 0, apps: apps || {} }
    var out = {}
    for (var k in (apps || {}))
        out[k] = apps[k]
    if (key !== "")
        out[key] = (Number(out[key]) || 0) + s
    return { total: (isFinite(t) ? t : 0) + s, apps: out }
}

// The apps as a list, longest first: [{ key, secs }]. `n` limits it (0 / missing = all).
function topApps(apps, n) {
    var list = []
    for (var k in (apps || {})) {
        var v = Number(apps[k])
        if (k !== "" && isFinite(v) && v > 0)
            list.push({ key: k, secs: v })
    }
    list.sort(function (a, b) { return b.secs - a.secs || (a.key < b.key ? -1 : 1) })
    return n > 0 ? list.slice(0, n) : list
}

// Only sane numbers, rounded to whole seconds, and at most MAX_APPS of them (the biggest).
function trimApps(apps) {
    var out = {}
    var list = topApps(apps, MAX_APPS)
    for (var i = 0; i < list.length; i++) {
        var n = Math.round(list[i].secs)
        if (n > 0)
            out[list[i].key] = Math.min(n, DAY_SECONDS)
    }
    return out
}

// Keeps only the last KEEP_DAYS days before `today` (today itself is the live count), and only
// sane numbers. Returns a new object.
function trimHistory(history, today) {
    var out = {}
    if (!history || typeof history !== "object")
        return out
    var oldest = shiftKey(today, -KEEP_DAYS)
    for (var k in history) {
        if (!parseKey(k))
            continue
        if (k >= today || k < oldest)
            continue
        var n = Math.round(Number(history[k]))
        if (isFinite(n) && n > 0)
            out[k] = Math.min(n, DAY_SECONDS)
    }
    return out
}

// What the service should hold after a new day starts. `state` = { day, total, apps, history };
// `today` is the key of now. Same day: nothing changes. A later day: the old day's total goes into
// the history and the day starts again at 0 (the very first run just stamps the day). A clock
// set back changes nothing.
function rollover(state, today) {
    var day = state && typeof state.day === "string" ? state.day : ""
    var history = state && state.history ? state.history : {}
    var total = state ? Number(state.total) || 0 : 0
    var apps = state && state.apps ? state.apps : {}
    if (day === today)
        return { changed: false, day: day, total: total, apps: apps, history: history }
    if (day === "" || !parseKey(day))
        return { changed: true, day: today, total: total, apps: apps, history: trimHistory(history, today) }
    if (today < day)
        return { changed: false, day: day, total: total, apps: apps, history: history }
    var h = {}
    for (var k in history)
        h[k] = history[k]
    if (Math.round(total) > 0)
        h[day] = Math.round(total)
    return { changed: true, day: today, total: 0, apps: {}, history: trimHistory(h, today) }
}

// 3 h 12 m -> { h: 3, m: 12 } (whole minutes, rounded down).
function parts(secs) {
    var s = Math.max(0, Math.floor(Number(secs) || 0))
    return { h: Math.floor(s / 3600), m: Math.floor((s % 3600) / 60) }
}

// "3h 12m", "42m", "0m". What the pill says.
function shortText(secs) {
    var p = parts(secs)
    if (p.h === 0)
        return p.m + "m"
    return p.h + "h " + p.m + "m"
}

// "3 hr 12 min" for a sentence ("1 hr", "42 min").
function longText(secs) {
    var p = parts(secs)
    if (p.h === 0)
        return p.m + " min"
    if (p.m === 0)
        return p.h + " hr"
    return p.h + " hr " + p.m + " min"
}

// The last `days` days ending today, oldest first: [{ key, weekday, secs, frac, today }].
// `frac` (0..1) is the bar's height against the longest day shown, with a floor of one hour so a
// quiet week doesn't look as tall as a busy one.
function weekBars(history, todaySecs, today, days) {
    var n = days > 0 ? days : 7
    var bars = []
    var max = 3600
    for (var i = n - 1; i >= 0; i--) {
        var key = shiftKey(today, -i)
        var secs = i === 0 ? Math.max(0, Number(todaySecs) || 0) : (Number(history && history[key]) || 0)
        bars.push({ key: key, weekday: weekday(key), secs: secs, frac: 0, today: i === 0 })
        if (secs > max)
            max = secs
    }
    for (var j = 0; j < bars.length; j++)
        bars[j].frac = bars[j].secs > 0 ? Math.max(0.04, bars[j].secs / max) : 0
    return bars
}

// The average of the days before today (up to `days`) that have any time, in seconds; 0 when none.
function average(history, today, days) {
    var n = days > 0 ? days : 7
    var sum = 0
    var count = 0
    for (var i = 1; i <= n; i++) {
        var v = Number(history && history[shiftKey(today, -i)]) || 0
        if (v > 0) {
            sum += v
            count++
        }
    }
    return count > 0 ? sum / count : 0
}

// How the pill writes the time (right-click cycles them):
//   "short"    3h 12m      (hours always shown, minutes padded: 0h 05m, so its length never jumps)
//   "clock"    03:12
//   "seconds"  03:12:45
var FORMATS = ["short", "clock", "seconds"]

function normalizeFormat(mode) {
    return FORMATS.indexOf(mode) >= 0 ? mode : "short"
}

// The format after this one (short -> clock -> seconds -> short).
function nextFormat(mode) {
    return FORMATS[(FORMATS.indexOf(normalizeFormat(mode)) + 1) % FORMATS.length]
}

// The time in the chosen format. Whole seconds, rounded down.
function formatText(secs, mode) {
    var m = normalizeFormat(mode)
    var total = Math.max(0, Math.floor(Number(secs) || 0))
    var h = Math.floor(total / 3600)
    var min = Math.floor((total % 3600) / 60)
    if (m === "short")
        return h + "h " + pad(min) + "m"
    var text = pad(h) + ":" + pad(min)
    return m === "seconds" ? text + ":" + pad(total % 60) : text
}

// The longest text a format can ever show (two-digit hours; a day has at most 24), with every digit
// a 0. The pill measures it (and the same with 8s, the widest digit in most fonts) and keeps that
// width, so its neighbours never move as the digits change.
function formatTemplate(mode) {
    var m = normalizeFormat(mode)
    if (m === "short")
        return "00h 00m"
    return m === "seconds" ? "00:00:00" : "00:00"
}
