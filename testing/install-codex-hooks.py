#!/usr/bin/env python3
"""Install legacy observer-only handlers after checking a prepared config backup.

This does not enable interactive answers/messages or trust any hooks. Prepare
codex-hooks.json in --backup-dir before running; --dry-run performs all preflight
checks without creating files or changing the user's configuration.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import tempfile

HOME_DIR = Path.home()
DEFAULT_BACKUP = Path(__file__).resolve().parents[1] / 'build/codex-prototype/hook-install-backup'
HOOKS = HOME_DIR / '.codex/hooks.json'
SCRIPT = Path('/Applications/AgentValley.app/Contents/Resources/codex/bridge.py')
JOURNAL = HOME_DIR / 'Library/Application Support/AgentValley/codex/events.jsonl'
EVENTS = ('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest',
          'PostToolUse', 'SubagentStart', 'SubagentStop', 'Stop', 'Interrupt',
          'SessionEnd', 'PreCompact', 'PostCompact')


def install(backup, dry_run=False):
    original = HOOKS.read_bytes()
    if original != (backup / 'codex-hooks.json').read_bytes():
        raise SystemExit('hooks.json changed after backup; refusing to overwrite new changes')
    if not SCRIPT.is_file():
        raise SystemExit('The installed app has no Codex bridge')
    reports = (backup / 'agentvalley-added-hooks.json', backup / 'hooks-after-sha256.txt')
    if any(os.path.lexists(path) for path in reports):
        raise SystemExit('Backup audit files already exist; refusing to overwrite them')
    if os.path.lexists(JOURNAL):
        raise SystemExit('The event journal already exists; refusing a second observer installation')
    config = json.loads(original)
    if not isinstance(config, dict):
        raise SystemExit('Invalid existing hook configuration')
    groups = config.setdefault('hooks', {})
    if not isinstance(groups, dict):
        raise SystemExit('Invalid existing hook groups')
    previous_handlers = sum(len(group.get('hooks', []))
                            for entries in groups.values() if isinstance(entries, list)
                            for group in entries if isinstance(group, dict)
                            and isinstance(group.get('hooks', []), list))
    command = shlex.join(['/usr/bin/python3', str(SCRIPT), 'emit', '--events', str(JOURNAL)])
    added = {event: [{'hooks': [{'type': 'command', 'command': command, 'timeout': 2}]}] for event in EVENTS}
    for event, entries in added.items():
        existing = groups.setdefault(event, [])
        if not isinstance(existing, list):
            raise SystemExit('Invalid existing hook groups')
        existing.extend(entries)
    new = (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode()
    report = {'added': len(EVENTS), 'previous_handlers_preserved': previous_handlers,
              'journal': str(JOURNAL), 'backup_dir': str(backup), 'dry_run': dry_run}
    if dry_run:
        print(json.dumps(report))
        return

    JOURNAL.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(JOURNAL, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
    fd, temporary = tempfile.mkstemp(prefix='.agentvalley-hooks-', dir=HOOKS.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            os.fchmod(output.fileno(), HOOKS.stat().st_mode & 0o777)
            output.write(new)
            output.flush()
            os.fsync(output.fileno())
        # Recheck immediately before replacing the config, as the preflight and
        # backup must not authorize overwriting edits made during this run.
        if HOOKS.read_bytes() != original:
            raise SystemExit('hooks.json changed during installation; refusing to overwrite new changes')
        os.replace(temporary, HOOKS)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    for path, content in zip(reports, (json.dumps({'hooks': added}, indent=2) + '\n',
                                       hashlib.sha256(new).hexdigest() + '\n')):
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as output:
            output.write(content)
    print(json.dumps(report))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup-dir', type=Path, default=DEFAULT_BACKUP,
                        help='Directory containing the prepared codex-hooks.json backup (default: %(default)s)')
    parser.add_argument('--dry-run', action='store_true', help='Validate and print the plan without writing any files')
    args = parser.parse_args()
    try:
        install(args.backup_dir.expanduser().resolve(), args.dry_run)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error


if __name__ == '__main__':
    main()
