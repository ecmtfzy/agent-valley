#!/usr/bin/env python3
"""Run real production Claude recovery/transport with local fixtures, never accounts."""
from pathlib import Path
import platform
import re
import runpy
import subprocess
import sys

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/codex-prototype/claude-usage-smoke'
SOURCES = [ROOT / 'Sources/AgentValley/ClaudeUsageSource.swift',
           ROOT / 'Sources/AgentValley/SafeJSON.swift']
MODEL = ROOT / 'Sources/AgentValley/PlanLimits.swift'
TESTS = ROOT / 'Tests/AgentValleyTests/ClaudeUsageSourceTests.swift'


def main():
    original = {path: path.read_bytes() for path in SOURCES + [MODEL, TESTS]}
    # Use the actual model, parser, protocol and primary source, omitting only the
    # unrelated Combine UI client below this boundary. No production logic is copied.
    model = original[MODEL].decode().split('final class PlanLimitsClient:')[0]
    assertions = runpy.run_path(str(ROOT / 'testing/codex-runtime-smoke.py'))['ASSERTIONS']
    tests = original[TESTS].decode().replace('import XCTest\n', '').replace('@testable import AgentValley\n', '')
    methods = re.findall(r'\bfunc (test\w+)\(\)(\s+throws)?\s*\{', tests)
    assert len(methods) >= 12, 'Expected recovery, cancellation and transport regressions'
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'Model.swift').write_text(model)
    (OUT / 'Assertions.swift').write_text(assertions)
    (OUT / TESTS.name).write_text(tests)
    entries = [f'("{name}", {{ {"try " if throws else ""}ClaudeUsageSourceTests().{name}() }})'
               for name, throws in methods]
    (OUT / 'main.swift').write_text('''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ',\n'.join(entries) + ''']
var failed = 0
for (name, run) in tests {
    let before = assertionFailures.count
    do { try run() } catch { fail("Thrown: \\(error)", file: #filePath, line: #line) }
    if assertionFailures.count == before { print("PASS \\(name)") } else { failed += 1 }
}
print("Claude usage: \\(tests.count - failed)/\\(tests.count) tests passed")
exit(failed == 0 ? 0 : 1)
''')
    compiler, sdk, environment = swift_toolchain()
    binary = OUT / 'claude-usage-smoke'
    command = [compiler, '-sdk', sdk, '-target', f'{platform.machine()}-apple-macosx15.0',
               '-module-cache-path', str(OUT / 'module-cache'), *map(str, SOURCES),
               str(OUT / 'Model.swift'), str(OUT / 'Assertions.swift'), str(OUT / TESTS.name),
               str(OUT / 'main.swift'), '-o', str(binary)]
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    for path, before in original.items():
        assert path.read_bytes() == before, f'{path.name} changed while compiling; rerun'
    return subprocess.run([str(binary)], cwd=ROOT, env=environment, timeout=45).returncode


if __name__ == '__main__':
    sys.exit(main())
