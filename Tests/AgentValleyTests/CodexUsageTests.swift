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

    private func writeIndex(_ records: [[String: Any]], home: URL) throws {
        var bytes = Data()
        for record in records {
            bytes += try JSONSerialization.data(withJSONObject: record)
            bytes += Data([10])
        }
        try bytes.write(to: home.appendingPathComponent("session_index.jsonl"))
    }

    func testIndexOnlyHistoryWorksWithoutHooksAndImportsOnceAcrossRestarts() throws {
        let (base, journalReader, _) = try fixture()
        try FileManager.default.removeItem(at: base.appendingPathComponent("events.jsonl"))
        try writeIndex([["id": id, "thread_name": "History before hooks"]], home: base)
        XCTAssertEqual(journalReader.snapshot().sources.map(\.id), [id])
        // Neither an environment journal nor the default AgentValley journal exists.
        let reader = try XCTUnwrap(CodexUsageReader.configured(environment: ["CODEX_HOME": base.path],
                                                              home: base.appendingPathComponent("unused-user-home")))
        let snapshot = reader.snapshot()
        XCTAssertEqual(snapshot.sources.map(\.id), [id])
        XCTAssertEqual(snapshot.titles, ["codex-" + id: "History before hooks"])
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
        XCTAssertNil(again.problem)
        XCTAssertFalse(again.added)
        let entries = try store.slice(DateInterval(start: .distantPast, end: .distantFuture)).answers
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.session, "codex-" + id)
        XCTAssertEqual(entries.first?.model, "gpt-6-astra")
    }

    func testIndexAndJournalUnionDeduplicatesAndPrefersActiveOverArchived() throws {
        let (base, reader, active) = try fixture()
        let archive = base.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let archivedCopy = archive.appendingPathComponent(active.lastPathComponent)
        try FileManager.default.copyItem(at: active, to: archivedCopy)
        let archivedOther = archive.appendingPathComponent("rollout-2026-10-26T09-00-00-" + other + ".jsonl")
        try (data("session_meta", ["id": other, "cwd": "/tmp/archived"]) + Data([10])
             + data("turn_context", ["model": "gpt-6-sol"]) + Data([10])
             + usage(total: counts(20, 0, 5)) + Data([10])).write(to: archivedOther)
        try writeIndex([["id": id, "thread_name": "Old title"], ["id": other],
                        ["id": id, "thread_name": "Latest title"], ["id": other]], home: base)
        let snapshot = reader.snapshot()
        XCTAssertEqual(snapshot.sources.map(\.id), [id, other])
        XCTAssertEqual(snapshot.sources.first?.path, active.path)
        XCTAssertEqual(snapshot.titles, ["codex-" + id: "Latest title"])
        let old = try XCTUnwrap(snapshot.sources.last)
        XCTAssertEqual(old.path, archivedOther.path)
        XCTAssertEqual(reader.read(old, state: .init()).answers.first?.tokens, 25)
    }

    func testIndexCannotDiscoverUnknownIDsOrOverrideTranscriptIdentity() throws {
        let (base, reader, file) = try fixture()
        let unknown = "01a1705b-6400-7000-8000-000000000003"
        let stranger = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T09-00-00-" + unknown + ".jsonl")
        try Data("private stranger content".utf8).write(to: stranger)
        // The filename is index-known, but its actual metadata belongs to a different session.
        let wrongIdentity = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T09-00-00-" + other + ".jsonl")
        try FileManager.default.copyItem(at: file, to: wrongIdentity)
        try writeIndex([["id": other], ["id": "../" + unknown], ["id": true]], home: base)
        let snapshot = reader.snapshot()
        XCTAssertEqual(snapshot.sources.map(\.id), [id, other])
        let source = try XCTUnwrap(snapshot.sources.last)
        let rejected = reader.read(source, state: .init())
        XCTAssertTrue(rejected.answers.isEmpty)
        XCTAssertTrue(rejected.state.rejected)
        XCTAssertFalse(rejected.state.verified)
    }

    func testNonV7IndexIDsOnlyDiscoverAnExactArchivedFilename() throws {
        let (base, reader, file) = try fixture()
        let legacy = "11111111-1111-4111-8111-111111111111"
        let dateFile = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T09-00-00-" + legacy + ".jsonl")
        try Data().write(to: dateFile)
        try writeIndex([["id": legacy]], home: base)
        // A UUID without a date cannot request a recursive search of sessions/.
        XCTAssertEqual(reader.snapshot().sources.map(\.id), [id])
        let archive = base.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let archived = archive.appendingPathComponent(dateFile.lastPathComponent)
        try FileManager.default.copyItem(at: dateFile, to: archived)
        let snapshot = reader.snapshot()
        XCTAssertEqual(Set(snapshot.sources.map(\.id)), [id, legacy])
        XCTAssertEqual(snapshot.sources.first { $0.id == legacy }?.path, archived.path)
    }

    func testCodexOnlyHistoryNeverLearnsGitCheckoutsButKeepsSavedMappings() throws {
        let (base, reader, file) = try fixture()
        let project = base.appendingPathComponent("old-project")
        let nextProject = base.appendingPathComponent("another-old-project")
        for folder in [project, nextProject] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(".git"), withIntermediateDirectories: true)
        }
        try (data("session_meta", ["id": id, "cwd": project.path]) + Data([10])
             + data("turn_context", ["model": "gpt-6-astra"]) + Data([10])
             + usage(total: counts(100, 60, 30)) + Data([10])).write(to: file)
        let database = base.appendingPathComponent("support/history.sqlite")
        func ledger() -> UsageLedger {
            UsageLedger(root: base.appendingPathComponent("projects"), database: database, codexUsage: reader)
        }
        var store = ledger()
        let all = DateInterval(start: .distantPast, end: .distantFuture)
        XCTAssertTrue(store.scan(now: now).added)
        let firstCheckouts = try store.slice(all).checkouts
        XCTAssertTrue(firstCheckouts.isEmpty)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: data("turn_context", ["model": "gpt-6-astra", "cwd": nextProject.path]) + Data([10])
                         + usage(total: counts(250, 160, 50), at: "2026-10-25T23:52:02.000Z") + Data([10]))
        try handle.close()
        XCTAssertTrue(store.scan(now: now).added)
        let nextCheckouts = try store.slice(all).checkouts
        XCTAssertTrue(nextCheckouts.isEmpty)
        do {
            let db = try SQLite(path: database.path)
            try db.rows("INSERT INTO checkouts VALUES (?, ?)", [.text(project.path), .text("/saved/checkout")])
        }
        store = ledger()
        XCTAssertFalse(store.scan(now: now).added)
        let savedCheckouts = try store.slice(all).checkouts
        XCTAssertEqual(savedCheckouts, [project.path: "/saved/checkout"])
    }

    func testIndexMustBeARegularFileAndDoesNotEnableAnEmptyHome() throws {
        let (base, _, _) = try fixture()
        let userHome = base.appendingPathComponent("unused-user-home")
        try FileManager.default.removeItem(at: base.appendingPathComponent("events.jsonl"))
        XCTAssertNil(CodexUsageReader.configured(environment: ["CODEX_HOME": base.path], home: userHome))
        let index = base.appendingPathComponent("session_index.jsonl")
        let target = base.appendingPathComponent("index-target.jsonl")
        try JSONSerialization.data(withJSONObject: ["id": id]).write(to: target)
        try FileManager.default.createSymbolicLink(at: index, withDestinationURL: target)
        XCTAssertNil(CodexUsageReader.configured(environment: ["CODEX_HOME": base.path], home: userHome))
        XCTAssertTrue(CodexUsageReader(home: base).snapshot().sources.isEmpty)
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertNil(CodexUsageReader.configured(environment: ["CODEX_HOME": base.path], home: userHome))
        XCTAssertTrue(CodexUsageReader(home: base).snapshot().sources.isEmpty)
    }

    func testDiscoveryRejectsRolloutFilesAndDateDirectoriesReachedThroughSymlinks() throws {
        let (base, reader, file) = try fixture()
        let target = base.appendingPathComponent("moved-transcript.jsonl")
        try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertTrue(reader.snapshot().sources.isEmpty)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: target, to: file)
        let day = file.deletingLastPathComponent()
        let movedDay = base.appendingPathComponent("moved-day")
        try FileManager.default.moveItem(at: day, to: movedDay)
        try FileManager.default.createSymbolicLink(at: day, withDestinationURL: movedDay)
        XCTAssertTrue(reader.snapshot().sources.isEmpty)
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
