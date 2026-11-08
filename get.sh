#!/usr/bin/env bash
# get.sh: the one-command installer for SekaiPop.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Blapples/SekaiPop/main/get.sh)
#
# It downloads SekaiPop into a temporary folder, runs install.sh from there (so nobody
# has to clone, chmod or cd), and cleans up afterwards. Everything after the script is
# passed on to install.sh, for example:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Blapples/SekaiPop/main/get.sh) --dry-run
#   bash <(curl -fsSL https://raw.githubusercontent.com/Blapples/SekaiPop/main/get.sh) --yes --hypr merge
#
# The "curl ... | bash -s -- --dry-run" form works too.
#
# Environment (all optional):
#   SEKAIPOP_REF=<branch|tag>   what to install (default: main)
#   SEKAIPOP_DIR=<folder>       keep the download there instead of a temporary folder
#                               (it is updated on the next run; do not keep your own edits in it)
#   SEKAIPOP_REPO=<git url>     install from a fork
#
# Run as your normal user, not root: install.sh calls sudo itself where it needs to.

set -euo pipefail

REPO=${SEKAIPOP_REPO:-https://github.com/Blapples/SekaiPop.git}
REF=${SEKAIPOP_REF:-main}
KEEP=${SEKAIPOP_DIR:-}
# A preview uses a disposable download even when a persistent checkout was configured.
for a in "$@"; do
    case "$a" in --dry-run) KEEP= ;; --) break ;; esac
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then B=$'\e[1m'; D=$'\e[2m'; C=$'\e[38;5;80m'; R=$'\e[38;5;203m'; Z=$'\e[0m'; else B=; D=; C=; R=; Z=; fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) U=1 ;; *) U=0 ;; esac
[ "${TERM:-}" = linux ] && U=0
if [ "$U" = 1 ]; then HR='─'; BAD='✘'; else HR='-'; BAD='x'; fi
say() { local n=$(( 60 - ${#1} - 5 )); [ "$n" -lt 3 ] && n=3; local l=""; local i; for ((i = 0; i < n; i++)); do l+=$HR; done
    printf '\n%s%s%s %s%s%s %s%s%s\n' "$C" "$HR$HR" "$Z" "$B" "$*" "$Z" "$D" "$l" "$Z"; }
die() { printf '  %s%s %s%s\n' "$R" "$BAD" "$*" "$Z" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" = 0 ] && die "Run this as your normal user, not root (it calls sudo itself)."

# ---- where the download goes
if [ -n "$KEEP" ]; then
    DIR=$KEEP
    mkdir -p "$DIR"
else
    DIR=$(mktemp -d "${TMPDIR:-/tmp}/sekaipop-XXXXXX")
    trap 'rm -rf "$DIR"' EXIT
fi

# ---- download: git if there is one, otherwise a tarball
say "Downloading SekaiPop ($REF)"
if have git; then
    if [ -d "$DIR/.git" ]; then
        git -C "$DIR" fetch --quiet --depth 1 origin "$REF"
        git -C "$DIR" checkout --quiet --force FETCH_HEAD
    else
        [ -z "$(ls -A "$DIR" 2>/dev/null)" ] || die "$DIR is not empty and is not a SekaiPop download."
        git clone --quiet --depth 1 --branch "$REF" "$REPO" "$DIR"
    fi
elif have curl && have tar; then
    TAR="${REPO%.git}/archive/${REF}.tar.gz"
    curl -fsSL "$TAR" | tar -xz --strip-components=1 -C "$DIR"
else
    die "Need git, or curl and tar. On Arch:  sudo pacman -S git"
fi
[ -f "$DIR/install.sh" ] || die "The download has no install.sh: wrong SEKAIPOP_REF or SEKAIPOP_REPO?"
chmod +x "$DIR/install.sh" "$DIR/install-deps.sh" "$DIR/check-deps.sh" 2>/dev/null || true

# ---- install.sh asks questions with read: give it the real terminal, because under
#      "curl | bash" its stdin is this script, not the keyboard
QUIET=0
for a in "$@"; do case "$a" in --yes|-y|--dry-run|-h|--help) QUIET=1 ;; esac; done
if [ -t 0 ]; then
    INPUT=/dev/stdin
elif { : </dev/tty; } 2>/dev/null; then
    INPUT=/dev/tty
elif [ "$QUIET" = 1 ]; then
    INPUT=/dev/null
else
    die "No terminal to ask questions on. Add --yes to install without questions."
fi

say "Running the installer"
set +e
bash "$DIR/install.sh" "$@" <"$INPUT"
rc=$?
set -e
[ "$rc" = 0 ] || printf '\n%sThe installer stopped (exit %s). Nothing is hidden: scroll up for the reason, then run the same command again.%s\n' "$R" "$rc" "$Z" >&2
exit "$rc"
