#!/bin/sh

# Helper for RegionService.qml / RegionSelector.qml: what happens to a region
# the user picked on screen.
#
#   region-action.sh capture <output> <png>
#       grim the whole <output> (a monitor name) into <png>. The selector shows
#       this frozen picture and crops from it.
#   region-action.sh crop <png> <x> <y> <w> <h> <scale> <out.png>
#       cut a rectangle (logical pixels, times <scale> for the picture's own
#       pixels) out of <png> into <out.png>. Needs ImageMagick (magick / convert).
#   region-action.sh copy|save|ocr|search <png> [<savedir>]
#       act on an already cropped picture:
#         copy    put it on the clipboard (wl-copy)
#         save    save it into <savedir> (default ~/Pictures/Screenshots) AND copy it
#         ocr     read the text in it (tesseract) and copy the text
#         search  upload it (uguu.se) and open an image search on it (Google Lens)
#                 NOTE: this sends the picture to that site. The picture is
#                 deleted from the temp folder afterwards.
#   region-action.sh swappy <png>
#       open an already cropped picture in swappy (annotate, then save / copy
#       from swappy itself). Returns at once; swappy runs on its own copy,
#       which is deleted when swappy closes. Needs swappy.
#   region-action.sh stash <png> <dest>
#       copy a cropped picture to <dest> (the preview card keeps it there; the
#       actions above delete the file they are given).
#   region-action.sh reuse <copy|save|swappy> <png>
#       do one of those on a fresh copy of <png>, leaving <png> where it is (the
#       preview card's buttons, which can be used more than once).
#   region-action.sh record <geometry> <sound: none|system|mic> <file>
#       wf-recorder on <geometry> ("x,y wxh", global logical pixels, the format
#       slurp prints). The script becomes wf-recorder (exec), so the caller stops
#       it with SIGINT, which is what makes wf-recorder finish the file properly.
#   region-action.sh encoder   print the wf-recorder options for the best video encoder that
#       works on this machine (nothing printed = wf-recorder's own software x264):
#       NVENC on an NVIDIA card, else VAAPI on another GPU (when an NVIDIA card is
#       there but NVENC is not usable, e.g. its driver is older than ffmpeg's NVENC
#       API), else software. Each is tried with a one-frame ffmpeg encode first.
#   region-action.sh rules     switch Hyprland's layer animation off for the picker and
#       its preview card (no zoom on the dim): applied live, and written to
#       ~/.config/hypr/sekaipop_overrides.lua when hyprland.lua loads that file.
#       Safe to run again; RegionService runs it at start-up and after a reload.
#   region-action.sh tools     print which of the helpers are installed
#
# Needs: grim, wl-clipboard. Optional: imagemagick (cropping; without it copy /
# save / ocr / search fall back to grabbing the region live with grim), tesseract
# (ocr), curl + jq (search), swappy (right-drag), wf-recorder (record), pactl (system sound).
# Everything is written to ${XDG_RUNTIME_DIR:-/tmp}/sekaipop-region/ and removed.

