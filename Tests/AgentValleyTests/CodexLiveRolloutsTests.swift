import Foundation
import XCTest
@testable import AgentValley

final class CodexLiveRolloutsTests: XCTestCase {
    private let id = "01a1705b-6400-7000-8000-000000000001"
    private let other = "01a1705b-6400-7000-8000-000000000002"
    private let epoch = Date(timeIntervalSince1970: 1_792_972_800)

    private func stamp(_ seconds: TimeInterval) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: epoch.addingTimeInterval(seconds))
    }

    private func line(_ type: String, _ payload: [String: Any], at: TimeInterval = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": stamp(at), "payload": payload]) + Data([10])
    }

    private func event(_ type: String, turn: String = "turn-1", at: TimeInterval = 0) throws -> Data {
        try line("event_msg", ["type": type, "turn_id": turn], at: at)
    }

    private func meta(_ session: String? = nil, source: Any = "vscode") throws -> Data {
        try line("session_meta", ["id": session ?? id, "source": source, "cwd": "/tmp/project",
                                  "timestamp": stamp(-100)], at: -100)
    }

    private func fixture(_ body: Data? = nil) throws -> (URL, URL, CodexLiveRollouts) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-live-fixture-" + UUID().uuidString)
        let file = home.appendingPathComponent("sessions/2026/10/26/rollout-2026-10-26T00-00-00-" + id + ".jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        try JSONSerialization.data(withJSONObject: ["id": id, "thread_name": "Fixture title"])
            .write(to: home.appendingPathComponent("session_index.jsonl"))
        try (body ?? meta()).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: epoch], ofItemAtPath: file.path)
        return (home, file, CodexLiveRollouts(home: home))
    }

    private func append(_ body: Data, to file: URL, at: TimeInterval = 0) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: body)
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: epoch.addingTimeInterval(at)], ofItemAtPath: file.path)
    }

    func testIndexedRootWithoutHooksGetsModelWorkingAndDoneWithoutPrivateToolText() throws {
        let body = try meta() + event("task_started")
            + line("turn_context", ["turn_id": "turn-1", "model": "gpt-6-astra", "cwd": "/tmp/project/child"])
            + line("response_item", ["type": "function_call", "name": "exec_command", "call_id": "call-1", "arguments": "PRIVATE"])
        let (_, file, reader) = try fixture(body)
        let card = try XCTUnwrap(reader.readCards(now: epoch).first)
        XCTAssertEqual(card.id, "codex-" + id)
        XCTAssertEqual(card.title, "Fixture title")
        XCTAssertEqual(card.project, "project")
        XCTAssertEqual(card.main?.info.folder, "/tmp/project/child")
        XCTAssertEqual(card.main?.info.model, "gpt-6-astra")
        XCTAssertEqual(card.main?.status, .working)
        XCTAssertEqual(card.main?.info.lastStep, "Bash")
        XCTAssertEqual(card.main?.info.openTools.first?.input, [:])
        XCTAssertFalse(card.main?.info.asking ?? true)
        try append(event("task_complete", at: 1), to: file, at: 1)
        let ended = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(1)).first)
        XCTAssertEqual(ended.main?.status, .done)
        XCTAssertTrue(ended.main?.info.openTools.isEmpty ?? false)
    }

    func testNineteenMiBBootstrapUsesTailAndStaysWithinPerTickBudget() throws {
        let body = try meta() + Data(repeating: 65, count: 19 * 1024 * 1024) + Data([10])
            + event("task_started") + line("turn_context", ["turn_id": "turn-1", "model": "gpt-6-astra"])
            + line("response_item", ["type": "message", "role": "assistant", "phase": "commentary", "content": "PRIVATE"])
        let (_, _, reader) = try fixture(body)
        let card = try XCTUnwrap(reader.readCards(now: epoch).first)
        XCTAssertEqual(card.main?.status, .working)
        XCTAssertEqual(card.main?.info.model, "gpt-6-astra")
        XCTAssertTrue(reader.lastReadBytes <= CodexLiveRollouts.maxReadBytes)
        XCTAssertTrue(reader.lastReadBytes < 2 * 1024 * 1024)
    }

    func testSkippedMiddleCannotCarryOldWorkingStateIntoContextOnlyTail() throws {
        let body = try meta() + event("task_started", turn: "old", at: -90)
            + event("task_complete", turn: "old", at: -80)
            + Data(repeating: 65, count: 3 * 1024 * 1024) + Data([10])
            + line("turn_context", ["turn_id": "unknown", "model": "gpt-6-astra"])
            + line("event_msg", ["type": "token_count", "info": ["secret": "PRIVATE"]])
        let (_, _, reader) = try fixture(body)
        let card = try XCTUnwrap(reader.readCards(now: epoch).first)
        XCTAssertEqual(card.main?.status, .quiet)
        XCTAssertNil(card.main?.info.lastActivity)
    }

    func testPartialLineWaitsForNewlineAndLongLinesDoNotStallCursor() throws {
        let (_, file, reader) = try fixture(meta() + event("task_started"))
        XCTAssertEqual(reader.readCards(now: epoch).first?.main?.status, .working)
        let complete = try event("task_complete", at: 2)
        try append(Data(complete.dropLast()), to: file, at: 1)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .working)
        try append(Data([10]), to: file, at: 2)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(2)).first?.main?.status, .done)
        try append(event("task_started", turn: "turn-2", at: 3), to: file, at: 3)
        _ = reader.readCards(now: epoch.addingTimeInterval(3))
        let legalLong = try line("response_item", ["type": "message", "role": "assistant", "phase": "commentary",
                                                   "content": String(repeating: "x", count: 400_000)], at: 4)
        try append(legalLong, to: file, at: 4)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(4)).first?.main?.info.lastActivity, epoch.addingTimeInterval(4))
        try append(Data(repeating: 65, count: 2 * CodexLiveRollouts.maxLineBytes + 100) + Data([10])
                   + event("task_complete", turn: "turn-2", at: 5), to: file, at: 5)
        var cards: [SessionCard] = []
        for _ in 0..<4 {
            cards = reader.readCards(now: epoch.addingTimeInterval(5))
            XCTAssertTrue(reader.lastReadBytes <= CodexLiveRollouts.maxReadBytes)
        }
        XCTAssertEqual(cards.first?.main?.status, .done)
    }

    func testReplacementAndTruncationReverifyIdentityAndClearOldTools() throws {
        let (_, file, reader) = try fixture(meta() + event("task_started")
            + line("response_item", ["type": "function_call", "name": "exec_command", "call_id": "call"]))
        XCTAssertEqual(reader.readCards(now: epoch).first?.main?.info.openTools.count, 1)
        try (meta(other) + event("task_started")).write(to: file, options: .atomic)
        XCTAssertTrue(reader.readCards(now: epoch).isEmpty)
        try (meta() + event("task_started") + event("task_complete", at: 1)).write(to: file, options: .atomic)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .done)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: meta() + event("task_started", turn: "new", at: 2))
        try handle.close()
        let card = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(2)).first)
        XCTAssertEqual(card.main?.status, .working)
        XCTAssertTrue(card.main?.info.openTools.isEmpty ?? false)
    }

    func testCachedPathCannotFollowAReplacedFileOrParentSymlink() throws {
        let (home, file, reader) = try fixture(meta() + event("task_started"))
        XCTAssertEqual(reader.readCards(now: epoch).count, 1)
        let moved = home.appendingPathComponent("moved.jsonl")
        try FileManager.default.moveItem(at: file, to: moved)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: moved)
        XCTAssertTrue(reader.readCards(now: epoch.addingTimeInterval(1)).isEmpty)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: moved, to: file)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(2)).count, 1)
        let day = file.deletingLastPathComponent(), movedDay = home.appendingPathComponent("moved-day")
        try FileManager.default.moveItem(at: day, to: movedDay)
        try FileManager.default.createSymbolicLink(at: day, withDestinationURL: movedDay)
        XCTAssertTrue(reader.readCards(now: epoch.addingTimeInterval(3)).isEmpty)
    }

    func testSubagentUnknownAndMismatchedMetadataNeverBecomeIndependentCards() throws {
        for origin: Any in [["subagent": ["thread_spawn": ["parent_thread_id": other]]],
                            ["subAgent": ["thread_spawn": ["parent_thread_id": other]]], "unknown", "subAgentThreadSpawn"] {
            let (_, _, reader) = try fixture(meta(source: origin) + event("task_started"))
            XCTAssertTrue(reader.readCards(now: epoch).isEmpty)
        }
    }

    func testLateOldTurnCompletionAndNonAssistantFinalDoNotEndNewWork() throws {
        let (_, file, reader) = try fixture(meta() + event("task_started", turn: "old")
            + event("task_started", turn: "new", at: 1) + event("task_complete", turn: "old", at: 2)
            + line("response_item", ["type": "message", "role": "user", "phase": "final_answer"], at: 3))
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(3)).first?.main?.status, .working)
        try append(line("response_item", ["type": "message", "role": "assistant", "phase": "final_answer"], at: 4), to: file, at: 4)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(4)).first?.main?.status, .done)
        try append(line("event_msg", ["type": "token_count"], at: 5)
                   + line("turn_context", ["turn_id": "new", "model": "gpt-test"], at: 5), to: file, at: 5)
        let ended = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(5)).first)
        XCTAssertEqual(ended.main?.status, .done)
        XCTAssertEqual(ended.main?.info.lastActivity, epoch.addingTimeInterval(4))
    }

    func testStructuredItemsCanDriveActivityButWrongThreadItemsCannot() throws {
        let (_, file, reader) = try fixture(meta() + line("event_msg", ["type": "item_completed", "thread_id": id,
            "turn_id": "turn-1", "item": ["type": "CommandExecution", "command": "PRIVATE", "output": "PRIVATE"]]))
        let first = try XCTUnwrap(reader.readCards(now: epoch).first)
        XCTAssertEqual(first.main?.status, .working)
        XCTAssertEqual(first.main?.step, "Bash")
        try append(line("event_msg", ["type": "item_completed", "thread_id": other, "turn_id": "turn-1",
            "item": ["type": "AgentMessage", "phase": "final_answer"]], at: 1), to: file, at: 1)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .working)
        try append(event("turn_aborted", at: 2), to: file, at: 2)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(2)).first?.main?.status, .done)
    }

    func testActivityExpiresAndHousekeepingDoesNotReviveFinishedCards() throws {
        let (_, file, reader) = try fixture(meta() + event("task_started"))
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(AgentStore.stuckAfter)).first?.main?.status, .quiet)
        try append(event("task_complete", at: 601), to: file, at: 601)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(601), visibleFor: 10).first?.main?.status, .done)
        XCTAssertTrue(reader.readCards(now: epoch.addingTimeInterval(612), visibleFor: 10).isEmpty)
        try append(line("event_msg", ["type": "token_count"], at: 613), to: file, at: 613)
        XCTAssertTrue(reader.readCards(now: epoch.addingTimeInterval(613), visibleFor: 10).isEmpty)
        XCTAssertTrue(reader.readCards(now: epoch.addingTimeInterval(AgentStore.forgetAfter + 700)).isEmpty)
    }

    func testExclusionsAndArchivedOrUnindexedFilesDoNotProduceDuplicates() throws {
        let (home, file, reader) = try fixture(meta() + event("task_started"))
        XCTAssertTrue(reader.readCards(now: epoch, excluding: ["codex-" + id]).isEmpty)
        XCTAssertTrue(reader.readCards(now: epoch, excluding: [id]).isEmpty)
        let unindexed = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T00-00-00-" + other + ".jsonl")
        try (meta(other) + event("task_started")).write(to: unindexed)
        XCTAssertEqual(reader.readCards(now: epoch).map(\.id), ["codex-" + id])
        let archive = home.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: archive.appendingPathComponent(file.lastPathComponent))
        XCTAssertTrue(reader.readCards(now: epoch.addingTimeInterval(11)).isEmpty)
    }

    func testMalformedAndUnknownRecordsNeverInventApprovalOrActivity() throws {
        let (_, _, reader) = try fixture(meta() + Data("not-json\n".utf8)
            + line("event_msg", ["type": "PermissionRequest", "tool_input": ["command": "PRIVATE"]]))
        let card = try XCTUnwrap(reader.readCards(now: epoch).first)
        XCTAssertEqual(card.main?.status, .quiet)
        XCTAssertFalse(card.main?.info.asking ?? true)
        XCTAssertTrue(card.main?.info.openTools.isEmpty ?? false)
        XCTAssertNil(card.main?.info.lastActivity)
    }

    func testTailWithoutTaskStartCanUseToolActivityButNotAnUnmatchedOutput() throws {
        let prefix = try meta() + event("task_started", turn: "old", at: -90)
            + event("task_complete", turn: "old", at: -80)
            + Data(repeating: 65, count: 2 * 1024 * 1024) + Data([10])
        let context = try line("turn_context", ["turn_id": "new", "model": "gpt-6-astra"])
        let (_, _, active) = try fixture(prefix + context + line("response_item", ["type": "custom_tool_call",
            "name": "exec", "call_id": "call", "input": "PRIVATE"]))
        let card = try XCTUnwrap(active.readCards(now: epoch).first)
        XCTAssertEqual(card.main?.status, .working)
        XCTAssertEqual(card.main?.info.model, "gpt-6-astra")
        let (_, _, unknown) = try fixture(prefix + context + line("response_item", ["type": "function_call_output",
            "call_id": "unseen", "output": "PRIVATE"]))
        XCTAssertEqual(unknown.readCards(now: epoch).first?.main?.status, .quiet)
    }

    func testUnchangedIncompleteEOFDoesNotSpendAnotherReadBudget() throws {
        let (_, file, reader) = try fixture(meta() + event("task_started"))
        _ = reader.readCards(now: epoch)
        let partial = try line("response_item", ["type": "message", "role": "assistant", "phase": "commentary",
                                                "content": String(repeating: "x", count: 400_000)], at: 1)
        try append(Data(partial.dropLast()), to: file, at: 1)
        _ = reader.readCards(now: epoch.addingTimeInterval(1))
        XCTAssertTrue(reader.lastReadBytes > 0)
        _ = reader.readCards(now: epoch.addingTimeInterval(2))
        XCTAssertEqual(reader.lastReadBytes, 0)
        try append(Data([10]) + event("task_complete", at: 3), to: file, at: 3)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(3)).first?.main?.status, .done)
    }

    func testCandidateCountAndReadBudgetStayBounded() throws {
        let (home, file, reader) = try fixture(meta() + event("task_started"))
        var index = try JSONSerialization.data(withJSONObject: ["id": id]) + Data([10])
        for number in 2...130 {
            let session = "01a1705b-6400-7000-8000-" + String(format: "%012x", number)
            let next = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-26T00-00-00-" + session + ".jsonl")
            try (meta(session) + event("task_started")).write(to: next)
            try FileManager.default.setAttributes([.modificationDate: epoch], ofItemAtPath: next.path)
            index += try JSONSerialization.data(withJSONObject: ["id": session]) + Data([10])
        }
        try index.write(to: home.appendingPathComponent("session_index.jsonl"))
        let cards = reader.readCards(now: epoch)
        XCTAssertEqual(cards.count, CodexLiveRollouts.maxCandidates)
        XCTAssertTrue(reader.lastReadBytes <= CodexLiveRollouts.maxReadBytes)
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
    }

    func testNullableParentIsRootButFutureMetadataAndInheritedActivityAreRejected() throws {
        let nullable = try line("session_meta", ["id": id, "source": "vscode", "cwd": "/tmp/project",
                                                 "timestamp": stamp(-100), "parent_thread_id": NSNull()], at: -100)
        let (_, _, root) = try fixture(nullable + event("task_started", at: -200))
        XCTAssertEqual(root.readCards(now: epoch).first?.main?.status, .quiet)
        let future = try line("session_meta", ["id": id, "source": "vscode", "timestamp": stamp(86400)], at: 86400)
        let (_, _, invalid) = try fixture(future)
        XCTAssertTrue(invalid.readCards(now: epoch).isEmpty)
    }

    func testAsyncQuestionFinalMessageDoesNotFinishTheTurnOrInventApproval() throws {
        let question: [String: Any] = ["type": "AgentMessage", "phase": "final_answer", "delivery": "async",
                                      "questions": [["title": "PRIVATE QUESTION", "options": ["PRIVATE OPTION"]]]]
        let (_, file, reader) = try fixture(meta() + event("task_started")
            + line("response_item", ["type": "custom_tool_call", "name": "exec", "call_id": "first", "input": "PRIVATE"])
            + line("event_msg", ["type": "item_completed", "thread_id": id, "turn_id": "turn-1", "item": question], at: 1))
        let card = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(1)).first)
        XCTAssertEqual(card.main?.status, .working)
        XCTAssertEqual(card.main?.step, "Bash")
        XCTAssertFalse(card.main?.info.turnEnded ?? true)
        XCTAssertFalse(card.main?.info.asking ?? true)
        XCTAssertEqual(card.main?.info.openTools.first?.input, [:])
        try append(line("response_item", ["type": "function_call", "name": "apply_patch", "call_id": "next"], at: 2), to: file, at: 2)
        let continued = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(2)).first)
        XCTAssertEqual(continued.main?.status, .working)
        XCTAssertEqual(continued.main?.step, "Edit")
        try append(event("task_complete", at: 3), to: file, at: 3)
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(3)).first?.main?.status, .done)
    }

    func testOrdinaryAsyncFinalWithNoQuestionsStillFinishes() throws {
        for questions: Any in [NSNull(), [Any]()] {
            let final: [String: Any] = ["type": "AgentMessage", "phase": "final_answer", "delivery": "async", "questions": questions]
            let (_, _, reader) = try fixture(meta() + event("task_started")
                + line("event_msg", ["type": "item_completed", "thread_id": id, "turn_id": "turn-1", "item": final], at: 1))
            XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .done)
        }
        let (_, _, reader) = try fixture(meta() + event("task_started")
            + line("event_msg", ["type": "item_completed", "thread_id": id, "turn_id": "turn-1",
                                 "item": ["type": "AgentMessage", "phase": "final_answer", "delivery": "async"]], at: 1))
        XCTAssertEqual(reader.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .done)
    }

    func testCompletionSurvivesNextTurnStartingBeforeTheNextPoll() throws {
        let (_, file, reader) = try fixture(meta() + event("task_started"))
        _ = reader.readCards(now: epoch)
        try append(event("task_complete", at: 40)
                   + event("task_started", turn: "next", at: 40.016), to: file, at: 41)
        let card = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(41)).first)
        XCTAssertEqual(card.main?.status, .working)
        XCTAssertEqual(card.main?.info.codexTurnID, "next")
        XCTAssertEqual(card.main?.info.codexCompletedTurns, [CodexTurnCompletion(
            turnID: "turn-1", startedAt: epoch, endedAt: epoch.addingTimeInterval(40))])
    }

    func testCompletionReceiptsAreBoundedAndAbortAndQuestionsDoNotCreateThem() throws {
        var body = try meta()
        for index in 0..<12 {
            body += try event("task_started", turn: "turn-\(index)", at: Double(index * 40))
            body += try event("task_complete", turn: "turn-\(index)", at: Double(index * 40 + 35))
        }
        body += try event("task_started", turn: "abort", at: 500)
        body += try line("response_item", ["type": "message", "role": "assistant", "phase": "final_answer",
                                          "questions": [["title": "PRIVATE"]]], at: 501)
        body += try event("turn_aborted", turn: "abort", at: 502)
        let (_, _, reader) = try fixture(body)
        let receipts = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(503)).first?.main?.info.codexCompletedTurns)
        XCTAssertEqual(receipts.count, CodexTurnCompletion.limit)
        XCTAssertEqual(receipts.first?.turnID, "turn-4")
        XCTAssertEqual(receipts.last?.turnID, "turn-11")
    }

    func testFinalAndTaskCompleteShareOneReceiptWithTheRealStart() throws {
        let (_, _, reader) = try fixture(meta() + event("task_started")
            + line("response_item", ["type": "message", "role": "assistant", "phase": "final"], at: 40)
            + event("task_complete", at: 40.01))
        let receipts = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(41)).first?.main?.info.codexCompletedTurns)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.startedAt, epoch)
        XCTAssertEqual(receipts.first?.endedAt, epoch.addingTimeInterval(40.01))
    }

    func testQuestionCardDoesNotReviveATurnAfterItsTaskComplete() throws {
        let question: [String: Any] = ["type": "AgentMessage", "phase": "final_answer", "delivery": "async",
                                      "questions": [["title": "PRIVATE", "options": []]]]
        let (_, _, reader) = try fixture(meta() + event("task_started") + event("task_complete", at: 1)
            + line("event_msg", ["type": "item_completed", "thread_id": id, "turn_id": "turn-1", "item": question], at: 2))
        let card = try XCTUnwrap(reader.readCards(now: epoch.addingTimeInterval(2)).first)
        XCTAssertEqual(card.main?.status, .done)
        XCTAssertEqual(card.main?.info.lastActivity, epoch.addingTimeInterval(1))
    }
}
