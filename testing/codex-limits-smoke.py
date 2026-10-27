#!/usr/bin/env python3
"""Run Codex quota parser, real subprocess transport and client checks with CLT.

Compiles the production CodexPlanLimits, PlanLimits, PlanLimitsScope, SafeJSON and LimitResets
logic. Only XCTest and Combine's observation wrappers are replaced. By default,
subprocesses are temporary local Python fixtures: no account, daemon,
authentication or network is read. Optional --live SCRIPT CODEX uses the same
production source transport against an explicitly selected runtime helper/CLI.
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
OUT = ROOT / "build/codex-prototype/limits-smoke"
SOURCE = ROOT / "Sources/AgentValley/CodexPlanLimits.swift"
CLIENT = ROOT / "Sources/AgentValley/PlanLimits.swift"
CLAUDE_SOURCE = ROOT / "Sources/AgentValley/ClaudeUsageSource.swift"
SCOPE = ROOT / "Sources/AgentValley/PlanLimitsScope.swift"
TESTS = ROOT / "Tests/AgentValleyTests/CodexPlanLimitsTests.swift"
LEGACY_TESTS = [ROOT / "Tests/AgentValleyTests/PlanLimitsTests.swift",
                ROOT / "Tests/AgentValleyTests/PlanLimitsClientTests.swift",
                ROOT / "Tests/AgentValleyTests/PlanLimitsScopeTests.swift"]


def main():
    original = {path: path.read_bytes() for path in [SOURCE, CLIENT, CLAUDE_SOURCE, SCOPE, TESTS] + LEGACY_TESTS}
    header = ROOT / "Sources/AgentValley/HeaderView.swift"
    reset_enum = re.search(r"enum LimitResets: Hashable \{.*?\n\}", header.read_text(), re.S).group(0)
    assertions = runpy.run_path(str(ROOT / "testing/codex-runtime-smoke.py"))["ASSERTIONS"]
    assertions = assertions.replace("class XCTestCase {}", "class XCTestCase { func setUp() {}; func tearDown() {} }")
    assertions = assertions.replace("func XCTUnwrap<T>(_ value: @autoclosure () -> T?",
                                    "func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?")
    assertions = assertions.replace("guard let result = value() else", "guard let result = try value() else")
    assertions = assertions.replace("func XCTAssertNil<T>(_ actual: @autoclosure () -> T?",
                                    "func XCTAssertNil<T>(_ actual: @autoclosure () throws -> T?")
    assertions = assertions.replace('if actual() != nil { fail("Expected nil. \\(message())", file: file, line: line) }',
                                    'do { if try actual() != nil { fail("Expected nil. \\(message())", file: file, line: line) } } catch { fail("Thrown: \\(error)", file: file, line: line) }')
    assertions += r'''
func XCTAssertNotNil<T>(_ actual: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    if actual() == nil { fail("Expected non-nil value", file: file, line: line) }
}
func XCTFail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    fail(message, file: file, line: line)
}
func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double,
                    file: StaticString = #filePath, line: UInt = #line) {
    if !actual.isFinite || abs(actual - expected) > accuracy {
        fail("\(actual) != \(expected) within \(accuracy)", file: file, line: line)
    }
}
'''
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "ObservationStubs.swift").write_text("""
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
""")
    (OUT / "Assertions.swift").write_text(assertions)
    (OUT / "LimitResets.swift").write_text(reset_enum + "\n")
    entries = []
    for test_file in [TESTS] + LEGACY_TESTS:
        tests = original[test_file].decode()
        methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", tests)
        if test_file == TESTS:
            assert len(methods) >= 14, "Expected parser, quota-state and subprocess regressions"
        tests = "import Foundation\n" + tests.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
        (OUT / test_file.name).write_text(tests)
        entries.extend(f'    ("{test_file.stem}.{name}", {{ let test = {test_file.stem}(); test.setUp(); defer {{ test.tearDown() }}; {"try " if throws else ""}test.{name}() }})'
                       for name, throws in methods)
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
print("Codex plan limits: \\(tests.count - failed)/\\(tests.count) tests passed")
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--live" {
    let command = CodexLimitsSource.Command(executable: URL(fileURLWithPath: "/usr/bin/python3"),
        arguments: [CommandLine.arguments[2], "--limits", "--codex", CommandLine.arguments[3], "--timeout", "8"])
    let source = CodexLimitsSource(command: { command })
    var answer: Result<PlanLimits, LimitsFailure>?
    let cancel = source.fetch { answer = $0 }
    let deadline = Date().addingTimeInterval(12)
    while answer == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    cancel()
    switch answer {
    case .success(let limits):
        let five = limits.fiveHour.map { String($0.usedPercent) } ?? "missing"
        let week = limits.week.map { String($0.usedPercent) } ?? "missing"
        let allowed = limits.ordinaryUsageAllowed.map { String($0) } ?? "unknown"
        print("Live Codex limits: provider=\\(limits.provider.rawValue), fiveHour=\\(five), week=\\(week), ordinaryUsageAllowed=\\(allowed)")
    case .failure(let reason): print("FAIL live Codex limits: \\(reason)"); failed += 1
    case nil: print("FAIL live Codex limits: no callback"); failed += 1
    }
}
exit(failed == 0 ? 0 : 1)
''')
    compiler, sdk, environment = swift_toolchain()
    binary = OUT / "limits-smoke"
    command = [compiler, "-sdk", sdk, "-target", f"{platform.machine()}-apple-macosx15.0",
               "-module-cache-path", str(OUT / "module-cache"), str(SOURCE), str(CLIENT), str(CLAUDE_SOURCE), str(SCOPE),
               str(ROOT / "Sources/AgentValley/SafeJSON.swift"), str(OUT / "ObservationStubs.swift"),
               str(OUT / "Assertions.swift"), str(OUT / "LimitResets.swift"),
               *[str(OUT / path.name) for path in [TESTS] + LEGACY_TESTS], str(OUT / "main.swift"),
               "-o", str(binary)]
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    for path, before in original.items():
        assert path.read_bytes() == before, f"{path.name} changed while compiling; rerun"
    assert reset_enum == re.search(r"enum LimitResets: Hashable \{.*?\n\}", header.read_text(), re.S).group(0)
    print("Limits source SHA256:", hashlib.sha256(original[SOURCE]).hexdigest(), flush=True)
    return subprocess.run([str(binary)] + sys.argv[1:], cwd=ROOT, env=environment, timeout=45).returncode


if __name__ == "__main__":
    sys.exit(main())
