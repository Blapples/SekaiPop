# Peek first: the hot edge shows only the tip of the phone

The Quick Panel's hot edge (the strip at the bottom centre of each screen) opens the whole
phone when the pointer rests in it for the edge delay. A pointer that strays to the bottom
of the screen while doing something else throws the phone up by mistake.

**Settings > General > Quick Panel > Peek first** (`panel.hotPeek`, off by default) changes
what the edge does:

- Resting in the strip raises only the **tip** of the phone: the top of its face, down to the
  clock and date.
- **Click the tip** (or the strip under it) and the whole phone slides up, a normal open phone.
- **Move the mouse off** the tip and the strip and, after a short moment (`peekLeaveMs`,
  450 ms, enough to cross from the strip onto the tip), the tip drops out of sight again.

The keybind, the bar's bell and `ipc call phone show` still open the whole phone at once.
`qs -c sekaipop ipc call options set panel.hotPeek true` turns it on from a shell.

## How it works

It is the notification alert's low spot used a second time. `QuickPanel.qml`:

- `peekUp` raises the phone like `alertUp` does (`up` is `open || alertUp || peekUp`), so it
  comes out of the pocket with the same pull-out, and takes neither the keyboard nor the
  click-away grab (both follow `open`).
- `peekMode` keeps it at the low spot `win.peekLift` until it is out of sight, the way
  `alertMode` keeps the alert's (so it doesn't jump up on the way down). `root.lowLift` is
  whichever applies; `stage.rise`, `hitRect` and the Power rail's hit box all use it.
- `win.liftShowing(faceY, margin)` works out either spot: how far down the phone rests so its
  face shows down to design y `faceY`. The alert asks for 204 (under its card), the peek for
  `peekTipY`, 96 (under the clock and date).
- `root.peeking` (`peekMode && !open`) is true for as long as the phone on screen is a peek: rising,
  up, or dropping. The phone takes no input then (its `enabled`), so nothing on the face can be
  clicked.
- `peekTouch`, a MouseArea over the whole window on top of everything, is on while `peeking`. Any
  press the window takes then opens the phone (`claimPeek`), wherever it lands, and its hover
  keeps the peek up. Hovering a tip that is already dropping brings it back up. The strip's own
  `TapHandler` does the same for a click on the strip, whichever of the two windows is on top there.
- It opens on the **release**, not the press: opening disables it, and a MouseArea disabled while
  its own press is being delivered lets that press carry on to what is under it.

Two earlier versions let clicks through to the banner (whose click opens the picture chooser),
found on the owner's shell with a debug log. The first opened on the press, as above. The second
covered only the phone's resting box and was on only while the peek was up. But the window also
takes the mouse above that box while the phone bounces up (`railHost`), and the face took clicks
again as soon as the peek began to drop. Hence the whole window, and `peeking` rather than `peekUp`.
- `peekLeave` runs while peeking with the mouse off both `peekTouch` and every strip
  (`hotHovering`), and lowers it when it fires.
- A notification arriving while the tip is up turns the peek into the alert phone (`alert()`):
  it rises a little further to show the card, and behaves as an alert from then on.

The hot edge's own rules still hold: the mouse has to leave the strip before it can raise the
phone again, and the edge ignores the mouse for 1.2 s after the phone went down.

`tests/hot-peek-test/hot_peek_test.js` checks the wiring and runs `peekOn`, `claimPeek`,
`close` and `alert` against a fake root.
