"""Manage the Kitty include; use Kitty's parser for first-time configuration audits."""

import fcntl
import io
import json
import shutil
import subprocess
import os
import re
import signal
import stat
import sys
import tempfile
from fnmatch import fnmatchcase
from hashlib import sha256
from inspect import signature
from pathlib import Path


PALETTE = {
    'foreground': 'fg', 'background': 'bg', 'selection_foreground': 'selfg',
    'selection_background': 'selbg', 'cursor': 'cursor', 'cursor_text_color': 'bg',
    'url_color': 'accent', 'active_border_color': 'accent', 'inactive_border_color': 'border',
    'active_tab_foreground': 'bg', 'active_tab_background': 'accent',
    'inactive_tab_foreground': 'fg', 'inactive_tab_background': 'surface',
    'tab_bar_background': 'bg', **{f'color{i}': f'c{i}' for i in range(16)},
}
MARK = '# sekaipop: kitty colours'
OLD_NAME = 'pjsekai'
LEGACY_MARK = '# {}: managed block, removed by Settings -> Desktop -> App colours (revert)'
HEADER = '# Written by {} (app-theme.sh). Do not edit: it is rewritten with the theme.'
PALETTE_NAME = 'sekaipop-colors.conf'
SYSTEM_CONF = Path('/etc/xdg/kitty/kitty.conf')
API_REQUIREMENT = 'Kitty colour integration needs Kitty 0.47 or newer with a compatible configuration parser'


class Conflict(Exception):
    pass


def error_message(error):
    return f'{API_REQUIREMENT} (incompatible API: {error})' if isinstance(error, TypeError) else str(error)


def digest(text):
    return sha256(text.encode('utf-8', errors='surrogateescape')).hexdigest()


def config_directory(env):
    home = Path(env.get('HOME', Path.home()))
    if env.get('KITTY_CONFIG_DIRECTORY'):
        value = env['KITTY_CONFIG_DIRECTORY']
        if value == '~' or value.startswith('~/'):
            value = str(home) + value[1:]
        directory = Path(os.path.expanduser(value))
        if not directory.is_absolute():
            raise Conflict('Use an absolute KITTY_CONFIG_DIRECTORY; process-relative paths are not managed')
        return directory
    primary = Path(env.get('XDG_CONFIG_HOME') or home / '.config') / 'kitty'
    candidates = [primary, home / '.config/kitty']
    candidates.extend(Path(d) / 'kitty' for d in env.get('XDG_CONFIG_DIRS', '').split(':') if d)
    return next((p for p in candidates if (p / 'kitty.conf').exists() and os.access(p, os.W_OK)), primary)


def read(path):
    try:
        mode = path.stat().st_mode
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(mode):
        raise Conflict(f'{path} is not a regular file')
    return path.read_bytes().decode('utf-8', errors='surrogateescape')


