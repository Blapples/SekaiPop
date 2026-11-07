.pragma library

// The logic behind the Downloader widget (services/DownloaderService.qml,
// modules/sekai/desktopWidgets/DownloaderWidget.qml and DownloaderTile.qml). No QML in here, so it
// can be unit-tested with plain node (tests/downloader-test/downloader_unit.js).
//
// What scripts/downloader/download.sh prints, one line at a time (parseLine reads it):
//   SEKAI|engine|<which>      SEKAI|title|<name>        SEKAI|prog|<percent>|<speed>|<time left>
//   SEKAI|item|<type>\t<address>\t<picture>   SEKAI|choose|<how many>
//   SEKAI|file|<path>         SEKAI|err|<what went wrong>         SEKAI|done

var KEEP_DONE = 12
var KEEP_JOBS = 30

var MODES = ["video", "audio", "mute"]
var QUALITIES = ["max", "1080", "720", "480"]
var AUDIO_FORMATS = ["mp3", "opus", "m4a", "flac", "wav", "best"]
var ENGINES = ["auto", "ytdlp", "gallerydl", "cobalt"]
var NAMES = ["basic", "pretty", "classic", "nerdy"]
// The browsers whose login yt-dlp / gallery-dl can use ("" = none).
var BROWSERS = ["", "firefox", "chrome", "chromium", "brave", "edge", "vivaldi", "opera"]
var MAX_ITEMS = 60

// ===== links =====

// The first http(s) link in some text (a copied sentence, a share message), without the
// punctuation that came after it. "" when there is none.
function firstUrl(text) {
    var m = /https?:\/\/[^\s<>"'`]+/i.exec(String(text || ""))
    if (!m)
        return ""
    var u = m[0]
    // A link at the end of a sentence or inside brackets: "(see https://a.b/c)." -> https://a.b/c
    while (/[.,;:!?)\]}>]$/.test(u)) {
        // A ")" that closes a "(" inside the link (wikipedia pages) stays.
        if (u.charAt(u.length - 1) === ")" && u.indexOf("(") >= 0 && u.split(")").length <= u.split("(").length)
            break
        u = u.slice(0, -1)
    }
    return /^https?:\/\/[^\/\s]+\.[^\/\s]+|^https?:\/\/localhost|^https?:\/\/\d+\.\d+\.\d+\.\d+/i.test(u) ? u : ""
}

function isUrl(text) {
    return firstUrl(text) !== ""
}

// "https://www.youtube.com/watch?v=x" -> "youtube.com"
function hostOf(url) {
    var m = /^https?:\/\/([^\/?#:]+)/i.exec(String(url || ""))
    if (!m)
        return ""
    return m[1].toLowerCase().replace(/^www\./, "").replace(/^m\./, "")
}

// The word on the tile for a link: "youtube.com" -> "YOUTUBE", "music.youtube.com" -> "YOUTUBE".
function siteWord(url) {
    var h = hostOf(url)
    if (h === "")
        return ""
    var parts = h.split(".")
    var tld2 = ["co", "com", "org", "net", "gov", "ac"]
    var n = parts.length
    var core = n >= 3 && tld2.indexOf(parts[n - 2]) >= 0 ? parts[n - 3] : (n >= 2 ? parts[n - 2] : parts[0])
    return core.toUpperCase()
}

// ===== options =====

function clampMode(m) {
    return MODES.indexOf(m) >= 0 ? m : "video"
}

function clampQuality(q) {
    var s = String(q)
    return QUALITIES.indexOf(s) >= 0 ? s : "1080"
}

function clampAudio(a) {
    return AUDIO_FORMATS.indexOf(a) >= 0 ? a : "mp3"
}

function clampEngine(e) {
    return ENGINES.indexOf(e) >= 0 ? e : "auto"
}

function clampNames(n) {
    return NAMES.indexOf(n) >= 0 ? n : "basic"
}

function clampBrowser(b) {
    return BROWSERS.indexOf(b) >= 0 ? b : ""
}

// A subtitle language: two or three letters, maybe with a region ("en", "pt-BR"). "" = none.
function cleanLang(l) {
    var s = String(l || "").trim()
    return /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,4})?$/.test(s) ? s : ""
}

