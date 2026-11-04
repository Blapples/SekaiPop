#!/bin/sh

# Hyprland options for the Settings Panel, written the same way
# antiflashbang-state.sh writes the screen shader: as marker-tagged lines in
# ~/.config/hypr/sekaipop_overrides.lua (which hyprland.lua loads with
# `pcall(require, "sekaipop_overrides")`), and applied live right away.
#
#   hyprland-settings.sh set <path> <int|float|bool|str> <value>
#   hyprland-settings.sh reset <path>          drop our override of one option
#   hyprland-settings.sh reset-all             drop every override of ours
#   hyprland-settings.sh read <path> ...       print  path=value  per line
#   hyprland-settings.sh check                 print  lua=yes|no  linked=yes|no
#
# One special path, `animation.workspaces`, is not a config option but the animation
# of switching workspaces (type `anim`, value = the style: slide, slidevert,
# slidefadevert, fade ...). It keeps the speed and curve Hyprland already uses for
# it and only changes the style: `slidevert` is niri's vertical slide.
#
# <path> is the option as dotted Lua names:  general.gaps_in,
# decoration.blur.enabled, input.touchpad.natural_scroll ...
#
# Only lines ending in "-- sekaipop:hypr:<path>" are ever touched, so the
# anti-flashbang lines (and anything else) in that file are left alone.
# Live apply: `hyprctl eval "hl.config({...})"` (Lua config); if Hyprland
# doesn't answer that, `hyprctl keyword section:name value` (hyprlang).

dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
file="$dir/sekaipop_overrides.lua"
MARK='-- sekaipop:hypr:'

# general.gaps_in 5 int  ->  { ["general"] = { ["gaps_in"] = 5 } }
lua_table() {
    path="$1"; val="$2"
    # The panel keeps the legacy key; Lua renamed this option.
    [ "$path" = input.touchpad.tap-to-click ] && path=input.touchpad.tap_to_click
    open=""; close=""
    old_ifs="$IFS"; IFS=.
    set -- $path
    IFS="$old_ifs"
    n=$#; i=0
    for part in "$@"; do
        i=$((i + 1))
        if [ "$i" -lt "$n" ]; then
            open="$open[\"$part\"] = { "; close=" }$close"
        else
            open="$open[\"$part\"] = $val"
        fi
    done
    printf '{ %s%s }' "$open" "$close"
}

lua_value() {
    case "$1" in
        bool)  [ "$2" = "true" ] || [ "$2" = "1" ] && printf 'true' || printf 'false' ;;
        int)   printf '%d' "$2" ;;
        float) printf '%s' "$2" ;;
        *)     printf '[==[%s]==]' "$2" ;;
    esac
}

drop_marker() {
    # Everything except our line for <path>. A grep that really failed (exit
    # 2) must never replace the file with nothing; exit 1 = no lines left.
    tmp=$(mktemp "$dir/.sekaipop_overrides.XXXXXX") || return 1
    case "$1" in
        input.touchpad.tap-to-click|input.touchpad.tap_to_click)
            # Also remove overrides repaired manually with the Lua spelling.
            grep -v -F -e "${MARK}input.touchpad.tap-to-click" \
                -e "${MARK}input.touchpad.tap_to_click" "$file" > "$tmp"
            ;;
        *) grep -v -F -e "$MARK$1" "$file" > "$tmp" ;;
    esac
    [ $? -le 1 ] || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp"
    mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# The workspaces animation as `hyprctl animations` lists it: prints "speed bezier"
# (the defaults when it can't be read).
anim_current() {
    speed=6; bez=default
    if command -v hyprctl >/dev/null 2>&1; then
        info=$(hyprctl animations 2>/dev/null | awk '/(name|animation): *workspaces *$/ {f=1; next} f && /(name|animation):/ {exit} f')
        s=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*speed: *\([0-9.]*\).*/\1/p' | head -n 1)
        b=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*bezier: *\([A-Za-z0-9_.-]*\).*/\1/p' | head -n 1)
        [ -n "$s" ] && speed="$s"
        [ -n "$b" ] && bez="$b"
    fi
    printf '%s %s' "$speed" "$bez"
}

# The style: ours from the override file if there is one, else Hyprland's.
anim_style() {
    if [ -f "$file" ]; then
        v=$(grep -F -e "${MARK}animation.workspaces" "$file" | sed -n 's/.*style = "\([^" ]*\).*/\1/p' | tail -n 1)
        [ -n "$v" ] && { printf '%s' "$v"; return; }
    fi
    if command -v hyprctl >/dev/null 2>&1; then
        v=$(hyprctl animations 2>/dev/null | awk '/(name|animation): *workspaces *$/ {f=1; next} f && /(name|animation):/ {exit} f' | sed -n 's/^[[:space:]]*style: *\([^ ]*\).*/\1/p' | head -n 1)
        [ -n "$v" ] && { printf '%s' "$v"; return; }
    fi
    printf 'slide'
}

