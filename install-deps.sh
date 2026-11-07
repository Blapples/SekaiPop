#!/usr/bin/env bash
# install-deps.sh: installs everything SekaiPop needs to be a full working desktop
# on Arch / CachyOS / EndeavourOS (anything with pacman), starting from a minimal Hyprland system.
#
# It does the same three jobs as end-4's "./setup install", for this rice:
#   1. packages      (repo packages with pacman, the rest from the AUR with yay/paru)
#   2. setup         (services, groups, user folders, Google Sans Flex font)
#   3. session glue  (a small Hyprland file for portals / screen sharing / autostart)
# It does NOT copy the rice itself and does NOT touch GPU drivers (same as end-4's).
#
# Usage:  ./install-deps.sh [options]
#   --dry-run             show what would happen, change nothing
#   --yes                 no questions, pass --noconfirm to pacman/yay
#   --core-only           only what the shell cannot start without
#   --with-optional       also songrec, mpvpaper, aubio, nwg-displays, Discord-voice tools, hypridle...
#   --no-desktop-layer    skip portals, file manager, fonts, keyring, icon theme (you already have a desktop)
#   --gpu amd|intel|nvidia|skip   which Vulkan/GL driver set to add (default: detect; nvidia is never installed)
#   --ddc                 set up i2c access for external-monitor brightness (ddcutil)
#   --no-suwayomi         skip Suwayomi (the manga reader's extension source: the full Java runtime and a ~150 MB jar)
#   --file-manager dolphin|thunar|none   which file manager to add (default: dolphin if you run KDE/Plasma or already have it, else thunar)
#   --no-update           don't run a full system update first
#   --no-aur  --no-services  --no-fonts  --no-session
#   -h, --help
#
# Run as your normal user (it uses sudo where needed). Run ./check-deps.sh afterwards.

set -u

DRY=0; YES=0; CORE_ONLY=0; WITH_OPT=0; DESKTOP=1; GPU=auto; DDC=0; FM=auto
UPDATE=1; AUR=1; SERVICES=1; FONTS=1; SESSION=1; SUWAYOMI=1
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --yes|-y) YES=1 ;;
        --core-only) CORE_ONLY=1 ;;
        --with-optional) WITH_OPT=1 ;;
        --no-desktop-layer) DESKTOP=0 ;;
        --gpu) shift; GPU=${1:-}; case "$GPU" in amd|intel|nvidia|skip) ;; *) echo "--gpu needs amd|intel|nvidia|skip" >&2; exit 2 ;; esac ;;
        --ddc) DDC=1 ;;
        --no-suwayomi) SUWAYOMI=0 ;;
        --file-manager) shift; FM=${1:-}; case "$FM" in dolphin|thunar|none) ;; *) echo "--file-manager needs dolphin|thunar|none" >&2; exit 2 ;; esac ;;
        --no-update) UPDATE=0 ;;
        --no-aur) AUR=0 ;;
        --no-services) SERVICES=0 ;;
        --no-fonts) FONTS=0 ;;
        --no-session) SESSION=0 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
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

# when install.sh runs this, its steps are shown one level down so the numbering doesn't clash
if [ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ]; then
    step() { printf '\n  %s%s%s %s%s%s\n' "$C" "$G_ARR" "$Z" "$B" "$1" "$Z"; }
fi

