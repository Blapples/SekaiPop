#!/bin/sh

# One-time move from the old name ("pjsekai") to the new one ("sekaipop"). Safe to run again;
# when there is nothing left of the old name it does nothing.
#
#   --dry-run     only say what would be moved or rewritten
#   --skip-hypr   leave Hyprland configs and backups alone
#
# install.sh runs it first thing. The Kitty helper recognises its old include separately.
#
# What it touches (everything is a plain rename of the word, nothing else is changed):
#   1. the shell's own folders: settings, presets, scale, to-dos, notifications, dock layout,
#      custom images, caches...   <config|state|cache|data>/pjsekai  ->  <...>/sekaipop
#      (if the new folder already exists, the old files are copied into it and the old folder is
#      kept as pjsekai.migrated-<time>, never deleted)
#   2. in those folders, paths and names inside the text files (a preset that points at
#      ~/.local/share/pjsekai/custom-images/x.png now points at .../sekaipop/...)
#   3. what the shell wrote into other programs' files, so "Revert" / "App colours" still find
#      their own blocks and do not add a second one:
#        ~/.config/hypr/pjsekai_overrides.lua, pjsekai_session.*, hyprland.lua / .conf and the
#        lua files of the config, hypr.pjsekai-backup-* / hypr.pjsekai-previous (kept for
#        install.sh --restore), foot, fuzzel, rofi, fish, gtk-3.0, gtk-4.0, qt5ct,
#        qt6ct, matugen, kdeglobals(+backup), VS Code / VSCodium / Cursor settings.json,
#        Vencord / vesktop / Equicord themes, the generated GTK theme and KDE colour scheme,
#        and ~/.bashrc / ~/.zshrc lines.
#   Every file it rewrites is listed in ~/.local/state/sekaipop/migration.log.
#   To undo a rewrite, swap the words back: sed -i 's/sekaipop/pjsekai/g' <file>.

dry=0
skip_hypr=0
for option in "$@"; do
    case "$option" in
        --dry-run) dry=1 ;;
        --skip-hypr) skip_hypr=1 ;;
        *) echo "Unknown migration option: $option" >&2; exit 2 ;;
    esac
done

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
ts=$(date +%Y%m%d-%H%M%S)
log="$state/sekaipop/migration.log"
changed=0
tmpl=$(mktemp 2>/dev/null || echo "/tmp/sekaipop-migrate.$$")
logbuf="$tmpl.log"
trap 'rm -f "$tmpl" "$logbuf"' EXIT

say() { printf '  %s\n' "$*"; }
note() { changed=$((changed + 1)); say "$*"; }
# The log is written at the very end: making its folder earlier would make the state folder
# "already exist" and turn a plain move into a merge.
record() {
    [ "$dry" = 1 ] && return 0
    printf '%s  %s\n' "$ts" "$*" >> "$logbuf"
    return 0
}

# the same word swap everywhere
swap() { sed -e 's/pjsekai/sekaipop/g' -e 's/PJSEKAI/SEKAIPOP/g' -e 's/Pjsekai/Sekaipop/g'; }
swapname() { printf '%s' "$1" | swap; }

# run `cmd file` for every path `find ...` lists (not in a pipe, so the change counter survives)
foreach() {
    cmd="$1"; shift
    find "$@" > "$tmpl" 2>/dev/null
    while IFS= read -r f; do "$cmd" "$f"; done < "$tmpl"
}

# rewrite one text file in place (keeps its mode)
rewrite() {
    f="$1"
    [ -f "$f" ] && [ ! -L "$f" ] || return 0
    [ "$f" = "$log" ] && return 0      # the log names the old files; it stays as written
    grep -qI -i 'pjsekai' "$f" 2>/dev/null || return 0
    note "rewrite $f"
    [ "$dry" = 1 ] && return 0
    tmp="$f.sekaipop-migrate"
    if swap < "$f" > "$tmp" 2>/dev/null; then
        cat "$tmp" > "$f" && record "rewrote $f"
    fi
    rm -f "$tmp"
}

# rename one file or folder to its new name (never over something that already exists)
rename() {
    old="$1"
    [ -e "$old" ] || [ -L "$old" ] || return 0
    dir=$(dirname "$old")
    base=$(basename "$old")
    case "$base" in *.migrated-*) return 0 ;; esac
    new="$dir/$(swapname "$base")"
    [ "$new" = "$old" ] && return 0
    if [ -e "$new" ] || [ -L "$new" ]; then
        say "keep $old (the new name $new already exists)"
        return 0
    fi
    note "rename $old -> $new"
    [ "$dry" = 1 ] && return 0
    mv "$old" "$new" && record "renamed $old -> $new"
}

