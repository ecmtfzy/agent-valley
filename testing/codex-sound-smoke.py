#!/usr/bin/env python3
"""Run the production Codex completion-sound decisions against temporary fixtures.

Compiles the pure Sound enum extracted from Sound.swift, CodexTurnCompletion, and
the original SoundCodexTests. UI models and XCTest assertions use the existing
smoke stand-ins. SoundCodexPlayerTests runs in the full XCTest suite instead.
No real audio, session, account, daemon, or user preference is accessed.
"""
from pathlib import Path
import re
import runpy
import subprocess
import sys

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/codex-prototype/sound-smoke"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    stubs = runpy.run_path(str(ROOT / "testing/codex-live-smoke.py"))["STUBS"] + r'''
struct BackgroundJob { let startedAt: Date }
enum BackgroundJobs {
    static let longAfter: TimeInterval = 1800
    static func resting(_ jobs: [BackgroundJob], now: Date) -> Bool { jobs.isEmpty }
}
extension SessionCard {
    var jobs: [BackgroundJob] { [] }
    var movedAt: Date? { rows.compactMap(\.info.lastActivity).max() }
}
'''
    sound = (ROOT / "Sources/AgentValley/Sound.swift").read_text()
    assert sound.count("enum BarkKind:") == 1, "Expected the pure Sound enum before SoundPlayer"
    sound = sound.split("enum BarkKind:", 1)[0].replace("import AppKit", "import Foundation")
    tests = (ROOT / "Tests/AgentValleyTests/SoundCodexTests.swift").read_text()
    assert tests.count("final class SoundCodexPlayerTests:") == 1, "Expected separate player integration tests"
    tests = tests.split("final class SoundCodexPlayerTests:", 1)[0]
    tests = tests.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
    methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", tests)
    assert methods, "Expected original Codex sound regression tests"
    assertions = runpy.run_path(str(ROOT / "testing/codex-runtime-smoke.py"))["ASSERTIONS"]
    entries = [f'("{name}", {{ {"try " if throws else ""}SoundCodexTests().{name}() }})'
               for name, throws in methods]
    runner = '''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ",\n".join(entries) + ''']
var failed = 0
for (name, run) in tests {
    let before = assertionFailures.count
    do { try run() } catch { fail("Thrown: \\(error)", file: #filePath, line: #line) }
    if before == assertionFailures.count { print("PASS \\(name)") } else { failed += 1 }
}
print("Codex sound decisions: \\(tests.count - failed)/\\(tests.count) passed")
exit(failed == 0 ? 0 : 1)
'''
    files = {"Stubs.swift": stubs, "Sound.swift": sound, "Tests.swift": tests,
             "Assertions.swift": assertions, "main.swift": runner}
    for name, content in files.items():
        (OUT / name).write_text(content)
    compiler, sdk, environment = swift_toolchain()
    binary = OUT / "sound-smoke"
    command = [compiler, "-sdk", sdk, "-module-cache-path", str(OUT / "module-cache"),
               str(ROOT / "Sources/AgentValley/CodexTurnCompletion.swift")]
    command += [str(OUT / name) for name in files]
    subprocess.run(command + ["-o", str(binary)], cwd=ROOT, env=environment, check=True)
    return subprocess.run([str(binary)], cwd=ROOT, env=environment).returncode


if __name__ == "__main__":
    sys.exit(main())
