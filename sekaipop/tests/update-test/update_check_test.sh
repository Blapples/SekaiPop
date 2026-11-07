#!/bin/sh
# Runs scripts/system/update-check.sh against a throw-away local "GitHub":
# installed copy (no marker / marker / behind / apply / failures), the repo layout
# (shell folder = <clone>/sekaipop), and symlinks on the way (followed). Needs git only.
#   sh tests/update-test/update_check_test.sh
here=$(cd "$(dirname "$0")/../.." && pwd)
t=$(mktemp -d) && trap 'rm -rf "$t"' EXIT
fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }
expect() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (wanted '$3', got: $(echo "$2" | tr '\n' ' '))" ;; esac; }

export HOME="$t/home" SEKAIPOP_REPO="$t/remote.git" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME/.config/quickshell" "$t/work/sekaipop/scripts/system"
cd "$t/work" && git init -q -b main . && cp "$here/scripts/system/update-check.sh" sekaipop/scripts/system/
echo 1.0.0 > sekaipop/VERSION && echo "import QtQuick" > sekaipop/shell.qml && touch install.sh
git add -A && git commit -qm first && git clone -q --bare . "$t/remote.git"
git remote add origin "$t/remote.git" && git fetch -q && git branch -q -u origin/main
inst="$HOME/.config/quickshell/sekaipop"; cp -a sekaipop "$inst"
S="sh $inst/scripts/system/update-check.sh"

export XDG_CACHE_HOME="$t/cache"
expect "no marker: managed + unknown" "$($S check)" "unknown=yes"
expect "check names the newest version (rev)" "$($S check)" "rev=$(git -C "$t/work" rev-parse --short HEAD)"
[ -z "$($S seen)" ] && ok "seen: empty at first" || bad "seen not empty"
$S seen abc1234; expect "seen: stores and reads back" "$($S seen)" "abc1234"
printf 'commit=%s\nrepo=%s\nref=main\n' "$(git rev-parse HEAD)" "$t/remote.git" > "$inst/.source"
expect "marker = remote: current" "$($S check)" "status=current"
echo 1.0.1 > sekaipop/VERSION && git commit -qam second && git push -q origin main
expect "remote moved: behind" "$($S check)" "status=behind"
$S apply >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "apply exits 0" || bad "apply exit $rc"
[ "$(cat "$inst/VERSION")" = 1.0.1 ] && ok "files updated" || bad "files not updated"
[ -d "$inst.previous" ] && ok "previous copy kept" || bad "no previous copy"
expect "after apply: current" "$($S check)" "status=current"
SEKAIPOP_REPO=/nonexistent $S apply >/dev/null; [ $? != 0 ] && [ -f "$inst/shell.qml" ] && ok "bad repo: fails, install untouched" || bad "bad repo"
# A link on the way is followed (issue #21): the folder itself kept in a dotfiles
# repo, or ~/.config linked somewhere else. The real folder is replaced, the link stays.
mkdir -p "$t/real" "$t/dots/cfg" && cp -a "$inst" "$t/real/s" && ln -s "$t/real/s" "$HOME/.config/quickshell/lnk"
cp -a "$inst" "$t/dots/cfg/sekaipop" && ln -s "$t/dots/cfg" "$t/cfglink"
(cd "$t/work" && echo 1.0.2 > sekaipop/VERSION && git commit -qam third && git push -q origin main)
sh "$HOME/.config/quickshell/lnk/scripts/system/update-check.sh" apply >/dev/null; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$t/real/s/VERSION")" = 1.0.2 ] && ok "symlinked folder: the real folder is updated" || bad "symlinked folder (exit $rc)"
[ -L "$HOME/.config/quickshell/lnk" ] && [ "$(cat "$HOME/.config/quickshell/lnk/VERSION")" = 1.0.2 ] && ok "symlinked folder: the link still points at it" || bad "link lost"
[ -d "$t/real/s.previous" ] && ok "symlinked folder: previous copy beside the real one" || bad "no previous copy beside the real folder"
sh "$t/cfglink/sekaipop/scripts/system/update-check.sh" apply >/dev/null; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$t/dots/cfg/sekaipop/VERSION")" = 1.0.2 ] && ok "linked parent folder: updated" || bad "linked parent folder (exit $rc)"
G="sh $t/work/sekaipop/scripts/system/update-check.sh"
expect "repo layout: git mode" "$($G info)" "git=yes"
expect "repo layout: rev is the upstream head" "$($G check)" "rev="
cd "$t/work" && git fetch -q && echo "// local" >> sekaipop/shell.qml && git commit -qam local && git push -q origin main
expect "repo layout: current after push" "$($G check)" "status=current"
# ---- system update: SYSTEM-REV (shipped with the files) against the number install.sh recorded
expect "system: no SYSTEM-REV, nothing recommended" "$($S system)" "system=ok"
printf '2\nnew keybinds\n\nnew packages: scrcpy\n' > "$inst/SYSTEM-REV"
expect "system: shipped above applied (none = 0) is needed" "$($S system)" "system=needed"
expect "system: shipped and applied are printed" "$($S system)" "shipped=2"
expect "system: the reasons come back joined by |, blank lines dropped" "$($S system)" "note=new keybinds|new packages: scrcpy"
mkdir -p "$HOME/.config/sekaipop" && echo 2 > "$HOME/.config/sekaipop/system-rev"
expect "system: applied = shipped is ok" "$($S system)" "system=ok"
printf '3\n' > "$inst/SYSTEM-REV"
expect "system: a higher number again is needed, with no reasons" "$($S system)" "note="
expect "system: ... and needed" "$($S system)" "system=needed"
printf 'junk\nsome line\n' > "$inst/SYSTEM-REV"
expect "system: a first line that is no number counts as 0" "$($S system)" "shipped=0"
# sysrun: an installed copy has no install.sh, so it runs one from a fresh clone of the same repo and branch;
# a git checkout runs its own.
(cd "$t/work" && printf 'echo "$0" > "$SYSRAN"\n' > install.sh && git add -A && git commit -qm sys && git push -q origin main)
SYSRAN="$t/ran1" $S sysrun >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && case "$(cat "$t/ran1" 2>/dev/null)" in *sekaipop-system-*install.sh) ok "sysrun: installed copy runs install.sh from a fresh clone" ;; *) bad "sysrun (managed) ran: $(cat "$t/ran1" 2>/dev/null)" ;; esac || bad "sysrun managed exit $rc"
SYSRAN="$t/ran2" $G sysrun >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$t/ran2" 2>/dev/null)" = "$t/work/install.sh" ] && ok "sysrun: a git checkout runs its own install.sh" || bad "sysrun (git) exit $rc, ran: $(cat "$t/ran2" 2>/dev/null)"
SEKAIPOP_REPO=/nonexistent SYSRAN="$t/ran3" $S sysrun >/dev/null 2>&1; [ $? != 0 ] && [ ! -e "$t/ran3" ] && ok "sysrun: a repo that can't be cloned fails and runs nothing" || bad "sysrun bad repo"
[ -z "$(ls -d "${TMPDIR:-/tmp}"/sekaipop-system-* 2>/dev/null)" ] && ok "sysrun: the temporary clone is removed" || bad "temporary clone left behind"
[ $fail = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
