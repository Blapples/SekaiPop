.pragma library

// The widget half of a desktop preset (services/DesktopPresetService.qml +
// services/PresetWidgets.qml). Pure functions on plain objects, so they can be
// unit-tested with node: tests/preset-widgets-test/registry_unit.js.
//
// One rule runs all of it, and it is the one that keeps an old preset from
// dragging anything newer along:
//
//     A preset wears what it holds.
//     Anything it can't hold, because it was saved BEFORE that existed, is worn as
//     the way things were back then:
//       - a whole widget it has no part for is switched OFF,
//       - an option of a widget it holds (a look, a size, a direction) is worn as the
//         value listed in the widget's `before` (see below).
//     So wearing an old preset always gives the same result, whatever the widget is
//     set to right now.
//
// The widgets themselves are listed in PresetWidgets.qml, one entry each:
//
//   {
//     id:      "clock"                  the key inside a preset's `widgets` object
//     service: ClockService             must have shown + setShown(bool)
//     skip:    ["use24h"]               keys of the widget's own saved piece that a
//                                       preset never carries (yours, not the look's)
//     before:  { style: "classic" }     what each option that was ADDED LATER was
//                                       before it existed. One line per new option.
//
//     // Only for a widget that is NOT "snapshot() out, restore() back in":
//     capture:    () => object          what a preset holds for it
//     wear:       (part, ctx) => void   put that part on (ctx = { name, wearFrames })
//
//     // Optional:
//     normalize:  part => part          only for a value that was RENAMED (an old preset
//                                       says "full", the widget now says "classic"); used
//                                       when wearing AND when asking "is this the preset
//                                       I'm wearing". Not for new options: use `before`.
//     digestStub: () => object          what "is this the one I'm wearing" compares
//                                       for a preset that has no part for it (default:
//                                       what the widget is now, switched off)
//   }

function isObj(v) {
    return !!v && typeof v === "object" && !Array.isArray(v)
}

// A snapshot-based widget's own saved piece, without the keys a preset never carries.
function snapshotPart(entry) {
    var s = {}
    try {
        s = JSON.parse(entry.service.snapshot())
    } catch (e) {
    }
    if (!isObj(s))
        s = {}
    var skip = entry.skip || []
    for (var i = 0; i < skip.length; i++)
        delete s[skip[i]]
    return s
}

// What the widget is right now, as a preset would hold it.
function partNow(entry) {
    return entry.capture ? entry.capture() : snapshotPart(entry)
}

// { id: part } for every registered widget. One that throws holds {} (a part with
// nothing in it: wearing it changes nothing), so one broken widget can't stop a save.
function capture(entries) {
    var out = {}
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        try {
            out[e.id] = partNow(e)
        } catch (err) {
            console.warn("PresetParts: couldn't capture widget \"" + e.id + "\" (" + err + ")")
            out[e.id] = {}
        }
    }
    return out
}

// Hands a widget its saved piece on top of what it has now, so a key the preset never
// carries on purpose (the widget's `skip`) keeps its current value. An option an old
// preset couldn't hold has already been filled in by fillBefore().
function mergeRestore(entry, saved) {
    var merged = {}
    try {
        merged = JSON.parse(entry.service.snapshot())
    } catch (e) {
    }
    if (!isObj(merged))
        merged = {}
    var skip = entry.skip || []
    for (var k in saved) {
        if (skip.indexOf(k) < 0)
            merged[k] = saved[k]
    }
    entry.service.restore(JSON.stringify(merged))
    entry.service.persist()
}

// The options an old preset could not hold, filled in with what they were before they
// existed (the entry's `before`). A key the preset does hold is never touched.
function fillBefore(entry, part) {
    var b = entry.before
    if (!isObj(b) || !isObj(part))
        return part
    var out = null
    for (var k in b) {
        if (part[k] === undefined) {
            if (!out)
                out = Object.assign({}, part)
            out[k] = b[k]
        }
    }
    return out || part
}

// What a preset's part for a widget is worn / compared as: the old options filled in,
// then any renamed value brought up to date.
function readPart(entry, part) {
    var p = fillBefore(entry, part)
    if (entry.normalize)
        p = entry.normalize(p)
    return p
}

// Puts a preset's `widgets` on. A preset with no `widgets` at all leaves them alone;
// one that has it but no part for a registered widget switches that widget OFF.
// Each widget is on its own try, so one that fails can't leave the rest unworn.
function wear(entries, widgets, ctx) {
    if (!isObj(widgets))
        return
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        try {
            var part = widgets[e.id]
            if (!isObj(part)) {
                e.service.setShown(false)
                continue
            }
            part = readPart(e, part)
            if (e.wear)
                e.wear(part, ctx)
            else
                mergeRestore(e, part)
        } catch (err) {
            console.warn("PresetParts: couldn't wear widget \"" + e.id + "\" (" + err + ")")
        }
    }
}