case "$1" in
    set)
        path="$2"; type="$3"; value="$4"
        [ -n "$path" ] && [ -n "$type" ] || exit 2
        if [ "$type" = anim ]; then
            # Checked before anything is dropped: a refused value changes nothing.
            [ "$path" = animation.workspaces ] || exit 2
            case "$value" in
                *[!A-Za-z0-9%\ ]*|"") exit 2 ;;
            esac
        fi
        mkdir -p "$dir" || exit 1
        [ -e "$file" ] || : > "$file"
        drop_marker "$path" || exit 1
        if [ "$type" = anim ]; then
            set -- $(anim_current)
            speed="$1"; bez="$2"
            tbl="{ leaf = \"workspaces\", enabled = true, speed = $speed, bezier = \"$bez\", style = \"$value\" }"
            printf 'hl.animation(%s) %s%s\n' "$tbl" "$MARK" "$path" >> "$file"
            command -v hyprctl >/dev/null 2>&1 || exit 0
            out=$(hyprctl eval "hl.animation($tbl)" 2>&1)
            case "$out" in
                ok*|"") ;;
                *) hyprctl keyword animation "workspaces,1,$speed,$bez,$value" >/dev/null 2>&1 ;;
            esac
            exit 0
        fi
        lv=$(lua_value "$type" "$value")
        tbl=$(lua_table "$path" "$lv")
        printf 'hl.config(%s) %s%s\n' "$tbl" "$MARK" "$path" >> "$file"
        command -v hyprctl >/dev/null 2>&1 || exit 0
        # Changing the layout list while the active layout is one that is about to
        # go (or that the new list is too short for) can take Hyprland down with it,
        # and the shell with it. Step back to the first layout before the list is
        # touched, and give the keymap a moment to settle.
        case "$path" in
            input.kb_layout|input.kb_variant)
                hyprctl switchxkblayout all 0 >/dev/null 2>&1
                sleep 0.25
                ;;
        esac
        out=$(hyprctl eval "hl.config($tbl)" 2>&1)
        case "$out" in
            ok*|"") ;;
            *)
                kv=$(printf '%s' "$value")
                [ "$type" = bool ] && { [ "$value" = "1" ] && kv=true; }
                hyprctl keyword "$(printf '%s' "$path" | tr . :)" "$kv" >/dev/null 2>&1
                ;;
        esac
        ;;
    reset)
        [ -f "$file" ] || exit 0
        drop_marker "$2" || exit 1
        command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1
        ;;
    reset-all)
        [ -f "$file" ] || exit 0
        tmp=$(mktemp "$dir/.sekaipop_overrides.XXXXXX") || exit 1
        grep -v -F -e "$MARK" "$file" > "$tmp"
        [ $? -le 1 ] || { rm -f "$tmp"; exit 1; }
        chmod 644 "$tmp"
        mv -f "$tmp" "$file" || { rm -f "$tmp"; exit 1; }
        command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1
        ;;
    read)
        shift
        command -v hyprctl >/dev/null 2>&1 || exit 0
        for path in "$@"; do
            if [ "$path" = animation.workspaces ]; then
                printf '%s=%s\n' "$path" "$(anim_style)"
                continue
            fi
            # "int: 5" / "float: 0.9" / "str: dwindle" / "custom type: 5 5 5 5"
            query="$path"
            if [ "$path" = input.touchpad.tap-to-click ] && [ -f "$dir/hyprland.lua" ]; then
                query=input.touchpad.tap_to_click
            fi
            v=$(hyprctl getoption "$(printf '%s' "$query" | tr . :)" 2>/dev/null | sed -n '1s/^[^:]*: *//p' | cut -d' ' -f1)
            [ -n "$v" ] && printf '%s=%s\n' "$path" "$v"
        done
        ;;
    check)
        cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
        if [ -f "$cfg" ]; then
            printf 'lua=yes\n'
            grep -q 'sekaipop_overrides' "$cfg" && printf 'linked=yes\n' || printf 'linked=no\n'
        else
            printf 'lua=no\nlinked=yes\n'
        fi
        ;;
    *)
        echo "usage: $0 set <path> <int|float|bool|str> <value> | reset <path> | reset-all | read <path>... | check" >&2
        exit 2
        ;;
esac
exit 0
