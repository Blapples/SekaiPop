#!/bin/sh
# sh tests/display-test/hyprmon_script_test.sh   (run from the sekaipop folder)
# scripts/hyprland/hyprmon.sh against a throwaway hyprmon folder. When hyprmon is
# installed it is also asked to read what was written (never to apply anything).
S="$(cd "$(dirname "$0")/../.." && pwd)/scripts/hyprland/hyprmon.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HYPRMON_CFG="$T/hyprmon"
mkdir -p "$HYPRMON_CFG/profiles"
fails=0
check() { # check <message> <command...>
    msg=$1; shift
    if "$@" >/dev/null 2>&1; then :; else fails=$((fails + 1)); echo "FAIL $msg"; fi
}
same() { # same <message> <got> <want>
    [ "$2" = "$3" ] || { fails=$((fails + 1)); echo "FAIL $1"; echo "   got  $2"; echo "   want $3"; }
}

P="$HYPRMON_CFG/profiles"
cat > "$P/Laptop.json" <<'EOF'
{ "name": "Laptop", "monitors": [ { "name": "eDP-1", "hardware_id": "LG Display/0x06B3", "make": "LG Display", "model": "0x06B3",
  "PxW": 1920, "PxH": 1200, "Hz": 59.95, "Scale": 1, "X": 0, "Y": 0, "Active": true, "EDIDName": "LG Display 0x06B3",
  "Modes": [ { "W": 1920, "H": 1200, "Hz": 59.95 } ], "BitDepth": 0, "ColorMode": "", "SDRBrightness": 0, "SDRSaturation": 0,
  "VRR": 0, "Transform": 0, "IsMirrored": false, "MirrorSource": "", "MirrorTargets": null, "Dragging": false, "DragOffX": 0, "DragOffY": 0 } ],
  "created_at": "2026-07-29T07:01:00+02:00", "updated_at": "2026-07-29T07:01:00+02:00" }
EOF
sed 's/"Laptop"/"Work"/' "$P/Laptop.json" > "$P/Work.json"
sed 's/"Laptop"/"Home"/' "$P/Laptop.json" > "$P/Home.json"
printf '["Work", "Gone", "Laptop"]\n' > "$P/.profile_order"
echo 'not json' > "$P/Broken.json"

# list: the order first (a name with no file skipped), then the rest by name; a broken file skipped
same "list order" "$(sh "$S" list | jq -c 'map(.name)')" '["Work","Laptop","Home"]'
same "list carries monitors" "$(sh "$S" list | jq -r '.[1].monitors[0].hardware_id')" "LG Display/0x06B3"

# save a new one: goes last in the order, created now
printf '{ "monitors": [ { "name": "DP-7", "hardware_id": "Iiyama/PL3480WQ/1", "PxW": 3440, "PxH": 1440, "Hz": 60, "Scale": 1, "X": 0, "Y": 0, "Active": true } ] }\n' > "$T/new.json"
check "save new" sh "$S" save "Desk 9" "$T/new.json"
same "saved name inside" "$(jq -r .name "$P/Desk 9.json")" "Desk 9"
same "new one appended to the order" "$(jq -c . "$P/.profile_order")" '["Work","Gone","Laptop","Desk 9"]'
same "file mode" "$(stat -c %a "$P/Desk 9.json")" "600"

# overwrite: created_at kept, a backup made
check "save over" sh "$S" save Laptop "$T/new.json"
same "created_at kept" "$(jq -r .created_at "$P/Laptop.json")" "2026-07-29T07:01:00+02:00"
same "monitors replaced" "$(jq -r '.monitors[0].name' "$P/Laptop.json")" "DP-7"
same "a backup of the old one" "$(ls "$HYPRMON_CFG"/backups/*/Laptop.json | wc -l | tr -d ' ')" "1"

# rename: file, name inside, order
check "rename" sh "$S" rename Work "Work desk"
same "renamed file" "$(ls "$P" | grep -c '^Work desk.json$')" "1"
same "old file gone" "$(ls "$P" | grep -c '^Work.json$')" "0"
same "name inside" "$(jq -r .name "$P/Work desk.json")" "Work desk"
same "order follows" "$(jq -c . "$P/.profile_order")" '["Work desk","Gone","Laptop","Desk 9"]'
check "rename onto an existing one refused" sh -c "! sh '$S' rename Home Laptop"

# order, delete
check "order" sh "$S" order Laptop "Desk 9" Home "Work desk"
same "new order" "$(sh "$S" list | jq -c 'map(.name)')" '["Laptop","Desk 9","Home","Work desk"]'
check "delete" sh "$S" delete Home
same "deleted" "$(ls "$P" | grep -c '^Home.json$')" "0"
same "out of the order" "$(jq -c . "$P/.profile_order")" '["Laptop","Desk 9","Work desk"]'
check "deleting what is not there is fine" sh "$S" delete Nope

# bad input
check "a name with a slash is refused" sh -c "! sh '$S' save '../x' '$T/new.json'"
check "a dot name is refused" sh -c "! sh '$S' delete .profile_order"
printf '{ "monitors": [] }\n' > "$T/empty.json"
check "a profile with no monitors is refused" sh -c "! sh '$S' save Empty '$T/empty.json'"
check "unknown command" sh -c "! sh '$S' frobnicate"

# hyprmon reads what was written (list only, nothing applied)
if command -v hyprmon >/dev/null 2>&1; then
    rm -f "$P/Broken.json"
    got=$(hyprmon -cfg "$HYPRMON_CFG" -list-profiles 2>/dev/null | sed 's/ \*$//' | sort | tr '\n' ',')
    same "hyprmon lists them" "$got" "Desk 9,Laptop,Work desk,"
fi

if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
echo "hyprmon_script_test: all passed"
