#!/bin/sh

# Helper for AppThemeService.qml: puts the shell's colours on a few apps that
# have their own colour settings, and takes them off again.
#
#   app-theme.sh apply <target> key=#rrggbb ...   write the colours (and hook them in)
#   app-theme.sh revert <target>                  remove everything `apply` added
#   app-theme.sh status                           one target=state per line
# Kitty: on/blocked/pending have a verified hook; conflict does not.
# Other states are off (no hook) and missing (Kitty absent and no hook).
#   app-theme.sh check|enable|sync kitty           inspect, opt in, or refresh an existing Kitty hook
#
# Targets: kitty, foot, vscode, fuzzel, rofi, fish, prompt, hyprland.
# Keys (all #rrggbb): bg fg cursor selbg selfg accent accent2 border surface
#   hover muted, pill onpill shadow (the prompt's pills and their shadow), c0 .. c15
#   (the 16 terminal colours), hlactive hlinactive (the
#   Hyprland window borders: a stronger accent, and a darker one of the same hue).
#
# The rule for every target: the colours go in a file of ours, and your own
# config gets ONE managed block that points at it (two lines, the first being a
# `sekaipop` comment). `revert` deletes that block and our file, nothing else.
# A config file that doesn't exist yet is only created when the app is installed.
#
#   kitty   kitty-theme.py manages a single final include in Kitty's config and reloads
#           open windows. Only `enable kitty` adds the include; apply/sync refresh it.
#           Revert removes only the include and retains all config/palette files.
#   foot    ~/.config/foot/sekaipop-colors.ini, `include=` at the TOP of foot.ini
#           (foot only allows it there, so a [colors] section of your own further
#           down still wins: remove it to let ours show). Foot never re-reads its
#           config, so new windows get the colours, open ones keep theirs.
#   vscode  settings.json of Code / Code - OSS / VSCodium: one block
#           `/* sekaipop:begin */ "workbench.colorCustomizations": {...}, /* sekaipop:end */`
#           right after the opening brace; VS Code applies it live. If the file
#           already has its own "workbench.colorCustomizations" nothing is
#           written (two of them would make the file invalid) and the colours
#           are put in ~/.config/sekaipop/vscode-colors.json for you to merge.
#   fuzzel  ~/.config/fuzzel/sekaipop-colors.ini, `include=` at the TOP of
#           fuzzel.ini (same note as foot). Read at every launch.
#   rofi    ~/.config/rofi/sekaipop-colors.rasi, `@import` at the END of
#           config.rasi: defines background, background-alt, foreground,
#           selected, active, urgent, the names most rofi themes use.
#   prompt  the fish prompt: outlined sticker plates (failed command, folder, git branch,
#           command time) with a hard shadow under each one, like the shell's own plates.
#           scripts/theming/prompt-sekaipop.sh is copied to ~/.local/state/sekaipop/terminal/prompt.sh
#           and ~/.config/fish/conf.d/sekaipop-prompt.fish defines a `fish_prompt` that runs it
#           (the shadow row has to be exactly as wide as each pill, so the script draws the pills
#           itself and measures them). Its colours are eight 256-colour indices (255 252 254 235
#           240 241 244 243) that the target redefines in every open terminal as `OSC 4` sequences
#           (live, and printed again by the same conf.d file for new shells). Nothing of yours
#           is edited: your config.fish and any Starship config stay as they are, while the switch
#           is on the prompt is ours, and revert deletes those files and gives the eight palette
#           entries back. A shell that is already open gets the new prompt when you open a new one
#           (or run `exec fish`); after a revert an open shell falls back to fish's own prompt.
#           Needs a Nerd Font in the terminal. fish only.

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
here="$(cd "$(dirname "$0")" && pwd)"
have() { command -v "$1" >/dev/null 2>&1; }
MARK="# sekaipop: managed block, removed by Settings -> Desktop -> App colours (revert)"

