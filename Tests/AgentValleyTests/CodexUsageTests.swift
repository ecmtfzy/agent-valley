import Foundation
import XCTest
@testable import AgentValley

final class CodexUsageTests: XCTestCase {
    // Synthetic UUID v7 values keep date-scoped discovery deterministic.
    private let id = "01a1705b-6400-7000-8000-000000000001"
    private let other = "01a1705b-6400-7000-8000-000000000002"
    private let now = Date(timeIntervalSince1970: 1_792_973_600)

    private func data(_ type: String, _ payload: [String: Any], at: String = "2026-10-25T23:52:00.000Z") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": at, "payload": payload])
    }

    private func counts(_ input: Int, _ cached: Int, _ output: Int, written: Int = 0) -> [String: Any] {
        ["input_tokens": input, "cached_input_tokens": cached, "cache_write_input_tokens": written,
         "output_tokens": output, "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }

    private func usage(total: [String: Any], last: [String: Any]? = nil, at: String = "2026-10-25T23:52:00.000Z") throws -> Data {
        try data("event_msg", ["type": "token_count", "info": ["total_token_usage": total, "last_token_usage": last ?? total]], at: at)
    }

    private func prepared() throws -> (CodexUsageReader.Source, CodexUsageReader.State) {
        let source = CodexUsageReader.Source(id: id, path: "/unused")
        var state = CodexUsageReader.State()
        _ = CodexUsageReader.consume(try data("session_meta", ["id": id, "cwd": "/tmp/project", "timestamp": "2026-10-25T22:00:00.000Z"]), source: source, state: &state)
        _ = CodexUsageReader.consume(try data("turn_context", ["turn_id": "turn", "model": "gpt-6-astra", "cwd": "/tmp/project"]), source: source, state: &state)
        return (source, state)
    }

    func testCountsCacheOnceAndNeverAddsReasoningTwiceOrClaudePrice() throws {
        var (source, state) = try prepared()
        let answer = try XCTUnwrap(CodexUsageReader.consume(usage(total: counts(100, 60, 30, written: 10)), source: source, state: &state))
        XCTAssertEqual(answer.input, 30)
        XCTAssertEqual(answer.read, 60)
        XCTAssertEqual(answer.write5m, 10)
        XCTAssertEqual(answer.output, 30)
        XCTAssertEqual(answer.tokens, 130)
        XCTAssertEqual(answer.model, "gpt-6-astra")
        XCTAssertEqual(answer.session, "codex-" + id)
        XCTAssertNil(Pricing.cost(of: answer))
    }

    func testRepeatedCumulativeUsageAndCheckpointRestartAreNotCountedAgain() throws {
        var (source, state) = try prepared()
        XCTAssertNotNil(CodexUsageReader.consume(try usage(total: counts(100, 60, 30)), source: source, state: &state))
        state = CodexUsageReader.State.decode(state.json)
        XCTAssertNil(CodexUsageReader.consume(try usage(total: counts(100, 60, 30), at: "2026-10-25T23:52:01.000Z"), source: source, state: &state))
        let next = try XCTUnwrap(CodexUsageReader.consume(usage(total: counts(250, 160, 50), last: counts(150, 100, 20), at: "2026-10-25T23:52:02.000Z"), source: source, state: &state))
        XCTAssertEqual(next.input, 50)
        XCTAssertEqual(next.read, 100)
        XCTAssertEqual(next.output, 20)
    }

    func testOnlyExplicitLastUsageIsCountedWhenTheCounterStartsPartwayThrough() throws {
        var (source, state) = try prepared()
        let answer = try XCTUnwrap(CodexUsageReader.consume(usage(total: counts(1000, 800, 300), last: counts(100, 60, 30)), source: source, state: &state))
        XCTAssertEqual(answer.tokens, 130)
        let reset = try XCTUnwrap(CodexUsageReader.consume(usage(total: counts(20, 0, 10), at: "2026-10-25T23:52:01.000Z"), source: source, state: &state))
        XCTAssertEqual(reset.tokens, 30)
    }

    func testRejectsMalformedCountsAndWrongSessionMetadata() throws {
        for bad: [String: Any] in [counts(-1, 0, 1), counts(10, 11, 1), ["input_tokens": true, "output_tokens": 1], ["input_tokens": 1.5, "output_tokens": 1]] {
            var (source, state) = try prepared()
            XCTAssertNil(CodexUsageReader.consume(try usage(total: bad), source: source, state: &state))
        }
        let source = CodexUsageReader.Source(id: id, path: "/unused")
        var state = CodexUsageReader.State()
        _ = CodexUsageReader.consume(try data("session_meta", ["id": other, "cwd": "/tmp/other"]), source: source, state: &state)
        XCTAssertNil(CodexUsageReader.consume(try usage(total: counts(100, 0, 5)), source: source, state: &state))
    }

    func testInheritedUsageBeforeSessionCreationIsNotChargedToTheFork() throws {
        var (source, state) = try prepared()
        state.createdAt = TranscriptReader.date(from: "2026-10-25T23:52:01.000Z")
        XCTAssertNil(CodexUsageReader.consume(try usage(total: counts(100, 60, 30)), source: source, state: &state))
        let next = try XCTUnwrap(CodexUsageReader.consume(usage(total: counts(250, 160, 50), last: counts(150, 100, 20), at: "2026-10-25T23:52:02.000Z"), source: source, state: &state))
        XCTAssertEqual(next.tokens, 170)
    }

    func testChildUsageBelongsToItsParentSessionWithItsActualModel() throws {
        let source = CodexUsageReader.Source(id: id, path: "/unused")
        var state = CodexUsageReader.State()
        _ = CodexUsageReader.consume(try data("session_meta", ["id": id, "cwd": "/tmp/project", "source": ["subagent": ["thread_spawn": ["parent_thread_id": other, "agent_role": "explore"]]]]), source: source, state: &state)
        _ = CodexUsageReader.consume(try data("turn_context", ["model": "gpt-6-sol"]), source: source, state: &state)
        let answer = try XCTUnwrap(CodexUsageReader.consume(usage(total: counts(100, 0, 30)), source: source, state: &state))
        XCTAssertEqual(answer.session, "codex-" + other)
        XCTAssertEqual(answer.agent, "explore")
        XCTAssertEqual(answer.model, "gpt-6-sol")
    }

    private func fixture() throws -> (URL, CodexUsageReader, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("agentvalley-codex-usage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let journal = base.appendingPathComponent("events.jsonl")
        try JSONSerialization.data(withJSONObject: ["version": 1, "session_id": id]).write(to: journal)
        let file = base.appendingPathComponent("sessions/2026/10/26/rollout-2026-10-26T09-00-00-" + id + ".jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let meta = try data("session_meta", ["id": id, "cwd": "/tmp/project"])
        let turn = try data("turn_context", ["model": "gpt-6-astra"])
        try (meta + Data([10]) + turn + Data([10]) + usage(total: counts(100, 60, 30)) + Data([10])).write(to: file)
        return (base, CodexUsageReader(home: base, journal: journal), file)
    }

    func testDiscoveryIsJournalScopedAndPartialLineWaitsForCompletion() throws {
        let (base, reader, file) = try fixture()
        let unrelated = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T09-00-00-" + other + ".jsonl")
        try Data("unrelated private content".utf8).write(to: unrelated)
        try JSONSerialization.data(withJSONObject: ["id": id, "thread_name": "Actual session title"]).write(to: base.appendingPathComponent("session_index.jsonl"))
        let snapshot = reader.snapshot()
        XCTAssertEqual(snapshot.sources.map(\.id), [id])
        XCTAssertEqual(snapshot.titles, ["codex-" + id: "Actual session title"])
        let source = try XCTUnwrap(snapshot.sources.first)
        let first = reader.read(source, state: .init())
        XCTAssertEqual(first.answers.count, 1)
        XCTAssertTrue(reader.read(source, state: first.state).answers.isEmpty)
        let next = try usage(total: counts(250, 160, 50), last: counts(150, 100, 20), at: "2026-10-25T23:52:02.000Z")
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: next.prefix(40))
        let partial = reader.read(source, state: first.state)
        XCTAssertTrue(partial.answers.isEmpty)
        XCTAssertEqual(partial.state.offset, first.state.offset)
        try handle.write(contentsOf: next.dropFirst(40) + Data([10]))
        XCTAssertEqual(reader.read(source, state: partial.state).answers.first?.tokens, 170)
    }

    func testExistingLedgerIncludesCodexUsageOnceAcrossAppRestarts() throws {
        let (base, reader, _) = try fixture()
        func ledger() -> UsageLedger {
            UsageLedger(root: base.appendingPathComponent("projects"), database: base.appendingPathComponent("support/history.sqlite"), codexUsage: reader)
        }
        var store = ledger()
        let first = store.scan(now: now)
        XCTAssertNil(first.problem)
        XCTAssertTrue(first.added)
        XCTAssertEqual(first.summary.fiveHours, TokenTotals(input: 40, cacheRead: 60, output: 30))
        store = ledger()
        let again = store.scan(now: now)
        XCTAssertFalse(again.added)
        XCTAssertEqual(again.summary.fiveHours, first.summary.fiveHours)
        let entries = try store.slice(DateInterval(start: .distantPast, end: .distantFuture)).answers
        XCTAssertEqual(entries.count, 1)
        let answer = try XCTUnwrap(entries.first)
        XCTAssertNil(Pricing.cost(of: answer))
    }

    func testKnownChildIDsAreDiscoveredWithoutTheirOwnSessionStartHook() throws {
        let (base, reader, file) = try fixture()
        let child = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T09-00-00-" + other + ".jsonl")
        try Data().write(to: child)
        try JSONSerialization.data(withJSONObject: ["version": 1, "event": "SubagentStart", "session_id": id, "agent_id": other])
            .write(to: base.appendingPathComponent("events.jsonl"))
        XCTAssertEqual(Set(reader.snapshot().sources.map(\.id)), [id, other])
    }

    func testOversizedLinesAreSkippedAndTranscriptSymlinksAreRefused() throws {
        let (base, reader, file) = try fixture()
        let source = try XCTUnwrap(reader.snapshot().sources.first)
        let first = reader.read(source, state: .init())
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 65, count: CodexUsageReader.maxReadBytes + 100))
        try handle.write(contentsOf: Data([10]) + usage(total: counts(250, 160, 50), last: counts(150, 100, 20), at: "2026-10-25T23:52:02.000Z") + Data([10]))
        try handle.close()
        let skipped = reader.read(source, state: first.state)
        XCTAssertTrue(skipped.answers.isEmpty)
        XCTAssertTrue(skipped.state.skippingLongLine)
        let after = reader.read(source, state: skipped.state)
        XCTAssertEqual(after.answers.first?.tokens, 170)
        let link = base.appendingPathComponent("symlink.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertTrue(reader.read(.init(id: id, path: link.path), state: .init()).answers.isEmpty)
    }
}
