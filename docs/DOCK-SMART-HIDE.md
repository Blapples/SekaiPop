# Dock: Smart hide

Settings > Desktop > Dock > Hide: **Smart hide** keeps the dock out while a window is in its
way and brings it back when none is. (Auto-hide keeps it away all the time, until the pointer
reaches its spot; Off keeps it there.) A pinned dock never hides.

## How it knows a window is in the way

Quickshell's own window list has no geometry, so `services/DockService.qml` reads
`hyprctl clients -j` and `hyprctl monitors -j`, and reads them again (60 ms after the last one)
whenever Hyprland reports an event, except the layer and screencast events, which this shell's
own popups fire all the time. `DockService.covers(screen, rect)` says whether a mapped,
not-hidden window on the monitor's visible workspace overlaps `rect`. `Dock.qml` passes
`smartRect`, the strip along its edge where the pill stands.

**The feed only runs while a dock needs it.** Each dock window in Smart hide *holds* it with
`DockService.hold(key, true)` and lets go when it leaves Smart hide or is destroyed. The key is
the dock window's own, from `DockService.newHoldKey("dock")` when it is built, never one two
docks could share. It used to be `dock-<monitor>`: the shell builds the dock twice on a
monitor at startup, the second dock found the key already held and skipped its own claim, and
the first released it on its way out. Nobody held the feed after that, so the window list was
never read again and every window event was ignored, and Smart hide stayed on whatever it had
seen in the first moment. If that first answer came back too late, it saw nothing at all, and
the dock stood over a maximized window until Smart hide was turned off and on (pinning and
unpinning does that) (issue #116).

## At startup

Until the first window and monitor lists are back (`DockService.ready`, asked again every
400 ms), the dock cannot know what is in its way, so it stays away (`smartWaiting`) for at
most 5 s (`startupMs`), and then shows if Hyprland never answered.

## Known limits

- Hyprland reports no event when a floating window is only moved or resized, so the dock
  learns of it at the next event (focus, workspace, another window).

## Tests

`tests/dock-test/smart_hide_startup_test.js` (the startup wait) and
`tests/dock-test/smart_hide_hold_test.js` (the hold: two docks on one monitor, the first
destroyed, the feed stays on).

## Checking it by hand without touching your own session

A nested Hyprland (`Hyprland -c <a minimal hyprland.conf>`, run from inside your session, opens
as a window) with the shell started inside it from a checkout. Use your own copies of the
config and state folders (`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`).
Put no-op stand-ins for `pkill`, `systemctl`, `hypridle`, `gsettings` and `dconf` first on
`PATH`, and point `DBUS_SESSION_BUS_ADDRESS` at nothing, so the second shell cannot restart
your hypridle or write your theme. `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` name the
nested one. `grim` with the nested `WAYLAND_DISPLAY` shows only the nested screen.
