.pragma library

// Pure logic for the manga reader's reading modes (no Quickshell imports;
// tests/manga-reader-test runs it in node). Top-level values use `var` on purpose: QML JS
// libraries don't reliably export top-level const/let.
//
//   MODES / modeInfo(id)           the seven ways to read a chapter
//   normalizePrefs(raw)            the saved reader settings -> a clean record
//   webtoonFromMeta / looksLikeStrip / resolveMode
//                                  manhwa and other long-strip series open as a long strip on their own
//   orderChapters / chapterNeighbors
//                                  which chapter comes before / after the one being read
//   buildSpreads / spreadIndex     which pages share a screen in Tablet mode
//   fitSize / clampPan / zoomAbout the zoom and pan of a page
//   keyAction / tapAction          what a key or a click does in each mode
//   keysHint / saveName            text for the toast, file names for a saved page

var MODES = [
    { id: "paged_ltr",  family: "paged",  dir: "ltr", icon: "arrow_right",
      label: "Paged \u00b7 left to right",  short: "Paged \u2192" },
    { id: "paged_rtl",  family: "paged",  dir: "rtl", icon: "arrow_left",
      label: "Paged \u00b7 right to left",  short: "Paged \u2190" },
    { id: "paged_v",    family: "paged",  dir: "v",   icon: "transfer_vertical",
      label: "Paged \u00b7 vertical",       short: "Paged \u2193" },
    { id: "strip",      family: "strip",  dir: "v",   icon: "posts_carousel_vertical", gap: 0,
      label: "Long strip",                  short: "Strip" },
    { id: "strip_gap",  family: "strip",  dir: "v",   icon: "list", gap: 18,
      label: "Long strip \u00b7 with gaps", short: "Strip + gaps" },
    { id: "spread_ltr", family: "spread", dir: "ltr", icon: "book_2",
      label: "Tablet \u00b7 left to right", short: "Tablet \u2192" },
    { id: "spread_rtl", family: "spread", dir: "rtl", icon: "book",
      label: "Tablet \u00b7 right to left (manga)", short: "Tablet \u2190" }
]

var BACKGROUNDS = [
    { id: "black", label: "Black" },
    { id: "gray",  label: "Gray" },
    { id: "white", label: "White" },
    { id: "theme", label: "Shell" }
]

var DEFAULT_PREFS = {
    auto: true,               // a manhwa / long-strip series picks `webtoonMode` by itself
    mode: "paged_rtl",        // everything else (and everything, when `auto` is off)
    webtoonMode: "strip",
    background: "theme",
    spreadCover: true,        // Tablet mode: the first page stands alone, like a book's cover
    fullWindow: true          // the panel takes the whole screen (false = the side card on the left)
}

function modeInfo(id) {
    for (var i = 0; i < MODES.length; i++)
        if (MODES[i].id === id) return MODES[i]
    return MODES[1]
}

function isMode(id) {
    for (var i = 0; i < MODES.length; i++)
        if (MODES[i].id === id) return true
    return false
}

function isBackground(id) {
    for (var i = 0; i < BACKGROUNDS.length; i++)
        if (BACKGROUNDS[i].id === id) return true
    return false
}

function normalizePrefs(raw) {
    var r = (raw && typeof raw === "object") ? raw : {}
    return {
        auto:        r.auto === undefined ? DEFAULT_PREFS.auto : r.auto === true,
        mode:        isMode(r.mode) ? r.mode : DEFAULT_PREFS.mode,
        webtoonMode: isMode(r.webtoonMode) ? r.webtoonMode : DEFAULT_PREFS.webtoonMode,
        background:  isBackground(r.background) ? r.background : DEFAULT_PREFS.background,
        spreadCover: r.spreadCover === undefined ? DEFAULT_PREFS.spreadCover : r.spreadCover === true,
        fullWindow:  r.fullWindow === undefined ? DEFAULT_PREFS.fullWindow : r.fullWindow === true
    }
}

// How many covers a grid puts in a row: about one per `target` pixels, never fewer than `min`
// (the side card's four) and never more than `max` (covers stay a size worth looking at on a
// very wide screen).
function gridColumns(width, target, min, max) {
    var t = target > 0 ? target : 190
    var lo = min > 0 ? min : 4
    var hi = max >= lo ? max : lo
    var n = Math.floor((width > 0 ? width : 0) / t)
    return Math.max(lo, Math.min(hi, n))
}

// ── Which mode a series opens in ──────────────────────────────────────────────

