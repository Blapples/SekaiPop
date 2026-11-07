# Phone mirror

Your Android phone, live, on a phone at the left side of the screen. Click, drag and scroll on
it like on the real one; click it once and your keyboard types into it.

    qs -c sekaipop ipc call phonemirror toggle        (SUPER + SHIFT + Y)
    qs -c sekaipop ipc call phonemirror show | hide | status
    qs -c sekaipop ipc call phonemirror start | stop | restart   (scrcpy on / off / again)
    qs -c sekaipop ipc call phonemirror connect 192.168.1.20:5555
    qs -c sekaipop ipc call phonemirror disconnect
    qs -c sekaipop ipc call phonemirror detach        (the phone in a normal scrcpy window)
    qs -c sekaipop ipc call phonemirror key home      (back, home, recents, power, volumeUp, volumeDown)

It is a port of p3drovfx's illogical-impulse scrcpy phone mirror (the Phone tab of its sidebar),
without KDE Connect.

## What you need

- `scrcpy` and `adb`: `sudo pacman -S scrcpy android-tools` (`check-deps.sh` lists them).
- On the phone: Settings > About phone > tap Build number 7 times > Developer options > USB
  debugging. Plug it in and accept the question on the phone.
- Hyprland, with either kind of config: a Lua one (`hyprland.lua`) or a plain `hyprland.conf`. The
  shell sees which and places the window with the matching commands. The window rules are optional:
  the shell makes the window float itself. `hypr/hyprland/rules.lua` has them for the Lua config;
  they only stop it flashing in the tiling layout when it opens.

For Wi-Fi: Developer options > Wireless debugging > note the IP address and port, then
`ipc call phonemirror connect <ip>:<port>` (or type it in Settings > Quick > Phone mirror). The
address is kept and tried again each time the phone opens.

## Start and stop

Showing the panel and running scrcpy are separate. The first key in the panel's header is Start /
Stop (a play or a stop, lit while scrcpy is on); `ipc call phonemirror start | stop` does the same
from a keybind. Stop ends the mirror at once, so the phone stops encoding video, and keeps it off
(the panel can stay up, showing a Start key) until you press Start. Restart starts it again. With
Settings > Quick > Phone mirror > Start when opened off, the panel always comes up stopped.

## If clicks go to what is behind the phone

The shell opens a click-through hole over the screen only after Hyprland says the scrcpy window
is floating and the right size. If it is not, the screen says "Cannot reach the phone's window".
It also checks the window's position, not only its size, and keeps the hole shut when Hyprland
does not say where the window is. The message says what failed. If it says the window is not
floating, add the `sekai-phone-*` window rules to your Hyprland config, `hyprctl reload`, and
press Try again.

## If it stalls

The phone's screen says which step it is waiting on. `qs -c sekaipop log | grep PhoneMirror` shows
what happened, in order: the manager's events, the window appearing, where it was placed, where
Hyprland says it is.

## It keeps the picture

Changing workspace, or anything that opens a layer (the Quick Panel's phone, a popup), does not
interrupt the mirror. The window is pinned, so it goes along; the shell only looks, a moment
later, whether Hyprland still has it where it was put, and places it again only if not. The
picture is not dropped for that look. The options (sound, notch, address and the rest of
`phoneMirror.*`) are global: a desktop preset never reads or writes them.

## How it works

Wayland has no window embedding, so the picture and the touches are carried separately.

- **The picture** is a `ScreencopyView` of scrcpy's own window, drawn inside the phone's screen
  like any other item. Nothing is copied through main memory, and there is no v4l2 loopback.
- **The touches** go to the real scrcpy window. It waits off the side of every monitor and, once
  the panel has stopped sliding, is moved and sized to sit exactly under the screen, pinned. The
  panel cuts that rectangle out of its input region, so a click falls through to scrcpy at the
  very place it was aimed. Multi-touch, scrolling, the keyboard and the clipboard are scrcpy's own.
- The window is only under the screen while it is fully covered. While the panel slides, or is
  away, it is parked off screen.
- `scripts/phone/scrcpy_session_manager.py` runs scrcpy. It waits until the phone answers,
  swipes a lock screen away, and, for a PIN, opens a small plain mirror to type it in (Android
  blanks the PIN pad, so it stays black; the input still arrives). It ends the mirror when the
  shell stops saying it still wants it.

## Options

Settings > Quick > Phone mirror, or `ipc call options set phoneMirror.<name> <value>`:
`edge` (left | right), `autoStart` (opening the panel starts scrcpy), `notch`, `height` (percent of the monitor), `audio`, `stayAwake`,
`turnScreenOff`, `autoUnlock`, `keyboard` (uhid | sdk), `clipboardSync`, `maxFps`, `bitRate`,
`keepWarm` (seconds the mirror stays up after the panel closes), `serial` (which phone, with
more than one), `address` (a phone on Wi-Fi).

## What it does not do

App windows on a virtual display (p3dro's "App mode"), recording, and KDE Connect are not part
of the port. The phone is shown upright; a phone turned sideways keeps the frame it had until
`restart`.

Test: `tests/phone-mirror-test/mirror_unit.js`.
