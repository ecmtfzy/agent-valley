#!/usr/bin/env python3
"""Compile the actual Codex usage reader, SQLite ledger, and original regression methods.

Only XCTest, observation, and unrelated Claude transcript/path helpers are stubbed;
usage conversion, discovery, incremental checkpoints, SQLite and pricing are real.
No app, auth file, daemon or user's history database is opened.
"""
import importlib.util
from pathlib import Path
import platform
import re
import subprocess
import sys

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/codex-prototype/usage-smoke"

STUBS = r'''
import Foundation
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
enum AnswerServer { static var defaultDirectory: URL { URL(fileURLWithPath: "/unused") } }
enum CodexEventStore {
    static func configuredJournal(environment: [String: String], home: URL) -> URL? { nil }
}
struct GitPlace { let checkout: String }
enum AgentStore {
    enum Kind { case main, sub }
    static func classify(_ path: String, root: String) -> Kind? { nil }
    static func gitPlace(of folder: String) -> GitPlace? { nil }
}
enum TranscriptReader {
    static func clipped(_ text: String, limit: Int = 120) -> String { String(text.prefix(limit)) }
    static func date(from text: String) -> Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
    }
    static func readLines(from handle: FileHandle, piece: Int, _ body: (Data) throws -> Void) rethrows -> UInt64 {
        guard let data = try? handle.readToEnd() else { return 0 }
        var offset = 0
        for part in data.split(separator: 10, omittingEmptySubsequences: false).dropLast() {
            try body(Data(part)); offset += part.count + 1
        }
        return UInt64(offset)
    }
}
'''


def main():
    spec = importlib.util.spec_from_file_location("runtime_smoke", ROOT / "testing/codex-runtime-smoke.py")
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    assertions = runtime.ASSERTIONS.replace("class XCTestCase {}", """class XCTestCase {
        var teardowns: [() throws -> Void] = []
        func addTeardownBlock(_ work: @escaping () throws -> Void) { teardowns.append(work) }
        func tearDown() { for work in teardowns.reversed() { try? work() } }
    }""")
    assertions = assertions.replace("func XCTUnwrap<T>(_ value: @autoclosure () -> T?", "func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?")
    assertions = assertions.replace("guard let result = value() else", "guard let result = try value() else")
    assertions = assertions.replace("func XCTAssertNil<T>(_ actual: @autoclosure () -> T?", "func XCTAssertNil<T>(_ actual: @autoclosure () throws -> T?")
    assertions = assertions.replace('if actual() != nil { fail("Expected nil. \\(message())", file: file, line: line) }',
                                    'do { if try actual() != nil { fail("Expected nil. \\(message())", file: file, line: line) } } catch { fail("Thrown: \\(error)", file: file, line: line) }')
    assertions += '''
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() == nil { fail("Unexpected nil", file: file, line: line) } }
    catch { fail("Thrown: \\(error)", file: file, line: line) }
}
'''
    tests = (ROOT / "Tests/AgentValleyTests/CodexUsageTests.swift").read_text()
    methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", tests)
    tests = tests.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Stubs.swift").write_text(STUBS)
    (OUT / "Assertions.swift").write_text(assertions)
    (OUT / "Tests.swift").write_text(tests)
    entries = [f'("{name}", {{ let t = CodexUsageTests(); defer {{ t.tearDown() }}; {"try " if throws else ""}t.{name}() }})'
               for name, throws in methods]
    (OUT / "main.swift").write_text('''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ",\n".join(entries) + ''']
var failed = 0
for (name, work) in tests {
    let before = assertionFailures.count
    do { try work() } catch { fail("Thrown: \\(error)", file: #filePath, line: #line) }
    if before == assertionFailures.count { print("PASS \\(name)") } else { failed += 1 }
}
print("Codex usage: \\(tests.count - failed)/\\(tests.count) passed")
if failed == 0, CommandLine.arguments.count == 3 {
    let source = CodexUsageReader.Source(id: CommandLine.arguments[2], path: CommandLine.arguments[1])
    let reader = CodexUsageReader(home: URL(fileURLWithPath: "/unused"), journal: URL(fileURLWithPath: "/unused"))
    var state = CodexUsageReader.State(), answers: [LedgerAnswer] = []
    for _ in 0..<256 {
        let next = reader.read(source, state: state)
        answers += next.answers
        if next.state.offset == state.offset { break }
        state = next.state
    }
    let report: [String: Any] = ["session": source.id, "responses": answers.count,
        "input": answers.reduce(0) { $0 + $1.input }, "cached": answers.reduce(0) { $0 + $1.read },
        "cache_write": answers.reduce(0) { $0 + $1.write5m }, "output": answers.reduce(0) { $0 + $1.output },
        "models": Array(Set(answers.map(\\.model))).sorted(), "unpriced": answers.allSatisfy { Pricing.cost(of: $0) == nil }]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print("SAMPLE " + text) }
}
exit(failed == 0 ? 0 : 1)
''')
    sources = ["CodexUsageReader", "Ledger", "LedgerAnswer", "Usage", "SQLite", "SafeJSON", "Pricing"]
    compiler, sdk, environment = swift_toolchain()
    binary = OUT / "usage-smoke"
    command = [compiler, "-sdk", sdk,
               "-target", f"{platform.machine()}-apple-macosx15.0", "-module-cache-path", str(OUT / "module-cache")]
    command += [str(ROOT / "Sources/AgentValley" / (name + ".swift")) for name in sources]
    command += [str(OUT / name) for name in ["Stubs.swift", "Assertions.swift", "Tests.swift", "main.swift"]]
    command += ["-o", str(binary)]
    subprocess.run(command, cwd=ROOT, env=environment, check=True)
    return subprocess.run([str(binary), *sys.argv[1:]], cwd=ROOT, env=environment).returncode


if __name__ == "__main__":
    sys.exit(main())
