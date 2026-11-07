// node tests/sensors-test/sensors_unit.js   (run from the sekaipop folder)
//
// The temperatures and disks in the CPU & RAM card (services/SensorsService.qml,
// scripts/system/sensors.sh, modules/sekai/bar/ResourcePopup.qml). Its numbers are in
// modules/common/functions/SensorsMath.js, which this runs on its own.
//   1. what the script prints -> numbers
//   2. the words and bars
//   3. the script runs, and prints only what it understands
//   4. the QML is wired to it
const fs = require("fs"), assert = require("assert"), cp = require("child_process")
const locate = require("../lib/locate")
const qmlcheck = require("../lib/qmlcheck")
const read = f => fs.readFileSync(locate(f), "utf8")
const src = read("modules/common/functions/SensorsMath.js").replace(".pragma library", "")
const S = {}
new Function("S", src + ";Object.assign(S,{parse,groupDisks,temp,tempText,tempWord,tempFrac,tempHot,bytesText,diskName,diskFrac,diskText,diskFull});")(S)
let n = 0
const ok = (c, m) => { assert(c, m); n++ }
const eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++ }

// ---- 1. parsing ----
let r = S.parse("cpu=62\ngpu=55\ndisk=/|112000000000|476000000000|/dev/nvme0n1p2\ndisk=/mnt/games|1000|4000|/dev/sda1\nhome=/\n")
eq(r.cpuTemp, 62); eq(r.gpuTemp, 55)
eq(r.disks, [{ name: "System / Home", mount: "/", mounts: ["/"], used: 112000000000, total: 476000000000 },
             { name: "Games", mount: "/mnt/games", mounts: ["/mnt/games"], used: 1000, total: 4000 }],
   "a home that is just a folder of / makes the one disk read System / Home; another mounted disk is its own row")
r = S.parse("disk=/|5|10\n")
eq([r.cpuTemp, r.gpuTemp], [null, null], "a sensor the script could not read is null, not 0")
r = S.parse("cpu=abc\ngpu=\ncpu=400\n")
eq([r.cpuTemp, r.gpuTemp], [null, null], "garbage and absurd temperatures are no temperature")
eq(S.parse("cpu=-4").cpuTemp, null, "below zero is a broken sensor")
eq(S.parse("cpu=0").cpuTemp, 0, "0 is a temperature")
eq(S.parse("cpu=62.7").cpuTemp, 63, "rounded")
eq(S.parse("disk=/|abc|10\ndisk=|5|10\ndisk=/x|5\ndisk=/y|5|0\ndisk=/z|-1|10").disks, [], "a bad disk line is skipped")
eq(S.parse("disk=/|20|10").disks.map(d => [d.name, d.used, d.total]), [["System", 10, 10]], "used is never more than the total, and a line with no device still works")

// ---- disks that are one disk ----
const d = (mount, device, used = 100, total = 1000) => ({ mount, device, used, total })
eq(S.groupDisks([d("/", "/dev/a"), d("/home", "/dev/a")], "/home").map(x => x.name), ["System / Home"], "root and /home on one device: one row")
eq(S.groupDisks([d("/", "/dev/a"), d("/home", "/dev/b")], "/home").map(x => x.name), ["System", "Home"], "on two devices: two rows")
eq(S.groupDisks([d("/", "/dev/a")], "/").map(x => x.name), ["System / Home"], "home is a folder of /: System / Home")
eq(S.groupDisks([d("/", "/dev/a")], "").map(x => x.name), ["System"], "no home line, no Home")
eq(S.groupDisks([d("/", "/dev/a"), d("/home", "/dev/a")], "/").map(x => x.name), ["System / Home"], "Home is not named twice")
eq(S.groupDisks([d("/home", "/dev/a"), d("/", "/dev/a")], "/home").map(x => x.name), ["System / Home"], "the order given does not matter")
eq(S.groupDisks([d("/mnt/games", "/dev/b"), d("/", "/dev/a")], "/").map(x => x.name), ["System / Home", "Games"], "the root's disk is first")
eq(S.groupDisks([d("/", "/dev/a"), d("/mnt/x/steam", "/dev/b"), d("/mnt/x", "/dev/b")], "/").map(x => x.name), ["System / Home", "X / Steam"], "a disk's mounts: shortest first, two at most")
eq(S.groupDisks([d("/", "/dev/a"), d("/a", "/dev/a"), d("/b", "/dev/a"), d("/c", "/dev/a")], "").map(x => x.name), ["System / A"], "never more than two names")
eq(S.groupDisks([d("/", "/dev/a"), d("/mnt/usb", "")], "").map(x => x.name), ["System", "Usb"], "no device: grouped by mount point")
eq(S.groupDisks([d("/", "/dev/a", 7, 70), d("/home", "/dev/a", 7, 70)], "").map(x => [x.used, x.total]), [[7, 70]], "one filesystem: its numbers once, not added up")
const many = []
for (let i = 0; i < 12; i++) many.push(d("/mnt/d" + i, "/dev/x" + i))
eq(S.groupDisks(many, "").length, 6, "at most six disks")
eq(S.groupDisks([], "/"), [])
eq(S.parse("").disks, []); eq(S.parse(null).cpuTemp, null)