// true = a long-strip series (manhwa, manhua, webtoons), false = a page-by-page one,
// null = the metadata doesn't say.
function webtoonFromMeta(type, tags) {
    var t = String(type || "").toLowerCase().replace(/[_\s-]+/g, "")
    if (t === "manhwa" || t === "manhua" || t === "webtoon" || t === "longstrip") return true
    if (tags && tags.length !== undefined) {
        for (var i = 0; i < tags.length; i++) {
            var g = String(tags[i] || "").toLowerCase()
            if (g === "long strip" || g === "web comic" || g === "webtoon") return true
        }
    }
    if (t === "manga" || t === "oneshot" || t === "doujinshi" || t === "novel") return false
    return null
}

// For a series whose metadata doesn't say: long strips are cut into tall slices. `sizes` is
// sparse, [{ w, h }] by page index. null until enough of the first pages have a size.
function looksLikeStrip(sizes, count) {
    var need = Math.min(3, Math.max(1, count || 0))
    var ratios = []
    for (var i = 0; i < Math.min(count || 0, 8); i++) {
        var s = sizes[i]
        if (s && s.w > 0 && s.h > 0) ratios.push(s.h / s.w)
    }
    if (ratios.length < need) return null
    ratios.sort(function (a, b) { return a - b })
    var median = ratios[Math.floor(ratios.length / 2)]
    return median >= 2.0
}

// prefs: normalizePrefs(); webtoon: true / false / null
function resolveMode(prefs, webtoon) {
    if (prefs.auto && webtoon === true) return prefs.webtoonMode
    return prefs.mode
}

// ── Chapters ──────────────────────────────────────────────────────────────────

function chapterNumber(ch) {
    var n = parseFloat(String(ch && ch.chapter !== undefined ? ch.chapter : ""))
    return isNaN(n) ? 0 : n
}

// Reading order, oldest first. The site's own `index` when the list has one (volumes and
// chapters share numbers), else the chapter number.
function orderChapters(chapters) {
    var list = []
    for (var i = 0; i < (chapters || []).length; i++) list.push({ ch: chapters[i], pos: i })
    var seen = {}, distinct = 0
    for (var j = 0; j < list.length; j++) {
        var ix = list[j].ch.index
        if (ix !== undefined && !seen["i" + ix]) { seen["i" + ix] = true; distinct++ }
    }
    var byIndex = distinct > 1
    list.sort(function (a, b) {
        var d = byIndex ? (a.ch.index - b.ch.index) : (chapterNumber(a.ch) - chapterNumber(b.ch))
        return d !== 0 ? d : a.pos - b.pos
    })
    return list.map(function (e) { return e.ch })
}

function chapterNeighbors(chapters, id) {
    var ordered = orderChapters(chapters)
    var at = -1
    for (var i = 0; i < ordered.length; i++)
        if (ordered[i].id === id) { at = i; break }
    return {
        pos:     at,
        total:   ordered.length,
        current: at >= 0 ? ordered[at] : null,
        prev:    at > 0 ? ordered[at - 1] : null,
        next:    at >= 0 && at < ordered.length - 1 ? ordered[at + 1] : null
    }
}

// ── AniList tracking ──────────────────────────────────────────────────────────

// How far a title has been read, as AniList counts it: the highest chapter number read
// ("Chapter 12.5" counts as 12) and the highest volume number read (a series that WeebCentral
// lists by volume). Extras have no number AniList knows and are left out. `isRead(id)` says
// whether a chapter is read.
function trackProgress(chapters, isRead) {
    var ch = 0, vol = 0
    for (var i = 0; i < (chapters || []).length; i++) {
        var c = chapters[i]
        if (!c || !isRead(c.id) || c.kind === "extra") continue
        var m = /\d+(\.\d+)?/.exec(String(c.chapter === undefined ? "" : c.chapter))
        var n = m ? Math.floor(parseFloat(m[0])) : 0
        if (c.kind === "volume") vol = Math.max(vol, n)
        else                     ch  = Math.max(ch, n)
    }
    return { progress: ch, volumes: vol }
}

