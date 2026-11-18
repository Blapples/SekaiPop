#!/bin/sh
# hyprmon's profiles for the Displays card when hyprmon is the display handler
# (services/HyprmonService.qml). hyprmon (github.com/erans/hyprmon) keeps each profile as
# ~/.config/hyprmon/profiles/<name>.json and their order in profiles/.profile_order; its
# command line can only apply one and say which is active, so saving, renaming, deleting
# and reordering are done here, on the same files, in the same shape. Applying is always
# hyprmon's own `-profile`, which also moves workspaces off screens that went away and
# writes ~/.config/hypr/hyprmon.lua.
#
#   hyprmon.sh list                 every profile as one JSON array, in the user's order
#   hyprmon.sh active               the profile hyprmon says is on now (empty: none)
#   hyprmon.sh apply  <name>        hyprmon -profile <name>
#   hyprmon.sh save   <name> <file> <file> is { "monitors": [...] }: write the profile
#                                   (created_at kept when it exists), new ones go last
#   hyprmon.sh rename <old> <new>
#   hyprmon.sh delete <name>
#   hyprmon.sh order  <name>...     the new order
#
# HYPRMON_CFG: hyprmon's folder (default ~/.config/hyprmon; the tests use their own).
# Before a profile is changed or deleted it is copied to <folder>/backups/<time>/.
# Needs jq. Exit 2 = bad arguments, 1 = it did not work.

cfg="${HYPRMON_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/hyprmon}"
dir="$cfg/profiles"
order="$dir/.profile_order"

valid_name() {
    case "$1" in ''|.*|*[!A-Za-z0-9\ _.-]*) return 1 ;; esac
    [ "${#1}" -le 64 ] || return 1
    # no leading / trailing space
    case "$1" in ' '*|*' ') return 1 ;; esac
    return 0
}

need_jq() {
    command -v jq >/dev/null 2>&1 || { echo "jq is not installed" >&2; exit 1; }
}

hm() { # hyprmon with the same folder
    if [ -n "$HYPRMON_CFG" ]; then hyprmon -cfg "$HYPRMON_CFG" "$@"; else hyprmon "$@"; fi
}

