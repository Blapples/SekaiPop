#!/bin/sh

# Screens for the Displays card (services/DisplayService.qml).
#
#   displays.sh apply <spec>...     change the screens now (nothing is saved)
#   displays.sh save  <spec>...     write ~/.config/hypr/monitors.lua
#   displays.sh force <spec>...     like apply, but with `hyprctl keyword monitor` (the
#                                   card uses it when apply did not take)
#   displays.sh known               the screens that are plugged in, name|WxH, whether or
#                                   not Hyprland lists them (a screen that was switched
#                                   off in monitors.lua can be missing from hyprctl)
#
# What hyprctl answers to a change that did not work is kept in ~/.cache/sekaipop/displays.log.
#
# <spec> is  name|on|mode|x|y|scale   (mode like 1920x1080@144.00, or "preferred")
#         or name|off            (or name|off|x|y: where to park it, see below)
#
# monitors.lua is the file nwg-displays writes and hyprland.lua loads, and this
# writes it in the same shape, so the two can be used side by side. Lines in an
# existing block that are not ours (transform, vrr, bitdepth, mirror ...) are carried
# over; the old file is kept as monitors.lua.bak. Every value is checked before it
# goes into a Lua line.

dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
file="$dir/monitors.lua"

# name mode x y scale -> ok (0) or not (1)
valid_on() {
    case "$1" in ''|*[!A-Za-z0-9_.:-]*) return 1 ;; esac
    case "$2" in ''|*[!A-Za-z0-9@.]*) return 1 ;; esac
    case "$3" in ''|-|*[!0-9-]*) return 1 ;; esac
    case "$4" in ''|-|*[!0-9-]*) return 1 ;; esac
    case "$5" in ''|*[!0-9.]*) return 1 ;; esac
    return 0
}

# whole number, not negative
is_num() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    return 0
}

valid_name() {
    case "$1" in ''|*[!A-Za-z0-9_.:-]*) return 1 ;; esac
    return 0
}

log="${XDG_CACHE_HOME:-$HOME/.cache}/sekaipop/displays.log"

# Run hyprctl; anything but "ok" goes to the log, so a change that did not take can be looked at.
hypr() {
    out=$(hyprctl "$@" 2>&1)
    [ "$out" = ok ] && return 0
    mkdir -p "${log%/*}" 2>/dev/null
    printf '%s hyprctl %s -> %s\n' "$(date '+%F %T')" "$*" "${out:-(nothing)}" >> "$log" 2>/dev/null
    return 1
}

# Lines inside an existing block for <name> that are not ours, one per line, with no
# trailing comma.
extras() {
    [ -f "$1" ] || return 0
    awk -v want="$2" '
        /hl\.monitor[ \t]*\(/ { inb = 1; name = ""; buf = ""; next }
        inb && /^[ \t]*\}[ \t]*\)/ { if (name == want) printf "%s", buf; inb = 0; next }
        inb {
            line = $0
            if (line ~ /^[ \t]*output[ \t]*=/) {
                s = line
                sub(/^[ \t]*output[ \t]*=[ \t]*"/, "", s)
                sub(/".*/, "", s)
                name = s
                next
            }
            if (line ~ /^[ \t]*(mode|position|scale|disabled)[ \t]*=/) next
            sub(/^[ \t]+/, "", line)
            sub(/,[ \t]*$/, "", line)
            if (line != "") buf = buf line "\n"
        }
    ' "$1"
}

case "$1" in
    apply)
        shift
        command -v hyprctl >/dev/null 2>&1 || exit 1
        # Screens that come on first, then the ones that go off: never none.
        for pass in on off; do
            for spec in "$@"; do
                IFS='|' read -r name state mode x y scale <<EOF2
