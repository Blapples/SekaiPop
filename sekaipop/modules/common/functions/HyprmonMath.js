.pragma library

// Pure helpers for the hyprmon display handler (services/HyprmonService.qml and the
// hyprmon side of services/DisplayService.qml): no QML, so they can be checked on their
// own (tests/display-test/hyprmon_unit.js).
//
// hyprmon (github.com/erans/hyprmon) keeps monitor profiles as JSON files in
// ~/.config/hyprmon/profiles/<name>.json. A profile's monitors are matched to the
// screens that are plugged in by a hardware id, "make/model/serial" (or "make/model"
// with no serial), never by connector name (DP-3 today may be DP-7 tomorrow). Two
// screens with the same id get "/#1", "/#2" by connector name, as hyprmon does.
//
// A "screen" here is what Hyprland reports, trimmed: { name, make, model, serial, ... }.

// "make/model/serial", "make/model", or "" (hyprmon's buildHardwareID).
function hardwareId(make, model, serial) {
    var mk = String(make || "").trim(), md = String(model || "").trim(), sr = String(serial || "").trim();
    if (mk === "" && md === "")
        return "";
    return sr === "" ? mk + "/" + md : mk + "/" + md + "/" + sr;
}

// { name: hardwareId } for a list of screens, with identical ids told apart by
// connector name ("/#1", "/#2"), as hyprmon's disambiguateHardwareIDs does.
function hardwareIds(screens) {
    var ids = {}, count = {};
    for (var i = 0; i < screens.length; i++) {
        var id = hardwareId(screens[i].make, screens[i].model, screens[i].serial);
        ids[screens[i].name] = id;
        if (id !== "")
            count[id] = (count[id] || 0) + 1;
    }
    var names = screens.map(function (s) { return s.name; }).sort();
    var seen = {};
    for (var j = 0; j < names.length; j++) {
        var base = ids[names[j]];
        if (base !== "" && count[base] > 1) {
            seen[base] = (seen[base] || 0) + 1;
            ids[names[j]] = base + "/#" + seen[base];
        }
    }
    return ids;
}

// The connected screen a profile monitor stands for, or null. By hardware id; a profile
// written before hyprmon had ids falls back to the connector name.
function resolve(pm, connected) {
    for (var i = 0; i < connected.length; i++) {
        var c = connected[i];
        if (pm.hardware_id ? c.hwid === pm.hardware_id : c.name === pm.name)
            return c;
    }
    return null;
}

// How well a profile fits the screens plugged in now. `connected`: [{ name, hwid }].
//   ok      it can be applied without leaving you with no screen: every screen the
//           profile turns on is plugged in, and there is at least one.
//   score   3 = it knows exactly these screens, 2 = it knows every screen plugged in
//           (and some that are not), 1 = it misses some plugged-in screens (they are
//           left as Hyprland sets them up), 0 = not ok.
function matchProfile(profile, connected) {
    var mons = (profile && profile.monitors) || [];
    var activeOn = 0, activeMissing = 0, allConnected = true;
    var known = {};
    for (var i = 0; i < mons.length; i++) {
        var c = resolve(mons[i], connected);
        if (c)
            known[c.name] = true;
        else
            allConnected = false;
        if (mons[i].Active) {
            if (c)
                activeOn++;
            else
                activeMissing++;
        }
    }
    var covers = connected.every(function (c) { return known[c.name] === true; });
    var ok = activeOn > 0 && activeMissing === 0;
    var score = !ok ? 0 : (covers && allConnected ? 3 : (covers ? 2 : 1));
    return { ok: ok, score: score };
}

// The key a set of plugged-in screens is remembered by: their ids, sorted.
function setKey(connected) {
    return connected.map(function (c) { return c.hwid || c.name; }).sort().join("+");
}

// Which profile to put on for the screens plugged in now, or "" for none.
// `profiles` in the user's order; `remembered` is { setKey: profileName } (the one used
// last on this set of screens), which settles a tie (Home vs Home-share on the same
// screens); otherwise the first in the order wins.
function chooseProfile(profiles, connected, remembered) {
    var best = 0, ties = [];
    for (var i = 0; i < profiles.length; i++) {
        var m = matchProfile(profiles[i], connected);
        if (m.score > best) {
            best = m.score;
            ties = [profiles[i].name];
        } else if (m.score === best && best > 0) {
            ties.push(profiles[i].name);
        }
    }
    if (ties.length === 0)
        return "";
    var last = remembered ? remembered[setKey(connected)] : undefined;
    return last !== undefined && ties.indexOf(last) >= 0 ? last : ties[0];
}

// What Hyprland calls the frame format -> the colour depth hyprmon stores (8 or 10).
function bitDepthOf(currentFormat) {
    return /2101010|101010/.test(String(currentFormat || "")) ? 10 : 8;
}

// hyprmon's colour modes, in the order the card shows them.
var COLOR_MODES = ["auto", "srgb", "wide", "edid", "hdr", "hdredid"];

function isHdr(cm) {
    return cm === "hdr" || cm === "hdredid";
}