// The ids of the chapters AniList already counts as read: the chapters up to `progress` and the
// volumes up to `volumes` (the same whole-number reading as trackProgress: 12.5 is 12). Extras
// and chapters with no number are left out. The reader marks these read when a title opens.
function chaptersUpTo(chapters, progress, volumes) {
    var ids = []
    for (var i = 0; i < (chapters || []).length; i++) {
        var c = chapters[i]
        if (!c || !c.id || c.kind === "extra") continue
        var m = /\d+(\.\d+)?/.exec(String(c.chapter === undefined ? "" : c.chapter))
        if (!m) continue
        var n = Math.floor(parseFloat(m[0]))
        if (c.kind === "volume") { if (volumes > 0 && n <= volumes) ids.push(c.id) }
        else if (progress > 0 && n <= progress) ids.push(c.id)
    }
    return ids
}

// ── The user's AniList lists (the Library tabs) ───────────────────────────────

// The tabs of the Library, in the order they are shown. There is no "All": a title is always in
// one list. Paused and Rereading are only shown while they hold something.
var LIST_TABS = [
    { id: "CURRENT",   label: "Reading",   always: true  },
    { id: "COMPLETED", label: "Completed", always: true  },
    { id: "DROPPED",   label: "Dropped",   always: true  },
    { id: "PLANNING",  label: "Planning",  always: true  },
    { id: "PAUSED",    label: "Paused",    always: false },
    { id: "REPEATING", label: "Rereading", always: false }
]

// The tabs to show now: the four always, the others while they have titles (or are open).
// `counts` is { CURRENT: n, ... } from the server.
function visibleListTabs(counts, current) {
    var out = []
    for (var i = 0; i < LIST_TABS.length; i++) {
        var t = LIST_TABS[i], n = counts && counts[t.id] > 0 ? counts[t.id] : 0
        if (t.always || n > 0 || t.id === current)
            out.push({ id: t.id, label: t.label, count: n })
    }
    return out
}

function listTabLabel(id) {
    for (var i = 0; i < LIST_TABS.length; i++)
        if (LIST_TABS[i].id === id) return LIST_TABS[i].label
    return ""
}

// The score of a list entry the way the user's AniList shows it. `score` is the number in the
// user's own format, `score100` the same on a 0-100 scale (used when the format is not known).
// "" for a title with no score.
function formatScore(score, score100, format) {
    score = Number(score) || 0
    score100 = Number(score100) || 0
    if (score <= 0 && score100 <= 0) return ""
    switch (format) {
    case "POINT_100":        return String(Math.round(score))
    case "POINT_10_DECIMAL": return (Math.round(score * 10) / 10).toFixed(1)
    case "POINT_10":         return String(Math.round(score))
    case "POINT_5":          return Math.round(score) + "\u2605"
    case "POINT_3":          return score >= 3 ? ":)" : (score >= 2 ? ":|" : ":(")
    default:                 return (score100 / 10).toFixed(1)
    }
}

// The user's own score for the info sheet: formatScore plus what it is out of ("8/10", "85/100");
// stars and smileys stand alone. "" when the title is not scored.
function yourScoreText(score, score100, format) {
    var t = formatScore(score, score100, format)
    if (t === "") return ""
    switch (format) {
    case "POINT_100":                         return t + "/100"
    case "POINT_10_DECIMAL": case "POINT_10": return t + "/10"
    case "POINT_5": case "POINT_3":           return t
    default:                                  return t + "/10"      // format not known: 0-100 shown out of 10
    }
}

// AniList's average (0-100) the way the cards show it: 85 -> "8.5". "" for none.
function communityScoreText(avg) {
    avg = Number(avg) || 0
    return avg > 0 ? (avg / 10).toFixed(1) : ""
}

// 250000 -> "250K", 1234567 -> "1.2M", 950 -> "950"; "" for none
function shortCount(n) {
    n = Math.floor(Number(n) || 0)
    if (n <= 0) return ""
    if (n >= 1000000) return (Math.round(n / 100000) / 10).toFixed(1).replace(/\.0$/, "") + "M"
    if (n >= 10000)   return Math.round(n / 1000) + "K"
    if (n >= 1000)    return (Math.round(n / 100) / 10).toFixed(1).replace(/\.0$/, "") + "K"
    return String(n)
}

