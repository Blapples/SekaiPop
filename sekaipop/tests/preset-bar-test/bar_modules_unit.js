// node tests/preset-bar-test/bar_modules_unit.js   (run from the sekaipop folder)
// A desktop preset wears the bar pills it was saved with, and nothing newer: a pill that was
// added after the preset was saved is OFF for it (DesktopPresetService.wornSettings).
const assert = require("assert"), fs = require("fs")
const locate = require("../lib/locate.js")
const src = fs.readFileSync(locate("modules/common/functions/PresetParts.js"), "utf8").replace(".pragma library", "")
const PP = new Function(src + "; return { withBarOff, barNoModules }")()

// the real lists, read from the source
const bar = fs.readFileSync(locate("services/BarLayoutService.qml"), "utf8")
const ids = [...bar.match(/builtinModules: \[([\s\S]*?)\n    \]/)[1].matchAll(/id: "(\w+)"/g)].map(m => m[1])
const legacy = [...bar.match(/legacyModules: \[([\s\S]*?)\]/)[1].matchAll(/"(\w+)"/g)].map(m => m[1])
const settings = fs.readFileSync(locate("services/SettingsService.qml"), "utf8")
const defaults = {}
for (const id of ids) {
    const m = settings.match(new RegExp('"bar\\.' + id + '":\\s*(true|false)'))
    assert.ok(m, "bar." + id + " has a default in SettingsService")
    defaults["bar." + id] = m[1] === "true"
}

// the three pills added after the first presets are the ones an old preset must not get
const later = ids.filter(id => legacy.indexOf(id) < 0).sort()
assert.deepStrictEqual(later, ["netSpeed", "screenTime", "timer"], "the pills newer than the legacy list")
for (const id of legacy) assert.ok(ids.indexOf(id) >= 0, "legacy " + id + " is still a module")

// an old preset (no list): the newer pills are off, everything else is left alone
const old = PP.withBarOff({ "bar.weather": false, "theme.x": 1 }, legacy, ids, defaults)
assert.strictEqual(old["bar.timer"], false)
assert.strictEqual(old["bar.netSpeed"], false)
assert.strictEqual(old["bar.screenTime"], false)
assert.strictEqual(old["bar.weather"], false, "its own choice stays")
assert.strictEqual(old["theme.x"], 1)
assert.strictEqual("bar.clock" in old, false, "a pill it knew is not touched")
assert.strictEqual("bar.resources" in old, false, "an off-by-default pill needs no line")

// a preset saved with the pills lists them: they follow its own settings (on by default)
const fresh = PP.withBarOff({}, ids, ids, defaults)
assert.deepStrictEqual(fresh, {}, "nothing is forced on a preset that knew every pill")
const freshOff = PP.withBarOff({ "bar.timer": false }, ids, ids, defaults)
assert.deepStrictEqual(freshOff, { "bar.timer": false })

// a pill added in some later version: a preset saved today (listing `ids`) wears it off
const future = PP.withBarOff({}, ids, ids.concat("brandNew"), Object.assign({ "bar.brandNew": true }, defaults))
assert.deepStrictEqual(future, { "bar.brandNew": false })

// the input is not changed
const input = { "bar.a": true }
PP.withBarOff(input, [], ["a"], { "bar.a": true })
assert.deepStrictEqual(input, { "bar.a": true })

// the list of pills is not part of what is compared
assert.deepStrictEqual(PP.barNoModules({ style: "x", modules: ["a"] }), { style: "x" })
assert.strictEqual(PP.barNoModules(undefined), undefined)

// wiring: the service saves the list, wears and compares through wornSettings
const svc = fs.readFileSync(locate("services/DesktopPresetService.qml"), "utf8").replace(/\/\/.*$/gm, "")
assert.ok(/modules:\s*BarLayoutService\.builtinModules\.map/.test(svc), "capture() saves the list of pills")
assert.ok(/applyPreset\(root\.wornSettings\(d\)/.test(svc), "wearing uses wornSettings")
assert.ok(/const worn = root\.wornSettings\(data\)/.test(svc), "the tick compares the worn settings")
assert.ok(/const mine = root\.wornSettings\(d\)/.test(svc), "the motion plan compares the worn settings")

console.log("bar_modules_unit: all checks passed")
