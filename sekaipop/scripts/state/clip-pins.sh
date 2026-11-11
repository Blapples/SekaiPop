#!/bin/sh

# Helper for ExtrasSource.qml: the clipboard's pinned entries.
#
#   clip-pins.sh pin <cliphist-id> <preview>   copy that history entry into a new pin
#   clip-pins.sh list                          print "<pin>\t<preview>", newest pin first
#   clip-pins.sh show <pin>                    text: "p<pin>\n<the text>";
#                                              picture: the path of a viewable copy
#   clip-pins.sh copy <pin>                    put the pin back on the clipboard
#   clip-pins.sh unpin <pin>                   forget it
#
# A pin is a copy of the entry's bytes, not a reference to cliphist's id, so it
# survives everything that empties the history: cliphist's own size cap, "Clear
# history" (cliphist wipe), and deleting the entry. It lives in
# ${XDG_STATE_HOME:-~/.local/state}/sekaipop/clip-pins/ -- state, the same place
# extras-state.sh and pinned-apps-state.sh keep theirs -- as <pin>.data (the bytes
# exactly as copied) and <pin>.preview (cliphist's one-line preview, which is also
# what tells a picture from text: "[[ binary data ... ]]"). <pin> is the time it
# was made, in milliseconds, so newest first is a plain reverse sort.

mode="$1"
shift
dir="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop/clip-pins"

# Pin names are digits only: nothing from the caller ends up in a path otherwise.
valid() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ -f "$dir/$1.data" ]
}

is_image() {
    case "$(cat "$dir/$1.preview" 2>/dev/null)" in
        '[[ binary data'* | '[[binary data'*) return 0 ;;
    esac
    return 1
}

case "$mode" in
    pin)
        id="$1"
        preview="$2"
        case "$id" in '' | *[!0-9]*) exit 2 ;; esac
        mkdir -p "$dir" || exit 1
        pin=$(date +%s%3N)
        # Two pins in the same millisecond (a double press): take the next free name.
        while [ -e "$dir/$pin.data" ]; do pin=$((pin + 1)); done
        cliphist decode "$id" > "$dir/$pin.tmp" && [ -s "$dir/$pin.tmp" ] || { rm -f "$dir/$pin.tmp"; exit 1; }
        # One line, whatever the caller passed: list prints it between a tab and a newline.
        printf '%s' "$preview" | tr '\t\n\r' '   ' > "$dir/$pin.preview"
        mv "$dir/$pin.tmp" "$dir/$pin.data"
        printf '%s\n' "$pin"
        ;;
    list)
        [ -d "$dir" ] || exit 0
        for f in "$dir"/*.data; do
            [ -e "$f" ] || continue
            p=${f##*/}
            p=${p%.data}
            printf '%s\t%s\n' "$p" "$(cat "$dir/$p.preview" 2>/dev/null)"
        done | sort -t "$(printf '\t')" -k1,1nr
        ;;
    show)
        valid "$1" || exit 1
        if ! is_image "$1"; then
            printf 'p%s\n' "$1"
            cat "$dir/$1.data"
            exit 0
        fi
        # The same viewable copy the history's pictures get (ExtrasSource
        # clipImageScript): in the runtime dir, turned into a png when Qt cannot read it.
        d="${XDG_RUNTIME_DIR:-/tmp}"
        rm -f "$d"/sekaipop-clip-*
        f="$d/sekaipop-clip-p$1"
        cp "$dir/$1.data" "$f" || exit 1
        t=$(file -b --mime-type "$f" 2>/dev/null)
        case "$t" in
            image/png | image/jpeg | image/gif | image/bmp) ;;
            *)
                for c in magick convert; do
                    if command -v "$c" > /dev/null 2>&1 && "$c" "$f" "png:$f.png" 2> /dev/null && [ -s "$f.png" ]; then
                        mv -f "$f.png" "$f"
                        break
                    fi
                done
                ;;
        esac
        rm -f "$f.png"
        printf '%s' "$f"
        ;;
    copy)
        valid "$1" || exit 1
        if is_image "$1"; then
            t=$(file -b --mime-type "$dir/$1.data" 2>/dev/null)
            case "$t" in image/*) ;; *) t=image/png ;; esac
            wl-copy --type "$t" < "$dir/$1.data"
        else
            wl-copy < "$dir/$1.data"
        fi
        ;;
    unpin)
        valid "$1" || exit 0
        rm -f "$dir/$1.data" "$dir/$1.preview"
        ;;
    *)
        echo "usage: $0 pin <cliphist-id> <preview>|list|show <pin>|copy <pin>|unpin <pin>" >&2
        exit 2
        ;;
esac
