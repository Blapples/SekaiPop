# The CPU & RAM pill's icons

The bar's CPU & RAM pill (Settings > Bar > CPU & RAM, `bar.resources`) shows two figures, each
with an icon and no word beside it, so the icon is the only thing that says which is which.
Its popup shows the same two on plates labelled CPU and RAM.

| Figure | Icon | Material name |
|---|---|---|
| CPU | a chip, always the same | `memory` |
| RAM | a pie that fills as the memory does, in six steps | `clock_loader_10` … `clock_loader_90` |

The rules are in `sekaipop/modules/common/functions/LoadGlyphs.js` (`cpu()`, `ram(pct)`),
shared by `modules/sekai/bar/ResourceIndicator.qml` (the pill, lying and standing) and
`ResourcePopup.qml` (the plates).

## Why this way round

It used to be the other way: CPU had the stepping pie and RAM the chip. Material's name for
the chip is `memory`, which is how it got to RAM, but the picture is a processor (the shell's
own `IconMap.js` maps it to `cpu` for the other icon set). A pie that fills reads as "how
full", which is the question for memory. With no words on the bar, "CPU 9 %, RAM 21 %" read
as the opposite (issue [#168](https://github.com/Blapples/SekaiPop/issues/168)).

## The pie's steps

Material Symbols Rounded only has the `clock_loader` pie in six steps (10, 20, 40, 60, 80,
90), so the percent snaps to the closest one, with the switch at the midpoints 15, 30, 50,
70 and 85. Either icon turns red at 90 % (`cpuHot` / `memHot`).

`node sekaipop/tests/resource-test/load_glyphs_test.js` checks the rules and both files.
