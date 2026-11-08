// Unit test for modules/common/functions/LockEditMath.js (the maths of the lockscreen
// editor) and for the helpers LockCanvasModel.js gives it. Pure logic, no QML. Run:
//   node tests/lock-edit-test/lock_edit_unit.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const dir = path.join(__dirname, "..", "..", "modules", "common", "functions");
const load = (file, names) => {
    const src = fs.readFileSync(path.join(dir, file), "utf8").replace(/^\.pragma library/m, "");
    return new Function(src + ";return {" + names.map(n => n + ":" + n).join(",") + "}")();
};
const E = load("LockEditMath.js", ["SNAP_PX", "SCALE_SNAP", "SCALE_LO", "SCALE_HI", "HISTORY_CAP", "clamp", "cardFit", "placeAxis", "keepOn",
    "linesOf", "snapAxis", "scaleFromDrag", "stepScale", "percent", "emptyHistory", "record", "undo", "redo", "same",
    "cycle", "optionLabel", "valueLabel", "LABELS"]);
const M = load("LockCanvasModel.js", ["CATALOG", "CORE", "SHARED", "kinds", "defaultBoard", "defaultModel", "withBoard",
    "boardFor", "hasBoard", "dropBoard", "describe", "coreLimits", "addItem", "moveItem", "scaleItem", "setOption",
    "removeItem", "setCore", "placeAxis", "cleanBoard", "SCALE_MIN", "SCALE_MAX"]);

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };
const eq = (a, b, msg) => { assert.deepStrictEqual(a, b, msg); n++; };
const near = (a, b, msg) => { assert.ok(Math.abs(a - b) < 1e-9, msg + " (" + a + " vs " + b + ")"); n++; };

// ---- the card: the screen's shape, as big as the room allows, centred ----
{
    const c = E.cardFit(1000, 500, 1920, 1080);
    near(c.w / c.h, 1920 / 1080, "the card keeps the screen's shape");
    ok(c.w <= 1000 + 1e-9 && c.h <= 500 + 1e-9, "it fits the room");
    ok(Math.abs(c.w - 1000) < 1e-9 || Math.abs(c.h - 500) < 1e-9, "and touches it on one axis");
    near(c.x, (1000 - c.w) / 2, "centred across");
    near(c.y, (500 - c.h) / 2, "centred down");
    const tall = E.cardFit(500, 1000, 1920, 1080);
    near(tall.w, 500, "a tall room is filled across");
    const bad = E.cardFit(0, 0, 1920, 1080);
    ok(bad.k === 1 && bad.w === 1920, "no room: a plain answer, no NaN");
    ok(isFinite(E.cardFit(NaN, 5, 1, 1).k), "garbage in, finite out");
}

// ---- placing: the editor puts a widget where the canvas does ----
for (const total of [1080, 1920, 2560]) {
    for (const size of [60, 300, 900, 3000]) {
        for (const scale of [0.5, 1, 2.5]) {
            for (let f = -0.2; f <= 1.2; f += 0.1) {
                near(E.placeAxis(f, size, scale, total), M.placeAxis(f, size, scale, total), "placeAxis agrees with the canvas's");
            }
        }
    }
}
{
    // keepOn gives a fraction the canvas draws in the same place
    for (const f of [0, 0.02, 0.5, 0.98, 1]) {
        const k = E.keepOn(f, 400, 1.5, 1920);
        near(M.placeAxis(k, 400, 1.5, 1920), M.placeAxis(f, 400, 1.5, 1920), "keepOn does not move what is already shown");
        ok(k >= 0 && k <= 1, "keepOn stays a fraction");
        const left = E.placeAxis(k, 400, 1.5, 1920) + 200 - 300;
        ok(left >= -1e-9 && left + 600 <= 1920 + 1e-9, "the drawn widget is on the screen");
    }
    ok(E.keepOn(0.5, 400, 1, 0) === 0.5, "no room: the middle");
}

// ---- snapping ----
{
    const lines = E.linesOf([{ c: 300, d: 200 }], 1000);
    eq(lines, [500, 300, 200, 400], "the screen's middle, then another widget's middle and edges");
    let s = E.snapAxis(505, 100, lines, 10);
    ok(s.delta === -5 && s.line === 500, "the middle snaps to the screen's middle");
    s = E.snapAxis(620, 100, lines, 10);
    ok(s.line === null && s.delta === 0, "nothing near: no snap");
    s = E.snapAxis(450, 100, lines, 10);
    ok(s.delta === 0 && (s.line === 400 || s.line === 500), "an edge already on a guide needs no move");
    s = E.snapAxis(408, 100, [400], 10);
    ok(s.delta === -8 && s.line === 400, "the middle, 8 away, snaps");
    s = E.snapAxis(458, 100, [400], 10);
    ok(s.line === 400 && s.delta === -8, "so does the near edge (408 -> 400)");
    // the closest of several wins
    s = E.snapAxis(500, 0, [496, 503], 10);
    ok(s.line === 503 && s.delta === 3, "the closest guide wins");
    s = E.snapAxis(100, 50, [], 10);
    ok(s.line === null, "no guides, no snap");
    ok(E.snapAxis(10, 0, [14], undefined).line === 14, "the default threshold is used");
}

