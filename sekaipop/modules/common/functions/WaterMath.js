.pragma library

// The numbers behind the Water Tank widget (services/WaterTankService.qml,
// modules/sekai/desktopWidgets/WaterTankWidget.qml and WaterTile.qml). No QML in here, so
// it can be unit-tested with plain node (tests/watertank-test/water_unit.js).

var KEEP_DAYS = 14
var MIN_GOAL = 1
var MAX_GOAL = 20
var MIN_GLASS = 100
var MAX_GLASS = 1000

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

// 0 = Sunday .. 6 = Saturday, for a key (Qt.locale().dayName uses the same numbers).
function weekday(key) {
    var d = parseKey(key)
    return d ? d.getDay() : 0
}

function clampInt(value, lo, hi, fallback) {
    var n = Math.round(Number(value))
    if (!isFinite(n))
        return fallback
    return Math.max(lo, Math.min(hi, n))
}

function clampGoal(value) {
    return clampInt(value, MIN_GOAL, MAX_GOAL, 8)
}

// The size of one glass in ml, kept to steps of 50.
function clampGlass(value) {
    var n = clampInt(value, MIN_GLASS, MAX_GLASS, 250)
    return Math.round(n / 50) * 50
}

// How full the tank is, 0..1 (more glasses than the goal is still just full).
function fraction(glasses, goal) {
    var g = Number(glasses)
    var t = Number(goal)
    if (!isFinite(g) || !isFinite(t) || t <= 0 || g <= 0)
        return 0
    return Math.min(1, g / t)
}

function reached(glasses, goal) {
    return Number(goal) > 0 && Number(glasses) >= Number(goal)
}

// "1.5 L" from 1500 ml, "750 ml" below a litre. Whole litres have no ".0".
function amountText(glasses, glassMl) {
    var ml = Math.max(0, Math.round(Number(glasses) * Number(glassMl)))
    if (!isFinite(ml))
        return "0 ml"
    if (ml < 1000)
        return ml + " ml"
    var l = Math.round(ml / 10) / 100
    var s = l.toFixed(2).replace(/0+$/, "").replace(/\.$/, "")
    return s + " L"
}

// Keeps only the last KEEP_DAYS days before `today` (today itself is not kept here: it is the
// live count), and only sane numbers. Returns a new object.
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
            out[k] = Math.min(n, 99)
    }
    return out
}

// What the service should hold after a new day starts. `state` = { day, glasses, history };
// `today` is the key of now. Same day: nothing changes. A later day: the old day's count goes
// into the history and the count starts at 0 (the very first run just stamps the day).
// (A clock set back changes nothing.)
function rollover(state, today) {
    var day = state.day || ""
    // Nothing to do on the same day, or when the clock was set back.
    if (day !== "" && day >= today)
        return { day: day, glasses: state.glasses, history: state.history, changed: false }
    var h = Object.assign({}, state.history || {})
    if (day !== "" && state.glasses > 0)
        h[day] = state.glasses
    return { day: today, glasses: 0, history: trimHistory(h, today), changed: true }
}

// The last `n` days ending today, oldest first, for the week bars:
// [{ key, weekday, count, today }]. Today's count is the live one.
function weekBars(history, glasses, today, n) {
    var out = []
    var h = history || {}
    for (var i = n - 1; i >= 0; i--) {
        var k = shiftKey(today, -i)
        out.push({
            key: k,
            weekday: weekday(k),
            count: i === 0 ? Number(glasses) : (Number(h[k]) || 0),
            today: i === 0
        })
    }
    return out
}

// How many days in a row the goal was reached. Today counts when it is reached; if it is not
// (yet), the run that ended yesterday still stands (the day is not over).
function streak(history, glasses, goal, today) {
    var h = history || {}
    var n = 0
    var k = today
    if (reached(glasses, goal))
        n = 1
    k = shiftKey(today, -1)
    while (k !== "" && n < 1000) {
        if (Number(h[k]) >= Number(goal))
            n++
        else
            break
        k = shiftKey(k, -1)
    }
    return n
}
