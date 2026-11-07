// A reader at full width counts as a maximized app for Desktop Focus Mode: the panel claims its
// monitor, FocusService turns the claim into a fullscreen window pinned to that monitor, and
// FocusMath hides the widgets there on whichever workspace is showing. Read as text (Node can't
// load QML) plus the real FocusMath rules.
// Run: node tests/manga-reader-test/focus_claim_unit.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const root = path.join(__dirname, "..", "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")
const svc = read("services/FocusService.qml")
const panel = read("modules/sekai/readers/ReaderPanel.qml")
const check = require("../lib/qmlcheck.js")

for (const [f, t] of [["services/FocusService.qml", svc], ["modules/sekai/readers/ReaderPanel.qml", panel]]) {
    const problems = check(t, f)
    assert.deepStrictEqual(problems, [], problems.join("\n"))
}

// The panel claims only while it is wide, wanted open and not minimized, and always lets go on the way out
assert(/takesDesktop:\s*root\.wide && root\.open && !root\.minimized/.test(panel))
assert(/FocusService\.claim\(root\.focusId, root\.screenName\)/.test(panel))
assert(/Component\.onDestruction:[\s\S]{0,200}FocusService\.release\(root\.focusId\)/.test(panel), "an unloaded reader must give its monitor back")
assert(/onScreenNameChanged:\s*\{\s*FocusService\.release/.test(panel), "moving monitors must release the old one")

// The service turns claims into pinned fullscreen windows, and a claim wakes the recompute
assert(/function claim\(id, screenName\)/.test(svc) && /function release\(id\)/.test(svc))
assert(/pinned:\s*true,\s*\n\s*fullscreen:\s*1/.test(svc), "claims should be pinned fullscreen windows")
assert(/root\.claims = next\s*\n\s*root\.schedule\(\)/.test(svc))

// What FocusMath does with such a window: hides its monitor on any workspace, leaves the others alone
const src = read("modules/common/functions/FocusMath.js").replace(".pragma library", "")
const F = {}
new Function("F", src + ";F.compute=compute;")(F)
const on = { enabled: true, hideTiled: true, hideFloating: false }
const claimWin = mon => ({ address: "claim:reader:left", workspaceId: 0, monitor: mon, floating: false, mapped: true, hidden: false, pinned: true, fullscreen: 1, cls: "", known: true })
for (const ws of [1, 2, 7]) {
    const r = F.compute([claimWin("DP-1")], [{ name: "DP-1", workspaceId: ws, specialId: 0 }, { name: "HDMI-A-1", workspaceId: 9, specialId: 0 }], on)
    assert.strictEqual(r["DP-1"].hidden, true, "claimed monitor should hide on workspace " + ws)
    assert.strictEqual(r["DP-1"].busy, true)
    assert.strictEqual(r["HDMI-A-1"].hidden, false, "the other monitor keeps its widgets")
}
assert.strictEqual(F.compute([], [{ name: "DP-1", workspaceId: 1, specialId: 0 }], on)["DP-1"].hidden, false, "no claim, no hiding")

console.log("reader focus claim: all checks passed")