// ---- the size handle ----
{
    near(E.scaleFromDrag(1, 100, 150, 0.5, 2.5), 1.5, "twice as far out is twice as big");
    near(E.scaleFromDrag(1, 100, 20, 0.5, 2.5), 0.5, "never below the least");
    near(E.scaleFromDrag(1, 100, 900, 0.5, 2.5), 2.5, "never above the most");
    near(E.scaleFromDrag(1, 100, 102, 0.5, 2.5), 1, "close to 100% it sticks");
    near(E.scaleFromDrag(1.4, 100, 100, 0.5, 2.5), 1.4, "no movement, no change");
    near(E.scaleFromDrag(2, 0, 50, 0.5, 2.5), 2, "a drag that began on the centre changes nothing");
    near(E.stepScale(1, 1, 0.05, 0.5, 2.5), 1.05, "a notch up");
    near(E.stepScale(1, -1, 0.1, 0.5, 2.5), 0.9, "a notch down");
    near(E.stepScale(2.5, 1, 0.05, 0.5, 2.5), 2.5, "stops at the top");
    near(E.stepScale(0.5, -1, 0.05, 0.5, 2.5), 0.5, "stops at the bottom");
    near(E.stepScale(0.7, 1), 0.75, "default step");
    ok(E.percent(1.2) === "120%" && E.percent(0.55) === "55%", "percent");
    // the editor's range is the model's range
    ok(M.SCALE_MIN === E.SCALE_LO && M.SCALE_MAX === E.SCALE_HI, "the editor's size range is the model's");
    near(E.stepScale(0.7, 1), 0.75, "the range defaults to the model's");
    near(E.scaleFromDrag(1, 100, 900), 2.5, "so does the handle's");
}

// ---- undo / redo ----
{
    const b0 = M.defaultBoard();
    const b1 = M.moveItem(b0, "clock-1", 0.3, 0.3);
    const b2 = M.scaleItem(b1, "clock-1", 1.5);
    let h = E.emptyHistory();
    ok(E.undo(h, b0) === null && E.redo(h, b0) === null, "nothing to undo or redo at the start");
    h = E.record(h, b0);
    h = E.record(h, b1);
    const u1 = E.undo(h, b2);
    ok(E.same(u1.board, b1), "undo gives the board before the last edit");
    ok(u1.h.undo.length === 1 && u1.h.redo.length === 1, "and moves it to redo");
    const u2 = E.undo(u1.h, u1.board);
    ok(E.same(u2.board, b0) && u2.h.undo.length === 0, "undo again reaches the first board");
    ok(E.undo(u2.h, u2.board) === null, "and stops");
    const r1 = E.redo(u2.h, u2.board);
    ok(E.same(r1.board, b1), "redo goes forward again");
    const r2 = E.redo(r1.h, r1.board);
    ok(E.same(r2.board, b2), "to the newest");
    ok(E.redo(r2.h, r2.board) === null, "and stops");
    // a new edit after an undo forgets the redo
    const h3 = E.record(u1.h, u1.board);
    ok(h3.redo.length === 0, "an edit clears redo");
    // history never changes the one it is given
    const frozen = E.record(E.emptyHistory(), b0);
    const copy = JSON.stringify(frozen);
    E.record(frozen, b1); E.undo(frozen, b1); E.redo(frozen, b1);
    ok(JSON.stringify(frozen) === copy, "history functions do not change their input");
    // the history is capped
    let big = E.emptyHistory();
    for (let i = 0; i < E.HISTORY_CAP + 25; i++)
        big = E.record(big, M.moveItem(b0, "clock-1", (i % 90) / 100, 0.5));
    ok(big.undo.length === E.HISTORY_CAP, "history is capped at " + E.HISTORY_CAP);
    // boards that come back out of history are still clean boards
    ok(E.same(M.cleanBoard(u1.board), u1.board), "a board from history is a clean board");
}

// ---- selection cycling ----
{
    const ids = ["clock-1", "date-1", "core"];
    ok(E.cycle(ids, "", 1) === "clock-1" && E.cycle(ids, "", -1) === "core", "from nothing: first or last");
    ok(E.cycle(ids, "clock-1", 1) === "date-1" && E.cycle(ids, "core", 1) === "clock-1", "forward wraps");
    ok(E.cycle(ids, "clock-1", -1) === "core" && E.cycle(ids, "date-1", -1) === "clock-1", "backward wraps");
    ok(E.cycle([], "x", 1) === "", "nothing to select");
    ok(E.cycle(ids, "gone-9", 1) === "clock-1", "a selection that is gone starts over");
}

