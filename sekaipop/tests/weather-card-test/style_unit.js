// The weather card's two styles (Classic / Minimal), same 2 x 2 footprint. Quickshell can't run
// here, so: the service's functions are cut out of the .qml and run against a fake, and the
// widget / Settings / ipc / Edit Desktop wiring and the minimal face's layout numbers are
// checked as text.
const fs = require("fs"), assert = require("assert")
const read = f => fs.readFileSync(require("../lib/locate")(f), "utf8")
const svc = read("services/WeatherCardService.qml")
const w = read("modules/sekai/desktopWidgets/WeatherCardWidget.qml")
const shell = read("shell.qml")
const settings = read("modules/sekai/settings/SettingsPageDesktop.qml")
const key = read("modules/sekai/editMode/SizeKey.qml")
let n = 0
const ok = (c, m) => { assert(c, m); n++ }

// ---- the service ----
function grab(name) {
    const start = svc.indexOf("    function " + name + "(")
    assert(start >= 0, "no function " + name)
    const end = svc.indexOf("\n    }\n", start)
    return svc.slice(start, end + 7).replace(/^    function /, "function ")
}
function fresh() {
    const root = { loaded: false, shown: true, posX: -1, posY: -1, posScale: 0, screenName: "", style: "classic", saved: 0 }
    Object.defineProperty(root, "minimal", { get() { return root.style === "minimal" } })
    root.persist = () => { root.saved++ }
    root.setStyle = eval("(" + grab("setStyle") + ")")
    root.toggleStyle = eval("(" + grab("toggleStyle") + ")")
    root.snapshot = eval("(" + grab("snapshot") + ")")
    root.restore = eval("(" + grab("restore") + ")")
    return root
}
ok(/property string style: "classic"/.test(svc) && /readonly property bool minimal: root\.style === "minimal"/.test(svc), "service: style (default classic) and minimal")

let r = fresh()
r.setStyle("minimal"); ok(r.style === "minimal" && r.saved === 1, "setStyle(minimal) changes and saves")
r.setStyle("minimal"); ok(r.saved === 1, "the same look again saves nothing")
r.setStyle("fancy"); ok(r.style === "classic" && r.saved === 2, "anything odd is classic")
r.setStyle("minimal"); r.setStyle("full"); ok(r.style === "classic", '"full" (the old name) is classic')
r.toggleStyle(); ok(r.style === "minimal", "toggle: classic -> minimal")
r.toggleStyle(); ok(r.style === "classic", "toggle: minimal -> classic")

r = fresh(); r.setStyle("minimal")
ok(JSON.parse(r.snapshot()).style === "minimal", "snapshot holds the look (so a preset keeps it)")
let b = fresh(); b.restore(r.snapshot()); ok(b.style === "minimal" && b.loaded, "restore puts the look back")
b = fresh(); b.style = "minimal"; b.restore(JSON.stringify({ x: 1, y: 2, shown: true })); ok(b.style === "minimal", "restore() itself leaves the look alone when the text has none (presets fill it in first, from the `before` below)")
b = fresh(); b.restore(JSON.stringify({ style: "weird" })); ok(b.style === "classic", "an unknown style reads as classic")
b = fresh(); b.style = "minimal"; b.restore(JSON.stringify({ style: "full" })); ok(b.style === "classic", 'a save that says "full" reads as classic')
b = fresh(); b.restore("not json"); ok(b.style === "classic" && b.loaded, "an unreadable file: defaults, still loaded")

// ---- old presets wear classic: the registry entry says what the style was before it existed ----
const reg = fs.readFileSync(require("../lib/locate")("services/PresetWidgets.qml"), "utf8")
ok(/id: "weathercard",\s*service: WeatherCardService,\s*before: \{ style: "classic", size: "2x2" \}/.test(reg), "PresetWidgets: weathercard's `before` is classic")
ok(/normalize: part => part\.style === "full"/.test(reg), 'PresetWidgets: a preset that says "full" means classic')
const plan = fs.readFileSync(require("../lib/locate")("services/DesktopPresetService.qml"), "utf8")
ok(/PP\.readPart\(e, wmine\[e\.id\]\)/.test(plan), "the motion plan reads an old preset the same way (through the registry)")
ok(!/wmine\.weathercard\.style/.test(plan), "no weather special case left in the motion plan")

