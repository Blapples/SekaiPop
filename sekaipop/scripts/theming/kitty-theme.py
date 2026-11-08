"""Audit and manage the Kitty include. Run in Kitty's Python via app-theme.sh."""

import fcntl
import os
import re
import signal
import stat
import sys
import tempfile
from fnmatch import fnmatchcase
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


class Conflict(Exception):
    pass


def config_directory(env):
    if env.get('KITTY_CONFIG_DIRECTORY'):
        return Path(os.path.abspath(os.path.expanduser(env['KITTY_CONFIG_DIRECTORY'])))
    home = Path(env.get('HOME', Path.home()))
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


def logical_lines(text):
    # Kitty continues a directive when the next physical line starts with a backslash.
    line, number = '', 0
    for i, part in enumerate(text.replace('\r\n', '\n').replace('\r', '\n').split('\n'), 1):
        part = part.lstrip()
        if part.startswith('\\') and number:
            line += part[1:]
        else:
            if number:
                yield number, line.strip()
            line, number = part, i
    if number:
        yield number, line.strip()


class Audit:
    def __init__(self, root, changes=None):
        from kitty.colors import ThemeColors
        from kitty.conf.utils import currently_parsing, key_pat
        from kitty.options.parse import create_result_dict, parse_conf_item
        from kitty.utils import expandvars, log_error

        self.parse = parse_conf_item
        self.options = create_result_dict()
        self.parsing = currently_parsing
        self.key_pat = key_pat
        self.expandvars = expandvars
        self.errors = []
        self.warnings = []
        self.references = {}
        self.colour_sources = {}
        self.last_colour = {}
        self.position = 0
        self.colour_keys = ThemeColors().get_default_colors().keys() | PALETTE.keys()
        self.opaque = False
        self.changes = changes or {}
        self.seen = set()
        self.env_stack = set()
        log_error.redirect = lambda message: self.errors.append(f'{self.location}: {message}')
        try:
            for path in (SYSTEM_CONF, root):
                self.seen.clear()  # Kitty starts a separate include graph for each config.
                self.scan(path, optional=True)
        finally:
            del log_error.redirect

    def scan(self, path, source=None, optional=False):
        try:
            real = path.resolve()
            if source:
                self.references.setdefault(real, []).append(self.position)
            if real in self.seen:
                self.errors.append(f'{source}: duplicate or recursive reference to {path}')
                return
            self.seen.add(real)
            text = self.changes[path] if path in self.changes else read(path)
            if text is not None:
                self.scan_lines(text, path.parent, str(path))
            elif not optional:
                self.errors.append(f'{source}: missing include {path}')
        except (OSError, Conflict, RuntimeError) as exc:
            self.opaque = True
            self.errors.append(f'{source or path}: {exc}')

    def scan_lines(self, text, base, name):
        for number, line in logical_lines(text):
            if not line or line.startswith('#'):
                continue
            self.position += 1
            where = f'{name}:{number}'
            match = self.key_pat.fullmatch(line)
            if not match:
                self.errors.append(f'{where}: invalid config line {line!r}')
                continue
            key, value = match.groups()
            try:
                if key in ('include', 'globinclude', 'envinclude', 'geninclude'):
                    self.include(key, value, base, where)
                    continue
                self.location = where
                with self.parsing.set_file(name), self.parsing.set_line(line, number):
                    if not self.parse(key, value, self.options):
                        self.errors.append(f'{where}: unknown config key {key}')
                if key in self.colour_keys or re.fullmatch(r'color[0-9]+', key):
                    self.colour_sources.setdefault(name, set()).add(key)
                    self.last_colour[key] = (self.position, name, where)
            except Exception as exc:
                self.errors.append(f'{where}: {key} {value!r}: {exc}')

    def include(self, key, value, base, where):
        value = self.expandvars(os.path.expanduser(value), {'KITTY_OS': 'linux'})
        if key == 'geninclude':
            self.opaque = True
            self.errors.append(f'{where}: geninclude {value} requires manual review (generator was not run)')
        elif key == 'envinclude':
            for name in os.environ:
                if fnmatchcase(name, value):
                    if name in self.env_stack:
                        self.errors.append(f'{where}: recursive envinclude {name}')
                        continue
                    self.env_stack.add(name)
                    self.scan_lines(os.environ[name], base, f'<env var {name}>')
                    self.env_stack.remove(name)
        elif key == 'globinclude':
            paths = set(base.glob(value))
            # Include proposed files in the match without creating them on disk.
            prefix, _, pattern = value.rpartition('/')
            for path, content in self.changes.items():
                if content is not None and fnmatchcase(path.name, pattern) and (
                    path.parent == base if not prefix else path.parent in base.glob(prefix)
                ):
                    paths.add(path)
            if not paths:
                self.warnings.append(f'{where}: globinclude {value} matched no files')
            for path in sorted(paths):
                self.scan(path, where)
        else:
            self.scan(base / value, where)


