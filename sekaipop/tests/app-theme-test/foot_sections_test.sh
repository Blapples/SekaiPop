#!/bin/sh
# sh tests/app-theme-test/foot_sections_test.sh
#
# app-theme.sh writes foot's colours under the section names the installed foot
# reads (issue #158): foot 1.26 renamed [colors] to [colors-dark] / [colors-light]
# and later dropped [colors], which older foot still needs. Runs the real script
# against a stand-in `foot` that only prints a version line, in a throwaway
# XDG_CONFIG_HOME, so nothing of yours is touched.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../scripts/theming/app-theme.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sekaipop-foot-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

colours="bg=#101010 fg=#eeeeee cursor=#ff00aa selbg=#333333 selfg=#ffffff accent=#00ccff"
i=0; while [ $i -le 15 ]; do colours="$colours c$i=#0000$(printf '%02x' $i)"; i=$((i + 1)); done

# run <foot version line, or "none"> -> the written sekaipop-colors.ini in $tmp/out
run() {
    rm -rf "$tmp/cfg" "$tmp/bin"; mkdir -p "$tmp/cfg/foot" "$tmp/bin"
    if [ "$1" != none ]; then
        printf '#!/bin/sh\necho "%s"\n' "$1" > "$tmp/bin/foot"; chmod +x "$tmp/bin/foot"
        path="$tmp/bin:$PATH"
    else
        # no foot at all (only its config folder): the system folders only
        path="/usr/bin:/bin"
    fi
    # shellcheck disable=SC2086
    XDG_CONFIG_HOME="$tmp/cfg" PATH="$path" sh "$script" apply foot $colours >/dev/null 2>&1 \
        || fail "apply exited non-zero for '$1'"
    cp "$tmp/cfg/foot/sekaipop-colors.ini" "$tmp/out" 2>/dev/null || : > "$tmp/out"
}
sections() { grep -E '^\[' "$tmp/out" | tr '\n' ' '; }

run "foot version: 1.26.1 (+pgo +ime +graphemes -assertions)"
[ "$(sections)" = "[colors-dark] [colors-light] " ] || fail "1.26: got '$(sections)'"
[ "$(grep -c '^background=101010$' "$tmp/out")" = 2 ] || fail "1.26: both sections carry the colours"
[ "$(grep -c '^bright7=00000f$' "$tmp/out")" = 2 ] || fail "1.26: the bright colours are in both"

run "foot version: 2.0.0 (+pgo)"
[ "$(sections)" = "[colors-dark] [colors-light] " ] || fail "2.0: got '$(sections)'"

run "foot version: 1.25.0 (+pgo +ime +graphemes -assertions)"
[ "$(sections)" = "[colors] " ] || fail "1.25: got '$(sections)'"
grep -q '^regular0=000000$' "$tmp/out" || fail "1.25: the colours are under [colors]"

run "foot version: 1.9.2"
[ "$(sections)" = "[colors] " ] || fail "1.9 (minor below 10): got '$(sections)'"

run "something foot never prints"
[ "$(sections)" = "[colors-dark] [colors-light] " ] || fail "unreadable version: current names, got '$(sections)'"

if PATH=/usr/bin:/bin command -v foot >/dev/null 2>&1; then
    echo "skip: foot is installed in /usr/bin or /bin, so the no-foot case can't be run here"
else
    run none
    [ "$(sections)" = "[colors-dark] [colors-light] " ] || fail "no foot: current names, got '$(sections)'"
fi

# foot.ini gets the include at the top, once, whatever the version.
grep -c "^include=$tmp/cfg/foot/sekaipop-colors.ini$" "$tmp/cfg/foot/foot.ini" | grep -qx 1 || fail "foot.ini includes the file once"

[ $fails -eq 0 ] && echo "foot_sections_test: ok" || { echo "foot_sections_test: $fails failed"; exit 1; }
