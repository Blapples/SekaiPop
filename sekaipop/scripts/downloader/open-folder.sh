#!/bin/sh

# Helper for DownloaderService.qml: opens the folder the Downloader puts its files in, in your
# file manager (xdg-open).
#
#   open-folder.sh [folder]      "" or nothing = your Downloads folder; "~" and "~/x" are your home

folder="$1"

if [ -z "$folder" ]; then
    folder="$(xdg-user-dir DOWNLOAD 2>/dev/null)"
    { [ -n "$folder" ] && [ "$folder" != "$HOME" ]; } || folder="$HOME/Downloads"
fi
case "$folder" in
    "~") folder="$HOME" ;;
    "~/"*) folder="$HOME/${folder#\~/}" ;;
esac

mkdir -p "$folder" 2>/dev/null
exec xdg-open "$folder"