backup() { # backup <name>
    [ -f "$dir/$1.json" ] || return 0
    b="$cfg/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$b" && cp -p "$dir/$1.json" "$b/" || return 1
    # keep the last 30 backup folders
    ls -1d "$cfg"/backups/*/ 2>/dev/null | sort | head -n -30 | while IFS= read -r old; do rm -rf "$old"; done
    return 0
}

write_order() { # write_order <json array>
    tmp=$(mktemp "$dir/.order.XXXXXX") || return 1
    printf '%s\n' "$1" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$order" || { rm -f "$tmp"; return 1; }
}

current_order() { # the saved order as a JSON array (missing file: [])
    if [ -f "$order" ]; then jq -c 'if type == "array" then map(strings) else [] end' "$order" 2>/dev/null || echo '[]'; else echo '[]'; fi
}

case "$1" in
    list)
        need_jq
        mkdir -p "$dir" 2>/dev/null
        names=$(cd "$dir" 2>/dev/null && ls -1 -- *.json 2>/dev/null | sed 's/\.json$//')
        ord=$(current_order)
        # profiles named in the order first, in that order, then the rest by name
        printf '%s\n' "$names" | jq -R -s -c --argjson ord "$ord" '
            (split("\n") | map(select(length > 0))) as $all
            | ($ord | map(select(. as $n | $all | index($n)))) + ($all - $ord | sort)' > "${TMPDIR:-/tmp}/hyprmon-names.$$"
        first=1
        printf '['
        for n in $(jq -r '.[] | @base64' "${TMPDIR:-/tmp}/hyprmon-names.$$"); do
            name=$(printf '%s' "$n" | base64 -d)
            f="$dir/$name.json"
            jq -e . "$f" >/dev/null 2>&1 || continue
            [ "$first" = 1 ] || printf ','
            first=0
            jq -c --arg n "$name" '{ name: $n, monitors: (.monitors // []), created_at, updated_at }' "$f"
        done
        printf ']\n'
        rm -f "${TMPDIR:-/tmp}/hyprmon-names.$$"
        ;;
    active)
        command -v hyprmon >/dev/null 2>&1 || exit 1
        out=$(hm -active-profile 2>/dev/null) || exit 1
        case "$out" in "No active profile"*|"") echo "" ;; *) printf '%s\n' "$out" | tail -n 1 ;; esac
        ;;
    apply)
        valid_name "$2" || { echo "bad profile name" >&2; exit 2; }
        [ -f "$dir/$2.json" ] || { echo "no profile $2" >&2; exit 1; }
        command -v hyprmon >/dev/null 2>&1 || { echo "hyprmon is not installed" >&2; exit 1; }
        hm -profile "$2"
        ;;
    save)
        need_jq
        valid_name "$2" || { echo "bad profile name" >&2; exit 2; }
        [ -f "$3" ] || { echo "no file $3" >&2; exit 2; }
        jq -e '.monitors | type == "array" and length > 0' "$3" >/dev/null 2>&1 || { echo "no monitors in $3" >&2; exit 2; }
        mkdir -p "$dir" || exit 1
        now=$(date +%Y-%m-%dT%H:%M:%S%:z)
        created="$now"
        isnew=1
        if [ -f "$dir/$2.json" ]; then
            isnew=0
            created=$(jq -r '.created_at // empty' "$dir/$2.json" 2>/dev/null)
            [ -n "$created" ] || created="$now"
            backup "$2" || exit 1
        fi
        tmp=$(mktemp "$dir/.save.XXXXXX") || exit 1
        jq --arg n "$2" --arg c "$created" --arg u "$now" \
            '{ name: $n, monitors: .monitors, created_at: $c, updated_at: $u }' "$3" > "$tmp" \
            && chmod 600 "$tmp" && mv -f "$tmp" "$dir/$2.json" || { rm -f "$tmp"; exit 1; }
        if [ "$isnew" = 1 ]; then
            ord=$(current_order)
            write_order "$(printf '%s' "$ord" | jq -c --arg n "$2" 'if index($n) then . else . + [$n] end')" || exit 1
        fi
        ;;
    rename)
        need_jq
        valid_name "$2" && valid_name "$3" || { echo "bad profile name" >&2; exit 2; }
        [ -f "$dir/$2.json" ] || { echo "no profile $2" >&2; exit 1; }
        [ "$2" = "$3" ] && exit 0
        [ -e "$dir/$3.json" ] && { echo "a profile $3 is already there" >&2; exit 1; }
        backup "$2" || exit 1
        tmp=$(mktemp "$dir/.save.XXXXXX") || exit 1
        jq --arg n "$3" '.name = $n' "$dir/$2.json" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$dir/$3.json" \
            || { rm -f "$tmp"; exit 1; }
        rm -f "$dir/$2.json"
        ord=$(current_order)
        write_order "$(printf '%s' "$ord" | jq -c --arg o "$2" --arg n "$3" 'map(if . == $o then $n else . end)')" || exit 1
        ;;
    delete)
        need_jq
        valid_name "$2" || { echo "bad profile name" >&2; exit 2; }
        [ -f "$dir/$2.json" ] || exit 0
        backup "$2" || exit 1
        rm -f "$dir/$2.json" || exit 1
        ord=$(current_order)
        write_order "$(printf '%s' "$ord" | jq -c --arg o "$2" 'map(select(. != $o))')" || exit 1
        ;;
    order)
        need_jq
        shift
        for n in "$@"; do valid_name "$n" || { echo "bad profile name: $n" >&2; exit 2; }; done
        mkdir -p "$dir" || exit 1
        write_order "$(jq -c -n '$ARGS.positional' --args "$@")" || exit 1
        ;;
    *)
        echo "usage: $0 list | active | apply <name> | save <name> <file> | rename <old> <new> | delete <name> | order <name>..." >&2
        exit 2
        ;;
esac
exit 0