# Kitty uses its own headless option parser. Setting an explicit directory at launch
# keeps even a read-only check from creating the default Kitty config directory.
kitty_theme() {
    if ! have kitty; then
        # Revert only needs to remove our exact hook and inspect references. It must
        # remain available after Kitty is removed, without Kitty's option parser.
        if [ "$1" = revert ]; then python3 -B "$here/kitty-theme.py" "$@"; return $?; fi
        if [ "$1" = status ]; then
            kitty_state=$(python3 -B "$here/kitty-theme.py" "$@") || return 1
            [ "$kitty_state" != off ] || kitty_state=missing
            printf '%s\n' "$kitty_state"
            return 0
        fi
        [ "$1" != sync ] || return 0
        echo "Kitty is not installed; configuration validation is unavailable." >&2
        return 3
    fi
    SEKAIPOP_KITTY_CONFIG_DIRECTORY="${KITTY_CONFIG_DIRECTORY-}" KITTY_CONFIG_DIRECTORY=/ \
        kitty +runpy 'import runpy, sys; sys.dont_write_bytecode = True; runpy.run_path(sys.argv.pop(1), run_name="__main__")' \
        "$here/kitty-theme.py" "$@"
}

# Only enable installs a hook; old background apply calls are refresh-only.
if [ "${2-}" = kitty ]; then
    cmd="$1"; shift 2
    [ "$cmd" != apply ] || cmd=sync
    case "$cmd" in
        check|status|enable|apply|sync|revert) kitty_theme "$cmd" "$@"; exit $? ;;
    esac
fi
kitty_status() { kitty_theme status || echo conflict; }