$spec
EOF2
                [ "$state" = "$pass" ] || continue
                if [ "$state" = on ]; then
                    valid_on "$name" "$mode" "$x" "$y" "$scale" || { echo "bad spec: $spec" >&2; exit 2; }
                    hypr eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"${x}x${y}\", scale = $scale })"
                else
                    valid_name "$name" || { echo "bad spec: $spec" >&2; exit 2; }
                    hypr eval "hl.monitor({ output = \"$name\", disabled = true })"
                    # Best effort: park it beside the others. An off screen is otherwise
                    # counted at 0, 0 and Hyprland warns that it overlaps. If Hyprland does
                    # not take a position on an off screen this changes nothing (it is
                    # already off), and nothing is saved from here.
                    px="$mode"; py="$x"
                    if is_num "$px" && is_num "$py"; then
                        hypr eval "hl.monitor({ output = \"$name\", disabled = true, position = \"${px}x${py}\" })"
                    fi
                fi
            done
        done
        ;;
    force)
        shift
        command -v hyprctl >/dev/null 2>&1 || exit 1
        for pass in on off; do
            for spec in "$@"; do
                IFS='|' read -r name state mode x y scale <<EOF2
$spec
EOF2
                [ "$state" = "$pass" ] || continue
                if [ "$state" = on ]; then
                    valid_on "$name" "$mode" "$x" "$y" "$scale" || { echo "bad spec: $spec" >&2; exit 2; }
                    hypr keyword monitor "$name,$mode,${x}x${y},$scale"
                else
                    valid_name "$name" || { echo "bad spec: $spec" >&2; exit 2; }
                    hypr keyword monitor "$name,disable"
                fi
            done
        done
        ;;
    known)
        # The kernel's list of plugged-in screens: /sys/class/drm/card1-HDMI-A-1/status says
        # "connected", and modes lists its sizes, the preferred one first.
        for st in /sys/class/drm/card*-*/status; do
            [ -f "$st" ] || continue
            [ "$(cat "$st" 2>/dev/null)" = connected ] || continue
            d=${st%/status}
            n=${d##*/}
            n=${n#card*-}
            valid_name "$n" || continue
            sz=$(head -n 1 "$d/modes" 2>/dev/null)
            case "$sz" in ''|*[!0-9x]*) sz="" ;; esac
            echo "$n|$sz"
        done
        ;;
    save)
        shift
        # Check everything before anything is written.
        for spec in "$@"; do
            IFS='|' read -r name state mode x y scale <<EOF2
$spec
EOF2
            if [ "$state" = on ]; then
                valid_on "$name" "$mode" "$x" "$y" "$scale" || { echo "bad spec: $spec" >&2; exit 2; }
            elif [ "$state" = off ]; then
                valid_name "$name" || { echo "bad spec: $spec" >&2; exit 2; }
            else
                echo "bad spec: $spec" >&2; exit 2
            fi
        done
        mkdir -p "$dir" || exit 1
        old=""
        if [ -f "$file" ]; then
            cp -f "$file" "$file.bak" || exit 1
            old="$file.bak"
        fi
        tmp=$(mktemp "$dir/.monitors.XXXXXX") || exit 1
        {
            printf '%s\n\n' '-- Written by the sekaipop shell (Settings > Hyprland > Displays) in the format nwg-displays uses. Do not edit manually.'
            for spec in "$@"; do
                IFS='|' read -r name state mode x y scale <<EOF2
$spec
EOF2
                if [ "$state" = on ]; then
                    printf 'hl.monitor({\n    output = "%s",\n    mode = "%s",\n    position = "%sx%s",\n    scale = %s' "$name" "$mode" "$x" "$y" "$scale"
                    extras "$old" "$name" | while IFS= read -r line; do
                        printf ',\n    %s' "$line"
                    done
                    printf '\n})\n'
                else
                    printf 'hl.monitor({\n    output = "%s",\n    disabled = true\n})\n' "$name"
                fi
            done
        } > "$tmp" || { rm -f "$tmp"; exit 1; }
        chmod 644 "$tmp"
        mv -f "$tmp" "$file" || { rm -f "$tmp"; exit 1; }
        ;;
    *)
        echo "usage: $0 apply <spec>... | force <spec>... | save <spec>... | known" >&2
        exit 2
        ;;
esac
exit 0
