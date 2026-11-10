// Runs the avatar / banner / phone picture parts of services/DesktopPresetService.qml
// on their own: the functions are cut out of the .qml text and run against fakes.
const fs = require("fs")
const assert = require("assert")
const src = fs.readFileSync(process.argv[2] || require("path").join(__dirname, "..", "..", "services", "DesktopPresetService.qml"), "utf8")

function grab(name) {
    const start = src.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    const end = src.indexOf("\n    }\n", start)
    return src.slice(start, end + 7).replace(/^    function /, "function ")
}

const calls = { clear: [], exec: [], assign: [] }
// Framing (docs/PICTURE-FRAMING.md): every picture here is centred unless a test frames it.
const framed = {}
const FR = { isCentred: f => !f || (f.zoom === 1 && f.panX === 0 && f.panY === 0) }
const PanelImages = {
    loaded: true, avatarPath: "", bannerPath: "", phonePath: "",
    clear(k) { calls.clear.push(k); this[k + "Path"] = "" },
    assign(k, p) { calls.assign.push([k, p]) },
    pathOf(k) { return k === "avatar" || k === "banner" || k === "phone" ? this[k + "Path"] : "" },
    framingFor(k) { return framed[k] || { zoom: 1, panX: 0, panY: 0 } },
    setFraming(k, f) { calls.framing = (calls.framing || []).concat([[k, f]]) }
}
const imager = { exec(a) { calls.exec.push(a) } }
const root = { script: "/s/preset-state.sh", pendingFraming: {} }
const TodoService = { size: "full" }
for (const n of ["baseName", "imageEntry", "stable", "digestOf", "isCurrent", "wearImages", "variantKey", "digestsOf", "wornPictures"])
    root[n] = eval("(" + grab(n) + ")")
// the functions call root.x(...), so bind them to our fake root
for (const n of Object.keys(root)) if (typeof root[n] === "function") { const f = root[n]; root[n] = f }
let dockItems = [{ type: "app", class: "firefox", iconName: "firefox" }]
// capture()'s `images` part, cut out of the service like the functions above, so the
// test follows what it really saves.
const capSrc = src.slice(src.indexOf("        if (PanelImages.loaded) {"), src.indexOf("        // Not before the saved pictures have been read back"))
assert.ok(capSrc.includes("out.images"), "capture()'s images block not found")
const imagesPart = eval("(() => { const out = {};\n" + capSrc + "\nreturn out.images })")
const capture = () => ({ theme: { g: "x" }, dock: { items: dockItems }, images: imagesPart() })
const reset = () => { calls.clear = []; calls.exec = []; calls.assign = [] }

// --- imageEntry ---
assert.deepStrictEqual(root.imageEntry("avatar", ""), null)
assert.deepStrictEqual(root.imageEntry("avatar", "/h/.local/share/sekaipop/avatar-170.PNG"),
    { file: "avatar.png", from: "avatar-170.PNG" })          // ext lower-cased, like the script
assert.deepStrictEqual(root.imageEntry("banner", "/x/banner-9"), { file: "banner", from: "banner-9" })

// --- wearImages ---
// older preset (no images part): nothing at all happens
PanelImages.avatarPath = "/d/avatar-1.png"; reset()
root.wearImages("Old", undefined); root.wearImages("Old", null)
assert.deepStrictEqual([calls.clear, calls.exec], [[], []])

// saved with none: the worn ones go back to default, only if something is worn
PanelImages.avatarPath = "/d/avatar-1.png"; PanelImages.bannerPath = ""; reset()
root.wearImages("P", { avatar: null, banner: null })
assert.deepStrictEqual(calls.clear, ["avatar"])             // banner wasn't worn: no pointless rm
assert.strictEqual(calls.exec.length, 0)

// both worn, both to be cleared: two clears in a row (PanelImages queues them)
PanelImages.avatarPath = "/d/avatar-1.png"; PanelImages.bannerPath = "/d/banner-2.png"; reset()
root.wearImages("P", { avatar: null, banner: null })
assert.deepStrictEqual(calls.clear, ["avatar", "banner"])

