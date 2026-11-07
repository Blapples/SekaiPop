#!/bin/sh

# Helper for UpdateService.qml: what version is this shell, and is there a
# newer one?
#
#   update-check.sh info     print  version= / git= / managed= / branch= / commit= / remote=
#   update-check.sh check    print  status=current|behind|nosource|error and
#                            behind=<n> (git) or latest=<version or commit> (the rest);
#                            rev=<short id of the newest version> (all modes);
#                            unknown=yes when the installed files carry no commit mark
#   update-check.sh seen [x] print, or with an argument store, the id of the newest version
#                            the user was last told about (~/.cache/sekaipop/update-seen)
#   update-check.sh log      commits that an update would bring, one per line:
#                            <hash>|<subject>|<age>   (git checkout only)
#   update-check.sh apply    bring the shell up to date; exits 0 only if it worked
#   update-check.sh system   print  system=needed|ok / shipped=<n> / applied=<n> / note=<a|b|c>:
#                            does this version ask for an install.sh run (new Hyprland keybinds
#                            or rules, new packages)? `shipped` is the first line of SYSTEM-REV
#                            next to shell.qml (its other lines are the reasons, shown as `note`);
#                            `applied` is the number install.sh last recorded in
#                            ~/.config/sekaipop/system-rev (none = 0). needed = shipped > applied.
#   update-check.sh sysrun   run install.sh (what the Update system key opens in a terminal):
#                            the clone's own on a git checkout, else one from a fresh clone of
#                            the same repo and branch
#
# Where it looks, in order:
#   1. A git checkout: this folder is a clone itself, or it is the sekaipop/ folder
#      of a SekaiPop clone (the repo layout). It compares with the branch's upstream
#      and `apply` is `git pull --ff-only`.
#   2. An installed copy (what install.sh makes: ~/.config/quickshell/sekaipop, no
#      .git inside). The repo is read from the ".source" file install.sh and this
#      script keep next to shell.qml (commit= / repo= / ref=), else from
#      $SEKAIPOP_REPO, else ~/.config/sekaipop/update-repo, else the SekaiPop repo on
#      GitHub; the branch is ref= (else $SEKAIPOP_REF, else main). `check` only asks
#      the remote for its newest commit (git ls-remote) and compares it with
#      commit=. `apply` downloads that commit into a temporary folder, builds the new
#      folder beside this one, keeps the old one as sekaipop.previous (one copy) and
#      swaps them. Needs git. A symlink on the way (the folder itself, or ~/.config
#      kept in a dotfiles repo) is followed: the real folder is the one replaced, so
#      the links keep pointing at the new files.
#   3. Otherwise a URL to a plain-text VERSION file, from $SEKAIPOP_UPDATE_URL or the
#      first line of ~/.config/sekaipop/update-url. It is compared with this folder's
#      VERSION. (Nothing is downloaded or installed this way; the panel just tells
#      you a newer version exists.)
#   4. Otherwise: status=nosource.
#
# Only the shell's own files are updated. Hyprland config and packages come from
# install.sh (bash <(curl -fsSL .../get.sh)).

here=$(cd "$(dirname "$0")/../.." && pwd)
herep=$(cd "$here" && pwd -P)
ver=$(head -n 1 "$here/VERSION" 2>/dev/null | tr -d ' \r')
[ -n "$ver" ] || ver=unknown

# Never stop to ask for a password (a private or renamed repo would hang the panel).
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

have_git() { command -v git >/dev/null 2>&1; }
# Give slow networks a limit, if `timeout` exists.
limit() { n=$1; shift; if command -v timeout >/dev/null 2>&1; then timeout "$n" "$@"; else "$@"; fi; }

# --- 1. a git checkout ------------------------------------------------------
root=""
if have_git; then
    top=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" 2>/dev/null && pwd -P)
    if [ -n "$top" ]; then
        if [ "$top" = "$herep" ]; then root=$top
        elif [ "$top/sekaipop" = "$herep" ] && [ -f "$top/install.sh" ]; then root=$top; fi
    fi
fi
is_git() { [ -n "$root" ]; }
has_up() { git -C "$root" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; }

