#!/bin/sh

# Helper for LockEditService.qml: lets you choose a picture for the Image widget of the
# Custom lockscreen with a normal file chooser, and prints its absolute path.
#
#   pick-lock-picture.sh pick     open a file chooser; print the chosen picture's path
#
# Unlike pick-image.sh (the Quick Panel's avatar and banner) it does NOT copy the picture:
# the lockscreen reads the file where it is (docs/LOCKCANVAS.md, rule 5: local files only).
# Only the kinds LockCanvasModel.js lets through are offered (png jpg jpeg webp gif bmp), and
# LockCanvasModel.cleanPath() checks the path again before it is saved.
#
# The chooser is the first of kdialog, zenity or yad that is installed, the same order
# pick-image.sh uses; SEKAIPOP_CHOOSER (Settings -> General -> Quick Panel -> Picture picker)
# names one to try first. Prints nothing (and exits 1) if you cancel.

[ "$1" = pick ] || { echo "usage: $0 pick" >&2; exit 2; }

title="Choose a picture for the lockscreen"

# Start in the Pictures folder if there is one.
start=$(xdg-user-dir PICTURES 2>/dev/null)
[ -d "$start" ] || start="$HOME/Pictures"
[ -d "$start" ] || start="$HOME"

# "*.png *.PNG *.jpg ..." -- the choosers match case-sensitively.
patterns=""
for e in png jpg jpeg webp gif bmp; do
    up=$(printf '%s' "$e" | tr 'a-z' 'A-Z')
    patterns="$patterns *.$e *.$up"
done
patterns="${patterns# }"

chooser=""
for c in ${SEKAIPOP_CHOOSER:-} kdialog zenity yad; do
    case "$c" in
        zenity|kdialog|yad) ;;
        *) continue ;;
    esac
    if command -v "$c" >/dev/null 2>&1; then
        chooser="$c"
        break
    fi
done

case "$chooser" in
    zenity)
        f=$(zenity --file-selection --title="$title" --filename="$start/" \
            --file-filter="Images | $patterns" 2>/dev/null)
        ;;
    kdialog)
        f=$(kdialog --title "$title" --getopenfilename "$start" "$patterns|Images" 2>/dev/null)
        ;;
    yad)
        f=$(yad --file --title="$title" --filename="$start/" \
            --file-filter="Images | $patterns" 2>/dev/null)
        ;;
    *)
        echo "no file chooser found: install zenity (or kdialog / yad)" >&2
        exit 127
        ;;
esac

# Cancelled, or nothing usable picked.
[ -n "$f" ] && [ -f "$f" ] || exit 1

printf '%s\n' "$f"
