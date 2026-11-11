#!/usr/bin/env bash
# install.sh: one command to turn a minimal Hyprland system into the SekaiPop desktop.
#
# What it does:
#   1. dependencies   packages, fonts, services, groups     (runs install-deps.sh)
#   2. the rice       copied to ~/.config/quickshell/sekaipop
#   3. Hyprland       a ready configuration in ~/.config/hypr (keybinds, rules, autostart),
#                     so after a re-login the shell simply starts. monitors.lua is not shipped:
#                     your own is kept, otherwise one is made for the screens connected now.
# Your old Hyprland config is never deleted: it is moved to ~/.config/hypr.sekaipop-backup-<time>
# and  ./install.sh --restore  puts it back.
#
# Usage:  ./install.sh [options] [-- options for install-deps.sh]
#   --dry-run           show what would happen, change nothing
#   --yes               no questions
#   --rice DIR          the sekaipop folder (default: ./sekaipop next to this script)
#   --hypr MODE         full   = install the preconfigured Hyprland config (default for a new setup)
#                       merge  = keep YOUR config, only add a small sekaipop_session file to it
#                       skip   = do not touch Hyprland at all
#   --kitty MODE        keep   = keep the current Kitty theme choice
#                       enable = opt in to SekaiPop's Kitty colours after validation
#   --restore-kitty     remove only SekaiPop's Kitty colour integration and exit
#   --no-deps           do not install packages / services (only copy files)
#   --with-tests        also copy the developer tests folder
#   --restore           put back the Hyprland config that was backed up by the last run
#   -h, --help
#
# Run as your normal user (it uses sudo where needed). Needs Arch / CachyOS / EndeavourOS for the packages.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

REPLACED=0; DRY=0; YES=0; RICE=""; HYPR=auto; KITTY=auto; NODEPS=0; WITH_TESTS=0; RESTORE=0; RESTORE_KITTY=0; DEPS_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --yes|-y) YES=1 ;;
        --rice) shift; RICE=${1:-} ;;
        --hypr) shift; HYPR=${1:-}; case "$HYPR" in full|merge|skip) ;; *) echo "--hypr needs full|merge|skip" >&2; exit 2 ;; esac ;;
        --kitty) shift; KITTY=${1:-}; case "$KITTY" in keep|enable) ;; *) echo "--kitty needs keep|enable" >&2; exit 2 ;; esac ;;
        --restore-kitty) RESTORE_KITTY=1 ;;
        --no-deps) NODEPS=1 ;;
        --with-tests) WITH_TESTS=1 ;;
        --restore) RESTORE=1 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        --) shift; DEPS_ARGS=("$@"); break ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

# ---- look: the same style in install.sh, install-deps.sh, check-deps.sh and get.sh -------------
# Colours only on a terminal (NO_COLOR turns them off). On the bare Linux console (TERM=linux) or a
# non-UTF-8 locale the symbols fall back to plain ASCII, because a TTY font often can't draw them.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    B=$'\e[1m'; D=$'\e[2m'; Z=$'\e[0m'
    C=$'\e[38;5;80m'; PK=$'\e[38;5;211m'; Y=$'\e[38;5;221m'; R=$'\e[38;5;203m'; GR=$'\e[38;5;114m'
else B=; D=; Z=; C=; PK=; Y=; R=; GR=; fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UI_UTF=1 ;; *) UI_UTF=0 ;; esac
[ "${TERM:-}" = linux ] && UI_UTF=0
if [ "$UI_UTF" = 1 ]; then
    G_OK='✔'; G_BAD='✘'; G_DOT='•'; G_ARR='›'; G_HR='─'; G_TL='╭'; G_TR='╮'; G_BL='╰'; G_BR='╯'; G_V='│'; G_NOTE='♪'
else
    G_OK='+'; G_BAD='x'; G_DOT='-'; G_ARR='>'; G_HR='-'; G_TL='+'; G_TR='+'; G_BL='+'; G_BR='+'; G_V='|'; G_NOTE='*'