# run <command...>: execute, or just print in --dry-run
run() {
    if [ "$DRY" = 1 ]; then printf '  %s%s%s %swould run%s' "$PK" "$G_ARR" "$Z" "$D" "$Z"; printf ' %q' "$@"; printf '\n'; return 0; fi
    "$@"
}
run_sh() { # run a shell snippet (needed for pipes / redirects)
    if [ "$DRY" = 1 ]; then printf '  %s%s%s %swould run%s %s\n' "$PK" "$G_ARR" "$Z" "$D" "$Z" "$1"; return 0; fi
    bash -c "$1"
}
ask() { # ask <question>: default yes in --yes and --dry-run
    [ "$YES" = 1 ] || [ "$DRY" = 1 ] && return 0
    local a; read -r -p "  ${PK}?${Z} $1 ${D}[Y/n]${Z} " a; case "$a" in n|N|no|No) return 1 ;; *) return 0 ;; esac
}
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- preconditions
[ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ] || banner "SekaiPop dependencies" "packages, fonts, services, groups"
step "Checking the system"
[ "$(id -u)" = 0 ] && { echo "Run this as your normal user, not root (it calls sudo itself)." >&2; exit 1; }
have pacman || { echo "pacman not found: this installer is for Arch-based systems. Read DEPENDENCIES.md for the package list." >&2; exit 1; }
have sudo   || { echo "sudo not found: install it first (pacman -S sudo) and add yourself to the wheel group." >&2; exit 1; }
[ "$DRY" = 1 ] && info "DRY RUN: nothing will be changed."
ok "distro: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"

# ---------------------------------------------------------------- package lists
# "a|b" = try a in the repos, else b (b is then taken from the AUR). Plain names not in the repos go to the AUR.
CORE=(
  hyprland "quickshell|quickshell-git"
  qt6-base qt6-declarative "qt6-multimedia-ffmpeg|qt6-multimedia" qt6-svg qt6-imageformats qt6-wayland qt6-shadertools
  dbus polkit mesa
  pipewire wireplumber pipewire-pulse libpulse
  networkmanager bluez bluez-utils upower power-profiles-daemon
  libnotify wl-clipboard jq curl git xdg-utils xdg-user-dirs fontconfig
  python python-numpy
  "ttf-material-symbols-variable|ttf-material-symbols-variable-git"
)
DESKTOP_LAYER=(
  xorg-xwayland
  xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  gvfs adwaita-icon-theme
  noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd
  gnome-keyring libsecret pipewire-alsa
)
FEATURES=(
  "matugen|matugen-bin" cava easyeffects
  grim slurp cliphist wtype hyprpicker hyprsunset
  scrcpy android-tools
  yt-dlp
  gallery-dl
  python-requests python-curl-cffi
  imagemagick tesseract tesseract-data-eng swappy wf-recorder ffmpeg
  brightnessctl ddcutil zenity kitty
  plasma-nm kde-cli-tools blueman
  dconf glib2 adw-gtk-theme xorg-xrdb
  libcanberra sound-theme-freedesktop pacman-contrib
)
OPTIONAL=( python-aubio songrec mpvpaper nwg-displays hypridle nodejs pnpm cloudflare-warp-bin )

WANT=("${CORE[@]}")
if [ "$CORE_ONLY" = 0 ]; then
    [ "$DESKTOP" = 1 ] && WANT+=("${DESKTOP_LAYER[@]}")
    WANT+=("${FEATURES[@]}")
fi
[ "$WITH_OPT" = 1 ] && WANT+=("${OPTIONAL[@]}")
[ "$CORE_ONLY" = 1 ] && SUWAYOMI=0