# ===== arguments =====
cmd="$1"; target="$2"
[ $# -gt 0 ] && shift
[ $# -gt 0 ] && shift
for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
        bg|fg|cursor|selbg|selfg|accent|accent2|border|surface|hover|muted|pill|onpill|shadow|hlactive|hlinactive|ptA|ptB|ptInk|ptPaper|ptLine|ptFail|c[0-9]|c1[0-5])
            eval "col_$k=\"\$v\"" ;;
    esac
done
nh() { printf '%s' "$1" | tr -d '#'; }

# ===== the managed block in a text file =====
block_remove() {
    f="$1"; [ -f "$f" ] || return 0
    grep -qF "sekaipop: managed block" "$f" || return 0
    awk -v m="sekaipop: managed block" '
        skip > 0 { skip--; next }
        index($0, m) > 0 { skip = 1; next }
        { print }' "$f" > "$f.sekaipop-tmp" && cat "$f.sekaipop-tmp" > "$f"
    rm -f "$f.sekaipop-tmp"
}
# block_add_end <file> <line> / block_add_top <file> <line>
block_add_end() {
    f="$1"; line="$2"
    block_remove "$f"
    mkdir -p "$(dirname "$f")" || return 1
    [ -f "$f" ] && [ -n "$(tail -c1 "$f")" ] && echo >> "$f"
    printf '%s\n%s\n' "$MARK" "$line" >> "$f"
}
block_add_top() {
    f="$1"; line="$2"
    block_remove "$f"
    mkdir -p "$(dirname "$f")" || return 1
    if [ -f "$f" ]; then
        { printf '%s\n%s\n' "$MARK" "$line"; cat "$f"; } > "$f.sekaipop-tmp" && cat "$f.sekaipop-tmp" > "$f"
        rm -f "$f.sekaipop-tmp"
    else
        printf '%s\n%s\n' "$MARK" "$line" > "$f"
    fi
}

# ===== foot =====
foot_file="$cfg/foot/sekaipop-colors.ini"
foot_conf="$cfg/foot/foot.ini"
foot_apply() {
    have foot || [ -d "$cfg/foot" ] || { echo "foot is not installed"; return 3; }
    mkdir -p "$cfg/foot" || return 1
    {
        echo "# Written by sekaipop (app-theme.sh). Do not edit: it is rewritten with the theme."
        echo "[colors]"
        echo "foreground=$(nh "$col_fg")"
        echo "background=$(nh "$col_bg")"
        echo "selection-foreground=$(nh "$col_selfg")"
        echo "selection-background=$(nh "$col_selbg")"
        echo "cursor=$(nh "$col_bg") $(nh "$col_cursor")"
        echo "urls=$(nh "$col_accent")"
        i=0
        while [ $i -le 7 ]; do eval "echo regular$i=\$(nh \"\$col_c$i\")"; i=$((i + 1)); done
        i=0
        while [ $i -le 7 ]; do j=$((i + 8)); eval "echo bright$i=\$(nh \"\$col_c$j\")"; i=$((i + 1)); done
    } > "$foot_file" || return 1
    block_add_top "$foot_conf" "include=$foot_file" || return 1
    return 0
}
foot_revert() { block_remove "$foot_conf"; rm -f "$foot_file"; return 0; }
foot_status() {
    if grep -qF "sekaipop: managed block" "$foot_conf" 2>/dev/null; then echo on
    elif have foot || [ -d "$cfg/foot" ]; then echo off
    else echo missing; fi
}

# ===== fuzzel =====
fuzzel_file="$cfg/fuzzel/sekaipop-colors.ini"
fuzzel_conf="$cfg/fuzzel/fuzzel.ini"
fuzzel_apply() {
    have fuzzel || [ -d "$cfg/fuzzel" ] || { echo "fuzzel is not installed"; return 3; }
    mkdir -p "$cfg/fuzzel" || return 1
    {
        echo "# Written by sekaipop (app-theme.sh). Do not edit: it is rewritten with the theme."
        echo "[colors]"
        echo "background=$(nh "$col_surface")f2"
        echo "text=$(nh "$col_fg")ff"
        echo "prompt=$(nh "$col_accent")ff"
        echo "placeholder=$(nh "$col_muted")ff"
        echo "input=$(nh "$col_fg")ff"
        echo "match=$(nh "$col_accent2")ff"
        echo "selection=$(nh "$col_selbg")ff"
        echo "selection-text=$(nh "$col_selfg")ff"
        echo "selection-match=$(nh "$col_accent")ff"
        echo "counter=$(nh "$col_muted")ff"
        echo "border=$(nh "$col_accent")ff"
    } > "$fuzzel_file" || return 1
    block_add_top "$fuzzel_conf" "include=$fuzzel_file" || return 1
    return 0
}
fuzzel_revert() { block_remove "$fuzzel_conf"; rm -f "$fuzzel_file"; return 0; }
fuzzel_status() {
    if grep -qF "sekaipop: managed block" "$fuzzel_conf" 2>/dev/null; then echo on
    elif have fuzzel || [ -d "$cfg/fuzzel" ]; then echo off
    else echo missing; fi
}

# ===== rofi =====
rofi_file="$cfg/rofi/sekaipop-colors.rasi"
rofi_conf="$cfg/rofi/config.rasi"
rofi_apply() {
    have rofi || [ -d "$cfg/rofi" ] || { echo "rofi is not installed"; return 3; }
    mkdir -p "$cfg/rofi" || return 1
    {
        echo "/* Written by sekaipop (app-theme.sh). Do not edit: it is rewritten with the theme. */"
        echo "* {"
        echo "    background:     $col_surface;"
        echo "    background-alt: $col_hover;"
        echo "    foreground:     $col_fg;"
        echo "    selected:       $col_accent;"
        echo "    active:         $col_accent2;"
        echo "    urgent:         #ff6f91;"
        echo "}"
    } > "$rofi_file" || return 1
    # rasi comments are /* */, so the marker is written as one.
    block_remove "$rofi_conf"
    mkdir -p "$(dirname "$rofi_conf")"
    [ -f "$rofi_conf" ] && [ -n "$(tail -c1 "$rofi_conf")" ] && echo >> "$rofi_conf"
    printf '/* sekaipop: managed block, removed by Settings -> Desktop -> App colours (revert) */\n@import "sekaipop-colors.rasi"\n' >> "$rofi_conf"
    return 0
}
rofi_revert() { block_remove "$rofi_conf"; rm -f "$rofi_file"; return 0; }
rofi_status() {
    if grep -qF "sekaipop: managed block" "$rofi_conf" 2>/dev/null; then echo on
    elif have rofi || [ -d "$cfg/rofi" ]; then echo off
    else echo missing; fi
}

# ===== VS Code =====
vscode_dirs() {
    for d in "Code" "Code - OSS" "VSCodium" "Cursor"; do
        [ -d "$cfg/$d/User" ] && printf '%s\n' "$cfg/$d/User"
    done
}
vscode_block() {
    a="$col_accent"
    cat <<JSON
/* sekaipop:begin */ "workbench.colorCustomizations": {
    "editor.background": "$col_bg", "editor.foreground": "$col_fg",
    "editor.selectionBackground": "$col_selbg", "editorCursor.foreground": "$col_cursor",
    "editorLineNumber.foreground": "$col_muted", "editorLineNumber.activeForeground": "$col_fg",
    "editor.lineHighlightBackground": "${col_hover}66",
    "sideBar.background": "$col_surface", "sideBar.foreground": "$col_fg",
    "sideBarSectionHeader.background": "$col_bg",
    "activityBar.background": "$col_surface", "activityBar.foreground": "$a", "activityBar.inactiveForeground": "$col_muted",
    "activityBarBadge.background": "$a", "activityBarBadge.foreground": "$col_bg",
    "titleBar.activeBackground": "$col_surface", "titleBar.activeForeground": "$col_fg",
    "titleBar.inactiveBackground": "$col_bg", "titleBar.inactiveForeground": "$col_muted",
    "statusBar.background": "$a", "statusBar.foreground": "$col_bg", "statusBar.noFolderBackground": "$col_surface",
    "tab.activeBackground": "$col_bg", "tab.activeForeground": "$col_fg", "tab.activeBorderTop": "$a",
    "tab.inactiveBackground": "$col_surface", "tab.inactiveForeground": "$col_muted",
    "editorGroupHeader.tabsBackground": "$col_surface",
    "list.activeSelectionBackground": "$col_selbg", "list.activeSelectionForeground": "$col_selfg",
    "list.hoverBackground": "$col_hover",
    "button.background": "$a", "button.foreground": "$col_bg",
    "focusBorder": "$a", "progressBar.background": "$a",
    "terminal.background": "$col_bg", "terminal.foreground": "$col_fg",
    "terminal.ansiBlack": "$col_c0", "terminal.ansiRed": "$col_c1", "terminal.ansiGreen": "$col_c2", "terminal.ansiYellow": "$col_c3",
    "terminal.ansiBlue": "$col_c4", "terminal.ansiMagenta": "$col_c5", "terminal.ansiCyan": "$col_c6", "terminal.ansiWhite": "$col_c7",
    "terminal.ansiBrightBlack": "$col_c8", "terminal.ansiBrightRed": "$col_c9", "terminal.ansiBrightGreen": "$col_c10", "terminal.ansiBrightYellow": "$col_c11",
    "terminal.ansiBrightBlue": "$col_c12", "terminal.ansiBrightMagenta": "$col_c13", "terminal.ansiBrightCyan": "$col_c14", "terminal.ansiBrightWhite": "$col_c15"
}, /* sekaipop:end */
JSON
}
# safe_replace <tmp> <dest>: only overwrite dest with a tmp that has content.
safe_replace() {
    if [ -s "$1" ]; then cat "$1" > "$2"; fi
    rm -f "$1"
}
# vscode_strip <file>: take our block out (the lines from the begin marker to
# the end marker, both included).
vscode_strip() {
    f="$1"; [ -f "$f" ] || return 0
    grep -qF "sekaipop:begin" "$f" || return 0
    awk '
        index($0, "/* sekaipop:begin */") > 0 { skip = 1 }
        skip { if (index($0, "/* sekaipop:end */") > 0) skip = 0; next }
        { print }' "$f" > "$f.sekaipop-tmp"
    safe_replace "$f.sekaipop-tmp" "$f"
}
# vscode_insert <file> <blockfile>: the block goes right after the first "{"
# (a line comment above it is skipped over).
vscode_insert() {
    f="$1"; blk="$2"
    awk -v blk="$blk" '
        !done && $0 !~ /^[ \t]*\/\// && (i = index($0, "{")) > 0 {
            print substr($0, 1, i)
            while ((getline line < blk) > 0) print line
            rest = substr($0, i + 1)
            if (rest != "") print rest
            done = 1
            next
        }
        { print }' "$f" > "$f.sekaipop-tmp"
    safe_replace "$f.sekaipop-tmp" "$f"
}
vscode_apply() {
    dirs=$(vscode_dirs)
    [ -n "$dirs" ] || { echo "VS Code settings folder not found"; return 3; }
    printf '%s\n' "$dirs" | while IFS= read -r d; do
        f="$d/settings.json"
        [ -f "$f" ] || printf '{\n}\n' > "$f"
        vscode_strip "$f"
        if grep -q '"workbench.colorCustomizations"' "$f"; then
            mkdir -p "$cfg/sekaipop"
            vscode_block > "$cfg/sekaipop/vscode-colors.json"
            echo "$f already has workbench.colorCustomizations; colours saved to $cfg/sekaipop/vscode-colors.json" >&2
            continue
        fi
        blkfile="$f.sekaipop-block"
        vscode_block > "$blkfile"
        vscode_insert "$f" "$blkfile"
        rm -f "$blkfile"
    done
    return 0
}
vscode_revert() {
    vscode_dirs | while IFS= read -r d; do vscode_strip "$d/settings.json"; done
    rm -f "$cfg/sekaipop/vscode-colors.json"
    return 0
}
vscode_status() {
    dirs=$(vscode_dirs)
    [ -n "$dirs" ] || { echo missing; return; }
    if printf '%s\n' "$dirs" | while IFS= read -r d; do
        grep -qF "sekaipop:begin" "$d/settings.json" 2>/dev/null && exit 0
    done; then echo on; else echo off; fi
}