// different pictures: one restore call carrying both, name + file + old name
PanelImages.avatarPath = "/d/avatar-1.png"; PanelImages.bannerPath = "/d/banner-2.png"; reset()
root.wearImages("Miku look", {
    avatar: { file: "avatar.png", from: "avatar-100.png" },
    banner: { file: "banner.jpg", from: "banner-200.jpg" } })
assert.deepStrictEqual(calls.exec, [["sh", "/s/preset-state.sh", "restore", "Miku look",
    "avatar", "avatar.png", "avatar-100.png", "banner", "banner.jpg", "banner-200.jpg"]])

// the one already worn is not copied again; the other still is
PanelImages.avatarPath = "/d/avatar-100.png"; reset()
root.wearImages("Miku look", {
    avatar: { file: "avatar.png", from: "avatar-100.png" },
    banner: { file: "banner.jpg", from: "banner-200.jpg" } })
assert.deepStrictEqual(calls.exec[0].slice(4), ["banner", "banner.jpg", "banner-200.jpg"])

// everything already worn: no process at all
PanelImages.avatarPath = "/d/avatar-100.png"; PanelImages.bannerPath = "/d/banner-200.jpg"; reset()
root.wearImages("Miku look", {
    avatar: { file: "avatar.png", from: "avatar-100.png" },
    banner: { file: "banner.jpg", from: "banner-200.jpg" } })
assert.strictEqual(calls.exec.length, 0)

// a half-saved preset (only avatar mentioned) leaves the banner alone
PanelImages.avatarPath = ""; PanelImages.bannerPath = "/d/banner-2.png"; reset()
root.wearImages("P", { avatar: { file: "avatar.png", from: "avatar-5.png" } })
assert.deepStrictEqual(calls.exec[0].slice(4), ["avatar", "avatar.png", "avatar-5.png"])
assert.deepStrictEqual(calls.clear, [])

// junk in the file is ignored, not thrown on
reset(); PanelImages.avatarPath = ""; PanelImages.bannerPath = ""
root.wearImages("P", { avatar: "nope", banner: { file: 5 } })
assert.deepStrictEqual([calls.clear, calls.exec], [[], []])

// --- the tick (isCurrent) ---
// refreshLive() without capture(): the service's own digestsOf() on our capture
const mk = () => { root.liveDigests = root.digestsOf(capture()) }
PanelImages.avatarPath = "/d/avatar-100.png"; PanelImages.bannerPath = ""
mk()
const saved = JSON.parse(JSON.stringify(capture()))
assert.strictEqual(root.isCurrent(saved), true)             // just saved = current
PanelImages.avatarPath = "/d/avatar-777.png"; mk()
assert.strictEqual(root.isCurrent(saved), false)            // picked another avatar: tick goes
PanelImages.avatarPath = "/d/avatar-100.png"; mk()
assert.strictEqual(root.isCurrent(saved), true)             // wearing it again (restore keeps the name): tick back
// a preset from before this feature has no images, and its tick must survive
const legacy = { theme: { g: "x" } }
assert.strictEqual(root.isCurrent(legacy), true)
PanelImages.avatarPath = "/d/avatar-555.png"; mk()
assert.strictEqual(root.isCurrent(legacy), true)            // whatever avatar is worn, it never mattered to it

// the dock is part of a preset: pinning another app takes the tick away from a
// preset that holds a dock, but not from one saved before docks were in presets
PanelImages.avatarPath = "/d/avatar-100.png"; mk()
const withDock = JSON.parse(JSON.stringify(capture()))
const beforeDock = JSON.parse(JSON.stringify(capture())); delete beforeDock.dock
assert.strictEqual(root.isCurrent(withDock), true)
assert.strictEqual(root.isCurrent(beforeDock), true)
dockItems = dockItems.concat([{ type: "app", class: "kitty", iconName: "kitty" }]); mk()
assert.strictEqual(root.isCurrent(withDock), false)         // dock changed: tick goes
assert.strictEqual(root.isCurrent(beforeDock), true)        // it never held a dock: tick stays
dockItems = withDock.dock.items; mk()
assert.strictEqual(root.isCurrent(withDock), true)          // back to the same dock: tick back

