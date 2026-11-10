# Displays

Settings > Hyprland > Displays turns screens on and off, and sets their mode, scale and
place. Issue [#109](https://github.com/Blapples/SekaiPop/issues/109) is why this page exists.

## How it works

- `services/DisplayService.qml` reads the screens with `hyprctl -j monitors all` (a screen
  that is off is listed too, with `disabled: true`), keeps a draft of your changes, and on
  **Apply** hands them to `scripts/hyprland/displays.sh apply`. A 15 s countdown follows:
  **Keep** writes them with `displays.sh save` into `~/.config/hypr/monitors.lua`, and no
  answer (a black screen, say) re-applies the screens as they were (`revert()`).
- `displays.sh apply` runs one `hyprctl eval "hl.monitor({ ... })"` per screen, the ones
  coming on first and the ones going off after, so there is never no screen on. A screen
  going off is parked past the right edge of the others.
- `displays.sh save` writes `monitors.lua` in the shape nwg-displays uses, keeping the lines
  of an existing block it doesn't own (transform, vrr, ...), with the old file as
  `monitors.lua.bak`.

## The one rule that matters

**A rule that turns a screen on says `disabled = false`.** Hyprland (seen on 0.56.2, Lua
config) keeps a screen's earlier `disabled = true` when a later `hl.monitor` for it leaves
the field out: the mode, place and scale change, the screen stays dark. Before this, a
screen turned off from the card could not be turned back on in the same session, and the
countdown's revert could not bring it back either. Changing the scale of a screen that is
on, any number of times, was never affected.

Checked on two real monitors (DP-3 and DP-2): with the field, off and on again twice in a
row; without it, off and never back.

Tests: `tests/display-test/displays_script_test.js` (the script against a fake `hyprctl`),
`display_unit.js` and `service_sim.js` (the maths and the service).