// The settings a screen has beyond mode / position / scale, as "key=value" for
// displays.sh (and so as the fields of hl.monitor). Only what differs from Hyprland's
// default is said, as hyprmon writes it; a mirrored screen takes nothing but `mirror`.
function extras(d) {
    var out = [];
    if (d.mirror) {
        out.push("mirror=" + d.mirror);
        return out;
    }
    if ((d.transform | 0) > 0)
        out.push("transform=" + (d.transform | 0));
    if ((d.vrr | 0) > 0)
        out.push("vrr=" + (d.vrr | 0));
    if ((d.bitDepth | 0) === 10)
        out.push("bitdepth=10");
    if (d.cm && d.cm !== "srgb" && COLOR_MODES.indexOf(d.cm) >= 0)
        out.push("cm=" + d.cm);
    if (isHdr(d.cm)) {
        if (d.sdrBrightness && Math.abs(d.sdrBrightness - 1) > 1e-6)
            out.push("sdrbrightness=" + Number(d.sdrBrightness).toFixed(2));
        if (d.sdrSaturation && Math.abs(d.sdrSaturation - 1) > 1e-6)
            out.push("sdrsaturation=" + Number(d.sdrSaturation).toFixed(2));
    }
    return out;
}

// Would `name` mirroring `source` go round in a circle (source mirrors name, or a
// screen that mirrors it does)? `draft`: [{ name, mirror }].
function mirrorLoops(draft, name, source) {
    if (!source)
        return false;
    if (source === name)
        return true;
    var by = {};
    draft.forEach(function (d) { by[d.name] = d.mirror || ""; });
    var at = source, steps = 0;
    while (at && steps < 32) {
        if (at === name)
            return true;
        at = by[at];
        steps++;
    }
    return false;
}

// One draft screen as a hyprmon profile monitor. `hwid` from hardwareIds(); `x`, `y`
// where it sits (logical px); `mode` its { w, h, hz }; `prev` the same screen in the
// profile being overwritten, if any (its alias and "write as desc:" choice are kept).
function toProfileMonitor(d, hwid, x, y, mode, prev) {
    var p = prev || {};
    var mon = {
        name: d.name,
        hardware_id: hwid || undefined,
        alias: p.alias || undefined,
        make: d.make || undefined,
        model: d.model || undefined,
        serial: d.serial || undefined,
        use_desc_format: p.use_desc_format ? true : undefined,
        PxW: mode ? mode.w : 0,
        PxH: mode ? mode.h : 0,
        Hz: mode ? Math.round(mode.hz * 1000) / 1000 : 0,
        Scale: Math.round(Number(d.scale || 1) * 100) / 100,
        X: Math.round(x || 0),
        Y: Math.round(y || 0),
        Active: !!d.on,
        EDIDName: d.desc || "",
        Modes: (d.modes || []).map(function (m) { return { W: m.w, H: m.h, Hz: m.hz }; }),
        BitDepth: (d.bitDepth | 0) === 10 ? 10 : 8,
        ColorMode: d.cm || "srgb",
        SDRBrightness: Number(d.sdrBrightness || 1),
        SDRSaturation: Number(d.sdrSaturation || 1),
        VRR: d.vrr | 0,
        Transform: d.transform | 0,
        IsMirrored: !!d.mirror,
        MirrorSource: d.mirror || "",
        MirrorTargets: null,
        Dragging: false,
        DragOffX: 0,
        DragOffY: 0
    };
    // JSON.stringify drops the undefined ones, as Go's omitempty would.
    return mon;
}

// The screens a profile will hold after saving `fresh` into it: the screens saved now
// replace the profile's own (same hardware id, or name for an old profile), and the
// profile's screens that are not plugged in now are kept as they were. Mirror targets
// are worked out again from the sources.
function mergeMonitors(old, fresh) {
    var out = fresh.slice();
    (old || []).forEach(function (pm) {
        var replaced = fresh.some(function (f) {
            return pm.hardware_id ? f.hardware_id === pm.hardware_id : f.name === pm.name;
        });
        if (!replaced)
            out.push(pm);
    });
    out.forEach(function (m) {
        var targets = out.filter(function (t) { return t.IsMirrored && t.MirrorSource === m.name; })
                         .map(function (t) { return t.name; });
        m.MirrorTargets = targets.length > 0 ? targets : null;
    });
    return out;
}

// A profile's monitor by hardware id (or name), for `prev` in toProfileMonitor().
function findMonitor(profile, hwid, name) {
    var mons = (profile && profile.monitors) || [];
    for (var i = 0; i < mons.length; i++) {
        if (hwid && mons[i].hardware_id === hwid)
            return mons[i];
    }
    for (var j = 0; j < mons.length; j++) {
        if (!mons[j].hardware_id && mons[j].name === name)
            return mons[j];
    }
    return null;
}

// One line about a profile for the card: "DP-7 3440x1440 · eDP-1 1920x1200" (screens
// that are on), "eDP-1 off" for the ones it turns off.
function summary(profile) {
    return ((profile && profile.monitors) || []).map(function (m) {
        var label = m.alias || m.name;
        if (!m.Active)
            return label + " off";
        if (m.IsMirrored && m.MirrorSource)
            return label + " mirrors " + m.MirrorSource;
        return label + " " + m.PxW + "x" + m.PxH + (Math.abs((m.Scale || 1) - 1) > 1e-6 ? " @" + Math.round(m.Scale * 100) + "%" : "");
    }).join("  \u00b7  ");
}

// A profile name hyprmon can keep as a file: letters, digits, space, _ . -, not
// starting with a dot, at most 64.
function validName(name) {
    var s = String(name || "");
    return s.length > 0 && s.length <= 64 && /^[A-Za-z0-9 _.-]+$/.test(s) && s[0] !== "." && s.trim() === s;
}
