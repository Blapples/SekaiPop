#!/bin/sh

# Helper for DesktopPresetService.qml: keeps the desktop presets (a saved
# "whole look": theme, bar, widgets, wallpaper, Quick Panel buttons and the
# Settings Panel's switches) as one JSON file each.
#
#   preset-state.sh all                 print every preset, one per line:
#                                       "<name><TAB><json on one line>"
#                                       (nothing at all if there are none),
#                                       then the undo slots, if there are any:
#                                       ".previous<TAB><json>" and
#                                       ".trash/<name><TAB><json>",
#                                       ".trash/.notes<TAB><json>" and
#                                       ".trash/.at<TAB><seconds>" (see below)
#   preset-state.sh save <name> <json> [avatar|-] [banner|-] [phone|-] [frame file...]
#                                       write (or replace) a preset; the three
#                                       optional paths are the pictures
#                                       currently worn as avatar, banner and
#                                       the phone's wallpaper ("-" = none),
#                                       copied in next to it; the rest are the
#                                       pictures the Custom Image frames show,
#                                       copied into <name>.frames/
#   preset-state.sh restore-frames <name> <file>...
#                                       put those frame pictures of a preset
#                                       back in the Custom Image data folder
#                                       (one already there is left alone) and
#                                       print the full path of each one that
#                                       is there afterwards
#   preset-state.sh restore <name> <kind> <file> <as> [<kind> <file> <as>]...
#                                       copy a preset's avatar / banner / phone
#                                       picture back
#                                       into the data folder as <as>, the way
#                                       pick-image.sh would have put it there,
#                                       and print "<kind> <path>" for each
#   preset-state.sh rename <old> <new> <json>
#                                       give a preset another name: <json> (the
#                                       preset with its new name inside) is
#                                       written as <new>, the pictures folder
#                                       moves with it, <old> goes away. Refused
#                                       (exit 3) when <new> is another preset's
#                                       name; exit 1 when <old> isn't there
#   preset-state.sh delete <name>       remove a preset (and its pictures)
#   preset-state.sh trash <name> [notes json]
#                                       move a preset (and its pictures) into
#                                       .trash/, in place of the one deleted
#                                       before it; the notes json is kept
#                                       there too (its sticky notes), and the
#                                       time it was deleted (.trash/.at)
#   preset-state.sh purge-trash <secs>  empty .trash/ if it is that old (or
#                                       has no time: it can't say)
#   preset-state.sh untrash <name>      put the preset in .trash/ back (the
#                                       service gives its notes back itself).
#                                       Exit 3 when another preset has its
#                                       name now, 1 when it isn't there
#   preset-state.sh exists <path>...    print the paths that are real files,
#                                       one per line (a preset applies a
#                                       wallpaper only if its file is there)
#
# Lives in ${XDG_CONFIG_HOME:-~/.config}/sekaipop/presets/<name>.json: a preset
# is something the user made and keeps, so it sits with the config. Presets
# saved by an older version in ${XDG_STATE_HOME:-~/.local/state}/sekaipop/presets/
# are moved here (the whole folder, pictures included) the first time this runs.
# Copy the folder to take your presets to another machine; the wallpaper
# paths inside are plain paths, so keep the pictures where they were.
#
# The avatar, banner and phone picture are different: pick-image.sh throws the old
# picture away whenever a new one is picked, so a preset keeps its OWN copy, in
# <name>.images/avatar.<ext>, banner.<ext> and phone.<ext> beside <name>.json. Those travel
# with the folder. "restore" puts a copy back in the data folder
# (${XDG_DATA_HOME:-~/.local/share}/sekaipop/, pick-image.sh's folder) and drops
# the picture of that kind that was there, exactly like a fresh pick (including
# scaling a very big one down, see shrink-image.sh).
#
# The Custom Image frames' pictures work the same way, for the same reason (the shell
# deletes a picture's file when its frame is removed): <name>.frames/img-<time>-<pid>.<ext>,
# the file names the widget gave them. They travel with the folder too.
#
# Undo (DesktopPresetService's undoWear / undoRemove). Wearing a preset saves
# the look it replaces first, as the hidden preset ".previous" (pictures and
# all, with "save"), and Undo wears that back: it is renamed ".undone" first
# and worn from there, so the look being undone can take ".previous" over
# (Undo again = Redo). Deleting moves the preset into .trash/ for ten minutes
# (the service purges it after that, or at the next start) instead of
# removing it; only the last one deleted is kept. Hidden = a leading dot, so
# "all" never lists them as presets and a name typed in the shell can never be
# one (the service strips leading dots).
#
# The name becomes the file name, so a name with a slash, a leading dot or
# nothing at all is refused (the service cleans names up before it gets here),
# except the two undo slots above.
# Writes go to a temp file and are moved into place, so a crash can't leave
# half a preset.