// The next one in a list after `current` (wraps round); the first when `current` is not in it.
function nextIn(list, current) {
    var i = list.indexOf(current)
    return list[(i + 1) % list.length]
}

// "max" -> "BEST", "1080" -> "1080P"
function qualityText(q) {
    return q === "max" ? "BEST" : q + "P"
}

function modeText(m) {
    return m === "audio" ? "AUDIO" : (m === "mute" ? "MUTE" : "VIDEO")
}

function modeIcon(m) {
    return m === "audio" ? "music_note" : (m === "mute" ? "volume_off" : "movie")
}

// What can do the work. "auto" tries what is installed in turn (yt-dlp, then gallery-dl for
// pictures, then a cobalt instance when one is set): it is "auto" when at least one of them can
// run. A named engine is that one only. Returns "" when nothing can: the widget then says what is
// missing.
function pickEngine(engine, haveYtdlp, cobaltUrl, haveGalleryDl) {
    var haveCobalt = String(cobaltUrl || "").trim() !== ""
    if (engine === "ytdlp")
        return haveYtdlp ? "ytdlp" : ""
    if (engine === "gallerydl")
        return haveGalleryDl ? "gallerydl" : ""
    if (engine === "cobalt")
        return haveCobalt ? "cobalt" : ""
    return (haveYtdlp || haveGalleryDl || haveCobalt) ? "auto" : ""
}

// What to say when pickEngine found nothing.
function missingText(engine, haveYtdlp, cobaltUrl, haveGalleryDl) {
    var haveCobalt = String(cobaltUrl || "").trim() !== ""
    if (engine === "cobalt")
        return "No cobalt instance is set (Settings > Desktop > Downloader)"
    if (engine === "ytdlp")
        return "yt-dlp is not installed (pacman -S yt-dlp)"
    if (engine === "gallerydl")
        return "gallery-dl is not installed (pacman -S gallery-dl)"
    return (haveYtdlp || haveGalleryDl || haveCobalt) ? "" : "Install yt-dlp and gallery-dl (pacman -S yt-dlp gallery-dl), or set a cobalt instance"
}

// The word for an engine on the card.
function engineText(e) {
    return e === "ytdlp" ? "YT-DLP" : (e === "gallerydl" ? "GALLERY-DL" : (e === "cobalt" ? "COBALT" : String(e || "").toUpperCase()))
}

