# Custom lockscreen (LockCanvas)

Settings -> General -> Launcher & lock -> **Lockscreen style -> Custom** shows a lockscreen
you arrange yourself: your wallpaper, the widgets you picked, and the password block.

The layout is saved as JSON, and you arrange it in the **lockscreen editor** (below), which works
like Edit Desktop: drag, resize, options, add and remove. You can still edit
`~/.local/state/sekaipop/lockcanvas.json` by hand.

```
qs -c sekaipop ipc call options set lock.style custom
qs -c sekaipop ipc call lockedit toggle         # the editor (also: open / close)
qs -c sekaipop ipc call lockcanvas reset        # back to the first layout
```

## The editor

Open it from **Settings -> General -> Launcher & lock -> Edit lockscreen** (shown while the style is
Custom), from **right-click the desktop -> Edit lockscreen**, or with the IPC call above.

The lockscreen is drawn as a framed card on a dark stage, the way Edit Desktop draws the desktop. The
card is the whole screen at a smaller scale, and the widgets on it are the lockscreen's own files, so
what you see is what you get. It opens the way Edit Desktop does: the card starts as the whole screen and
shrinks into its place (a little past it, then settling back; 560 ms in, 360 ms out, the same curves as
Edit Desktop), the frame grows round it, the stage fades in behind and the shelf slides up from the
bottom. Done runs it backwards. The frame's rings are drawn over the card, which is what rounds the
card's corners.

| do this | to get this |
|---|---|
| press and drag a widget | move it. It snaps to the middle of the screen and to the other widgets (a mint line shows it); hold **Shift** to move freely |
| drag the corner knob of the selected widget, or turn the wheel over it | resize (50% to 250%); close to 100% it sticks there |
| right click a widget, or press **Delete** | remove it |
| click a key on the shelf | add that widget in the middle (or select it, if it can only be there once and already is) |
| press and drag a key off the shelf onto the card | add it where you let go |
| click a widget | its options appear on the shelf: SIZE, and one row per option |
| the **password block** | drag it up and down and a little sideways; the range it may go in is shown while you drag. It can not be removed or resized |
| arrow keys (Shift: 10 times as far) | nudge the selection |
| **+** and **-** | resize the selection (Shift: bigger steps) |
| **Tab** / **Shift+Tab** | select the next / previous (the password block included) |
| **Ctrl+Z**, **Ctrl+Shift+Z** or **Ctrl+Y** | undo, redo (also the two keys on the shelf) |
| **RESET** on the shelf | back to the first layout (can be undone) |
| **THIS** on the shelf (with more than one monitor) | give this monitor a layout of its own; press again to use the shared one |
| **Esc** | let go of the selection, then leave. **DONE** leaves too |

Every change is saved as you make it. The image widget's **folder** key opens a file chooser (the same
one as the avatar picker); the editor steps aside while it is open. If the style is not Custom the card
says so, with a key that switches it.

Safety, on top of the rules below: **the editor is never part of the lock.** It is its own window in your
session (`modules/sekai/lockEditor`), nothing in `modules/sekai/lock` mentions it, and it closes by itself
if the session locks. The password block on the card is a stand-in, not the real one: the editor never
touches the password or the lock's context. Everything it saves goes through `LockCanvasModel.js` like a
hand-edited file does.

## Widgets

| id | shows | options |
|---|---|---|
| `clock` | the time, big | `format`: auto / 12h / 24h |
| `date` | today's date | `style`: long / short |
| `user` | avatar, name, "Locked since" | `since` |
| `greeting` | "Good morning" / "Good afternoon" / "Good evening" / "Good night" by the hour | `name`: add your name |
| `weather` | icon, temperature, condition | `condition`, `place` (off by default) |
| `sun` | today's sunrise and sunset (the weather's reading) | none |
| `battery` | icon and percentage (laptops only) | `percent` |
| `media` | title, artist, prev / play-pause / next | `controls` |
| `lyrics` | the line being sung and the next one | none |
| `timer` | the dock's timer, stopwatch or pomodoro clock, while one runs | `label`: what it is |
| `notifications` | how many notifications are waiting (a number only; **private**) | none |
| `event` | your next calendar event or deadline (**private**: a count until `details`) | `details` (off by default) |
| `todo` | your to-do list (**private**: "3 tasks left" until `details`) | `details` (off by default) |
| `countdown` | days to (or since) a day you pick; up to four | `label` (40 chars), `date` (`YYYY-MM-DD`) |
| `text` | a line of your own words | `text` (120 chars), `size` |
| `image` | a picture of yours | `path` (absolute path), `shape` |

