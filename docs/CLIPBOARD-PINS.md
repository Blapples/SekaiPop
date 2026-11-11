# Pinned clipboard entries

The Clipboard card (type `clip ` on the Apps screen, or `ipc call launcherphone mode
clip`) can keep an entry for good: pick it and press the pin key beside Delete, or
Ctrl+P. A pinned entry sits at the top of the list with a pin on its disc, and the
line under the text says "Pinned". It outlives everything that empties the history:

- cliphist's own size limit (the oldest copies are dropped as new ones come in),
- Clear history (the dock's clipboard card, `cliphist wipe`),
- deleting the entry it was pinned from.

Copy (or Enter, or a double click) puts it back on the clipboard as it was, a picture
with its own type. Press the pin key again, or Delete, to let it go.

## Where pins live

`${XDG_STATE_HOME:-~/.local/state}/sekaipop/clip-pins/`, beside the shell's other
state (recent emoji, pinned apps). Each pin is two files named by the time it was made
in milliseconds: `<pin>.data`, the bytes exactly as copied, and `<pin>.preview`,
cliphist's one-line preview of them. A pin is a copy, not a pointer to cliphist's id,
which is why the history can be emptied under it.

Pictures are kept whole, so pinning many large screenshots takes the room they take.

## How it fits together

- `scripts/state/clip-pins.sh`: `pin <cliphist-id> <preview>`, `list`, `show <pin>`,
  `copy <pin>`, `unpin <pin>`. It only accepts digits as ids, so nothing passed to it
  becomes part of a path.
- `modules/common/functions/ClipPins.js`: reads `list` and merges the pins with the
  history (pins first). Tested by `tests/clip-pins-test/clip_pins_test.js`.
- `services/ExtrasSource.qml`: `clipEntries` is that merge of `clipPins` and
  `clipHistory`. `togglePin`, `copyClip` and `deleteClip` know a pin from a history
  entry by `pinned`. Pin and unpin run one at a time, in order, and the list is read
  again after each. The pins are read again with the history every 1.5 s while the card
  is up, so the two launchers (each has its own ExtrasSource) agree.
- `ClipboardCard.qml`: the pin key, the pin glyph, "Pinned" in the info line.

A pinned entry's id is `p<pin>`, which cliphist's ids (digits only) can never be, so
the card keeps the same entry picked across a refresh, and the full-text loader's "is
this answer still for the pick" check works for both kinds unchanged.

## Not listed twice

Copying a pin puts it back on the clipboard, and the watcher stores it in the history
again. A history entry whose preview is the same as a pin's is left out of the list.
The preview is cliphist's own (up to 500 characters of the text, or a picture's size,
type and dimensions), so two different entries are only taken for one when they agree
on all of that.

## What it doesn't do

The dock's clipboard card still shows the history only (its last eight copies); the
pins are in the full Clipboard card it opens with "more".