# ===== fish (and the colour palette of every open terminal) =====
# Two layers, both live:
#  1. fish's own colours (fish_color_*) as universal variables: every running fish picks them up at once.
#  2. the terminal palette as escape sequences (colours 0-15, text, background, cursor, selection): written to a file,
#     pushed into every open terminal, and printed again by one line at the end of config.fish for new shells.
#     starship, eza, ls and anything else that uses the named colours follow it.
fish_state="${XDG_STATE_HOME:-$HOME/.local/state}/sekaipop/terminal"
fish_seq="$fish_state/sequences.txt"
fish_conf="$cfg/fish/config.fish"
fish_names="fish_color_normal fish_color_command fish_color_keyword fish_color_quote fish_color_redirection fish_color_end fish_color_error fish_color_param fish_color_option fish_color_comment fish_color_selection fish_color_operator fish_color_escape fish_color_autosuggestion fish_color_cwd fish_color_cwd_root fish_color_user fish_color_host fish_color_host_remote fish_color_status fish_color_search_match fish_pager_color_progress fish_pager_color_prefix fish_pager_color_completion fish_pager_color_description fish_pager_color_selected_background"

osc() { printf '\033]%s;%s\033\\' "$1" "$2"; }
getc() { eval "printf '%s' \"\$col_c$1\""; }

