// The Custom lockscreen's wiring (LockCanvas.qml and friends). Node cannot load QML, so this
// reads the real files and checks the things that keep the screen safe and the pieces
// joined up. Run:  node tests/lock-canvas-test/canvas_wiring_test.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const top = path.join(__dirname, "..", "..");
const read = rel => fs.readFileSync(path.join(top, rel), "utf8");
let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };

const modelSrc = read("modules/common/functions/LockCanvasModel.js");
const kinds = [...modelSrc.matchAll(/^    (\w+): \{\n        title:/gm)].map(m => m[1]);
ok(kinds.length === 16, "the catalog lists sixteen widgets: " + kinds.join());

const canvas = read("modules/sekai/lock/LockCanvas.qml");
const cap = k => k.charAt(0).toUpperCase() + k.slice(1);

// ---- every catalog widget has a file, a Component, and an entry in the canvas's map ----
for (const k of kinds) {
    const file = "modules/sekai/lock/Lock" + cap(k) + "Widget.qml";
    ok(fs.existsSync(path.join(top, file)), k + ": " + file + " exists");
    ok(/^LockWidget \{/m.test(read(file)), k + ": is a LockWidget");
    ok(new RegExp("Component \\{ id: " + k + "Widget;\\s+Lock" + cap(k) + "Widget \\{\\} \\}").test(canvas), k + ": has a Component in the canvas");
    ok(new RegExp("\\b" + k + ": " + k + "Widget\\b").test(canvas), k + ": is in the canvas's kinds map");
}
const mapped = [...canvas.matchAll(/^\s+(\w+): (\w+)Widget,?$/gm)].map(m => m[1]);
ok(mapped.sort().join() === kinds.slice().sort().join(), "the canvas maps exactly the catalog's widgets");

// ---- the password block is always there, on top, and the canvas owns the keyboard ----
ok(/LockCore \{[^}]*z: 100/.test(canvas), "the password block is built unconditionally, above the widgets");
ok(!/(Loader|Repeater)[^\n]*LockCore/.test(canvas), "the password block is not behind a Loader or Repeater");
ok(/z: 1\b/.test(canvas), "widgets sit below it");
ok(/Keys\.onPressed:/.test(canvas) && /root\.context\.tryUnlock\(\)/.test(canvas) && /root\.context\.typeText\(t\)/.test(canvas), "the canvas catches the keys for the password");
ok(/Component\.onCompleted:\s*\{\s*root\.forceActiveFocus\(\)/.test(canvas), "the canvas takes the focus");
const gachaKeys = /Keys\.onPressed: event => \{[\s\S]*?\n    \}\n/.exec(read("modules/sekai/lock/LockSurface.qml"))[0];
const canvasKeys = /Keys\.onPressed: event => \{[\s\S]*?\n    \}\n/.exec(canvas)[0];
ok(gachaKeys === canvasKeys, "the key handling is the Gacha look's, word for word");

// ---- no widget can take keys, run a program, or load code ----
const widgetFiles = fs.readdirSync(path.join(top, "modules/sekai/lock")).filter(f => /^Lock(\w+Widget|Widget)\.qml$/.test(f));
ok(widgetFiles.length === 17, "the base and sixteen widgets: " + widgetFiles.join());
for (const f of widgetFiles) {
    const s = read("modules/sekai/lock/" + f).replace(/\/\/.*$/gm, "");
    ok(!/TextInput|TextField|TextEdit|Keys\.|forceActiveFocus|activeFocusOnPress|\bfocus:/.test(s), f + ": takes no keyboard");
    ok(!/\bProcess\b|Quickshell\.execDetached|Qt\.openUrlExternally|createQmlObject|Qt\.createComponent|Qt\.include|eval\(|\bsource: *root\.opt|\bPopup\b|PopupWindow|PanelWindow/.test(s), f + ": runs nothing, loads no code, opens no window");
}
ok(!/Qt\.createQmlObject|Qt\.createComponent|Qt\.include|eval\(|source: *slot|setSource/.test(canvas.replace(/\/\/.*$/gm, "")), "the canvas never loads code named by the layout");
ok(/sourceComponent: root\.kinds\[slot\.spec\.kind\]/.test(canvas), "a widget is only ever picked from the canvas's own map");

// ---- the media keys only call the player's MPRIS controls; no cover picture is fetched ----
const media = read("modules/sekai/lock/LockMediaWidget.qml").replace(/\/\/.*$/gm, "");
ok(/root\.media\.previous\(\)/.test(media) && /root\.media\.togglePlaying\(\)/.test(media) && /root\.media\.next\(\)/.test(media), "media keys call MediaSource");
ok(!/artUrl/.test(media), "no cover picture (it would fetch from the network)");
ok(!/LockLyrics|lyrics/i.test(media), "the line being sung is not part of the Now playing widget any more");

// ---- the Lyrics widget is its own widget: it only reads the player, and says so in the editor ----
const lyricsW = read("modules/sekai/lock/LockLyricsWidget.qml").replace(/\/\/.*$/gm, "");
ok(/LockLyrics \{/.test(lyricsW) && /always: true/.test(lyricsW) && /preview: root\.preview/.test(lyricsW), "the Lyrics widget is the shared capsule, on because it was placed, with a sample in the editor");
const lyr = read("modules/sekai/lock/LockLyrics.qml");
ok(/readonly property bool enabled: root\.always \|\| SettingsService\.flag\("lock\.lyrics"\)/.test(lyr), "the Gacha look still waits for the setting; only the widget skips it");
ok(/property bool always: false/.test(lyr), "...and `always` is off unless the widget asks");

// ---- the small capsules are one family: the same height (the User widget's) ----
const baseW = read("modules/sekai/lock/LockWidget.qml");
ok(/readonly property real capH: root\.px\(116\)/.test(baseW), "the base gives the small capsules one height");
for (const f of ["User", "Date", "Weather", "Battery", "Media"])
    ok(/height: root\.capH/.test(read("modules/sekai/lock/Lock" + f + "Widget.qml")), f + ": its capsule is the shared height");
for (const k of ["user", "date", "weather", "battery", "media"])
    ok(new RegExp(k + ": \\{\\n        title: \"[^\"]+\", icon: \"[^\"]+\", privacy: \"public\", w: \\d+, h: 116,").test(modelSrc), k + ": the catalog's nominal height is the shared one");
ok(!/https?:/.test(read("modules/sekai/lock/LockImageWidget.qml").replace(/\/\/.*$/gm, "")), "the image widget reads files only");
ok(/"file:\/\/" \+ root\.path/.test(read("modules/sekai/lock/LockImageWidget.qml")), "a picture is a file:// URL");

// ---- the service: data only, loaded at start, never before it has loaded ----
const svc = read("services/LockCanvasService.qml");
ok(/^pragma Singleton/.test(svc), "the service is a singleton");
ok(/LM\.parse\(text\)/.test(svc) && /LM\.stringify\(root\.model\)/.test(svc), "everything read or written goes through the model");
ok(/function persist\(\) \{\s*if \(root\.loaded\)/.test(svc), "nothing is saved before the file was read");
ok(/lockcanvas-state\.sh/.test(svc) && fs.existsSync(path.join(top, "scripts/state/lockcanvas-state.sh")), "it has its state script");
ok(/target: "lockcanvas"/.test(svc) && /function reset\(\): void/.test(svc), "ipc: lockcanvas reset");
ok(!/createQmlObject|Qt\.createComponent|eval\(/.test(svc), "the service never turns data into code");

// ---- LockHost: Custom is a third look; the other two are as they were ----
const host = read("modules/sekai/lock/LockHost.qml");
ok(/sourceComponent: root\.custom \? customLook : \(root\.calendar \? calendarLook : gachaLook\)/.test(host), "LockHost picks Custom, Calendar or Gacha");
ok(/SettingsService\.get\("lock\.style"\) === "custom"/.test(host), "LockHost reads lock.style for Custom");
ok(/id: customLook[\s\S]*?LockCanvas \{[\s\S]*?context: root\.context[\s\S]*?uiScale: root\.uiScale[\s\S]*?screenName: root\.screenName/.test(host), "the Custom look gets the same three things");
ok(/root\.custom \? LockCanvasService\.loaded : true/.test(host), "the host warms the layout when Custom is the style");
ok(/\{ id: "custom"/.test(read("modules/sekai/settings/SettingsPageGeneral.qml")), "Settings offers Custom");
ok(/l\.style === "custom"/.test(read("services/DesktopPresetService.qml")), "a preset can wear Custom");

// ---- the canvas draws what LockRing needs ----
ok(/readonly property bool wallpaperReady: wallpaper\.status !== Image\.Loading/.test(canvas), "LockRing can wait for the wallpaper");
for (const p of ["context", "uiScale", "screenName"])
    ok(new RegExp("(required )?property \\w+ " + p + "\\b").test(canvas), "the canvas has " + p);

console.log("lock canvas wiring: " + n + " checks passed");
