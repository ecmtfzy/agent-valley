#!/usr/bin/env python3
"""Prepare/apply only the three reviewed AgentValley hook upgrades."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import tempfile

EVENT_FLAGS = {'PermissionRequest': ('--answers', 600),
               'Stop': ('--messages', 86400),
               'PreToolUse': ('--display-inputs', 2)}
SCRIPT = '/Applications/AgentValley.app/Contents/Resources/codex/bridge.py'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    source = Path.home() / '.codex/hooks.json'
    original = source.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    if args.apply:
        manifest = json.loads((args.backup / 'hook-upgrade-plan.json').read_text())
        if manifest['before_sha256'] != digest:
            raise SystemExit('hooks.json changed since preparation; nothing written')
        replacement = (args.backup / 'codex-hooks-proposed.json').read_bytes()
        if hashlib.sha256(replacement).hexdigest() != manifest['after_sha256']:
            raise SystemExit('Prepared hook file changed; nothing written')
        fd, name = tempfile.mkstemp(prefix='.agentvalley-hooks-', dir=source.parent)
        try:
            with os.fdopen(fd, 'wb') as stream:
                os.fchmod(stream.fileno(), source.stat().st_mode & 0o777)
                stream.write(replacement)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, source)
        finally:
            if os.path.exists(name):
                os.unlink(name)
        print(json.dumps({'updated_events': list(EVENT_FLAGS), 'other_handlers': 'unchanged'}))
        return
    args.backup.mkdir(parents=True, exist_ok=False)
    data = json.loads(original)
    changes = []
    for event, (flag, timeout) in EVENT_FLAGS.items():
        matches = []
        for group in data.get('hooks', {}).get(event, []):
            for handler in group.get('hooks', []):
                if handler.get('type') != 'command':
                    continue
                command = handler.get('command', '')
                words = shlex.split(command)
                if len(words) == 5 and words[:4] == ['/usr/bin/python3', SCRIPT, 'emit', '--events']:
                    matches.append(handler)
        if len(matches) != 1:
            raise SystemExit('Expected exactly one existing AgentValley handler for ' + event)
        handler = matches[0]
        old = dict(handler)
        handler['command'] += ' ' + flag
        handler['timeout'] = timeout
        changes.append({'event': event, 'before': old, 'after': dict(handler)})
    proposed = (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode()
    for name, contents in [('codex-hooks.json', original), ('codex-hooks-proposed.json', proposed)]:
        path = args.backup / name
        path.write_bytes(contents)
        path.chmod(0o600)
    manifest = {'before_sha256': digest, 'after_sha256': hashlib.sha256(proposed).hexdigest(), 'changes': changes}
    (args.backup / 'hook-upgrade-plan.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'prepared': str(args.backup), 'updated_events': list(EVENT_FLAGS), 'other_handlers': 'unchanged'}))


if __name__ == '__main__':
    main()