class Audit:
    """Kitty parses static config; this adapter limits our automatic management scope."""
    def __init__(self, root, palette, changes=None, strict=True):
        from kitty.conf import utils as conf
        from kitty.options.parse import create_result_dict, parse_conf_item
        from kitty.utils import expandvars, log_error

        try:
            if 'allow_geninclude' not in signature(conf.parse_config_base).parameters:
                raise TypeError('configuration parser lacks allow_geninclude')
        except ValueError as exc:
            raise TypeError('cannot inspect configuration parser signature') from exc

        self.errors, self.warnings, self.references = [], [], 0
        self.colour_sources, last = {}, {}
        bad, diagnostics = [], []
        changes = changes or {}
        original_line = conf.parse_line
        unset = object()
        original_open = getattr(conf, 'open', unset)
        original_redirect = getattr(log_error, 'redirect', unset)

        def location():
            return f'{conf.currently_parsing.file}:{conf.currently_parsing.number}'

        def source(path, *args, **kwargs):
            path = Path(path)
            if path in changes:
                stream = io.StringIO(changes[path] or '')
                stream.name = str(path)
                return stream
            return open(path, *args, **kwargs)

        def item(key, value, options):
            if not strict and key not in PALETTE:
                return True
            accepted = parse_conf_item(key, value, options)
            if accepted and key in PALETTE:
                name = conf.currently_parsing.file
                self.colour_sources.setdefault(name, set()).add(key)
                if self.references and Path(name).resolve() != palette.resolve():
                    last[key] = location()
            return accepted

        def line(text, parser, options, base, *args):
            match = conf.key_pat.match(text.strip())
            if match:
                key, value = match.groups()
                variables = re.findall(r'\$(?:(\w+)|\{([^}]+)\})', value.replace('$$', ''))
                if key in ('include', 'globinclude') and any((plain or braced) != 'KITTY_OS' for plain, braced in variables):
                    self.errors.append(f'{location()}: environment-dependent include requires manual configuration')
                    return
                value = expandvars(os.path.expanduser(value), {'KITTY_OS': 'linux'})
                if key in ('envinclude', 'geninclude'):
                    self.errors.append(f'{location()}: {key} requires manual configuration; dynamic input was not evaluated')
                    return
                if key == 'globinclude':
                    prefix, _, pattern = value.rpartition('/')
                    # Only filename wildcards in one directory: no virtual filesystem
                    # or attempts to predict recursive, parent or linked-directory globs.
                    directory = Path(base) / prefix
                    if (Path(value).is_absolute() or '..' in Path(value).parts
                            or any(c in prefix for c in '*?[') or '**' in pattern
                            or directory.resolve() != Path(os.path.abspath(directory))):
                        self.errors.append(f'{location()}: complex globinclude {value!r} requires manual configuration')
                        return
                    paths = set(directory.glob(pattern))
                    if palette in changes and directory.resolve() == palette.parent.resolve() and fnmatchcase(palette.name, pattern):
                        paths.add(palette)
                    if not paths:
                        self.warnings.append(f'{location()}: globinclude {value} matched no files')
                    for path in sorted(paths):
                        line('include ' + str(path).replace('$', '$$'), parser, options, base, *args)
                    return
                if key == 'include' and (Path(base) / value).resolve() == palette.resolve():
                    self.references += 1
            original_line(text, parser, options, base, *args)

        conf.parse_line, conf.open = line, source
        log_error.redirect = lambda message: diagnostics.append(f'{location()}: {message}')
        try:
            options = create_result_dict()
            for file in (SYSTEM_CONF, root):
                text = changes.get(file, read(file))
                if text is not None:
                    with conf.currently_parsing.set_file(str(file)):
                        conf.parse_config_base(conf.NamedLineIterator(str(file), iter(text.splitlines(True))),
                                               item, options, bad, allow_geninclude=False)
        finally:
            conf.parse_line = original_line
            for owner, name, previous in ((conf, 'open', original_open), (log_error, 'redirect', original_redirect)):
                if previous is unset:
                    delattr(owner, name)
                else:
                    setattr(owner, name, previous)
        # Kitty can collect callback signature errors as bad config lines. They
        # invalidate the audit even when sync ignores unrelated user config errors.
        for failure in bad:
            if isinstance(failure.exception, TypeError):
                raise failure.exception
        if strict:
            self.errors.extend(diagnostics)
            self.errors.extend(f'{b.file}:{b.number}: {b.line}: {b.exception}' for b in bad)
        if self.references:
            self.errors.extend(f'{where}: {key} overrides the SekaiPop include'
                               for key, where in last.items())
        for name in ('dark-theme.auto.conf', 'light-theme.auto.conf', 'no-preference-theme.auto.conf'):
            if os.path.lexists(root.parent / name):
                self.errors.append(f'{root.parent / name}: automatic theme overrides kitty.conf; configure it manually')


