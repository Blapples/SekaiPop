# foot's colours and its section names

Settings > Desktop > App colours > foot writes the theme's colours to
`~/.config/foot/sekaipop-colors.ini` and puts `include=` to it at the top of
`~/.config/foot/foot.ini` (`sekaipop/scripts/theming/app-theme.sh`, `foot_apply`). Revert
removes both.

## Which section the colours go in

foot changed the name of its colours section:

| foot | colours section | what it does with the other name |
|---|---|---|
| before 1.26 | `[colors]` (and `[colors2]`, the second theme) | `[colors-dark]` is an error |
| 1.26 | `[colors-dark]` and `[colors-light]` | `[colors]` still read, with a warning |
| later (1.28 here) | `[colors-dark]` and `[colors-light]` | `[colors]` is an error: `invalid section name: colors` |

A file with only `[colors]` made every new foot window print that error, and editing the file
by hand didn't last, because it is rewritten with each theme change (issue
[#158](https://github.com/Blapples/SekaiPop/issues/158)). No one file works for every foot,
so `foot_sections` reads `foot --version` each time the colours are written:

- **1.26 or later**: the same colours under both `[colors-dark]` and `[colors-light]`. foot
  uses one or the other (by `initial-color-theme`, and the dark / light switch), and with
  both the same the theme shows whichever it is on.
- **Older**: `[colors]`, as before.
- **No foot on PATH** (only its config folder), or a version line that can't be read: the
  current names.

## Updating foot

The file is only rewritten when the colours are applied (a theme or wallpaper change, or
turning foot on). After updating foot past 1.26 with an old file still in place, the next
theme change rewrites it; until then, turning foot off and on again in App colours does it at
once.

## Checking it

`sh sekaipop/tests/app-theme-test/foot_sections_test.sh` runs the real script against a
stand-in `foot` that prints a version line (1.26, 2.0, 1.25, 1.9, garbage, none). With a real
foot, `foot -c ~/.config/foot/foot.ini --check-config` says whether the config is valid.