// --- the phone's own picture (issue #147) ---
PanelImages.avatarPath = "/d/avatar-100.png"; PanelImages.bannerPath = ""; PanelImages.phonePath = ""
assert.strictEqual("phone" in imagesPart(), false)          // none picked: no entry, so wearing it leaves yours alone
PanelImages.phonePath = "/d/phone-300.JPG"
assert.deepStrictEqual(imagesPart().phone, { file: "phone.jpg", from: "phone-300.JPG" })
framed.phone = { zoom: 1.5, panX: 0.2, panY: -0.1 }
assert.deepStrictEqual(imagesPart().phone.framing, { zoom: 1.5, panX: 0.2, panY: -0.1 })   // its framing comes along
delete framed.phone

// what save hands the script: avatar, banner, phone ("-" for none)
assert.deepStrictEqual(root.wornPictures(capture()), ["/d/avatar-100.png", "-", "/d/phone-300.JPG"])
PanelImages.phonePath = ""
assert.deepStrictEqual(root.wornPictures(capture()), ["/d/avatar-100.png", "-", "-"])
assert.deepStrictEqual(root.wornPictures({ theme: {} }), ["-", "-", "-"])   // nothing loaded yet: no images part

// wearing: a preset with a phone picture puts it back...
PanelImages.avatarPath = "/d/avatar-100.png"; PanelImages.bannerPath = ""; PanelImages.phonePath = "/d/phone-1.png"; reset()
root.wearImages("Phone look", { avatar: { file: "avatar.png", from: "avatar-100.png" }, banner: null,
    phone: { file: "phone.jpg", from: "phone-300.jpg", framing: { zoom: 2, panX: 0, panY: 0 } } })
assert.deepStrictEqual(calls.exec, [["sh", "/s/preset-state.sh", "restore", "Phone look", "phone", "phone.jpg", "phone-300.jpg"]])
assert.deepStrictEqual(root.pendingFraming.phone, { zoom: 2, panX: 0, panY: 0 })   // framed once its copy is in place
assert.deepStrictEqual(calls.clear, [])
// ...not again when it is already the one worn (only its framing)
PanelImages.phonePath = "/d/phone-300.jpg"; reset(); calls.framing = []
root.wearImages("Phone look", { phone: { file: "phone.jpg", from: "phone-300.jpg" } })
assert.deepStrictEqual([calls.exec, calls.framing], [[], [["phone", null]]])
// ...and a preset without one (saved with none, or before #147) leaves yours where it is
reset()
root.wearImages("Plain", { avatar: null, banner: null })
assert.deepStrictEqual(calls.clear, ["avatar"])
assert.strictEqual(PanelImages.phonePath, "/d/phone-300.jpg")
assert.strictEqual(calls.exec.length, 0)

// the tick: the phone picture is part of a preset that holds one
PanelImages.avatarPath = "/d/avatar-100.png"; PanelImages.phonePath = "/d/phone-300.jpg"; mk()
const withPhone = JSON.parse(JSON.stringify(capture()))
const noPhonePic = JSON.parse(JSON.stringify(capture())); delete noPhonePic.images.phone
assert.strictEqual(root.isCurrent(withPhone), true)
assert.strictEqual(root.isCurrent(noPhonePic), true)        // saved with none: whatever picture you have never mattered
PanelImages.phonePath = "/d/phone-999.jpg"; mk()
assert.strictEqual(root.isCurrent(withPhone), false)        // picked another: tick goes
assert.strictEqual(root.isCurrent(noPhonePic), true)
PanelImages.phonePath = ""; mk()
assert.strictEqual(root.isCurrent(withPhone), false)        // cleared it: tick goes
assert.strictEqual(root.isCurrent(noPhonePic), true)
PanelImages.phonePath = "/d/phone-300.jpg"; mk()
assert.strictEqual(root.isCurrent(withPhone), true)         // back: tick back
// the avatar still counts in a preset without a phone picture
PanelImages.avatarPath = "/d/avatar-1.png"; mk()
assert.strictEqual(root.isCurrent(noPhonePic), false)
// every variant exists, and "no phone picture" only beside an images part
const keys = Object.keys(root.liveDigests)
assert.strictEqual(keys.length, 96)
assert.ok(keys.every(k => !(k[0] === "i" && k[6] === "q")))
assert.strictEqual(root.variantKey(true, false, false, false, false, false, true), root.variantKey(true, false, false, false, false, false, false))

