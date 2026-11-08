// The lockscreen editor's wiring (modules/sekai/lockEditor, services/LockEditService.qml).
// Node cannot load QML, so this reads the real files and checks the things that keep the
// lockscreen safe and the pieces joined up. Run:
//   node tests/lock-edit-test/lock_edit_wiring_test.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const top = path.join(__dirname, "..", "..");
const read = rel => fs.readFileSync(path.join(top, rel), "utf8");
const code = rel => read(rel).replace(/\/\/.*$/gm, "");
let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };

const modelSrc = read("modules/common/functions/LockCanvasModel.js");
const kinds = [...modelSrc.matchAll(/^    (\w+): \{\n        title:/gm)].map(m => m[1]);
const cap = k => k.charAt(0).toUpperCase() + k.slice(1);

// ---- the files are there ----
const dir = "modules/sekai/lockEditor";
const files = ["LockEditor", "LockEditStage", "LockEditSlot", "LockEditCore", "LockEditShelf", "LockEditOptions", "LockEditFrame", "LockEditBackdrop"];
for (const f of files)
    ok(fs.existsSync(path.join(top, dir, f + ".qml")), f + ".qml exists");
const edFiles = files.map(f => dir + "/" + f + ".qml").concat(["services/LockEditService.qml"]);

// ---- the editor is NOT on the lock surface, and the lock does not know about it ----
// (docs/LOCKCANVAS.md rules 3 and 4: the lock only draws; editing happens in your own session)
const lockDir = fs.readdirSync(path.join(top, "modules/sekai/lock"));
ok(!lockDir.some(f => /Edit/.test(f)), "no editor file lives in the lock's folder");
for (const f of lockDir.filter(f => f.endsWith(".qml")))
    ok(!/LockEdit|lockEditor/.test(read("modules/sekai/lock/" + f)), f + ": the lock never mentions the editor");
ok(!/LockEdit/.test(read("services/LockCanvasService.qml").replace(/\/\/.*$/gm, "")), "the canvas service does not depend on the editor");

// ---- the editor never touches the password, never runs saved data as code ----
for (const f of edFiles) {
    const s = code(f);
    ok(!/LockContext|tryUnlock|typeText|selectAll|\.context\b|LockCore\b/.test(s.replace(/LockEditCore/g, "")), f + ": nothing to do with the password");
    ok(!/createQmlObject|Qt\.createComponent|Qt\.include|eval\(|setSource/.test(s), f + ": loads no code");
    ok(!/Quickshell\.execDetached|\bProcess\b/.test(s) || f === "services/LockEditService.qml", f + ": starts no program (only the service's file chooser)");
}

// ---- the service sends every change through the model, and saves through the canvas service ----
const svc = code("services/LockEditService.qml");
ok(/^pragma Singleton/.test(svc), "the service is a singleton");
ok(/LockCanvasService\.setBoard\(root\.ownBoard \? root\.screenName : "\*", root\.board\)/.test(svc), "it saves to this monitor's board, or the shared one");
ok(/function apply\(next\) \{\s*const clean = LM\.cleanBoard\(next\)/.test(svc), "a whole edit is cleaned by the model first");
ok(/LockState\.locked \|\| !LockCanvasService\.loaded/.test(svc), "it does not open while locked or before the layout was read");
ok(/onLockedChanged\(\) \{\s*if \(LockState\.locked\)\s*root\.close\(\)/.test(svc), "it closes when the session locks");
ok(/target: "lockedit"/.test(svc) && /function open\(\): void/.test(svc) && /function close\(\): void/.test(svc) && /function toggle\(\): void/.test(svc), "ipc: lockedit open / close / toggle");
ok(/if \(uid === "core" \|\| root\.item\(uid\) === null\)\s*return/.test(svc), "the password block can not be removed");
ok(/function finish\(\)/.test(svc) && /function begin\(\)/.test(svc) && /function live\(next\)/.test(svc), "a drag is begin / live / finish (one undo step)");
ok(/path !== "" && root\.active/.test(svc) && /setOption\(root\.pickUid, "path", path\)/.test(svc), "a chosen picture goes through setOption (the model checks the path)");

// ---- the window ----
const win = code(dir + "/LockEditor.qml");
ok(/WlrLayershell\.layer: WlrLayer\.Overlay/.test(win) && /WlrKeyboardFocus\.Exclusive/.test(win), "an Overlay window that takes the keyboard");
ok(/active: win\.visible/.test(win), "built only while shown");
ok(/!LockEditService\.picking/.test(win), "it steps aside for the file chooser");
ok(/visible: win\.shown/.test(win) || /visible: win\.shown && !LockEditService\.picking/.test(win), "mapped only while open or closing");

// ---- the stage draws the lock's own widgets, with the same map as the lock ----
const stage = read(dir + "/LockEditStage.qml");
const canvas = read("modules/sekai/lock/LockCanvas.qml");
const stageMap = [...stage.matchAll(/^\s+(\w+): (\w+)Widget,?$/gm)].map(m => m[1]);
const canvasMap = [...canvas.matchAll(/^\s+(\w+): (\w+)Widget,?$/gm)].map(m => m[1]);
ok(stageMap.slice().sort().join() === kinds.slice().sort().join(), "the stage maps exactly the catalog's widgets");
ok(stageMap.join() === canvasMap.join(), "and the lock's map is the same");
for (const k of kinds)
    ok(new RegExp("Component \\{ id: " + k + "Widget;\\s+Lock" + cap(k) + "Widget \\{\\} \\}").test(stage), k + ": the stage has a Component for it");
ok(/sourceComponent: slot\.stage\.kinds\[slot\.kind\]/.test(read(dir + "/LockEditSlot.qml")), "a widget is only picked from the stage's own map");
ok(/ld\.item\.preview = true/.test(read(dir + "/LockEditSlot.qml")), "widgets are drawn in preview mode");
ok(/ld\.item\.media = |ld\.item\.context = /.test(read(dir + "/LockEditSlot.qml")) === false, "the editor gives widgets no player and no password context");
ok(/EM\.placeAxis\(/.test(read(dir + "/LockEditSlot.qml")) && /EM\.placeAxis\(/.test(read(dir + "/LockEditCore.qml")), "widgets and the block are placed by the canvas's rule");
ok(/z: 10[\s\S]*?preventStealing/.test(read(dir + "/LockEditSlot.qml")), "a MouseArea sits over each widget so its own keys do nothing while editing");
ok(/LM\.setCore\(LockEditService\.board, fx, fy\)/.test(read(dir + "/LockEditCore.qml")), "the block moves through setCore (kept in its range)");
ok(!/remove\(|scaleItem|Wheel|onWheel/.test(code(dir + "/LockEditCore.qml")), "the block can not be removed or resized");
ok(/Esc/.test(stage) && /Qt\.Key_Z/.test(stage) && /Qt\.Key_Delete/.test(stage), "the keys are there");
ok(/if \(shelf\.typing\)/.test(stage), "typing in the words box is left alone");

// ---- opening and closing: the card shrinks in from the whole screen, like Edit Desktop ----
const stageCode = code(dir + "/LockEditStage.qml");
ok(/readonly property real ps: Math\.max\(0, LockEditService\.progress\)/.test(stageCode), "the card follows the unclamped progress (the pop overshoots)");
ok(/readonly property real kNow: 1 \+ \(root\.k - 1\) \* root\.ps/.test(stageCode), "it starts at the screen's own size and ends at the card's");
ok(/scale: root\.kNow/.test(stageCode) && /width: root\.liveW/.test(stageCode) && /x: root\.liveX/.test(stageCode), "the picture and its window are the live size and place");
ok(!/scale: 0\.86/.test(stageCode), "the old small-pop is gone");
const svcSrc = code("services/LockEditService.qml");
ok(/duration: root\.active \? 560 : 360/.test(svcSrc) && /Easing\.OutBack : Easing\.InOutCubic/.test(svcSrc) && /easing\.overshoot: 1\.25/.test(svcSrc), "the same times and curves as Edit Desktop");
const em = code("services/EditMode.qml");
ok(/duration: 560/.test(em) && /easing\.overshoot: 1\.25/.test(em) && /duration: 360/.test(em) && /Easing\.InOutCubic/.test(em), "(and those are Edit Desktop's)");

// ---- the corners: the shadow is under the card, the rings over it ----
const shadowAt = stageCode.indexOf("drawRings: false");
const cardAt = stageCode.indexOf("clip: true");
const ringsAt = stageCode.indexOf("drawShadow: false");
ok(shadowAt > 0 && cardAt > shadowAt && ringsAt > cardAt, "shadow, then the card, then the rings on top of it");
const frameSrc = code(dir + "/LockEditFrame.qml");
ok(/property bool drawShadow: true/.test(frameSrc) && /property bool drawRings: true/.test(frameSrc), "the frame can draw either part alone");
ok((frameSrc.match(/visible: root\.drawRings/g) || []).length === 3 && (frameSrc.match(/visible: root\.drawShadow/g) || []).length === 1, "three rings, one shadow, each behind its switch");
ok(/Math\.min\(1, Math\.max\(0, root\.grow\)\)/.test(frameSrc), "the frame grows with the card");

// ---- the shelf lists the catalog, whatever it holds ----
ok(/model: LockEditService\.catalog/.test(read(dir + "/LockEditShelf.qml")), "the shelf has one key per catalog widget");
ok(/model: root\.info \? root\.info\.options : \[\]/.test(read(dir + "/LockEditOptions.qml")), "the options come from the catalog");

// ---- the ways in ----
ok(/import qs\.modules\.sekai\.lockEditor/.test(read("shell.qml")) && /^\s*LockEditor \{\}/m.test(read("shell.qml")), "shell.qml loads the editor");
ok(/label: "Edit lockscreen"/.test(read("modules/sekai/settings/SettingsPageGeneral.qml")) && /LockEditService\.open\(""\)/.test(read("modules/sekai/settings/SettingsPageGeneral.qml")), "Settings has the key");
ok(/lock\.style"\) === "custom"\s*\n\s*icon: "dashboard_customize"/.test(read("modules/sekai/settings/SettingsPageGeneral.qml")), "...only while Custom is the style");
ok(/text: "Edit lockscreen"/.test(read("modules/sekai/desktopMenu/DesktopMenu.qml")), "the desktop menu has the row");
ok(/LockEditService\.close\(\)/.test(read("services/EditMode.qml")), "Edit Desktop closes the editor (one at a time)");
ok(/EditMode\.close\(\)/.test(svc), "and the editor closes Edit Desktop");

// ---- the picture chooser ----
const sh = read("scripts/images/pick-lock-picture.sh");
ok(/for e in png jpg jpeg webp gif bmp; do/.test(sh) && !/svg/.test(sh), "it offers only the kinds the model lets through");
ok(!/\bcp\b|\bmv\b|shrink-image/.test(sh), "it does not copy the picture");
ok((fs.statSync(path.join(top, "scripts/images/pick-lock-picture.sh")).mode & 0o111) !== 0, "it is executable like its sibling");
ok(/images\/pick-lock-picture\.sh/.test(svc), "the service runs it");

console.log("lock edit wiring: " + n + " checks passed");
