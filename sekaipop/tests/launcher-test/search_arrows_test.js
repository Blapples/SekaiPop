// node tests/launcher-test/search_arrows_test.js
//
// While something is typed on the Apps screen, Left / Right move the search box's
// caret, and Enter opens the first match. Down takes the keys into the grid on that
// first match (not a row lower); from there Left / Right move the pick, until a letter
// is typed again (docs/LAUNCHER-KEY-CURSOR.md, "Typing, then the arrows"). This is a
// source check (nothing here runs QML).
const assert = require("assert")
const fs = require("fs")
const locate = require("../lib/locate")

const face = require("../lib/themetext")(fs.readFileSync(locate("modules/sekai/launcher/LauncherFace.qml"), "utf8"))

// Left / Right go to the grid only when it has the arrows.
assert.ok(/readonly property bool gridHasArrows:\s*query\.length === 0\s*\|\|\s*\(keyNav && drawerGrid\.currentIndex >= 0 && extrasLayer\.rowPick < 0\)/.test(face),
          "the grid has the arrows with nothing typed, or after Down while typing (not while a row above has the pick)")
assert.ok(/event\.key === Qt\.Key_Left && \(face\.gridHasArrows \|\|/.test(face)
          && /event\.key === Qt\.Key_Right && \(face\.gridHasArrows \|\|/.test(face),
          "Left / Right ask gridHasArrows, not just whether anything is typed")

// The first Down while typing stays on the first match.
const move = face.slice(face.indexOf("function moveKey("), face.indexOf("onQueryChanged:"))
const down = move.indexOf("key === Qt.Key_Down && face.searching && !face.keyNav")
assert.ok(down > 0, "moveKey has the first-Down case")
assert.ok(down < move.indexOf("grid.moveCurrentIndexDown()"), "and it comes before the pick moves down")
assert.ok(/face\.keyNav = true\s*return\s*\}/.test(move.slice(down)), "it only hands the keys to the grid")
assert.ok(move.indexOf("extrasLayer.moveRows(") < down, "rows above the grid still take Down first")

// Typing gives the arrows back to the caret.
const query = face.slice(face.indexOf("onQueryChanged:"))
assert.ok(/onQueryChanged:\s*\{\s*face\.keyNav = false/.test(query), "a new letter hands the arrows back to the caret")

// Enter still opens the first match while typing, with or without Down.
assert.ok(/if \(i < 0 && face\.searching\)\s*i = 0/.test(face), "Enter falls back to the first match")
assert.ok(/drawerGrid\.currentIndex = face\.searching \? 0 : -1/.test(query), "typing puts the pick on the first match")

console.log("search_arrows_test: ok")
