.pragma library

// The rules of the Custom lockscreen (LockCanvas.qml), kept free of QML so
// tests/lock-canvas-test/canvas_model_unit.js can run them under node.
//
// A Custom lockscreen is a BOARD: a few widgets (clock, date, weather ...) placed
// anywhere on the screen, and the password block (the "core"), which is always there.
// The boards are saved as JSON (services/LockCanvasService.qml), and that file is
// DATA ONLY: this file turns whatever is in it into a board that is safe to draw, and
// nothing in it is ever run or loaded as code. A widget is a name from CATALOG below;
// LockCanvas.qml maps the name to a QML file it already contains. A name that is not in
// the catalog is dropped, so a hand-edited or damaged file can only ever give a plainer
// screen, never a different program and never a screen without a password field.
//
//   parse(text)                      the saved text -> a model (a plain default if unreadable)
//   stringify(model)                 a model -> the text to save
//   boardFor(model, screen)          that monitor's board (else the shared one)
//   defaultBoard()                   what a first run shows
//   cleanBoard(board)                any board-shaped thing -> a safe board
//   addItem / moveItem / scaleItem / setOption / removeItem / setCore
//                                    edits; each returns a NEW, clean board
//   withBoard(model, screen, board)  a model with that monitor's board replaced
//   hasBoard(model, screen)          true if that monitor has a board of its own
//   dropBoard(model, screen)         a model where that monitor uses the shared board again
//   describe(kind)                   a widget's title, icon, limit and options (the editor's shelf)
//   coreLimits()                     how far the password block may move (the editor draws it)
//   placeAxis(frac, size, scale, total)
//                                    where (x or y) a widget goes so it stays on screen
//   presetPart(model)                what a desktop preset holds of the lockscreen: every
//                                    board, and the list of widgets this build has
//   wornModel(part)                  the model a preset's part gives (widgets it did not
//                                    know are left out), or null if it holds no layout
//   keepKinds(model, keep)           a model with only the widgets named in `keep`
//   legacyKinds()                    the widgets that existed before presets held a layout
//
// Positions are FRACTIONS of the screen (the widget's centre), so a layout looks the same
// on a 1080p panel and a 4K one and on another monitor. Sizes are scales on top of the
// size the widget has at 1080 p.

const VERSION = 1
const MAX_ITEMS = 24
const SCALE_MIN = 0.5
const SCALE_MAX = 2.5
const MAX_TEXT = 120
const MAX_PATH = 4096
const SHARED = "*"

// The password block's nominal size (design pixels at 1080 p). It can be moved a little,
// never hidden, scaled, or put off the screen: the ranges below keep it in the lower half.
const CORE = { w: 916, h: 128, xMin: 0.28, xMax: 0.72, yMin: 0.5, yMax: 0.93, x: 0.5, y: 0.86 }

const IMAGE_EXT = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]

// The widgets there were before a desktop preset carried a lockscreen layout. A preset saved
// since holds the list of widgets the shell had (`kinds`, see presetPart); one saved before
// holds nothing of the lockscreen, so this fixed list stands for what it knew. Wearing it
// leaves out every widget added after (the information widgets: greeting, sun, timer,
// notifications, event, to-do, countdown, and anything added from now on). Never edit this
// list: a widget added later is NOT put in it, that is the whole point.
const LEGACY_KINDS = ["clock", "date", "user", "weather", "battery", "media", "lyrics", "text", "image"]