# --- 2. an installed copy ---------------------------------------------------
cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/sekaipop"
marker="$here/.source"
mark() { sed -n "s/^$1=//p" "$marker" 2>/dev/null | head -n 1 | tr -d '\r'; }
installed=$(mark commit)
repo="$SEKAIPOP_REPO"
[ -n "$repo" ] || repo=$(mark repo)
[ -n "$repo" ] || repo=$(head -n 1 "$cfgdir/update-repo" 2>/dev/null | tr -d '\r')
[ -n "$repo" ] || repo=https://github.com/Blapples/SekaiPop.git
ref="$SEKAIPOP_REF"
[ -n "$ref" ] || ref=$(mark ref)
{ [ -n "$ref" ] && [ "$ref" != HEAD ]; } || ref=main
is_managed() { ! is_git && have_git; }
short() { printf '%s' "$1" | cut -c1-7; }

remote_head() {
    out=$(limit 25 git ls-remote "$repo" "refs/heads/$ref" 2>/dev/null) || out=""
    [ -n "$out" ] || out=$(limit 25 git ls-remote "$repo" "refs/tags/$ref^{}" "refs/tags/$ref" 2>/dev/null | head -n 1) || out=""
    printf '%s' "$out" | awk 'NR == 1 { print $1 }'
}

apply_managed() {
    # Work on the real folder, not the path the shell was started from: moving a
    # symlink would replace the link and leave the files it points to behind.
    real=$herep
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/sekaipop-update-XXXXXX") || { echo "couldn't make a temporary folder"; return 1; }
    trap 'rm -rf "$tmp"' EXIT
    echo "downloading $ref from $repo"
    limit 180 git clone --quiet --depth 1 --branch "$ref" "$repo" "$tmp/src" >/dev/null 2>&1 \
        || { echo "couldn't download the update"; return 1; }
    new="$tmp/src/sekaipop"
    [ -f "$new/shell.qml" ] || { echo "the download has no sekaipop folder (wrong repo or branch?)"; return 1; }
    commit=$(git -C "$tmp/src" rev-parse HEAD) || { echo "couldn't read the downloaded commit"; return 1; }

    stage="$real.update-new"
    old="$real.previous"
    rm -rf "$stage"
    cp -a "$new" "$stage" || { rm -rf "$stage"; echo "couldn't copy the new files"; return 1; }
    # install.sh leaves the developer tests out unless asked; keep it that way.
    [ -d "$real/tests" ] || rm -rf "$stage/tests"
    { echo "commit=$commit"; echo "repo=$repo"; echo "ref=$ref"; } > "$stage/.source"

    # Qt older than 6.12 cannot read the shipped .qsb shaders: build them again, as install.sh does.
    qt=$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}' | grep -oE '^[0-9]+\.[0-9]+')
    if [ -n "$qt" ] && [ "$(printf '%s\n6.12\n' "$qt" | sort -V | head -n 1)" != 6.12 ] && [ -f "$stage/shaders/compile-shaders.sh" ]; then
        bash "$stage/shaders/compile-shaders.sh" >/dev/null 2>&1 \
            || { rm -rf "$stage"; echo "the shaders didn't build (needs qt6-shadertools)"; return 1; }
    fi

    rm -rf "$old"
    if mv "$real" "$old" && mv "$stage" "$real"; then
        echo "updated to $(short "$commit")"
        return 0
    fi
    # Put things back the way they were.
    [ -e "$real" ] || mv "$old" "$real"
    rm -rf "$stage"
    echo "couldn't swap in the new files; nothing was changed"
    return 1
}

# --- 3. a URL to a VERSION file ---------------------------------------------
url="$SEKAIPOP_UPDATE_URL"
[ -n "$url" ] || url=$(head -n 1 "$cfgdir/update-url" 2>/dev/null)

