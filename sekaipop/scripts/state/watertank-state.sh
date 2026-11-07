#!/bin/sh

# Helper for WaterTankService.qml: remembers the desktop Water Tank widget's position,
# monitor, size, daily goal and the glasses you have had (today and the last days), so a
# shell restart brings it back exactly as you left it.
#
#   watertank-state.sh save <json>   replace the remembered state with <json>
#   watertank-state.sh load          print the remembered JSON (or nothing at all, if the
#                                    widget has never been used)
#
# Lives in ${XDG_STATE_HOME:-~/.local/state}/sekaipop/watertank.json: state, not data, same
# convention weathercard-state.sh / todo-state.sh use. Written to a temp file and moved into
# place, so a crash mid-save can't leave half a file.

mode="$1"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop"
file="$dir/watertank.json"

case "$mode" in
    save)
        mkdir -p "$dir" || exit 1
        printf '%s\n' "$2" > "$file.tmp" || exit 1
        mv "$file.tmp" "$file"
        ;;
    load)
        [ -f "$file" ] && cat "$file"
        exit 0
        ;;
    *)
        echo "usage: $0 save <json>|load" >&2
        exit 2
        ;;
esac
