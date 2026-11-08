// node tests/lock-info-widgets-test/info_widgets_test.js   (run from the sekaipop folder)
//
// The lockscreen's information widgets: greeting, sun, timer, notifications, next event, to-do
// and countdown. Node cannot load QML, so this runs the model (LockCanvasModel.js) for real and
// reads the QML files for what must hold:
//   - the private ones (notifications, event, to-do) show a COUNT unless `details` is on, and
//     notifications have no details at all
//   - nothing a notification says can reach the lockscreen (only the number is kept)
//   - the widgets only read: no Process, no windows, no keys, no writing back to a service
//   - the countdown's date is a real YYYY-MM-DD or nothing
// The QML itself has not been run by this test (no Quickshell here).
const fs = require("fs"), path = require("path"), assert = require("assert")
const top = path.join(__dirname, "..", "..")
const read = rel => fs.readFileSync(path.join(top, rel), "utf8")
const code = rel => read(rel).replace(/\/\/.*$/gm, "")
let n = 0
const ok = (c, m) => { assert.ok(c, m); n++ }

const src = read("modules/common/functions/LockCanvasModel.js").replace(/^\.pragma library/m, "")
const names = ["CATALOG", "kinds", "known", "isPrivate", "cleanBoard", "addItem", "describe", "defaultBoard"]
const M = new Function(src + ";return {" + names.map(x => x + ":" + x).join(",") + "}")()

const NEW = ["greeting", "sun", "timer", "notifications", "event", "todo", "countdown"]
const cap = k => k.charAt(0).toUpperCase() + k.slice(1)

// ---- the model ----
for (const k of NEW) ok(M.known(k), k + ": is in the catalog")
for (const k of ["notifications", "event", "todo"]) ok(M.isPrivate(k), k + ": is private")
for (const k of ["greeting", "sun", "timer", "countdown"]) ok(!M.isPrivate(k), k + ": is public")
ok(M.CATALOG.event.options.details.def === false && M.CATALOG.todo.options.details.def === false, "event and to-do show only a count until `details` is turned on")
ok(Object.keys(M.CATALOG.notifications.options).length === 0, "notifications have no details to turn on: only the number")
ok(M.CATALOG.greeting.options.name.def === true && M.CATALOG.timer.options.label.def === true, "greeting and timer defaults")
ok(M.defaultBoard().items.every(i => !NEW.includes(i.kind)), "the first layout is as it was (the new widgets are added by you)")

// the countdown's date
const board = date => M.cleanBoard({ items: [{ uid: "countdown-1", kind: "countdown", options: { label: "Concert", date } }] }).items[0].options
ok(board("2026-12-25").date === "2026-12-25", "a YYYY-MM-DD date is kept")
for (const bad of ["12/25/2026", "2026-1-5", "tomorrow", "20261225", "2026-12-2", "<b>2026-12-25</b>"])
    ok(board(bad).date === "", "a date that is not YYYY-MM-DD becomes none: " + bad)
ok(board("2026-12-25 10:00").date === "2026-12-25", "the date box holds 10 characters, so the rest is cut off")
ok(board("2026-12-25").label === "Concert" && board("2026-12-25").label.length <= 40, "the label is kept")
ok(M.cleanBoard({ items: [{ kind: "countdown", options: { label: "x".repeat(200) } }] }).items[0].options.label.length === 40, "the label is cut to 40")
let b = { items: [] }
for (let i = 0; i < 6; i++) b = M.addItem(b, "countdown", 0.5, 0.5).board
ok(b.items.length === 4, "no more than four countdowns")
for (const k of ["notifications", "event", "todo", "timer", "sun", "greeting"]) {
    ok(M.addItem({ items: [] }, k, 0.5, 0.5).board.items.length === 1 && M.addItem(M.addItem({ items: [] }, k, 0.5, 0.5).board, k, 0.5, 0.5).board.items.length === 1, k + ": one at most")
}