fi
UI_W=$(tput cols 2>/dev/null || echo 72); case "$UI_W" in ''|*[!0-9]*) UI_W=72 ;; esac
[ "$UI_W" -gt 76 ] && UI_W=76; [ "$UI_W" -lt 56 ] && UI_W=56
UI_BW=50
rep() { local i s=""; for ((i = 0; i < $2; i++)); do s+=$1; done; printf '%s' "$s"; }
step() { local n=$((UI_W - ${#1} - 5)); [ "$n" -lt 3 ] && n=3
    printf '\n%s%s%s %s%s%s %s%s%s\n' "$C" "$G_HR$G_HR" "$Z" "$B" "$1" "$Z" "$D" "$(rep "$G_HR" "$n")" "$Z"; }
info() { printf '  %s%s%s %s\n' "$D" "$G_DOT" "$Z" "$1"; }
ok()   { printf '  %s%s%s %s\n' "$GR" "$G_OK" "$Z" "$1"; }
warn() { printf '  %s!%s %s%s%s\n' "$Y" "$Z" "$Y" "$1" "$Z"; }
FAILED=()
fail() { printf '  %s%s%s %s%s%s\n' "$R" "$G_BAD" "$Z" "$R" "$1" "$Z"; FAILED+=("$1"); }
boxrow() { local t=$1 col=${2:-} plain=${1//"$G_NOTE"/x} pad; pad=$((UI_BW - ${#plain})); [ "$pad" -lt 0 ] && pad=0
    printf '  %s%s%s%s%s%s%*s%s%s%s\n' "$PK" "$G_V" "$Z" "$col" "$t" "$Z" "$pad" "" "$PK" "$G_V" "$Z"; }
banner() { # banner <title> <subtitle>
    printf '\n  %s%s%s%s\n' "$PK" "$G_TL" "$(rep "$G_HR" "$UI_BW")" "$G_TR$Z"
    boxrow "  $G_NOTE  $1" "$B"
    boxrow "     $2" "$D"
    printf '  %s%s%s%s\n' "$PK" "$G_BL" "$(rep "$G_HR" "$UI_BW")" "$G_BR$Z"
}
result() { # result ok|bad <text>
    local col=$GR sym=$G_OK; [ "$1" = bad ] && { col=$R; sym=$G_BAD; }
    printf '\n  %s%s %s%s\n' "$col$B" "$sym" "$2" "$Z"
}
nx() { printf '  %s%s%s %s\n' "$PK" "$G_ARR" "$Z" "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() {
    if [ "$DRY" = 1 ]; then printf '  %s%s%s %swould run%s' "$PK" "$G_ARR" "$Z" "$D" "$Z"; printf ' %q' "$@"; printf '\n'; return 0; fi
    "$@"
}
ask() { # ask <question>: yes by default; always yes with --yes / --dry-run
    { [ "$YES" = 1 ] || [ "$DRY" = 1 ]; } && return 0
    local a; read -r -p "  ${PK}?${Z} $1 ${D}[Y/n]${Z} " a; case "$a" in n|N|no|No) return 1 ;; *) return 0 ;; esac
}
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }   # ver_ge A B: A >= B

CFG=${XDG_CONFIG_HOME:-$HOME/.config}
HYPR_DEST="$CFG/hypr"
QS_DEST="$CFG/quickshell/sekaipop"
TS=$(date +%Y%m%d-%H%M%S)
hypr_running() { [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && have hyprctl && hyprctl version >/dev/null 2>&1; }

banner "SekaiPop installer" "Quickshell + Hyprland desktop"

if [ "$RESTORE_KITTY" = 1 ]; then
    step "Restoring Kitty colours"
    KITTY_THEME="$HERE/sekaipop/scripts/theming/app-theme.sh"
    if [ ! -f "$KITTY_THEME" ] || [ ! -f "$HERE/sekaipop/scripts/theming/kitty-theme.py" ]; then
        echo "The bundled Kitty helper is missing. Run --restore-kitty from a complete current SekaiPop checkout." >&2
        exit 1
    fi
    KITTY_FLAGS=()
    [ "$DRY" = 1 ] && KITTY_FLAGS+=(--dry-run)
    sh "$KITTY_THEME" revert kitty "${KITTY_FLAGS[@]}" || exit $?
    exit 0
fi

if [ "$RESTORE" = 1 ] && [ "$HYPR" = skip ]; then
    echo "--restore cannot be combined with --hypr skip." >&2
    exit 2
fi

# Anything left from when SekaiPop was called pjsekai (settings, presets, app-colour blocks, the
# Hyprland overrides file and backups) is moved to the new name first, respecting --hypr skip.
if [ -f "$HERE/sekaipop/scripts/system/migrate-from-pjsekai.sh" ]; then
    MIGRATE_FLAGS=()
    [ "$DRY" = 1 ] && MIGRATE_FLAGS+=(--dry-run)
    [ "$HYPR" = skip ] && MIGRATE_FLAGS+=(--skip-hypr)
    sh "$HERE/sekaipop/scripts/system/migrate-from-pjsekai.sh" "${MIGRATE_FLAGS[@]}"
fi

# ------------------------------------------------------------------ --restore
if [ "$RESTORE" = 1 ]; then
    step "Restoring your previous Hyprland config"
    last=$(ls -d "$CFG"/hypr.sekaipop-backup-* 2>/dev/null | sort | tail -1)
    [ -n "$last" ] || { echo "No backup of your own config found (looked for $CFG/hypr.sekaipop-backup-*)." >&2
        [ -d "$CFG/hypr.sekaipop-previous" ] && echo "There is $CFG/hypr.sekaipop-previous: the sekaipop config from before the last update." >&2
        exit 1; }
    info "backup: $last"
    ask "Put it back as $HYPR_DEST (the current one is kept as hypr.sekaipop-replaced-$TS)?" || exit 0
    [ -e "$HYPR_DEST" ] && run mv "$HYPR_DEST" "$CFG/hypr.sekaipop-replaced-$TS"
    run cp -a "$last" "$HYPR_DEST"
    ok "done. Reload Hyprland (or log out and in) to use it."
    exit 0
fi

# ------------------------------------------------------------------ checks
step "Checking the system"
[ "$(id -u)" = 0 ] && { echo "Run this as your normal user, not root (it calls sudo itself)." >&2; exit 1; }
[ "$DRY" = 1 ] && info "DRY RUN: nothing will be changed."

# the rice
if [ -z "$RICE" ]; then
    for c in "$HERE/sekaipop" "$HERE/../sekaipop" "$HERE"; do
        [ -f "$c/shell.qml" ] && { RICE=$c; break; }
    done
fi
if [ -z "$RICE" ] || [ ! -f "$RICE/shell.qml" ]; then
    echo "Could not find the sekaipop folder (the one with shell.qml)." >&2
    echo "Put it next to install.sh, or pass:  --rice /path/to/sekaipop" >&2
    exit 1
fi
RICE=$(cd "$RICE" && pwd)
FIRST_INSTALL=0; [ -f "$QS_DEST/shell.qml" ] || FIRST_INSTALL=1
VERSION=$(cat "$RICE/VERSION" 2>/dev/null || echo unknown)
ok "rice: $RICE ${D}(version $VERSION)${Z}"

# Hyprland config: Lua needs Hyprland 0.55+
HV=""
if have hyprctl && hypr_running; then HV=$(hyprctl version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
elif have Hyprland; then HV=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1); fi
if [ -n "$HV" ]; then ok "Hyprland $HV"; else info "Hyprland: not found / version unknown"; fi
HAVE_CFG=0; [ -f "$HYPR_DEST/hyprland.lua" ] || [ -f "$HYPR_DEST/hyprland.conf" ] && HAVE_CFG=1
SRC_HYPR="$HERE/hypr"
[ -d "$SRC_HYPR" ] || { [ "$HYPR" = skip ] || [ "$HYPR" = merge ] || { echo "The preconfigured Hyprland files are missing ($SRC_HYPR)." >&2; exit 1; }; }

if [ "$HYPR" = auto ]; then
    HYPR=full
    if [ "$HAVE_CFG" = 1 ]; then
        if grep -qsE 'SekaiPop( \(pjsekai\))?: Hyprland configuration' "$HYPR_DEST/hyprland.lua" 2>/dev/null; then
            info "your Hyprland config is already the sekaipop one: it will be updated (your custom/ folder is kept)"
        else
            warn "you already have a Hyprland config in $HYPR_DEST."
            info "'full' replaces it with the sekaipop one (keybinds, rules, autostart). Yours is moved to"
            info "$CFG/hypr.sekaipop-backup-$TS and  ./install.sh --restore  puts it back."
            ask "Replace it? (n = keep yours and only add the small sekaipop_session file)" || HYPR=merge
        fi
    fi
fi
if [ "$HYPR" = full ] && [ -n "$HV" ] && ! ver_ge "$HV" 0.55; then
    warn "Hyprland $HV is older than 0.55, which is the first with the Lua config this installer writes."
    warn "Falling back to 'merge' (your hyprlang config stays; a small sekaipop_session.conf is added)."
    HYPR=merge
fi
info "Hyprland config mode: $HYPR"

# ------------------------------------------------------------------ 1. dependencies
if [ "$NODEPS" = 0 ]; then
    step "1. Dependencies, fonts, services"
    FLAGS=()
    [ "$DRY" = 1 ] && FLAGS+=(--dry-run)
    [ "$YES" = 1 ] && FLAGS+=(--yes)
    [ "$HYPR" != merge ] && FLAGS+=(--no-session)    # full/skip handle the session themselves
    SEKAIPOP_FULL_INSTALL=1 bash "$HERE/install-deps.sh" "${FLAGS[@]}" "${DEPS_ARGS[@]}" || fail "install-deps.sh reported problems (see above)"

    if [ "$HYPR" = full ] && have pacman; then
        # used by the keybinds / autostart of the preconfigured config
        EXTRA=()
        for p in playerctl hypridle; do pacman -T "$p" >/dev/null 2>&1 || EXTRA+=("$p"); done
        if [ "${#EXTRA[@]}" -gt 0 ]; then
            info "for the keybinds and idle lock: ${EXTRA[*]}"
            PF=(--needed); [ "$YES" = 1 ] && PF+=(--noconfirm)
            run sudo pacman -S "${PF[@]}" "${EXTRA[@]}" || fail "could not install ${EXTRA[*]}"
        fi
    fi
else
    step "1. Dependencies"; info "skipped (--no-deps)"
fi

# ------------------------------------------------------------------ 2. the rice
step "2. The rice -> $QS_DEST"
if [ -d "$QS_DEST" ] && [ "$(realpath "$QS_DEST")" = "$RICE" ]; then
    ok "the rice is already in place (installing from the same folder)"
elif [ -d "$QS_DEST" ] && diff -rq --exclude=tests --exclude=.git --exclude=.source "$RICE" "$QS_DEST" >/dev/null 2>&1; then
    ok "the installed copy is already identical to this one"
else
    if [ -e "$QS_DEST" ]; then
        info "an existing copy is there: it is kept as $QS_DEST.bak-$TS"
        ask "Replace it with version $VERSION?" || { echo "Stopped by you."; exit 0; }
        run mv "$QS_DEST" "$QS_DEST.bak-$TS" || fail "could not back up the old rice"
    fi
    run mkdir -p "$(dirname "$QS_DEST")"
    run cp -a "$RICE" "$QS_DEST" && REPLACED=1 || fail "could not copy the rice"
    run rm -rf "$QS_DEST/.git"
    [ "$WITH_TESTS" = 1 ] || run rm -rf "$QS_DEST/tests"
    [ "$DRY" = 1 ] || ok "copied (tests folder $([ "$WITH_TESTS" = 1 ] && echo kept || echo left out))"
fi

# Remember which commit these files came from, so About / Update -> "Update now" can tell what is newer.
# (Only when installing from a git checkout, which is what get.sh does; a zip has no commit to record.)
if [ "$DRY" != 1 ] && [ -d "$HERE/.git" ] && have git && [ -d "$QS_DEST" ] && [ "$(realpath "$QS_DEST")" != "$RICE" ]; then
    {
        echo "commit=$(git -C "$HERE" rev-parse HEAD)"
        echo "repo=$(git -C "$HERE" config --get remote.origin.url)"
        echo "ref=$(git -C "$HERE" rev-parse --abbrev-ref HEAD)"
    } > "$QS_DEST/.source" 2>/dev/null || true
fi

# shaders: .qsb files are built with Qt 6.12 and older Qt cannot read them
QTV=$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}' | grep -oE '^[0-9]+\.[0-9]+')
if [ -n "$QTV" ] && ! ver_ge "$QTV" 6.12; then
    info "Qt $QTV is older than 6.12: rebuilding the shaders once"
    if [ -f "$QS_DEST/shaders/compile-shaders.sh" ]; then
        run bash "$QS_DEST/shaders/compile-shaders.sh" || fail "shader build failed (needs qt6-shadertools)"
    fi
elif [ -n "$QTV" ]; then
    ok "Qt $QTV: the shipped shaders work as they are"
fi

# ------------------------------------------------------------------ optional Kitty colours
step "Kitty colours"
KITTY_THEME="$RICE/scripts/theming/app-theme.sh"
if [ ! -f "$RICE/scripts/theming/kitty-theme.py" ]; then
    if [ "$KITTY" = enable ]; then
        fail "This rice does not include the Kitty configuration checker."
    else
        warn "This rice does not include the Kitty configuration checker."
    fi
else
    # Detect the choice before asking. Only enable requests the helper's audit;
    # unrelated errors must not prevent the prompt or a routine reinstall.
    kitty_status=$(sh "$KITTY_THEME" status kitty) || kitty_status=conflict
    if [ "$KITTY" = auto ] && [ "$FIRST_INSTALL" = 1 ] && [ "$kitty_status" = off ] &&
        [ "$YES" = 0 ] && [ "$DRY" = 0 ] && [ -t 0 ]; then
        read -r -p "  Enable SekaiPop's dynamic Kitty colours? [y/N] " answer
        case "$answer" in y|Y|yes|YES) KITTY=enable ;; esac
    fi
    if [ "$KITTY" = enable ]; then
        KITTY_FLAGS=()
        [ "$DRY" = 1 ] && KITTY_FLAGS+=(--dry-run)
        if sh "$KITTY_THEME" enable kitty "${KITTY_FLAGS[@]}"; then
            if [ "$DRY" = 0 ]; then
                ok "Kitty hook is ready; palette sync is not yet confirmed."
                info "Start or restart SekaiPop with the same KITTY_CONFIG_DIRECTORY to supply the palette."
            fi
        else
            fail "Kitty colour sync could not be enabled (see above)"
        fi
    else
        info "Keeping the current Kitty colour choice."
        case "$kitty_status" in
            off|missing|on) ;;
            pending) info "Kitty integration is waiting for the current palette; start or restart SekaiPop." ;;
            blocked|conflict)
                warn "Kitty integration needs review; no Kitty configuration was changed."
                info "Inspect it with: sh \"$KITTY_THEME\" check kitty"
                ;;
            *) warn "Could not determine Kitty integration status; no Kitty configuration was changed." ;;
        esac
    fi
