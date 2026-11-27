# The region picker's frozen picture

The region picker (Screenshot, Save, Copy text, Image search, Record: SUPER + SHIFT + S and
friends, `qs -c sekaipop ipc call region screenshot`) does not let you pick on the live
screen. As it opens, each monitor's overlay takes a picture of that monitor with `grim`
(`region-action.sh capture`) and shows it frozen under a dim. What you pick is cropped out
of that picture (`region-action.sh crop`), so a menu or tooltip that closes as the picker
takes the keyboard is still in the shot.

Files: `modules/sekai/regionSelector/RegionSelector.qml` (the overlay),
`services/RegionService.qml` (state, actions, the crop queue),
`scripts/system/region-action.sh` (grim, crop, copy / save / ocr / search / record).

## The frozen picture

The picture has to be of the screen **without** the picker on it. grim is started in the
overlay window's `Component.onCompleted`, and the window is put on screen at the same time,
so the two race:

- grim usually takes its frame first (it starts in a few milliseconds, and the window's first
  frame takes longer), and the picture is clean;
- but on a slower or busier machine the window can be drawn first. Then the dim (48 % black
  over the whole screen while nothing is picked) and the hint at the top are **in the
  picture**, and every crop of it comes out darker than the screen was. It looks random,
  because it is a race (issue [#160](https://github.com/Blapples/SekaiPop/issues/160)).

So the overlay draws nothing until grim is done: `shotTaken` starts `false`, a `Binding`
holds the window's `contentItem.opacity` at 0 until then, and grim's `onExited` sets it,
whatever grim's exit code. Two choices in that:

- **Opacity, not `visible`.** An invisible item can't hold the keyboard, and the overlay
  takes it (`WlrKeyboardFocus.Exclusive`) from the first moment, so Escape must work even
  in the fraction of a second before the picture is there. An item at opacity 0 keeps its
  focus and its mouse areas; it just isn't drawn.
- **grim failing still shows the picker.** Otherwise a failed grim would leave an invisible
  window holding the keyboard. With no picture the picker shows over the live screen, as it
  always did, and the crop falls back to grabbing the region live once the picker is gone.

The window being mapped while its content is at opacity 0 is harmless: it is
`color: "transparent"`, and the `sekaipop-region` layer has no animation (`region-action.sh
rules`), so there is nothing of it on screen for grim to catch.

## Checking it

The race rarely goes the wrong way on a fast machine, so make it lose on purpose: put
`sleep 0.5;` before `exec grim` in the installed `region-action.sh capture` branch, then open
the picker (`ipc call region screenshot`), wait two seconds, and look at
`$XDG_RUNTIME_DIR/sekaipop-region/shot-<monitor>.png` before cancelling (`ipc call region
cancel`). Without the fix the picture has the dim and the "Esc cancels" hint in it; with it,
the picture matches a plain `grim -o <monitor>` taken just before, and the picker appears
only after grim is done. Put the script back afterwards.

`node sekaipop/tests/region-test/frozen_shot_test.js` is the source check.
