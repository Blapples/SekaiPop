// node tests/region-test/frozen_shot_test.js
//
// The region picker takes a picture of its monitor (grim) and shows it frozen, dimmed.
// grim and the picker's window race: when the window is drawn before grim has taken
// the picture, the dim (and the hint) end up in the picture, and every crop of it comes
// out dark (issue #160; docs/REGION-PICKER.md, "The frozen picture"). The window draws
// nothing until grim is done, then shows whether grim worked or not. This is a source
// check (nothing here runs QML).
const assert = require("assert")
const fs = require("fs")
const locate = require("../lib/locate")

const src = fs.readFileSync(locate("modules/sekai/regionSelector/RegionSelector.qml"), "utf8")

// The window's whole content is hidden by opacity until grim is done. Opacity, not
// `visible`: an invisible item loses the keyboard, and Escape must still cancel.
assert.ok(/Binding\s*\{\s*target:\s*win\.contentItem\s*property:\s*"opacity"\s*value:\s*win\.shotTaken \? 1 : 0\s*\}/.test(src),
          "the content's opacity follows shotTaken")
assert.ok(!/target:\s*win\.contentItem\s*property:\s*"visible"/.test(src), "not `visible`, which would drop the keyboard")

// shotTaken turns on when grim exits, whatever its exit code: if grim fails the picker
// still shows (over the live screen), instead of an invisible window holding the keyboard.
const grabber = src.slice(src.indexOf("id: grabber"))
const exited = grabber.slice(grabber.indexOf("onExited:"), grabber.indexOf("}\n        }"))
assert.ok(/win\.shotTaken = true/.test(exited), "grim exiting shows the picker")
assert.ok(!/if \(code === 0\)[^]*win\.shotTaken/.test(exited), "even when grim failed")
assert.ok(/property bool shotTaken: false/.test(src), "and it starts hidden")

// grim is still started as the window is built, not later.
assert.ok(/Component\.onCompleted:\s*\{[^}]*grabber\.exec\(\["sh", RegionService\.script, "capture"/.test(src),
          "the picture is taken as the window opens")

console.log("frozen_shot_test: ok")
