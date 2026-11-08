#!/bin/sh
# Installs the libraries the novel reader's LNReader plugins load (cheerio, htmlparser2, dayjs,
# urlencode) into ~/.local/share/sekaipop/readers/lnreader/node_modules.
# The novel server does this by itself the first time it starts; run this to do it by hand
# (or to see npm's own error when that did not work). Needs node and npm
# (Arch: pacman -S nodejs npm).
set -e
DIR="${SEKAIPOP_LNREADER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sekaipop/readers/lnreader}"
command -v node >/dev/null || { echo "node is not installed (pacman -S nodejs npm)" >&2; exit 1; }
command -v npm  >/dev/null || { echo "npm is not installed (pacman -S npm)" >&2; exit 1; }
mkdir -p "$DIR"
[ -f "$DIR/package.json" ] || echo '{"name":"sekaipop-lnreader","private":true}' > "$DIR/package.json"
npm install --prefix "$DIR" --no-audit --no-fund cheerio@1.0.0-rc.12 htmlparser2@9 dayjs@1 urlencode@1
echo "Done: $DIR/node_modules"
echo "Reopen the novel reader (qs -c sekaipop ipc call novelreader toggle) to pick them up."
