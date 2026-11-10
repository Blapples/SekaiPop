#!/bin/sh

# Used by the Quick Panel's Wi-Fi and Bluetooth popups ("Advanced"): opens the full
# settings app for that device kind, so what the small popup cannot do (saved networks,
# static IP, VPN, pairing a new device, trusting, renaming) is one tap away.
#
#   open-settings-app.sh wifi|bluetooth
#
# Takes the first app that is installed (Wi-Fi: KDE's page, then nm-connection-editor). If there is none it opens a terminal tool
# (nmtui / bluetui / bluetoothctl) and, if even that is missing, says which package to
# install in a notification. install-deps.sh installs plasma-nm (KDE's Wi-Fi page) and blueman.

kind="${1:-wifi}"

have() { command -v "$1" >/dev/null 2>&1; }
have_kcm() { have kcmshell6 && kcmshell6 --list 2>/dev/null | grep -qsE "^$1([[:space:]]|$)"; }

say() {
    if have notify-send; then
        notify-send -a Shell -i "material:settings" "$1" "$2"
    else
        echo "$1: $2" >&2
    fi
}

term() { # term <command...>: run in the first terminal found
    for t in "${TERMINAL:-}" kitty foot alacritty konsole gnome-terminal xterm; do
        [ -n "$t" ] && have "$t" || continue
        case "$t" in
            gnome-terminal) exec "$t" -- "$@" ;;
            *) exec "$t" -e "$@" ;;
        esac
    done
    return 1
}

case "$kind" in
    wifi)
        # KDE's Wi-Fi & Networking page (plasma-nm) first. kcmshell6 returns 0 even
        # when a requested KCM is missing, so verify it is listed before running.
        have_kcm kcm_networkmanagement && exec kcmshell6 kcm_networkmanagement
        have nm-connection-editor && exec nm-connection-editor
        have gnome-control-center && exec gnome-control-center wifi
        have nmtui && term nmtui
        say "No network settings app found" "Install plasma-nm and kde-cli-tools (pacman -S plasma-nm kde-cli-tools)."
        ;;
    bluetooth)
        have blueman-manager && exec blueman-manager
        have blueberry && exec blueberry
        have_kcm kcm_bluetooth && exec kcmshell6 kcm_bluetooth
        have gnome-control-center && exec gnome-control-center bluetooth
        have bluetui && term bluetui
        have bluetoothctl && term bluetoothctl
        say "No Bluetooth settings app found" "Install blueman (pacman -S blueman)."
        ;;
    *)
        echo "usage: $0 wifi|bluetooth" >&2
        exit 2
        ;;
esac
