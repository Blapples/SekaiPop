.pragma library

// Pure helpers for services/DisplayService.qml (the Displays card): no QML, so
// they can be checked on their own (tests/display-test/display_unit.js).
//
// A "mode" is { w, h, hz, id } with id like "1920x1080@144.00" (what
// hl.monitor({ mode = ... }) takes). A screen's `place` is where it sits
// relative to the main screen: "right", "left", "above" or "below".

var SCALES = ["1", "1.25", "1.5", "1.75", "2"];

// ["1920x1080@144.00Hz", ...] (hyprctl's availableModes) -> [{ w, h, hz, id }].
function parseModes(list) {
    var out = [];
    for (var i = 0; i < (list || []).length; i++) {
        var m = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(String(list[i]));
        if (!m)
            continue;
        var hz = parseFloat(m[3]);
        out.push({ w: parseInt(m[1], 10), h: parseInt(m[2], 10), hz: hz,
                   id: m[1] + "x" + m[2] + "@" + hz.toFixed(2) });
    }
    return out;
}

// Which of a screen's modes is the one it runs now (hyprctl reports 143.981 where the
// list says 143.98). Falls back to the first listed mode (the preferred one), and to
// "preferred" when the screen lists none.
function matchMode(modes, w, h, hz) {
    for (var i = 0; i < modes.length; i++) {
        if (modes[i].w === w && modes[i].h === h && Math.abs(modes[i].hz - hz) < 0.6)
            return modes[i].id;
    }
    if (modes.length > 0)
        return modes[0].id;
    return w > 0 && h > 0 ? (w + "x" + h + "@" + Number(hz).toFixed(2)) : "preferred";
}

function modeById(modes, id) {
    for (var i = 0; i < modes.length; i++) {
        if (modes[i].id === id)
            return modes[i];
    }
    var m = /^(\d+)x(\d+)@([\d.]+)$/.exec(String(id));
    return m ? { w: parseInt(m[1], 10), h: parseInt(m[2], 10), hz: parseFloat(m[3]), id: id } : null;
}

// The size a screen takes in the layout: its mode divided by the scale, turned on
// its side for the rotated transforms (1, 3, 5, 7).
function logicalSize(w, h, scale, transform) {
    var s = scale > 0 ? scale : 1;
    var lw = w / s, lh = h / s;
    if ((transform | 0) % 2 === 1) {
        var t = lw; lw = lh; lh = t;
    }
    return { w: lw, h: lh };
}

// Where a screen is relative to the main one, read from live positions.
function placeOf(x, y, lw, lh, mainLw, mainLh) {
    if (x >= mainLw - 1)
        return "right";
    if (x + lw <= 1)
        return "left";
    if (y >= mainLh - 1)
        return "below";
    if (y + lh <= 1)
        return "above";
    return "right";
}

// The layout of the screens that are on. `items`: [{ name, on, w, h, scale,
// transform, place }]; `mainName` sits at the origin and the rest are stacked
// outwards on their side of it (two on the right go side by side). Everything is then
// moved so the smallest x and y are 0. Returns { name: [x, y] }.
function positions(items, mainName) {
    var en = items.filter(function (d) { return d.on; });
    var pos = {};
    if (en.length === 0)
        return pos;
    var main = en[0];
    for (var i = 0; i < en.length; i++) {
        if (en[i].name === mainName)
            main = en[i];
    }
    var msz = logicalSize(main.w, main.h, main.scale, main.transform);
    pos[main.name] = [0, 0];
    var cur = { right: msz.w, left: 0, above: 0, below: msz.h };
    for (var j = 0; j < en.length; j++) {
        var d = en[j];
        if (d === main)
            continue;
        var sz = logicalSize(d.w, d.h, d.scale, d.transform);
        if (d.place === "left") {
            cur.left += sz.w;
            pos[d.name] = [-cur.left, 0];
        } else if (d.place === "above") {
            cur.above += sz.h;
            pos[d.name] = [0, -cur.above];
        } else if (d.place === "below") {
            pos[d.name] = [0, cur.below];
            cur.below += sz.h;
        } else {
            pos[d.name] = [cur.right, 0];
            cur.right += sz.w;
        }
    }
    var minX = 0, minY = 0;
    for (var k in pos) {
        minX = Math.min(minX, pos[k][0]);
        minY = Math.min(minY, pos[k][1]);
    }
    for (var n in pos)
        pos[n] = [Math.round(pos[n][0] - minX), Math.round(pos[n][1] - minY)];
    return pos;
}

