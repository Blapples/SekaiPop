#!/bin/sh

# Helper for LockCanvasService.qml: remembers the Custom lockscreen's layout (which
# widgets, where, and their options), so a shell restart brings it back as you left it.
#
#   lockcanvas-state.sh save <json>   replace the remembered layout with <json>
#   lockcanvas-state.sh load          print the remembered JSON (or nothing at all, if
#                                     the layout has never been changed)
#
# Lives in ${XDG_STATE_HOME:-~/.local/state}/sekaipop/lockcanvas.json -- state, not data,
# the same convention clock-state.sh / todo-state.sh use. Written to a temp file and moved
# into place, so a crash mid-save can't leave half a file. The file is DATA ONLY: the shell
# reads it through LockCanvasModel.js, which drops everything it does not know.

mode="$1"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop"
file="$dir/lockcanvas.json"

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
