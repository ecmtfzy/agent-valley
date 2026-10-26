#!/usr/bin/env python3
"""Exercise the actual message sender/Stop desk without XCTest, GUI or live agents.

Uses the original regression methods, production sender/desk/protocol sources and
small model stubs for terminal UI types. A final private fake-socket check passes
the real Swift StopDesk reply through the actual Python Codex bridge.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

from codex_test_toolchain import swift_toolchain

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/codex-prototype/message-smoke"
SOURCES = [ROOT / "Sources/AgentValley" / name for name in (
    "SessionSender.swift", "StopDesk.swift", "PhoneText.swift", "SendRoute.swift",
    "TabGuard.swift", "AwayMode.swift", "AnswerProtocol.swift", "SafeJSON.swift", "SendLog.swift")]
TESTS = [ROOT / "Tests/AgentValleyTests" / name for name in ("SessionSenderTests.swift", "StopDeskTests.swift")]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


MODELS = r'''
import Foundation

struct TabPlace: Equatable {
    enum Terminal: Equatable { case terminal, iterm, ghostty }
    let terminal: Terminal
    let key: String
    static func terminal(bundleID: String?) -> Terminal? {
        switch bundleID {
        case "com.apple.Terminal": return .terminal
        case "com.googlecode.iterm2": return .iterm
        case "com.mitchellh.ghostty": return .ghostty
        default: return nil
        }
    }
}
enum OwnerApp {
    static let supersetBundle = "com.superset.desktop"
    static let supersetWorkspace = "SUPERSET_WORKSPACE_ID"
    static func isID(_ text: String) -> Bool {
        UUID(uuidString: text)?.uuidString.lowercased() == text.lowercased()
    }
}
enum TypingResult: Equatable {
    case typed, stoppedBeforeText, stoppedBeforeEnter, tabNotFound, ambiguous, notAllowed, timedOut
    case failed(String)
}
enum AgentStore {
    static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
enum KeyCommand: Equatable { case allow, deny, option(Int) }
enum TranscriptReader { static let planReady = "Plan ready" }
'''

CODEX_TESTS = r'''
import Foundation

var codexWireReply: Data?
final class CodexMessagePathTests: XCTestCase {
    let session = "codex-00000000-0000-4000-8000-000000000001"
    var statuses: [UUID: [SendStatus]] = [:]
    var reachedSessions: [String] = []
    var route: SendRoute? = .stopHook
    var terminalCalls = 0
    var awayCalls = 0
    var sender: SessionSender!
    let desk = StopDesk()

    override func setUp() {
        desk.holds = { [unowned self] in $0 == session }
        sender = SessionSender(
            reach: { [unowned self] id in
                reachedSessions.append(id)
                return route.map { SessionReach(process: nil, route: $0, waitingOnPerson: true) }
            },
            asking: { _ in true },
            holdsTab: { [unowned self] _, _ in terminalCalls += 1; return false },
            type: { [unowned self] _, _, _ in terminalCalls += 1; return .failed("must not type") },
            superset: { [unowned self] _, _, _, _ in terminalCalls += 1; return .failed("must not send") },
            desk: desk, away: { [unowned self] _ in awayCalls += 1 },
            worker: DispatchQueue(label: "codex-message-test"),
            onStatus: { [unowned self] id, namedSession, status in
                XCTAssertEqual(namedSession, session)
                statuses[id, default: []].append(status)
            })
    }

    func message(_ text: String, id: UUID = UUID()) -> PhoneMessage {
        PhoneMessage(id: id, session: session, text: text)
    }

    func stop(_ namedSession: String? = nil) throws -> StopWait {
        let input = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop", "transcript_path": (namedSession ?? session) + ".jsonl"])
        return try XCTUnwrap(StopWait(hookInput: input))
    }

    func testNamespacedDaemonMessageUsesItsOwnStopAndNeverTypes() throws {
        desk.awayOn = true
        let sent = message("  Continue this task\r\nwith the next step.  ")
        sender.send(sent)
        XCTAssertEqual(statuses[sent.id], [.received, .waitingForTurnEnd])
        var wrongReplies: [Data?] = []
        desk.arrived(try stop("claude-unrelated")) { wrongReplies.append($0); return true }
        XCTAssertEqual(wrongReplies, [nil])
        XCTAssertEqual(statuses[sent.id]?.last, .waitingForTurnEnd)
        desk.arrived(try stop()) { codexWireReply = $0; return true }
        XCTAssertEqual(statuses[sent.id]?.last, .sent)
        let object = try XCTUnwrap(codexWireReply.flatMap(SafeJSON.object))
        XCTAssertEqual(Set(object.keys), Set(["decision", "reason"]))
        XCTAssertEqual(object["decision"] as? String, "block")
        XCTAssertEqual(object["reason"] as? String, "Continue this task\nwith the next step.")
        XCTAssertEqual(reachedSessions, [session])
        XCTAssertEqual(awayCalls, 1)
        XCTAssertEqual(terminalCalls, 0)
    }

    func testNoAwayDoesNotHoldOrDeliverAndReleasePreservesUnsentWords() throws {
        let queued = message("A message that stays unsent")
        sender.send(queued)
        var replies: [Data?] = []
        desk.arrived(try stop()) { replies.append($0); return true }
        XCTAssertEqual(replies, [nil])
        XCTAssertEqual(statuses[queued.id]?.last, .waitingForTurnEnd)
        desk.release()
        XCTAssertEqual(statuses[queued.id]?.last, .notSent(.backAtDesk))
        XCTAssertEqual(desk.leftOver.map(\.text), [queued.text])
        XCTAssertEqual(terminalCalls, 0)
    }

    func testDuplicateIDAndFailedHookDoNotDuplicateOrLoseCodexMessage() throws {
        desk.awayOn = true
        let queued = message("Send exactly once")
        sender.send(queued)
        sender.send(queued)
        var replies: [Data?] = []
        desk.arrived(try stop()) { replies.append($0); return false }
        XCTAssertEqual(statuses[queued.id]?.last, .waitingForTurnEnd)
        desk.arrived(try stop()) { replies.append($0); return true }
        XCTAssertEqual(statuses[queued.id]?.last, .sent)
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies.first!, replies.last!)
        sender.send(queued)
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(terminalCalls, 0)
    }

    func testGoneCodexSessionIsRejectedBeforeQueueing() {
        route = nil
        let gone = message("Do not send")
        sender.send(gone)
        XCTAssertEqual(statuses[gone.id], [.received, .notSent(.sessionGone)])
        XCTAssertEqual(awayCalls, 0)
        XCTAssertEqual(terminalCalls, 0)
    }
}
'''


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    snapshots = {path: path.read_bytes() for path in SOURCES + TESTS}
    support = module("runtime_smoke_support", ROOT / "testing/codex-runtime-smoke.py")
    assertions = support.ASSERTIONS.replace("class XCTestCase {}", "class XCTestCase { func setUp() {} }")
    assertions += r'''
func XCTAssertLessThan<T: Comparable>(_ actual: @autoclosure () -> T,
                                     _ expected: @autoclosure () -> T,
                                     _ message: @autoclosure () -> String = "",
                                     file: StaticString = #filePath, line: UInt = #line) {
    if !(actual() < expected()) { fail("Expected less. \(message())", file: file, line: line) }
}
'''
    (OUT / "Models.swift").write_text(MODELS)
    (OUT / "Assertions.swift").write_text(assertions)
    generated_tests = []
    entries = []
    for source, contents in [(p, snapshots[p].decode()) for p in TESTS] + [(Path("CodexMessagePathTests.swift"), CODEX_TESTS)]:
        clean = "import Foundation\n" + contents.replace("import XCTest\n", "").replace("@testable import AgentValley\n", "")
        destination = OUT / source.name
        destination.write_text(clean)
        generated_tests.append(destination)
        name = source.stem
        methods = re.findall(r"\bfunc (test\w+)\(\)(\s+throws)?\s*\{", contents)
        for method, throws in methods:
            entries.append(f'    ("{name}.{method}", {{ let suite = {name}(); suite.setUp(); {"try " if throws else ""}suite.{method}() }})')
    driver = '''import Foundation
let tests: [(String, () throws -> Void)] = [
''' + ",\n".join(entries) + r'''
]
var failedTests = 0
for (name, run) in tests {
    let before = assertionFailures.count
    do { try run() } catch { fail("Thrown error: \(error)", file: #filePath, line: #line) }
    if assertionFailures.count == before { print("PASS \(name)") }
    else { failedTests += 1 }
}
if let reply = codexWireReply {
    try reply.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("Message path: \(tests.count - failedTests)/\(tests.count) tests passed")
exit(failedTests == 0 ? 0 : 1)
'''
    (OUT / "main.swift").write_text(driver)
    compiler, sdk, env = swift_toolchain()
    binary = OUT / "message-smoke"
    command = [str(compiler), "-sdk", str(sdk), "-target", f"{platform.machine()}-apple-macosx15.0",
               "-module-cache-path", str(OUT / "module-cache")]
    command += [str(path) for path in SOURCES + [OUT / "Models.swift", OUT / "Assertions.swift"] + generated_tests + [OUT / "main.swift"]]
    command += ["-o", str(binary)]
    subprocess.run(command, cwd=ROOT, env=env, check=True)
    if any(path.read_bytes() != body for path, body in snapshots.items()):
        raise RuntimeError("Source changed during compilation; rerun when stable")
    wire = OUT / "actual-swift-stop-reply.json"
    subprocess.run([str(binary), str(wire)], cwd=ROOT, env=env, check=True)

    # The reply originated from SessionSender → StopDesk → AnswerProtocol, not
    # from a manually constructed approval. Only this temporary endpoint sees it.
    fixtures = module("answer_test_fixtures", ROOT / "integrations/codex/test_answers.py")
    reply = json.loads(wire.read_text())
    with tempfile.TemporaryDirectory(prefix="av-message-", dir="/tmp") as folder:
        socket_path = Path(folder) / "answers.sock"
        (Path(folder) / "away").touch(mode=0o600)
        with fixtures.FakeNotch(socket_path, reply):
            relayed = fixtures.bridge.stop_reply({"hook_event_name": "Stop",
                "session_id": "00000000-0000-4000-8000-000000000001"}, socket_path, 1)
        if relayed != reply:
            raise RuntimeError("Actual Swift queued-message reply did not survive the Python bridge")
    print("PASS Actual Swift StopDesk reply → private Unix socket → Codex bridge")
    result = {"swift_tests_passed": len(entries), "actual_reply_bridge_passed": True,
              "production_sources": {str(path.relative_to(ROOT)): hashlib.sha256(body).hexdigest()
                                     for path, body in snapshots.items() if path in SOURCES},
              "limits": ["No real phone pairing or live Codex conversation", "No GUI or terminal typing",
                         "Terminal UI types and XCTest assertion surface are test stubs"]}
    (OUT / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
