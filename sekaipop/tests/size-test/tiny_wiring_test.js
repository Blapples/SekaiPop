// The 1 x 1 size of the user, weather, calendar and palette cards: reads the QML source and checks
// that each service, card, tile, the ipc, Settings, Edit Desktop and the preset registry line up,
// and that the 1 x 1 footprint is exactly a quarter of the 2 x 2 (154 x 132 of 320 x 276).
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8");
let fails = 0;
function ok(cond, msg) { console.log((cond ? "ok   " : "FAIL ") + msg); if (!cond) fails++; }

const W = "modules/sekai/desktopWidgets/";
const cards = [
  { name: "usercard", svc: "UserCardService", file: W + "UserCardWidget.qml", ipc: "usercard", def: "2x2", three: false, tile: null },
  { name: "weathercard", svc: "WeatherCardService", file: W + "WeatherCardWidget.qml", ipc: "weathercard", def: "2x2", three: false, tile: W + "WeatherTile.qml" },
  { name: "calendarcard", svc: "CalendarCardService", file: W + "CalendarCardWidget.qml", ipc: "calendarcard", def: "full", three: true, tile: W + "CalendarTile.qml" },
  { name: "palettecard", svc: "PaletteService", file: W + "PaletteWidget.qml", ipc: "palettecard", def: "full", three: true, tile: W + "PaletteTile.qml" },
];
const shell = read("shell.qml");
const settings = read("modules/sekai/settings/SettingsPageDesktop.qml");
const reg = read("services/PresetWidgets.qml");
const key = read("modules/sekai/editMode/SizeKey.qml");

// ---- the footprint: a quarter of the 2 x 2 ----
const inset = 7 + 10, shadow = 4            // borderWidth + outerRingWidth + 10, Theme.shadowOffset
ok(120 + 2 * inset === 154 && 94 + 2 * inset + shadow === 132, "1 x 1 footprint is 154 x 132");
ok(2 * 154 + 12 === 286 + 2 * inset && 2 * 132 + 12 === 238 + 2 * inset + shadow, "four 1 x 1 footprints tile the 320 x 276 of a 2 x 2 (12 px between)");

const braces = t => t.split("{").length === t.split("}").length && t.split("(").length === t.split(")").length && t.split("[").length === t.split("]").length;

