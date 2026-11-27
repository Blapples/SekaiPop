#!/bin/sh

# Helper for QuickSource.qml's Keep Awake tile.
#
#   keep-awake-state.sh restore    kill any leftover Keep Awake inhibitor,
#                                  then print the saved mode: "session",
#                                  "always" or nothing
#   keep-awake-state.sh save off|session|always
#
# "session": kept in ${XDG_RUNTIME_DIR:-/tmp}/sekaipop/keep-awake (tmpfs), so
# a reload keeps it but logging out or rebooting forgets it.
# "always": also written to ${XDG_STATE_HOME:-~/.local/state}/sekaipop/keep-awake,
# which survives a reboot, until it is turned off. "off" removes both.
# An old "on" in the runtime file is treated as "session".

mode="$1"
rdir="${XDG_RUNTIME_DIR:-/tmp}/sekaipop"
rfile="$rdir/keep-awake"
sdir="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop"
sfile="$sdir/keep-awake"

case "$mode" in
    restore)
        pkill -f 'sekaipop-keep-awak[e]' 2>/dev/null
        if [ -f "$rfile" ]; then
            cat "$rfile"
        elif [ -f "$sfile" ]; then
            echo always
        fi
        exit 0
        ;;
    save)
        case "$2" in
            session|always|off) ;;
            *) echo "usage: $0 save off|session|always" >&2; exit 2 ;;
        esac
        mkdir -p "$rdir" || exit 1
        printf '%s\n' "$2" > "$rfile.tmp" || exit 1
        mv "$rfile.tmp" "$rfile"
        if [ "$2" = "always" ]; then
            mkdir -p "$sdir" || exit 1
            printf 'always\n' > "$sfile.tmp" || exit 1
            mv "$sfile.tmp" "$sfile"
        else
            rm -f "$sfile"
        fi
        ;;
    *)
        echo "usage: $0 restore|save off|session|always" >&2
        exit 2
        ;;
esac