# 1. the shell's own folders -----------------------------------------------------------------
move_dir() {
    old="$1/pjsekai"
    new="$1/sekaipop"
    [ -d "$old" ] || return 0
    if [ ! -e "$new" ]; then
        note "move $old -> $new"
        [ "$dry" = 1 ] && return 0
        mv "$old" "$new" && record "moved $old -> $new"
    else
        note "merge $old into $new (the old folder is kept as pjsekai.migrated-$ts)"
        [ "$dry" = 1 ] && return 0
        cp -a "$old/." "$new/" && mv "$old" "$old.migrated-$ts" && record "merged $old into $new"
    fi
}
for b in "$cfg" "$state" "$cache" "$data"; do move_dir "$b"; done

# 2. paths and names inside the moved folders (config + state hold the JSON and scripts)
for d in "$cfg/sekaipop" "$state/sekaipop"; do
    [ -d "$d" ] || continue
    foreach rewrite "$d" -path "$state/sekaipop/kitty-backups" -prune -o -type f -size -4M -print
done

# 3. what was written into other programs' files ---------------------------------------------
# Hyprland's backups, names and contents share the same migration scope.
if [ "$skip_hypr" = 0 ]; then
    for f in "$cfg"/hypr.pjsekai-backup-* "$cfg"/hypr.pjsekai-replaced-* \
             "$cfg"/hypr.pjsekai-previous; do
        [ -e "$f" ] && rename "$f"
    done
    if [ -d "$cfg/hypr" ]; then
        foreach rename "$cfg/hypr" -maxdepth 3 -depth \( -name '*pjsekai*' -o -name '*Pjsekai*' \)
        foreach rewrite "$cfg/hypr" -maxdepth 2 -type f \( -name '*.lua' -o -name '*.conf' \)
    fi
fi

# Other programs' files still migrate in skip mode. Rename files before rewriting their references.
if [ -d "$cfg" ]; then
    [ -e "$cfg/kdeglobals.pjsekai-bak" ] && rename "$cfg/kdeglobals.pjsekai-bak"
    for d in foot fuzzel rofi fish gtk-3.0 gtk-4.0 qt5ct qt6ct matugen; do
        [ -d "$cfg/$d" ] || continue
        foreach rename "$cfg/$d" -maxdepth 3 -depth \( -name '*pjsekai*' -o -name '*Pjsekai*' \)
    done
fi
for d in "$data/themes" "$data/color-schemes"; do
    [ -d "$d" ] || continue
    for f in "$d"/*pjsekai* "$d"/*Pjsekai*; do [ -e "$f" ] && rename "$f"; done
done

# the contents
if [ -d "$cfg" ]; then
    for d in foot fuzzel rofi fish gtk-3.0 gtk-4.0 qt5ct qt6ct matugen; do
        [ -d "$cfg/$d" ] || continue
        foreach rewrite "$cfg/$d" -maxdepth 3 -type f -size -2M
    done
    rewrite "$cfg/kdeglobals"
    rewrite "$cfg/kdeglobals.sekaipop-bak"
    for app in Code "Code - OSS" "Code - Insiders" VSCodium Cursor Windsurf; do
        rewrite "$cfg/$app/User/settings.json"
    done
    # Vencord and friends: the theme file and the "enabled themes" entry that names it
    for app in Vencord vesktop Equicord; do
        for t in "$cfg/$app/themes"/*.css; do [ -f "$t" ] && rewrite "$t"; done
        rewrite "$cfg/$app/settings/settings.json"
    done
fi
if [ -d "$data/color-schemes" ]; then
    for f in "$data/color-schemes"/Sekaipop*.colors; do [ -f "$f" ] && rewrite "$f"; done
fi
for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.profile"; do rewrite "$f"; done

# the Vencord / vesktop theme file itself (its name is what Discord's settings list)
for app in Vencord vesktop Equicord; do
    rename "$cfg/$app/themes/pjsekai.theme.css"
done

# GTK theme setting, when it still names the old generated theme
if command -v gsettings >/dev/null 2>&1 && [ "$dry" = 0 ]; then
    cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    case "$cur" in
        pjsekai-adw-gtk3|pjsekai-adw-gtk3-dark)
            new=$(swapname "$cur")
            if [ -d "$data/themes/$new" ]; then
                gsettings set org.gnome.desktop.interface gtk-theme "$new" 2>/dev/null \
                    && note "gtk-theme $cur -> $new" && record "gtk-theme $cur -> $new"
            fi ;;
    esac
fi

if [ "$dry" = 0 ] && [ -s "$logbuf" ]; then
    mkdir -p "$state/sekaipop" 2>/dev/null && cat "$logbuf" >> "$log" 2>/dev/null
fi

if [ "$changed" -eq 0 ]; then
    say "nothing left to move from the old pjsekai name"
elif [ "$dry" = 1 ]; then
    say "$changed change(s) would be made (run again without --dry-run)"
else
    say "$changed change(s) made, listed in $log"
fi
exit 0