// 12431 -> "12,431" (a count on the profile card); 0 for none
function groupDigits(n) {
    n = Math.floor(Number(n) || 0)
    if (n <= 0) return "0"
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// The user's mean score from AniList's statistics, which is always on a 0-100 scale:
// 78.4 -> "7.8" (or "78" for a user who scores out of 100). "" when nothing is scored.
function meanScoreText(mean, format) {
    mean = Number(mean) || 0
    if (mean <= 0) return ""
    if (format === "POINT_100") return String(Math.round(mean))
    return (mean / 10).toFixed(1)
}

// How far along a series is, for the info sheet: "200 chapters \u00b7 14 volumes" (what AniList knows,
// either part may be missing), "" when it knows neither
function sizeText(chapters, volumes) {
    chapters = Math.floor(Number(chapters) || 0)
    volumes  = Math.floor(Number(volumes) || 0)
    var out = []
    if (chapters > 0) out.push(chapters + (chapters === 1 ? " chapter" : " chapters"))
    if (volumes > 0)  out.push(volumes  + (volumes  === 1 ? " volume"  : " volumes"))
    return out.join(" \u00b7 ")
}

// "164/250", or just "21" when the total is not known (as AniList's own list writes it)
function listProgressText(done, total) {
    done = Math.max(0, Math.floor(Number(done) || 0))
    total = Math.max(0, Math.floor(Number(total) || 0))
    return total > 0 ? done + "/" + total : String(done)
}

// ── The profile page (status bar, taste, heatmap) ────────────────────────────

// The order of the segments in the status bar, and the name each goes by
var STATUS_BAR = [
    { id: "CURRENT",   label: "Reading"   },
    { id: "COMPLETED", label: "Completed" },
    { id: "DROPPED",   label: "Dropped"   },
    { id: "PLANNING",  label: "Planning"  },
    { id: "PAUSED",    label: "Paused"    },
    { id: "REPEATING", label: "Rereading" }
]

// { CURRENT: 39, ... } -> { total, segments: [{ id, label, count, fraction }] }: only the lists
// that hold something, in the bar's order; the fractions add up to 1 (all 0 for an empty list)
function statusSegments(counts) {
    var rows = [], total = 0
    for (var i = 0; i < STATUS_BAR.length; i++) {
        var n = Math.max(0, Math.floor(Number(counts && counts[STATUS_BAR[i].id]) || 0))
        if (n > 0) { rows.push({ id: STATUS_BAR[i].id, label: STATUS_BAR[i].label, count: n, fraction: 0 }); total += n }
    }
    for (var j = 0; j < rows.length; j++) rows[j].fraction = rows[j].count / total
    return { total: total, segments: rows }
}

// AniList's genre statistics ([{ genre, count, meanScore }], most read first) -> the bars of the
// Taste card: the width is relative to the biggest genre, so the first is always full
function genreBars(genres, limit, format) {
    var rows = []
    for (var i = 0; i < (genres || []).length; i++) {
        var g = genres[i], n = Math.floor(Number(g && g.count) || 0)
        if (g && g.genre && n > 0) rows.push({ genre: String(g.genre), count: n, mean: Number(g.meanScore) || 0 })
    }
    rows.sort(function(a, b) { return (b.count - a.count) || (a.genre < b.genre ? -1 : 1) })
    rows = rows.slice(0, limit > 0 ? limit : 6)
    var top = rows.length > 0 ? rows[0].count : 1
    return rows.map(function(r) {
        return { genre: r.genre, count: r.count, fraction: r.count / top, meanText: meanScoreText(r.mean, format) }
    })
}

function _dayKey(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1, 2) + "-" + pad(d.getDate(), 2) }

// The reading-activity heatmap: `counts` is { "YYYY-MM-DD": n } (the server's, in local days),
// `today` a Date. `weeks` columns of seven days, Monday at the top, the last column the week of
// `today` (its days after today are `future`). `level` is 0 for a quiet day and 1 to 4 for the
// busy ones, relative to the busiest day shown.
function activityGrid(counts, today, weeks) {
    weeks = weeks > 0 ? Math.floor(weeks) : 26
    var row = (today.getDay() + 6) % 7
    var y = today.getFullYear(), m = today.getMonth(), d = today.getDate()
    var first = d - row - (weeks - 1) * 7
    var cells = [], max = 0, total = 0
    for (var c = 0; c < weeks; c++) {
        for (var r = 0; r < 7; r++) {
            var date = new Date(y, m, first + c * 7 + r)
            var key = _dayKey(date)
            var future = date.getTime() > new Date(y, m, d).getTime()
            var n = future ? 0 : Math.max(0, Math.floor(Number(counts && counts[key]) || 0))
            if (n > max) max = n
            total += n
            cells.push({ key: key, count: n, level: 0, col: c, row: r, future: future })
        }
    }
    for (var i = 0; i < cells.length; i++)
        if (cells[i].count > 0) cells[i].level = Math.min(4, Math.max(1, Math.ceil(cells[i].count * 4 / max)))
    return { weeks: weeks, cells: cells, max: max, total: total }
}

