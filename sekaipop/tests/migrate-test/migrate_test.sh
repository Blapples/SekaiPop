#!/bin/bash
# Tests for scripts/system/migrate-from-pjsekai.sh: builds a fake home that looks like an install
# from before the rename, runs the migration and checks what moved and what was rewritten.
#   bash tests/migrate-test/migrate_test.sh
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../../scripts/system/migrate-from-pjsekai.sh"
fails=0; checks=0
ck() { checks=$((checks+1)); if ! eval "$2"; then fails=$((fails+1)); echo "FAIL: $1"; fi; }

H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
export HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" XDG_CACHE_HOME="$H/.cache" XDG_DATA_HOME="$H/.local/share"
C="$H/.config"; ST="$H/.local/state"; CA="$H/.cache"; D="$H/.local/share"

mkdir -p "$C/pjsekai/presets" "$ST/pjsekai/terminal" "$CA/pjsekai/matugen" "$D/pjsekai/custom-images" \
         "$C/hypr/hyprland" "$C/hypr.pjsekai-backup-20260101-000000" "$C/hypr.pjsekai-previous" \
         "$C/kitty" "$C/gtk-3.0" "$C/fish/conf.d" "$C/Code/User" "$C/vesktop/themes" "$C/vesktop/settings" \
         "$D/themes/pjsekai-adw-gtk3" "$D/color-schemes" "$C/matugen" "$C/qt6ct/colors"
echo '{"theme":"x"}' > "$C/pjsekai/settings.json"
echo "{\"image\":\"$D/pjsekai/custom-images/a.png\"}" > "$C/pjsekai/presets/one.json"
echo png > "$D/pjsekai/custom-images/a.png"
echo "p" > "$ST/pjsekai/terminal/prompt.sh"
echo '{"c":1}' > "$CA/pjsekai/matugen/colors.json"
printf 'hl.config({}) -- pjsekai:hypr:general.gaps_out\n' > "$C/hypr/pjsekai_overrides.lua"
printf 'load("pjsekai_overrides", true)\n' > "$C/hypr/hyprland.lua"
printf 'hl.layer_rule({ match = { namespace = "^pjsekai-" } })\n' > "$C/hypr/hyprland/rules.lua"
printf 'user = 1\n' > "$C/hypr.pjsekai-backup-20260101-000000/hyprland.conf"
printf '# pjsekai: managed block, removed by Settings -> Desktop -> App colours (revert)\ninclude pjsekai-colors.conf\nfont_size 12\n' > "$C/kitty/kitty.conf"
printf '# Written by pjsekai\nforeground #fff\n' > "$C/kitty/pjsekai-colors.conf"
printf "@import 'pjsekai-colors.css';\n" > "$C/gtk-3.0/gtk.css"
printf '@define-color x #000;\n' > "$C/gtk-3.0/pjsekai-colors.css"
printf '# pjsekai: managed file\nfunction __pjsekai_define_prompt\nend\n' > "$C/fish/conf.d/pjsekai-prompt.fish"
printf '{\n  /* pjsekai:begin */ "workbench.colorCustomizations": {}, /* pjsekai:end */\n  "editor.fontSize": 14\n}\n' > "$C/Code/User/settings.json"
printf '/* @name pjsekai */\n' > "$C/vesktop/themes/pjsekai.theme.css"
printf '{"enabledThemes":["pjsekai.theme.css"]}\n' > "$C/vesktop/settings/settings.json"
printf '[templates.pjsekai-gtk3]\ninput_path = "x"\n' > "$C/matugen/config.toml"
printf '[General]\nColorScheme=PjsekaiA\n' > "$C/kdeglobals"
printf 'Name=PjsekaiA\n' > "$D/color-schemes/PjsekaiA.colors"
printf 'color_scheme_path=%s/qt6ct/colors/pjsekai.conf\n' "$C" > "$C/qt6ct/qt6ct.conf"
printf 'cc\n' > "$C/qt6ct/colors/pjsekai.conf"
printf 'export A=1\nsource ~/.local/state/pjsekai/terminal/prompt.sh\n' > "$H/.zshrc"
printf 'my own line mentioning nothing\n' > "$H/.bashrc"
mkdir -p "$C/unrelated"; printf 'pjsekai in someone else folder\n' > "$C/unrelated/notes.txt"

# dry run changes nothing
sh "$S" --dry-run > /tmp/mig-dry.txt
ck "dry run keeps the old folder" '[ -d "$C/pjsekai" ] && [ ! -e "$C/sekaipop" ]'
ck "dry run says what it would do" 'grep -q "would be made" /tmp/mig-dry.txt'