def find_hook(config, root):
    """Only the exact known marker/include pair is ours. Never remove surrounding bytes."""
    marker = (r'# sekaipop: kitty colours(?: \(created config\)| \(added newline\)|'
              r' \((?:added newline|created symlink target) sha256=[0-9a-f]{64}\))?')
    markers = {LEGACY_MARK.format(name): f'{name}-colors.conf' for name in ('sekaipop', OLD_NAME)}
    hits = []
    pattern = rf'(?:^|(?<=[\r\n]))([ \t]*# (?:sekaipop|{OLD_NAME}): (?:kitty colours|managed block)[^\r\n]*)(?:\r\n|[\r\n])?'
    for match in re.finditer(pattern, config):
        name = PALETTE_NAME if re.fullmatch(marker, match[1]) else markers.get(match[1])
        if name is None:
            raise Conflict(f'{root}: unfamiliar integration marker; review it manually')
        include = re.match(r'include ' + re.escape(name) + r'(?:\r\n|[\r\n]|\Z)', config[match.end():])
        if not include or re.match(r'[ \t]*\\', config[match.end() + (include.end() if include else 0):]):
            raise Conflict(f'{root}: managed include was edited; review it manually')
        hits.append((match.start(), match.end() + include.end(), root.parent / name))
    if len(hits) > 1:
        raise Conflict(f'{root}: multiple managed includes; review them manually')
    return hits[0] if hits else None


def palette_header(path):
    return HEADER.format(path.name.removesuffix('-colors.conf')) + '\n'


def managed_palette(path, body):
    return f'{palette_header(path)}# sekaipop: palette sha256={digest(body)}\n{body}'


def owned_palette(path, contents):
    parts = (contents or '').split('\n', 2)
    return len(parts) == 3 and contents == managed_palette(path, parts[2])


def legacy_palette(path, contents):
    """Recognise the old format, not authorship or absence of manual colour edits."""
    header = palette_header(path)
    if not contents.startswith(header):
        return False
    lines = contents[len(header):].splitlines(keepends=True)
    return not lines or (len(lines) == len(PALETTE) and all(
        re.fullmatch(rf'{key} #[0-9a-fA-F]{{6}}\n', line) for key, line in zip(PALETTE, lines)
    ))


class File:
    """Pin the target at read time; only replace unchanged regular files, never delete."""
    def __init__(self, path):
        self.path, self.target = path, path.resolve()
        self.before = read(self.target)

    def write(self, after):
        def verify():
            if self.path.resolve() != self.target or read(self.target) != self.before:
                raise Conflict(f'{self.path} changed during the operation; retry after reviewing it')
        verify()
        info = self.target.stat() if self.before is not None else None
        if info and (info.st_uid != os.getuid() or info.st_nlink != 1):
            raise Conflict(f'{self.path}: expected a user-owned file without hard links')
        fd, temporary = tempfile.mkstemp(prefix='.sekaipop-', dir=self.target.parent)
        try:
            with os.fdopen(fd, 'wb') as stream:
                os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode) if info else 0o600)
                stream.write(after.encode('utf-8', errors='surrogateescape'))
            verify()
            os.replace(temporary, self.target)
        finally:
            Path(temporary).unlink(missing_ok=True)


def backup(path, contents):
    if contents is None:
        return
    directory = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'sekaipop/kitty-backups'
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=path.name + '-', dir=directory, delete=False) as f:
        f.write(contents.encode('utf-8', errors='surrogateescape'))
        print(f'Kitty backup: {f.name}')


def show(audit):
    for name, keys in audit.colour_sources.items():
        print(f'Kitty colour settings: {name} ({len(keys)} settings)')
    for message in audit.warnings + audit.errors:
        print(f'Kitty: {message}', file=sys.stderr)


def process_environment(proc):
    return dict(item.split('=', 1) for item in os.fsdecode((proc / 'environ').read_bytes()).split('\0') if '=' in item)