// "3 days of reading in the last 26 weeks" style line for under the heatmap
function activityCaption(grid) {
    var days = 0
    for (var i = 0; i < grid.cells.length; i++) if (grid.cells[i].count > 0) days++
    if (days === 0) return "No list updates in the last " + grid.weeks + " weeks"
    return days + (days === 1 ? " day" : " days") + " with a list update in the last " + grid.weeks + " weeks"
}

// Where the month names go over the heatmap: [{ col, label }] for the first column of each new
// month, leaving out a mark that would sit within three columns of the one before it
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function monthMarks(grid) {
    var marks = [], prevMonth = -1, lastCol = -10
    for (var c = 0; c < grid.weeks; c++) {
        var cell = grid.cells[c * 7]
        if (!cell) break
        var month = Number(cell.key.substr(5, 2)) - 1
        if (month === prevMonth) continue
        prevMonth = month
        if (c - lastCol < 3 && marks.length > 0) { marks.pop() }       // the earlier one is too close: this one wins
        marks.push({ col: c, label: MONTH_NAMES[month] })
        lastCol = c
    }
    return marks
}

// "Nov 4 \u00b7 3 updates" for a day of the heatmap (the date is its "YYYY-MM-DD" key)
function dayText(cell) {
    if (!cell) return ""
    var m = Number(cell.key.substr(5, 2)) - 1, d = Number(cell.key.substr(8, 2))
    var n = cell.count
    return MONTH_NAMES[m] + " " + d + " \u00b7 " + (n === 0 ? "no updates" : n + (n === 1 ? " update" : " updates"))
}

// ── The profile page: numbers, score spread, streaks, shelves ───────────────

// The user's score spread ({ max, counts: [n of score 1, ...] } from the backend) -> the bars of
// the score card: one per point of their scale, the width relative to the busiest. `label` is the
// score as their AniList writes it (a number, stars, or a smiley); `rated` is how many titles hold
// a score. `peak` is the index of the busiest bar (-1 when nothing is scored).
function scoreBars(dist, format) {
    var counts = (dist && dist.counts) || []
    var max = Math.floor(Number(dist && dist.max) || counts.length)
    if (max <= 0 || counts.length === 0) return { rated: 0, peak: -1, bars: [] }
    var rows = [], rated = 0, top = 0, peak = -1
    for (var i = 0; i < max; i++) {
        var n = Math.max(0, Math.floor(Number(counts[i]) || 0))
        var label = String(i + 1)
        if (max === 5) label = (i + 1) + "\u2605"
        else if (max === 3) label = i === 0 ? ":(" : (i === 1 ? ":|" : ":)")
        rows.push({ label: label, count: n, fraction: 0 })
        rated += n
        if (n > top) { top = n; peak = i }
    }
    for (var j = 0; j < rows.length; j++) rows[j].fraction = top > 0 ? rows[j].count / top : 0
    return { rated: rated, peak: peak, bars: rows }
}

// The numbers of the stats strip, from the profile's statistics and the list counts:
// [{ value, label }]. Volumes read, titles completed, titles scored, and the chapters read per
// title tracked (rounded to a whole chapter). A figure that is not known yet is an em dash.
function statStripCells(stats, counts, rated) {
    var dash = "\u2014"
    var tracked = Math.floor(Number(stats && stats.count) || 0)
    var chapters = Math.floor(Number(stats && stats.chaptersRead) || 0)
    var done = Math.floor(Number(counts && counts.COMPLETED) || 0)
    var per = tracked > 0 ? Math.round(chapters / tracked) : 0
    return [
        { value: stats ? groupDigits(stats.volumesRead) : dash, label: "Volumes read" },
        { value: counts ? groupDigits(done) : dash,             label: "Completed" },
        { value: rated > 0 ? groupDigits(rated) : dash,         label: "Scored" },
        { value: per > 0 ? groupDigits(per) : dash,             label: "Chapters per title" }
    ]
}