for (const c of cards) {
  const svc = read(`services/${c.svc}.qml`);
  const w = read(c.file);
  ok(new RegExp(`property string size: "${c.def}"`).test(svc) && /readonly property bool tiny: root\.size === "1x1"/.test(svc), `${c.name}: service has size (default ${c.def}) and tiny`);
  ok(/function setSize\(value\)/.test(svc) && /value === "1x1" \|\| value === "tiny"/.test(svc) && /function toggleSize\(\)/.test(svc), `${c.name}: setSize takes 1x1 / tiny, toggleSize exists`);
  ok(/size: root\.size/.test(svc), `${c.name}: size is saved`);
  ok(c.three ? /\(s\.size === "2x2" \|\| s\.size === "1x1"\) \? s\.size : "full"/.test(svc)
             : /root\.size = s\.size === "1x1" \? "1x1" : "2x2"/.test(svc), `${c.name}: size is restored (anything odd -> ${c.def})`);
  if (c.three) ok(/root\.setSize\(root\.tiny \? "full" : \(root\.small \? "1x1" : "2x2"\)\)/.test(svc), `${c.name}: the key steps full -> 2x2 -> 1x1 -> full`);
  else ok(/root\.setSize\(root\.tiny \? "2x2" : "1x1"\)/.test(svc), `${c.name}: the key flips 2x2 <-> 1x1`);

  ok(new RegExp(`readonly property bool tiny: ${c.svc}\\.tiny`).test(w), `${c.name}: widget follows ${c.svc}.tiny`);
  ok(/contentW: card\.tiny \? 120 : /.test(w) && /contentH: card\.tiny \? 94 : /.test(w), `${c.name}: 1 x 1 content is 120 x 94`);
  ok(new RegExp(`onToggled: ${c.svc}\\.toggleSize\\(\\)`).test(w) && /SizeKey \{\s*shown: chrome\.selected[^]*?label: "SIZE  "/.test(w), `${c.name}: Edit Desktop size key shows 1 x 1`);
  ok(/id: tinyLoader|active: card\.tiny\s+sourceComponent: tinyFace/.test(w) && /id: tinyFace/.test(w), `${c.name}: the 1 x 1 face is built only while 1 x 1`);

  const block = shell.slice(shell.indexOf(`target: "${c.ipc}"`));
  const handler = block.slice(0, block.indexOf("IpcHandler") > 0 ? block.indexOf("IpcHandler") : block.length);
  ok(new RegExp(`function size\\(mode: string\\): void \\{ ${c.svc}\\.setSize\\(mode\\) \\}`).test(handler) && new RegExp(`function toggleSize\\(\\): void \\{ ${c.svc}\\.toggleSize\\(\\) \\}`).test(handler), `${c.name}: ipc ${c.ipc} size / toggleSize`);
  ok(new RegExp(`onPicked: id => ${c.svc}\\.setSize\\(id\\)`).test(settings), `${c.name}: Settings -> Desktop offers the size`);
  ok(braces(w) && braces(svc), `${c.name}: braces balance`);
  if (c.tile) {
    const t = read(c.tile);
    ok(braces(t) && /^Item \{/m.test(t), `${c.name}: ${path.basename(c.tile)} balances and is an Item`);
    ok(new RegExp(`${path.basename(c.tile, ".qml")} \\{[^}]*width: card\\.contentW[^}]*height: card\\.contentH`).test(w), `${c.name}: the tile is given the card's content size`);
  }
}

// ---- cards that always wear 2x2 / the page switches: the content is hidden at 1 x 1 ----
const uc = read(cards[0].file);
ok(/id: content\s+z: 2\s+visible: !card\.tiny/.test(uc), "usercard: the 2x2 content is hidden at 1 x 1");
ok(/card\.tiny \? \(tinyLoader\.item \? tinyLoader\.item\.avatar : null\) : avatarSlot/.test(uc) && /tinyLoader\.item\.pop\(\)/.test(uc), "usercard: the avatar hit test and the burst follow the 1 x 1 face");
const cc = read(cards[2].file);
ok(/id: content\s+z: 2\s+visible: !card\.small && !card\.tiny/.test(cc) && /active: card\.small\s+sourceComponent: miniFace/.test(cc), "calendar: full / 2x2 / 1x1 each show only their own face");
const pc = read(cards[3].file);
ok(/id: content\s+z: 2\s+visible: !card\.tiny/.test(pc), "palette: the card's content is hidden at 1 x 1");
ok(/onClicked: \{\s*if \(card\.tiny\)\s*PaletteService\.shuffle\(\)/.test(pc) && /hoverEnabled: card\.tiny/.test(pc), "palette: a click on the tile shuffles, the fan hears the pointer");
const wc = read(cards[1].file);
ok(/active: !win\.minimal && !card\.tiny/.test(wc) && /active: card\.tiny\s+sourceComponent: tinyFace/.test(wc), "weather: classic / minimal / 1 x 1 are one Loader each");
ok(/shown: chrome\.selected && !card\.tiny\s+icon:/.test(wc) && /row: card\.tiny \? 0 : 1/.test(wc), "weather: the style key hides at 1 x 1 and the size key takes the top place");
ok(/property int row: 0/.test(key) && /y: -12 \+ root\.row \* 40/.test(key), "SizeKey: a second key can sit under the first");

// ---- old presets: wear the cards as they always were ----
ok(/id: "usercard", service: UserCardService, before: \{ size: "2x2" \}/.test(reg), "presets: usercard's `before` is 2x2");
ok(/before: \{ style: "classic", size: "2x2" \}/.test(reg), "presets: weathercard's `before` is classic, 2x2");
ok(/id: "calendarcard", service: CalendarCardService, skip: \["events"\], before: \{ size: "full" \}/.test(reg), "presets: calendarcard's `before` is still full");

// ---- the 1 x 1 face is ONE bare object (TinyFoot frames it), not a card and not a plate ----
const tf = read(W + "TinyFoot.qml");
ok(/readonly property real capW: root\.width \+ root\.bleed \* 2/.test(tf) && /readonly property real capH: root\.height \+ root\.bleed \* 2/.test(tf) && /default property alias content: frame\.data/.test(tf), "TinyFoot: the footprint is the tile's box grown by the housing's inset, with a content alias");
ok(/x: -root\.bleed\s+y: -root\.bleed/.test(tf) && /height: root\.capH \+ root\.shadowDy/.test(tf), "TinyFoot: the frame starts at the card's edge and has room for the hard shadow");
ok(!fs.existsSync(path.join(root, W + "TinyKey.qml")), "TinyKey is gone (no plate behind the 1 x 1 objects)");
for (const c of cards) {
  const w = read(c.file);
  ok(/Pill \{\s+visible: !card\.tiny\s+anchors\.fill: parent\s+cornerRadius: mt\.radiusOuter/.test(w), `${c.name}: the housing is not drawn at 1 x 1`);
  if (c.tile) {
    const t = read(c.tile);
    ok(/TinyFoot \{/.test(t) && !/SekaiPlate/.test(t) && !/TinyKey/.test(t) && !/DotField/.test(t), `${c.name}: ${path.basename(c.tile)} stands in a TinyFoot, no plate, no backdrop`);
    ok(/property bool hover: false/.test(t) && /property bool pressed: false/.test(t) && /hover: dragArea\.containsMouse\s+pressed: dragArea\.pressed/.test(w), `${c.name}: the card's drag area lights and presses the object`);
    ok(/pressed: root\.pressed/.test(t) || /root\.pressed/.test(t), `${c.name}: the press reaches the object`);
  }
}
const face = uc.slice(uc.indexOf("the 1 x 1 face"), uc.indexOf("the content ====="));
ok(/TinyFoot \{\s+id: tFoot/.test(face) && !/TinyKey/.test(face) && !/SekaiPlate/.test(face), "usercard: the 1 x 1 face stands in a TinyFoot, no plate");
ok(/readonly property Item avatar: tAvatar/.test(face) && /pressed: card\.avatarDown/.test(face), "usercard: the avatar itself is the key (hit test, press)");
ok(!/userName/.test(face.replace(/text: win\.userName\.charAt\(0\)/, "")), "usercard: avatar only, no name on the 1 x 1 face (just the initial when no picture is set)");
ok(!/tName|ribbon|halftone/.test(face), "usercard: no name plate, ribbon or halftone at 1 x 1");
ok(/hoverEnabled: card\.tiny/.test(read(cards[1].file)) && /hoverEnabled: card\.tiny/.test(cc), "weather and calendar: the drag area hears the pointer at 1 x 1");

// ---- the objects fit their footprint (capW 154 x capH 128) ----
const CAP_W = 154, CAP_H = 128;
const wt = read(W + "WeatherTile.qml");
const sizes = /<= 2 \? (\d+) : \(root\.num\.length === 3 \? (\d+) : (\d+)\)/.exec(wt);
ok(!!sizes, "weather tile: three number sizes (2 / 3 / 4 characters)");
if (sizes) {
  const [, s2, s3, s4] = sizes.map(Number);
  const dia = CAP_H - 4;
  const width = (n, px) => n * 0.62 * px + 0.4 * px * 1.3 + 2 * px * 0.085   // the characters, a degree + C, and the outline
  ok(width(2, s2) < dia - 14 && width(3, s3) < dia - 14 && width(4, s4) < dia - 14, `weather tile: 2 / 3 / 4 characters (${s2} / ${s3} / ${s4} px) fit the ${dia} px button`);
}
const pt = read(W + "PaletteTile.qml");
const chipW = +/chipW: (\d+)/.exec(pt)[1], chipH = +/chipH: (\d+)/.exec(pt)[1];
const widest = Math.max(...JSON.parse(/lean: (\[[^\]]*\])/.exec(pt)[1]).map(Math.abs)) * 1.1 * Math.PI / 180;
ok(chipH * Math.sin(widest) + (chipW / 2) * Math.cos(widest) <= CAP_W / 2 - 4, `palette tile: the fan, fully open, stays inside the ${CAP_W} px footprint`);
ok(chipH * Math.cos(widest) + (chipW / 2) * Math.sin(widest) + 6 <= CAP_H, `palette tile: the fan stays inside the ${CAP_H} px footprint`);
const ct = read(W + "CalendarTile.qml");
ok(/Locale\.ShortFormat/.test(ct) && /today: win\.today/.test(cc), "calendar tile: weekday and month come from the card's own clock, in the system locale");

// A Behavior writes to the property it animates; on a `readonly` one QML refuses to load the file
// ("Invalid property assignment: ... is a read-only property"), which takes the whole shell down.
for (const c of cards.filter(c => c.tile)) {
  const t = read(c.tile);
  const ro = new Set([...t.matchAll(/readonly\s+property\s+\w+\s+(\w+)\s*:/g)].map(m => m[1]));
  const bad = [...t.matchAll(/Behavior\s+on\s+(\w+)/g)].map(m => m[1]).filter(n => ro.has(n));
  ok(bad.length === 0, `${c.name} tile: no Behavior on a readonly property${bad.length ? " (" + bad.join(", ") + ")" : ""}`);
}

console.log(fails ? `\n${fails} FAILED` : "\nall 1 x 1 checks passed");
process.exit(fails ? 1 : 0);
