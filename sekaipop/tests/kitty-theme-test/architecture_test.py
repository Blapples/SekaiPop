"""Regression tests for the integration's deliberately narrow ownership boundary."""

import json
import io
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import traceback
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from hashlib import sha256
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock


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


class KittyApiTest(unittest.TestCase):
    """Representative private API signatures; runs with Python alone, without Kitty."""
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.directory = self.home / 'config/kitty'
        self.directory.mkdir(parents=True)
        self.config = self.directory / 'kitty.conf'
        self.palette = self.directory / 'sekaipop-colors.conf'
        self.config.write_text('font_size 13\n')
        helper = runpy.run_path(str(HELPER))
        self.palette.write_text(helper['managed_palette'](self.palette, 'background #112233\n'))
        self.env = {'HOME': str(self.home), 'PATH': '', 'XDG_CONFIG_HOME': str(self.home / 'config'),
                    'XDG_STATE_HOME': str(self.home / 'state')}
        self.calls = []
        self.conf = ModuleType('kitty.conf.utils')
        self.conf.parse_line = lambda *args: None
        self.conf.key_pat = re.compile(r'(\S+)\s+(.+)')
        self.conf.NamedLineIterator = lambda name, lines: lines
        self.conf.currently_parsing = SimpleNamespace(file='', number=1)

        @contextmanager
        def set_file(name):
            previous = self.conf.currently_parsing.file
            self.conf.currently_parsing.file = name
            try:
                yield
            finally:
                self.conf.currently_parsing.file = previous

        self.conf.currently_parsing.set_file = set_file
        self.log_error = lambda message: None
        self.modules = {
            'kitty': ModuleType('kitty'),
            'kitty.conf': SimpleNamespace(utils=self.conf),
            'kitty.options.parse': SimpleNamespace(create_result_dict=dict, parse_conf_item=lambda *args: True),
            'kitty.utils': SimpleNamespace(expandvars=lambda value, env: value, log_error=self.log_error),
        }

    def old_parser(self, lines, item, options, bad=None, effective_config_lines=None):
        self.calls.append('old parser must not run')

    def current_parser(self, lines, item, options, bad=None, effective_config_lines=None, allow_geninclude=True):
        self.calls.append(allow_geninclude)
        for line in lines:
            self.conf.parse_line(line, item, options, str(self.directory))

    def installed(self):
        self.config.write_text('font_size 13\n# sekaipop: kitty colours\ninclude sekaipop-colors.conf\n')

    def snapshot(self):
        return {str(p.relative_to(self.home)): p.read_bytes() for p in self.home.rglob('*') if p.is_file()}

    def invoke(self, action, parser, *extra):
        self.conf.parse_config_base = parser
        output, error = io.StringIO(), io.StringIO()
        code = 0
        # Run the actual command entry point and render uncaught exceptions as the
        # Python CLI would. None of these fixtures import or launch installed Kitty.
        with mock.patch.dict(sys.modules, self.modules), mock.patch.dict(os.environ, self.env, clear=True), \
                mock.patch.object(sys, 'argv', [str(HELPER), action, *extra]), \
                redirect_stdout(output), redirect_stderr(error):
            try:
                runpy.run_path(str(HELPER), run_name='__main__')
            except SystemExit as exc:
                code = exc.code
            except Exception:
                code = 1
                traceback.print_exc()
        return code, output.getvalue(), error.getvalue()

    def test_old_api_refuses_check_and_enable_without_writes_or_traceback(self):
        before = self.snapshot()
        for action, extra in (('check', ()), ('enable', ()), ('enable', ('--dry-run',))):
            with self.subTest(action=action, extra=extra):
                code, _, error = self.invoke(action, self.old_parser, *extra)
                self.assertEqual(code, 1)
                self.assertNotIn('Traceback', error)
                self.assertIn('Kitty 0.47', error)
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(self.calls, [])

    def test_old_api_installed_hook_is_blocked_and_sync_is_refused(self):
        self.installed()
        before = self.snapshot()
        for action in ('status', 'sync'):
            with self.subTest(action=action):
                code, output, error = self.invoke(action, self.old_parser, *(f'{k}=#445566' for k in COLOURS))
                self.assertEqual(code, 0 if action == 'status' else 1)
                if action == 'status':
                    self.assertEqual(output.strip(), 'blocked')
                self.assertIn('Kitty 0.47', error)
                self.assertNotIn('Traceback', error)
                self.assertEqual(self.snapshot(), before)

    def test_supported_api_keeps_generator_execution_disabled(self):
        before = self.snapshot()
        code, _, error = self.invoke('check', self.current_parser)
        self.assertEqual((code, error), (0, ''))
        self.assertTrue(self.calls)
        self.assertEqual(set(self.calls), {False})
        self.assertEqual(self.snapshot(), before)

    def test_uninspectable_parser_is_reported_as_incompatible(self):
        self.installed()
        before = self.snapshot()
        code, output, error = self.invoke('status', min)
        self.assertEqual((code, output.strip()), (0, 'blocked'))
        self.assertIn('cannot inspect configuration parser signature', error)
        self.assertNotIn('Traceback', error)
        self.assertEqual(self.snapshot(), before)

    def test_future_signature_error_restores_temporary_parser_changes(self):
        def future_parser(lines, item, options, bad, *, required_new_argument, allow_geninclude=True):
            raise AssertionError('signature should reject our call')

        self.installed()
        before = self.snapshot()
        original_line = self.conf.parse_line
        for existing in (False, True):
            with self.subTest(existing=existing):
                if existing:
                    self.conf.open = original_line
                    self.log_error.redirect = original_line
                code, output, error = self.invoke('status', future_parser)
                self.assertEqual((code, output.strip()), (0, 'blocked'))
                self.assertIn('incompatible', error)
                self.assertNotIn('Traceback', error)
                self.assertIs(self.conf.parse_line, original_line)
                for owner, name in ((self.conf, 'open'), (self.log_error, 'redirect')):
                    self.assertEqual(hasattr(owner, name), existing)
                    if existing:
                        self.assertIs(getattr(owner, name), original_line)
                self.assertEqual(self.snapshot(), before)
                code, _, error = self.invoke('check', self.current_parser)
                self.assertEqual((code, error), (0, ''))

    def test_collected_api_type_error_cannot_be_ignored_by_sync(self):
        def collecting_parser(lines, item, options, bad, effective_config_lines=None, allow_geninclude=True):
            self.current_parser(lines, item, options, bad, effective_config_lines, allow_geninclude)
            bad.append(SimpleNamespace(exception=TypeError('future parse_line signature'),
                                       file=str(self.config), number=1, line='font_size 13'))

        self.installed()
        before = self.snapshot()
        for action in ('status', 'sync'):
            with self.subTest(action=action):
                code, output, error = self.invoke(action, collecting_parser, *(f'{k}=#445566' for k in COLOURS))
                self.assertEqual(code, 0 if action == 'status' else 1)
                if action == 'status':
                    self.assertEqual(output.strip(), 'blocked')
                self.assertIn('incompatible', error)
                self.assertNotIn('Traceback', error)
                self.assertEqual(self.snapshot(), before)

    def test_no_hook_status_and_sync_do_not_require_parser_compatibility(self):
        for action in ('status', 'sync'):
            code, output, error = self.invoke(action, self.old_parser)
            self.assertEqual((code, error), (0, ''))
            if action == 'status':
                self.assertEqual(output.strip(), 'off')
        self.assertEqual(self.calls, [])

    def test_revert_does_not_require_a_supported_or_installed_kitty(self):
        previous = self.palette.read_bytes()
        for missing in (False, True):
            with self.subTest(missing=missing):
                self.installed()
                if missing:
                    self.modules['kitty.conf'] = None
                code, _, error = self.invoke('revert', self.old_parser)
                self.assertEqual((code, error), (0, ''))
                self.assertEqual(self.config.read_text(), 'font_size 13\n')
                self.assertEqual(self.palette.read_bytes(), previous)
                self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
