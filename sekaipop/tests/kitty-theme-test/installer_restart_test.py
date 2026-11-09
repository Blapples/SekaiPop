"""Exercise installer restart guidance with a simulated running Quickshell."""

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
                   'case "$*" in *"ipc call apptheme syncKitty") exit "${TEST_IPC_RESULT:-1}" ;; esac\n')
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

    def install(self, *options):
        result = subprocess.run(['bash', str(self.installer), '--yes', '--hypr', 'skip', '--no-deps',
                                 '--rice', str(self.rice), *options],
                                env=self.env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertEqual(self.hypr.read_text(), '# user config\n')
        self.assertFalse((self.home / 'restarts').exists())
        return output

    def test_skip_upgrade_explains_restart_requirement(self):
        self.write(self.installed / 'shell.qml', '// old shell\n')
        output = self.install('--kitty', 'keep')
        self.assertIn('Restart SekaiPop to load the installed shell', output)
        self.assertEqual((self.installed / 'shell.qml').read_text(), '// new shell\n')

    def test_old_process_without_sync_ipc_gets_guidance_even_if_files_match(self):
        self.installed.parent.mkdir(parents=True)
        shutil.copytree(self.rice, self.installed)
        output = self.install('--kitty', 'enable')
        self.assertIn('Start or restart SekaiPop to apply the current Kitty palette', output)
        self.assertIn('ipc call apptheme syncKitty', (self.home / 'qs-calls').read_text())

    def test_successful_sync_has_no_failure_guidance(self):
        self.installed.parent.mkdir(parents=True)
        shutil.copytree(self.rice, self.installed)
        self.env['TEST_IPC_RESULT'] = '0'
        output = self.install('--kitty', 'enable')
        self.assertNotIn('Start or restart SekaiPop to apply the current Kitty palette', output)


if __name__ == '__main__':
    unittest.main(verbosity=2)