// Every widget a lockscreen can have. `privacy` is "public" (fine for anyone walking past)
// or "private" (names, events, messages: shown masked until the user says otherwise: the
// notifications, next event and to-do widgets). `w` and `h` are the nominal size at 1080 p, only used to place the first layout
// without overlaps; the widgets size themselves.
// An option is { type: "enum", values, def } | { type: "bool", def } | { type: "string", max, def }
// | { type: "path", def } (an absolute path to a picture). A string option may also carry a
// `pattern` (a regular expression the whole text must match, or it is the default).
const CATALOG = {
    clock: {
        title: "Clock", icon: "schedule", privacy: "public", w: 560, h: 230, max: 1,
        options: { format: { type: "enum", values: ["auto", "12h", "24h"], def: "auto" } }
    },
    date: {
        title: "Date", icon: "calendar_month", privacy: "public", w: 520, h: 116, max: 1,
        options: { style: { type: "enum", values: ["long", "short"], def: "long" } }
    },
    user: {
        title: "User", icon: "badge", privacy: "public", w: 470, h: 116, max: 1,
        options: { since: { type: "bool", def: true } }
    },
    // "Good morning" by the hour, with your name if you like.
    greeting: {
        title: "Greeting", icon: "waving_hand", privacy: "public", w: 600, h: 116, max: 1,
        options: { name: { type: "bool", def: true } }
    },
    weather: {
        title: "Weather", icon: "partly_cloudy_day", privacy: "public", w: 430, h: 116, max: 1,
        options: {
            place: { type: "bool", def: false },
            condition: { type: "bool", def: true }
        }
    },
    // Today's sunrise and sunset, from the weather reading.
    sun: {
        title: "Sun", icon: "wb_twilight", privacy: "public", w: 520, h: 116, max: 1,
        options: {}
    },
    battery: {
        title: "Battery", icon: "battery_android_full", privacy: "public", w: 240, h: 116, max: 1,
        options: { percent: { type: "bool", def: true } }
    },
    media: {
        title: "Now playing", icon: "music_note", privacy: "public", w: 640, h: 116, max: 1,
        options: { controls: { type: "bool", def: true } }
    },
    // The line being sung. It used to be an option of the Now playing widget; it is a widget of
    // its own so it can go anywhere. Placing it is what switches it on (it asks the lyrics
    // providers for the song, so it is not in the first layout).
    lyrics: {
        title: "Lyrics", icon: "lyrics", privacy: "public", w: 640, h: 128, max: 1,
        options: {}
    },
    // The dock's timer / stopwatch / pomodoro, while one is running.
    timer: {
        title: "Timer", icon: "timer", privacy: "public", w: 330, h: 116, max: 1,
        options: { label: { type: "bool", def: true } }
    },
    // The three below are PRIVATE: they show a count and nothing that was written by you or to
    // you, until you turn `details` on (notifications have no details at all: only the number).
    notifications: {
        title: "Notifications", icon: "notifications", privacy: "private", w: 470, h: 116, max: 1,
        options: {}
    },
    event: {
        title: "Next event", icon: "event", privacy: "private", w: 560, h: 116, max: 1,
        options: { details: { type: "bool", def: false } }
    },
    todo: {
        title: "To-do", icon: "checklist", privacy: "private", w: 520, h: 116, max: 1,
        options: { details: { type: "bool", def: false } }
    },
    // Days to (or since) a day you pick; `date` is YYYY-MM-DD, anything else is "no date yet".
    countdown: {
        title: "Countdown", icon: "hourglass_top", privacy: "public", w: 470, h: 116, max: 4,
        options: {
            label: { type: "string", max: 40, def: "Event" },
            date: { type: "string", max: 10, def: "", pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" }
        }
    },
    text: {
        title: "Text", icon: "title", privacy: "public", w: 520, h: 90, max: 6,
        options: {
            text: { type: "string", max: MAX_TEXT, def: "Hello" },
            size: { type: "enum", values: ["small", "medium", "large"], def: "medium" }
        }
    },
    image: {
        title: "Image", icon: "image", privacy: "public", w: 320, h: 320, max: 6,
        options: {
            path: { type: "path", def: "" },
            shape: { type: "enum", values: ["rounded", "circle", "square"], def: "rounded" }
        }
    }
}

function kinds() {
    return Object.keys(CATALOG)
}

// A copy of LEGACY_KINDS (a const is not reachable from QML, a function is).
function legacyKinds() {
    return LEGACY_KINDS.slice()
}

function known(kind) {
    return typeof kind === "string" && Object.prototype.hasOwnProperty.call(CATALOG, kind)
}

function isPrivate(kind) {
    return known(kind) && CATALOG[kind].privacy === "private"
}

// ===== small checks =====

function num(v, lo, hi, def) {
    const n = typeof v === "number" ? v : NaN
    if (!isFinite(n))
        return def
    return Math.max(lo, Math.min(hi, n))
}

// No control characters (newlines included), trimmed, cut to `max`.
function cleanString(v, max, def) {
    if (typeof v !== "string")
        return def
    let out = ""
    for (let i = 0; i < v.length; i++) {
        if (v.charCodeAt(i) >= 32 && v.charCodeAt(i) !== 127)
            out += v[i]
    }
    return out.trim().slice(0, max)
}

// An absolute path to a picture: no "..", no "?" or "#" (it becomes a file:// URL), a picture
// extension. Anything else is "no picture".
function cleanPath(v) {
    if (typeof v !== "string" || v.length === 0 || v.length > MAX_PATH)
        return ""
    if (v[0] !== "/" || /[\u0000-\u001f\u007f?#]/.test(v))
        return ""
    if (v.split("/").indexOf("..") >= 0)
        return ""
    const m = /\.([A-Za-z0-9]+)$/.exec(v)
    if (!m || IMAGE_EXT.indexOf(m[1].toLowerCase()) < 0)
        return ""
    return v
}

function cleanOption(spec, v) {
    if (spec.type === "enum")
        return spec.values.indexOf(v) >= 0 ? v : spec.def
    if (spec.type === "bool")
        return typeof v === "boolean" ? v : spec.def
    if (spec.type === "string") {
        const text = cleanString(v, spec.max, spec.def)
        // An option may say what shape its text must have (the countdown's date); anything
        // else is the default.
        if (spec.pattern && text !== "" && !new RegExp(spec.pattern).test(text))
            return spec.def
        return text
    }
    if (spec.type === "path")
        return cleanPath(v)
    return spec.def
}

function defaultOptions(kind) {
    const out = {}
    const spec = known(kind) ? CATALOG[kind].options : {}
    for (const k of Object.keys(spec))
        out[k] = spec[k].def
    return out
}

// Only the options the catalog lists, each checked; the rest of what was saved is dropped.
function cleanOptions(kind, raw) {
    const out = {}
    const spec = CATALOG[kind].options
    const src = raw && typeof raw === "object" ? raw : {}
    for (const k of Object.keys(spec))
        out[k] = cleanOption(spec[k], src[k])
    return out
}

function uidFits(kind, uid) {
    return typeof uid === "string" && new RegExp("^" + kind + "-[0-9]{1,4}$").test(uid)
}

// ===== boards =====

function cleanItem(raw, taken) {
    if (!raw || typeof raw !== "object" || !known(raw.kind))
        return null
    const kind = raw.kind
    let uid = raw.uid
    if (!uidFits(kind, uid) || taken[uid])
        uid = nextUid(kind, taken)
    return {
        uid: uid,
        kind: kind,
        x: num(raw.x, 0, 1, 0.5),
        y: num(raw.y, 0, 1, 0.5),
        scale: num(raw.scale, SCALE_MIN, SCALE_MAX, 1),
        options: cleanOptions(kind, raw.options)
    }
}

function nextUid(kind, taken) {
    let n = 1
    while (taken[kind + "-" + n])
        n++
    return kind + "-" + n
}

function cleanCore(raw) {
    const c = raw && typeof raw === "object" ? raw : {}
    return {
        x: num(c.x, CORE.xMin, CORE.xMax, CORE.x),
        y: num(c.y, CORE.yMin, CORE.yMax, CORE.y)
    }
}

// Any board-shaped thing -> a board you can draw: known widgets only, no more than the
// catalog allows of each, at most MAX_ITEMS, every number in range, a password block.
function cleanBoard(raw) {
    const src = raw && typeof raw === "object" ? raw : {}
    const list = Array.isArray(src.items) ? src.items : []
    const items = []
    const taken = {}
    const count = {}
    for (const r of list) {
        if (items.length >= MAX_ITEMS)
            break
        const it = cleanItem(r, taken)
        if (!it)
            continue
        if ((count[it.kind] || 0) >= CATALOG[it.kind].max)
            continue
        count[it.kind] = (count[it.kind] || 0) + 1
        taken[it.uid] = true
        items.push(it)
    }
    return { core: cleanCore(src.core), items: items }
}

function defaultBoard() {
    const at = (kind, x, y) => ({ uid: kind + "-1", kind: kind, x: x, y: y, scale: 1, options: defaultOptions(kind) })
    return cleanBoard({
        core: { x: CORE.x, y: CORE.y },
        items: [
            at("clock", 0.5, 0.2),
            at("date", 0.5, 0.375),
            at("user", 0.14, 0.09),
            at("weather", 0.8, 0.09),
            at("battery", 0.93, 0.2),
            at("media", 0.5, 0.6)
        ]
    })
}

// ===== the model: a board per monitor, and a shared one =====

function defaultModel() {
    const boards = {}
    boards[SHARED] = defaultBoard()
    return { v: VERSION, boards: boards }
}

// Monitor names are short ("DP-1", "HDMI-A-1"); anything odd is dropped.
function screenKeyFits(name) {
    return typeof name === "string" && /^[A-Za-z0-9._:+-]{1,40}$/.test(name)
}

function parse(text) {
    let raw = null
    try {
        raw = JSON.parse(text)
    } catch (e) {
        return defaultModel()
    }
    if (!raw || typeof raw !== "object" || raw.v !== VERSION || !raw.boards || typeof raw.boards !== "object")
        return defaultModel()
    const boards = {}
    let n = 0
    for (const k of Object.keys(raw.boards)) {
        if ((k !== SHARED && !screenKeyFits(k)) || n >= 16)
            continue
        boards[k] = cleanBoard(raw.boards[k])
        n++
    }
    if (!boards[SHARED])
        boards[SHARED] = defaultBoard()
    return { v: VERSION, boards: boards }
}

function stringify(model) {
    const boards = {}
    const src = model && model.boards ? model.boards : {}
    for (const k of Object.keys(src)) {
        if (k === SHARED || screenKeyFits(k))
            boards[k] = cleanBoard(src[k])
    }
    if (!boards[SHARED])
        boards[SHARED] = defaultBoard()
    return JSON.stringify({ v: VERSION, boards: boards })
}

function boardFor(model, screen) {
    const b = model && model.boards ? model.boards : null
    if (b && screenKeyFits(screen) && b[screen])
        return b[screen]
    return b && b[SHARED] ? b[SHARED] : defaultBoard()
}

function withBoard(model, screen, board) {
    const boards = Object.assign({}, model && model.boards ? model.boards : {})
    const key = screen === SHARED || screenKeyFits(screen) ? screen : SHARED
    boards[key] = cleanBoard(board)
    if (!boards[SHARED])
        boards[SHARED] = defaultBoard()
    return { v: VERSION, boards: boards }
}

// True when that monitor has a board of its own (not just the shared one).
function hasBoard(model, screen) {
    const b = model && model.boards ? model.boards : null
    return !!b && screen !== SHARED && screenKeyFits(screen) && Object.prototype.hasOwnProperty.call(b, screen)
}

// A model where that monitor has no board of its own: it wears the shared one again. The
// shared board itself can not be dropped.
function dropBoard(model, screen) {
    const boards = Object.assign({}, model && model.boards ? model.boards : {})
    if (screen !== SHARED)
        delete boards[screen]
    if (!boards[SHARED])
        boards[SHARED] = defaultBoard()
    return { v: VERSION, boards: boards }
}

// What the editor shows about a widget: { kind, title, icon, max, w, h, options: [ { key,
// type, values, def, max } ] }, or null for a name that is not in the catalog. A copy, so
// the editor can not change the catalog.
function describe(kind) {
    if (!known(kind))
        return null
    const c = CATALOG[kind]
    const options = []
    for (const key of Object.keys(c.options)) {
        const o = c.options[key]
        options.push({
            key: key,
            type: o.type,
            values: o.values ? o.values.slice() : [],
            def: o.def,
            max: typeof o.max === "number" ? o.max : 0
        })
    }
    return { kind: kind, title: c.title, icon: c.icon, max: c.max, w: c.w, h: c.h, options: options }
}

// The password block's room: its nominal size and the range its centre may be in
// (fractions of the screen). A copy.
function coreLimits() {
    return Object.assign({}, CORE)
}

// ===== boards inside a desktop preset =====
// A preset wears what it holds (the same rule as the desktop widgets and the bar pills,
// modules/common/functions/PresetParts.js): it holds every board as it was, and the list of widgets
// the shell had when it was saved. A widget that is not in that list did not exist for the
// preset, so it is never drawn from it, whatever is on the board it is handed.

// What a preset holds: { boards: { "*": board, "DP-1": board ... }, kinds: [ "clock" ... ] }.
function presetPart(model) {
    const src = model && model.boards ? model.boards : {}
    const boards = {}
    for (const k of Object.keys(src)) {
        if (k === SHARED || screenKeyFits(k))
            boards[k] = cleanBoard(src[k])
    }
    if (!boards[SHARED])
        boards[SHARED] = defaultBoard()
    return { boards: boards, kinds: kinds().slice().sort() }
}

// The same model with only the widgets in `keep` on its boards (a new model; the password
// block and every number stay as they were).
function keepKinds(model, keep) {
    const src = model && model.boards ? model.boards : {}
    const list = Array.isArray(keep) ? keep : []
    const boards = {}
    for (const k of Object.keys(src)) {
        if (k !== SHARED && !screenKeyFits(k))
            continue
        const b = cleanBoard(src[k])
        b.items = b.items.filter(i => list.indexOf(i.kind) >= 0)
        boards[k] = cleanBoard(b)
    }
    if (!boards[SHARED])
        boards[SHARED] = defaultBoard()
    return { v: VERSION, boards: boards }
}

// The model a preset's part gives, checked like a saved file is; null when the part holds no
// usable layout (there is no shared board), so wearing it changes nothing. When the part
// says which widgets existed (`kinds`), the ones that are not in it are left out.
function wornModel(part) {
    if (!part || typeof part !== "object" || !part.boards || typeof part.boards !== "object" || !part.boards[SHARED])
        return null
    const boards = {}
    let n = 0
    for (const k of Object.keys(part.boards)) {
        if ((k !== SHARED && !screenKeyFits(k)) || n >= 16)
            continue
        boards[k] = cleanBoard(part.boards[k])
        n++
    }
    const model = { v: VERSION, boards: boards }
    return Array.isArray(part.kinds) ? keepKinds(model, part.kinds) : model
}

// ===== edits (each returns a new, clean board) =====

function copyBoard(board) {
    return cleanBoard(JSON.parse(JSON.stringify(cleanBoard(board))))
}

// Adds a widget in the middle of the screen (or at x, y), unless the catalog allows no more
// of that kind or the board is full. Returns { board, uid }; uid is "" when nothing was added.
function addItem(board, kind, x, y) {
    const b = copyBoard(board)
    if (!known(kind) || b.items.length >= MAX_ITEMS)
        return { board: b, uid: "" }
    if (b.items.filter(i => i.kind === kind).length >= CATALOG[kind].max)
        return { board: b, uid: "" }
    const taken = {}
    for (const i of b.items)
        taken[i.uid] = true
    const uid = nextUid(kind, taken)
    b.items.push({ uid: uid, kind: kind, x: num(x, 0, 1, 0.5), y: num(y, 0, 1, 0.5), scale: 1, options: defaultOptions(kind) })
    return { board: cleanBoard(b), uid: uid }
}

function editItem(board, uid, change) {
    const b = copyBoard(board)
    for (const i of b.items) {
        if (i.uid === uid)
            change(i)
    }
    return cleanBoard(b)
}

function moveItem(board, uid, x, y) {
    return editItem(board, uid, i => {
        i.x = x
        i.y = y
    })
}

function scaleItem(board, uid, scale) {
    return editItem(board, uid, i => {
        i.scale = scale
    })
}

function setOption(board, uid, key, value) {
    return editItem(board, uid, i => {
        i.options[key] = value
    })
}

function removeItem(board, uid) {
    const b = copyBoard(board)
    b.items = b.items.filter(i => i.uid !== uid)
    return cleanBoard(b)
}

function setCore(board, x, y) {
    const b = copyBoard(board)
    b.core = { x: x, y: y }
    return cleanBoard(b)
}

// ===== placing =====

// Where the widget's own x (or y) goes. `frac` is where its centre should be (0..1 of
// `total`), `size` its own length before scaling, `scale` the scale it is drawn at (around
// its centre). The result keeps the drawn widget fully on the screen; one wider than the
// screen sits at the start. `total` is the screen's width (or height) in pixels.
function placeAxis(frac, size, scale, total) {
    const drawn = size * scale
    let left = frac * total - drawn / 2
    left = Math.min(left, total - drawn)
    left = Math.max(left, 0)
    return left + drawn / 2 - size / 2
}