// ---- words ----
{
    ok(E.optionLabel("since") === "Locked since" && E.optionLabel("zzz") === "Zzz", "option labels");
    ok(E.valueLabel(true) === "On" && E.valueLabel(false) === "Off" && E.valueLabel("auto") === "Auto" && E.valueLabel("12h") === "12h", "value labels");
    // every option the catalog has can be labelled
    for (const k of M.kinds())
        for (const o of Object.keys(M.CATALOG[k].options))
            ok(typeof E.LABELS[o] === "string", k + "." + o + ": has a label in the editor");
}

// ---- the model's helpers for the editor ----
{
    for (const k of M.kinds()) {
        const d = M.describe(k);
        ok(d.kind === k && d.title === M.CATALOG[k].title && d.icon === M.CATALOG[k].icon && d.max === M.CATALOG[k].max, k + ": describe");
        eq(d.options.map(o => o.key).sort(), Object.keys(M.CATALOG[k].options).sort(), k + ": describe lists its options");
        for (const o of d.options) {
            const spec = M.CATALOG[k].options[o.key];
            ok(o.type === spec.type && o.def === spec.def, k + "." + o.key + ": type and default");
            if (spec.type === "enum") eq(o.values, spec.values, k + "." + o.key + ": values");
            if (spec.type === "string") ok(o.max === spec.max, k + "." + o.key + ": limit");
        }
        // a copy: changing it leaves the catalog alone
        d.title = "x"; d.options.length = 0;
        ok(M.CATALOG[k].title !== "x" && Object.keys(M.CATALOG[k].options).length === M.describe(k).options.length, k + ": describe is a copy");
    }
    ok(M.describe("nope") === null && M.describe(undefined) === null && M.describe("__proto__") === null && M.describe("constructor") === null, "unknown names describe as null");

    const lim = M.coreLimits();
    ok(lim.xMin < lim.xMax && lim.yMin < lim.yMax && lim.w > 0 && lim.h > 0, "core limits are a real range");
    lim.xMin = 99;
    ok(M.coreLimits().xMin !== 99 && M.CORE.xMin !== 99, "coreLimits is a copy");
    // the editor keeps the block inside the range the model clamps to
    const moved = M.setCore(M.defaultBoard(), 5, -5);
    ok(moved.core.x === M.CORE.xMax && moved.core.y === M.CORE.yMin, "the model clamps the block (the editor draws that range)");

    // own boards per monitor
    let model = M.defaultModel();
    ok(!M.hasBoard(model, "DP-1") && !M.hasBoard(model, "*") && !M.hasBoard(model, undefined), "no own board at first, and the shared one is not 'own'");
    model = M.withBoard(model, "DP-1", M.addItem(M.defaultBoard(), "text", 0.5, 0.5).board);
    ok(M.hasBoard(model, "DP-1") && !M.hasBoard(model, "DP-2"), "a monitor with a board of its own");
    ok(M.boardFor(model, "DP-1").items.some(i => i.kind === "text"), "it wears it");
    ok(!M.boardFor(model, "DP-2").items.some(i => i.kind === "text"), "another monitor wears the shared one");
    const dropped = M.dropBoard(model, "DP-1");
    ok(!M.hasBoard(dropped, "DP-1") && !M.boardFor(dropped, "DP-1").items.some(i => i.kind === "text"), "dropped: back to the shared board");
    ok(M.hasBoard(model, "DP-1"), "dropBoard does not change the model it was given");
    ok(M.dropBoard(model, "*").boards["*"] !== undefined, "the shared board can not be dropped");
    ok(M.dropBoard(M.defaultModel(), "DP-9").boards["*"] !== undefined, "dropping nothing is fine");
    ok(M.dropBoard(null, "DP-1").boards["*"] !== undefined, "garbage in: a model with a shared board");
    ok(!M.hasBoard(model, "../etc"), "a monitor name that is not one is never 'own'");
}

// ---- a whole editing session, through the model, ends in a clean board ----
{
    let b = M.defaultBoard();
    const hist = [];
    let h = E.emptyHistory();
    const edit = next => { h = E.record(h, b); b = next; };
    edit(M.moveItem(b, "clock-1", E.keepOn(0.1, 560, 1, 1920), E.keepOn(0.1, 230, 1, 1080)));
    const added = M.addItem(b, "text", 0.5, 0.5); edit(added.board);
    edit(M.setOption(b, added.uid, "text", "Hello world"));
    edit(M.scaleItem(b, added.uid, E.stepScale(1, 1, 0.05, M.SCALE_MIN, M.SCALE_MAX)));
    edit(M.setCore(b, 0.3, 0.9));
    edit(M.removeItem(b, "battery-1"));
    ok(!b.items.some(i => i.uid === "battery-1") && b.items.some(i => i.uid === added.uid), "the session did what it was asked");
    ok(E.same(M.cleanBoard(b), b), "and the result is a clean board");
    // undo all the way back to the start
    let steps = 0, cur = b, r;
    while ((r = E.undo(h, cur)) !== null) { h = r.h; cur = r.board; steps++; }
    ok(steps === 6 && E.same(cur, M.defaultBoard()), "six undos give back the first layout");
}

console.log("LockEditMath: " + n + " checks passed");
