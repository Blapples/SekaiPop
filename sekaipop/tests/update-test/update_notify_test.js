// Node test for the update notification (nothing here needs Quickshell).
// It cuts the real `announce()` out of services/UpdateService.qml and runs it against a
// stand-in `root`, and reads the source for the wiring (timers gated by the setting,
// settings keys, the page and the tab badge).
//   node tests/update-test/update_notify_test.js
"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path");
const top = path.join(__dirname, "..", "..");
const read = rel => fs.readFileSync(path.join(top, rel), "utf8");
let n = 0;
const ok = (name, fn) => { fn(); n++; console.log("  ok   " + name); };

const svc = read("services/UpdateService.qml");

// ---- pull a function body out of the QML by brace matching
function body(src, name) {
    const i = src.indexOf("function " + name + "(");
    assert(i >= 0, "no function " + name);
    const open = src.indexOf("{", src.indexOf(")", i));
    let depth = 0, j = open;
    for (; j < src.length; j++) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}" && --depth === 0) break;
    }
    return src.slice(open + 1, j);
}
const announceFn = new Function("root", "GameModeService", "seenWriter", "Quickshell", body(svc, "announce"));

function world(over) {
    const w = {
        sent: [], wrote: [],
        root: Object.assign({ status: "behind", unknown: false, rev: "abc1234", seen: "", byUser: false, watching: true,
            isGit: false, managed: true, behind: 0, latest: "abc1234", script: "S" }, over || {}),
        game: { enabled: false }
    };
    w.writer = { exec: a => w.wrote.push(a) };
    w.qs = { execDetached: a => w.sent.push(a) };
    w.run = () => announceFn(w.root, w.game, w.writer, w.qs);
    return w;
}

ok("a background look that finds a newer version sends one notification and remembers it", () => {
    const w = world(); w.run();
    assert.strictEqual(w.sent.length, 1);
    assert.strictEqual(w.sent[0][0], "notify-send");
    assert(/Update available/i.test(w.sent[0].join(" ")));
    assert.deepStrictEqual(w.wrote, [["sh", "S", "seen", "abc1234"]]);
    assert.strictEqual(w.root.seen, "abc1234");
    w.run();                                         // the next look finds the same one
    assert.strictEqual(w.sent.length, 1, "no repeat for the same version");
});
ok("a newer version after that sends another", () => {
    const w = world(); w.run(); w.root.rev = "def5678"; w.run();
    assert.strictEqual(w.sent.length, 2);
});
ok("already seen at start (read from the cache file): nothing", () => {
    const w = world({ seen: "abc1234" }); w.run();
    assert.strictEqual(w.sent.length, 0); assert.strictEqual(w.wrote.length, 0);
});
ok("a look the user asked for counts as seen and sends nothing", () => {
    const w = world({ byUser: true }); w.run();
    assert.strictEqual(w.sent.length, 0);
    assert.strictEqual(w.root.seen, "abc1234");
    assert.strictEqual(w.wrote.length, 1);
});
ok("an installed copy with no version mark (unknown) is never announced", () => {
    const w = world({ unknown: true }); w.run();
    assert.strictEqual(w.sent.length, 0); assert.strictEqual(w.wrote.length, 0);
});
ok("up to date, error or no id: nothing", () => {
    for (const o of [{ status: "current" }, { status: "error" }, { status: "nosource" }, { rev: "" }]) {
        const w = world(o); w.run();
        assert.strictEqual(w.sent.length + w.wrote.length, 0, JSON.stringify(o));
    }
});
ok("Game Mode: waits (not marked seen), then announces on a later look", () => {
    const w = world(); w.game.enabled = true; w.run();
    assert.strictEqual(w.sent.length, 0); assert.strictEqual(w.root.seen, "");
    w.game.enabled = false; w.run();
    assert.strictEqual(w.sent.length, 1);
});
ok("setting off: a look marks it seen but never notifies", () => {
    const w = world({ watching: false }); w.run();
    assert.strictEqual(w.sent.length, 0); assert.strictEqual(w.root.seen, "abc1234");
});
ok("the text says what is waiting, per mode", () => {
    const git = world({ isGit: true, managed: false, behind: 3 }); git.run();
    assert(/3 new commits are waiting/.test(git.sent[0][6]));
    const one = world({ isGit: true, managed: false, behind: 1 }); one.run();
    assert(/1 new commit is waiting/.test(one.sent[0][6]));
    const url = world({ isGit: false, managed: false, latest: "3.9.0", rev: "3.9.0" }); url.run();
    assert(/Version 3\.9\.0 is out/.test(url.sent[0][6]));
    const gh = world(); gh.run();
    assert(/newer version is on GitHub/.test(gh.sent[0][6]));
    assert(/About \/ Update/.test(gh.sent[0][6]));
});