sh "$S" > /tmp/mig-run.txt
ck "config folder moved" '[ -f "$C/sekaipop/settings.json" ] && [ ! -e "$C/pjsekai" ]'
ck "state folder moved" '[ -f "$ST/sekaipop/terminal/prompt.sh" ]'
ck "cache folder moved" '[ -f "$CA/sekaipop/matugen/colors.json" ]'
ck "data folder moved" '[ -f "$D/sekaipop/custom-images/a.png" ]'
ck "preset path follows the data folder" 'grep -q "$D/sekaipop/custom-images/a.png" "$C/sekaipop/presets/one.json" && ! grep -q pjsekai "$C/sekaipop/presets/one.json"'
ck "hypr overrides renamed and rewritten" '[ -f "$C/hypr/sekaipop_overrides.lua" ] && grep -q "sekaipop:hypr:general.gaps_out" "$C/hypr/sekaipop_overrides.lua"'
ck "hyprland.lua loads the new name" 'grep -q "sekaipop_overrides" "$C/hypr/hyprland.lua" && ! grep -q pjsekai "$C/hypr/hyprland.lua"'
ck "layer rules follow the namespace" 'grep -q "\^sekaipop-" "$C/hypr/hyprland/rules.lua"'
ck "hypr backups renamed for --restore" '[ -d "$C/hypr.sekaipop-backup-20260101-000000" ] && [ -d "$C/hypr.sekaipop-previous" ]'
ck "backup content is left as it was" 'grep -q "user = 1" "$C/hypr.sekaipop-backup-20260101-000000/hyprland.conf"'
ck "kitty config is left to the Kitty integration" 'grep -q "include pjsekai-colors.conf" "$C/kitty/kitty.conf" && grep -q "font_size 12" "$C/kitty/kitty.conf"'
ck "kitty colours file keeps its existing name" '[ -f "$C/kitty/pjsekai-colors.conf" ] && [ ! -e "$C/kitty/sekaipop-colors.conf" ]'
ck "gtk import and file renamed" 'grep -q "sekaipop-colors.css" "$C/gtk-3.0/gtk.css" && [ -f "$C/gtk-3.0/sekaipop-colors.css" ]'
ck "fish prompt file renamed and rewritten" 'grep -q "__sekaipop_define_prompt" "$C/fish/conf.d/sekaipop-prompt.fish"'
ck "VS Code block markers" 'grep -q "sekaipop:begin" "$C/Code/User/settings.json" && grep -q "editor.fontSize" "$C/Code/User/settings.json"'
ck "Discord theme renamed and enabled entry follows" '[ -f "$C/vesktop/themes/sekaipop.theme.css" ] && grep -q "sekaipop.theme.css" "$C/vesktop/settings/settings.json"'
ck "matugen template name" 'grep -q "templates.sekaipop-gtk3" "$C/matugen/config.toml"'
ck "KDE scheme name and file" 'grep -q "ColorScheme=SekaipopA" "$C/kdeglobals" && [ -f "$D/color-schemes/SekaipopA.colors" ] && grep -q "Name=SekaipopA" "$D/color-schemes/SekaipopA.colors"'
ck "generated GTK theme folder renamed" '[ -d "$D/themes/sekaipop-adw-gtk3" ]'
ck "qt6ct points at the renamed colours" 'grep -q "colors/sekaipop.conf" "$C/qt6ct/qt6ct.conf" && [ -f "$C/qt6ct/colors/sekaipop.conf" ]'
ck "shell rc line follows" 'grep -q "state/sekaipop/terminal/prompt.sh" "$H/.zshrc" && grep -q "export A=1" "$H/.zshrc"'
ck "an rc file without the old name is untouched" 'grep -q "my own line" "$H/.bashrc"'
ck "other programs folders are left alone" 'grep -q pjsekai "$C/unrelated/notes.txt"'
ck "the log lists the rewrites" 'grep -q "rewrote" "$ST/sekaipop/migration.log"'

# second run: nothing to do
mkdir -p "$ST/sekaipop/kitty-backups"
printf 'include pjsekai-colors.conf\n' > "$ST/sekaipop/kitty-backups/kitty.conf-test"
sh "$S" > /tmp/mig-again.txt
ck "second run does nothing" 'grep -q "nothing left" /tmp/mig-again.txt'
ck "Kitty backups preserve the original bytes" 'grep -qx "include pjsekai-colors.conf" "$ST/sekaipop/kitty-backups/kitty.conf-test"'

# both old and new exist (the new shell started first): old files are copied in, the old folder is kept aside
mkdir -p "$C/pjsekai" && echo '{"theme":"old"}' > "$C/pjsekai/settings.json"
echo '{"theme":"default"}' > "$C/sekaipop/settings.json"
sh "$S" > /tmp/mig-merge.txt
ck "merge: old settings win" 'grep -q old "$C/sekaipop/settings.json"'
ck "merge: old folder kept aside, not deleted" 'ls -d "$C"/pjsekai.migrated-* >/dev/null 2>&1'
sh "$S" > /tmp/mig-after.txt
ck "kept-aside folder is not touched again" 'ls -d "$C"/pjsekai.migrated-* >/dev/null 2>&1 && ! ls -d "$C"/sekaipop.migrated-* >/dev/null 2>&1'

# The old name survives only in compatibility code, fixtures and the dev log.
repo="$here/../../.."
left=$(grep -rIl -i pjsekai "$repo" --exclude-dir=.git --exclude=DEVLOG.md 2>/dev/null | sed "s#^$repo/##" |
    grep -vxE 'install\.sh|sekaipop/scripts/system/migrate-from-pjsekai\.sh|sekaipop/scripts/theming/kitty-theme\.py|sekaipop/tests/(kitty-theme-test/kitty_theme_test\.py|migrate-test/migrate_test\.sh)')
ck "the old name only survives where it must: [$left]" '[ -z "$left" ]'

echo "$checks checks, $fails failed"
[ "$fails" = 0 ]
