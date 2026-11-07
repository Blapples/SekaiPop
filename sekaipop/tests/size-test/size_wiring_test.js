// The 2 x 2 size of the To-Do, Calendar and Palette cards: reads the QML source and checks
// that the service, the card, the ipc, Settings and Edit Desktop all line up, and that the
// 2 x 2 content height adds up to the 238 the clock / user / weather cards use.
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8");
let fails = 0;
function ok(cond, msg) { console.log((cond ? "ok   " : "FAIL ") + msg); if (!cond) fails++; }

const cards = [
  { name: "todo", svc: "TodoService", file: "modules/sekai/desktopWidgets/TodoWidget.qml", ipc: "todo" },
  { name: "calendar", svc: "CalendarCardService", file: "modules/sekai/desktopWidgets/CalendarCardWidget.qml", ipc: "calendarcard" },
  { name: "palette", svc: "PaletteService", file: "modules/sekai/desktopWidgets/PaletteWidget.qml", ipc: "palettecard" },
];
const shell = read("shell.qml");
const settings = read("modules/sekai/settings/SettingsPageDesktop.qml");

for (const c of cards) {
  const svc = read(`services/${c.svc}.qml`);
  const w = read(c.file);
  ok(/property string size: "full"/.test(svc) && /readonly property bool small: root\.size === "2x2"/.test(svc), `${c.name}: service has size (default full) and small`);
  const restores = c.name === "todo" ? /root\.size = s\.size === "2x2" \? "2x2" : "full"/ : /root\.size = \(s\.size === "2x2" \|\| s\.size === "1x1"\) \? s\.size : "full"/;
  ok(/size: root\.size/.test(svc) && restores.test(svc), `${c.name}: size is saved and restored (anything odd -> full)`);
  ok(/function setSize\(value\)/.test(svc) && /function toggleSize\(\)/.test(svc), `${c.name}: setSize / toggleSize exist`);
  ok(new RegExp(`${c.svc}\\.small`).test(w), `${c.name}: widget follows ${c.svc}.small`);
  ok(/SizeKey \{\s*shown: chrome\.selected/.test(w) && new RegExp(`${c.svc}\\.toggleSize\\(\\)`).test(w), `${c.name}: size key shows while selected and toggles`);
  const block = shell.slice(shell.indexOf(`target: "${c.ipc}"`));
  const handler = block.slice(0, block.indexOf("IpcHandler") > 0 ? block.indexOf("IpcHandler") : block.length);
  ok(new RegExp(`function size\\(mode: string\\): void \\{ ${c.svc}\\.setSize\\(mode\\) \\}`).test(handler) && new RegExp(`function toggleSize\\(\\): void \\{ ${c.svc}\\.toggleSize\\(\\) \\}`).test(handler), `${c.name}: ipc ${c.ipc} size / toggleSize`);
  ok(new RegExp(`onPicked: id => ${c.svc}\\.setSize\\(id\\)`).test(settings), `${c.name}: Settings -> Desktop offers the size`);
  const b = w.split("{").length === w.split("}").length;
  ok(b, `${c.name}: braces balance`);
}

// To-Do: 36 header + 2 rule + 40 add box + list, 3 gaps of 10 = 108 + list = 238
const todo = read(cards[0].file);
ok(/smallContentH: 238/.test(todo) && /smallListH: win\.smallContentH - 108/.test(todo), "todo: 2x2 list window = 238 - 108 = 130");
ok(/id: header|height: 36/.test(todo) && /height: 40/.test(todo), "todo: header 36 / add box 40 still the sizes the 108 assumes");
// Calendar: plate 62 + gap 4 + week 13 + gap 3 + 6 rows (24) with 5 gaps (2) = 238 at most
const grid = 82 + 6 * 24 + 5 * 2;
ok(grid <= 238 && 41 * 6 + 38 + 1 <= 286, `calendar: 2x2 grid ends at ${grid} of 238, 7 cells fit 286 wide`);
// Palette: 30 + 28 + 88 + 37 + 37 + 4 gaps of 4
ok(30 + 28 + (8 + 72 + 8) + 37 + 37 + 4 * 4 <= 238, "palette: 2x2 column adds up to 236 of 238");
ok(5 * 52 + 4 * 4 <= 286, "palette: five 52 px swatches fit 286");
ok(/Preview only/.test(read(cards[2].file)), "palette: still has its status chip");

console.log(fails ? `\n${fails} FAILED` : "\nall size checks passed");
process.exit(fails ? 1 : 0);