// A reason for the 1 x 1 tile's small chip: two or three words.
function shortReason(why) {
    var s = String(why || "")
    if (/^Nothing copied/i.test(s))
        return "NO LINK"
    if (/isn't a link/i.test(s))
        return "NOT A LINK"
    return "SET UP FIRST"
}

// ===== what the script says =====

// "  45.3%" -> 45.3, "100%" -> 100, "NA" / "" / "Unknown" -> -1 (not known: show a moving bar).
function percentOf(text) {
    var m = /(\d+(?:\.\d+)?)\s*%/.exec(String(text || ""))
    if (!m)
        return -1
    var v = Number(m[1])
    return Math.max(0, Math.min(100, v))
}

// yt-dlp says "Unknown B/s" / "NA" when it doesn't know yet: that is nothing, not a word to show.
function cleanText(text) {
    var s = String(text || "").trim()
    if (s === "" || /^(NA|N\/A|Unknown|Unknown B\/s|None)$/i.test(s))
        return ""
    return s
}

// A line of the script -> { kind: "title"|"prog"|"file"|"err"|"done", ... } or null.
function parseLine(line) {
    var s = String(line === undefined || line === null ? "" : line).replace(/\r$/, "")
    if (s.indexOf("SEKAI|") !== 0)
        return null
    var body = s.slice(6)
    var bar = body.indexOf("|")
    var kind = bar < 0 ? body : body.slice(0, bar)
    var rest = bar < 0 ? "" : body.slice(bar + 1)
    // Titles, paths and messages may hold a "|": everything after the kind is the text.
    if (kind === "title")
        return { kind: "title", text: rest }
    if (kind === "file")
        return { kind: "file", path: rest }
    if (kind === "err")
        return { kind: "err", text: rest }
    if (kind === "done")
        return { kind: "done" }
    if (kind === "engine")
        return { kind: "engine", name: rest }
    if (kind === "choose")
        return { kind: "choose", count: parseInt(rest, 10) || 0 }
    if (kind === "item") {
        // type, address, picture: separated by tabs (an address may hold a "|").
        var p = rest.split("\t")
        if (p.length < 2 || p[1] === "")
            return null
        return { kind: "item", type: p[0] === "video" || p[0] === "gif" ? p[0] : "photo", url: p[1], thumb: p[2] || "" }
    }
    if (kind === "prog") {
        var f = rest.split("|")
        return { kind: "prog", pct: percentOf(f[0]), speed: cleanText(f[1]), eta: cleanText(f[2]) }
    }
    return null
}

// The file name of a path.
function fileName(path) {
    var s = String(path || "")
    var i = s.lastIndexOf("/")
    return i >= 0 ? s.slice(i + 1) : s
}

// A name that fits on the card: cut in the middle so the end (the extension) stays.
function shorten(text, max) {
    var s = String(text || "")
    if (s.length <= max)
        return s
    if (max < 8)
        return s.slice(0, max)
    var tail = Math.min(10, Math.floor(max / 3))
    return s.slice(0, max - tail - 1) + "\u2026" + s.slice(s.length - tail)
}

// ===== the queue =====
// A job: { id, url, host, title, status, pct, speed, eta, file, error, mode, quality, engine, when }
// status: "queued" | "running" | "done" | "failed" | "cancelled"

function newJob(id, url, opts, now) {
    return {
        id: id,
        url: url,
        host: hostOf(url),
        title: "",
        status: "queued",
        pct: -1,
        speed: "",
        eta: "",
        file: "",
        error: "",
        mode: clampMode(opts.mode),
        quality: clampQuality(opts.quality),
        engine: opts.engine,
        items: [],       // what a post with several items holds (the picker)
        fetch: [],       // the ones chosen: what is fetched next
        when: now
    }
}

function nextQueued(jobs) {
    for (var i = 0; i < jobs.length; i++)
        if (jobs[i].status === "queued")
            return i
    return -1
}

function indexOfId(jobs, id) {
    for (var i = 0; i < jobs.length; i++)
        if (jobs[i].id === id)
            return i
    return -1
}

// Still to do: waiting, going, or waiting for the user to choose items.
function isLive(job) {
    return job.status === "queued" || job.status === "running" || job.status === "choosing"
}

// { running, queued, done, failed } for the little counters.
function stats(jobs) {
    var r = { running: 0, queued: 0, choosing: 0, done: 0, failed: 0 }
    for (var i = 0; i < jobs.length; i++) {
        var s = jobs[i].status
        if (s === "running") r.running++
        else if (s === "queued") r.queued++
        else if (s === "choosing") r.choosing++
        else if (s === "done") r.done++
        else if (s === "failed") r.failed++
    }
    return r
}

// A copy of the list with one job changed (a new array, so QML sees it change).
function patch(jobs, id, changes) {
    var out = jobs.slice()
    var i = indexOfId(out, id)
    if (i < 0)
        return out
    var j = {}
    for (var k in out[i])
        j[k] = out[i][k]
    for (var c in changes)
        j[c] = changes[c]
    out[i] = j
    return out
}

// Newest first, at most KEEP_JOBS; the ones still going always stay.
function trimJobs(jobs) {
    if (jobs.length <= KEEP_JOBS)
        return jobs
    var out = []
    var finished = 0
    for (var i = jobs.length - 1; i >= 0; i--) {
        if (isLive(jobs[i])) {
            out.unshift(jobs[i])
        } else if (finished < KEEP_JOBS) {
            out.unshift(jobs[i])
            finished++
        }
    }
    return out
}

// ===== what is remembered =====
// Only finished downloads that have a file: a restart forgets what was still going or failed.

function remember(jobs) {
    var out = []
    for (var i = 0; i < jobs.length; i++) {
        var j = jobs[i]
        if (j.status === "done" && j.file)
            out.push({ id: j.id, url: j.url, host: j.host, title: j.title, file: j.file, mode: j.mode, when: j.when })
    }
    return out.slice(Math.max(0, out.length - KEEP_DONE))
}

// What a saved file says -> jobs, ignoring anything that isn't one.
function recall(saved) {
    var out = []
    if (!Array.isArray(saved))
        return out
    for (var i = 0; i < saved.length; i++) {
        var s = saved[i]
        if (!s || typeof s.file !== "string" || s.file === "" || typeof s.id !== "number")
            continue
        out.push({
            id: s.id,
            url: typeof s.url === "string" ? s.url : "",
            host: typeof s.host === "string" ? s.host : hostOf(s.url),
            title: typeof s.title === "string" ? s.title : fileName(s.file),
            status: "done",
            pct: 100,
            speed: "",
            eta: "",
            file: s.file,
            error: "",
            mode: clampMode(s.mode),
            quality: "1080",
            engine: "",
            when: typeof s.when === "number" ? s.when : 0
        })
    }
    return out.slice(Math.max(0, out.length - KEEP_DONE))
}

// ===== the picker =====

// The first job that is waiting for the user to choose, or -1.
function firstChoosing(jobs) {
    for (var i = 0; i < jobs.length; i++)
        if (jobs[i].status === "choosing")
            return i
    return -1
}

function typeIcon(type) {
    return type === "video" ? "movie" : (type === "gif" ? "movie" : "image")
}

// Items from the script lines, at most MAX_ITEMS, nothing twice.
function addItem(items, item) {
    if (items.length >= MAX_ITEMS)
        return items
    for (var i = 0; i < items.length; i++)
        if (items[i].url === item.url)
            return items
    return items.concat([{ type: item.type, url: item.url, thumb: item.thumb }])
}

// A mask with every item on (or off): one boolean per item.
function maskOf(count, on) {
    var m = []
    for (var i = 0; i < count; i++)
        m.push(on !== false)
    return m
}

function toggleMask(mask, index) {
    var m = mask.slice()
    if (index >= 0 && index < m.length)
        m[index] = !m[index]
    return m
}

function countOn(mask) {
    var n = 0
    for (var i = 0; i < mask.length; i++)
        if (mask[i])
            n++
    return n
}

// The items that are on in the mask.
function chosenItems(items, mask) {
    var out = []
    for (var i = 0; i < items.length; i++)
        if (mask[i])
            out.push({ type: items[i].type, url: items[i].url })
    return out
}

// What the script wants for the chosen items: one per line, "<type><TAB><address>".
function itemsText(chosen) {
    var lines = []
    for (var i = 0; i < chosen.length; i++)
        lines.push(chosen[i].type + "\t" + chosen[i].url)
    return lines.join("\n")
}

// ===== the words for a failure =====

// What a login would fix: said under a failure so the user knows where to look.
function wantsLogin(why) {
    return /log ?in|sign ?in|cookies|private|age-restricted|confirm your age/i.test(String(why || ""))
}

// The next free id after the ones in a list.
function nextId(jobs) {
    var m = 0
    for (var i = 0; i < jobs.length; i++)
        if (jobs[i].id > m)
            m = jobs[i].id
    return m + 1
}