fi

# monitors.lua is made for THIS machine, never shipped: a file written for someone else's screens
# (a disabled laptop panel, an output that does not exist here) is what gives a black screen.
# Reads the connected outputs from the kernel (works on a TTY and inside Hyprland), writes one rule
# per output in the same layout nwg-displays uses, so the shell's Settings > Displays can edit it.
# Resolution is the panel's preferred one. The kernel's mode list has no refresh rates, and a rule
# with only WIDTHxHEIGHT can leave a 144 Hz screen on 60 Hz, so when Hyprland is already running
# (best_mode below) the highest refresh rate it offers at that resolution is written too.
# Nothing is disabled and nothing is placed by hand (position = "auto").
best_mode() { # best_mode <output> <WxH>  ->  prints WxH@Hz (highest Hz offered at that size), or nothing
    command -v hyprctl >/dev/null 2>&1 || return 1
    hyprctl monitors all 2>/dev/null | awk -v out="$1" -v res="$2" '
        /^Monitor /   { cur = $2 }
        /availableModes:/ && cur == out {
            for (i = 2; i <= NF; i++) {
                split($i, a, "@")
                if (a[1] == res) { hz = a[2]; sub(/Hz$/, "", hz); if (hz + 0 > best) { best = hz + 0; bs = hz } }
            }
        }
        END { if (bs != "") printf "%s@%s", res, bs }'
}