def reject_legacy_writers(directory):
    """Old helpers cannot honour our revoke. Require their shells to stop first."""
    if not shutil.which('qs'):
        return
    result = subprocess.run(['qs', 'list', '-a', '-j'], capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise Conflict('Cannot inspect running shells; stop them before changing Kitty integration')
    try:
        instances = [] if result.stdout.strip() == 'No running instances.' else json.loads(result.stdout or '[]')
        for instance in instances:
            helper = Path(instance['config_path']).parent / 'scripts/theming/app-theme.sh'
            text = read(helper)
            if text and ('kitty_apply()' in text or 'kitty-theme.py' in text):
                try:
                    env = process_environment(Path('/proc') / str(instance['pid']))
                    target = (Path(env.get('XDG_CONFIG_HOME') or Path(env['HOME']) / '.config') / 'kitty'
                              if 'kitty_apply()' in text else config_directory(env))
                    if target.resolve() != directory.resolve():
                        continue
                except (OSError, KeyError, Conflict):
                    pass  # An unidentifiable old writer must be stopped explicitly.
                if instance.get('id'):
                    reply = subprocess.run(['qs', 'ipc', '-i', instance['id'], 'call', 'apptheme', 'kittyProtocol'],
                                           capture_output=True, text=True, timeout=5)
                    if reply.returncode == 0 and reply.stdout.strip() == 'enable-only':
                        continue
                raise Conflict(f'Stop or upgrade the legacy shell at {helper.parent.parent.parent} before changing Kitty integration')
    except (ValueError, KeyError, TypeError):
        raise Conflict('Cannot identify running shell versions; stop them before changing Kitty integration')


def reload_windows(directory):
    # Limit SIGUSR1 to our user's Kitty GUIs using this default config directory.
    try:
        from kitty.cli import parse_args, parse_override
        from kitty.utils import is_kitty_gui_cmdline
    except ImportError:
        return  # Restoring config must also work after Kitty has been uninstalled.

    for proc in Path('/proc').iterdir():
        if not proc.name.isdecimal():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / 'comm').read_bytes().strip() != b'kitty':
                continue
            args = os.fsdecode((proc / 'cmdline').read_bytes()).removesuffix('\0').split('\0')
            if not is_kitty_gui_cmdline(*args):
                continue
            options, _ = parse_args(args[1:])
            if options.config or any(value.strip() and parse_override(value).split(maxsplit=1)[0] in PALETTE
                                     for value in options.override):
                continue
            env = process_environment(proc)
            if config_directory(env).resolve() == directory.resolve():
                os.kill(int(proc.name), signal.SIGUSR1)
        except (OSError, RuntimeError, SystemExit, Conflict):
            continue


