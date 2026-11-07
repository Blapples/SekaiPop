#!/bin/sh

# Helper for ScreenTimeService.qml: remembers how long the screen has been in use today, which
# apps it went to, and the totals of the last days, so a shell restart carries on where it left
# off.
#
#   screentime-state.sh save <json>   replace the remembered state with <json>
#   screentime-state.sh load          print the remembered JSON (or nothing at all, if the pill
#                                     has never counted anything)
#
# Lives in ${XDG_STATE_HOME:-~/.local/state}/sekaipop/screentime.json: state, not data, same
# convention watertank-state.sh / weathercard-state.sh use. Written to a temp file and moved into
# place, so a crash mid-save can't leave half a file.

mode="$1"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop"
file="$dir/screentime.json"

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