cmd=$1
case "$cmd" in
    info)
        printf 'version=%s\n' "$ver"
        if is_git; then
            printf 'git=yes\nbranch=%s\ncommit=%s\n' "$(git -C "$root" rev-parse --abbrev-ref HEAD)" "$(git -C "$root" rev-parse --short HEAD)"
            printf 'remote=%s\n' "$(git -C "$root" config --get remote.origin.url)"
        elif is_managed; then
            printf 'git=no\nmanaged=yes\nbranch=%s\nremote=%s\n' "$ref" "$repo"
            [ -n "$installed" ] && printf 'commit=%s\n' "$(short "$installed")"
        else
            printf 'git=no\n'
            [ -n "$url" ] && printf 'remote=%s\n' "$url"
        fi
        ;;
    check)
        if is_git && has_up; then
            limit 60 git -C "$root" fetch --quiet || { echo "status=error"; echo "reason=fetch failed"; exit 0; }
            n=$(git -C "$root" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
            if [ "$n" -gt 0 ]; then echo "status=behind"; else echo "status=current"; fi
            echo "behind=$n"
            echo "rev=$(git -C "$root" rev-parse --short '@{u}' 2>/dev/null)"
        elif is_managed; then
            head=$(remote_head)
            [ -n "$head" ] || { echo "status=error"; echo "reason=couldn't reach the repository"; exit 0; }
            echo "latest=$(short "$head")"
            echo "rev=$(short "$head")"
            if [ -z "$installed" ]; then echo "unknown=yes"; echo "status=behind"
            elif [ "$installed" = "$head" ]; then echo "status=current"
            else echo "status=behind"; fi
        elif [ -n "$url" ]; then
            command -v curl >/dev/null 2>&1 || { echo "status=error"; echo "reason=curl not installed"; exit 0; }
            latest=$(curl -fsSL -m 15 "$url" 2>/dev/null | head -n 1 | tr -d ' \r')
            [ -n "$latest" ] || { echo "status=error"; echo "reason=couldn't reach the update URL"; exit 0; }
            echo "latest=$latest"
            echo "rev=$latest"
            if [ "$latest" = "$ver" ]; then echo "status=current"
            elif [ "$(printf '%s\n%s\n' "$ver" "$latest" | sort -V | tail -n 1)" = "$latest" ]; then echo "status=behind"
            else echo "status=current"; fi
        else
            echo "status=nosource"
        fi
        ;;
    seen)
        f="${XDG_CACHE_HOME:-$HOME/.cache}/sekaipop/update-seen"
        if [ -n "$2" ]; then
            mkdir -p "$(dirname "$f")" && printf '%s\n' "$2" > "$f"
        else
            head -n 1 "$f" 2>/dev/null
        fi
        ;;
    log)
        is_git && has_up || exit 0
        git -C "$root" log --pretty=format:'%h|%s|%cr' -n 30 'HEAD..@{u}' 2>/dev/null
        ;;
    apply)
        if is_git; then
            has_up || { echo "this clone has no upstream branch"; exit 1; }
            out=$(git -C "$root" pull --ff-only 2>&1); rc=$?
            printf '%s\n' "$out" | tail -n 1
            exit "$rc"
        elif is_managed; then
            apply_managed
            exit $?
        else
            echo "git isn't installed, so there is nothing to update from"
            exit 1
        fi
        ;;
    system)
        shipped=$(head -n 1 "$here/SYSTEM-REV" 2>/dev/null | tr -d ' \r')
        case "$shipped" in ''|*[!0-9]*) shipped=0 ;; esac
        applied=$(head -n 1 "$cfgdir/system-rev" 2>/dev/null | tr -d ' \r')
        case "$applied" in ''|*[!0-9]*) applied=0 ;; esac
        if [ "$shipped" -gt "$applied" ]; then echo "system=needed"; else echo "system=ok"; fi
        echo "shipped=$shipped"
        echo "applied=$applied"
        printf 'note=%s\n' "$(tail -n +2 "$here/SYSTEM-REV" 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | paste -sd'|' -)"
        ;;
    sysrun)
        if is_git && [ -f "$root/install.sh" ]; then
            exec bash "$root/install.sh"
        fi
        have_git || { echo "git isn't installed, so there is no install.sh to run"; exit 1; }
        tmp=$(mktemp -d "${TMPDIR:-/tmp}/sekaipop-system-XXXXXX") || { echo "couldn't make a temporary folder"; exit 1; }
        trap 'rm -rf "$tmp"' EXIT
        echo "downloading $ref from $repo"
        limit 180 git clone --quiet --depth 1 --branch "$ref" "$repo" "$tmp/src" \
            || { echo "couldn't download install.sh"; exit 1; }
        [ -f "$tmp/src/install.sh" ] || { echo "the download has no install.sh (wrong repo or branch?)"; exit 1; }
        bash "$tmp/src/install.sh"
        exit $?
        ;;
    *)
        echo "usage: $0 info|check|log|apply|seen|system|sysrun" >&2
        exit 2
        ;;
esac
exit 0