def change(action, root, args, dry):
    config_file = File(root)
    original = config_file.before
    config = original or ''
    try:
        hook = find_hook(config, root)
    except Conflict:
        if action == 'status':
            print('conflict')
            return
        raise
    palette = hook[2] if hook else root.parent / PALETTE_NAME

    if action == 'revert':
        reject_legacy_writers(root.parent)
        if hook:
            if dry:
                print(f'Would remove only the SekaiPop include from {root}; keep all files.')
            else:
                backup(root, original)
                config_file.write(config[:hook[0]] + config[hook[1]:])
                reload_windows(root.parent)
        print(f'Kitty: kept {palette}; any other references remain user-managed.')
        return
    # Old in-memory services call apply periodically. Only explicit enable may opt in.
    if action in ('apply', 'sync') and not hook:
        return
    if action == 'status' and not hook:
        print('off')
        return
    if action == 'check':
        audit = Audit(root, palette)
        print(f'Kitty config: {root}' + (' (new)' if original is None else ''), flush=True)
        show(audit)
        if audit.errors:
            raise Conflict('Review the reported configuration before enabling Kitty colours')
        return

    try:
        colour_file = File(palette)
        before = colour_file.before
        legacy = before is not None and not owned_palette(palette, before)
        if palette.is_symlink():
            raise Conflict(f'{palette}: linked palette is user-managed; use a regular generated file')
        if legacy and not legacy_palette(palette, before):
            raise Conflict(f'{palette}: edited or unrecognised palette; review it manually')
        after = before if before is not None else managed_palette(palette, '')
        if action in ('apply', 'sync') or (action == 'enable' and any('=' in arg for arg in args)):
            values = dict(arg.split('=', 1) for arg in args if '=' in arg)
            if any(not re.fullmatch(r'#[0-9a-fA-F]{6}', values.get(key, '')) for key in PALETTE.values()):
                raise Conflict('Kitty palette is incomplete or contains invalid colours')
            after = managed_palette(palette, ''.join(f'{key} {values[name]}\n' for key, name in PALETTE.items()))
        proposed = config
        if not hook:
            if root.is_symlink() and original is None:
                raise Conflict(f'{root}: dangling config link; create its target yourself before enabling')
            newline = '\r\n' if '\r\n' in config else '\n'
            if config and not config.endswith(('\r', '\n')):
                proposed += newline
            proposed += f'{MARK}{newline}include {palette.name}{newline}'
        audit = Audit(root, palette, {root: proposed, palette: after}, strict=not hook)
        if audit.errors or audit.references != 1:
            if action != 'status':
                show(audit)
            raise Conflict('Kitty integration requires one unambiguous static include; review the reported configuration')
    except (Conflict, OSError, ImportError, TypeError) as exc:
        if action == 'status':
            if isinstance(exc, TypeError):
                print(f'Kitty: {error_message(exc)}', file=sys.stderr)
            print('blocked')
            return
        raise
    if action == 'status':
        print('pending' if before is None or before in (palette_header(palette), managed_palette(palette, '')) else 'on')
        return
    reject_legacy_writers(root.parent)
    if dry:
        print(f'Would enable Kitty colours in {root}.' if not hook else f'Kitty integration already enabled in {root}.')
        return
    if proposed != config:
        backup(root, original)
    if after != before:
        if legacy:
            print('Kitty: legacy format matches, but cannot distinguish manual edits; backing up before replacement.')
            backup(palette, before)
        colour_file.write(after)
    if proposed != config:
        # A failed config write leaves a harmless generated file for a later retry.
        # Never delete or roll back a path another process might now be using.
        config_file.write(proposed)
    print(f'Kitty integration: {root}')
    if proposed != config or after != before:
        reload_windows(root.parent)


def main():
    action, *args = sys.argv[1:]
    dry = '--dry-run' in args
    if 'SEKAIPOP_KITTY_CONFIG_DIRECTORY' in os.environ:
        original_dir = os.environ.pop('SEKAIPOP_KITTY_CONFIG_DIRECTORY')
        if original_dir:
            os.environ['KITTY_CONFIG_DIRECTORY'] = original_dir
        else:
            os.environ.pop('KITTY_CONFIG_DIRECTORY', None)
    directory = config_directory(os.environ)
    # Use the chosen directory for Kitty's option parser without asking its launcher to create it.
    if hasattr(sys, 'kitty_run_data'):
        sys.kitty_run_data['config_dir'] = str(directory)
    root = directory / 'kitty.conf'
    if action not in ('check', 'status') and directory.exists() and directory.stat().st_uid != os.getuid():
        raise Conflict(f'{directory}: Kitty config directory is not owned by this user')
    if dry or action in ('check', 'status') or (action in ('apply', 'sync', 'revert') and not directory.exists()):
        change(action, root, args, dry)
        return
    directory.mkdir(parents=True, exist_ok=True)
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        change(action, root, args, dry)
    finally:
        os.close(fd)


if __name__ == '__main__':
    try:
        main()
    except (Conflict, OSError, ImportError, TypeError, subprocess.TimeoutExpired) as exc:
        print(f'Kitty: {error_message(exc)}', file=sys.stderr)
        if sys.argv[1] == 'status':
            print('conflict')
            sys.exit(0)
        sys.exit(1)
