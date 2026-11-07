#!/bin/sh

# The manga reader hides the mouse cursor while it rests.
#
#   reader-cursor.sh on    Hyprland hides a cursor that has not moved for 2 seconds (and shows it
#                          again on the next move): `cursor:inactive_timeout`. The value that was
#                          set before is kept in a file.
#   reader-cursor.sh off   puts that value back.
#
# Why Hyprland and not the reader's own cursor: a Qt app can ask for a blank cursor, but for a
# pointer that is resting nothing makes the compositor take it, so the reader would only hide it
# after you moved.
#
# Same rule as gamemode-state.sh: a Lua Hyprland config ignores `hyprctl keyword`, so
# `hyprctl eval "hl.config({...})"` goes first and `hyprctl keyword` (hyprlang) is the fallback.
# Nothing in the user's config files is edited.
#
# Exit codes:  0 applied   1 hyprctl missing, or Hyprland refused the change   2 bad argument

command -v hyprctl >/dev/null 2>&1 || exit 1

SECONDS_HIDDEN=2
state="${XDG_RUNTIME_DIR:-/tmp}/sekaipop-reader-cursor"

apply() {
    out=$(hyprctl eval "hl.config({ cursor = { inactive_timeout = $1 } })" 2>&1)
    case "$out" in
        ok*|"") return 0 ;;
    esac
    out=$(hyprctl keyword cursor:inactive_timeout "$1" 2>&1)
    [ "$out" = "ok" ]
}

case "$1" in
    on)
        # Keep what was there once: a second "on" (or one left by a crash) must not overwrite it
        # with our own value.
        if [ ! -f "$state" ]; then
            cur=$( { timeout 2 hyprctl getoption cursor:inactive_timeout; timeout 2 hyprctl getoption cursor.inactive_timeout; } 2>/dev/null \
                | sed -nE 's/^[[:space:]]*(int|float): *//p' | head -n1 | cut -d' ' -f1)
            case "$cur" in
                ''|*[!0-9.]*) cur=0 ;;
            esac
            printf '%s\n' "$cur" > "$state"
        fi
        apply "$SECONDS_HIDDEN" || exit 1
        ;;
    off)
        [ -f "$state" ] || exit 0
        prev=$(cat "$state" 2>/dev/null)
        case "$prev" in
            ''|*[!0-9.]*) prev=0 ;;
        esac
        apply "$prev" || exit 1
        rm -f "$state"
        ;;
    *)
        exit 2
        ;;
esac