def find_hook(config, root):
    """Return the exact span of the owned pair, leaving any unfamiliar edits alone."""
    markers = {
        MARK: (PALETTE_NAME, ''),
        MARK + ' (created config)': (PALETTE_NAME, 'created'),
        MARK + ' (added newline)': (PALETTE_NAME, 'newline'),
        **{LEGACY_MARK.format(name): (f'{name}-colors.conf', '') for name in ('sekaipop', OLD_NAME)},
    }
    hits = []
    marker_line = rf'(?:^|(?<=[\r\n]))([ \t]*# (?:sekaipop|{OLD_NAME}): (?:kitty colours|managed block)[^\r\n]*)'
    for match in re.finditer(marker_line + r'(?:\r\n|[\r\n])?', config):
        marker = match[1]
        if marker not in markers:
            raise Conflict(f'{root}: unfamiliar Kitty integration marker {marker!r}; review it manually')
        name, kind = markers[marker]
        include = re.match(r'include ' + re.escape(name) + r'(?:\r\n|[\r\n]|\Z)', config[match.end():])
        if not include:
            raise Conflict(f'{root}: managed marker is missing its original include; review it manually')
        end = match.end() + include.end()
        if re.match(r'[ \t]*\\', config[end:]):
            raise Conflict(f'{root}: managed include has a continuation; review it manually')
        start = match.start()
        if kind == 'newline' and start and end == len(config):
            start -= 2 if config[:start].endswith('\r\n') else 1
        hits.append((start, end, root.parent / name, kind == 'created'))
    if len(hits) > 1:
        raise Conflict(f'{root}: multiple managed Kitty includes; review them manually')
    return hits[0] if hits else None


def owned_palette(path, contents):
    lines = (contents or '').splitlines()
    name = path.name.removesuffix('-colors.conf')
    return bool(lines and lines[0] == HEADER.format(name) and all(
        not line.strip() or line.split(maxsplit=1)[0] in PALETTE for line in lines[1:]
    ))


def writable(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return 0o600
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid():
        raise Conflict(f'{path}: expected a user-owned regular file without links; review it manually')
    return stat.S_IMODE(info.st_mode)


def write(path, before, after):
    mode = writable(path)
    if read(path) != before:
        raise Conflict(f'{path} changed during the operation; retry after reviewing it')
    if after is None:
        if before is not None:
            path.unlink()
        return
    fd, tmp = tempfile.mkstemp(prefix='.sekaipop-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            os.fchmod(f.fileno(), mode)
            f.write(after.encode('utf-8', errors='surrogateescape'))
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def backup(path, contents):
    if contents is None:
        return
    directory = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'sekaipop/kitty-backups'
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=path.name + '-', dir=directory, delete=False) as f:
        f.write(contents.encode('utf-8', errors='surrogateescape'))
        print(f'Kitty backup: {f.name}')


def show(audit, root, palette):
    overlap = set()
    for name, keys in audit.colour_sources.items():
        if name != str(palette):
            label = 'Colour file' if name != str(root) else 'Inline colours'
            print(f'Kitty {label}: {name} ({len(keys)} colour settings)')
            overlap.update(keys & PALETTE.keys())
    if overlap:
        print(f'  {len(overlap)} settings overlap SekaiPop colours. The last definition of each colour takes precedence.')
    for warning in audit.warnings:
        print(f'Kitty warning: {warning}', file=sys.stderr)
    for error in audit.errors:
        print(f'Kitty conflict: {error}', file=sys.stderr)


def inspect(root, palette, changes=None):
    audit = Audit(root, changes)
    from kitty.colors import ThemeFile

    for theme in ThemeFile:
        path = root.parent / theme.value
        if os.path.lexists(path):
            audit.errors.append(f'{path}: Kitty automatic theme overrides kitty.conf; review it before enabling SekaiPop')
            audit.opaque = True
    references = audit.references.get(palette.resolve(), [])
    if references:
        for key, (position, name, where) in audit.last_colour.items():
            if key in PALETTE and name != str(palette) and position > references[0]:
                audit.errors.append(f'{where}: {key} overrides the SekaiPop include')
    return audit


def reload_windows(directory):
    # Limit SIGUSR1 to our user's Kitty GUIs using this default config directory.
    from kitty.cli import parse_args
    from kitty.utils import is_kitty_gui_cmdline

    for proc in Path('/proc').iterdir():
        if not proc.name.isdecimal():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / 'comm').read_bytes().strip() != b'kitty':
                continue
            args = os.fsdecode((proc / 'cmdline').read_bytes()).rstrip('\0').split('\0')
            if not is_kitty_gui_cmdline(*args):
                continue
            options, _ = parse_args(args[1:])
            if options.config or options.override:
                continue
            env = dict(item.split('=', 1) for item in os.fsdecode((proc / 'environ').read_bytes()).split('\0') if '=' in item)
            if config_directory(env).resolve() == directory.resolve():
                os.kill(int(proc.name), signal.SIGUSR1)
        except (OSError, RuntimeError, SystemExit):
            continue


