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

    def apply(self, colour='#abc123', action='apply', success=True):
        return self.theme(action, *(f'{key}={colour}' for key in COLOUR_ARGS), success=success)

    def effective(self):
        return self.run_command(['kitty', '+runpy',
                                 'from kitty.config import load_config; '
                                 'from kitty.constants import defconf; '
                                 'bad = []; o = load_config(defconf, accumulate_bad_lines=bad); '
                                 'assert not bad, bad; print(f"#{int(o.background):06x}", o.font_size)']).strip()

    def install(self, *args, success=True):
        return self.run_command(['bash', REPO / 'install.sh', '--yes', '--hypr', 'skip',
                                 '--no-deps', *args], success)

    def test_fresh_opt_in_and_exact_restore(self):
        self.assertIn('(new)', self.theme('check'))
        self.theme('enable', '--dry-run')
        self.apply(action='sync')
        self.assertEqual(list(self.home.iterdir()), [])
        self.theme('enable')
        self.assertEqual(self.theme('status').strip(), 'on')
        self.apply(action='sync')
        self.assertEqual(self.effective().split()[0], '#abc123')
        self.theme('revert')
        self.assertFalse(self.config.exists())
        self.assertFalse(self.palette.exists())
        self.apply(action='sync')
        self.assertFalse(self.config.exists())

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

    def test_other_dynamic_theme_and_complex_config(self):
        generated = self.put(self.directory / 'nested' / 'arbitrary-name',
                             'background rgb:11/22/33\nforeground white\ncolor1 red\n')
        settings = self.put(self.directory / 'nested' / 'settings.conf',
                            'include $DYNAMIC_THEME\nfont_size 12\nmap ctrl+shift+c copy_to_clipboard\n')
        original = ('# user config\r\nglobinclude nested/*.conf\r\nenvinclude TEST_KITTY_CONFIG\r\n'
                    'window_margin_width\r\n  \\ 12\r\nbackground #334455')
        self.env['TEST_KITTY_CONFIG'] = 'font_size 14\ncursor none'
        self.env['DYNAMIC_THEME'] = generated.name
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
        self.assertEqual(self.config.read_bytes(), original.encode())
        self.assertEqual(self.effective(), '#334455 14.0')
        self.assertIn('rgb:11/22/33', generated.read_text())

    def test_invalid_include_duplicate_syntax_and_unmatched_glob(self):
        self.put(self.directory / 'nested.conf', 'font_size 12\n')
        self.put(self.config, 'include absent.conf\ninclude nested.conf\ninclude ./nested.conf\n'
                 'globinclude snippets/*.conf\nfont_size nope\ninvalid line\nmissing-value\n')
        diagnostic = self.theme('check', success=False)
        for message in ('missing include', 'duplicate or recursive reference', 'matched no files',
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
        self.assertIn('generator was not run', diagnostic)
        self.assertIn('automatic theme overrides kitty.conf', diagnostic)
        self.theme('enable', success=False)
        self.assertFalse(marker.exists())

    def test_glob_cannot_capture_a_new_managed_palette(self):
        original = 'font_size 12\nglobinclude **/sekaipop*.conf\n'
        self.put(self.config, original)
        self.assertIn('matched no files', self.theme('check'))
        self.assertIn('duplicate or recursive reference', self.apply(success=False))
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
                self.assertFalse(self.config.exists())
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
                self.apply('#112233', action='sync', success=False)
                self.assertEqual(palette.read_text(), previous)
                self.apply(action='sync')
                self.assertIn(previous, [p.read_text() for p in self.backups.iterdir()])
                self.apply('#112233', action='sync')
                self.assertEqual(self.effective(), '#112233 12.0')
                self.theme('revert')
                self.assertEqual(self.config.read_text(), original)
                self.assertFalse(palette.exists())

    def test_restore_keeps_an_unsigned_legacy_palette(self):
        previous = f'{HEADER.format("sekaipop")}\nbackground #112233\n'
        self.put(self.palette, previous)
        original = 'font_size 12\n'
        self.put(self.config, original + LEGACY_MARK.format('sekaipop') + '\ninclude sekaipop-colors.conf\n')
        self.theme('revert')
        self.assertEqual(self.config.read_text(), original)
        self.assertEqual(self.palette.read_text(), previous)

    def test_ambiguous_ownership_is_not_rewritten(self):
        edited = f'{LEGACY_MARK.format("sekaipop")}\nfont_size 11\n'
        self.put(self.config, edited)
        self.theme('revert', success=False)
        self.assertEqual(self.config.read_text(), edited)
        self.config.unlink()
        original = self.put(self.home / 'dotfiles/kitty.conf', 'font_size 13\n')
        self.config.symlink_to(original)
        self.theme('enable', success=False)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(original.read_text(), 'font_size 13\n')

    def test_user_reference_to_generated_file_survives_restore(self):
        self.put(self.config, 'font_size 11\n')
        self.apply()
        with self.config.open('a') as f:
            f.write('include ./sekaipop-colors.conf\n')
        self.apply(action='sync', success=False)
        self.theme('revert')
        self.assertEqual(self.config.read_text(), 'font_size 11\ninclude ./sekaipop-colors.conf\n')
        self.assertTrue(self.palette.is_file())

    def test_restore_cleans_up_an_owned_orphan(self):
        self.apply()
        self.config.unlink()
        self.theme('revert', '--dry-run')
        self.assertTrue(self.palette.is_file())
        self.theme('revert')
        self.assertFalse(self.palette.exists())

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
        self.assertFalse(self.palette.exists())

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
                helper['write'](self.config, original, original + 'include sekaipop-colors.conf\n')
        self.assertEqual(self.config.read_text(), edited)
        self.assertEqual(list(self.directory.iterdir()), [self.config])

    def test_config_directory_override(self):
        directory = self.home / 'custom kitty'
        self.env['KITTY_CONFIG_DIRECTORY'] = str(directory)
        self.apply()
        self.assertTrue((directory / self.config.name).is_file())
        self.assertFalse(self.directory.exists())
        self.theme('revert')
        self.assertFalse((directory / self.config.name).exists())

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
        self.install('--rice', rice)
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
        self.assertFalse(self.config.exists())
        self.assertFalse(self.palette.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