// ---- 2. words and bars ----
eq([S.tempText(62), S.tempText(null), S.tempText(undefined)], ["62°C", "--", "--"])
eq([S.tempWord(40), S.tempWord(59), S.tempWord(60), S.tempWord(79), S.tempWord(80), S.tempWord(null)], ["COOL", "COOL", "WARM", "WARM", "HOT", ""])
eq([S.tempFrac(50), S.tempFrac(120), S.tempFrac(null)], [0.5, 1, 0])
eq([S.tempHot(79), S.tempHot(80), S.tempHot(null)], [false, true, false])
eq([S.bytesText(112e9), S.bytesText(476e9), S.bytesText(2 * 1024 ** 4), S.bytesText(640 * 1024 ** 2), S.bytesText(5 * 1024 ** 3)], ["104 GB", "443 GB", "2.0 TB", "640 MB", "5 GB"])
eq(S.bytesText(-1), "0 MB"); eq(S.bytesText("x"), "0 MB")
eq([S.diskName("/"), S.diskName("/home"), S.diskName("/mnt/games"), S.diskName("")], ["System", "Home", "Games", ""])
eq([S.diskFrac({ used: 1, total: 4 }), S.diskFrac({ used: 1, total: 0 }), S.diskFrac(null)], [0.25, 0, 0])
eq(S.diskText({ used: 100 * 1024 ** 3, total: 500 * 1024 ** 3 }), "400 GB free of 500 GB")
eq([S.diskFull({ used: 89, total: 100 }), S.diskFull({ used: 90, total: 100 })], [false, true])

// ---- 3. the script ----
const script = locate("scripts/system/sensors.sh")
ok((fs.statSync(script).mode & 0o111) !== 0, "the script is executable")
const out = cp.execFileSync("sh", [script], { encoding: "utf8" })
const sh = read("scripts/system/sensors.sh")
ok(/timeout 3/.test(sh), "df is given three seconds: a hung mount can't hang the reading")
ok(/\^\\\/dev\\\//.test(sh) || sh.includes("/dev/"), "only devices under /dev are listed (never a network mount)")
for (const line of out.split("\n").filter(Boolean))
    ok(/^(cpu=\d+|gpu=\d+|disk=[^|]+\|\d+\|\d+\|[^|]+|home=.+)$/.test(line), "every line it prints is one the card understands: " + line)
ok(/^disk=\//m.test(out), "the disk holding / is always there")
ok(/^home=/m.test(out), "and which mount $HOME is on")
const parsed = S.parse(out)
ok(parsed.disks.length >= 1 && parsed.disks[0].mounts.includes("/"), "the root's disk comes first")
ok(/^System/.test(parsed.disks[0].name), "named System")
ok(!/nvidia-smi/.test(read("scripts/system/sensors.sh").replace(/^#.*$/gm, "")), "it never runs nvidia-smi (that wakes a sleeping GPU)")

// ---- 4. the QML is wired to it ----
const svc = read("services/SensorsService.qml")
ok(/pragma Singleton/.test(svc) && svc.includes('"system/sensors.sh"'), "a singleton running the script")
ok(svc.includes('SettingsService.flag("bar.resources")') && /running: root\.enabled/.test(svc), "it reads only while the CPU & RAM pill is on")
ok(/if \(!reader\.running\)/.test(svc), "a slow read is not started twice")
const pop = read("modules/sekai/bar/ResourcePopup.qml")
ok(pop.includes("SensorsService.cpuTemp") && pop.includes("SensorsService.gpuTemp") && pop.includes("SensorsService.disks"), "the card shows temperatures and disks")
ok(pop.includes("label: modelData.name"), "each disk row carries its own name (System / Home, Games, ...)")
ok(/visible: SensorsService\.cpuTemp !== null/.test(pop) && /visible: SensorsService\.gpuTemp !== null/.test(pop), "a row the machine can't read is not there")
const ri = read("modules/sekai/bar/ResourceIndicator.qml")
ok(ri.includes("property string tempText") && /root\.tempText !== ""/.test(ri), "the hover tag gets the CPU temperature")
ok(/Layout\.preferredWidth: root\.figuresWidth/.test(ri), "the CPU & RAM figures sit in fixed boxes, so the pill keeps its width")
ok(read("modules/sekai/bar/Status_Bar.qml").includes("tempText: status_Bar.cpuTempText") && read("modules/sekai/bar/Bar.qml").includes("cpuTempText: SensorsService.cpuTempText"), "the temperature reaches the pill")
for (const f of ["services/SensorsService.qml", "modules/sekai/bar/StatBar.qml", "modules/sekai/bar/ResourcePopup.qml", "modules/sekai/bar/ResourceIndicator.qml"])
    eq(qmlcheck(read(f), f), [], f + " has no duplicate ids / members and balanced braces")

console.log("sensors_unit: all " + n + " checks passed")
