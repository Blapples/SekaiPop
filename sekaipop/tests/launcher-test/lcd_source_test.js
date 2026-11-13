// node tests/launcher-test/lcd_source_test.js
//
// The Apps screen shows the monitor's wallpaper as an LCD (LauncherLcd.qml): washed out,
// under a fine pixel mesh, in the shape of the phone's glass. This is a source check
// (nothing here runs QML): it makes sure the switch, the wiring and the few things that
// keep it cheap and readable are all still there.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const locate = require("../lib/locate")

const read = rel => require("../lib/themetext")(fs.readFileSync(locate(rel), "utf8"))
const top = path.join(__dirname, "..", "..")

const lcd = read("modules/sekai/launcher/LauncherLcd.qml")
const face = read("modules/sekai/launcher/LauncherFace.qml")
const quick = read("modules/sekai/quickPanel/QuickPanel.qml")
const settings = read("services/SettingsService.qml")
const general = read("modules/sekai/settings/SettingsPageGeneral.qml")

// ---------- the setting ----------
// One "Phone wallpaper" choice for the Quick and Apps screens (tests/phone-test/
// phone_wallpaper_test.js has the rules); the old on / off switch still decides until it is set.
assert.ok(/"launcher\.lcdWallpaper":\s*true/.test(settings), "the old switch is still on by default")
assert.ok(/"phone\.wallpaper":\s*""/.test(settings), "the phone wallpaper starts unchosen (the old switch decides)")
assert.ok(general.includes('label: "Phone wallpaper"') && general.includes('SettingsService.set("phone.wallpaper", id)'),
          "Settings has the Phone wallpaper choice")
assert.ok(!general.includes('SettingsService.toggle("launcher.lcdWallpaper")'), "the old Apps-only switch is gone from Settings")

// ---------- the wiring ----------
assert.ok(/LauncherLcd\s*\{[^}]*z:\s*-10/.test(face), "the LCD sits under everything else on the Apps screen")
assert.ok(face.includes("PanelImages.phoneWallpaperFor(face.screenName)"),
          "it shows the phone wallpaper for this monitor (the same one as the Quick screen)")
assert.ok(/screenName:\s*root\.targetScreen/.test(quick), "the Quick Panel tells the Apps screen which monitor it is on")
assert.ok(/active:\s*face\.visible/.test(face), "the picture is only decoded while the Apps screen shows")
assert.ok(/visible:\s*lcd\.path\s*!==\s*""/.test(lcd), "no wallpaper: no LCD, the screen stays plain white")

// ---------- the shape of the glass ----------
assert.ok(lcd.includes("Theme.phoneScreenInset") && lcd.includes("Theme.phoneCornerRadius"),
          "it is cut to the phone's glass (inset and corner radius), so it never reaches the bezel")
