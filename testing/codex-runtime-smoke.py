#!/usr/bin/env python3
"""Run the runtime-status regression methods with CLT Swift, without XCTest/Xcode.

Compiles the actual production reducer and SafeJSON source. Only the app's model
types and XCTest's assertion/reporting surface are replaced by small local stubs.
The test methods themselves are copied verbatim from CodexRuntimeStatusTests.swift.
No process reader is exercised: every test injects a deterministic fake reader.
"""

import hashlib
from pathlib import Path
import platform
import re
import subprocess
import sys

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "codex-prototype" / "runtime-smoke"
SOURCE = ROOT / "Sources" / "AgentValley" / "CodexRuntimeStatus.swift"
TESTS = ROOT / "Tests" / "AgentValleyTests" / "CodexRuntimeStatusTests.swift"

MODELS = r'''
import Foundation

enum AgentStatus: Equatable { case working, quiet, needsYou, done }
struct OpenTool: Equatable {
    let id: String
    let tool: String
    let input: NSDictionary
}
struct AgentInfo: Equatable {
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
    var step: String {
        status == .needsYou && !info.asking && !info.lastStepAsRun.isEmpty
            ? info.lastStepAsRun : info.lastStep
    }
}
struct SessionCard: Equatable {
    let id: String
    let project: String
    let branch: String
    var main: AgentRow?
    var agents: [AgentRow]
    let startedAt: Date
    var closed = false
}
'''

ASSERTIONS = r'''
import Foundation

class XCTestCase {}
var assertionFailures: [String] = []
enum HarnessError: Error { case unwrap }
func fail(_ text: String, file: StaticString, line: UInt) {
    let message = "\(file):\(line): \(text)"
    assertionFailures.append(message)
    print("FAIL \(message)")
}
func XCTAssertEqual<T: Equatable>(_ actual: @autoclosure () -> T,
                                  _ expected: @autoclosure () -> T,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
    let a = actual(), e = expected()
    if a != e { fail("\(a) != \(e). \(message())", file: file, line: line) }
}
func XCTAssertTrue(_ actual: @autoclosure () -> Bool,
                   _ message: @autoclosure () -> String = "",
                   file: StaticString = #filePath, line: UInt = #line) {
    if !actual() { fail("Expected true. \(message())", file: file, line: line) }
}
func XCTAssertFalse(_ actual: @autoclosure () -> Bool,
                    _ message: @autoclosure () -> String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    if actual() { fail("Expected false. \(message())", file: file, line: line) }
}
func XCTAssertNil<T>(_ actual: @autoclosure () -> T?,
                     _ message: @autoclosure () -> String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    if actual() != nil { fail("Expected nil. \(message())", file: file, line: line) }
}
func XCTUnwrap<T>(_ value: @autoclosure () -> T?,
                  _ message: @autoclosure () -> String = "",
                  file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let result = value() else {
        fail("Unexpected nil. \(message())", file: file, line: line)
        throw HarnessError.unwrap
    }
    return result
}
'''


def main():
    source_before = SOURCE.read_bytes()
    tests_before = TESTS.read_bytes()
    tests = tests_before.decode("utf-8")
    methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", tests)
    if len(methods) < 5:
        raise RuntimeError("Expected at least five runtime-status regressions")
    tests = tests.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "ModelStubs.swift").write_text(MODELS)
    (OUT / "Assertions.swift").write_text(ASSERTIONS)
    (OUT / "CodexRuntimeStatusTests.swift").write_text(tests)
    entries = [f'    ("{name}", {{ {"try " if throws else ""}CodexRuntimeStatusTests().{name}() }})'
               for name, throws in methods]
    driver = '''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ",\n".join(entries) + '''
]
var failedTests = 0
for (name, run) in tests {
    let before = assertionFailures.count
    do { try run() } catch { fail("Thrown error: \\(error)", file: #filePath, line: #line) }
    if assertionFailures.count == before { print("PASS \\(name)") }
    else { failedTests += 1 }
}
print("Runtime status: \\(tests.count - failedTests)/\\(tests.count) tests passed")
exit(failedTests == 0 ? 0 : 1)
'''
    (OUT / "main.swift").write_text(driver)
    compiler, sdk, env = swift_toolchain()
    binary = OUT / "runtime-status-smoke"
    command = [str(compiler), "-sdk", str(sdk), "-target", f"{platform.machine()}-apple-macosx15.0",
               "-module-cache-path", str(OUT / "module-cache"),
               str(SOURCE), str(ROOT / "Sources" / "AgentValley" / "SafeJSON.swift"),
               str(OUT / "ModelStubs.swift"), str(OUT / "Assertions.swift"),
               str(OUT / "CodexRuntimeStatusTests.swift"), str(OUT / "main.swift"), "-o", str(binary)]
    subprocess.run(command, cwd=ROOT, env=env, check=True)
    if SOURCE.read_bytes() != source_before or TESTS.read_bytes() != tests_before:
        raise RuntimeError("Production source or tests changed during compilation; rerun when stable")
    print("Production source SHA256:", hashlib.sha256(source_before).hexdigest(), flush=True)
    print("Regression tests SHA256:", hashlib.sha256(tests_before).hexdigest(), flush=True)
    return subprocess.run([str(binary)], cwd=ROOT, env=env).returncode


if __name__ == "__main__":
    sys.exit(main())
