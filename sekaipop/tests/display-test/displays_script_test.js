// scripts/hyprland/displays.sh apply, run for real against a fake `hyprctl` that writes
// down every Lua string it is handed. Issue #109: a screen turned off in a session could
// not be turned back on (nor brought back by the countdown's revert), because the rule
// that turns it on did not say `disabled = false` and Hyprland kept the earlier `disabled`.
//   node tests/display-test/displays_script_test.js
const fs = require("fs"), os = require("os"), path = require("path"), assert = require("assert")
const { spawnSync } = require("child_process")

const script = path.join(__dirname, "..", "..", "scripts", "hyprland", "displays.sh")
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "displays-"))
try {
    const bin = path.join(tmp, "bin"), log = path.join(tmp, "calls")
    fs.mkdirSync(bin)
    // `hyprctl eval <lua>`: one line per call.
    fs.writeFileSync(path.join(bin, "hyprctl"), '#!/bin/sh\n[ "$1" = eval ] && printf \'%s\\n\' "$2" >> "' + log + '"\nexit 0\n', { mode: 0o755 })
    const run = (...specs) => {
        fs.rmSync(log, { force: true })
        const r = spawnSync("sh", [script, "apply", ...specs], { env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }), encoding: "utf8" })
        assert.strictEqual(r.status, 0, r.stderr)
        return fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n") : []
    }

    // turning a screen on says so outright
    const on = run("DP-3|on|1920x1080@180|0|0|1", "DP-2|on|2560x1080@74.99|1920|0|1.25")
    assert.deepStrictEqual(on, [
        'hl.monitor({ output = "DP-3", mode = "1920x1080@180", position = "0x0", scale = 1, disabled = false })',
        'hl.monitor({ output = "DP-2", mode = "2560x1080@74.99", position = "1920x0", scale = 1.25, disabled = false })'
    ])

    // off: the screens that stay on go first (never none on), then the one going off, parked
    const off = run("DP-2|off|1920|0", "DP-3|on|1920x1080@180|0|0|1")
    assert.deepStrictEqual(off, [
        'hl.monitor({ output = "DP-3", mode = "1920x1080@180", position = "0x0", scale = 1, disabled = false })',
        'hl.monitor({ output = "DP-2", disabled = true })',
        'hl.monitor({ output = "DP-2", disabled = true, position = "1920x0" })'
    ])

    // every "on" rule carries it, whatever else it says
    for (const line of run("A|on|preferred|0|0|1", "B|on|800x600@60.00|-800|0|2"))
        assert.ok(/, disabled = false \}\)$/.test(line), "an on rule without disabled = false: " + line)

    // bad specs are still refused before anything runs
    const bad = spawnSync("sh", [script, "apply", "DP-2|on|preferred|0|0|1); os.exit()"], { env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }), encoding: "utf8" })
    assert.strictEqual(bad.status, 2)

    // the 7th field (hyprmon display handler): more settings, turned into hl.monitor fields
    const more = run("DP-4|on|5120x1440@240.00|0|0|1.33|transform=1,vrr=2,bitdepth=10,cm=hdr,sdrbrightness=1.20,sdrsaturation=0.90",
                     "DP-3|on|1920x1080@60.00|0|0|1|mirror=DP-4", "eDP-1|on|preferred|0|0|1|")
    assert.deepStrictEqual(more, [
        'hl.monitor({ output = "DP-4", mode = "5120x1440@240.00", position = "0x0", scale = 1.33, disabled = false, transform = 1, vrr = 2, bitdepth = 10, cm = "hdr", sdrbrightness = 1.20, sdrsaturation = 0.90 })',
        'hl.monitor({ output = "DP-3", mode = "1920x1080@60.00", position = "0x0", scale = 1, disabled = false, mirror = "DP-4" })',
        'hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1, disabled = false })'
    ])
    // ...and every one of them is checked: nothing runs on a bad one
    for (const extra of ["transform=8", "vrr=3", "bitdepth=12", "cm=neon", "sdrbrightness=1.2.3", "sdrbrightness=.5",
                         "mirror=DP-1\"", "mirror=", "rotate=1", "transform", "cm=hdr); os.exit("]) {
        fs.rmSync(log, { force: true })
        const r = spawnSync("sh", [script, "apply", "DP-2|on|preferred|0|0|1|" + extra], { env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }), encoding: "utf8" })
        assert.strictEqual(r.status, 2, "accepted a bad extra: " + extra)
        assert.ok(!fs.existsSync(log), "ran hyprctl for a bad extra: " + extra)
    }
} finally {
    fs.rmSync(tmp, { recursive: true, force: true })
}
console.log("displays_script_test: all checks passed")
