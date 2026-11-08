.pragma library

// Pure logic for the novel reader's reading modes (no Quickshell imports;
// tests/novel-reader-test runs it in node). Top-level values use `var` on purpose: QML JS
// libraries don't reliably export top-level const/let.
//
//   MODES / modeInfo(id)           Scroll (one long page) and Paged (a screen at a time)
//   BACKGROUNDS / palette(id)      what a chapter is read on, and the type colours that go with it
//   normalizePrefs(raw)            the saved reader settings -> a clean record
//   keyAction / tapAction          what a key or a click does in each mode
//   pageStep / pageInfo            how far a page turn moves, and "page 3 of 12"
//   shouldPreload                  when the next chapter is asked for ahead of the reader
//   keysHint                       text for the toast
//   trackProgress / readDone       what goes to AniList: the highest chapter number read, and when a chapter counts as read
//   TRACK_STATUSES / statusLabel   the AniList list statuses
//   typeShort / statusWord         the short stamp for where a novel is from (LN, KR, CN, TW) and the
//                                  one word for how far it has come (Ongoing, Completed, ...)
//   scoreStamp / yourScoreStamp    "8.2" and "9/10" for the stamps on a cover and in a title's header
//   sourceTag                      the source's name as the small tag on a Library cover
//   dateText / releasedText        "2018-03-09" -> "Mar 9, 2018"; "Mar 9, 2018  ->  now" for the Info sheet
//   originLanguage / otherNames    "LIGHT NOVEL" -> "Japanese"; the names a title goes by besides its own
//   authorsText                    the people AniList lists for a novel, as one line

var MODES = [
    { id: "scroll", icon: "posts_carousel_vertical", label: "Scroll", short: "Scroll" },
    { id: "paged",  icon: "book_2",                  label: "Paged",  short: "Paged" }
]

// "theme" has no colours here: the reader takes them from the shell's palette. The others are
// fixed, so a white page stays white in every shell mode.
var BACKGROUNDS = [
    { id: "theme", label: "Shell" },
    { id: "black", label: "Black", bg: "#000000", title: "#e6e6e6", ink: "#c4c4c4", accent: "#6f6f6f" },
    { id: "sepia", label: "Sepia", bg: "#f4ecd8", title: "#2f2417", ink: "#4a3b2a", accent: "#a88b62" },
    { id: "white", label: "White", bg: "#ffffff", title: "#111111", ink: "#262626", accent: "#9a9a9a" }
]

var FONT_MIN = 13
var FONT_MAX = 26
var LINE_MIN = 1.4
var LINE_MAX = 2.2

var DEFAULT_PREFS = {
    mode: "scroll",
    background: "theme",
    fontSize: 17,
    lineHeight: 1.75,
    fullWindow: true          // the panel takes the whole screen (false = the side card on the right)
}