fish_push() {
    for p in /dev/pts/[0-9]*; do
        [ -c "$p" ] && [ -w "$p" ] && [ -O "$p" ] || continue
        ( cat "$1" > "$p" 2>/dev/null & )
    done
}

fish_apply() {
    have fish || [ -d "$cfg/fish" ] || { echo "fish is not installed"; return 3; }
    mkdir -p "$fish_state" || return 1
    {
        i=0
        while [ $i -le 15 ]; do osc "4;$i" "$(getc $i)"; i=$((i + 1)); done
        osc 10 "$col_fg"
        osc 11 "$col_bg"
        osc 12 "$col_cursor"
        osc 17 "$col_selbg"
        osc 19 "$col_selfg"
    } > "$fish_seq.tmp" && mv "$fish_seq.tmp" "$fish_seq" || return 1

    # one line at the END of config.fish: runs after anything else there that prints colours
    block_add_end "$fish_conf" "status is-interactive; and test -f '$fish_seq'; and cat '$fish_seq'" || return 1

    if have fish; then
        h() { nh "$1"; }
        fish -c "
            set -U fish_color_normal $(h "$col_fg")
            set -U fish_color_command $(h "$col_accent")
            set -U fish_color_keyword $(h "$col_accent2")
            set -U fish_color_quote $(h "$col_c2")
            set -U fish_color_redirection $(h "$col_c6")
            set -U fish_color_end $(h "$col_c5")
            set -U fish_color_error $(h "$col_c1")
            set -U fish_color_param $(h "$col_fg")
            set -U fish_color_option $(h "$col_c6")
            set -U fish_color_comment $(h "$col_muted")
            set -U fish_color_selection $(h "$col_selfg") --bold --background=$(h "$col_selbg")
            set -U fish_color_operator $(h "$col_accent2")
            set -U fish_color_escape $(h "$col_c6")
            set -U fish_color_autosuggestion $(h "$col_muted")
            set -U fish_color_cwd $(h "$col_accent")
            set -U fish_color_cwd_root $(h "$col_c1")
            set -U fish_color_user $(h "$col_c2")
            set -U fish_color_host $(h "$col_c4")
            set -U fish_color_host_remote $(h "$col_c3")
            set -U fish_color_status $(h "$col_c1")
            set -U fish_color_search_match $(h "$col_fg") --background=$(h "$col_hover")
            set -U fish_pager_color_progress $(h "$col_bg") --background=$(h "$col_accent")
            set -U fish_pager_color_prefix $(h "$col_accent") --bold --underline
            set -U fish_pager_color_completion $(h "$col_fg")
            set -U fish_pager_color_description $(h "$col_muted")
            set -U fish_pager_color_selected_background --background=$(h "$col_selbg")
        " || echo "fish: could not set fish's own colours" >&2
    fi

    fish_push "$fish_seq"
    return 0
}