// The argument displays.sh takes for one screen: "name|on|mode|x|y|scale" or "name|off".
// A screen that is off may carry a parking spot: "name|off|x|y".
function spec(name, on, modeId, x, y, scale) {
    if (!on)
        return typeof x === "number" && typeof y === "number" ? name + "|off|" + x + "|" + y : name + "|off";
    return [name, "on", modeId, x, y, Number(scale).toFixed(2)].join("|");
}

// Distinct resolutions of a screen, biggest first, "1920x1080" ... at most `limit`
// (the one in use is always kept).
function resolutions(modes, currentId, limit) {
    var seen = {}, list = [];
    for (var i = 0; i < modes.length; i++) {
        var id = modes[i].w + "x" + modes[i].h;
        if (!seen[id]) {
            seen[id] = true;
            list.push({ id: id, area: modes[i].w * modes[i].h });
        }
    }
    list.sort(function (a, b) { return b.area - a.area; });
    var cur = currentRes(modes, currentId);
    var out = list.slice(0, limit || 10);
    if (cur && !out.some(function (r) { return r.id === cur; }))
        out.push({ id: cur, area: 0 });
    return out.map(function (r) { return { id: r.id, label: r.id }; });
}

function currentRes(modes, modeId) {
    var m = modeById(modes, modeId);
    return m ? m.w + "x" + m.h : "";
}

// The refresh rates a screen has at one resolution, fastest first.
function rates(modes, res) {
    var list = modes.filter(function (m) { return (m.w + "x" + m.h) === res; });
    list.sort(function (a, b) { return b.hz - a.hz; });
    return list.map(function (m) {
        var whole = Math.abs(m.hz - Math.round(m.hz)) < 0.05;
        return { id: m.id, label: (whole ? Math.round(m.hz) : m.hz.toFixed(2)) + " Hz" };
    });
}

// Switching resolution keeps the refresh rate as close as it can.
function modeForRes(modes, res, wantHz) {
    var best = null;
    for (var i = 0; i < modes.length; i++) {
        var m = modes[i];
        if ((m.w + "x" + m.h) !== res)
            continue;
        if (best === null || Math.abs(m.hz - wantHz) < Math.abs(best.hz - wantHz))
            best = m;
    }
    return best ? best.id : "";
}

// ===== free placement (drag a screen anywhere) =====
// A screen in the layout is a rectangle { name, x, y, w, h } in logical px (its mode
// divided by its scale, turned on its side for the rotated transforms).

function overlaps(a, b) {
    return a.x < b.x + b.w - 0.5 && b.x < a.x + a.w - 0.5
        && a.y < b.y + b.h - 0.5 && b.y < a.y + a.h - 0.5;
}

// Snap a dragged rectangle to the others: its left edge to their right edge, its right
// edge to their left edge, and flush lefts / rights / tops / bottoms, each way within
// `threshold` px. Returns { x, y }.
function snap(r, others, threshold) {
    var bestDx = null, bestDy = null;
    for (var i = 0; i < others.length; i++) {
        var o = others[i];
        var xs = [o.x + o.w - r.x, o.x - (r.x + r.w), o.x - r.x, o.x + o.w - (r.x + r.w)];
        var ys = [o.y + o.h - r.y, o.y - (r.y + r.h), o.y - r.y, o.y + o.h - (r.y + r.h)];
        for (var a = 0; a < 4; a++) {
            if (Math.abs(xs[a]) <= threshold && (bestDx === null || Math.abs(xs[a]) < Math.abs(bestDx)))
                bestDx = xs[a];
            if (Math.abs(ys[a]) <= threshold && (bestDy === null || Math.abs(ys[a]) < Math.abs(bestDy)))
                bestDy = ys[a];
        }
    }
    return { x: r.x + (bestDx === null ? 0 : bestDx), y: r.y + (bestDy === null ? 0 : bestDy) };
}