// ---- the widget ----
ok(/readonly property bool minimal: WeatherCardService\.minimal/.test(w), "widget follows WeatherCardService.minimal")
ok(/active: !win\.minimal && !card\.tiny\s+sourceComponent: classicFace/.test(w) && /active: win\.minimal && !card\.tiny\s+sourceComponent: minimalFace/.test(w), "only the look in use is built (a Loader each; neither at 1 x 1)")
ok(/onMinimalChanged: waveAnim\.restart\(\)/.test(w), "switching replays the pop-ins")
ok(/SizeKey \{\s*shown: chrome\.selected[\s\S]*?onToggled: WeatherCardService\.toggleStyle\(\)/.test(w), "Edit Desktop: style key shows while selected and toggles")
ok(/ipc call weathercard style/.test(w), "header documents the ipc call")

// the two faces
const fullStart = w.indexOf("id: classicFace"), miniStart = w.indexOf("id: minimalFace")
ok(fullStart > 0 && miniStart > fullStart, "both faces exist, classic first")
const full = w.slice(fullStart, miniStart), mini = w.slice(miniStart)
const ids = t => new Set([...t.matchAll(/\bid:\s*(\w+)/g)].map(m => m[1]))
const fi = ids(full), mi = ids(mini)
const clash = [...mi].filter(x => fi.has(x) && x !== "minimalFace")
ok(clash.length === 0, "no id used in both faces: " + clash.join(", "))
const miniIds = [...mini.matchAll(/\bid:\s*(\w+)/g)].map(m => m[1])
ok(new Set(miniIds).size === miniIds.length, "no id twice inside the minimal face")
ok(!/win\.hoverHour|win\.hoverDay/.test(mini), "the minimal face has no hover readout")
ok(/WeatherGlyph/.test(mini) && /SekaiPlate/.test(mini) && /Slant \{/.test(mini) && /Burst \{/.test(mini), "minimal keeps the plate, the glyph, the place tab and the puff")
ok(!/Water \{|windArrow|WM\.curvePoints|calendar_view_day/.test(mini), "minimal has no gauges, curve or Hourly / Days key")

// ---- the minimal layout adds up (design px; the content is 286 x 238) ----
const num = (name, t = mini) => { const m = new RegExp("property (?:real|int) " + name + ":\\s*(?:card\\.tiny \\? [0-9.]+ : )?([0-9.]+)").exec(t); assert(m, "no " + name); return +m[1] }
const contentW = num("contentW", w), contentH = num("contentH", w)
ok(contentW === 286 && contentH === 238, "the 2 x 2 content is still 286 x 238")
const plateH = num("plateH"), laneY = num("laneY"), cols = num("cols")
ok(/readonly property real laneH: card\.contentH - mini\.laneY/.test(mini), "the lane runs to the bottom of the content")
ok(plateH - 14 + 28 <= laneY, "the place tab / refresh key (hang 14 up, 28 tall) end above the lane")
ok(plateH < laneY && laneY < contentH - 60, "plate, then lane, with room for the readings")
ok(cols === 4, "four readings")
// the temperature, its unit and the disc share the plate's width without touching
const px = (re) => { const m = re.exec(mini); assert(m, "missing " + re); return +m[1] }
const numPx = px(/id: mNum[\s\S]*?pixelSize:\s*(\d+)/), discW = px(/id: mdisc[\s\S]*?width:\s*(\d+)/)
const approx = 3 * 0.62 * numPx + 21 + 24 * 1.7    // three characters of the big number, and "°C" at 24 px
ok(approx < contentW - discW - 12 - 4, "the number plus its unit leave room for the disc (3 characters): " + Math.round(approx))

// ---- Settings, ipc, cheat sheet, Edit Desktop key ----
ok(/onPicked: id => WeatherCardService\.setStyle\(id\)/.test(settings) && /id: "minimal"/.test(settings), "Settings -> Desktop offers the style")
ok(/function style\(mode: string\): void \{ WeatherCardService\.setStyle\(mode\) \}/.test(shell), "ipc weathercard style")
ok(/property string icon: ""/.test(key) && /property string label: ""/.test(key) && /root\.label !== ""/.test(key), "SizeKey takes an icon and a label (size users unchanged)")
ok(/text: root\.label !== "" \? root\.label : "SIZE  "/.test(key), "SizeKey still says SIZE by default")

console.log("style_unit: all " + n + " checks passed")