// ---- wiring
ok("both timers run only while the setting is on", () => {
    const timers = svc.match(/Timer \{[^}]*\}/g) || [];
    assert.strictEqual(timers.length, 2);
    for (const t of timers) assert(/running: root\.watching/.test(t), t);
    assert(/watching: SettingsService\.flag\("updates\.shellNotify"\)/.test(svc));
    assert(/SettingsService\.get\("updates\.shellHours"\)/.test(svc));
});
ok("the rev comes from the script and announce() runs after every look", () => {
    assert(/root\.rev = kv\.rev/.test(svc));
    assert(/root\.announce\(\)/.test(svc));
});
ok("timed looks keep the shown answer; user looks say checking", () => {
    const f = body(svc, "check");
    assert(/byUser === true \|\| root\.status === "idle"/.test(f));
});
ok("settings keys exist with the right types, and presets leave the 'updates.' prefix alone", () => {
    const s = read("services/SettingsService.qml");
    assert(/"updates\.shellNotify": true/.test(s));
    assert(/"updates\.shellHours": 6/.test(s));
    const p = read("services/DesktopPresetService.qml");
    assert(/keepPrefix: \[[^\]]*"updates\."/.test(p));
});
ok("the page asks as the user, and has the switch and the slider", () => {
    const a = read("modules/sekai/settings/SettingsPageAbout.qml");
    assert.strictEqual((a.match(/UpdateService\.check\(true\)/g) || []).length, 2);
    assert(!/UpdateService\.check\(\)/.test(a));
    assert(/SettingsService\.toggle\("updates\.shellNotify"\)/.test(a));
    assert(/SettingsService\.set\("updates\.shellHours"/.test(a));
});
ok("the About tab's badge is not lit for 'can't tell'", () => {
    const f = read("modules/sekai/settings/SettingsFace.qml");
    assert(/UpdateService\.status === "behind" && !UpdateService\.unknown/.test(f));
});

ok("system update: the service reads `system`, asks again when install.sh's terminal closes, and runs sysrun in a terminal", () => {
    assert(/command: \["sh", root\.script, "system"\]/.test(svc));
    assert(/root\.systemNeeded = kv\.system === "needed"/.test(svc));
    assert(/kv\.note \? kv\.note\.split\("\|"\)/.test(svc));
    assert(/X\.terminalArgv\("sh " \+ quoted \+ " sysrun"\)/.test(svc));
    const exit = svc.slice(svc.indexOf("id: sysRunner"));
    assert(/root\.systemRunning = false/.test(exit) && /sysChecker\.running = true/.test(exit));
    assert(/Extras\.js" as X/.test(svc));
});
ok("system update: the key shows only when needed and applicable; the About tab's badge also lights for it", () => {
    const a = read("modules/sekai/settings/SettingsPageAbout.qml");
    assert(/visible: UpdateService\.systemNeeded && UpdateService\.canApply[\s\S]{0,80}label: "Update system"/.test(a));
    assert(/onActivated: UpdateService\.updateSystem\(\)/.test(a));
    assert(/UpdateService\.systemNote\.map/.test(a));
    const f = read("modules/sekai/settings/SettingsFace.qml");
    assert(/\|\| UpdateService\.systemNeeded/.test(f));
});
ok("system update: install.sh records the number after a clean, real run, and SYSTEM-REV starts with a number", () => {
    const inst = fs.readFileSync(path.join(top, "..", "install.sh"), "utf8");
    assert(/\[ "\$DRY" = 0 \] && \[ "\$\{#FAILED\[@\]\}" -eq 0 \] && \[ -f "\$QS_DEST\/SYSTEM-REV" \]/.test(inst));
    assert(/\$CFG\/sekaipop\/system-rev/.test(inst));
    const rev = read("SYSTEM-REV").split("\n");
    assert(/^[0-9]+$/.test(rev[0]) && rev.slice(1).some(l => l.trim() !== ""));
    assert(!rev.slice(1).some(l => l.includes("|") || l.includes("=")));
});

console.log("all " + n + " passed");
