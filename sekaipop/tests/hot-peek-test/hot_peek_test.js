// The hot edge's "Peek first" (panel.hotPeek, QuickPanel.qml): the edge raises only the
// tip of the phone, a click on it opens the whole phone, and leaving it lowers it. The
// wiring is checked as text; peekOn / claimPeek / close / alert run against a fake root
// (Quickshell can't run here). Run: node hot_peek_test.js
const fs = require("fs"), assert = require("assert")
const read = f => fs.readFileSync(require("../lib/locate")(f), "utf8")
const src = read("modules/sekai/quickPanel/QuickPanel.qml")

// ----- the setting -----
const settings = read("services/SettingsService.qml")
assert.ok(/"panel\.hotPeek": false,/.test(settings), "off by default")
assert.ok(/property bool hotPeek: SettingsService\.flag\("panel\.hotPeek"\)/.test(src))
const general = read("modules/sekai/settings/SettingsPageGeneral.qml")
assert.ok(/label: "Peek first"[\s\S]{0,300}SettingsService\.toggle\("panel\.hotPeek"\)/.test(general), "a toggle in General > Quick Panel")
const presets = read("services/DesktopPresetService.qml")
assert.ok(/"panel\.hotPeek",/.test(presets), "kept exact, like the other hot edge keys")
assert.ok(/hotPeek: SettingsService\.flag\("panel\.hotPeek"\)/.test(presets), "a preset's phone part carries it")
assert.ok(/typeof p\.hotPeek === "boolean"\)\s+SettingsService\.set\("panel\.hotPeek", p\.hotPeek\)/.test(presets), "and puts it back")

// ----- the wiring -----
assert.ok(/readonly property bool up: open \|\| alertUp \|\| peekUp/.test(src), "a peek shows the phone like the other two")
assert.ok(/readonly property real lowLift: alertMode \? win\.alertLift : \(peekMode \? win\.peekLift : 0\)/.test(src))
for (const use of ["property real rise: root.lowLift", "readonly property real drop: root.lowLift", "+ root.lowLift"])
    assert.ok(src.includes(use), "the low spot is used by " + use)
assert.ok(!/alertMode \? win\.alertLift : 0/.test(src), "nothing reads the alert's spot alone any more")
assert.ok(/readonly property real peekLift: liftShowing\(root\.peekTipY, 0\)/.test(src))
assert.ok(/readonly property real alertLift: liftShowing\(204, root\.alertMargin \* uiScale\)/.test(src), "the alert's spot is unchanged")
assert.ok(/if \(root\.hotPeek\)\s+root\.peekOn\(hot\.modelData\)\s+else\s+root\.openOn\(hot\.modelData\)/.test(src), "the edge peeks only with the setting on")
assert.ok(/onHoveredChanged: \{\s+root\.hotHovering = hovered/.test(src), "the strip's hover holds the peek")
assert.ok(/TapHandler \{\s+enabled: root\.peekUp && !root\.open\s+onTapped: root\.claimPeek\(\)/.test(src), "a click on the strip opens it too")
const touch = src.slice(src.indexOf("id: peekTouch"), src.indexOf("onPressed: root.claimPeek()") + 30)
assert.ok(touch.length > 30 && /z: 1000/.test(touch) && /enabled: root\.peekUp && !root\.open/.test(touch) && /hoverEnabled: true/.test(touch),
          "the tip takes every press over the face under it, only while peeking")
assert.ok(/running: root\.peekUp && !root\.open && !root\.hotHovering && !peekTouch\.containsMouse\s+onTriggered: root\.peekUp = false/.test(src),
          "it drops once the mouse is off the tip and the strip")
assert.ok(/onOpenChanged: \{[\s\S]{0,600}peekUp = false\s+peekMode = false/.test(src), "opening ends the peek")
assert.ok(/root\.alertMode = false\s+root\.peekMode = false/.test(src), "out of sight forgets the low spot")
// It takes neither the keyboard nor the click-away grab (both follow `open`, not `up`).
assert.ok(/readonly property bool grabWanted: \(open \|\| settingsOpen\)/.test(src))

// ----- the state, against a fake root -----
const fn = name => {
    const i = src.indexOf("    function " + name + "(")
    assert.ok(i > 0, name)
    return src.slice(i, src.indexOf("\n    }\n", i) + 6)
}
function makeRoot() {
    const r = { open: false, alertUp: false, peekUp: false, alertMode: false, peekMode: false,
                settingsOpen: false, targetScreen: "A", rings: 0, turningBack: false,
                buzzRiseMs: 700, buzzTimer: { restart() {} }, closed: 0 }
    Object.defineProperty(r, "up", { get() { return this.open || this.alertUp || this.peekUp } })
    r.stopRing = () => r.rings++
    r.focusedScreen = () => "F"
    r.closeSettings = () => r.closed++
    for (const name of ["peekOn", "claimPeek", "close", "alert"]) {
        const body = fn(name).replace(/^\s*function \w+\(([^)]*)\)/, "function ($1)")
        r[name] = new Function("r", "buzzTimer", "with (r) { return (" + body + ") }")(r, r.buzzTimer)
    }
    return r
}

let r = makeRoot()
r.peekOn("B")
assert.ok(r.peekUp && r.peekMode && !r.open && r.targetScreen === "B", "peeks on the edge's monitor, without opening")
r.claimPeek()
assert.ok(r.open, "a click opens it")
r = makeRoot()
r.open = true
r.peekOn("B")
assert.ok(!r.peekUp && r.targetScreen === "A", "an open phone is left alone")
r = makeRoot()
r.settingsOpen = true
r.peekOn("B")
assert.ok(!r.peekUp, "standalone Settings are left alone")
r = makeRoot()
r.claimPeek()
assert.ok(!r.open, "nothing to claim without a peek")
r = makeRoot()
r.peekOn("B")
r.close()
assert.ok(!r.peekUp && !r.up, "close lowers a peek")
r = makeRoot()
r.peekOn("B")
const seen = []
Object.defineProperty(r, "peekUp", { get() { return this._p }, set(v) { this._p = v; seen.push(this.up) } })
r._p = true
r.alert()
assert.ok(r.alertUp && r.alertMode && !r.peekUp && !r.peekMode, "a notification turns the peek into the alert phone")
assert.ok(seen.every(Boolean), "and the phone never drops on the way")
console.log("hot_peek_test: all checks passed")
