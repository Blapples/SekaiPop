// node tests/clip-pins-test/clip_pins_test.js   (run from the sekaipop folder)
// The clipboard's pins: ClipPins.js (reading the list, pins first, no doubles) and
// scripts/state/clip-pins.sh against a stand-in cliphist and wl-copy, in a
// throwaway state dir that is removed at the end.
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")
const locate = require("../lib/locate.js")

let fails = 0
function eq(a, b, msg) {
    const x = JSON.stringify(a), y = JSON.stringify(b)
    if (x !== y) { fails++; console.log("FAIL " + msg + "\n   got  " + x + "\n   want " + y) }
}

// ===== ClipPins.js =====
const src = fs.readFileSync(locate("modules/common/functions/ClipPins.js"), "utf8").replace(".pragma library", "")
const P = new Function(src + "; return { parsePinList, merge, isImagePreview }")()

const pins = P.parsePinList("1700000000002\thello world\n1700000000001\t[[ binary data 12 KiB png 10x10 ]]\nbad\tline\n\n")
eq(pins.map(p => p.id), ["p1700000000002", "p1700000000001"], "pin ids are p + the name on disk; junk lines are skipped")
eq(pins.map(p => [p.pinned, p.image]), [[true, false], [true, true]], "pins say they are pinned, and pictures are pictures")

const history = [
    { id: "9", preview: "new copy", image: false },
    { id: "8", preview: "hello world", image: false },
    { id: "7", preview: "[[ binary data 12 KiB png 10x10 ]]", image: true },
]
eq(P.merge(pins, history).map(e => e.id), ["p1700000000002", "p1700000000001", "9"],
   "pins first, and the history's copies of them are not listed twice")
eq(P.merge([], history).map(e => e.id), ["9", "8", "7"], "no pins: the history as it was")

// ===== clip-pins.sh =====
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sekaipop-clip-pins-"))
try {
    const bin = path.join(tmp, "bin")
    fs.mkdirSync(bin)
    // cliphist decode <id> prints "entry <id>"; wl-copy records what it was given.
    fs.writeFileSync(path.join(bin, "cliphist"), '#!/bin/sh\n[ "$1" = decode ] && printf "entry %s\\nsecond line" "$2"\n', { mode: 0o755 })
    fs.writeFileSync(path.join(bin, "wl-copy"), '#!/bin/sh\ncat > "$XDG_STATE_HOME/copied"\n', { mode: 0o755 })
    const env = Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH, XDG_STATE_HOME: tmp, XDG_RUNTIME_DIR: tmp })
    const run = (...a) => execFileSync("sh", [locate("scripts/state/clip-pins.sh"), ...a], { env, encoding: "utf8" })

    eq(run("list"), "", "no pins yet: an empty list")
    const a = run("pin", "41", "first\tpreview").trim()
    const b = run("pin", "42", "second").trim()
    eq(run("list"), `${b}\tsecond\n${a}\tfirst preview\n`, "newest pin first; a tab in the preview cannot break the line")
    eq(run("show", a), `p${a}\nentry 41\nsecond line`, "show gives the pin's id line, then the whole text")
    run("copy", a)
    eq(fs.readFileSync(path.join(tmp, "copied"), "utf8"), "entry 41\nsecond line", "copy puts the exact bytes back")
    run("unpin", a)
    eq(run("list"), `${b}\tsecond\n`, "unpin forgets it")
    let refused = false
    try { run("show", "../../etc/passwd") } catch (e) { refused = true }
    eq(refused, true, "a pin name that is not digits is refused")
    let noPin = false
    try { run("pin", "x1", "nope") } catch (e) { noPin = true }
    eq(noPin, true, "a cliphist id that is not digits is refused")
} finally {
    fs.rmSync(tmp, { recursive: true, force: true })
}

if (fails) {
    console.log(fails + " failed")
    process.exit(1)
}
console.log("clip pins: ok")
