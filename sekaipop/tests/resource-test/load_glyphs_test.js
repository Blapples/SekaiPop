// node tests/resource-test/load_glyphs_test.js
//
// The bar's CPU & RAM pill and its popup: CPU is the chip, RAM the pie that fills with
// the memory (issue #168; docs/RESOURCE-ICONS.md). The icon rules
// (modules/common/functions/LoadGlyphs.js) are loaded for real; the two QML files that
// use them are read as source, since node cannot load QML.
const assert = require("assert")
const fs = require("fs")
const locate = require("../lib/locate")

const src = fs.readFileSync(locate("modules/common/functions/LoadGlyphs.js"), "utf8").replace(".pragma library", "")
const LG = new Function(src + "\nreturn { CPU, pie, cpu, ram }")()

// CPU: the chip, whatever the load.
assert.strictEqual(LG.cpu(), "memory", "CPU is the chip (Material's \"memory\")")

// RAM: the pie, in Material's six steps.
const steps = [[0, 10], [14, 10], [15, 20], [29, 20], [30, 40], [49, 40], [50, 60], [69, 60], [70, 80], [84, 80], [85, 90], [100, 90]]
for (const [pct, step] of steps)
    assert.strictEqual(LG.ram(pct), "clock_loader_" + step, pct + "% of RAM is clock_loader_" + step)
assert.strictEqual(LG.ram(undefined), "clock_loader_10", "no figure yet: the emptiest pie")
assert.strictEqual(LG.ram("63"), "clock_loader_60", "a figure as text still steps")

// The bar uses them the right way round, in both the lying and the standing pill.
const bar = fs.readFileSync(locate("modules/sekai/bar/ResourceIndicator.qml"), "utf8")
assert.ok(/readonly property string cpuGlyphName: LG\.cpu\(\)/.test(bar), "the bar's CPU icon is the chip")
assert.ok(/readonly property string memGlyphName: LG\.ram\(root\.memPercent\)/.test(bar), "the bar's RAM icon is the pie, from memPercent")
assert.ok(!/clock_loader/.test(bar), "the bar no longer steps its own pie")
const cpuUses = bar.match(/name: root\.cpuGlyphName(?:(?!MaterialIcon)[\s\S])*?text: root\.cpuPercent/g) || []
const memUses = bar.match(/name: root\.memGlyphName(?:(?!MaterialIcon)[\s\S])*?text: root\.memPercent/g) || []
assert.strictEqual(cpuUses.length, 2, "each pill shape puts the CPU icon over the CPU figure")
assert.strictEqual(memUses.length, 2, "and the RAM icon over the RAM figure")

// The popup's plates match the bar.
const popup = fs.readFileSync(locate("modules/sekai/bar/ResourcePopup.qml"), "utf8")
assert.ok(/label: "CPU"\s*glyph: LG\.cpu\(\)/.test(popup), "the CPU plate has the chip")
assert.ok(/label: "RAM"\s*glyph: LG\.ram\(root\.memPercent\)/.test(popup), "the RAM plate has the pie")
assert.ok(!/clock_loader/.test(popup), "the popup no longer steps its own pie")

console.log("load_glyphs_test: ok")
