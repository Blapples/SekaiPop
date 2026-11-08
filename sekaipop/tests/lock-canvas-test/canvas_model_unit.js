// Unit test for modules/common/functions/LockCanvasModel.js: the rules of the Custom
// lockscreen's saved layout. Pure logic, no QML. Run:
//   node tests/lock-canvas-test/canvas_model_unit.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const file = path.join(__dirname, "..", "..", "modules", "common", "functions", "LockCanvasModel.js");
const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library/m, "");
const names = ["VERSION", "MAX_ITEMS", "SCALE_MIN", "SCALE_MAX", "MAX_TEXT", "SHARED", "CORE", "CATALOG", "kinds", "known",
    "isPrivate", "cleanBoard", "defaultBoard", "defaultModel", "parse", "stringify", "boardFor", "withBoard", "addItem",
    "moveItem", "scaleItem", "setOption", "removeItem", "setCore", "placeAxis", "cleanPath", "cleanString"];
const M = new Function(src + ";return {" + names.map(n => n + ":" + n).join(",") + "}")();

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };
const eq = (a, b, msg) => { assert.deepStrictEqual(a, b, msg); n++; };

// ---- the catalog is complete and well formed ----
for (const k of M.kinds()) {
    const c = M.CATALOG[k];
    ok(typeof c.title === "string" && c.title !== "", k + ": has a title");
    ok(typeof c.icon === "string" && c.icon !== "", k + ": has an icon");
    ok(c.privacy === "public" || c.privacy === "private", k + ": says whether it is private");
    ok(c.w > 0 && c.h > 0 && c.max >= 1, k + ": has a size and a limit");
    for (const [o, spec] of Object.entries(c.options)) {
        ok(["enum", "bool", "string", "path"].includes(spec.type), k + "." + o + ": known option type");
        if (spec.type === "enum") ok(spec.values.includes(spec.def), k + "." + o + ": default is one of the values");
        if (spec.type === "bool") ok(typeof spec.def === "boolean", k + "." + o + ": bool default");
    }
}
ok(M.known("clock") && !M.known("__proto__") && !M.known("constructor") && !M.known("toString") && !M.known(5), "only catalog names are known");
ok(!M.isPrivate("clock") && !M.isPrivate("nope"), "isPrivate follows the catalog");

// ---- the first layout: every widget known, inside the screen, none on another ----
const def = M.defaultBoard();
ok(def.items.length >= 6, "the default board has widgets");
const rect = (cx, cy, w, h) => ({ l: cx * 1920 - w / 2, t: cy * 1080 - h / 2, r: cx * 1920 + w / 2, b: cy * 1080 + h / 2 });
const rects = def.items.map(i => ({ uid: i.uid, ...rect(i.x, i.y, M.CATALOG[i.kind].w, M.CATALOG[i.kind].h) }));
rects.push({ uid: "core", ...rect(def.core.x, def.core.y, M.CORE.w, M.CORE.h) });
for (const r of rects) ok(r.l >= 0 && r.t >= 0 && r.r <= 1920 && r.b <= 1080, r.uid + ": on a 1080p screen");
for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
    const a = rects[i], b = rects[j];
    ok(a.r <= b.l || b.r <= a.l || a.b <= b.t || b.b <= a.t, a.uid + " and " + b.uid + " do not overlap");
}

// ---- a model is always readable, and always has the shared board ----
for (const bad of ["", "nope", "null", "[]", "{}", '{"v":2,"boards":{}}', '{"v":1}', '{"v":1,"boards":5}', '{"v":1,"boards":[]}']) {
    const m = M.parse(bad);
    ok(m.v === M.VERSION && m.boards[M.SHARED] && m.boards[M.SHARED].items.length > 0, "unreadable text gives the default: " + bad);
}
const round = M.parse(M.stringify(M.defaultModel()));
eq(round, M.defaultModel(), "the default model survives a save and a load");

// ---- a hostile or damaged file can only give a plainer screen ----
const hostile = {
    v: 1,
    boards: {
        "*": {
            core: { x: -5, y: 99 },
            items: [
                { uid: "clock-1", kind: "clock", x: 7, y: -3, scale: 99, options: { format: "rm -rf", extra: "x" } },
                { kind: "__proto__", x: 0.5, y: 0.5 },
                { kind: "constructor" },
                { kind: "../../etc/passwd" },
                { kind: "clock", x: 0.1, y: 0.1 },                       // a second clock: over the limit
                { uid: "text-1", kind: "text", x: "0.5", y: NaN, scale: Infinity, options: { text: "hi\u0007\nthere  ", size: "huge" } },
                { uid: "text-1", kind: "text", options: { text: "same uid" } },
                { uid: "image-9", kind: "image", options: { path: "/home/u/../../etc/shadow.png" } },
                { uid: "image-8", kind: "image", options: { path: "/home/u/pic.PNG" } },
                { uid: "image-7", kind: "image", options: { path: "/home/u/pic.png?x" } },
                { uid: "image-6", kind: "image", options: { path: "relative.png" } },
                { uid: "image-5", kind: "image", options: { path: "/home/u/script.sh" } },
                null, 5, "x", []
            ]
        },
        "DP-1": { items: [] },
        "bad name!": { items: [{ kind: "clock" }] },
        "__proto__": { items: [{ kind: "clock" }] }
    }
};
const hm = M.parse(JSON.stringify(hostile));
const hb = hm.boards[M.SHARED];
ok(hb.core.x === M.CORE.xMin && hb.core.y === M.CORE.yMax, "the password block is pulled back into its range");
const clock = hb.items.find(i => i.kind === "clock");
ok(clock && clock.x === 1 && clock.y === 0 && clock.scale === M.SCALE_MAX, "numbers are clamped");
eq(clock.options, { format: "auto" }, "an option outside the catalog's values is the default, extra keys are gone");
ok(hb.items.filter(i => i.kind === "clock").length === 1, "a second clock is dropped (the catalog allows one)");
ok(hb.items.every(i => M.known(i.kind)), "unknown kinds are dropped");
const texts = hb.items.filter(i => i.kind === "text");
ok(texts.length === 2 && texts[0].uid !== texts[1].uid, "a repeated uid is replaced by a free one");
eq(texts[0].options.text, "hithere", "control characters are removed and the text trimmed");
eq(texts[0].options.size, "medium", "an unknown size is the default");
ok(texts[0].x === 0.5 && texts[0].y === 0.5 && texts[0].scale === 1, "non-numbers are the defaults");
const imgs = hb.items.filter(i => i.kind === "image").map(i => i.options.path);
eq(imgs, ["", "/home/u/pic.PNG", "", "", ""], "only an absolute picture path without .. ? # survives");
ok(Object.keys(hm.boards).sort().join() === "*,DP-1", "odd monitor names are dropped");
eq(Object.getPrototypeOf(hm.boards), Object.prototype, "the boards object has no odd prototype");