# Suwayomi (the manga reader's third source, it runs Mihon / Tachiyomi extensions) is a Java program:
# it needs Java 21 or newer, and we use the FULL runtime (jre-openjdk), not the headless one.
# Any full JRE/JDK of 21+ already on the system is kept as it is. A headless-only Java is swapped
# for jre-openjdk (the two packages conflict, so pacman is told to remove the headless one).
SW_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/suwayomi"
SW_JAR="$SW_DIR/Suwayomi-Server.jar"
SW_RUN="$SW_DIR/run.sh"
java_major() { # java_major <java binary>: the major version, or nothing
    "$1" -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n1
}
java_is_full() { # java_is_full <java binary>: true for a full runtime (it has the desktop libraries, the headless build does not)
    local real; real=$(readlink -f "$1" 2>/dev/null) || return 1
    [ -e "$(dirname "$real")/../lib/libawt_xawt.so" ]
}
find_java21() { # prints the best java of version 21 or newer: a full one first, a headless one only if that is all there is
    local j m headless=""
    for j in "$(command -v java 2>/dev/null)" /usr/lib/jvm/*/bin/java; do
        [ -x "$j" ] || continue
        m=$(java_major "$j"); case "$m" in ''|*[!0-9]*) continue ;; esac
        [ "$m" -ge 21 ] || continue
        if java_is_full "$j"; then printf '%s\n' "$j"; return 0; fi
        [ -z "$headless" ] && headless=$j
    done
    [ -n "$headless" ] && { printf '%s\n' "$headless"; return 0; }
    return 1
}
NEED_JAVA=0
if [ "$SUWAYOMI" = 1 ]; then
    jv=$(find_java21) && java_is_full "$jv" || NEED_JAVA=1
    if [ "$NEED_JAVA" = 1 ]; then
        if [ -n "${jv:-}" ]; then
            info "Suwayomi: only a headless Java was found ($jv): it will be replaced by jre-openjdk"
        else
            info "Suwayomi needs Java 21 or newer and none was found: adding jre-openjdk"
        fi
    fi
fi

# KDE / Plasma already present? Then Qt apps are themed by Plasma (QT_QPA_PLATFORMTHEME=kde) and qt6ct is not wanted.
IS_KDE=0
pacman -T plasma-integration >/dev/null 2>&1 && IS_KDE=1
[ "${QT_QPA_PLATFORMTHEME:-}" = kde ] && IS_KDE=1

if [ "$CORE_ONLY" = 0 ] && [ "$DESKTOP" = 1 ]; then
    if [ "$FM" = auto ]; then
        if [ "$IS_KDE" = 1 ] || pacman -T dolphin >/dev/null 2>&1; then FM=dolphin; else FM=thunar; fi
    fi
    case "$FM" in
        dolphin) WANT+=(dolphin kio-extras ffmpegthumbs) ;;
        thunar)  WANT+=(thunar thunar-volman tumbler) ;;
    esac
    # qt6ct only on a system where nothing else themes Qt apps
    [ "$IS_KDE" = 0 ] && WANT+=(qt6ct)
    info "file manager: $FM   Qt theming: $([ "$IS_KDE" = 1 ] && echo 'KDE (qt6ct skipped)' || echo qt6ct)"
fi

# GPU
if [ "$GPU" = auto ]; then
    GPU=skip
    for v in /sys/class/drm/card*/device/vendor; do
        [ -r "$v" ] || continue
        case "$(cat "$v")" in
            0x1002) GPU=amd; break ;;
            0x8086) GPU=intel ;;
            0x10de) [ "$GPU" = skip ] && GPU=nvidia ;;
        esac
    done
fi
case "$GPU" in
    amd)    WANT+=(vulkan-radeon) ;;
    intel)  WANT+=(vulkan-intel) ;;
    nvidia) warn "NVIDIA detected: install your NVIDIA driver yourself (e.g. nvidia-open + nvidia-utils). This script never touches it." ;;
esac
info "GPU: $GPU"

# ---------------------------------------------------------------- 1. packages
step "1. Packages"
if [ "$UPDATE" = 1 ]; then
    if ask "Run a full system update first (sudo pacman -Syu)? Recommended on a fresh install."; then
        if [ "$YES" = 1 ]; then run sudo pacman -Syu --noconfirm; else run sudo pacman -Syu; fi
    fi
fi

REPO=(); AURP=(); ALREADY=()
for entry in "${WANT[@]}"; do
    IFS='|' read -ra alts <<<"$entry"
    # already satisfied (installed, or provided by a -git / AUR build of the same thing)? leave it alone.
    # This is what stops conflicts like adw-gtk-theme vs adw-gtk-theme-git.
    satisfied=0
    for a in "${alts[@]}"; do
        if pacman -T "$a" >/dev/null 2>&1; then satisfied=1; ALREADY+=("$a"); break; fi
    done
    [ "$satisfied" = 1 ] && continue
    hit=""
    for a in "${alts[@]}"; do
        if pacman -Si "$a" >/dev/null 2>&1; then hit=$a; break; fi
    done
    if [ -n "$hit" ]; then REPO+=("$hit"); else AURP+=("${alts[${#alts[@]}-1]}"); fi
