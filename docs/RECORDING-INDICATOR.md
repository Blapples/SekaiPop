# The recording indicator

While the screen is being recorded, a red **● REC 01:23** pill sits in the top-right corner
of every screen, just inside the bar (`sekaipop/modules/sekai/onScreenDisplay/RecordingIndicator.qml`).
The dot pulses, the timer counts from when the recording started, and clicking the pill stops
the recording with SIGINT, which is what makes `wf-recorder` finish the file properly.

It knows about two kinds of recording:

- **The shell's own**: the region picker's Record and Record with sound
  (`RegionService.recording`).
- **Any other recorder**: `wf-recorder`, `wl-screenrec` and `gpu-screen-recorder`, found with
  `pgrep -x` every 2 s. The kernel keeps only the first 15 characters of a process name, so
  gpu-screen-recorder is looked for as `gpu-screen-reco`.

## Turning it down or off

**Settings > General > Screen region > Recording indicator** (`region.recIndicator`):

| Choice | Setting | The pill shows for |
|---|---|---|
| Any recorder (default) | `all` | the shell's own recordings and the other recorders above |
| Only the shell's | `own` | the region picker's recordings only; other recorders aren't looked for |
| Off | `off` | nothing |

`own` is for a recorder that never stops. gpu-screen-recorder's replay mode (the "save the
last 30 seconds" setup) runs all the time, so with `all` the pill never goes away (issue
[#166](https://github.com/Blapples/SekaiPop/issues/166)). With `own`, clicking the pill during
one of the shell's recordings stops only that one, and leaves the replay buffer running.

From a shell: `qs -c sekaipop ipc call options set region.recIndicator own` (or `all`, `off`).

The `pgrep` poll runs only with `all`, so `own` and `off` also stop that check every 2 s.

## Checking it

`node sekaipop/tests/recording-test/indicator_setting_test.js` is the source check. By hand:
run anything named `wf-recorder` (`cp /usr/bin/sleep /tmp/wf-recorder && /tmp/wf-recorder 60`)
and switch the setting. The pill's window is the `sekaipop-recording` layer in
`hyprctl layers` while it is up.