// ===== "is this preset what the desktop looks like right now?" =====

// What one widget's part is compared as. An option the preset can't hold is the value
// it was before (the entry's `before`), the same as when wearing it; a key that moved to
// `skip` since takes the widget's current value, so it never takes the tick away from a
// preset that wears the widget fine.
function digestPart(entry, part) {
    var p = readPart(entry, Object.assign({}, part))
    if (!entry.capture) {
        var skip = entry.skip || []
        for (var i = 0; i < skip.length; i++)
            delete p[skip[i]]
        p = Object.assign({}, snapshotPart(entry), p)
    }
    return p
}

// The widget a preset has no part for, as the comparison sees it: wearing that
// preset switches it off, so it counts as the widget now, off.
function stubPart(entry) {
    var base = entry.digestStub ? entry.digestStub() : partNow(entry)
    return Object.assign({}, base, { shown: false })
}

// The preset's `widgets`, ready to compare with capture(): one part per registered
// widget (widgets this build doesn't know are left out; it never wears them).
function digestWidgets(entries, widgets) {
    var src = isObj(widgets) ? widgets : {}
    var out = {}
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        out[e.id] = isObj(src[e.id]) ? digestPart(e, src[e.id]) : stubPart(e)
    }
    return out
}

// ===== a check of the registry itself =====
// What is wrong with the list of widgets, as text (empty = fine). DesktopPresetService
// prints these once at start, so a half-made entry shows up in the log at once
// instead of as a widget that silently doesn't follow presets.
function problems(entries) {
    var out = []
    var seen = {}
    if (!Array.isArray(entries))
        return ["the widget list is not a list"]
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        var who = e && typeof e.id === "string" ? "widget \"" + e.id + "\"" : "entry #" + i
        if (!e || typeof e.id !== "string" || e.id === "") {
            out.push(who + " has no id")
            continue
        }
        if (seen[e.id])
            out.push(who + " is listed twice")
        seen[e.id] = true
        var s = e.service
        if (!s || typeof s !== "object") {
            out.push(who + " has no service")
            continue
        }
        if (typeof s.setShown !== "function")
            out.push(who + ": its service has no setShown(), so an old preset can't switch it off")
        if (s.shown === undefined)
            out.push(who + ": its service has no `shown`")
        if (!e.capture || !e.wear) {
            for (var f of ["snapshot", "restore", "persist"]) {
                if (typeof s[f] !== "function")
                    out.push(who + ": its service has no " + f + "() (needed unless the entry has both capture and wear)")
            }
        }
        if (e.skip !== undefined && !Array.isArray(e.skip))
            out.push(who + ": skip must be a list of key names")
        if (e.before !== undefined) {
            if (!isObj(e.before)) {
                out.push(who + ": before must be an object of { option: what it was before }")
            } else {
                // A typo here would silently never match anything.
                var held = partNow(e)
                for (var k in e.before) {
                    if (!isObj(held) || !(k in held))
                        out.push(who + ": before names \"" + k + "\", which the widget doesn't save")
                }
            }
        }
    }
    return out
}

// ===== bar pills =====
// The same rule for the bar as for the widgets: a preset wears what it holds. A preset
// saves the list of bar modules the shell had when it was saved (`bar.modules`); a pill
// that is not in that list did not exist for it, so it is worn OFF, whatever the Settings
// Panel's switch for that pill is now. A preset saved before the list existed holds
// BarLayoutService.legacyModules instead (the pills there were then).

// The preset's Settings Panel part as it is worn: the same keys, plus `bar.<id>: false` for
// every pill the preset did not know. Only for a pill that is on by default (one that is off
// by default is already off, and the Settings Panel holds only what differs from a default).
function withBarOff(settings, known, allIds, defaults) {
    var out = Object.assign({}, settings)
    for (var i = 0; i < allIds.length; i++) {
        var key = "bar." + allIds[i]
        if (known.indexOf(allIds[i]) < 0 && defaults[key] === true)
            out[key] = false
    }
    return out
}

// The bar part without its list of modules (what is compared, not what is worn).
function barNoModules(bar) {
    if (!isObj(bar))
        return bar
    var out = Object.assign({}, bar)
    delete out.modules
    return out
}

