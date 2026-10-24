import XCTest
@testable import AgentValley

final class SupersetSendTests: XCTestCase {
    private let ok = ScriptRun(status: 0, out: "", err: "", timedOut: false)
    private let text = ["terminals", "send", "--local", "--workspace", "W", "--terminal", "T", "--no-submit", "--text=go"]
    private let enter = ["terminals", "send", "--local", "--workspace", "W", "--terminal", "T", "--keys", "enter"]

    /// Sends "go" to W/T. `checks` answers each look in turn; `results` each run in turn.
    private func send(checks: [Bool] = [true, true], results: [ScriptRun]? = nil) -> (result: TypingResult, runs: [[String]], waits: [TimeInterval]) {
        var checks = checks, results = results ?? [ok, ok]
        var runs: [[String]] = [], waits: [TimeInterval] = []
        let result = SupersetSend.send(workspace: "W", terminal: "T", text: "go", check: { checks.removeFirst() },
                                       run: { runs.append($0); return results.removeFirst() }, wait: { waits.append($0) })
        return (result, runs, waits)
    }

    func testTheTextGoesInOneArgumentThatCannotBeReadAsAnOption() {
        XCTAssertEqual(SupersetSend.arguments(workspace: "W", terminal: "T", text: "--help\nnext"),
                       ["terminals", "send", "--local", "--workspace", "W", "--terminal", "T", "--no-submit", "--text=--help\nnext"])
    }
    func testTheCommandLivesInSupersetsOwnFolder() {
        XCTAssertEqual(SupersetSend.binary(home: URL(fileURLWithPath: "/Users/a")).path, "/Users/a/.superset/bin/superset")
    }
    // As in a tab: the text staged, a pause and a second look, then Enter on its own.
    func testTheTextThenAPauseThenEnter() {
        let sent = send()
        XCTAssertEqual(sent.result, .typed)
        XCTAssertEqual(sent.runs, [text, enter])
        XCTAssertEqual(sent.waits, [TabTyping.pause])
    }
    func testNothingGoesWhenClaudeIsNotInFront() {
        let sent = send(checks: [false])
        XCTAssertEqual(sent.result, .stoppedBeforeText)
        XCTAssertTrue(sent.runs.isEmpty)
    }
    func testALookThatFailsBetweenTextAndEnterSendsNoEnter() {
        let sent = send(checks: [true, false])
        XCTAssertEqual(sent.result, .stoppedBeforeEnter)
        XCTAssertEqual(sent.runs, [text])
    }
    func testExitZeroIsSentAndAnythingElseSaysWhy() {
        let failed = send(results: [ScriptRun(status: 1, out: "", err: "Terminal not found\n", timedOut: false)])
        XCTAssertEqual(failed.result, .failed("Terminal not found"))
        XCTAssertEqual(failed.runs, [text])
        XCTAssertEqual(send(results: [ok, ScriptRun(status: 1, out: "", err: "No such key\n", timedOut: false)]).result, .failed("No such key"))
    }
    func testAHungCommandIsTimedOutAndStdoutBacksUpEmptyStderr() {
        XCTAssertEqual(send(results: [ScriptRun(status: -1, out: "", err: "", timedOut: true)]).result, .timedOut)
        XCTAssertEqual(send(results: [ok, ScriptRun(status: -1, out: "", err: "", timedOut: true)]).result, .timedOut)
        XCTAssertEqual(send(results: [ScriptRun(status: 2, out: "\n no luck \nmore", err: "", timedOut: false)]).result, .failed("no luck"))
    }
    func testNoBinarySaysSupersetIsNotInstalled() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let run = SupersetSend.run(SupersetSend.binary(home: home))
        XCTAssertEqual(SupersetSend.send(workspace: "W", terminal: "T", text: "go", check: { true }, run: run, wait: { _ in }),
                       .failed("Superset's command isn't installed."))
    }
}