// If the rectangle sits on top of another screen, move it to the nearest spot that is
// clear: flush against the side of one of the others (keeping the other coordinate),
// or, when nothing is clear that way, past the right edge of them all. Returns { x, y }.
function separate(r, others) {
    function free(x, y) {
        for (var i = 0; i < others.length; i++) {
            if (overlaps({ x: x, y: y, w: r.w, h: r.h }, others[i]))
                return false;
        }
        return true;
    }
    if (free(r.x, r.y))
        return { x: r.x, y: r.y };
    var best = null, bestD = 0;
    function consider(x, y) {
        if (!free(x, y))
            return;
        var d = Math.abs(x - r.x) + Math.abs(y - r.y);
        if (best === null || d < bestD) {
            best = { x: x, y: y };
            bestD = d;
        }
    }
    for (var i = 0; i < others.length; i++) {
        var o = others[i];
        consider(o.x + o.w, r.y);
        consider(o.x - r.w, r.y);
        consider(r.x, o.y + o.h);
        consider(r.x, o.y - r.h);
    }
    if (best !== null)
        return best;
    var edge = r.x;
    for (var j = 0; j < others.length; j++)
        edge = Math.max(edge, others[j].x + others[j].w);
    return { x: edge, y: r.y };
}

// Put a rectangle flush against `main` on one side ("right", "left", "above", "below"),
// its top (or left) edge level with main's, and further out if another screen is there.
function dock(r, main, place, others) {
    var x, y;
    if (place === "left") {
        x = main.x - r.w; y = main.y;
    } else if (place === "above") {
        x = main.x; y = main.y - r.h;
    } else if (place === "below") {
        x = main.x; y = main.y + main.h;
    } else {
        x = main.x + main.w; y = main.y;
    }
    for (var pass = 0; pass < 8; pass++) {
        var moved = false;
        for (var i = 0; i < others.length; i++) {
            var o = others[i];
            if (!overlaps({ x: x, y: y, w: r.w, h: r.h }, o))
                continue;
            if (place === "left") x = o.x - r.w;
            else if (place === "above") y = o.y - r.h;
            else if (place === "below") y = o.y + o.h;
            else x = o.x + o.w;
            moved = true;
        }
        if (!moved)
            break;
    }
    return { x: x, y: y };
}

// One screen has changed size (resolution, scale): everything that was past its old
// right edge moves by the difference in width, everything that was past its old bottom
// edge by the difference in height, so neighbours stay neighbours. `rects` already
// holds the new size of `name`. Returns the rectangles with their new positions.
function reflow(rects, name, oldW, oldH) {
    var me = null;
    for (var i = 0; i < rects.length; i++) {
        if (rects[i].name === name)
            me = rects[i];
    }
    if (me === null)
        return rects;
    var dw = me.w - oldW, dh = me.h - oldH;
    return rects.map(function (r) {
        if (r.name === name)
            return r;
        return { name: r.name, w: r.w, h: r.h,
                 x: r.x >= me.x + oldW - 1 ? r.x + dw : r.x,
                 y: r.y >= me.y + oldH - 1 ? r.y + dh : r.y };
    });
}

// Shift { name: [x, y] } so the smallest x and y are 0, whole numbers.
function normalize(pos) {
    var minX = null, minY = null;
    for (var k in pos) {
        minX = minX === null ? pos[k][0] : Math.min(minX, pos[k][0]);
        minY = minY === null ? pos[k][1] : Math.min(minY, pos[k][1]);
    }
    var out = {};
    for (var n in pos)
        out[n] = [Math.round(pos[n][0] - minX), Math.round(pos[n][1] - minY)];
    return out;
}

