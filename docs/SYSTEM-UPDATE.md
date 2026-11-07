# Update system (Hyprland config and packages)

**Update now** only replaces the shell's own files (`sekaipop/`). Some versions also need
something outside them: new keybinds or window rules in the Hyprland config, new packages. Until
now that was a line in the changelog ("run install.sh again"). Now the shell says so itself:
**Settings > About / Update** shows the reasons and an **Update system** key, and the About tab
gets its badge.

## How it knows

- `sekaipop/SYSTEM-REV` ships with the files. Line 1 is a whole number, the **system revision**.
  The lines under it are the reasons, one per line, shown on the page.
- `install.sh` records the number it brought, after a clean (not dry) run, in
  `~/.config/sekaipop/system-rev`. No file counts as 0.
- Shipped number above the recorded one means **recommended**: `update-check.sh system` prints
  `system=needed`, plus `shipped=`, `applied=` and `note=` (the reasons joined by `|`).
- Nothing is recommended on a fresh install (install.sh records the number it just installed).
  A user who updates from a version without this feature has no record, so the first version that
  ships a number recommends it once, which is right: they have not run install.sh for it.

## What the key does

It opens a terminal and runs `update-check.sh sysrun`:

- a git checkout runs its own `install.sh`;
- an installed copy (no `install.sh` in it) clones the same repo and branch into a temporary
  folder and runs that one (it needs git, as Update now does).

install.sh asks before it changes anything, backs up a Hyprland config it replaces
(`./install.sh --restore` puts it back), and keeps `~/.config/hypr/custom/`. When the terminal is
closed the shell asks again; if install.sh failed the key stays, so it can be tried again.

## For the developer

Bump `SYSTEM-REV` (and write the reason under it) in the same commit as any change that needs an
install.sh run: a new or changed line in `hypr/`, a new package in `install-deps.sh`, a new
service. Do not bump it for a change in `sekaipop/` alone; Update now covers those. Keep the
reasons short, one line each, and without `|` or `=`.

`ipc` is not needed; to try it, put a higher number in `sekaipop/SYSTEM-REV` of the running shell
and restart it, or delete `~/.config/sekaipop/system-rev`.

Tests: `sh sekaipop/tests/update-test/update_check_test.sh` (system, sysrun) and
`node sekaipop/tests/update-test/update_notify_test.js` (the wiring). The QML was not run in a
live Quickshell.