assert.ok(/ClippingRectangle\s*\{/.test(lcd), "clipped with a ClippingRectangle, not a masked layer")

// ---------- cheap ----------
assert.ok(!/ShaderEffect|MultiEffect|Behavior|Animation|Timer/.test(lcd), "static: no shader, effect or animation in it");
assert.ok(/FramedImage\s*\{[\s\S]{0,400}decodeScale:\s*lcd\.renderScale[\s\S]{0,200}maxDecode:\s*\d+/.test(lcd),
          "the wallpaper is decoded at the size it is drawn (FramedImage, framed), with a ceiling")
assert.ok(/lcd\.active\s*&&\s*lcd\.path/.test(lcd), "nothing is decoded while it is not active")

// ---------- the mesh tile ----------
const tilePath = path.join(top, "assets", "images", "lcd-mesh.png")
assert.ok(fs.existsSync(tilePath), "assets/images/lcd-mesh.png ships with the shell")
assert.ok(lcd.includes('Directories.asset("images/lcd-mesh.png")'), "the tile is found through Directories, like every other asset")
const png = fs.readFileSync(tilePath)
assert.strictEqual(png.slice(1, 4).toString(), "PNG", "the tile is a PNG")
const w = png.readUInt32BE(16), h = png.readUInt32BE(20)
assert.strictEqual(w, 24, "the tile is 24 texels wide: one LCD pixel")
assert.strictEqual(h, 24, "the tile is 24 texels tall: one LCD pixel")
assert.ok(/pitch\s*\/\s*24/.test(lcd), "the code scales the 24 texel tile to `pitch` design units")
assert.ok(/mipmap:\s*true/.test(lcd), "the tile is mipmapped, so the phone's layer can shrink it without noise")

// ---------- see-through, and still readable ----------
const num = name => {
    const m = lcd.match(new RegExp("property real " + name + ":\\s*([0-9.]+)"))
    assert.ok(m, name + " is a plain number in LauncherLcd.qml")
    return parseFloat(m[1])
}
assert.ok(num("washBody") <= 0.2 && num("washTop") <= 0.2,
          "the wallpaper is near full strength: the white wash over it stays light")
// With so little wash there is no chip behind the app names any more: over the wallpaper
// they are white with a thin dark edge. The header (clock, date, speed) changes its ink with
// the picture instead, like the Quick screen's.
assert.ok(!/lcdChip/.test(face), "no chip behind the app names or \"No apps match\"")
assert.ok(!/color:\s*Theme\.pRingWhite|Theme\.accentMint/.test(face.slice(face.indexOf("id: tileDelegate"))),
          "the app tile is no button: no white ring, no lit mint-to-cyan face")
// A name on the keyboard cursor plate drops the edge: it sits on the mint plate, not the
// wallpaper (docs/LAUNCHER-KEY-CURSOR.md).
assert.ok((face.match(/style:\s*face\.lcdOn( && !tile\.picked)? \? Text\.Outline/g) || []).length >= 2,
          "the app names and \"No apps match\" get a thin dark edge over the wallpaper")
assert.ok(!/clockCol/.test(face), "no chip behind the clock and date")

// ---------- the header matches the Quick screen's ----------
const qpFace = read("modules/sekai/quickPanel/QuickPanelFace.qml")
const rate = src => {
    const m = src.match(/function formatRate\(bps\) \{[\s\S]*?\n    \}/)
    assert.ok(m, "formatRate is there")
    return m[0].replace(/\s+/g, " ")
}
assert.strictEqual(rate(face), rate(qpFace), "the speed is written the same way as on the Quick screen")
assert.ok(/downloadBps:\s*root\.source\.downloadBps/.test(quick.slice(quick.indexOf("LauncherFace {"))) &&
          /uploadBps:\s*root\.source\.uploadBps/.test(quick.slice(quick.indexOf("LauncherFace {"))),
          "the Quick Panel feeds the Apps screen the internet speed")
assert.ok(/id:\s*speedBlock/.test(face) && face.includes('"arrow_downward"') && face.includes('"arrow_upward"'),
          "the speed readout (down and up arrows) is on the Apps screen")
// Same places and sizes as QuickPanelFace's clock + date and speed block.
const geom = src => {
    const clock = src.match(/Column \{\s*(?:id: \w+\s*)?x: (\d+)\s*y: (\d+)\s*spacing: (-?\d+)/)
    assert.ok(clock, "clock column found")
    const speed = src.match(/id: speedBlock\s*(?:\/\/[^\n]*\s*)*x: ([^\n]+)\s*y: (\d+)\s*width: (\d+)\s*spacing: (-?\d+)/)
    assert.ok(speed, "speed block found")
    const sizes = [...src.matchAll(/font\.pixelSize: (\d+)/g)].map(m => m[1])
    return { clock: clock.slice(1).join(","), speed: speed.slice(1).join(",") }
}
const g1 = geom(face), g2 = geom(qpFace)
assert.strictEqual(g1.clock, g2.clock, "the clock + date sit where the Quick screen's do")
assert.strictEqual(g1.speed, g2.speed, "the speed readout sits where the Quick screen's does")
assert.ok(/font\.pixelSize:\s*24[\s\S]{0,120}ExtraBold/.test(face.slice(face.indexOf("text: face.clockText"))), "clock: 24px, extra bold")
assert.ok(/text: face\.dateText[\s\S]{0,160}font\.pixelSize:\s*20/.test(face), "date: 20px")
// Ink: white over a dark picture, navy over a light one, measured by LauncherLcd.
assert.ok(/inkLeft[^\n]*lcdLayer\.darkLeft[^\n]*"#ffffff"[^\n]*Theme\.colBorder/.test(face), "left ink follows the picture under the clock")
assert.ok(/inkRight[^\n]*lcdLayer\.darkRight[^\n]*"#ffffff"[^\n]*Theme\.colBorder/.test(face), "right ink follows the picture under the speed")
assert.ok(/id:\s*sampler/.test(lcd) && /< 0\.30/.test(lcd) && /drawImage\(wall/.test(lcd),
          "LauncherLcd measures the picture it has already decoded (the same 0.30 rule as the banner)")

console.log("ok: launcher LCD wallpaper")
