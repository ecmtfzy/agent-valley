#!/usr/bin/env python3
"""Run the real live-rollout reader and original tests against temporary fixtures only.

Compiles CodexEvents, CodexLiveRollouts, CodexLiveSessions, CodexUsageReader and SafeJSON. Only UI model types,
the ledger answer carrier, formatting, and XCTest assertions are local stand-ins.
No real session, daemon, user configuration, Git directory or account is read.
"""
from pathlib import Path
import re
import runpy
import subprocess
import sys

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/codex-prototype/live-smoke"
TEST_CLASSES = ("CodexLiveRolloutsTests", "CodexLiveSessionsTests", "CodexStateSyncTests")

STUBS = r'''
import Foundation
enum AgentStatus: Equatable { case working, quiet, needsYou, done }
struct OpenTool: Equatable { let id: String; let tool: String; let input: NSDictionary }
struct AgentInfo: Equatable {
    var type = "agent", title = "", model = "", cwd = "", folder = "", entrypoint = "", branch = ""
    var startedAt: Date?, lastActivity: Date?, turnStartedAt: Date?
    var codexTurnID: String?
    var codexCompletedTurns: [CodexTurnCompletion] = []
    var steps = 0, lastStep = "", lastStepAsRun = "", turnEnded = false, asking = false
    var openTools: [OpenTool] = []
}
struct AgentRow: Equatable {
    let id: String; let info: AgentInfo; let status: AgentStatus; let elapsed: TimeInterval
    var quietFor: TimeInterval = 0, calledBusy = false
    var step: String { info.lastStep }
}
struct SessionCard: Equatable {
    let id: String, project: String, branch: String
    var main: AgentRow?; var agents: [AgentRow]; let startedAt: Date
    var title = "", repo = ""
    var closed = false
    var name: String { title.isEmpty ? project : title }
    var rows: [AgentRow] { [main].compactMap { $0 } + agents }
    var isIdle: Bool { !rows.isEmpty && rows.allSatisfy { $0.status == .done } }
    var asShown: SessionCard {
        var card = self
        let busy = rows.filter { $0.status == .working }
        if !busy.isEmpty && busy.allSatisfy({ $0.quietFor >= AgentStore.stuckAfter }) {
            func quiet(_ row: AgentRow) -> AgentRow {
                row.status == .working ? AgentRow(id: row.id, info: row.info, status: .quiet, elapsed: row.elapsed,
                                                  quietFor: row.quietFor, calledBusy: true) : row
            }
            card.main = main.map(quiet)
            card.agents = agents.map(quiet)
        }
        return card
    }
}
enum AgentStore {
    static let defaultVisibleFor: TimeInterval = 600
    static let stuckAfter: TimeInterval = 600
    static let forgetAfter: TimeInterval = 86400
    static let askingVisibleFor: TimeInterval = 3600
}
enum Projects { static func name(of path: String, home: String) -> String { (path as NSString).lastPathComponent } }
enum Format { static func model(_ value: String) -> String { value } }
enum TranscriptReader {
    static let openToolLimit = 16
    static func clipped(_ value: String, limit: Int = 120) -> String { String(value.prefix(limit)) }
    static func date(from value: String) -> Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
    }
    static func stepLabel(tool: String, input: [String: Any], asRun: Bool = false) -> String {
        tool + ((input["command"] as? String).map { " " + $0 } ?? "")
    }
}
struct LedgerAnswer {
    init(id: String, at: Date, folder: String, session: String, agent: String, model: String,
         input: Int, write5m: Int, read: Int, output: Int) {}
}
'''


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    assertions = runpy.run_path(str(ROOT / "testing/codex-runtime-smoke.py"))["ASSERTIONS"]
    assertions = assertions.replace("class XCTestCase {}", """class XCTestCase {
        var teardowns: [() throws -> Void] = []
        func addTeardownBlock(_ work: @escaping () throws -> Void) { teardowns.append(work) }
        func tearDown() { for work in teardowns.reversed() { try? work() } }
    }""")
    tests = ""
    entries = []
    for name in TEST_CLASSES:
        source = (ROOT / "Tests/AgentValleyTests" / (name + ".swift")).read_text()
        methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", source)
        assert methods, "Expected regression tests in " + name
        tests += source.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
        entries += [f'("{method}", {{ let t = {name}(); defer {{ t.tearDown() }}; {"try " if throws else ""}t.{method}() }})'
                    for method, throws in methods]
    (OUT / "Stubs.swift").write_text(STUBS)
    (OUT / "Assertions.swift").write_text(assertions)
    (OUT / "Tests.swift").write_text(tests)
    (OUT / "main.swift").write_text('''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ",\n".join(entries) + ''']
var failed = 0
for (name, run) in tests {
    let before = assertionFailures.count
    do { try run() } catch { fail("Thrown: \\(error)", file: #filePath, line: #line) }
    if before == assertionFailures.count { print("PASS \\(name)") } else { failed += 1 }
}
print("Codex live rollouts: \\(tests.count - failed)/\\(tests.count) passed")
exit(failed == 0 ? 0 : 1)
''')
    compiler, sdk, environment = swift_toolchain()
    binary = OUT / "live-smoke"
    sources = [ROOT / "Sources/AgentValley" / (name + ".swift")
               for name in ("CodexTurnCompletion", "CodexEvents", "CodexLiveRollouts", "CodexLiveSessions", "CodexUsageReader", "SafeJSON")]
    command = [compiler, "-sdk", sdk, "-module-cache-path", str(OUT / "module-cache")]
    command += [str(path) for path in sources]
    command += [str(OUT / name) for name in ("Stubs.swift", "Assertions.swift", "Tests.swift", "main.swift")]
    subprocess.run(command + ["-o", str(binary)], cwd=ROOT, env=environment, check=True)
    return subprocess.run([str(binary)], cwd=ROOT, env=environment).returncode


if __name__ == "__main__":
    sys.exit(main())