mode="$1"
[ $# -gt 0 ] && shift

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a sekaipop "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Does a one-frame encode with the given ffmpeg arguments work? Gives up after 5 s.
try_encode() {
    have ffmpeg || return 1
    if have timeout; then
        timeout 5 ffmpeg -v error -nostdin -f lavfi -i nullsrc=s=256x256 -frames:v 1 "$@" -f null - >/dev/null 2>&1
    else
        ffmpeg -v error -nostdin -f lavfi -i nullsrc=s=256x256 -frames:v 1 "$@" -f null - >/dev/null 2>&1
    fi
}

# wf-recorder options for the best encoder that works here (see "encoder" above).
pick_encoder() {
    [ -e /dev/nvidiactl ] || return 0
    # NVENC: ~20 % of one core instead of 3-4 cores. /dev/nvidiactl only says the NVIDIA
    # driver is loaded; NVENC can still fail (a driver older than ffmpeg's NVENC API).
    if try_encode -c:v h264_nvenc; then
        echo "-c h264_nvenc -p rc=vbr -p cq=21 -p b=0 -p preset=p5"
        return 0
    fi
    # VAAPI on a render node that is not the NVIDIA one (the Intel / AMD GPU of a laptop).
    for node in /dev/dri/renderD*; do
        [ -e "$node" ] || continue
        drv=$(basename "$(readlink -f "/sys/class/drm/$(basename "$node")/device/driver" 2>/dev/null)")
        [ "$drv" = nvidia ] && continue
        if try_encode -vaapi_device "$node" -vf format=nv12,hwupload -c:v h264_vaapi; then
            echo "-c h264_vaapi -d $node"
            return 0
        fi
    done
}

case "$mode" in
    capture)
        out="$1"; png="$2"
        [ -n "$out" ] && [ -n "$png" ] || exit 2
        mkdir -p "$(dirname "$png")" || exit 1
        have grim || { echo "grim is not installed" >&2; exit 127; }
        exec grim -o "$out" "$png"
        ;;
    crop)
        png="$1"; x="$2"; y="$3"; w="$4"; h="$5"; scale="$6"; out="$7"
        [ -n "$out" ] || exit 2
        # logical -> picture pixels
        px=$(awk -v v="$x" -v s="$scale" 'BEGIN { printf "%d", v * s + 0.5 }')
        py=$(awk -v v="$y" -v s="$scale" 'BEGIN { printf "%d", v * s + 0.5 }')
        pw=$(awk -v v="$w" -v s="$scale" 'BEGIN { printf "%d", v * s + 0.5 }')
        ph=$(awk -v v="$h" -v s="$scale" 'BEGIN { printf "%d", v * s + 0.5 }')
        [ "$pw" -gt 0 ] && [ "$ph" -gt 0 ] || exit 2
        if have magick; then
            exec magick "$png" -crop "${pw}x${ph}+${px}+${py}" +repage "$out"
        elif have convert; then
            exec convert "$png" -crop "${pw}x${ph}+${px}+${py}" +repage "$out"
        fi
        echo "imagemagick is not installed" >&2
        exit 127
        ;;
    copy)
        png="$1"
        have wl-copy || { notify -i material:photo_camera "Screenshot" "wl-clipboard is not installed"; exit 127; }
        wl-copy --type image/png < "$png" && notify -i material:content_copy "Copied to the clipboard" "Region screenshot"
        rm -f "$png"
        ;;
    save)
        png="$1"; dir="${2:-$HOME/Pictures/Screenshots}"
        mkdir -p "$dir" || exit 1
        f="$dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
        cp "$png" "$f" || exit 1
        have wl-copy && wl-copy --type image/png < "$f"
        notify -i material:photo_camera "Screenshot saved" "$f"
        rm -f "$png"
        ;;
    ocr)
        png="$1"
        have tesseract || { notify -i material:document_scanner "Copy text" "tesseract is not installed"; rm -f "$png"; exit 127; }
        langs=$(tesseract --list-langs 2>/dev/null | awk 'NR > 1 && $1 != "osd" { printf "%s%s", sep, $1; sep = "+" }')
        [ -n "$langs" ] || langs=eng
        text=$(tesseract "$png" stdout -l "$langs" 2>/dev/null)
        rm -f "$png"
        if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
            notify -i material:document_scanner "Copy text" "No text found in the region"
            exit 0
        fi
        printf '%s' "$text" | wl-copy
        notify -i material:document_scanner "Text copied" "$(printf '%s' "$text" | head -c 160)"
        ;;
    search)
        png="$1"
        have curl && have jq || { notify -i material:image_search "Image search" "curl and jq are needed"; rm -f "$png"; exit 127; }
        url=$(curl -sf -m 30 -F "files[]=@$png" https://uguu.se/upload | jq -r '.files[0].url' 2>/dev/null)
        rm -f "$png"
        if [ -z "$url" ] || [ "$url" = null ]; then
            notify -i material:image_search "Image search" "The upload failed"
            exit 1
        fi
        exec xdg-open "https://lens.google.com/uploadbyurl?url=$url"
        ;;
    swappy)
        png="$1"
        have swappy || { notify -i material:draw "Annotate" "swappy is not installed"; rm -f "$png"; exit 127; }
        # swappy gets its own copy (named so the temp-folder cleanup leaves it
        # alone) and the script does not wait for it, so a second pick is not
        # held up behind an open swappy window.
        keep="$(dirname "$png")/swappy-$(basename "$png")"
        mv "$png" "$keep" || exit 1
        ( swappy -f "$keep"; rm -f "$keep" ) </dev/null >/dev/null 2>&1 &
        ;;
    stash)
        png="$1"; dest="$2"
        [ -f "$png" ] && [ -n "$dest" ] || exit 2
        mkdir -p "$(dirname "$dest")" || exit 1
        cp "$png" "$dest" || exit 1
        ;;
    reuse)
        act="$1"; png="$2"
        case "$act" in copy|save|swappy) ;; *) exit 2 ;; esac
        [ -f "$png" ] || exit 2
        tmp="$(dirname "$png")/reuse-$(date +%s%N)-$(basename "$png")"
        cp "$png" "$tmp" || exit 1
        exec sh "$0" "$act" "$tmp"
        ;;
    record)
        geom="$1"; sound="${2:-none}"; file="$3"
        [ -n "$geom" ] && [ -n "$file" ] || exit 2
        have wf-recorder || { notify -i material:videocam "Recording" "wf-recorder is not installed"; exit 127; }
        mkdir -p "$(dirname "$file")" || exit 1
        enc=$(pick_encoder)
        case "$sound" in
            system)
                sink=$(pactl get-default-sink 2>/dev/null)
                if [ -n "$sink" ]; then exec wf-recorder $enc -g "$geom" --audio="$sink.monitor" -f "$file"; fi
                exec wf-recorder $enc -g "$geom" --audio -f "$file"
                ;;
            mic)  exec wf-recorder $enc -g "$geom" --audio -f "$file" ;;
            *)    exec wf-recorder $enc -g "$geom" -f "$file" ;;
        esac
        ;;
    encoder)
        pick_encoder
        ;;
    rules)
        # The picker's overlay is mapped when it opens and unmapped when it
        # closes, and Hyprland plays its own layer animation on both: the dim
        # zooms in and out. Switch that off for the picker's two namespaces
        # (the dim and the card are untouched). Same thing as, in hyprland.lua:
        #   hl.layer_rule({ match = { namespace = "^sekaipop-region$" }, no_anim = true })
        #
        # A rule added with `hyprctl eval` lives only until Hyprland reloads its
        # config (hyprctl reload, an edit of hyprland.lua, the anti-flashbang
        # tile, Settings -> Hyprland ...), and then the zoom comes back. So:
        #   - it is applied live (RegionService does this at start-up and again
        #     after every "configreloaded" event), and
        #   - when hyprland.lua already loads sekaipop_overrides, it is also
        #     written there (marker lines, like the other sekaipop options), so a
        #     reload brings it back by itself.
        have hyprctl || exit 0
        cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
        ovr="$cfgdir/sekaipop_overrides.lua"
        linked=no
        [ -f "$cfgdir/hyprland.lua" ] && grep -q 'sekaipop_overrides' "$cfgdir/hyprland.lua" && linked=yes
        for spec in "region-no-anim:sekaipop-region" "region-preview-no-anim:sekaipop-region-preview"; do
            key="${spec%%:*}"
            ns="${spec#*:}"
            lua="hl.layer_rule({ name = \"sekaipop-$key\", match = { namespace = \"^$ns\$\" }, no_anim = true })"
            if [ "$linked" = yes ]; then
                mark="-- sekaipop:$key"
                [ -e "$ovr" ] || : > "$ovr"
                grep -q -F -e "$mark" "$ovr" || printf '%s %s\n' "$lua" "$mark" >> "$ovr"
            fi
            out=$(hyprctl eval "$lua" 2>&1)
            case "$out" in
                ok*|"") ;;
                *) hyprctl keyword layerrule "no_anim on, match:namespace ^$ns\$" >/dev/null 2>&1 ;;
            esac
        done
        ;;
    tools)
        for t in grim wl-copy swappy magick convert tesseract curl jq wf-recorder pactl xdg-open notify-send; do
            if have "$t"; then echo "$t: yes"; else echo "$t: no"; fi
        done
        ;;
    *)
        echo "usage: $0 capture|crop|copy|save|ocr|search|swappy|stash|reuse|record|encoder|rules|tools ..." >&2
        exit 2
        ;;
esac
exit 0
