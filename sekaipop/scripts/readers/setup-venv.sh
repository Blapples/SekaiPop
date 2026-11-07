#!/bin/sh
# Makes the private Python environment the manga and novel readers run under
# (~/.local/share/sekaipop/readers/venv) with the two libraries their backends use:
#   curl_cffi  fetches like a browser, which the manga site needs to let the requests through
#   requests   the fallback when curl_cffi is missing
# Without it the backends use the system python3, which works if it has `requests`
# (Arch: pacman -S python-requests python-curl-cffi).
set -e
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sekaipop/readers/venv"
command -v python3 >/dev/null || { echo "python3 is not installed" >&2; exit 1; }
mkdir -p "$(dirname "$DIR")"
python3 -m venv "$DIR"
"$DIR/bin/pip" install --upgrade pip curl_cffi requests
echo "Done: $DIR"
echo "Reopen the readers (qs -c sekaipop ipc call mangareader toggle) to start their backends under it."
