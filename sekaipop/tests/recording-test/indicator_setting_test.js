// node tests/recording-test/indicator_setting_test.js
//
// The red REC pill (RecordingIndicator.qml) follows Settings > General > Screen region >
// Recording indicator, `region.recIndicator`: "all" shows it for any recorder, "own" only
// for the shell's own, "off" never (issue #166; docs/RECORDING-INDICATOR.md). This is a
// source check (nothing here runs QML).
const assert = require("assert")
const fs = require("fs")
const locate = require("../lib/locate")
const read = f => fs.readFileSync(locate(f), "utf8")

const ind = read("modules/sekai/onScreenDisplay/RecordingIndicator.qml")
const settings = read("services/SettingsService.qml")
const page = read("modules/sekai/settings/SettingsPageGeneral.qml")

// The default keeps what everyone has today.
assert.ok(/"region\.recIndicator":\s*"all"/.test(settings), "the setting defaults to all")

// The pill is up only for a recording the mode shows.
assert.ok(/readonly property string mode: SettingsService\.get\("region\.recIndicator"\) \|\| "all"/.test(ind), "the pill reads the setting")
assert.ok(/readonly property bool watchOthers: root\.mode === "all"/.test(ind), "only all looks at other recorders")
assert.ok(/readonly property bool recording: root\.mode !== "off"\s*&& \(RegionService\.recording \|\| \(root\.watchOthers && root\.external\)\)/.test(ind),
          "off never shows it; own shows only the shell's recorder")

// Other recorders are not even looked for outside "all" (no pgrep every 2 s), and what
// was found is forgotten when the poll stops.
const poll = ind.slice(ind.indexOf("property Timer pollTimer"), ind.indexOf("property Timer clock"))
assert.ok(/running: root\.watchOthers/.test(poll), "the pgrep poll runs only in all")
assert.ok(/onRunningChanged: if \(!running\) root\.external = false/.test(poll), "stopping it forgets the last answer")

// Clicking the pill stops only what it shows: with "own", a replay buffer is left alone.
const stop = ind.slice(ind.indexOf("function stop()"), ind.indexOf("model: Quickshell.screens"))
assert.ok(/if \(root\.watchOthers && root\.external\)\s*(\/\/[^\n]*\n\s*)*Quickshell\.execDetached\(\["pkill"/.test(stop)
          || /if \(root\.watchOthers && root\.external\)\s*Quickshell\.execDetached\(\["pkill"/.test(stop),
          "pkill only when other recorders are being shown")
assert.ok(!/if \(root\.external\)\s*Quickshell/.test(stop), "never on external alone")

// Settings has the three choices.
const choice = page.slice(page.indexOf('label: "Recording indicator"'))
assert.ok(page.indexOf('label: "Recording indicator"') > 0, "Settings > General has the row")
for (const id of ["all", "own", "off"])
    assert.ok(new RegExp('\\{ id: "' + id + '"').test(choice.slice(0, 600)), "with the " + id + " choice")
assert.ok(/onPicked: id => SettingsService\.set\("region\.recIndicator", id\)/.test(choice), "and it sets region.recIndicator")

console.log("indicator_setting_test: ok")