function modeInfo(id) {
    for (var i = 0; i < MODES.length; i++)
        if (MODES[i].id === id) return MODES[i]
    return MODES[0]
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

// The colours of a background, or null for the shell's own.
function palette(id) {
    for (var i = 0; i < BACKGROUNDS.length; i++)
        if (BACKGROUNDS[i].id === id) return BACKGROUNDS[i].bg ? BACKGROUNDS[i] : null
    return null
}

function nextMode(id) {
    for (var i = 0; i < MODES.length; i++)
        if (MODES[i].id === id) return MODES[(i + 1) % MODES.length].id
    return MODES[0].id
}

function nextBackground(id) {
    for (var i = 0; i < BACKGROUNDS.length; i++)
        if (BACKGROUNDS[i].id === id) return BACKGROUNDS[(i + 1) % BACKGROUNDS.length].id
    return BACKGROUNDS[0].id
}

function clampFont(v) {
    var n = Math.round(Number(v))
    if (!isFinite(n)) return DEFAULT_PREFS.fontSize
    return Math.max(FONT_MIN, Math.min(FONT_MAX, n))
}

function clampLine(v) {
    var n = Number(v)
    if (!isFinite(n)) return DEFAULT_PREFS.lineHeight
    return Math.max(LINE_MIN, Math.min(LINE_MAX, Math.round(n * 100) / 100))
}

function normalizePrefs(raw) {
    var r = (raw && typeof raw === "object") ? raw : {}
    return {
        mode:       isMode(r.mode) ? r.mode : DEFAULT_PREFS.mode,
        background: isBackground(r.background) ? r.background : DEFAULT_PREFS.background,
        fontSize:   r.fontSize === undefined ? DEFAULT_PREFS.fontSize : clampFont(r.fontSize),
        lineHeight: r.lineHeight === undefined ? DEFAULT_PREFS.lineHeight : clampLine(r.lineHeight),
        fullWindow: r.fullWindow === undefined ? DEFAULT_PREFS.fullWindow : r.fullWindow === true
    }
}

// What W A S D / the arrows do. `dir` is left | right | up | down.
//   scroll: up / down scroll the chapter, left / right go to the previous / next chapter
//   paged:  left and up turn back a page, right and down turn forward
// (a page turn past either end of the chapter goes on to the neighbouring chapter)
function keyAction(modeId, dir) {
    if (modeId === "paged") {
        if (dir === "left" || dir === "up") return "prev"
        if (dir === "right" || dir === "down") return "next"
        return ""
    }
    switch (dir) {
    case "up":    return "scroll_up"
    case "down":  return "scroll_down"
    case "left":  return "prev_chapter"
    case "right": return "next_chapter"
    }
    return ""
}

// A click at (x, y) of a w x h page: in Paged mode the outer thirds turn the page, the middle
// (and everything in Scroll mode) brings the bar back.
function tapAction(modeId, x, y, w, h) {
    if (modeId !== "paged" || !(w > 0)) return "menu"
    if (x < w * 0.3) return "prev"
    if (x > w * 0.7) return "next"
    return "menu"
}

// How far one page turn moves: the screen less a line and a bit, so the last line you read is
// still on screen after the turn.
function pageStep(viewH, fontSize, lineHeight) {
    var overlap = Math.round(fontSize * lineHeight * 1.2)
    return Math.max(80, Math.round(viewH - overlap))
}

// { index, total } (1-based) for a chapter scrolled to contentY, `maxY` being the furthest it
// can scroll.
function pageInfo(contentY, maxY, step) {
    var s = step > 0 ? step : 1
    var total = maxY > 0 ? Math.ceil(maxY / s) + 1 : 1
    var index = Math.min(total, Math.max(1, Math.round(Math.max(0, contentY) / s) + 1))
    return { index: index, total: total }
}

// The next chapter is asked for once the reader is this far through (0..1), or at once when
// the whole chapter fits one screen.
var PRELOAD_AT = 0.5

function shouldPreload(progress, fitsOneScreen) {
    return fitsOneScreen === true || progress >= PRELOAD_AT
}

function keysHint(modeId) {
    if (modeId === "paged")
        return "\u2190 / A back \u00b7 \u2192 / D / Space forward \u00b7 M mode"
    return "W / S scroll \u00b7 A / D chapter \u00b7 Space page \u00b7 M mode"
}

// ── Chapter list ──────────────────────────────────────────────────────────────

function chapterNumber(ch) {
    var m = /\d+(\.\d+)?/.exec(String(ch && ch.chapter !== undefined ? ch.chapter : ""))
    return m ? parseFloat(m[0]) : 0
}

// Reading order, oldest first: by chapter number, the source's own order (`index`) when two share a
// number (a source that restarts the numbering with every volume), else the order given.
function orderChapters(chapters) {
    var list = []
    for (var i = 0; i < (chapters || []).length; i++) list.push({ ch: chapters[i], pos: i })
    list.sort(function (a, b) {
        var d = chapterNumber(a.ch) - chapterNumber(b.ch)
        if (d !== 0) return d
        var ia = a.ch.index === undefined ? a.pos : a.ch.index
        var ib = b.ch.index === undefined ? b.pos : b.ch.index
        return ia !== ib ? ia - ib : a.pos - b.pos
    })
    return list.map(function (e) { return e.ch })
}

// "CH.12" for a chapter, "VOL.3" for a row that is a whole volume
function chapterTag(ch) {
    if (!ch) return "CH.?"
    var m = /\d+(\.\d+)?/.exec(String(ch.chapter === undefined ? "" : ch.chapter))
    var n = m ? m[0] : String(ch.chapter || "?")
    if (ch.kind === "volume") {
        var v = /\d+(\.\d+)?/.exec(String(ch.volume || ""))
        return "VOL." + (v ? v[0] : n)
    }
    return "CH." + n
}

// True when the title only says the number the stamp already says ("Chapter 47", "Vol. 2"): the row
// then shows its date where the title would be, and a chapter with a real name shows the name.
function titleIsPlain(title) {
    var t = String(title || "").trim()
    return t.length === 0 || /^(chapter|chap\.?|ch\.?|volume|vol\.?)\s*[\d.]+$/i.test(t)
}

// Where the reader left off, or null when there is nowhere to continue (nothing listed, or everything
// is read). `lastId` is the chapter opened last (the Library entry's), `isRead(id)` says what is read.
// A chapter opened last and not finished is resumed; else the first unread chapter after the furthest
// one read; a novel not started begins at the first. { chapter, started }
function continueTarget(chapters, lastId, isRead) {
    var ordered = orderChapters(chapters)
    if (ordered.length === 0) return null

    if (lastId) {
        for (var i = 0; i < ordered.length; i++)
            if (ordered[i].id === lastId && !isRead(ordered[i].id))
                return { chapter: ordered[i], started: true }
    }

    var furthest = -1
    for (var j = 0; j < ordered.length; j++)
        if (isRead(ordered[j].id)) furthest = j
    if (furthest < 0) return { chapter: ordered[0], started: false }

    for (var k = furthest + 1; k < ordered.length; k++)
        if (!isRead(ordered[k].id)) return { chapter: ordered[k], started: true }
    return null
}

// The ids from the first chapter up to `id`, itself included ("Up to here" in the selection bar)
function idsUpTo(chapters, id) {
    var ordered = orderChapters(chapters), out = []
    for (var i = 0; i < ordered.length; i++) {
        out.push(ordered[i].id)
        if (ordered[i].id === id) return out
    }
    return []
}

// ── AniList tracking ──────────────────────────────────────────────────────────

// The highest chapter number among the chapters `isRead(id)` says are read (the whole number:
// 12.5 counts as 12), the way the manga reader works out what to tell AniList. Chapters with no
// number (a "Prologue") are left out, and so are rows that are a whole volume ("Volume 2": the
// source numbers it in its list, but it is not chapter 2).
function trackProgress(chapters, isRead) {
    var ch = 0
    for (var i = 0; i < (chapters || []).length; i++) {
        var c = chapters[i]
        if (!c || !isRead(c.id) || c.kind === "volume") continue
        var m = /\d+(\.\d+)?/.exec(String(c.chapter === undefined ? "" : c.chapter))
        var n = m ? Math.floor(parseFloat(m[0])) : 0
        if (n > ch) ch = n
    }
    return ch
}

// The ids of the chapters AniList already counts as read: every numbered chapter up to
// `progress` (whole numbers, the way trackProgress reads them). Unnumbered ones are left out.
function chaptersUpTo(chapters, progress) {
    var ids = []
    if (!(progress > 0)) return ids
    for (var i = 0; i < (chapters || []).length; i++) {
        var c = chapters[i]
        if (!c || !c.id || c.kind === "volume") continue
        var m = /\d+(\.\d+)?/.exec(String(c.chapter === undefined ? "" : c.chapter))
        if (!m) continue
        if (Math.floor(parseFloat(m[0])) <= progress) ids.push(c.id)
    }
    return ids
}

// A chapter counts as read once the reader is this far through it (0..1), or has had it open
// for a moment when it fits one screen.
var READ_AT = 0.9

function readDone(progress, fitsOneScreen) {
    return fitsOneScreen === true || progress >= READ_AT
}

var TRACK_STATUSES = [
    { id: "CURRENT",   label: "Reading" },
    { id: "PLANNING",  label: "Planning" },
    { id: "COMPLETED", label: "Completed" },
    { id: "PAUSED",    label: "Paused" },
    { id: "DROPPED",   label: "Dropped" },
    { id: "REPEATING", label: "Rereading" }
]

function statusLabel(id) {
    for (var i = 0; i < TRACK_STATUSES.length; i++)
        if (TRACK_STATUSES[i].id === id) return TRACK_STATUSES[i].label
    return id || ""
}

// ── Stamps ───────────────────────────────────────────────────────────────────
// A cover is about 140 px wide, so what it says about itself has to be short. The server labels a
// novel by where it is from ("LIGHT NOVEL", "KOREAN NOVEL", ...); on a cover that is two letters.
// "LIGHT NOVEL" alone was wider than the card and sat on top of the score stamp.
var TYPE_SHORT = {
    "LIGHT NOVEL":   "LN",
    "KOREAN NOVEL":  "KR",
    "CHINESE NOVEL": "CN",
    "TAIWAN NOVEL":  "TW",
    "NOVEL":         "NOVEL"
}

function typeShort(type) {
    var t = String(type || "").trim().toUpperCase()
    if (t === "") return ""
    if (TYPE_SHORT[t] !== undefined) return TYPE_SHORT[t]
    // a label this list does not know: the first word, so it still fits
    var first = t.split(/\s+/)[0]
    return first.length > 6 ? first.slice(0, 6) : first
}

// AniList's own wording for how far a title has come -> the words the manga panel uses
// (Releasing -> Ongoing, Finished -> Completed). Anything else is kept as it is.
var STATUS_WORD = {
    "RELEASING":        "Ongoing",
    "Releasing":        "Ongoing",
    "FINISHED":         "Completed",
    "Finished":         "Completed",
    "NOT_YET_RELEASED": "Upcoming",
    "Upcoming":         "Upcoming",
    "CANCELLED":        "Cancelled",
    "Cancelled":        "Cancelled",
    "HIATUS":           "Hiatus",
    "Hiatus":           "Hiatus"
}

function statusWord(s) {
    s = String(s || "").trim()
    if (s === "") return ""
    return STATUS_WORD[s] !== undefined ? STATUS_WORD[s] : s
}

// AniList's average (0-100) the way the cards show it: 82 -> "8.2". "" for none.
function scoreStamp(avg) {
    avg = Number(avg) || 0
    return avg > 0 ? (avg / 10).toFixed(1) : ""
}

// Your own score for a stamp: "9/10", "85/100", "4\u2605". "" when the title is not scored. `format`
// is the AniList account's score format (POINT_100, POINT_10_DECIMAL, POINT_10, POINT_5, POINT_3).
function yourScoreStamp(score, score100, format) {
    score = Number(score) || 0
    score100 = Number(score100) || 0
    if (score <= 0 && score100 <= 0) return ""
    switch (format) {
    case "POINT_100":        return Math.round(score) + "/100"
    case "POINT_10_DECIMAL": return (Math.round(score * 10) / 10).toFixed(1) + "/10"
    case "POINT_10":         return Math.round(score) + "/10"
    case "POINT_5":          return Math.round(score) + "\u2605"
    case "POINT_3":          return score >= 3 ? ":)" : (score >= 2 ? ":|" : ":(")
    default:                 return (score100 / 10).toFixed(1) + "/10"
    }
}

// The source a novel is read from, as the short plate on its cover: a name in capitals, cut to
// fit ("FREEWEBNOVEL", "ROYAL ROAD \u00b7 EN"). "" when the id names no source.
var SOURCE_TAG_MAX = 14

function sourceTag(name) {
    var t = String(name || "").trim().toUpperCase()
    if (t.length <= SOURCE_TAG_MAX) return t
    return t.slice(0, SOURCE_TAG_MAX - 1).replace(/[\s\u00b7.\-]+$/, "") + "\u2026"
}

// ── The Info sheet's words ───────────────────────────────────────────────────
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// AniList's partial dates as the server writes them ("2018", "2018-03", "2018-03-09") for reading.
// "" for anything else.
function dateText(iso) {
    var m = /^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$/.exec(String(iso || ""))
    if (!m) return ""
    var mo = m[2] ? parseInt(m[2], 10) : 0
    if (mo < 1 || mo > 12) return m[1]
    var day = m[3] ? parseInt(m[3], 10) : 0
    return MONTHS[mo - 1] + (day > 0 ? " " + day + "," : "") + " " + m[1]
}

// When it came out: "Mar 9, 2018  \u2192  now" while it is going on, "... \u2192  Jun 2, 2021" once it has ended,
// just the start when that is all there is; the year alone when the day is not known.
function releasedText(start, end, status, year) {
    var from = dateText(start)
    if (from === "") return Number(year) > 0 ? String(Math.floor(Number(year))) : ""
    var word = statusWord(status)
    var to = dateText(end)
    if (to !== "" && to !== from && (word === "Completed" || word === "Cancelled")) return from + "  \u2192  " + to
    if (word === "Ongoing") return from + "  \u2192  now"
    return from
}

var ORIGIN_LANGUAGE = {
    "LIGHT NOVEL":   "Japanese",
    "KOREAN NOVEL":  "Korean",
    "CHINESE NOVEL": "Chinese",
    "TAIWAN NOVEL":  "Chinese (Taiwan)"
}

function originLanguage(type) {
    var t = String(type || "").trim().toUpperCase()
    return ORIGIN_LANGUAGE[t] !== undefined ? ORIGIN_LANGUAGE[t] : ""
}

// The names AniList knows a title by, without the one already shown as its title (the same words
// in another case or with other punctuation count as the same name).
function otherNames(names, title) {
    var seen = {}
    seen[normTitle(title)] = true
    var out = []
    for (var i = 0; i < (names ? names.length : 0); i++) {
        var n = String(names[i] || "").trim()
        var k = normTitle(n)
        if (n === "" || k === "" || seen[k]) continue
        seen[k] = true
        out.push(n)
    }
    return out
}

// The people AniList lists for a novel, once each, as one line ("Tappei Nagatsuki, Shinichirou Otsuka")
function authorsText(people) {
    var out = []
    for (var i = 0; i < (people ? people.length : 0); i++) {
        var n = String(people[i] && people[i].name || "").trim()
        if (n !== "" && out.indexOf(n) < 0) out.push(n)
    }
    return out.join(", ")
}

// ── Discover: AniList's novels, with filters ─────────────────────────────────
// The lists the filter keys offer and the query the backend (/al/browse) is asked with. The
// backend checks every value again; this keeps the panel and the URL in step.
//
//   DISCOVER_SORTS / GENRES / COUNTRIES / STATUSES / SCORE_MIN / SCORE_MAX / LENGTHS   the options
//   yearOptions(thisYear)         Any, then this year and 39 back
//   lengthRange(key)              a Length option -> { volMin, volMax, chMin, chMax }
//   discoverQuery(s)              the /al/browse query string for a filter state
//   discoverFilterCount(s)        how many filters are on (the count on the key)
//   lengthText(card)              "5 vols", "550 ch" or "5 vols · 40 ch"
//   cardMeta(card)                "2018 · Releasing" for under a title

var DISCOVER_SORTS = [
    { label: "Trending",  value: "TRENDING_DESC"   },
    { label: "Popular",   value: "POPULARITY_DESC" },
    { label: "Top rated", value: "SCORE_DESC"      },
    { label: "Favorites", value: "FAVOURITES_DESC" },
    { label: "Newest",    value: "START_DATE_DESC" }
]

var GENRES = [
    "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror",
    "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance",
    "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"
]

// AniList has one NOVEL format; where a novel is from is the difference that matters
var COUNTRIES = [
    { label: "Any",                    value: ""   },
    { label: "Japan (light novels)",   value: "JP" },
    { label: "Korea (web novels)",     value: "KR" },
    { label: "China (web novels)",     value: "CN" },
    { label: "Taiwan",                 value: "TW" }
]

var STATUSES = [
    { label: "Releasing", value: "RELEASING"        },
    { label: "Finished",  value: "FINISHED"         },
    { label: "Hiatus",    value: "HIATUS"           },
    { label: "Upcoming",  value: "NOT_YET_RELEASED" },
    { label: "Cancelled", value: "CANCELLED"        }
]

// AniList scores run 0-100 and the cards show them out of 10, so the options do too
var SCORE_MIN = [
    { label: "Any", value: 0 }, { label: "5.0+", value: 50 }, { label: "6.0+", value: 60 },
    { label: "7.0+", value: 70 }, { label: "7.5+", value: 75 }, { label: "8.0+", value: 80 },
    { label: "8.5+", value: 85 }, { label: "9.0+", value: 90 }
]
var SCORE_MAX = [
    { label: "Any", value: 0 }, { label: "Up to 5.0", value: 50 }, { label: "Up to 6.0", value: 60 },
    { label: "Up to 7.0", value: 70 }, { label: "Up to 8.0", value: 80 }, { label: "Up to 9.0", value: 90 }
]

// How long a novel is (`chip` is the short text the filter key shows once one is chosen). Light novels are counted in volumes, web novels in chapters, so the
// options are both. A title AniList has no count for is left out while one is chosen.
var LENGTHS = [
    { label: "Any",                      chip: "Any",        value: "",         volMin: 0,  volMax: 0,  chMin: 0,   chMax: 0   },
    { label: "Short · up to 3 volumes",  chip: "up to 3 vols",  value: "vol-short", volMin: 0,  volMax: 3,  chMin: 0,   chMax: 0   },
    { label: "Medium · 4-10 volumes",    chip: "4-10 vols",     value: "vol-mid",   volMin: 4,  volMax: 10, chMin: 0,   chMax: 0   },
    { label: "Long · 11+ volumes",       chip: "11+ vols",      value: "vol-long",  volMin: 11, volMax: 0,  chMin: 0,   chMax: 0   },
    { label: "Short · up to 100 chapters", chip: "up to 100 ch", value: "ch-short", volMin: 0, volMax: 0,  chMin: 0,   chMax: 100 },
    { label: "Medium · 101-500 chapters", chip: "101-500 ch",   value: "ch-mid",   volMin: 0,  volMax: 0,  chMin: 101, chMax: 500 },
    { label: "Long · 501+ chapters",     chip: "501+ ch",       value: "ch-long",   volMin: 0,  volMax: 0,  chMin: 501, chMax: 0   }
]

function yearOptions(thisYear) {
    var out = [{ label: "Any", value: 0 }]
    for (var i = 0; i < 40; i++)
        out.push({ label: String(thisYear - i), value: thisYear - i })
    return out
}

function lengthRange(key) {
    for (var i = 0; i < LENGTHS.length; i++) {
        if (LENGTHS[i].value === key)
            return { volMin: LENGTHS[i].volMin, volMax: LENGTHS[i].volMax,
                     chMin: LENGTHS[i].chMin, chMax: LENGTHS[i].chMax }
    }
    return { volMin: 0, volMax: 0, chMin: 0, chMax: 0 }
}

// s: { query, sort, genres[], tags[], country, statuses[], scoreMin, scoreMax, year, length, adult, page }
function discoverQuery(s) {
    var q = (s.query || "").trim()
    var out = ["page=" + Math.max(1, s.page || 1)]
    // a typed search is ordered by best match (the backend's default for one), a list by the sort
    if (q.length > 0)               out.push("q=" + encodeURIComponent(q))
    else if (s.sort)                out.push("sort=" + s.sort)
    if (s.genres && s.genres.length > 0)     out.push("genres=" + encodeURIComponent(s.genres.join(",")))
    if (s.tags && s.tags.length > 0)         out.push("tags=" + encodeURIComponent(s.tags.join("|")))
    if (s.country)                  out.push("country=" + s.country)
    if (s.statuses && s.statuses.length > 0) out.push("status=" + s.statuses.join(","))
    if (s.scoreMin > 0)             out.push("score_min=" + s.scoreMin)
    if (s.scoreMax > 0)             out.push("score_max=" + s.scoreMax)
    if (s.year > 0)                 out.push("year=" + s.year)
    var r = lengthRange(s.length || "")
    if (r.volMin > 0) out.push("vol_min=" + r.volMin)
    if (r.volMax > 0) out.push("vol_max=" + r.volMax)
    if (r.chMin > 0)  out.push("ch_min=" + r.chMin)
    if (r.chMax > 0)  out.push("ch_max=" + r.chMax)
    if (s.adult)                    out.push("adult=1")
    return out.join("&")
}

function discoverFilterCount(s) {
    return (s.genres ? s.genres.length : 0) + (s.tags ? s.tags.length : 0)
         + (s.statuses ? s.statuses.length : 0)
         + (s.country ? 1 : 0) + (s.length ? 1 : 0)
         + (s.scoreMin > 0 ? 1 : 0) + (s.scoreMax > 0 ? 1 : 0)
         + (s.year > 0 ? 1 : 0) + (s.adult ? 1 : 0)
}

function lengthText(c) {
    var parts = []
    if (c && c.volumes > 0)  parts.push(c.volumes + (c.volumes === 1 ? " vol" : " vols"))
    if (c && c.chapters > 0) parts.push(c.chapters + " ch")
    return parts.join(" · ")
}

function cardMeta(c) {
    var parts = []
    if (c && c.year > 0) parts.push(String(c.year))
    if (c && c.status)   parts.push(c.status)
    return parts.join(" · ")
}

// ── Finding a Discover title in the source ───────────────────────────────────
// A title on AniList and the same novel on a source are rarely spelled the same ("Re:ZERO -Starting
// Life in Another World-" / "Re:Zero kara Hajimeru Isekai Seikatsu"), so the source's answers are
// ordered by how close each is to any of AniList's names for it, and the closest is marked.
//
//   normTitle(s)                  lower case, no accents, letters and digits only
//   matchScore(title, names)      0..1: same name 1, one inside the other 0.85, else shared words
//   rankCandidates(list, names)   the list (each row { title, ... }) with `score` and `best`, closest first
//   BEST_MIN                      the score a row needs to be marked as the best match

var BEST_MIN = 0.85

function normTitle(s) {
    var t = String(s === undefined || s === null ? "" : s).toLowerCase()
    if (typeof t.normalize === "function") t = t.normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
    return t.replace(/[^a-z0-9\u3040-\u30ff\u4e00-\u9fff\uac00-\ud7af]+/g, " ").replace(/^\s+|\s+$/g, "")
}

function _words(s) {
    var out = [], seen = {}
    var parts = s.split(" ")
    for (var i = 0; i < parts.length; i++)
        if (parts[i].length > 0 && !seen[parts[i]]) { seen[parts[i]] = true; out.push(parts[i]) }
    return out
}

function matchScore(title, names) {
    var a = normTitle(title)
    if (a.length === 0) return 0
    var best = 0
    for (var i = 0; i < (names || []).length; i++) {
        var b = normTitle(names[i])
        if (b.length === 0) continue
        var score = 0
        if (a === b) score = 1
        else if ((a.length >= 4 && b.indexOf(a) >= 0) || (b.length >= 4 && a.indexOf(b) >= 0)) score = 0.85
        else {
            var wa = _words(a), wb = _words(b), shared = 0
            for (var j = 0; j < wa.length; j++) if (wb.indexOf(wa[j]) >= 0) shared++
            var union = wa.length + wb.length - shared
            score = union > 0 ? 0.8 * shared / union : 0
        }
        if (score > best) best = score
    }
    return best
}

function rankCandidates(list, names) {
    var rows = (list || []).map(function(r, i) {
        return Object.assign({}, r, { score: matchScore(r.title, names), _i: i })
    })
    rows.sort(function(x, y) { return y.score - x.score || x._i - y._i })
    for (var i = 0; i < rows.length; i++) {
        rows[i].best = i === 0 && rows[i].score >= BEST_MIN
        delete rows[i]._i
    }
    return rows
}
