"""Regression tests for the integration's deliberately narrow ownership boundary."""

import json
import os
import runpy
import shutil
import subprocess
import tempfile
import unittest
from hashlib import sha256
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / 'sekaipop/scripts/theming/app-theme.sh'
HELPER = SCRIPT.with_name('kitty-theme.py')
COLOURS = ('bg', 'fg', 'selfg', 'selbg', 'cursor', 'accent', 'border', 'surface',
           *(f'c{i}' for i in range(16)))


@unittest.skipUnless(shutil.which('kitty'), 'requires the Kitty executable')
class ArchitectureTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.env = dict(os.environ, HOME=str(self.home))
        for name in ('KITTY_CONFIG_DIRECTORY', 'XDG_CONFIG_DIRS', 'SEKAIPOP_TEST_SHARED_KITTY'):
            self.env.pop(name, None)
        for kind in ('CONFIG', 'STATE', 'DATA', 'CACHE'):
            self.env[f'XDG_{kind}_HOME'] = str(self.home / kind.lower())
        self.directory = self.home / 'config/kitty'
        self.directory.mkdir(parents=True)
        self.config = self.directory / 'kitty.conf'
        self.palette = self.directory / 'sekaipop-colors.conf'

    def theme(self, action, success=True):
        result = subprocess.run(['sh', str(SCRIPT), action, 'kitty',
                                 *(f'{key}=#445566' for key in COLOURS)],
                                env=self.env, capture_output=True, text=True, timeout=15)
        if success is not None:
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {str(p.relative_to(self.home)): (p.read_bytes(), p.stat().st_mtime_ns)
                for p in self.home.rglob('*') if p.is_file()}

    def native_background(self, env):
        result = subprocess.run(['kitty', '+runpy',
                                 'from kitty.config import load_config; '
                                 'from kitty.constants import defconf; '
                                 'o = load_config(defconf, accumulate_bad_lines=[]); '
                                 'print(f"#{int(o.background):06x}")'],
                                env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_process_config_directory_uses_its_home_and_requires_absolute_paths(self):
        helper = runpy.run_path(str(HELPER))
        env = {'HOME': str(self.home), 'KITTY_CONFIG_DIRECTORY': '~/terminal'}
        self.assertEqual(helper['config_directory'](env), self.home / 'terminal')
        env['KITTY_CONFIG_DIRECTORY'] = 'relative-terminal'
        with self.assertRaises(helper['Conflict']):
            helper['config_directory'](env)

    def test_glob_self_capture_is_rejected_before_first_write(self):
        # f629d2b's virtual glob matching misses the parent-directory spelling:
        # enable succeeds, then status immediately becomes blocked.
        self.config.write_text('font_size 13\nglobinclude ../kitty/sekaipop*.conf\n')
        before = self.snapshot()
        result = self.theme('enable', success=None)
        self.assertNotEqual(result.returncode, 0,
                            'Unexpected successful enable; status=' + self.theme('status').stdout.strip())
        self.assertEqual(self.snapshot(), before)

    def test_environment_variable_with_builtin_prefix_is_not_allowlisted(self):
        self.config.write_text('include $KITTY_OS_SUFFIX\n')
        (self.directory / 'other.conf').write_text('font_size 13\n')
        self.env['KITTY_OS_SUFFIX'] = 'other.conf'
        before = self.snapshot()
        self.theme('enable', success=False)
        self.assertEqual(self.snapshot(), before)

    def test_unsupported_dynamic_and_glob_inputs_are_rejected_without_writes(self):
        snippets = self.directory / 'snippets'
        snippets.mkdir()
        (snippets / 'font.conf').write_text('font_size 13\n')
        (self.directory / 'linked').symlink_to(snippets, target_is_directory=True)
        self.env['SEKAIPOP_TEST_SHARED_KITTY'] = 'font_size 13'
        self.env['SEKAIPOP_TEST_INCLUDE'] = 'snippets/font.conf'
        for line in ('envinclude SEKAIPOP_TEST_SHARED_KITTY',
                     'include $SEKAIPOP_TEST_INCLUDE', 'globinclude **/*.conf',
                     'globinclude snip*/*.conf', 'globinclude linked/*.conf',
                     f'globinclude {snippets}/*.conf'):
            with self.subTest(line=line):
                self.config.write_text(line + '\n')
                before = self.snapshot()
                self.theme('enable', success=False)
                self.assertEqual(self.snapshot(), before)

    def test_revert_keeps_palette_used_by_another_environment(self):
        self.config.write_text('font_size 13\n')
        self.theme('enable')
        self.theme('sync')
        with self.config.open('a') as output:
            output.write('envinclude SEKAIPOP_TEST_SHARED_KITTY\n')
        other_env = dict(self.env, SEKAIPOP_TEST_SHARED_KITTY='include sekaipop-colors.conf')
        self.assertEqual(self.native_background(other_env), '#445566')
        previous = self.palette.read_bytes()
        self.theme('revert')  # This process cannot see the other window's envinclude.
        self.assertTrue(self.palette.exists(), 'Revert deleted a palette still used in another environment')
        self.assertEqual(self.palette.read_bytes(), previous)
        self.assertEqual(self.native_background(other_env), '#445566')

    def test_retarget_after_revert_decision_cannot_delete_user_target(self):
        target = self.home / 'dotfiles/created.conf'
        target.parent.mkdir()
        fingerprint = sha256(str(target).encode()).hexdigest()
        original = ('# sekaipop: kitty colours (created symlink target sha256='
                    + fingerprint + ')\ninclude sekaipop-colors.conf\n')
        target.write_text(original)
        replacement = target.with_name('user.conf')
        replacement.write_text(original)
        self.config.symlink_to(target)
        # This represents a previously installed preview hook. The replacement
        # happens after the old implementation decided it owned the empty target.
        code = f'''
import runpy
from pathlib import Path
h = runpy.run_path({str(HELPER)!r})
root = Path({str(self.config)!r})
replacement = Path({str(replacement)!r})
backup = h['backup']
def retarget_after_backup(path, contents):
    backup(path, contents)
    if path == root:
        root.unlink()
        root.symlink_to(replacement)
h['change'].__globals__['backup'] = retarget_after_backup
try:
    h['change']('revert', root, [], False)
except h['Conflict']:
    pass  # Refusing an operation whose target changed is safe.
'''
        result = subprocess.run(['kitty', '+runpy', f'exec({code!r}, {{}})'],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(replacement.exists(), 'Revert deleted the newly selected user target')
        self.assertEqual(replacement.read_text(), original)
        self.assertTrue(target.exists())
        self.assertEqual(self.config.resolve(), replacement)

    def test_legacy_background_apply_cannot_reverse_revert(self):
        self.config.write_text('font_size 13\n')
        self.theme('enable')
        self.theme('sync')
        self.theme('revert')
        previous = self.config.read_bytes()
        # The pre-PR AppThemeService calls apply on each theme change, not sync.
        self.theme('apply')
        self.assertEqual(self.config.read_bytes(), previous)
        self.assertEqual(self.theme('status').stdout.strip(), 'off')

    def test_missing_directory_does_not_hide_an_active_legacy_writer(self):
        self.directory.rmdir()
        old_shell = self.home / 'old-shell/shell.qml'
        helper = old_shell.parent / 'scripts/theming/app-theme.sh'
        helper.parent.mkdir(parents=True)
        helper.write_text('kitty_apply() { :; }\n')
        (self.home / 'instances.json').write_text(json.dumps([{'config_path': str(old_shell)}]))
        binaries = self.home / 'bin'
        binaries.mkdir()
        qs = binaries / 'qs'
        qs.write_text('#!/bin/sh\ncat "$HOME/instances.json"\n')
        qs.chmod(0o755)
        self.env['PATH'] = str(binaries) + ':' + self.env['PATH']
        result = self.theme('revert', success=False)
        self.assertIn('legacy shell', result.stdout + result.stderr)
        self.assertFalse(self.directory.exists())

    def test_native_no_running_instances_diagnostic_allows_enable(self):
        binaries = self.home / 'bin'
        binaries.mkdir()
        qs = binaries / 'qs'
        qs.write_text('#!/bin/sh\nprintf "No running instances.\\n"\n')
        qs.chmod(0o755)
        self.env['PATH'] = str(binaries) + ':' + self.env['PATH']
        self.theme('enable')
        self.assertEqual(self.theme('status').stdout.strip(), 'on')

    def test_new_helper_on_disk_does_not_prove_running_shell_was_upgraded(self):
        self.theme('enable')
        before = self.config.read_bytes(), self.palette.read_bytes()
        helper = self.home / 'old-runtime/scripts/theming/app-theme.sh'
        helper.parent.mkdir(parents=True)
        shutil.copy(SCRIPT, helper)
        (self.home / 'instances.json').write_text(json.dumps([
            {'config_path': str(helper.parents[2] / 'shell.qml'), 'id': 'old-runtime'}]))
        binaries = self.home / 'bin'
        binaries.mkdir()
        qs = binaries / 'qs'
        qs.write_text('#!/bin/sh\ncase "$1" in list) cat "$HOME/instances.json" ;; '
                      'ipc) [ "$2" = -i ] && [ "$4" = call ] || exit 109; '
                      'printf "%s\\n" "${PROTOCOL_REPLY:-Function not found.}" ;; *) exit 109 ;; esac\n')
        qs.chmod(0o755)
        self.env['PATH'] = str(binaries) + ':' + self.env['PATH']
        self.theme('revert', success=False)
        self.assertEqual((self.config.read_bytes(), self.palette.read_bytes()), before)
        self.env['PROTOCOL_REPLY'] = 'enable-only'
        self.theme('revert')
        self.assertEqual(self.theme('status').stdout.strip(), 'off')
        self.assertEqual(self.palette.read_bytes(), before[1])


if __name__ == '__main__':
    unittest.main(verbosity=2)
