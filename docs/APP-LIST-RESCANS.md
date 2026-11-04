# The app list and Quickshell's rescans

How `sekaipop/services/AppSource.qml` keeps its list of apps in step with Quickshell's
`DesktopEntries`, and why it must not simply bind to `DesktopEntries.applications.values`
(issue #128: the shell froze at 100% CPU when a terminal or a video player opened).

## What Quickshell does (0.3.1)

Read from `src/core/desktopentrymonitor.cpp`, `desktopentry.cpp` and `model.hpp`:

- **What starts a rescan.** The monitor watches every application folder
  (`$XDG_DATA_HOME/applications`, then each `$XDG_DATA_DIRS/applications`), their
  subfolders, **and every folder above them up to `/`** (`addPathAndParents`). A file
  created, removed or renamed in any of those starts a full rescan, 100 ms later. So
  `~/.zsh_history` being written (a terminal starting its shell),
  `~/.local/share/recently-used.xbel` being rewritten (a player opening a file from the
  file manager) and much else in `~` or `~/.local/share` all rescan the apps. Opening the
  same player from the Apps screen writes neither, which is why the report found it "so
  specific".
- **What a rescan changes.** Entries are matched to the previous scan by desktop id and
  updated in place, so most apps keep their `DesktopEntry` object. But an id found in
  more than one data folder (a `~/.local/share/applications` override, flatpak exports,
  a folder listed twice in `XDG_DATA_DIRS`) gets a **new** object on every scan and the
  old one is deleted (`deleteLater`).
- **How the model reports it.** `ObjectModel::diffUpdate` moves rows one at a time, and
  each `removeAt` / `insertObject` emits its own `valuesChanged`. A replaced object costs
  two signals. `DesktopEntries.applicationsChanged` is emitted once, after the model is
  complete.

Measured with a throwaway config (one rescan started by touching a file in `~`):

| Data folders | Apps | `valuesChanged` | Objects replaced |
| --- | --- | --- | --- |
| this desktop's own | 242 | 6 | 3 |
| `/usr/share:/usr/share` | 224 | 312 | 156 |

## What AppSource does

- `entries` is a read-only view of `_entries`, which only `refresh()` writes.
- `refresh()` runs once per finished scan (`onApplicationsChanged`, straight away: the
  objects the old list points at are deleted when the event loop next turns) and at
  start. It reads every app's fields once and hands back the **same array** when every
  app is the same object with the same fields, so nothing downstream re-runs. Otherwise
  it rebuilds, and an app that did not change keeps its entry object; only new, replaced
  or edited apps get new ones.
- `sync()` runs when the Apps screen opens. It compares the model's objects with the ones
  the list was built from (no field reads, nothing into C++) and refreshes only if they
  differ, then moves the "Most used" order on (docs/APPS-ORDER.md).

The same rescan with the real `AppSource.qml` in that throwaway config: `main` rebuilt
the list 313 times and held the event loop for 1.35 s; this version rebuilds once, with
a 40 ms worst stall. The real shell also had its Apps grid re-diff every rebuild.

## Checking it

- `node tests/launcher-test/app_source_rescan_test.js` (from `sekaipop/`): the wiring,
  and the real functions against fake entries that count field reads.
- `node tests/launcher-test/rank_unit.js`: the search ranking is unchanged.
- Live: a Quickshell config holding a copy of `AppSource.qml` with stub `SettingsService`,
  `IconCursorService` and `Directories` singletons, run as `XDG_DATA_DIRS=/usr/share:/usr/share
  qs -p <dir>/shell.qml -n`, counting `onEntriesChanged` and the longest gap of a 5 ms
  timer around a `touch ~/x; rm ~/x`. Use a scratch `XDG_DATA_HOME` to add or edit a
  `.desktop` file, never the real one.

## Elsewhere

The dock and the bar call `DesktopEntries.heuristicLookup()` per window class. Those
don't bind to the model's values, so a rescan doesn't re-run them, but anything new that
binds to `DesktopEntries.applications.values` will pay for every row of every rescan.
Listen to `DesktopEntries.applicationsChanged` instead.