gen_monitors_lua() { # gen_monitors_lua <file>
    local out=$1 dir=${SEKAIPOP_DRM_DIR:-/sys/class/drm} d n st m b names=()
    for d in "$dir"/card*-*; do
        [ -e "$d/status" ] || continue
        st=$(cat "$d/status" 2>/dev/null)
        [ "$st" = connected ] || continue
        n=${d##*/}; n=${n#card*-}
        names+=("$n")
    done
    {
        printf '%s\n' '-- Made by the sekaipop installer for the screens found at install time.'
        printf '%s\n' "-- Change it in the shell's Settings > Hyprland > Displays, or with nwg-displays."
        printf '%s\n' '-- Outputs that are not listed here are set up by Hyprland itself (preferred mode, auto position).'
        if [ "${#names[@]}" -eq 0 ]; then
            printf '%s\n' '-- No connected output was found while installing, so there are no rules: Hyprland uses its defaults.'
        else
            while IFS= read -r n; do
                [ -n "$n" ] || continue
                set -- "$dir"/card*-"$n"/modes
                m=$(head -n1 "$1" 2>/dev/null | sed 's/[^0-9x].*//')
                b=$(best_mode "$n" "$m") && [ -n "$b" ] && m=$b
                printf '\nhl.monitor({\n    output = "%s",\n    mode = "%s",\n    position = "auto",\n    scale = 1,\n    vrr = 0\n})\n' \
                    "$n" "${m:-preferred}"
            done < <(printf '%s\n' "${names[@]}" | sort -u)
        fi
    } > "$out"
}

# ------------------------------------------------------------------ 3. Hyprland
step "3. Hyprland"
# Your own config is saved under a time-stamped name (and kept for good: --restore uses it).
# Re-running the installer on a config that is already ours only keeps one rolling "previous" copy,
# so it can never push your original out of reach.
OURS=0; grep -qsE 'SekaiPop( \(pjsekai\))?: Hyprland configuration' "$HYPR_DEST/hyprland.lua" 2>/dev/null && OURS=1
if [ "$OURS" = 1 ]; then BACKUP_TO="$CFG/hypr.sekaipop-previous"; else BACKUP_TO="$CFG/hypr.sekaipop-backup-$TS"; fi
case "$HYPR" in
  skip) info "left alone (--hypr skip). Start the shell yourself with:  qs -c sekaipop" ;;
  merge)
    if [ "$NODEPS" = 1 ]; then
        info "your config was kept. No session file was written because of --no-deps; add it with:"
        info "  ./install-deps.sh --no-update --core-only"
    else
        info "your config was kept; install-deps.sh added sekaipop_session.* to it (see above)"
    fi ;;
  full)
    if [ "$DRY" = 1 ]; then
        info "would build the new config from $SRC_HYPR"
        [ -e "$HYPR_DEST" ] && info "would move $HYPR_DEST to $BACKUP_TO"
        info "would keep your monitors.lua, workspaces.lua, sekaipop_overrides.lua and custom/ folder"
        [ -f "$HYPR_DEST/monitors.lua" ] || info "would make a monitors.lua for the screens connected to this machine"
    else
        mkdir -p "$CFG"
        NEW=$(mktemp -d "$CFG/.hypr-sekaipop-new.XXXXXX") || { fail "could not create a temporary folder in $CFG"; NEW=""; }
        if [ -n "$NEW" ]; then
            cp -a "$SRC_HYPR/." "$NEW/"
            for f in monitors.lua workspaces.lua sekaipop_overrides.lua; do
                [ -f "$HYPR_DEST/$f" ] && cp -a "$HYPR_DEST/$f" "$NEW/$f"
            done
            if [ -d "$HYPR_DEST/custom" ]; then mkdir -p "$NEW/custom"; cp -a "$HYPR_DEST/custom/." "$NEW/custom/"; fi
            if [ ! -f "$NEW/monitors.lua" ]; then
                if gen_monitors_lua "$NEW/monitors.lua"; then
                    ok "monitors.lua made for the screens connected now: $(grep -o 'output = "[^"]*"' "$NEW/monitors.lua" | cut -d'"' -f2 | paste -sd' ' -)"
                else
                    rm -f "$NEW/monitors.lua"; warn "could not make monitors.lua: Hyprland will use its defaults"
                fi
            fi
            find "$NEW" -name '*.sh' -exec chmod +x {} +
            if [ -e "$HYPR_DEST" ]; then
                [ "$OURS" = 1 ] && rm -rf "$BACKUP_TO"      # only one rolling copy of a previous sekaipop config
                mv "$HYPR_DEST" "$BACKUP_TO" || fail "could not back up $HYPR_DEST"
                info "old config kept as $BACKUP_TO"
            fi
            if mv "$NEW" "$HYPR_DEST"; then
                ok "installed $HYPR_DEST ${D}(put your own changes in $HYPR_DEST/custom/)${Z}"
                # hypridle.conf takes its idle times from the shell's own file (Settings > General >
                # Idle & sleep). Make it with the out-of-the-box times if there is none yet, and
                # restart hypridle, which reads its config only when it starts.
                IDLE_SH="$HERE/sekaipop/scripts/system/idle-config.sh"
                if [ ! -f "$CFG/sekaipop/idle.conf" ]; then
                    XDG_CONFIG_HOME="$CFG" sh "$IDLE_SH" write 300 600 900 suspend >/dev/null || warn "could not write $CFG/sekaipop/idle.conf"
                else
                    XDG_CONFIG_HOME="$CFG" sh "$IDLE_SH" restart || warn "could not restart hypridle: log in again for the idle times"
                fi
            else
                fail "could not move the new config into place"
                [ -e "$BACKUP_TO" ] && [ ! -e "$HYPR_DEST" ] && mv "$BACKUP_TO" "$HYPR_DEST"
            fi
        fi
    fi
    ;;
esac

# login session
if [ -f /usr/share/wayland-sessions/hyprland.desktop ]; then
    ok "login session 'Hyprland' is installed (pick it, not the 'uwsm' one, in your login screen)"
else
    warn "no Hyprland session file found in /usr/share/wayland-sessions: is the hyprland package installed?"
fi

# ------------------------------------------------------------------ done
step "Done"
if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '  %s%d problem(s):%s\n' "$R" "${#FAILED[@]}" "$Z"
    for m in "${FAILED[@]}"; do printf '    %s%s%s %s\n' "$R" "$G_BAD" "$Z" "$m"; done
fi
if [ "$DRY" = 0 ] && [ -f "$HERE/check-deps.sh" ]; then
    printf '\n'; SEKAIPOP_DIR="$QS_DEST" bash "$HERE/check-deps.sh" --core
fi

# A shell that is already running keeps the old files: the folder it watches was moved
# aside, and a reload inside the same process can fail on Qt state left from them
# ("FaceKey is not a type", issue #79). So it is restarted, as a new process.
# Skip mode leaves the restart to the user because startup can write Hyprland overrides.
shell_running() { have qs && ! qs list -p "$QS_DEST" 2>/dev/null | grep -q "No running instances"; }
restart_shell() {
    setsid -f sh "$QS_DEST/scripts/system/restart-shell.sh" "$QS_DEST" >/dev/null 2>&1 && ok "shell restarted on the new files"
}
if [ "$DRY" = 0 ] && [ "$HYPR" = full ] && hypr_running; then
    printf '\n'
    if ask "You are inside Hyprland now. Reload it and start the shell right away?"; then
        hyprctl reload >/dev/null 2>&1
        if [ "$REPLACED" = 1 ] && shell_running; then
            restart_shell
        elif ! pgrep -x qs >/dev/null && ! pgrep -x quickshell >/dev/null; then
            setsid -f qs -c sekaipop >/dev/null 2>&1 && ok "shell started"
        fi
    fi
elif [ "$DRY" = 0 ] && [ "$HYPR" = skip ] && [ "$REPLACED" = 1 ]; then
    warn "Restart SekaiPop to load the installed shell if it is already running."
elif [ "$DRY" = 0 ] && [ "$HYPR" != skip ] && [ "$REPLACED" = 1 ] && shell_running; then
    printf '\n'
    ask "The shell is running on the old files. Restart it now?" && restart_shell
fi
if [ "${#FAILED[@]}" -eq 0 ]; then
    [ "$DRY" = 1 ] && result ok "Dry run finished, nothing was changed" || result ok "SekaiPop is installed"
else
    result bad "Finished with ${#FAILED[@]} problem(s), see above"
fi
printf '\n  %sNext%s\n' "$B" "$Z"
nx "If you did not reload above: log out and back in (pick the plain Hyprland session)."
printf '      %sThe shell starts by itself. By hand:%s  %sqs -c sekaipop%s\n' "$D" "$Z" "$B" "$Z"
nx "Keybinds: ${B}Super + /${Z} opens the cheat sheet.  ${B}Super${Z} (tap) = apps.  ${B}Super + I${Z} = settings."
nx "Config mistakes are written to ${B}~/.cache/sekaipop/hypr-errors.log${Z} (the rest still loads)."
nx "Undo the Hyprland part:  ${B}./install.sh --restore${Z}"
printf '\n'
[ "${#FAILED[@]}" -eq 0 ]