// ---- limits ----
const many = { items: [] };
for (let i = 0; i < 100; i++) many.items.push({ kind: "text", uid: "text-" + (i + 1) });
ok(M.cleanBoard(many).items.length === M.CATALOG.text.max, "no more of a kind than the catalog allows");
ok(M.cleanString("a".repeat(500), M.MAX_TEXT, "") .length === M.MAX_TEXT, "text is cut to its limit");
ok(M.cleanPath("/" + "a".repeat(5000) + ".png") === "", "an enormous path is refused");

// ---- the password block can not be lost ----
for (const b of [null, undefined, 5, "x", {}, { core: null }, { core: { x: "a", y: [] } }, { items: "no" }]) {
    const c = M.cleanBoard(b);
    ok(c.core && c.core.x >= M.CORE.xMin && c.core.x <= M.CORE.xMax && c.core.y >= M.CORE.yMin && c.core.y <= M.CORE.yMax,
        "every board has a password block in range: " + JSON.stringify(b));
}
ok(M.cleanBoard({ items: [] }).items.length === 0, "an empty board stays empty (just the password block)");

// ---- per monitor ----
let model = M.defaultModel();
eq(M.boardFor(model, "DP-1"), model.boards[M.SHARED], "a monitor without its own board uses the shared one");
const mine = M.addItem(M.cleanBoard({ items: [] }), "clock", 0.3, 0.3).board;
model = M.withBoard(model, "DP-1", mine);
eq(M.boardFor(model, "DP-1").items.map(i => i.kind), ["clock"], "a monitor can have its own board");
eq(M.boardFor(model, "HDMI-A-1"), model.boards[M.SHARED], "the others still use the shared one");
eq(M.boardFor(model, "weird name"), model.boards[M.SHARED], "an odd monitor name uses the shared one");
eq(M.boardFor(null, "DP-1"), M.defaultBoard(), "no model at all: the default board");

// ---- edits ----
let b = M.cleanBoard({ items: [] });
let r = M.addItem(b, "text", 0.4, 0.6);
ok(r.uid === "text-1" && r.board.items.length === 1, "addItem adds one");
ok(b.items.length === 0, "addItem does not change its input");
r = M.addItem(r.board, "text");
ok(r.uid === "text-2", "the next one gets the next free number");
b = M.removeItem(r.board, "text-1");
ok(b.items.length === 1 && b.items[0].uid === "text-2", "removeItem removes that one");
r = M.addItem(b, "text");
ok(r.uid === "text-1", "a freed number is used again");
r = M.addItem(M.addItem(M.cleanBoard({ items: [] }), "clock").board, "clock");
ok(r.uid === "" && r.board.items.length === 1, "a second clock is refused");
ok(M.addItem(b, "nope").uid === "" && M.addItem(b, "__proto__").uid === "", "an unknown kind is refused");
b = M.moveItem(b, "text-2", 2, -1);
ok(b.items[0].x === 1 && b.items[0].y === 0, "a move is clamped to the screen");
b = M.scaleItem(b, "text-2", 0.01);
ok(b.items[0].scale === M.SCALE_MIN, "a scale is clamped");
b = M.setOption(b, "text-2", "text", "Good morning");
b = M.setOption(b, "text-2", "size", "large");
b = M.setOption(b, "text-2", "evil", "x");
b = M.setOption(b, "text-2", "size", "gigantic");
ok(b.items[0].options.text === "Good morning" && b.items[0].options.size === "medium" && !("evil" in b.items[0].options), "options are checked on every change");
ok(M.moveItem(b, "nothing", 0.1, 0.1).items.length === b.items.length, "editing a widget that is not there changes nothing");
b = M.setCore(b, 0, 0);
ok(b.core.x === M.CORE.xMin && b.core.y === M.CORE.yMin, "the password block can be moved, within its range");

// ---- placing keeps the drawn widget on the screen ----
const W = 1920;
ok(M.placeAxis(0.5, 400, 1, W) === 760, "centred");
ok(M.placeAxis(0, 400, 1, W) === 0, "pushed back from the left edge");
ok(M.placeAxis(1, 400, 1, W) === W - 400, "pushed back from the right edge");
ok(M.placeAxis(0, 400, 2, W) === 200, "scaled up around its centre it still starts at the edge (x = (drawn - size) / 2)");
ok(M.placeAxis(1, 400, 2, W) === W - 400 - 200, "scaled up, at the right edge");
const wide = M.placeAxis(0.5, 3000, 1, W);
ok(wide === 0, "wider than the screen: it starts at the edge");

console.log("LockCanvasModel: " + n + " checks passed");