def change(action, root, args, dry):
    original = read(root)
    config = original or ''
    hook = find_hook(config, root)
    palette = hook[2] if hook else root.parent / PALETTE_NAME
    if action == 'status':
        print('on' if hook else 'off')
        return
    if action == 'check':
        audit = inspect(root, palette)
        print(f'Kitty config: {root}' + (' (new)' if original is None else ''))
        show(audit, root, palette)
        if audit.errors:
            raise Conflict('Review the locations above. Fix invalid values or comment out confirmed obsolete theme includes, then retry.')
        return
    if action == 'sync' and not hook:
        return

    if action == 'revert':
        if not hook and not os.path.lexists(palette):
            return
        restored = original
        if hook:
            start, end, _, created = hook
            restored = config[:start] + config[end:]
            if created and not restored:
                restored = None
        audit = Audit(root, {root: restored})
        if hook:
            writable(root)
            if dry:
                print(f'Would remove the SekaiPop include from {root}.')
            else:
                backup(root, original)
                write(root, original, restored)
        try:
            before = read(palette)
            if owned_palette(palette, before):
                if audit.opaque or palette.resolve() in audit.references:
                    print(f'Kitty: kept {palette} because another config may reference it.')
                elif dry:
                    writable(palette)
                    print(f'Would remove the generated palette {palette}.')
                else:
                    write(palette, before, None)
        except (OSError, Conflict) as exc:
            print(f'Kitty: kept {palette}: {exc}', file=sys.stderr)
        if hook and not dry:
            reload_windows(root.parent)
        return

    before = read(palette)
    if before is not None and not owned_palette(palette, before):
        raise Conflict(f'{palette}: existing file has no SekaiPop ownership marker; review it manually')
    after = before if before is not None else HEADER.format(palette.name.removesuffix('-colors.conf')) + '\n'
    if action in ('apply', 'sync'):
        values = dict(arg.split('=', 1) for arg in args if '=' in arg)
        if any(not re.fullmatch(r'#[0-9a-fA-F]{6}', values.get(key, '')) for key in PALETTE.values()):
            raise Conflict('Kitty palette is incomplete or contains invalid colours')
        after = after.splitlines()[0] + '\n' + ''.join(f'{key} {values[name]}\n' for key, name in PALETTE.items())

    proposed = config
    if not hook:
        marker = MARK
        newline = '\r\n' if '\r\n' in config else '\n'
        if original is None:
            marker += ' (created config)'
        elif config and not config.endswith(('\n', '\r')):
            marker += ' (added newline)'
            proposed += newline
        proposed += f'{marker}{newline}include {palette.name}{newline}'
    audit = inspect(root, palette, {root: proposed, palette: after})
    if audit.errors or len(audit.references.get(palette.resolve(), [])) != 1:
        show(audit, root, palette)
        raise Conflict('Kitty colour sync needs an unambiguous, valid include. Review the reported config before retrying.')
    writable(root)
    if after != before:
        writable(palette)
    if dry:
        print(f'Would enable SekaiPop colours in {root}.' if not hook else f'Kitty sync already enabled in {root}.')
        return
    if proposed != config:
        backup(root, original)
    if after != before:
        write(palette, before, after)
    try:
        if proposed != config:
            write(root, original, proposed)
    except (OSError, Conflict):
        if after != before:
            write(palette, after, before)
        raise
    if proposed != config or after != before:
        reload_windows(root.parent)


def main():
    action, *args = sys.argv[1:]
    dry = '--dry-run' in args
    original_dir = os.environ.pop('SEKAIPOP_KITTY_CONFIG_DIRECTORY', '')
    if original_dir:
        os.environ['KITTY_CONFIG_DIRECTORY'] = original_dir
    else:
        os.environ.pop('KITTY_CONFIG_DIRECTORY', None)
    directory = config_directory(os.environ)
    # Use the chosen directory for Kitty's option parser without asking its launcher to create it.
    sys.kitty_run_data['config_dir'] = str(directory)
    root = directory / 'kitty.conf'
    if action not in ('check', 'status') and directory.exists() and directory.stat().st_uid != os.getuid():
        raise Conflict(f'{directory}: Kitty config directory is not owned by this user')
    if dry or action in ('check', 'status') or (not directory.exists() and action in ('sync', 'revert')):
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
    except (Conflict, OSError, ImportError) as exc:
        print(f'Kitty: {exc}', file=sys.stderr)
        sys.exit(1)