fish_revert() {
    block_remove "$fish_conf"
    rm -f "$fish_seq"
    if have fish; then
        fish -c "for n in $fish_names; set -e -U \$n; end" 2>/dev/null
    fi
    # give every open terminal its own colours back (reset palette, text, background, cursor, selection)
    reset="$fish_state/reset.tmp"
    mkdir -p "$fish_state" 2>/dev/null
    { osc 104 ""; osc 110 ""; osc 111 ""; osc 112 ""; osc 117 ""; osc 119 ""; } > "$reset" 2>/dev/null
    # the prompt target's palette entries are part of what osc 104 just reset: put them back while it is on
    [ -f "$prompt_seq" ] && cat "$prompt_seq" >> "$reset" 2>/dev/null
    fish_push "$reset"
    ( sleep 2; rm -f "$reset" ) >/dev/null 2>&1 &
    return 0
}

fish_status() {
    if grep -qF "sekaipop: managed block" "$fish_conf" 2>/dev/null; then echo on
    elif have fish || [ -d "$cfg/fish" ]; then echo off
    else echo missing; fi
}

# ===== prompt (capsule pills with a hard shadow, for fish) =====
# See the header. The prompt's colours are fixed 256-colour indices, so the theme reaches it by
# redefining those indices in the terminal (OSC 4); the other 249 entries are left alone.
prompt_src="$here/prompt-sekaipop.sh"
prompt_bin="$fish_state/prompt.sh"
prompt_seq="$fish_state/prompt-sequences.txt"
prompt_conf="$cfg/fish/conf.d/sekaipop-prompt.fish"
prompt_indices="255 252 254 235 240 241 244 243"