### The information widgets

`timer`, `notifications`, `event`, `todo`, `countdown`, `greeting` and `sun` are new. They only
**read** what the shell already knows and draw it; none of them changes anything (no ticking off a
task, no dismissing a notification, no starting a timer), and each one draws nothing when it has
nothing to say (no timer running, no tasks, no notifications, no reading yet). The editor shows a
sample of each so you can place it.

- **Private ones.** The notifications, event and to-do widgets are marked *private*
  (`LockCanvasModel.js`): they show a **count** by default (`3 notifications`, `2 events today` or
  `Next: in 3 days`, `3 tasks left`) and nothing you or anyone else wrote. Turn **Details** on for the
  event and to-do widgets to show the next entry's words (and for an event, when it is). The
  notifications widget has no details at all: what a message says, who sent it and which app it
  came from are never on the lockscreen. (`services/NotificationCount.qml` holds just the number;
  `shell.qml` keeps it equal to the notification daemon's count.)
- **Where the data is from.** `timer` is `TimerService` (the dock's), `todo` is `TodoService`
  (the desktop To-Do widget's), `event` is `CalendarCardService` (the desktop Calendar card's),
  `sun` and `weather` are the same Open-Meteo reading (they start from `WeatherCache`, so they are
  there the moment the lock is).
- **Countdown.** The date goes in the Date box in the editor's options; it has to be a real day written
  `YYYY-MM-DD` (`2026-12-25`), anything else is "no date yet" and the widget draws nothing on the
  lock. A past date counts the days *since*. Put up to four on the screen, each with its own label.
- The notifications, event, to-do, timer and countdown widgets share one capsule look
  (`LockInfoCapsule.qml`: an icon, a main line and a smaller second line).

## The saved file

```json
{ "v": 1, "boards": { "*": { "core": { "x": 0.5, "y": 0.86 },
  "items": [ { "uid": "clock-1", "kind": "clock", "x": 0.5, "y": 0.2, "scale": 1,
               "options": { "format": "auto" } } ] } } }
```

The small capsules (`user`, `date`, `weather`, `battery`, `media`) are all the same height, the User
widget's (116 px at 1080 p, `LockWidget.capH`), with the same padding at their ends and the same type
sizes (40 px for the main line, 22 px for the second), so side by side they read as one family.

The `lyrics` widget used to be an option of `media`. It is its own widget now so it can go anywhere. It
is not in the first layout: **putting it on the lockscreen is what switches it on**, since it asks the
lyrics providers for the song (once per track, only while a player is running). It does not wait for
Settings -> General -> Lockscreen -> Lyrics, which is the Gacha look's switch. A saved `lyrics` option
on a `media` widget is dropped when the layout is read; add the Lyrics widget to get the line back. The
capsule opens when a line starts and closes when there are none; the editor shows a sample line.

`x` and `y` are where the widget's centre is, as a fraction of the screen. `"*"` is the board
every monitor uses; a monitor name (`"DP-1"`) gives that monitor its own.
`core` is the password block.

## Safety rules (the code keeps them; tests/lock-canvas-test checks them)

1. **The file is data only.** `LockCanvasModel.js` drops every widget it does not know, clamps
   every number, checks every option, and caps the count. A widget is a name that maps to a QML
   file the shell already contains; nothing in the file is run or loaded as code.
2. **The password block cannot be lost.** It is built every time, above all widgets, and kept
   inside the screen (it can move a little, never hidden or scaled). A damaged file gives a plainer
   screen, never one without a way to unlock.
3. **Widgets never get keys.** The canvas catches every key for the password (the same handler as
   the Gacha look). Widgets have no text fields and never take the focus, so nothing you type can
   land in one.
4. **Widgets only draw.** The one exception is the media keys, which call the player's own MPRIS
   controls. (The Lyrics widget asks the lyrics providers for the words, through `LyricsService`, and
   only once it is placed.) No widget starts a program, opens a link or opens a window.
5. **No network for pictures.** The media widget shows no cover art (players give web addresses).
   The image widget reads local picture files only.
6. **A broken widget is skipped.** Each one is in its own Loader; the rest still draw.
7. **No plugin widgets on the lockscreen.** Plugins run with full shell rights (docs/PLUGINS.md).
   This may come later as an opt-in with a consent screen.
8. **Private widgets are masked by default.** The notifications, next event and to-do widgets show
   counts, not details, until you turn **Details** on (notifications never have details).

## Files

- `modules/common/functions/LockCanvasModel.js` the rules (pure JS, tested under node)
- `services/LockCanvasService.qml` loads and saves the layout, and holds / wears it for desktop presets (`presetPart`, `wearPreset`)
- `scripts/state/lockcanvas-state.sh` the file on disk
- `modules/sekai/lock/LockCanvas.qml` the look; `LockCore.qml` the password block
- `modules/sekai/lock/Lock*Widget.qml` the widgets; `LockWidget.qml` is their base; `LockLyrics.qml` is the
  lyrics capsule the Lyrics widget (and the Gacha look) uses; `LockInfoCapsule.qml` is the capsule the
  information widgets share
- `services/NotificationCount.qml` the notification count the lockscreen can read (a number only)
- `services/LockEditService.qml` the editor's state: open / close, the board being edited, selection,
  undo, saving (`ipc call lockedit`)
- `modules/sekai/lockEditor/` the editor: `LockEditor.qml` (window), `LockEditStage.qml` (card, keys),
  `LockEditSlot.qml` (a widget on the card), `LockEditCore.qml` (the password block's stand-in),
  `LockEditShelf.qml`, `LockEditOptions.qml`, `LockEditFrame.qml`, `LockEditBackdrop.qml`
- `modules/common/functions/LockEditMath.js` the editor's maths (card fit, snapping, sizing, undo; node-tested)
- `scripts/images/pick-lock-picture.sh` the file chooser for the image widget (does not copy the picture)
- `tests/lock-edit-test/` the editor's tests (`lock_edit_unit.js`, `lock_edit_wiring_test.js`)
- `tests/preset-lock-test/` the layout inside presets (`preset_lock_unit.js`)

## Presets

Each desktop preset (Edit Desktop -> PRESETS) holds its own lockscreen: every board (the shared one and
each monitor's own) and the list of lockscreen widgets the shell had when it was saved (`lockCanvas` in the
preset's file). Wearing a preset puts that layout on, so two presets can have two different lockscreens.
Every change you make in the lockscreen editor (moving, resizing, adding, removing or changing a widget, Reset)
is **saved into the preset you are in** a moment later, with no need to save the preset again: the one you last
saved or wore (the one the sticky notes follow, kept across restarts). In no preset, nothing extra is saved.

A preset wears what it holds, like the desktop widgets and the bar pills:

- A widget that is **not in the preset's list did not exist for it, so it is not shown**, whatever the
  boards say (`LockCanvasModel.wornModel`). A widget added to the shell later is therefore off for every
  preset saved before it, and on for the ones saved after (nothing to do per widget).
- A preset saved **before layouts were part of one** has no layout to put on. Wearing it leaves your
  layout where it is, but keeps only the widgets that existed then (`LockCanvasModel.LEGACY_KINDS`: clock, date,
  user, weather, battery, media, lyrics, text, image); Greeting, Sun, Timer, Notifications, Next event, To-do and
  Countdown, and anything newer, come off the boards. That list is fixed, never extend it. Wearing the preset
  you had before (Undo on the PRESETS tab) brings them back.
- The password block is never touched by either, and an open lockscreen editor closes when a preset
  replaces the layout (so it can not save its copy back over it).

The "wearing this one" tick compares the layout too, but not for a preset saved before it was held.