console.log("preset_images_unit: all checks passed")

// preset-state.sh for real, in a temp folder: the phone picture is copied in beside the
// avatar and banner, the frame pictures still come after it, and restore puts it back.
{
    const os = require("os"), path = require("path"), { spawnSync } = require("child_process")
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "presets-phone-"))
    try {
        const data = path.join(tmp, "data", "sekaipop")
        const env = Object.assign({}, process.env, { XDG_CONFIG_HOME: path.join(tmp, "config"), XDG_STATE_HOME: path.join(tmp, "state"), XDG_DATA_HOME: path.join(tmp, "data") })
        const dir = path.join(tmp, "config", "sekaipop", "presets")
        const sh = (...a) => spawnSync("sh", [path.join(__dirname, "..", "..", "scripts", "state", "preset-state.sh"), ...a], { env, encoding: "utf8" })
        fs.mkdirSync(path.join(data, "custom-images"), { recursive: true })
        const put = (f, body) => { fs.writeFileSync(f, body); return f }
        const avatar = put(path.join(data, "avatar-1.png"), "A")
        const phone = put(path.join(data, "phone-300.JPG"), "P")
        const frame = put(path.join(data, "custom-images", "img-9-1.png"), "F")
        const json = JSON.stringify({ _meta: { name: "Look", v: 1 } })

        assert.strictEqual(sh("save", "Look", json, avatar, "-", phone, frame).status, 0)
        assert.deepStrictEqual(fs.readdirSync(path.join(dir, "Look.images")).sort(), ["avatar.png", "phone.jpg"])
        assert.strictEqual(fs.readFileSync(path.join(dir, "Look.images", "phone.jpg"), "utf8"), "P")
        assert.deepStrictEqual(fs.readdirSync(path.join(dir, "Look.frames")), ["img-9-1.png"], "frames come after the phone argument")
        // a save without one (or an older caller's three paths' worth of "-") keeps no phone copy
        assert.strictEqual(sh("save", "Plain", json, avatar, "-", "-").status, 0)
        assert.deepStrictEqual(fs.readdirSync(path.join(dir, "Plain.images")), ["avatar.png"])
        assert.strictEqual(fs.existsSync(path.join(dir, "Plain.frames")), false)

        // another phone picture picked since; wearing Look brings its own back, under its old name
        fs.unlinkSync(phone); put(path.join(data, "phone-500.png"), "Q")
        const r = sh("restore", "Look", "phone", "phone.jpg", "phone-300.jpg")
        assert.strictEqual(r.status, 0)
        assert.strictEqual(r.stdout, "phone " + path.join(data, "phone-300.jpg") + "\n")
        assert.strictEqual(fs.readFileSync(path.join(data, "phone-300.jpg"), "utf8"), "P")
        assert.strictEqual(fs.existsSync(path.join(data, "phone-500.png")), false, "the one it replaces goes, like a fresh pick")
        assert.ok(fs.existsSync(avatar), "the avatar is not touched")
        // unknown kinds are still refused
        assert.strictEqual(sh("restore", "Look", "wallpaper", "phone.jpg", "x").stdout, "")
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true })
    }
    console.log("preset_images_unit: script checks passed")
}

// DesktopPresetService lives in services/ but PanelImages.qml sits in the
// config root, a different QML module. Without `import qs` the name is
// undefined at run time: capture() throws and nothing is saved. (Quickshell
// can't be run here, so this reads the source.)
{
    const fs = require("fs"), path = require("path")
    const svc = fs.readFileSync(path.join(__dirname, "..", "..", "services", "DesktopPresetService.qml"), "utf8")
    const head = svc.split("\n").filter(l => /^import /.test(l))
    assert.ok(head.includes("import qs.modules.common"),
        "DesktopPresetService.qml uses PanelImages (modules/common) and needs `import qs.modules.common`")
    console.log("preset_images_unit: import check passed")
}