mode="$1"
dir="${XDG_CONFIG_HOME:-$HOME/.config}/sekaipop/presets"
old="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop/presets"
here=$(cd "$(dirname "$0")" && pwd)

# One-time move from the old place: only when there is no presets folder here
# yet, so nothing already in the new place is ever overwritten.
if [ ! -d "$dir" ] && [ -d "$old" ]; then
    mkdir -p "$(dirname "$dir")" && mv -- "$old" "$dir"
fi

bad_name() {
    case "$1" in
        .previous|.undone) return 1 ;;
        ''|.*|*/*) return 0 ;;
    esac
    return 1
}

# keep_image <kind> <source path|-> <folder>: copy one worn picture in as
# <folder>/<kind>.<ext> (the extension lower-cased, as pick-image.sh does).
keep_image() {
    [ "$2" != "-" ] && [ -f "$2" ] || return 0
    b=$(basename -- "$2")
    case "$b" in
        *.*) ext=".$(printf '%s' "${b##*.}" | tr 'A-Z' 'a-z')" ;;
        *) ext="" ;;
    esac
    cp -- "$2" "$3/$1$ext"
}

# keep_frames <folder> <the save command's own arguments>: copy the Custom Image
# pictures that are listed after the avatar / banner / phone into <folder> (built beside
# it and swapped in; no pictures at all leaves no folder). Only the widget's own
# copies (img-* in its data folder) are taken.
keep_frames() {
    out="$1"
    # <folder>, then save, <name>, <json>, avatar, banner, phone.
    if [ $# -ge 7 ]; then shift 7; else set --; fi
    src="${XDG_DATA_HOME:-$HOME/.local/share}/sekaipop/custom-images"
    rm -rf -- "$out.tmp"
    mkdir -p "$out.tmp" || return 1
    for f in "$@"; do
        case "$f" in
            "$src"/img-*) ;;
            *) continue ;;
        esac
        [ -f "$f" ] && cp -- "$f" "$out.tmp/$(basename -- "$f")"
    done
    rm -rf -- "$out"
    if [ -n "$(ls -A "$out.tmp")" ]; then
        mv "$out.tmp" "$out"
    else
        rmdir "$out.tmp"
    fi
    return 0
}

# undo_rename <old> <new>: put a half-renamed preset's folders back.
undo_rename() {
    [ "$1" != "$2" ] || return 0
    [ -d "$dir/$2.images" ] && mv -- "$dir/$2.images" "$dir/$1.images"
    [ -d "$dir/$2.frames" ] && mv -- "$dir/$2.frames" "$dir/$1.frames"
    return 0
}

case "$mode" in
    all)
        [ -d "$dir" ] || exit 0
        for f in "$dir"/*.json; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .json)
            printf '%s\t' "$name"
            tr -d '\n\r' < "$f"
            printf '\n'
        done
        if [ -f "$dir/.previous.json" ]; then
            printf '.previous\t'
            tr -d '\n\r' < "$dir/.previous.json"
            printf '\n'
        fi
        for f in "$dir"/.trash/*.json; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .json)
            printf '.trash/%s\t' "$name"
            tr -d '\n\r' < "$f"
            printf '\n'
        done
        if [ -f "$dir/.trash/.notes" ]; then
            printf '.trash/.notes\t'
            tr -d '\n\r' < "$dir/.trash/.notes"
            printf '\n'
        fi
        if [ -f "$dir/.trash/.at" ]; then
            printf '.trash/.at\t'
            tr -d '\n\r' < "$dir/.trash/.at"
            printf '\n'
        fi
        ;;
    save)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        [ -n "$3" ] || exit 2
        mkdir -p "$dir" || exit 1
        # The pictures first, built beside the final folder and swapped in, so
        # a preset never points at pictures that aren't there. Nothing worn
        # (or a preset saved without pictures) leaves no folder at all.
        imgs="$dir/$2.images"
        rm -rf -- "$imgs.tmp"
        mkdir -p "$imgs.tmp" || exit 1
        keep_image avatar "${4:--}" "$imgs.tmp"
        keep_image banner "${5:--}" "$imgs.tmp"
        keep_image phone "${6:--}" "$imgs.tmp"
        rm -rf -- "$imgs"
        if [ -n "$(ls -A "$imgs.tmp")" ]; then
            mv "$imgs.tmp" "$imgs"
        else
            rmdir "$imgs.tmp"
        fi
        keep_frames "$dir/$2.frames" "$@" || exit 1
        printf '%s\n' "$3" > "$dir/$2.json.tmp" || exit 1
        mv "$dir/$2.json.tmp" "$dir/$2.json"
        ;;
    restore-frames)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        name="$2"
        shift 2
        data="${XDG_DATA_HOME:-$HOME/.local/share}/sekaipop/custom-images"
        for file in "$@"; do
            # <file> is a plain name inside the preset's own folder.
            case "$file" in
                img-*) ;;
                *) continue ;;
            esac
            case "$file" in
                */*) continue ;;
            esac
            if [ -f "$data/$file" ]; then
                printf '%s\n' "$data/$file"
                continue
            fi
            src="$dir/$name.frames/$file"
            [ -f "$src" ] || continue
            mkdir -p "$data" || exit 1
            cp -- "$src" "$data/$file" && printf '%s\n' "$data/$file"
        done
        exit 0
        ;;
    restore)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        name="$2"
        shift 2
        data="${XDG_DATA_HOME:-$HOME/.local/share}/sekaipop"
        while [ $# -ge 3 ]; do
            kind="$1"
            file="$2"
            as="$3"
            shift 3
            case "$kind" in
                avatar|banner|phone) ;;
                *) continue ;;
            esac
            # <file> is a plain name inside the preset's own folder.
            case "$file" in
                ''|.*|*/*) continue ;;
            esac
            src="$dir/$name.images/$file"
            [ -f "$src" ] || continue
            # <as> keeps the picture's old name (avatar-<time>.<ext>) so the
            # shell can tell it is the one the preset was saved with. A name
            # that doesn't look like that gets a fresh one.
            case "$as" in
                */*) as="" ;;
                "$kind"-*) ;;
                *) as="" ;;
            esac
            if [ -z "$as" ]; then
                case "$file" in
                    *.*) e=".${file##*.}" ;;
                    *) e="" ;;
                esac
                as="$kind-$(date +%s)$e"
            fi
            mkdir -p "$data" || exit 1
            # Through shrink-image.sh: a copy saved from a very big picture
            # (before pictures were scaled when picked) is scaled down here.
            sh "$here/../images/shrink-image.sh" "$kind" "$src" "$data/$as" || continue
            for old in "$data/$kind"-*; do
                [ "$old" != "$data/$as" ] && rm -f -- "$old"
            done
            printf '%s %s\n' "$kind" "$data/$as"
        done
        exit 0
        ;;
    rename)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        bad_name "$3" && { echo "bad preset name" >&2; exit 2; }
        [ -n "$4" ] || exit 2
        [ -f "$dir/$2.json" ] || { echo "no such preset" >&2; exit 1; }
        if [ "$2" != "$3" ]; then
            [ -e "$dir/$3.json" ] && { echo "name taken" >&2; exit 3; }
            # A folder of pictures left behind by a preset that is gone (a crash
            # between its two files) must not come along with the new name.
            rm -rf -- "$dir/$3.images"
            if [ -d "$dir/$2.images" ]; then
                mv -- "$dir/$2.images" "$dir/$3.images" || exit 1
            fi
            rm -rf -- "$dir/$3.frames"
            if [ -d "$dir/$2.frames" ]; then
                mv -- "$dir/$2.frames" "$dir/$3.frames" || { undo_rename "$2" "$3"; exit 1; }
            fi
        fi
        printf '%s\n' "$4" > "$dir/$3.json.tmp" \
            || { undo_rename "$2" "$3"; exit 1; }
        mv "$dir/$3.json.tmp" "$dir/$3.json" \
            || { rm -f "$dir/$3.json.tmp"; undo_rename "$2" "$3"; exit 1; }
        [ "$2" != "$3" ] && rm -f "$dir/$2.json"
        exit 0
        ;;
    delete)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        rm -f "$dir/$2.json"
        rm -rf -- "$dir/$2.images" "$dir/$2.frames"
        ;;
    trash)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        [ -f "$dir/$2.json" ] || { echo "no such preset" >&2; exit 1; }
        # Built beside the old trash and swapped in, so a failed move leaves
        # the last deleted preset where it was.
        rm -rf -- "$dir/.trash.tmp"
        mkdir -p "$dir/.trash.tmp" || exit 1
        for part in images frames; do
            if [ -d "$dir/$2.$part" ]; then
                mv -- "$dir/$2.$part" "$dir/.trash.tmp/$2.$part" || exit 1
            fi
        done
        [ -n "$3" ] && printf '%s\n' "$3" > "$dir/.trash.tmp/.notes"
        date +%s > "$dir/.trash.tmp/.at"
        mv -- "$dir/$2.json" "$dir/.trash.tmp/$2.json" || exit 1
        rm -rf -- "$dir/.trash"
        mv -- "$dir/.trash.tmp" "$dir/.trash"
        ;;
    untrash)
        bad_name "$2" && { echo "bad preset name" >&2; exit 2; }
        [ -f "$dir/.trash/$2.json" ] || { echo "not in the trash" >&2; exit 1; }
        [ -e "$dir/$2.json" ] && { echo "name taken" >&2; exit 3; }
        for part in images frames; do
            rm -rf -- "$dir/$2.$part"
            if [ -d "$dir/.trash/$2.$part" ]; then
                mv -- "$dir/.trash/$2.$part" "$dir/$2.$part" || exit 1
            fi
        done
        mv -- "$dir/.trash/$2.json" "$dir/$2.json" || exit 1
        rm -rf -- "$dir/.trash"
        exit 0
        ;;
    purge-trash)
        case "$2" in
            ''|*[!0-9]*) exit 2 ;;
        esac
        [ -d "$dir/.trash" ] || exit 0
        at=$(cat "$dir/.trash/.at" 2>/dev/null)
        case "$at" in
            ''|*[!0-9]*) at=0 ;;
        esac
        [ $(( $(date +%s) - at )) -ge "$2" ] && rm -rf -- "$dir/.trash"
        exit 0
        ;;
    exists)
        shift
        for p in "$@"; do
            [ -f "$p" ] && printf '%s\n' "$p"
        done
        exit 0
        ;;
    *)
        echo "usage: $0 all|save <name> <json> [avatar|-] [banner|-] [frame file...]|restore-frames <name> <file>...|restore <name> <kind> <file> <as>...|rename <old> <new> <json>|delete <name>|trash <name> [notes json]|untrash <name>|purge-trash <secs>|exists <path>..." >&2
        exit 2
        ;;
esac