done
info "${#ALREADY[@]} already installed (kept as they are), ${#REPO[@]} to install from the repos, ${#AURP[@]} from the AUR"
[ "${#REPO[@]}" -gt 0 ] && info "repos: ${REPO[*]}"
[ "${#AURP[@]}" -gt 0 ] && info "AUR: ${AURP[*]}"

PACFLAGS=(--needed); [ "$YES" = 1 ] && PACFLAGS+=(--noconfirm)
if [ "${#REPO[@]}" -gt 0 ]; then
    if ! run sudo pacman -S "${PACFLAGS[@]}" "${REPO[@]}"; then
        warn "the batch install failed (usually a package conflict), retrying one package at a time"
        for p in "${REPO[@]}"; do
            run sudo pacman -S "${PACFLAGS[@]}" "$p" || fail "pacman could not install $p (conflicts with something you have installed?)"
        done
    fi
fi

# Java for Suwayomi on its own, never inside the big batch: jre-openjdk conflicts with jre-openjdk-headless,
# and in a batch pacman would stop on that question. --ask 4 answers it "yes, remove the headless one".
if [ "$NEED_JAVA" = 1 ]; then
    JAVAFLAGS=(--needed --ask 4); [ "$YES" = 1 ] && JAVAFLAGS+=(--noconfirm)
    pacman -Qq jre-openjdk-headless >/dev/null 2>&1 && info "jre-openjdk-headless is installed: pacman swaps it for jre-openjdk (they conflict)"
    run sudo pacman -S "${JAVAFLAGS[@]}" jre-openjdk || fail "pacman could not install jre-openjdk (Suwayomi needs it)"
fi

if [ "${#AURP[@]}" -gt 0 ]; then
    if [ "$AUR" = 0 ]; then
        warn "--no-aur: skipped these, install them yourself: ${AURP[*]}"
    else
        helper=""
        have yay && helper=yay
        [ -z "$helper" ] && have paru && helper=paru
        if [ -z "$helper" ]; then
            warn "no AUR helper found (yay or paru)."
            if ask "Build yay-bin from the AUR now (needs base-devel + git, like end-4's installer)?"; then
                run sudo pacman -S --needed base-devel git
                run_sh 'rm -rf /tmp/sekaipop-yay && git clone https://aur.archlinux.org/yay-bin.git /tmp/sekaipop-yay && cd /tmp/sekaipop-yay && makepkg -si'"$([ "$YES" = 1 ] && echo ' --noconfirm')"' && cd / && rm -rf /tmp/sekaipop-yay' \
                    || fail "could not build yay"
                helper=yay
            fi
        fi
        if [ -n "$helper" ]; then
            AURFLAGS=(-S --needed); [ "$YES" = 1 ] && AURFLAGS+=(--noconfirm)
            if ! run "$helper" "${AURFLAGS[@]}" "${AURP[@]}"; then
                warn "the AUR batch failed, retrying one package at a time"
                for p in "${AURP[@]}"; do
                    run "$helper" "${AURFLAGS[@]}" "$p" || fail "AUR: could not build $p"
                done
            fi
        else
            warn "skipped the AUR packages: ${AURP[*]}"
        fi
    fi
fi

# ---------------------------------------------------------------- 2. setup
step "2. Setup (fonts, user folders, services, groups)"