// ---- the QML ----
for (const k of NEW) {
    const f = "modules/sekai/lock/Lock" + cap(k) + "Widget.qml"
    const s = code(f)
    ok(/^LockWidget \{/m.test(s), k + ": is a LockWidget")
    ok(!/\bProcess\b|execDetached|openUrlExternally|PanelWindow|PopupWindow|TextInput|TextField|Keys\.|\bfocus:/.test(s), k + ": only draws")
    // a widget never writes to a service it reads
    ok(!/(TodoService|CalendarCardService|TimerService|NotificationCount|WaterTankService)\.\w+\s*=[^=]/.test(s) && !/(TodoService|CalendarCardService|TimerService)\.(add|edit|toggle|remove|clearDone|update|setDone|start|toggleTimer|resetTimer|toggleStopwatch)\(/.test(s), k + ": reads, never changes, a service")
}

const todo = code("modules/sekai/lock/LockTodoWidget.qml")
ok(/root\.details && root\.nextTitle !== "" \? root\.nextTitle : root\.countText/.test(todo), "to-do: the words of a task appear only with `details` on, otherwise the count")
ok(/subtitle: !root\.allDone && root\.details/.test(todo), "to-do: the second line (the count) only goes with the words")
ok(/opt\("details", false\) === true/.test(todo), "to-do: `details` is off unless set")

const ev = code("modules/sekai/lock/LockEventWidget.qml")
ok(/if \(root\.details\)\s*\n\s*return String\(root\.next\.title\)/.test(ev), "event: a title is only used under `details`")
ok(/return "Next: " \+ EM\.countdown\(root\.next, root\.diff\)/.test(ev), "event: the masked line is a count or a distance, not a title")
ok(/subtitle: \{\s*\n\s*if \(!root\.details\)\s*\n\s*return ""/.test(ev), "event: no second line (time, note) unless `details`")
ok(!/\.note\b/.test(ev), "event: a note is never shown")
ok(/opt\("details", false\) === true/.test(ev), "event: `details` is off unless set")

const nw = code("modules/sekai/lock/LockNotificationsWidget.qml")
ok(!/NotificationSource|entries|\.body|\.summary|\.appName|\.title/.test(nw), "notifications: nothing a notification says is read")
ok(/NotificationCount\.count/.test(nw), "notifications: only the count")
const nc = code("services/NotificationCount.qml")
ok(/^pragma Singleton/.test(nc) && (nc.match(/property /g) || []).length === 1 && /property int count: 0/.test(nc), "the singleton holds one number and nothing else")
const shell = code("shell.qml")
ok(/Binding \{\s*target: NotificationCount\s*property: "count"\s*value: notificationState\.count\s*\}/.test(shell), "shell.qml keeps the count up to date from the daemon")

const cd = code("modules/sekai/lock/LockCountdownWidget.qml")
ok(/EM\.parseDate\(root\.rawDate\) !== null/.test(cd), "countdown: only a real day counts")
const ge = code("modules/sekai/lock/LockGreetingWidget.qml")
ok(/h >= 5 && h < 12/.test(ge) && /Good night/.test(ge), "greeting: by the hour")
const su = code("modules/sekai/lock/LockSunWidget.qml")
ok(/WeatherSource \{/.test(su) && /sunriseText/.test(su) && /sunsetText/.test(su), "sun: reads the weather source's sunrise and sunset")
const tm = code("modules/sekai/lock/LockTimerWidget.qml")
ok(/TimerService\.hasTime/.test(tm) && /TimerService\.shownClock/.test(tm), "timer: shows the running clock and nothing when none runs")

// ---- the shared capsule is a look, not a widget ----
const info = code("modules/sekai/lock/LockInfoCapsule.qml")
ok(/^LockCapsule \{/m.test(info) && !/LockWidget/.test(info), "the info capsule is a capsule, not a widget")
ok(!/\bProcess\b|MouseArea|Keys\./.test(info), "the info capsule has no input")

// ---- docs and labels ----
const E = new Function(read("modules/common/functions/LockEditMath.js").replace(/^\.pragma library/m, "") + ";return {LABELS:LABELS}")().LABELS
for (const k of NEW) for (const o of Object.keys(M.CATALOG[k].options)) ok(typeof E[o] === "string", k + "." + o + ": has an editor label")
const doc = read("../docs/LOCKCANVAS.md")
for (const k of NEW) ok(new RegExp("\\| `" + k + "` \\|").test(doc), k + ": is in docs/LOCKCANVAS.md")

console.log("lock info widgets: " + n + " checks passed")