// What the heatmap says about the days: { current, longest, week, month, busiest: { key, count } }.
// `grid` is activityGrid's, `today` the Date it was made for. A streak is a run of days in a row with
// a list update; the current one still counts when today has none yet (the day is not over) and
// ends at yesterday. `week` is Monday to today, `month` the first of this month to today, both
// counting list updates (AniList folds a run of chapters into one update, so they are not chapters).
function activityStats(grid, today) {
    var out = { current: 0, longest: 0, week: 0, month: 0, busiest: null }
    if (!grid || !grid.cells) return out
    var days = []
    for (var i = 0; i < grid.cells.length; i++) if (!grid.cells[i].future) days.push(grid.cells[i])
    var run = 0
    for (var j = 0; j < days.length; j++) {
        run = days[j].count > 0 ? run + 1 : 0
        if (run > out.longest) out.longest = run
        if (days[j].count > 0 && (!out.busiest || days[j].count > out.busiest.count))
            out.busiest = { key: days[j].key, count: days[j].count }
    }
    var k = days.length - 1
    if (k >= 0 && days[k].count === 0) k--
    while (k >= 0 && days[k].count > 0) { out.current++; k-- }
    var monthKey = today ? _dayKey(today).substr(0, 7) : ""
    var lastCol = grid.weeks - 1
    for (var m = 0; m < days.length; m++) {
        if (days[m].col === lastCol) out.week += days[m].count
        if (monthKey !== "" && days[m].key.substr(0, 7) === monthKey) out.month += days[m].count
    }
    return out
}

// AniList's CDN keeps every cover in three sizes under one file name, and the small one (what a
// list query hands out by default) is only ~100px wide: stretched over a grid card or the detail
// header it looks pixelated. Point the URL at the "large" folder instead. The URL may be the raw
// CDN address or the image proxy's `?url=` form (where the slashes are %2F), so both are matched.
// Anything that is not an AniList cover comes back untouched, as does the empty string.
function hiResCover(url) {
    var s = String(url || "")
    if (s.length === 0) return s
    return s.replace(/(anilistcdn(?:\/|%2F)media(?:\/|%2F)(?:manga|anime)(?:\/|%2F)cover(?:\/|%2F))(?:small|medium)((?:\/|%2F))/i, "$1large$2")
}

// The little line on a shelf cover: "3 left" for a title near its end, "Ch. 12 \u00b7 45d" for one
// that has sat (chapter read, days since it moved), "Ch. 12" otherwise
function shelfNote(kind, row) {
    if (!row) return ""
    if (kind === "almost") {
        var left = Math.floor(Number(row.left) || 0)
        return left > 0 ? left + " ch. left" : ""
    }
    if (kind === "stalled") {
        var days = Math.floor(Number(row.idleDays) || 0)
        var ch = Math.floor(Number(row.progress) || 0)
        return (ch > 0 ? "Ch. " + ch : "Not started") + (days > 0 ? " \u00b7 " + days + "d" : "")
    }
    if (kind === "feed") return row.note ? String(row.note) : ""
    return ""
}

// "2h" for a time `then` (seconds since 1970) as seen at `now`: "now" under 45 seconds, then
// minutes, hours, days, months and years, each rounded down. "" when the time is not a number.
function timeAgo(now, then) {
    now = Number(now); then = Number(then)
    if (!(then > 0) || !(now > 0)) return ""
    var d = Math.max(0, now - then)
    if (d < 45) return "now"
    if (d < 3600) return Math.max(1, Math.floor(d / 60)) + "m"
    if (d < 86400) return Math.floor(d / 3600) + "h"
    if (d < 86400 * 30) return Math.floor(d / 86400) + "d"
    if (d < 86400 * 365) return Math.floor(d / (86400 * 30)) + "mo"
    return Math.floor(d / (86400 * 365)) + "y"
}

// What a list update says, in few words for the strip under a cover: "Ch. 52 \u00b7 2h", "Completed \u00b7 1d".
// `row.status` and `row.progress` are AniList's own words ("read chapter" and "52", "plans to read", "completed",
// "dropped", "paused reading", "re-read"); anything else is shown as it is, capitalised.
function feedNote(row, now) {
    if (!row) return ""
    var st = String(row.status || "").toLowerCase().trim(), pr = String(row.progress || "").trim()
    var what
    if (/re-?read/.test(st))         what = "Reread" + (pr ? " Ch. " + pr : "")
    else if (/plans? to/.test(st))   what = "Planned"
    else if (/complete/.test(st))    what = "Completed"
    else if (/drop/.test(st))        what = "Dropped"
    else if (/paus/.test(st))        what = "Paused"
    else if (/read/.test(st) || pr)  what = pr ? "Ch. " + pr : "Read"
    else                             what = st ? st.charAt(0).toUpperCase() + st.slice(1) : ""
    var ago = timeAgo(now, row.createdAt)
    return ago ? (what ? what + " \u00b7 " + ago : ago) : what
}

