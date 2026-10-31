// The keyboard layout tag on the lockscreen (issue #110): one service says which layout is
// active, the bar's pill and both lock looks read it, and the tag hides when there is
// nothing to switch between. Node cannot load QML, so this reads the real files and cuts
// the real expression for the code out of the service.
// Run:  node tests/lock-layout-test/lock_layout_test.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const top = path.join(__dirname, "..", "..");
const read = rel => fs.readFileSync(path.join(top, rel), "utf8");

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };

const service = read("services/KeyboardLayoutService.qml");
const tag = read("modules/sekai/lock/LockLayoutTag.qml");
const gacha = read("modules/sekai/lock/LockSurface.qml");
const calendar = read("modules/sekai/lock/LockCalendar.qml");
const bar = read("modules/sekai/bar/Bar.qml");

// ---- the code: two letters, upper case, and only with more than one layout ----
const m = /readonly property string code: ([^\n]+\n[^\n]+)/.exec(service);
ok(m, "KeyboardLayoutService.code is declared");
const code = (layoutName, layoutCount) => new Function("root", "return " + m[1])({ layoutName, layoutCount });
ok(code("English (US)", 2) === "EN", "English (US) shows EN");
ok(code("Russian", 3) === "RU", "Russian shows RU");
ok(code("English (US)", 1) === "", "one layout: nothing to show");
ok(code("English (US)", 0) === "", "no layouts read yet: nothing to show");
ok(code("", 2) === "", "no active keymap read yet: nothing to show");

// ---- the service keeps what the bar used to keep for itself ----
ok(/^pragma Singleton/.test(service), "the service is a singleton");
ok(/command: \["hyprctl", "-j", "devices"\]/.test(service), "reads the active keymap from hyprctl devices");
ok(/event\.name === "activelayout"/.test(service), "follows the activelayout event");
ok(/event\.name === "configreloaded"/.test(service), "reads again after a config reload");
ok(/path\.indexOf\("input\.kb_"\) === 0/.test(service), "reads again after the Hyprland page changes kb_layout");
ok(/\["hyprctl", "switchxkblayout", "all", "next"\]/.test(service), "cycles every keyboard together");
ok(/target: LockState[\s\S]{0,120}LockState\.locked[\s\S]{0,40}root\.refresh\(\)/.test(service), "reads again when the screen locks");

ok(/\+\+root\.failures < \d+\)\s*refetch\.restart\(\)/.test(service) && /root\.failures = 0/.test(service), "a failed read is retried a few times, and a good one resets the count");

// ---- the bar reads the service and no longer keeps a copy ----
ok(/keyboardLayoutCode: KeyboardLayoutService\.code/.test(bar), "Bar: the pill shows the service's code");
ok(/onKeyboardLayoutClicked: KeyboardLayoutService\.cycle\(\)/.test(bar), "Bar: a click cycles through the service");
ok(!/xkbLayout|xkbFetch|cycleKeyboardLayout/.test(bar), "Bar: no second copy of the layout state");

// ---- the tag: hidden with no code, drawn from the service ----
ok(/readonly property string code: KeyboardLayoutService\.code/.test(tag), "tag reads the service");
ok(/visible: root\.code !== ""/.test(tag), "tag hides itself when there is no code");
ok(/text: root\.code/.test(tag), "tag says the code");
ok(/import qs\.modules\.common/.test(tag), "tag imports Theme");
ok(/onClicked: \{\s*KeyboardLayoutService\.cycle\(\)\s*root\.activated\(\)/.test(tag), "a click on the tag cycles the layout and says so");
ok(/cursorShape: Qt\.PointingHandCursor/.test(tag), "the tag looks clickable");

// ---- both lock looks carry it, on the password plate, and make room for it ----
for (const [name, src, id] of [["LockSurface", gacha, "layoutTag"], ["LockCalendar", calendar, "calLayoutTag"]]) {
    ok(new RegExp("LockLayoutTag \\{\\s*id: " + id + "\\b").test(src), name + ": has the layout tag");
    ok(new RegExp("id: " + id + "\\b[\\s\\S]{0,500}onActivated: root\\.forceActiveFocus\\(\\)").test(src), name + ": a click on the tag keeps the keyboard on the look");
    ok(new RegExp(id + "\\.visible \\? " + id + "\\.width").test(src), name + ": the label gives the tag room when it shows");
    ok(new RegExp("x: parent\\.width - width - root\\.px\\(\\d+\\)").test(src.slice(src.indexOf("id: " + id))), name + ": the tag sits on the plate's right edge");
}
// the tag is inside the plate that shakes, not beside the controls
ok(gacha.indexOf("id: layoutTag") > gacha.indexOf("id: pwGroup") && gacha.indexOf("id: layoutTag") < gacha.indexOf("id: unlockPill"), "LockSurface: the tag is on the password pill");
ok(calendar.indexOf("id: calLayoutTag") > calendar.indexOf("id: pwGroup"), "LockCalendar: the tag is on the password plate");

console.log("lock layout: " + n + " checks passed");