// Do two screens share an edge (so the pointer can cross)?
function touches(a, b) {
    var sideX = (Math.abs(a.x + a.w - b.x) <= 1 || Math.abs(b.x + b.w - a.x) <= 1)
        && a.y < b.y + b.h - 1 && b.y < a.y + a.h - 1;
    var sideY = (Math.abs(a.y + a.h - b.y) <= 1 || Math.abs(b.y + b.h - a.y) <= 1)
        && a.x < b.x + b.w - 1 && b.x < a.x + a.w - 1;
    return sideX || sideY;
}

// The names of screens that cannot be reached from the first one by crossing edges
// (the pointer cannot get to them). Empty when the layout is one piece.
function unlinked(rects) {
    if (rects.length < 2)
        return [];
    var seen = {};
    seen[rects[0].name] = true;
    var queue = [rects[0]];
    while (queue.length > 0) {
        var cur = queue.shift();
        for (var i = 0; i < rects.length; i++) {
            if (!seen[rects[i].name] && touches(cur, rects[i])) {
                seen[rects[i].name] = true;
                queue.push(rects[i]);
            }
        }
    }
    return rects.filter(function (r) { return !seen[r.name]; }).map(function (r) { return r.name; });
}

// How the layout is drawn in a box: the screens' bounding box with room around it to
// drag into, fitted to areaW x areaH. Returns { scale, ox, oy }: a layout point (x, y)
// is drawn at (ox + x * scale, oy + y * scale).
function view(rects, areaW, areaH) {
    if (rects.length === 0)
        return { scale: 1, ox: 0, oy: 0 };
    var x0 = rects[0].x, y0 = rects[0].y, x1 = rects[0].x + rects[0].w, y1 = rects[0].y + rects[0].h;
    var big = 0;
    for (var i = 0; i < rects.length; i++) {
        x0 = Math.min(x0, rects[i].x);
        y0 = Math.min(y0, rects[i].y);
        x1 = Math.max(x1, rects[i].x + rects[i].w);
        y1 = Math.max(y1, rects[i].y + rects[i].h);
        big = Math.max(big, rects[i].w, rects[i].h);
    }
    var pad = big * 0.5;
    x0 -= pad; y0 -= pad; x1 += pad; y1 += pad;
    var scale = Math.min(areaW / (x1 - x0), areaH / (y1 - y0));
    return { scale: scale,
             ox: (areaW - (x1 - x0) * scale) / 2 - x0 * scale,
             oy: (areaH - (y1 - y0) * scale) / 2 - y0 * scale };
}

// ===== screens Hyprland does not list =====
// A screen switched off in monitors.lua can be missing from `hyprctl monitors all` after
// a restart, and then the card has nothing to switch back on. displays.sh `known` lists
// the screens the kernel says are plugged in ("name|WxH", the size may be empty).
function parseKnown(text) {
    var out = [];
    String(text || "").split("\n").forEach(function (line) {
        var parts = line.trim().split("|");
        if (!/^[A-Za-z0-9_.:-]+$/.test(parts[0] || ""))
            return;
        var m = /^(\d+)x(\d+)$/.exec(parts[1] || "");
        out.push({ name: parts[0], w: m ? parseInt(m[1], 10) : 0, h: m ? parseInt(m[2], 10) : 0 });
    });
    return out;
}

// What Hyprland lists, plus a switched-off entry for every plugged-in screen it does not.
// `hint` is the panel's size, only used to draw it in the layout until it has real modes.
function mergeKnown(hypr, known) {
    var have = {};
    hypr.forEach(function (m) { have[m.name] = true; });
    var extra = (known || []).filter(function (k) { return !have[k.name]; }).map(function (k) {
        return { name: k.name, desc: "", on: false, w: 0, h: 0, hz: 0, x: 0, y: 0, scale: 1,
                 transform: 0, modes: [], hint: k.w > 0 ? { w: k.w, h: k.h } : null };
    });
    return hypr.concat(extra);
}

// The draft screens whose on / off differs from what Hyprland reports (after Apply).
function mismatched(draft, live) {
    return draft.filter(function (d) {
        var m = live.filter(function (x) { return x.name === d.name; })[0];
        return m && m.on !== d.on;
    });
}