# index colour, one pair per line: 255 the folder plate, 252 the git-branch plate, 254 the
# command-time plate, 235 the dark ink on them, 240 the outline, 241 the hard shadow under them,
# 244 a failed command (plate and arrow), 243 the arrow
prompt_pairs() {
    echo "255 ${col_ptA:-$col_accent}"
    echo "252 ${col_ptB:-$col_accent2}"
    echo "254 ${col_ptPaper:-${col_pill:-$col_surface}}"
    echo "235 ${col_ptInk:-$col_bg}"
    echo "240 ${col_ptLine:-$col_border}"
    echo "241 ${col_shadow:-$col_muted}"
    echo "244 ${col_ptFail:-${col_c1:-$col_accent2}}"
    echo "243 ${col_ptA:-$col_accent}"
}

# The first version of this was a "starship" target (the illogical-impulse pills through
# STARSHIP_CONFIG): if its files are still there, take them away.
prompt_legacy_cleanup() {
    old_toml="$cfg/sekaipop/starship.toml"
    old_conf="$cfg/fish/conf.d/sekaipop-starship.fish"
    [ -f "$old_toml" ] || [ -f "$old_conf" ] || return 0
    rm -f "$old_conf" "$old_toml" "$fish_state/starship-sequences.txt"
    rmdir "$cfg/sekaipop" 2>/dev/null
    if have fish; then
        fish -c "if string match -q -- 'STARSHIP_CONFIG $old_toml' (set -U); set -e -U STARSHIP_CONFIG; end" 2>/dev/null
    fi
}

prompt_apply() {
    have fish || [ -d "$cfg/fish" ] || { echo "fish is not installed"; return 3; }
    [ -f "$prompt_src" ] || { echo "prompt-sekaipop.sh is missing next to app-theme.sh" >&2; return 1; }
    mkdir -p "$fish_state" "$cfg/fish/conf.d" || return 1
    prompt_legacy_cleanup
    cp "$prompt_src" "$prompt_bin.tmp" && chmod +x "$prompt_bin.tmp" && mv "$prompt_bin.tmp" "$prompt_bin" || return 1
    prompt_pairs | while read -r i c; do osc "4;$i" "$c"; done > "$prompt_seq.tmp" \
        && mv "$prompt_seq.tmp" "$prompt_seq" || return 1
    # fish_prompt is (re)defined once now and once more before the first prompt, so a prompt
    # that config.fish sets up later (a `starship init fish | source`, say) does not win.
    {
        echo "# sekaipop: managed file, removed by Settings -> Desktop -> App colours (revert)"
        echo "if status is-interactive"
        echo "    test -f '$prompt_seq'; and cat '$prompt_seq'"
        echo "    function __sekaipop_define_prompt"
        echo "        function fish_prompt"
        echo "            set -l last \$status"
        echo "            if test -f '$prompt_bin'"
        echo "                sh '$prompt_bin' \$last \"\$CMD_DURATION\" \"\$PWD\" \"\$COLUMNS\""
        echo "            else"
        echo "                functions --erase fish_prompt"
        echo "                fish_prompt"
        echo "            end"
        echo "        end"
        echo "    end"
        echo "    __sekaipop_define_prompt"
        echo "    function __sekaipop_keep_prompt --on-event fish_prompt"
        echo "        __sekaipop_define_prompt"
        echo "        functions --erase __sekaipop_keep_prompt"
        echo "    end"
        echo "end"
    } > "$prompt_conf" || return 1
    fish_push "$prompt_seq"
    return 0
}

prompt_revert() {
    prompt_legacy_cleanup
    rm -f "$prompt_conf" "$prompt_bin" "$prompt_seq"
    reset="$fish_state/prompt-reset.tmp"
    mkdir -p "$fish_state" 2>/dev/null
    for i in $prompt_indices; do osc 104 "$i"; done > "$reset" 2>/dev/null
    fish_push "$reset"
    ( sleep 2; rm -f "$reset" ) >/dev/null 2>&1 &
    return 0
}

prompt_status() {
    if [ -f "$prompt_conf" ]; then echo on
    elif have fish || [ -d "$cfg/fish" ]; then echo off
    else echo missing; fi
}

