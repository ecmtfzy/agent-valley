#!/usr/bin/env python3
"""Run the actual metadata cache's regression methods without XCTest or GUI.

The reader and scheduler are injected by the original tests. UI model types,
formatting helpers and XCTest assertions have small local stand-ins; the cache,
bounded runtime transport and SafeJSON are compiled from production source.
"""
import hashlib
from pathlib import Path
import platform
import re
import runpy
import subprocess
import sys

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/codex-prototype/metadata-smoke"
SOURCE = ROOT / "Sources/AgentValley/CodexSessionMetadata.swift"
RUNTIME = ROOT / "Sources/AgentValley/CodexRuntimeStatus.swift"
TESTS = ROOT / "Tests/AgentValleyTests/CodexSessionMetadataTests.swift"

MODELS = r'''
import Foundation
enum AgentStatus: Equatable { case working, quiet, needsYou, done }
struct OpenTool: Equatable {
    let id: String
    let tool: String
    let input: NSDictionary
}
struct AgentInfo: Equatable {
    var type = "agent"
    var task = ""
    var title = ""
    var model = ""
    var cwd = ""
    var folder = ""
    var turnStartedAt: Date?
    var lastStep = ""
    var lastStepAsRun = ""
    var asking = false
    var openTools: [OpenTool] = []
}
struct AgentRow: Equatable {
    let id: String
    let info: AgentInfo
    let status: AgentStatus
    let elapsed: TimeInterval
    var quietFor: TimeInterval = 0
    var calledBusy = false
}
struct GitPlace: Equatable { let worktree: String; let checkout: String }
struct OwnerApp: Equatable { let bundle: URL; let name: String; var link: URL? = nil }
struct SessionCard: Equatable {
    let id: String
    let project: String
    let branch: String
    var main: AgentRow?
    var agents: [AgentRow]
    let startedAt: Date
    var title = ""
    var owner: OwnerApp?
    var worktree = false
    var look: String?
    var repo = ""
    var git: GitPlace?
    var jobs: [String] = []
    var onlyForJobs = false
    var closed = false
}
enum AgentStore {
    static func gitPlace(of: String) -> GitPlace? { fatalError("Metadata presentation must not read project files") }
    static func isWorktree(_ folder: String) -> Bool { fatalError("Metadata presentation must not read project files") }
}
enum Projects { static func name(of path: String, home: String) -> String { (path as NSString).lastPathComponent } }
enum Format { static func model(_ name: String) -> String { name } }
enum TranscriptReader {
    static let stepDetailLimit = 120
    static func clipped(_ text: String, limit: Int = stepDetailLimit) -> String { String(text.prefix(limit)) }
}
'''


def main():
    files = [SOURCE, RUNTIME, TESTS]
    original = {path: path.read_bytes() for path in files}
    tests = original[TESTS].decode()
    methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", tests)
    assert len(methods) >= 6, "Expected at least six metadata regression methods"
    tests = tests.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
    assertions = runpy.run_path(str(ROOT / "testing/codex-runtime-smoke.py"))["ASSERTIONS"] + r'''
func XCTAssertNotNil<T>(_ actual: @autoclosure () -> T?,
                       file: StaticString = #filePath, line: UInt = #line) {
    if actual() == nil { fail("Expected non-nil value", file: file, line: line) }
}
'''
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "ModelStubs.swift").write_text(MODELS)
    (OUT / "Assertions.swift").write_text(assertions)
    (OUT / TESTS.name).write_text(tests)
    entries = [f'    ("{name}", {{ {"try " if throws else ""}CodexSessionMetadataTests().{name}() }})'
               for name, throws in methods]
    (OUT / "main.swift").write_text('''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ",\n".join(entries) + '''
]
var failed = 0
for (name, run) in tests {
    let before = assertionFailures.count
    do { try run() } catch { fail("Thrown error: \\(error)", file: #filePath, line: #line) }
    if before == assertionFailures.count { print("PASS \\(name)") } else { failed += 1 }
}
print("Metadata: \\(tests.count - failed)/\\(tests.count) tests passed")
exit(failed == 0 ? 0 : 1)
''')
    compiler, sdk, environment = swift_toolchain()
    binary = OUT / "metadata-smoke"
    command = [compiler, "-sdk", sdk, "-target", f"{platform.machine()}-apple-macosx15.0",
               "-module-cache-path", str(OUT / "module-cache"), str(SOURCE), str(RUNTIME),
               str(ROOT / "Sources/AgentValley/SafeJSON.swift"), str(OUT / "ModelStubs.swift"),
               str(OUT / "Assertions.swift"), str(OUT / TESTS.name), str(OUT / "main.swift"),
               "-o", str(binary)]
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    for path, before in original.items():
        assert path.read_bytes() == before, f"{path.name} changed while compiling; rerun"
    print("Metadata source SHA256:", hashlib.sha256(original[SOURCE]).hexdigest(), flush=True)
    return subprocess.run([str(binary)], cwd=ROOT, env=environment).returncode


if __name__ == "__main__":
    sys.exit(main())
