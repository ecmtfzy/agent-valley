import Foundation
import XCTest
@testable import AgentValley

final class CodexRuntimeStatusTests: XCTestCase {
    private typealias State = CodexRuntimeStatus.RuntimeState
    private let waiting = State(status: "active", flags: ["waitingOnApproval"])
    private let working = State(status: "active", flags: [])
    private let cardID = "codex-test-session"

    private final class Clock {
        var now: TimeInterval = 0
        func advance(_ seconds: TimeInterval = 1) { now += seconds }
    }

    private func card(id: String = "codex-test-session", status: AgentStatus = .needsYou) -> SessionCard {
        var info = AgentInfo()
        info.lastStep = "Bash"
        info.openTools = [OpenTool(id: "call-1", tool: "exec_command", input: [:])]
        return SessionCard(id: id, project: "test", branch: "",
                           main: AgentRow(id: id + "-main", info: info, status: status,
                                          elapsed: 12, quietFor: 4),
                           agents: [], startedAt: Date(timeIntervalSince1970: 0))
    }

    func testRequiresObservedWaitThenRestoresWorkingBeforeToolResult() throws {
        var current: State? = working
        var requested: [String] = []
        let clock = Clock()
        let runtime = CodexRuntimeStatus(now: { clock.now }) { requested.append($0); return current }
        let source = card()
        let tokens = [cardID: "permission-1"]
        XCTAssertEqual(runtime.adjust(cards: [source], tokens: tokens).first, source)
        current = waiting
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [source], tokens: tokens).first?.main?.status, .needsYou)
        current = working
        clock.advance()
        let shown = try XCTUnwrap(runtime.adjust(cards: [source], tokens: tokens).first)
        XCTAssertEqual(shown.main?.status, .working)
        XCTAssertEqual(shown.main?.step, "Bash")
        XCTAssertEqual(shown.main?.quietFor, 0)
        XCTAssertEqual(shown.main?.elapsed, source.main?.elapsed)
        XCTAssertEqual(shown.main?.info.openTools, source.main?.info.openTools)
        XCTAssertEqual(requested, ["test-session", "test-session", "test-session"])
        // This is an overlay; the native hook row remains pending until its result.
        XCTAssertEqual(source.main?.status, .needsYou)
    }

    func testUnavailableIdleOrUnknownStatusCannotResolveAnObservedWait() {
        var current: State? = waiting
        let clock = Clock()
        let runtime = CodexRuntimeStatus(now: { clock.now }) { _ in current }
        let tokens = [cardID: "permission-1"]
        _ = runtime.adjust(cards: [card()], tokens: tokens)
        let unsupported: [State?] = [nil, State(status: "idle", flags: []),
                                     State(status: "notLoaded", flags: []),
                                     State(status: "systemError", flags: []),
                                     State(status: "futureStatus", flags: []),
                                     State(status: "active", flags: ["futureFlag"])]
        for value in unsupported {
            current = value
            clock.advance(10)
            XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status,
                           .needsYou, "Must not infer approval from \(String(describing: value))")
        }
    }

    func testResolvedOverlaySurvivesTransientFailureUntilHookClearsOrTokenChanges() {
        var current: State? = waiting
        let clock = Clock()
        let runtime = CodexRuntimeStatus(now: { clock.now }) { _ in current }
        let tokens = [cardID: "permission-1"]
        _ = runtime.adjust(cards: [card()], tokens: tokens)
        current = working
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .working)
        current = nil
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .working)
        current = working
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: [cardID: "permission-2"]).first?.main?.status, .needsYou)
        current = waiting
        clock.advance()
        _ = runtime.adjust(cards: [card()], tokens: [cardID: "permission-2"])
        current = working
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: [cardID: "permission-2"]).first?.main?.status, .working)
        let stopped = card(status: .done)
        XCTAssertEqual(runtime.adjust(cards: [stopped], tokens: [:]).first, stopped)
        // Even reusing a token after its hook cleared cannot reuse old evidence.
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: [cardID: "permission-2"]).first?.main?.status, .needsYou)
    }

    func testUserInputAndAnotherApprovalRemainVisibleAfterWorking() {
        var current: State? = waiting
        let clock = Clock()
        let runtime = CodexRuntimeStatus(now: { clock.now }) { _ in current }
        let tokens = [cardID: "permission-1"]
        _ = runtime.adjust(cards: [card()], tokens: tokens)
        current = State(status: "active", flags: ["waitingOnUserInput"])
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .needsYou)
        current = working
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .working)
        current = State(status: "active", flags: ["waitingOnUserInput"])
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .needsYou)
        current = nil
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .needsYou)
        current = waiting
        clock.advance(10)
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .needsYou)
        current = nil
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .needsYou)
    }

    func testOtherSessionsAndFinishedRowsNeverReadRuntimeOrChange() {
        var reads = 0
        let runtime = CodexRuntimeStatus { _ in reads += 1; return self.working }
        let other = card(id: "claude-session")
        let finished = card(status: .done)
        var closed = card(id: "codex-closed")
        closed.closed = true
        let noPermission = card(id: "codex-no-permission", status: .working)
        let cards = [other, finished, closed, noPermission]
        XCTAssertEqual(runtime.adjust(cards: cards, tokens: [other.id: "1", finished.id: "1", closed.id: "1"]), cards)
        XCTAssertEqual(reads, 0)
    }

    func testFrequentPublishesReuseOnlyCurrentTokenEvidenceAndSampleAtMostOncePerSecond() {
        let clock = Clock()
        var current: State? = waiting
        var reads = 0
        let runtime = CodexRuntimeStatus(now: { clock.now }) { _ in reads += 1; return current }
        let tokens = [cardID: "permission-1"]
        _ = runtime.adjust(cards: [card()], tokens: tokens)
        current = working
        for _ in 0..<8 {
            clock.advance(0.1)
            XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .needsYou)
        }
        XCTAssertEqual(reads, 1)
        clock.advance(0.21)
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: tokens).first?.main?.status, .working)
        XCTAssertEqual(reads, 2)
        // A new request discards the old overlay even before it is eligible to sample.
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: [cardID: "permission-2"]).first?.main?.status, .needsYou)
        XCTAssertEqual(reads, 2)
        clock.advance()
        XCTAssertEqual(runtime.adjust(cards: [card()], tokens: [cardID: "permission-2"]).first?.main?.status, .needsYou)
        XCTAssertEqual(reads, 3)
    }

    func testFailureBacksOffTenSecondsAndDoesNotStarveAnotherCard() {
        let clock = Clock()
        var requested: [String] = []
        let runtime = CodexRuntimeStatus(now: { clock.now }) { id in
            requested.append(id)
            return id == "a" ? nil : self.waiting
        }
        let cards = [card(id: "codex-b"), card(id: "codex-a")]
        let tokens = ["codex-a": "1", "codex-b": "1"]
        _ = runtime.adjust(cards: cards, tokens: tokens)
        XCTAssertEqual(requested, ["a"]) // At most one helper in this publish.
        _ = runtime.adjust(cards: cards, tokens: tokens)
        XCTAssertEqual(requested, ["a", "b"])
        for _ in 0..<9 {
            clock.advance()
            _ = runtime.adjust(cards: cards, tokens: tokens)
        }
        XCTAssertEqual(requested.filter { $0 == "a" }.count, 1)
        clock.advance()
        _ = runtime.adjust(cards: cards, tokens: tokens)
        XCTAssertEqual(requested.last, "a") // Oldest eligible sample wins.
        XCTAssertEqual(requested.filter { $0 == "a" }.count, 2)
    }

    func testOldestEligibleCardIsSelectedWithoutDependingOnInputOrder() {
        let clock = Clock()
        var requested: [String] = []
        let runtime = CodexRuntimeStatus(now: { clock.now }) { requested.append($0); return self.waiting }
        let cards = [card(id: "codex-c"), card(id: "codex-b"), card(id: "codex-a")]
        let tokens = ["codex-a": "1", "codex-b": "1", "codex-c": "1"]
        for _ in 0..<3 {
            _ = runtime.adjust(cards: cards, tokens: tokens)
            clock.advance()
        }
        XCTAssertEqual(requested, ["a", "b", "c"])
        _ = runtime.adjust(cards: cards, tokens: tokens)
        XCTAssertEqual(requested, ["a", "b", "c", "a"])
    }
}