# ===== hyprland (window borders) =====
# The active and inactive window borders take the theme's colours, written to
# ~/.config/hypr/sekaipop_overrides.lua (the file the Hyprland page of the Settings
# Panel also writes, and which hyprland.lua loads with
# `pcall(require, "sekaipop_overrides")`) as ONE line tagged "-- sekaipop:apptheme:hyprland",
# and applied live with `hyprctl eval`. Revert deletes that line and reloads Hyprland, which
# gives back the colours of your own hyprland.lua. The thickness is not touched
# (Settings -> Hyprland -> Gaps & borders -> Border thickness; 0 means no border at all).
hypr_file="$cfg/hypr/sekaipop_overrides.lua"
HMARK="-- sekaipop:apptheme:hyprland"
hyprland_drop() {
    [ -f "$hypr_file" ] || return 0
    tmp=$(mktemp "$cfg/hypr/.sekaipop_overrides.XXXXXX") || return 1
    grep -v -F -e "$HMARK" "$hypr_file" > "$tmp"
    [ $? -le 1 ] || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp"
    mv -f "$tmp" "$hypr_file" || { rm -f "$tmp"; return 1; }
}
hyprland_apply() {
    have hyprctl || [ -d "$cfg/hypr" ] || { echo "Hyprland is not installed"; return 3; }
    # The borders' own colours; the accent and the muted tone if a caller sent none.
    act="${col_hlactive:-$col_accent}"; ina="${col_hlinactive:-$col_muted}"
    [ -n "$act" ] && [ -n "$ina" ] || { echo "missing colours" >&2; return 2; }
    mkdir -p "$cfg/hypr" || return 1
    [ -e "$hypr_file" ] || : > "$hypr_file"
    hyprland_drop || return 1
    tbl="{ [\"general\"] = { [\"col\"] = { [\"active_border\"] = \"rgba($(nh "$act")ee)\", [\"inactive_border\"] = \"rgba($(nh "$ina")cc)\" } } }"
    # pcall: a bad value must not stop the lines below it in the override file.
    printf 'pcall(hl.config, %s) %s\n' "$tbl" "$HMARK" >> "$hypr_file" || return 1
    have hyprctl || return 0
    out=$(hyprctl eval "hl.config($tbl)" 2>&1)
    case "$out" in
        ok*|"") ;;
        *) echo "hyprland: Hyprland did not take the colours live ($out); they are in $hypr_file for the next reload" >&2 ;;
    esac
    return 0
}
hyprland_revert() {
    hyprland_drop
    have hyprctl && hyprctl reload >/dev/null 2>&1
    return 0
}
hyprland_status() {
    if grep -qF -e "$HMARK" "$hypr_file" 2>/dev/null; then echo on
    elif have hyprctl || [ -d "$cfg/hypr" ]; then echo off
    else echo missing; fi
}

# ===== dispatch =====
case "$cmd" in
    apply)
        [ -n "$col_bg" ] && [ -n "$col_fg" ] && [ -n "$col_accent" ] || { echo "missing colours" >&2; exit 2; }
        case "$target" in
            foot) foot_apply ;; vscode) vscode_apply ;;
            fuzzel) fuzzel_apply ;; rofi) rofi_apply ;; fish) fish_apply ;;
            prompt) prompt_apply ;; hyprland) hyprland_apply ;;
            *) echo "unknown target: $target" >&2; exit 2 ;;
        esac
        exit $?
        ;;
    revert)
        case "$target" in
            foot) foot_revert ;; vscode) vscode_revert ;;
            fuzzel) fuzzel_revert ;; rofi) rofi_revert ;; fish) fish_revert ;;
            prompt) prompt_revert ;; hyprland) hyprland_revert ;;
            *) echo "unknown target: $target" >&2; exit 2 ;;
        esac
        exit $?
        ;;
    status)
        for t in kitty foot vscode fuzzel rofi fish prompt hyprland; do printf '%s=%s\n' "$t" "$(${t}_status)"; done
        ;;
    *)
        echo "usage: $0 apply <target> k=v ...|revert <target>|status" >&2
        exit 2
        ;;
esac