// The backend's feed ([{ id, title, image, status, progress, createdAt }]) -> the rows of a shelf, each with
// its `note` worded as of `now`; a row without an id is dropped
function feedRows(rows, now) {
    var out = []
    for (var i = 0; i < (rows || []).length; i++) {
        var r = rows[i]
        if (!r || !r.id) continue
        out.push({ id: r.id, title: r.title || "", image: r.image || "", note: feedNote(r, now) })
    }
    return out
}

// Rows of { label, count, meanScore?, url? } (the order they come in is kept) -> the bars of the breakdown
// card: the width relative to the biggest, and a `note` such as "30 \u00b7 \u2605 8.2" for the end of the row
function countBars(rows, limit, format) {
    var list = []
    for (var i = 0; i < (rows || []).length; i++) {
        var r = rows[i], n = Math.floor(Number(r && r.count) || 0)
        if (r && r.label && n > 0) list.push({ label: String(r.label), count: n, mean: Number(r.meanScore) || 0, url: r.url ? String(r.url) : "" })
    }
    list = list.slice(0, limit > 0 ? limit : 8)
    var top = 0
    for (var j = 0; j < list.length; j++) if (list[j].count > top) top = list[j].count
    return list.map(function(r) {
        var mean = meanScoreText(r.mean, format)
        return { label: r.label, count: r.count, fraction: top > 0 ? r.count / top : 0, url: r.url,
                 note: r.count + (mean.length > 0 ? "  \u00b7  \u2605 " + mean : "") }
    })
}

// A title cut to `max` characters with an ellipsis, for a heading that has no room for a long name
function ellipsize(text, max) {
    text = String(text || "")
    return text.length > max ? text.substr(0, max - 1).replace(/\s+$/, "") + "\u2026" : text
}

// The score stamp on a Top rated cover: "\u2605 8" for the number formats, the stars or the smiley
// as they are for POINT_5 / POINT_3. "" for an unscored title.
function scoreStamp(score, score100, format) {
    var t = formatScore(score, score100, format)
    if (t === "") return ""
    return (format === "POINT_5" || format === "POINT_3") ? t : "\u2605 " + t
}

// How far along a title is, 0 to 1 (0 when the total is not known)
function progressFraction(done, total) {
    done = Math.max(0, Number(done) || 0)
    total = Math.max(0, Number(total) || 0)
    return total > 0 ? Math.min(1, done / total) : 0
}

// ── Pages and spreads ─────────────────────────────────────────────────────────

function aspectOf(size) {
    return size && size.w > 0 && size.h > 0 ? size.w / size.h : 0.7
}

function isWide(size) {
    return !!(size && size.w > 0 && size.h > 0 && size.w > size.h * 1.05)
}

// Tablet mode: [[0], [1, 2], [3, 4], [5]]. A landscape page (a double-page spread that
// is already joined) always stands alone. A page whose size is not known yet counts as portrait.
function buildSpreads(count, sizes, coverAlone) {
    var out = [], i = 0
    while (i < count) {
        if (i === 0 && coverAlone) { out.push([0]); i = 1; continue }
        if (isWide(sizes[i]) || i + 1 >= count || isWide(sizes[i + 1])) { out.push([i]); i++ }
        else { out.push([i, i + 1]); i += 2 }
    }
    return out
}

function spreadIndex(spreads, page) {
    for (var i = 0; i < spreads.length; i++)
        for (var j = 0; j < spreads[i].length; j++)
            if (spreads[i][j] === page) return i
    return Math.max(0, spreads.length - 1)
}

// ── Zoom and pan ──────────────────────────────────────────────────────────────

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// What a page (or a spread of pages side by side, same height) is drawn at, to fit a view.
// aspects: [w / h, ...]. Returns { h, widths: [...], w }.
function fitSize(vw, vh, aspects) {
    var total = 0
    for (var i = 0; i < aspects.length; i++) total += aspects[i]
    if (total <= 0 || vw <= 0 || vh <= 0) return { h: 0, w: 0, widths: aspects.map(function () { return 0 }) }
    var h = Math.min(vh, vw / total)
    return { h: h, w: total * h, widths: aspects.map(function (a) { return a * h }) }
}

