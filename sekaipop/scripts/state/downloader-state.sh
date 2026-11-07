#!/bin/sh

# Helper for DownloaderService.qml: remembers the desktop Downloader widget's position,
# monitor, size, options, and the downloads that finished, so a shell restart brings it back
# exactly as you left it.
#
#   downloader-state.sh save      replace the remembered state with the JSON in $SEKAI_DL_STATE
#   downloader-state.sh load      print the remembered JSON (or nothing at all, if the widget has
#                                 never been used)
#
# The JSON arrives in the environment, not on the command line: it can hold a cobalt API key,
# and a command line can be read by every program on the machine.
#
# Lives in ${XDG_STATE_HOME:-~/.local/state}/sekaipop/downloader.json: state, not data, same
# convention watertank-state.sh / todo-state.sh use. Only this user can read it (mode 600),
# because of that key. Written to a temp file and moved into place, so a crash mid-save can't
# leave half a file.

mode="$1"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop"
file="$dir/downloader.json"

case "$mode" in
    save)
        mkdir -p "$dir" || exit 1
        umask 077
        printf '%s\n' "$SEKAI_DL_STATE" > "$file.tmp" || exit 1
        mv "$file.tmp" "$file"
        ;;
    load)
        [ -f "$file" ] && cat "$file"
        exit 0
        ;;
    *)
        echo "usage: $0 save|load" >&2
        exit 2
        ;;
esac
