# The Apps screen's keyboard cursor

On the Apps screen (SUPER + A), the app that Enter would open is picked out by a
mint plate behind its tile: a thick outline and the phone's hard shadow, the same
look as a picked row above the grid (a system action, a web search). The plate
slides from tile to tile as the arrow keys move it, and the app's name turns to the
dark ink the mint keys use, over the wallpaper as well.

## Why

The pick used to show only as the icon growing by a tenth, the same as a mouse hover.
Against a wallpaper, with forty icons on the screen, it was hard to see where the
arrow keys had gone. While typing it was worse: Enter opens the first match, but
nothing showed which one that was until an arrow key was pressed.

## When it shows

`LauncherFace.qml` `gridPickShown`:

- after an arrow key (or Tab) moved the pick into the grid, and
- while something is typed, on the first match, before any arrow key,
- but not while a row above the grid has the pick (a strong match such as a system
  action takes Enter first, `LauncherExtras.qml` `rowPick`), and not while a card
  (calculator, clipboard, emoji...) is up.

A mouse hover does not bring the plate: a hovered icon only grows, as before. With
nothing typed, moving the mouse over the grid hands the pick back to the mouse
(`keyNav = false`) and the plate goes until a key is pressed again. While something is
typed it stays on the match Enter would open, since that is still true.

## Typing, then the arrows

While something is typed, Left and Right belong to the search box: they move the
caret in what you typed, and Enter opens the first match (the one under the plate).
To walk the matches with the keys:

- **Down** takes the keys into the grid on that first match. It does not move the
  plate: the first match is already what Enter opens, so Down only says "the arrows
  are for the grid now". (A row above the grid, such as a strong system-action match,
  still takes Down first, as before.)
- From there **Left / Right** move the plate from match to match, Up / Down move it a
  row, and Enter opens the picked one.
- **Typing** another letter hands Left / Right back to the caret, and the plate goes
  back to the first of the new matches. Moving the mouse over the grid does the same.

With nothing typed there is no caret to move, so the arrows always go to the grid.

`LauncherFace.qml`: `gridHasArrows` says who Left / Right belong to; `moveKey()` has
the first-Down case; `onQueryChanged` sets `keyNav` back to false. Checked by
`tests/launcher-test/search_arrows_test.js`.

Before this, Left / Right only went to the grid with nothing typed, so while searching
the only way through the matches was Up / Down a whole row at a time (and the first
Down skipped the first row).

## How

One item, the `GridView`'s `highlight` (`pickPlate`), drawn under the tiles and moved
by the view itself (`highlightMoveDuration: 90`). One plate instead of one per tile
keeps the tiles as cheap as they were (no extra items per tile, and nothing changes in
a tile but its name's colour when it is picked).