if [ "$FONTS" = 1 ]; then
    if have fc-list && fc-list 2>/dev/null | grep -qi "Google Sans Flex"; then
        info "Google Sans Flex already installed"
    else
        info "installing Google Sans Flex (the same source end-4's installer uses)"
        run_sh 'set -e; d=$(mktemp -d); git clone --depth 1 --recurse-submodules https://github.com/end-4/google-sans-flex "$d/gsf"; mkdir -p "$HOME/.local/share/fonts/sekaipop-google-sans-flex"; cp -r "$d/gsf/." "$HOME/.local/share/fonts/sekaipop-google-sans-flex/"; rm -rf "$HOME/.local/share/fonts/sekaipop-google-sans-flex/.git"; fc-cache -f; rm -rf "$d"' \
            || fail "Google Sans Flex install failed (put the .ttf files in ~/.local/share/fonts by hand and run fc-cache -f)"
    fi
fi

# Suwayomi: the server jar from GitHub, plus a small launcher the manga reader starts it with.
suwayomi_url() { # the .jar link of the latest release. GitHub's API first, then the release page (the API has a rate limit)
    local url="" tag
    url=$(curl -fsSL --retry 3 https://api.github.com/repos/Suwayomi/Suwayomi-Server/releases/latest 2>/dev/null \
        | jq -r '[.assets[] | select(.name | test("\\.jar$"; "i"))][0].browser_download_url // empty' 2>/dev/null)
    if [ -z "$url" ]; then
        tag=$(curl -fsSIL --retry 3 -o /dev/null -w '%{url_effective}' https://github.com/Suwayomi/Suwayomi-Server/releases/latest 2>/dev/null | sed -n 's#.*/tag/##p')
        [ -n "$tag" ] && url=$(curl -fsSL --retry 3 "https://github.com/Suwayomi/Suwayomi-Server/releases/expanded_assets/$tag" 2>/dev/null \
            | grep -o 'href="[^"]*\.jar"' | head -n1 | sed 's/^href="//; s/"$//')
        [ -n "$url" ] && url="https://github.com$url"
    fi
    printf '%s\n' "$url"
}
suwayomi_fetch() {
    local url; url=$(suwayomi_url)
    [ -n "$url" ] || return 1
    info "downloading $(basename "$url") (about 150 MB)"
    curl -fL --retry 3 -o "$SW_JAR.part" "$url" || { rm -f "$SW_JAR.part"; return 1; }
    [ "$(head -c2 "$SW_JAR.part")" = PK ] || { rm -f "$SW_JAR.part"; return 1; }   # a jar is a zip
    mv "$SW_JAR.part" "$SW_JAR"
}
suwayomi_launcher() { # suwayomi_launcher <java binary>
    {
        echo '#!/bin/sh'
        echo '# written by SekaiPop install-deps.sh: the manga reader starts Suwayomi through this file'
        echo '# (no browser window, no tray icon). Safe to edit; delete it to switch Suwayomi off.'
        printf 'exec "%s" \\\n' "$1"
        echo '    -Dsuwayomi.tachidesk.config.server.initialOpenInBrowserEnabled=false \'
        echo '    -Dsuwayomi.tachidesk.config.server.systemTrayEnabled=false \'
        printf '    -jar "%s"\n' "$SW_JAR"
    } > "$SW_RUN" && chmod +x "$SW_RUN"
}
if [ "$SUWAYOMI" = 1 ]; then
    if [ "$DRY" = 1 ]; then
        info "would download the latest Suwayomi-Server jar to $SW_JAR and write $SW_RUN"
    else
        mkdir -p "$SW_DIR"
        if [ -f "$SW_JAR" ]; then
            info "Suwayomi jar already at $SW_JAR (delete it and run this again to update)"
        elif ! suwayomi_fetch; then
            warn "could not download Suwayomi: save the .jar from https://github.com/Suwayomi/Suwayomi-Server/releases as $SW_JAR and run this again"
        fi
        if [ -f "$SW_JAR" ]; then
            if jv=$(find_java21); then
                suwayomi_launcher "$jv" && info "wrote $SW_RUN (uses $jv)" || fail "could not write $SW_RUN"
            else
                fail "Suwayomi has no Java 21+ to run on (jre-openjdk did not install, see above). Fix that, then run ./install-deps.sh again"
            fi
        fi
    fi
fi

have xdg-user-dirs-update && run xdg-user-dirs-update

# folder default app (only if nothing is set)
if have xdg-mime && [ -z "$(xdg-mime query default inode/directory 2>/dev/null)" ]; then
    for fm in dolphin thunar org.gnome.Nautilus nemo pcmanfm; do
        if [ -f "/usr/share/applications/$fm.desktop" ] || [ -f "/usr/share/applications/org.kde.$fm.desktop" ]; then
            f="$fm.desktop"; [ -f "/usr/share/applications/org.kde.$fm.desktop" ] && f="org.kde.$fm.desktop"
            run xdg-mime default "$f" inode/directory; break
        fi
    done
fi

if [ "$SERVICES" = 1 ] && have systemctl; then
    for u in NetworkManager bluetooth upower power-profiles-daemon; do
        run sudo systemctl enable --now "$u" || fail "could not enable $u"
    done
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; then
        run systemctl --user enable --now pipewire pipewire-pulse wireplumber || fail "could not enable the PipeWire user services"
    else
        warn "no user D-Bus session here: after you log in, run: systemctl --user enable --now pipewire pipewire-pulse wireplumber"
    fi
elif [ "$SERVICES" = 1 ]; then
    warn "no systemd: enable NetworkManager, bluetooth, upower, power-profiles-daemon, pipewire, pipewire-pulse, wireplumber with your init system"
fi

run sudo usermod -aG video "$USER" || fail "could not add you to the video group"
if [ "$DDC" = 1 ]; then
    info "i2c access for ddcutil (external monitor brightness)"
    run sudo groupadd -f i2c
    run sudo usermod -aG i2c "$USER"
    run_sh 'echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null'
fi

# ---------------------------------------------------------------- 3. session glue
step "3. Hyprland session glue"
if [ "$SESSION" = 1 ]; then
    HYPR="$HOME/.config/hypr"
    mode=""
    [ -f "$HYPR/hyprland.lua" ] && mode=lua
    [ -z "$mode" ] && [ -f "$HYPR/hyprland.conf" ] && mode=conf
    if [ -z "$mode" ]; then
        warn "no Hyprland config found in $HYPR: start Hyprland once so it creates one, then run this script again with just: ./install-deps.sh --no-update --core-only"
    else
        tmp=$(mktemp)
        autostart=1; grep -rqsE '(qs|quickshell)[[:space:]]+-c[[:space:]]+sekaipop' "$HYPR" 2>/dev/null && autostart=0
        qtline=1;    grep -rqs 'QT_QPA_PLATFORMTHEME' "$HYPR" 2>/dev/null && qtline=0
        have qt6ct || qtline=0
        [ -n "${QT_QPA_PLATFORMTHEME:-}" ] && qtline=0   # something already themes Qt apps (e.g. kde): don't override it
        [ "$IS_KDE" = 1 ] && qtline=0
        if [ "$mode" = lua ]; then
            f="$HYPR/sekaipop_session.lua"
            {
                echo '-- sekaipop_session.lua  (written by install-deps.sh; safe to edit or delete)'
                echo '-- Glue a bare Hyprland session needs so portals (screen sharing) and apps work.'
                echo 'hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")'
                [ "$qtline" = 1 ] && echo 'hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")'
                echo 'hl.on("hyprland.start", function()'
                echo '    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")'
                [ "$autostart" = 1 ] && echo '    hl.exec_cmd("qs -c sekaipop")'
                echo 'end)'
            } > "$tmp"
            reqline='pcall(require, "sekaipop_session")'
        else
            f="$HYPR/sekaipop_session.conf"
            {
                echo '# sekaipop_session.conf  (written by install-deps.sh; safe to edit or delete)'
                echo 'env = ELECTRON_OZONE_PLATFORM_HINT,auto'
                [ "$qtline" = 1 ] && echo 'env = QT_QPA_PLATFORMTHEME,qt6ct'
                echo 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP'
                [ "$autostart" = 1 ] && echo 'exec-once = qs -c sekaipop'
            } > "$tmp"
            reqline='source = ~/.config/hypr/sekaipop_session.conf'
        fi
        if [ -e "$f" ]; then
            if cmp -s "$tmp" "$f"; then
                info "$f is already up to date"
            else
                warn "$f already exists, left as it is (new version saved to $f.new)"
                run cp "$tmp" "$f.new"
            fi
            # an earlier run may have forced qt6ct onto a system whose Qt apps are themed by KDE: take that line out
            if [ "$IS_KDE" = 1 ] && grep -qsE 'QT_QPA_PLATFORMTHEME.*qt6ct' "$f"; then
                if ask "Remove the QT_QPA_PLATFORMTHEME=qt6ct line from $f (you use KDE theming)? A backup is saved."; then
                    run cp "$f" "$f.bak"
                    run sed -i -E '/QT_QPA_PLATFORMTHEME.*qt6ct/d' "$f"
                else
                    warn "delete the QT_QPA_PLATFORMTHEME line from $f yourself if Qt apps look wrong"
                fi
            fi
        else
            run cp "$tmp" "$f"
            [ "$DRY" = 1 ] || info "wrote $f"
        fi
        rm -f "$tmp"
        cfg="$HYPR/hyprland.$mode"
        if grep -qsF 'sekaipop_session' "$cfg"; then
            info "$cfg already loads sekaipop_session"
        elif ask "Add  $reqline  to $cfg (a backup is saved next to it)?"; then
            run cp "$cfg" "$cfg.sekaipop.bak"
            run_sh "printf '\\n%s\\n' '$reqline' >> '$cfg'"
            [ "$DRY" = 1 ] || info "added  $reqline  to $cfg"
        else
            warn "add this line to $cfg yourself:  $reqline"
        fi
        [ "$mode" = lua ] && ! grep -rqs 'sekaipop_overrides' "$HYPR/hyprland.lua" 2>/dev/null && \
            warn 'also add this line to hyprland.lua so the Settings-panel Hyprland changes survive reloads:  pcall(require, "sekaipop_overrides")'
    fi
fi

# ---------------------------------------------------------------- done
[ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ] || step "Done"
if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '  %s%d problem(s):%s\n' "$R" "${#FAILED[@]}" "$Z"
    for m in "${FAILED[@]}"; do printf '    %s%s%s %s\n' "$R" "$G_BAD" "$Z" "$m"; done
fi
# when install.sh runs this, it prints its own "Next" and runs the check itself
[ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ] && exit "${#FAILED[@]}"
if [ "${#FAILED[@]}" -eq 0 ]; then result ok "Dependencies are in place"; else result bad "Finished with ${#FAILED[@]} problem(s), see above"; fi
printf '\n  %sNext%s\n' "$B" "$Z"
nx "Log out and back in (group membership and user services need a fresh session)."
printf '      %sStart Hyprland as the plain Hyprland session, not the uwsm one.%s\n' "$D" "$Z"
nx "Copy the rice folder to ${B}~/.config/quickshell/sekaipop${Z}"
printf '      %sand run shaders/compile-shaders.sh once if your Qt is not 6.12.%s\n' "$D" "$Z"
nx "Run ${B}./check-deps.sh${Z}, it should end with \"core missing: 0\"."
nx "Start the shell:  ${B}qs -c sekaipop${Z}"
if [ "$SUWAYOMI" = 1 ]; then
    nx "Manga reader: the Source key offers ${B}Suwayomi${Z}; it starts by itself when you pick it."
    printf '      %sIt has no extensions yet: in Browse press the puzzle key beside Source (Sources page),\n' "$D"
    printf '      add a repository under Repositories, then install the extensions you want.%s\n' "$Z"
fi
[ "$DRY" = 1 ] || { here=$(cd "$(dirname "$0")" && pwd); [ -f "$here/check-deps.sh" ] && { printf '\n'; bash "$here/check-deps.sh" --core; }; }
[ "${#FAILED[@]}" -eq 0 ]
