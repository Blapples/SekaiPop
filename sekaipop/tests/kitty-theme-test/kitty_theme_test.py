"""Run with python3 sekaipop/tests/kitty-theme-test/kitty_theme_test.py (requires Kitty)."""

import os
import runpy
import shutil
import subprocess
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[3]
THEMING = REPO / 'sekaipop/scripts/theming'
SCRIPT = THEMING / 'app-theme.sh'
COLOUR_ARGS = ('bg', 'fg', 'selfg', 'selbg', 'cursor', 'accent', 'border', 'surface',
               *(f'c{i}' for i in range(16)))
LEGACY_MARK = '# {}: managed block, removed by Settings -> Desktop -> App colours (revert)'
HEADER = '# Written by {} (app-theme.sh). Do not edit: it is rewritten with the theme.'
PALETTE_KEYS = ('foreground background selection_foreground selection_background cursor cursor_text_color '
                'url_color active_border_color inactive_border_color active_tab_foreground active_tab_background '
                'inactive_tab_foreground inactive_tab_background tab_bar_background').split() + [f'color{i}' for i in range(16)]


@unittest.skipUnless(shutil.which('kitty'), 'requires the Kitty executable')
class KittyThemeTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.env = dict(os.environ, HOME=str(self.home))
        self.env.pop('KITTY_CONFIG_DIRECTORY', None)
        self.env.pop('XDG_CONFIG_DIRS', None)
        for kind in ('CONFIG', 'STATE', 'DATA', 'CACHE'):
            self.env[f'XDG_{kind}_HOME'] = str(self.home / kind.lower())
        self.directory = self.home / 'config/kitty'
        self.config = self.directory / 'kitty.conf'
        self.palette = self.directory / 'sekaipop-colors.conf'
        self.backups = self.home / 'state/sekaipop/kitty-backups'

    def put(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode())
        return path

    def run_command(self, args, success=True, input_text=None):
        result = subprocess.run(args, env=self.env, input=input_text, text=True, capture_output=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, output)
        return output

    def theme(self, action, *args, success=True):
        return self.run_command(['sh', SCRIPT, action, 'kitty', *args], success)

    def apply(self, colour='#abc123', action='enable', success=True):
        return self.theme(action, *(f'{key}={colour}' for key in COLOUR_ARGS), success=success)

    def effective(self):
        return self.run_command(['kitty', '+runpy',
                                 'from kitty.config import load_config; '
                                 'from kitty.constants import defconf; '
                                 'bad = []; o = load_config(defconf, accumulate_bad_lines=bad); '
                                 'print(f"#{int(o.background):06x}", o.font_size); '
                                 'print(bad) if bad else None']).strip()

    def install(self, *args, success=True):
        return self.run_command(['bash', REPO / 'install.sh', '--yes', '--hypr', 'skip',
                                 '--no-deps', *args], success)

    def test_fresh_opt_in_and_detach_without_deleting_files(self):
        self.assertIn('(new)', self.theme('check'))
        self.theme('enable', '--dry-run')
        self.apply(action='sync')
        self.assertEqual(list(self.home.iterdir()), [])
        self.theme('enable')
        self.assertEqual(self.theme('status').strip(), 'pending')
        self.apply(action='sync')
        self.assertEqual(self.effective().split()[0], '#abc123')
        self.theme('revert')
        self.assertEqual(self.config.read_text(), '')
        retained = self.palette.read_bytes()
        self.apply(action='sync')
        self.apply(action='apply')
        self.assertEqual(self.config.read_text(), '')
        self.assertEqual(self.palette.read_bytes(), retained)

    def test_end4_reports_bad_template_then_can_enable(self):
        generated = self.put(self.home / '.local/state/quickshell/user/generated/terminal/kitty-theme.conf',
                             'background $background\ncolor0 $term0\ncolor1 $term1\n')
        original = 'include ~/.local/state/quickshell/user/generated/terminal/kitty-theme.conf\nfont_size 11\n'
        self.put(self.config, original)
        diagnostic = self.theme('check', success=False)
        self.assertIn(f'{generated}:2:', diagnostic)
        self.assertIn('$term1', diagnostic)
        self.apply(success=False)
        self.assertEqual(self.config.read_text(), original)
        self.assertFalse(self.palette.exists())

        # The user confirms that the bad reference is obsolete and comments it out.
        self.put(self.config, '#' + original)
        self.apply()
        self.assertEqual(self.effective(), '#abc123 11.0')
        self.theme('revert')
        self.assertEqual(self.config.read_text(), '#' + original)
        self.assertIn('$term0', generated.read_text())

    def test_other_generated_theme_and_complex_static_config(self):
        generated = self.put(self.directory / 'nested' / 'arbitrary-name',
                             'background rgb:11/22/33\nforeground white\ncolor1 red\n')
        settings = self.put(self.directory / 'nested' / 'settings.conf',
                            'include arbitrary-name\nfont_size 12\nmap ctrl+shift+c copy_to_clipboard\n')
        original = ('# user config\r\nglobinclude nested/*.conf\r\nfont_size 14\r\ncursor none\r\n'
                    'window_margin_width\r\n  \\ 12\r\nbackground #334455')
        self.put(self.config, original)
        fish = self.put(self.home / 'config/fish/config.fish', 'starship init fish | source\n')
        self.assertIn(str(generated), self.theme('check'))
        self.apply()
        self.assertEqual(self.effective(), '#abc123 14.0')
        self.assertEqual(next(self.backups.iterdir()).read_bytes(), original.encode())
        hooked = self.config.read_bytes()
        self.apply('#010203', action='sync')
        self.assertEqual(self.config.read_bytes(), hooked)
        self.assertEqual(self.effective(), '#010203 14.0')
        self.assertEqual(fish.read_text(), 'starship init fish | source\n')
        self.assertFalse((fish.parent / 'conf.d').exists())
        self.assertIn('map ctrl+shift+c', settings.read_text())
        self.theme('revert')
        self.assertEqual(self.config.read_bytes(), (original + '\r\n').encode())
        self.assertEqual(self.effective(), '#334455 14.0')
        self.assertIn('rgb:11/22/33', generated.read_text())

    def test_invalid_include_duplicate_syntax_and_unmatched_glob(self):
        self.put(self.directory / 'nested.conf', 'font_size 12\n')
        self.put(self.config, 'include absent.conf\ninclude nested.conf\ninclude ./nested.conf\n'
                 'globinclude snippets/*.conf\nfont_size nope\ninvalid line\nmissing-value\n')
        diagnostic = self.theme('check', success=False)
        for message in ('Could not find included config file', 'already been included', 'matched no files',
                        'font_size', 'unknown config key', 'invalid config line'):
            self.assertIn(message, diagnostic)
        self.theme('enable', success=False)
        self.assertFalse(self.palette.exists())
        self.assertFalse(self.backups.exists())

    def test_generator_and_native_auto_theme_are_reported(self):
        marker = self.home / 'generator-ran'
        generator = self.put(self.directory / 'theme.sh', f'#!/bin/sh\ntouch "{marker}"\n')
        generator.chmod(0o755)
        self.put(self.directory / 'dark-theme.auto.conf', 'background #123456\n')
        self.put(self.config, 'geninclude theme.sh\n')
        diagnostic = self.theme('check', success=False)
        self.assertIn('dynamic input was not evaluated', diagnostic)
        self.assertIn('automatic theme overrides kitty.conf', diagnostic)
        self.theme('enable', success=False)
        self.assertFalse(marker.exists())

    def test_glob_cannot_capture_a_new_managed_palette(self):
        original = 'font_size 12\nglobinclude sekaipop*.conf\n'
        self.put(self.config, original)
        self.assertIn('matched no files', self.theme('check'))
        self.assertIn('already been included', self.apply(success=False))
        self.assertEqual(self.config.read_text(), original)
        self.assertFalse(self.palette.exists())

    def test_restore_keeps_later_user_edits_and_unowned_files(self):
        self.put(self.config, 'font_size 12')
        self.apply()
        with self.config.open('a') as f:
            f.write('background #112233\n')
        self.assertIn('overrides the SekaiPop include', self.apply(action='sync', success=False))
        self.put(self.palette, '# user-owned file\nbackground #222222\n')
        self.theme('revert')
        self.assertEqual(self.config.read_text(), 'font_size 12\nbackground #112233\n')
        self.assertEqual(self.palette.read_text(), '# user-owned file\nbackground #222222\n')
        self.theme('enable', success=False)

    def test_restore_keeps_new_lines_before_the_hook(self):
        self.put(self.config, 'font_size 12')
        self.apply()
        config = self.config.read_text()
        edited = 'font_size 12\nmap ctrl+shift+c copy_to_clipboard\n\n'
        self.put(self.config, config.replace('font_size 12\n', edited, 1))
        self.theme('revert')
        self.assertEqual(self.config.read_text(), edited)

    def test_restore_preserves_a_manually_edited_palette(self):
        for transform in (lambda text: text + 'color1 #445566\n',
                          lambda text: text.replace('background #abc123', 'background #445566', 1)):
            with self.subTest(transform=transform):
                self.apply()
                edited = transform(self.palette.read_text())
                self.put(self.palette, edited)
                self.apply(action='sync', success=False)
                self.theme('revert')
                self.assertEqual(self.config.read_text(), '')
                self.assertEqual(self.palette.read_text(), edited)
                self.palette.unlink()

    def test_existing_managed_blocks_are_respected(self):
        for name in ('pjsekai', 'sekaipop'):
            with self.subTest(name=name):
                previous = f'{HEADER.format(name)}\n' + ''.join(f'{key} #abc123\n' for key in PALETTE_KEYS)
                palette = self.put(self.directory / f'{name}-colors.conf', previous)
                original = 'font_size 12\n'
                self.put(self.config, f'{original}{LEGACY_MARK.format(name)}\ninclude {palette.name}\n')
                self.assertEqual(self.theme('status').strip(), 'on')
                # The wallpaper can change while the old shell is not running.
                self.apply('#112233', action='sync')
                self.assertIn(previous, [p.read_text() for p in self.backups.iterdir()])
                self.apply('#112233', action='sync')
                self.assertEqual(self.effective(), '#112233 12.0')
                self.theme('revert')
                self.assertEqual(self.config.read_text(), original)
                self.assertTrue(palette.exists())

    def test_restore_keeps_an_unsigned_legacy_palette(self):
        previous = f'{HEADER.format("sekaipop")}\nbackground #112233\n'
        self.put(self.palette, previous)
        original = 'font_size 12\n'
        self.put(self.config, original + LEGACY_MARK.format('sekaipop') + '\ninclude sekaipop-colors.conf\n')
        # A header alone proves no ownership of a partial or edited set of values.
        self.apply(action='sync', success=False)
        self.theme('revert')
        self.assertEqual(self.config.read_text(), original)
        self.assertEqual(self.palette.read_text(), previous)

    def test_ambiguous_ownership_is_not_rewritten(self):
        edited = f'{LEGACY_MARK.format("sekaipop")}\nfont_size 11\n'
        self.put(self.config, edited)
        self.assertEqual(self.theme('status').strip(), 'conflict')
        self.theme('revert', success=False)
        self.assertEqual(self.config.read_text(), edited)

    def test_symlinked_config_enable_sync_and_restore(self):
        original = 'font_size 13\ninclude extras.conf\n'
        target = self.put(self.home / 'dotfiles/kitty.conf', original)
        self.put(self.directory / 'extras.conf', 'window_margin_width 7\n')
        self.config.symlink_to(target)
        self.apply()
        installed = target.read_bytes()
        self.apply('#112233', action='sync')
        self.assertEqual(target.read_bytes(), installed)
        self.assertEqual(self.effective(), '#112233 13.0')
        self.theme('revert')
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(self.config.resolve(), target)
        self.assertEqual(target.read_text(), original)
        self.assertTrue(self.palette.exists())

    def test_legacy_symlink_sync_does_not_rewrite_config(self):
        target = self.put(self.home / 'dotfiles/kitty.conf',
                          LEGACY_MARK.format('sekaipop') + '\ninclude sekaipop-colors.conf\n')
        self.put(self.palette, HEADER.format('sekaipop') + '\n')
        self.config.symlink_to(target)
        before = target.stat()
        self.apply(action='sync')
        self.assertEqual((target.stat().st_ino, target.stat().st_mtime_ns),
                         (before.st_ino, before.st_mtime_ns))
        self.theme('revert')
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_text(), '')

    def test_sync_ignores_unrelated_audit_errors(self):
        self.apply()
        for problem in ('some_future_option 1\n', 'font_size nope\n', 'include missing.conf\n',
                        'foreground $unexpanded\n', 'include extras.conf\ninclude ./extras.conf\n'):
            with self.subTest(problem=problem):
                self.put(self.directory / 'extras.conf', 'window_margin_width 7\n')
                # Earlier invalid colour definitions cannot override the managed palette.
                self.put(self.config, problem + '# sekaipop: kitty colours\ninclude sekaipop-colors.conf\n')
                before = self.config.read_bytes()
                self.apply('#112233', action='sync')
                self.assertIn('background #112233', self.palette.read_text())
                self.assertEqual(self.config.read_bytes(), before)
                self.assertEqual(self.theme('status').strip(), 'on')
                self.theme('check', success=False)
                self.apply('#abc123', action='sync')

    def test_status_detects_and_clears_managed_conflicts(self):
        self.apply()
        original = self.config.read_text()
        for addition in ('background #112233\n', 'include sekaipop-colors.conf\n'):
            self.put(self.config, original + addition)
            self.assertEqual(self.theme('status').strip(), 'blocked')
            self.put(self.config, original)
            self.assertEqual(self.theme('status').strip(), 'on')
        palette = self.palette.read_text()
        self.put(self.palette, palette + 'color1 #123456\n')
        self.assertEqual(self.theme('status').strip(), 'blocked')
        self.put(self.palette, palette)
        self.assertEqual(self.theme('status').strip(), 'on')

    def test_repeated_user_include_still_checks_colour_precedence(self):
        self.put(self.directory / 'other-theme.conf', 'background #224466\n')
        self.put(self.config, 'include other-theme.conf\n')
        self.apply()
        with self.config.open('a') as f:
            f.write('include ./other-theme.conf\n')
        # Kitty skips a repeat of the same lexical path; unrelated duplicate errors
        # must not block sync. A different symlink alias really does override colours.
        self.apply('#112233', action='sync')
        (self.directory / 'alias.conf').symlink_to('other-theme.conf')
        with self.config.open('a') as f:
            f.write('include alias.conf\n')
        before = self.palette.read_bytes()
        self.assertIn('overrides the SekaiPop include', self.apply('#334455', action='sync', success=False))
        self.assertEqual(self.palette.read_bytes(), before)

    def test_literal_dollar_include_matches_kitty_expansion(self):
        self.env['literal'] = 'wrong-path'
        self.put(self.directory / '$literal.conf', 'font_size 14\n')
        original = 'include $$literal.conf\n'
        self.put(self.config, original)
        self.apply()
        self.apply('#112233', action='sync')
        self.assertEqual(self.effective(), '#112233 14.0')
        self.theme('revert')
        self.assertEqual(self.config.read_text(), original)

    def test_revert_keeps_a_created_config_moved_behind_a_symlink(self):
        self.apply()
        target = self.home / 'dotfiles/kitty.conf'
        target.parent.mkdir()
        self.config.rename(target)
        self.config.symlink_to(target)
        self.theme('revert')
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_text(), '')

    def test_revert_preserves_a_user_palette_symlink(self):
        self.apply()
        target = self.home / 'dotfiles/colours.conf'
        target.parent.mkdir()
        self.palette.rename(target)
        self.palette.symlink_to(target)
        original = target.read_bytes()
        self.theme('revert', '--dry-run')
        self.assertTrue(self.palette.is_symlink())
        self.theme('revert')
        self.assertTrue(self.palette.is_symlink())
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(self.config.read_text(), '')

    def test_dangling_config_link_requires_manual_target_creation(self):
        target = self.home / 'dotfiles/kitty.conf'
        target.parent.mkdir()
        self.directory.mkdir(parents=True)
        self.config.symlink_to(target)
        for args in (('--dry-run',), ()):
            self.assertIn('dangling config link', self.theme('enable', *args, success=False))
            self.assertTrue(self.config.is_symlink())
            self.assertFalse(target.exists())
            self.assertFalse(self.palette.exists())
        self.put(target, 'font_size 13\n')
        self.apply()
        self.theme('revert')
        self.assertEqual(target.read_text(), 'font_size 13\n')

    def test_old_created_target_marker_only_detaches_the_hook(self):
        helper = runpy.run_path(str(THEMING / 'kitty-theme.py'))
        target = self.home / 'dotfiles/kitty.conf'
        marker = '# sekaipop: kitty colours (created symlink target sha256=' + helper['digest'](str(target)) + ')'
        self.put(target, marker + '\ninclude sekaipop-colors.conf\nfont_size 13\n')
        self.directory.mkdir(parents=True)
        self.config.symlink_to(target)
        self.theme('revert')
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_text(), 'font_size 13\n')

    def test_failed_config_write_keeps_palette_for_retry(self):
        original = 'font_size 13\n'
        self.put(self.config, original)
        args = [f'{key}=#abc123' for key in COLOUR_ARGS]
        code = f"""
import runpy
from pathlib import Path
h = runpy.run_path({str(THEMING / 'kitty-theme.py')!r})
write = h['File'].write
root = Path({str(self.config)!r})
def refuse_root(file, after):
    if file.path == root:
        raise h['Conflict']('injected config write failure')
    write(file, after)
h['File'].write = refuse_root
try:
    h['change']('enable', root, {args!r}, False)
except h['Conflict'] as error:
    print(error)
else:
    raise RuntimeError('write failure was not exercised')
"""
        self.assertIn('injected config write failure', self.run_command(['kitty', '+runpy', f'exec({code!r}, {{}})']))
        self.assertEqual(self.config.read_text(), original)
        self.assertIn('background #abc123', self.palette.read_text())
        self.assertEqual(self.theme('status').strip(), 'off')
        self.apply()
        self.assertEqual(self.theme('status').strip(), 'on')

    def test_dynamic_include_does_not_claim_successful_sync(self):
        self.apply('#445566')
        ran = self.home / 'generator-ran'
        generator = self.put(self.directory / 'dynamic.py',
                             f'#!/usr/bin/env python3\nfrom pathlib import Path\n'
                             f'Path({str(ran)!r}).touch()\nprint("background #998877")\n')
        generator.chmod(0o755)
        with self.config.open('a') as f:
            f.write('geninclude dynamic.py\n')
        # Run Kitty's real parser to establish the effective precedence.
        self.assertEqual(self.effective().split()[0], '#998877')
        self.assertTrue(ran.exists())
        ran.unlink()
        before = self.palette.read_bytes()
        self.assertEqual(self.theme('status').strip(), 'blocked')
        output = self.apply('#112233', action='sync', success=False)
        self.assertIn('dynamic input was not evaluated', output)
        self.assertEqual(self.palette.read_bytes(), before)
        self.assertFalse(ran.exists())

    def test_invalid_later_colour_is_ignored_like_kitty(self):
        self.apply()
        with self.config.open('a') as f:
            f.write('background $term0\n')
        self.assertEqual(self.effective().split()[0], '#abc123')
        self.apply('#445566', action='sync')
        self.assertEqual(self.effective().split()[0], '#445566')
        self.assertEqual(self.theme('status').strip(), 'on')
        self.theme('check', success=False)

    def test_missing_palette_is_pending_until_sync_repairs_it(self):
        self.apply()
        self.palette.unlink()
        self.assertEqual(self.theme('status').strip(), 'pending')
        self.apply('#445566', action='sync')
        self.assertEqual(self.theme('status').strip(), 'on')
        self.assertEqual(self.effective().split()[0], '#445566')

    def test_preview_newline_marker_remains_recoverable(self):
        original = 'font_size 12\n'
        self.put(self.config, original + '# sekaipop: kitty colours (added newline)\n'
                 'include sekaipop-colors.conf\n')
        self.put(self.palette, HEADER.format('sekaipop') + '\n')
        self.apply(action='sync')
        self.assertEqual(self.effective(), '#abc123 12.0')
        self.theme('revert')
        # The old marker cannot prove which newline is ours; keep it conservatively.
        self.assertEqual(self.config.read_text(), original)

    def test_unsigned_legacy_format_is_not_proof_of_unmodified_colours(self):
        previous = HEADER.format('sekaipop') + '\n' + ''.join(f'{key} #654321\n' for key in PALETTE_KEYS)
        self.put(self.palette, previous)
        self.put(self.config, LEGACY_MARK.format('sekaipop') + '\ninclude sekaipop-colors.conf\n')
        output = self.apply(action='sync')
        self.assertIn('cannot distinguish manual edits', output)
        self.assertIn(previous, [p.read_text() for p in self.backups.iterdir()])

    def test_revert_without_kitty(self):
        original = 'font_size 13\n'
        self.put(self.config, original)
        self.apply()
        binaries = self.home / 'bin'
        binaries.mkdir()
        for name in ('sh', 'dirname', 'python3', 'bash', 'id', 'date', 'readlink'):
            (binaries / name).symlink_to(shutil.which(name))
        self.env['PATH'] = str(binaries)
        self.assertEqual(self.theme('status').strip(), 'blocked')
        self.theme('revert', '--dry-run')
        self.assertTrue(self.palette.exists())
        self.theme('revert')
        self.assertEqual(self.config.read_text(), original)
        self.assertTrue(self.palette.exists())

        # Directory discovery must be identical for status and revert after uninstall.
        self.env['PATH'] = os.environ['PATH']
        self.apply()
        fallback = self.home / '.config/kitty'
        fallback.parent.mkdir()
        self.directory.rename(fallback)
        self.env['PATH'] = str(binaries)
        self.assertEqual(self.theme('status').strip(), 'blocked')
        self.theme('revert')
        self.assertEqual((fallback / 'kitty.conf').read_text(), original)
        self.assertTrue((fallback / 'sekaipop-colors.conf').exists())
        # Both UI/script revert and the public installer restore use the same fallback.
        self.env['PATH'] = os.environ['PATH']
        self.apply()
        self.env['PATH'] = str(binaries)
        self.install('--restore-kitty')
        self.assertEqual((fallback / 'kitty.conf').read_text(), original)
        self.assertTrue((fallback / 'sekaipop-colors.conf').exists())

    def test_reload_respects_only_config_and_palette_overrides(self):
        proc = self.home / 'processes/123'
        self.put(proc / 'comm', 'kitty\n')
        self.put(proc / 'environ', '\0'.join(f'{k}={v}' for k, v in self.env.items()) + '\0')
        for options, reload in ((['--class', 'dropdown', '-o', 'font_size=12'], True),
                                (['--override', 'window_margin_width=8'], True),
                                (['-o', ''], True),
                                (['-o', '  '], True),
                                (['-o', 'background=#123456'], False),
                                (['-o', 'background #123456'], False),
                                (['-o', 'color3=#123456'], False),
                                (['--config', 'other.conf'], False)):
            with self.subTest(options=options):
                self.put(proc / 'cmdline', '\0'.join(['kitty', *options]) + '\0')
                code = (f'import runpy; from pathlib import Path; from unittest.mock import patch; '
                        f'h = runpy.run_path({str(THEMING / "kitty-theme.py")!r}); '
                        f'p = patch.object(Path, "iterdir", return_value=iter([Path({str(proc)!r})])); '
                        'p.start(); k = patch("os.kill"); calls = k.start(); '
                        f'h["reload_windows"](Path({str(self.directory)!r})); '
                        'print(calls.call_count)')
                self.assertEqual(self.run_command(['kitty', '+runpy', code]).strip(), str(int(reload)))

    def test_user_reference_to_generated_file_survives_restore(self):
        self.put(self.config, 'font_size 11\n')
        self.apply()
        with self.config.open('a') as f:
            f.write('include ./sekaipop-colors.conf\n')
        self.apply(action='sync', success=False)
        self.theme('revert')
        self.assertEqual(self.config.read_text(), 'font_size 11\ninclude ./sekaipop-colors.conf\n')
        self.assertTrue(self.palette.is_file())

    def test_restore_retains_an_orphan_for_external_references(self):
        self.apply()
        self.config.unlink()
        self.theme('revert', '--dry-run')
        self.assertTrue(self.palette.is_file())
        self.theme('revert')
        self.assertTrue(self.palette.exists())

    def test_concurrent_enable_sync_and_restore(self):
        original = 'font_size 13\n'
        self.put(self.config, original)
        colours = [f'{key}=#abc123' for key in COLOUR_ARGS]

        def parallel(*commands):
            with ExitStack() as stack:
                jobs = [stack.enter_context(subprocess.Popen(
                    ['sh', SCRIPT, action, 'kitty', *args], env=self.env,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
                )) for action, args in commands]
                for job in jobs:
                    output, _ = job.communicate(timeout=10)
                    self.assertEqual(job.returncode, 0, output)

        parallel(('enable', []), ('apply', colours), ('sync', colours))
        self.assertEqual(self.config.read_text().count('include sekaipop-colors.conf\n'), 1)
        parallel(('sync', colours), ('revert', []), ('sync', colours))
        self.assertEqual(self.config.read_text(), original)
        self.assertTrue(self.palette.exists())

    def test_write_detects_an_edit_during_staging(self):
        helper = runpy.run_path(str(THEMING / 'kitty-theme.py'))
        original = 'font_size 13\n'
        self.put(self.config, original)
        edited = original + 'window_margin_width 8\n'
        mkstemp = tempfile.mkstemp

        def stage_then_save(*args, **kwargs):
            result = mkstemp(*args, **kwargs)
            self.put(self.config, edited)
            return result

        with mock.patch.object(tempfile, 'mkstemp', stage_then_save):
            with self.assertRaisesRegex(helper['Conflict'], 'changed during the operation'):
                helper['File'](self.config).write(original + 'include sekaipop-colors.conf\n')
        self.assertEqual(self.config.read_text(), edited)
        self.assertEqual(list(self.directory.iterdir()), [self.config])

    def test_write_preserves_a_symlink_retargeted_during_staging(self):
        helper = runpy.run_path(str(THEMING / 'kitty-theme.py'))
        original = 'font_size 13\n'
        target = self.put(self.home / 'dotfiles/kitty.conf', original)
        replacement = self.put(self.home / 'dotfiles/other.conf', original)
        self.directory.mkdir(parents=True)
        self.config.symlink_to(target)
        mkstemp = tempfile.mkstemp

        def stage_then_retarget(*args, **kwargs):
            result = mkstemp(*args, **kwargs)
            self.config.unlink()
            self.config.symlink_to(replacement)
            return result

        with mock.patch.object(tempfile, 'mkstemp', stage_then_retarget):
            with self.assertRaisesRegex(helper['Conflict'], 'changed during the operation'):
                helper['File'](self.config).write(original + 'include sekaipop-colors.conf\n')
        self.assertEqual(self.config.resolve(), replacement)
        self.assertEqual(target.read_text(), original)
        self.assertEqual(replacement.read_text(), original)

    def test_config_directory_override(self):
        directory = self.home / 'custom kitty'
        self.env['KITTY_CONFIG_DIRECTORY'] = str(directory)
        self.apply()
        self.assertTrue((directory / self.config.name).is_file())
        self.assertFalse(self.directory.exists())
        self.theme('revert')
        self.assertEqual((directory / self.config.name).read_text(), '')

    @unittest.skipIf(os.getuid() == 0, 'installer requires an unprivileged user')
    def test_installer_dry_run_repeat_and_restore(self):
        # Use the normal installer path, with just the shell files needed for this test.
        rice = self.home / 'rice'
        self.put(rice / 'shell.qml', 'import QtQuick\n')
        scripts = rice / 'scripts/theming'
        scripts.mkdir(parents=True)
        for name in ('app-theme.sh', 'kitty-theme.py'):
            shutil.copy(THEMING / name, scripts / name)
        self.install('--rice', rice, '--kitty', 'enable', '--dry-run')
        self.assertEqual(list(self.home.iterdir()), [rice])

        config_home = self.home / 'config'
        old_settings = self.put(config_home / 'pjsekai/settings.json', '{"theme":"pjsekai"}\n')
        kde_backup = self.put(config_home / 'kdeglobals.pjsekai-bak', 'ColorScheme=PjsekaiA\n')
        hypr_files = {
            self.put(config_home / name, 'source = pjsekai_overrides.lua\n')
            for name in ('hypr/hyprland.conf', 'hypr/pjsekai_overrides.lua', 'hypr/sekaipop_overrides.lua',
                         'hypr.pjsekai-backup-20260101-000000/hyprland.conf',
                         'hypr.pjsekai-replaced-20260101-000000/hyprland.conf',
                         'hypr.pjsekai-previous/hyprland.conf')
        }

        def hypr_snapshot():
            return {p: (p.read_bytes(), p.stat().st_mtime_ns)
                    for folder in (config_home / 'hypr', *config_home.glob('hypr.*'))
                    for p in folder.rglob('*') if p.is_file()}

        original_hypr = hypr_snapshot()
        self.assertEqual(set(original_hypr), hypr_files)
        # Pretend a shell is running to catch any installer-initiated restart in skip mode.
        qs = self.put(self.home / 'bin/qs', '#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/qs-calls"\n')
        qs.chmod(0o755)
        self.env['PATH'] = f'{qs.parent}:{self.env["PATH"]}'
        self.env['GSETTINGS_BACKEND'] = 'memory'
        preview = self.install('--rice', rice, '--kitty', 'enable', '--dry-run')
        self.assertIn(f'move {old_settings.parent}', preview)
        self.assertIn(f'rename {kde_backup}', preview)
        self.assertNotIn(f'{config_home}/hypr', preview)
        self.assertEqual(hypr_snapshot(), original_hypr)
        self.assertTrue(old_settings.exists())

        self.install('--rice', rice)
        self.assertEqual((config_home / 'sekaipop/settings.json').read_text(), '{"theme":"sekaipop"}\n')
        self.assertEqual((config_home / 'kdeglobals.sekaipop-bak').read_text(), 'ColorScheme=SekaipopA\n')
        self.assertFalse(old_settings.exists())
        self.assertEqual(hypr_snapshot(), original_hypr)
        self.assertFalse(self.config.exists())
        self.install('--rice', rice, '--kitty', 'enable')
        self.apply(action='sync')
        previous = self.config.read_bytes()
        self.install('--rice', rice)
        self.install('--rice', rice, '--kitty', 'enable')
        self.assertEqual(self.config.read_bytes(), previous)
        self.install('--restore-kitty', '--dry-run')
        self.assertEqual(self.config.read_bytes(), previous)
        self.install('--restore-kitty')
        self.install('--rice', rice)
        self.apply(action='sync')
        self.assertEqual(self.config.read_text(), '')
        self.assertTrue(self.palette.exists())
        self.assertEqual(hypr_snapshot(), original_hypr)
        calls = (self.home / 'qs-calls').read_text().splitlines()
        self.assertFalse(any(' ipc ' in call for call in calls))
        self.assertFalse(any(call.endswith(' list') or ' list -p ' in call for call in calls))

        self.assertIn('cannot be combined', self.install('--restore', success=False))
        self.assertEqual(hypr_snapshot(), original_hypr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