// The pan keeps the zoomed content covering the view: no gap on a side that is bigger than the
// view, centred on a side that is smaller. cw / ch = the content's size at zoom 1.
function clampPan(vw, vh, cw, ch, zoom, px, py) {
    var mx = Math.max(0, (cw * zoom - vw) / 2)
    var my = Math.max(0, (ch * zoom - vh) / 2)
    return { panX: clamp(px, -mx, mx), panY: clamp(py, -my, my) }
}

// Zoom to `nz` keeping the point (fx, fy) of the view where it is. The content is centred
// in the view at pan 0.
function zoomAbout(vw, vh, cw, ch, zoom, panX, panY, nz, fx, fy, zmin, zmax) {
    var z = clamp(nz, zmin, zmax)
    var k = zoom > 0 ? z / zoom : 1
    var cx = vw / 2 + panX, cy = vh / 2 + panY
    var p = clampPan(vw, vh, cw, ch, z, fx - (fx - cx) * k - vw / 2, fy - (fy - cy) * k - vh / 2)
    return { zoom: z, panX: p.panX, panY: p.panY }
}

// One zoom step in or out (dir +1 / -1), snapping back to exactly 1 near it.
function stepZoom(z, dir, zmin, zmax) {
    var n = dir > 0 ? z * 1.25 : z / 1.25
    if (Math.abs(n - 1) < 0.06) n = 1
    return clamp(Math.round(n * 100) / 100, zmin, zmax)
}

// ── Keys and clicks ───────────────────────────────────────────────────────────

// key: "left" | "right" | "up" | "down" (W A S D are the arrows). The answer is one of
// next, prev, scrollUp, scrollDown, panLeft, panRight, panUp, panDown, "" (nothing).
// A zoomed page is panned by the arrows; Space / Page keys still turn it.
function keyAction(modeId, key, zoomed) {
    var m = modeInfo(modeId)
    var pan = { left: "panLeft", right: "panRight", up: "panUp", down: "panDown" }[key] || ""
    if (m.family === "strip") {
        if (key === "up") return "scrollUp"
        if (key === "down") return "scrollDown"
        return zoomed ? pan : ""
    }
    if (zoomed) return pan
    if (m.dir === "v") return key === "up" ? "prev" : key === "down" ? "next" : ""
    var fwd = m.dir === "rtl" ? "left" : "right"
    var back = m.dir === "rtl" ? "right" : "left"
    return key === fwd ? "next" : key === back ? "prev" : ""
}

// A click at (x, y) in a w x h view: the outer thirds turn the page, the middle shows or
// hides the bar. A long strip has no zones.
function tapAction(modeId, x, y, w, h) {
    var m = modeInfo(modeId)
    if (m.family === "strip" || w <= 0 || h <= 0) return "menu"
    if (m.dir === "v") {
        var fy = y / h
        return fy < 1 / 3 ? "prev" : fy > 2 / 3 ? "next" : "menu"
    }
    var fx = x / w
    if (fx >= 1 / 3 && fx <= 2 / 3) return "menu"
    var left = fx < 1 / 3
    if (m.dir === "rtl") return left ? "next" : "prev"
    return left ? "prev" : "next"
}

function keysHint(modeId) {
    var m = modeInfo(modeId)
    if (m.family === "strip") return "\u2193 / S scroll down \u00b7 \u2191 / W scroll up"
    if (m.dir === "v")   return "\u2193 / S next \u00b7 \u2191 / W back"
    if (m.dir === "rtl") return "\u2190 / A next \u00b7 \u2192 / D back"
    return "\u2192 / D next \u00b7 \u2190 / A back"
}

// ── Saving a page ─────────────────────────────────────────────────────────────

function sanitize(s, fallback) {
    var t = String(s || "").replace(/[\\\/:*?"<>|\r\n\t]+/g, " ").replace(/\s+/g, " ").replace(/^[.\s]+|[.\s]+$/g, "")
    if (t.length > 80) t = t.substring(0, 80).replace(/\s+$/, "")
    return t.length > 0 ? t : (fallback || "manga")
}

function pad(n, width) {
    var s = String(n)
    while (s.length < width) s = "0" + s
    return s
}

// { dir, base } for page `index` (0-based) of a chapter: "<title>" / "<title> - ch 12 - p003"
function saveName(mangaTitle, chapterLabel, index) {
    return {
        dir:  sanitize(mangaTitle, "manga"),
        base: sanitize(mangaTitle, "manga") + " - " + sanitize(chapterLabel, "chapter") + " - p" + pad(index + 1, 3)
    }
}
