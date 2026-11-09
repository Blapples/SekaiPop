"""Exercise installer boundaries without mutating a running Quickshell's environment."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]


@unittest.skipIf(os.getuid() == 0, 'installer requires an unprivileged user')
class InstallerRestartTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.env = dict(os.environ, HOME=str(self.home), GSETTINGS_BACKEND='memory')
        for kind in ('CONFIG', 'STATE', 'CACHE', 'DATA'):
            self.env[f'XDG_{kind}_HOME'] = str(self.home / kind.lower())
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        self.env.pop('KITTY_CONFIG_DIRECTORY', None)
        self.installer = self.home / 'source/install.sh'
        self.installer.parent.mkdir()
        shutil.copy(REPO / 'install.sh', self.installer)
        self.rice = self.home / 'rice'
        self.installed = self.home / 'config/quickshell/sekaipop'
        self.write(self.rice / 'shell.qml', '// new shell\n')
        self.write(self.rice / 'VERSION', 'test\n')
        self.write(self.rice / 'scripts/theming/kitty-theme.py', '# fixture\n')
        self.write(self.rice / 'scripts/theming/app-theme.sh',
                   '#!/bin/sh\n[ "$1" != status ] || echo off\nexit 0\n')
        self.hypr = self.write(self.home / 'config/hypr/hyprland.conf', '# user config\n')
        binaries = self.home / 'bin'
        self.write(binaries / 'qs', '#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/qs-calls"\n'
                   'case "$*" in *"ipc call apptheme syncKitty") '
                   '[ -z "${TEST_IPC_OUTPUT:-}" ] || printf "%s\\n" "$TEST_IPC_OUTPUT"; '
                   'exit "${TEST_IPC_RESULT:-1}" ;; esac\n')
        self.write(binaries / 'setsid', '#!/bin/sh\necho restart >> "$HOME/restarts"\n')
        self.write(binaries / 'Hyprland', '#!/bin/sh\necho "Hyprland 0.57.1"\n')
        self.write(binaries / 'pacman', '#!/bin/sh\necho "qt6-base 6.12.0"\n')
        for binary in binaries.iterdir():
            binary.chmod(0o755)
        self.env['PATH'] = f'{binaries}:{self.env["PATH"]}'

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def install(self, *options, success=True):
        result = subprocess.run(['bash', str(self.installer), '--yes', '--hypr', 'skip', '--no-deps',
                                 '--rice', str(self.rice), *options],
                                env=self.env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, output)
        self.assertEqual(self.hypr.read_text(), '# user config\n')
        self.assertFalse((self.home / 'restarts').exists())
        return output

    def test_skip_upgrade_explains_restart_requirement(self):
        self.write(self.installed / 'shell.qml', '// old shell\n')
        output = self.install('--kitty', 'keep')
        self.assertIn('Restart SekaiPop to load the installed shell', output)
        self.assertEqual((self.installed / 'shell.qml').read_text(), '// new shell\n')

    def test_enable_never_calls_a_running_shell(self):
        self.installed.parent.mkdir(parents=True)
        shutil.copytree(self.rice, self.installed)
        for code, diagnostic in (('1', ''), ('0', 'Function not found.'), ('0', '')):
            with self.subTest(code=code, diagnostic=diagnostic):
                self.env['TEST_IPC_RESULT'] = code
                self.env['TEST_IPC_OUTPUT'] = diagnostic
                output = self.install('--kitty', 'enable')
                self.assertFalse((self.home / 'qs-calls').exists())
                self.assertIn('Kitty hook is ready; palette sync is not yet confirmed', output)
                self.assertIn('same KITTY_CONFIG_DIRECTORY', output)
                self.assertNotIn('Kitty colour sync is enabled.', output)

    def test_restore_dry_run_cannot_fall_back_to_an_old_installed_script(self):
        palette = self.write(self.home / 'config/kitty/sekaipop-colors.conf', '# user colours\n')
        # The original upstream revert ignored extra arguments such as --dry-run.
        legacy = self.write(self.installed / 'scripts/theming/app-theme.sh',
                            '#!/bin/sh\nrm -f "$HOME/config/kitty/sekaipop-colors.conf"\n')
        result = subprocess.run(['bash', str(self.installer), '--restore-kitty', '--dry-run'],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertTrue(palette.exists(), result.stdout + result.stderr)
        self.assertEqual(palette.read_text(), '# user colours\n')
        self.assertTrue(legacy.exists())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('bundled Kitty helper', result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('kitty'), 'requires the Kitty executable')
    def test_enable_does_not_sync_another_shells_config_directory(self):
        for name in ('app-theme.sh', 'kitty-theme.py'):
            shutil.copy(REPO / 'sekaipop/scripts/theming' / name,
                        self.rice / 'scripts/theming' / name)
        custom = self.home / 'installer-kitty'
        self.env['KITTY_CONFIG_DIRECTORY'] = str(custom)
        # Simulate a running shell which inherited a different config directory.
        qs = self.home / 'bin/qs'
        qs.write_text('#!/bin/sh\n'
                      'case "$*" in *"ipc call apptheme syncKitty") '
                      'mkdir -p "$HOME/service-kitty"; '
                      'printf "background #112233\\n" > "$HOME/service-kitty/sekaipop-colors.conf" ;; esac\n')
        output = self.install('--kitty', 'enable')
        self.assertTrue((custom / 'kitty.conf').exists())
        self.assertFalse((self.home / 'service-kitty').exists())
        self.assertIn('same KITTY_CONFIG_DIRECTORY', output)

    @unittest.skipUnless(shutil.which('kitty'), 'requires the Kitty executable')
    def test_repeated_enable_ignores_unrelated_errors_like_the_helper(self):
        scripts = self.rice / 'scripts/theming'
        for name in ('app-theme.sh', 'kitty-theme.py'):
            shutil.copy(REPO / 'sekaipop/scripts/theming' / name, scripts / name)
        self.installed.parent.mkdir(parents=True)
        shutil.copytree(self.rice, self.installed)
        helper = scripts / 'app-theme.sh'
        enabled = subprocess.run(['sh', str(helper), 'enable', 'kitty'],
                                 env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(enabled.returncode, 0, enabled.stdout + enabled.stderr)
        config = self.home / 'config/kitty/kitty.conf'
        with config.open('a') as output:
            output.write('some_future_option 1\n')
        snapshot = {p: (p.read_bytes(), p.stat().st_mtime_ns)
                    for p in config.parent.rglob('*') if p.is_file()}
        repeated = subprocess.run(['sh', str(helper), 'enable', 'kitty', '--dry-run'],
                                  env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(repeated.returncode, 0, repeated.stdout + repeated.stderr)
        self.install('--kitty', 'enable', '--dry-run')
        self.assertEqual({p: (p.read_bytes(), p.stat().st_mtime_ns)
                          for p in config.parent.rglob('*') if p.is_file()}, snapshot)

    @unittest.skipUnless(shutil.which('kitty'), 'requires the Kitty executable')
    def test_first_enable_still_requires_the_helper_audit(self):
        for name in ('app-theme.sh', 'kitty-theme.py'):
            shutil.copy(REPO / 'sekaipop/scripts/theming' / name,
                        self.rice / 'scripts/theming' / name)
        config = self.write(self.home / 'config/kitty/kitty.conf', 'background $term0\n')
        output = self.install('--kitty', 'enable', '--dry-run', success=False)
        self.assertIn('Kitty colour sync could not be enabled', output)
        self.assertEqual(config.read_text(), 'background $term0\n')
        self.assertFalse((config.parent / 'sekaipop-colors.conf').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
