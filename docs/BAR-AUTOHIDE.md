# Auto-hiding the bar, and a key to show or hide it

The bar can slide off its edge and come back when the pointer touches that edge, and it
can be shown or hidden with a key. Issue [#61](https://github.com/Blapples/SekaiPop/issues/61).

## Using it

- **Settings > Bar > Auto-hide.** On: the bar is away until the pointer touches the edge
  it sits on, and windows use the whole screen (the bar reserves no space and slides in
  over them). Off: always shown, as before. The setting is `bar.hideMode` (`off` | `auto`).
- **A key to show / hide the bar:** Settings > Hyprland > Keybinds > Shell > *Toggle bar*. It ships
  without a key, so it can't take one you already use; pick one there (SUPER + B is free
  in the shipped config). It is the same switch as Settings > Bar > Show bar.
- From a script or your own bind:

  ```sh
  qs -c sekaipop ipc call bar toggle            # Show bar on / off (also: show, hide)
  qs -c sekaipop ipc call bar peek              # an auto-hiding bar comes out for 2 s
  qs -c sekaipop ipc call bar hidemode auto     # or off
  ```

## When an auto-hiding bar is out

- The pointer is on the bar, or on the line along the very edge (3 px at 100 % scale)
  that brings it out.
- One of its popups is open: tray dropdown or menu, battery, CPU & RAM, screen time, calendar,
  weather, media, equalizer, Discord, utility keys. It stays out until the popup closes.
- Edit Desktop is open on that monitor (the bar is part of the card there).
- For 2 s after `ipc call bar peek`.

Leaving it, it waits 0.45 s before it slides away (the dock's auto-hide waits the same),
so moving off the bar toward a window doesn't flick it away at once. The slide takes
220 ms and is the same slide a desktop preset uses, so the four styles and the four
edges all go the same way.

## How it works

- `Bar.qml`: `revealed` decides; `hideSlide` (0 out, 1 away) is animated from it and
  pushes `Status_Bar` off its edge with the preset slide (`Math.max` of the two, so a bar
  that is already away stays away while a preset swaps).
- While it is away (`tucked`) the input mask is only `hotThick` real pixels along the
  edge. A bottom bar still cuts the Quick Panel's hot edge out of that line, as it does
  out of the whole strip.
- `exclusiveZone` is 0 while it auto-hides. `BarPositionService.reserved` says the same
  to the rest of the shell; the pinned dock uses it to place its Edit Desktop card, since
  the compositor no longer moves the dock off the bar's space.
- One HoverHandler on top of the window's contents sees the pointer (passive, so the
  bar's own mouse areas keep their clicks).
- A bar built while auto-hide is on (a shell start, a new monitor) starts away; the
  slide animates only from 0.6 s after it is on screen, so nothing flashes.

## What it doesn't do

- **Game Mode:** the bar takes no input then, so an auto-hiding bar stays away for the
  whole game. Turn Auto-hide off to keep the clock in view while you play.
- **No "smart" mode** (away only while a window is in its way, like the dock's Smart
  hide). `bar.hideMode` is a string so it can be added later.
- **Notifications, the OSD and the reload popup** still keep clear of the bar's place,
  so they don't end up under the bar when it comes out. The same goes for an unpinned
  dock on the bar's edge.
- **Fullscreen windows** cover the bar as before.
