import Foundation
import XCTest
@testable import AgentValley

final class CodexStateSyncTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_792_800_000)

    private func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

    private func event(_ kind: String, at seconds: TimeInterval, turn: String? = "first",
                       tool: String? = nil, call: String? = nil, child: String? = nil) throws -> Data {
        var value: [String: Any] = ["version": 1, "event": kind, "session_id": "session-1",
            "timestamp": at(seconds).ISO8601Format(.init(includingFractionalSeconds: true)),
            "cwd": "/tmp/fixture", "model": "gpt-hook"]
        if let turn { value["turn_id"] = turn }
        if let tool { value["tool_name"] = tool }
        if let call { value["tool_use_id"] = call }
        if let child { value["agent_id"] = child; value["agent_type"] = "explore" }
        return try JSONSerialization.data(withJSONObject: value) + Data([10])
    }

    private func append(_ bytes: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
    }

    private func journal(_ work: (URL, CodexEventStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("events.jsonl")
        try Data().write(to: file)
        try work(file, CodexEventStore(path: file.path))
    }

    private func local(_ status: AgentStatus, turn: String? = "first", start: TimeInterval = 0,
                       activity: TimeInterval, id: String = "codex-session-1") -> SessionCard {
        var info = AgentInfo()
        info.codexTurnID = turn
        info.startedAt = at(-100)
        info.turnStartedAt = at(start)
        info.lastActivity = at(activity)
        info.turnEnded = status == .done
        info.model = "gpt-rollout"
        info.cwd = "/tmp/fixture"
        info.folder = info.cwd
        info.entrypoint = "codex-rollout"
        info.lastStep = "Rollout tool"
        return SessionCard(id: id, project: "fixture", branch: "",
                           main: AgentRow(id: id + "-main", info: info, status: status, elapsed: 0),
                           agents: [], startedAt: at(-100))
    }

    func testMissingStopUsesRealCompletionTimeAndCannotReviveAfterRetention() throws {
        try journal { file, store in
            // This callback was delivered after the turn had already ended in the rollout.
            try append(event("PreToolUse", at: 20, tool: "exec_command", call: "late"), to: file)
            let finished = local(.done, activity: 10)
            let card = try XCTUnwrap(store.readCards(now: at(20), visibleFor: 60, reconciling: [finished]).first)
            XCTAssertEqual(card.main?.status, .done)
            XCTAssertEqual(card.main?.info.lastActivity, at(10))
            XCTAssertEqual(card.main?.info.codexTurnID, "first")
            XCTAssertTrue(card.main?.info.openTools.isEmpty ?? false)
            XCTAssertEqual(store.readCards(now: at(30), visibleFor: 60, reconciling: [finished]).first?.main?.info.lastActivity, at(10))
            XCTAssertTrue(store.readCards(now: at(70), visibleFor: 60, reconciling: [finished]).isEmpty)
            XCTAssertTrue(store.observedSessionIDs.contains("codex-session-1"))
            try append(event("PreToolUse", at: 80, tool: "apply_patch", call: "later"), to: file)
            XCTAssertTrue(store.readCards(now: at(80), visibleFor: 60).isEmpty)
            XCTAssertTrue(store.readCards(now: at(10 + AgentStore.forgetAfter), visibleFor: 60).isEmpty)
            XCTAssertTrue(store.observedSessionIDs.isEmpty)
        }
    }

    func testRolloutConfirmsNewTurnWithoutPromptAndCanFinishIt() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "exec_command", call: "old"), to: file)
            _ = store.readCards(now: at(10), reconciling: [local(.done, activity: 10)])
            let next = local(.working, turn: "second", start: 20, activity: 21)
            var card = try XCTUnwrap(store.readCards(now: at(21), reconciling: [next]).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.info.turnStartedAt, at(20))
            XCTAssertEqual(card.main?.info.model, "gpt-rollout")
            XCTAssertTrue(card.main?.info.openTools.isEmpty ?? false)
            try append(event("PreToolUse", at: 22, turn: "second", tool: "apply_patch", call: "new"), to: file)
            card = try XCTUnwrap(store.readCards(now: at(22), reconciling: [next]).first)
            XCTAssertEqual(card.main?.info.openTools.map(\.id), ["new"])
            card = try XCTUnwrap(store.readCards(now: at(30), reconciling: [local(.done, turn: "second", start: 20, activity: 30)]).first)
            XCTAssertEqual(card.main?.status, .done)
            XCTAssertEqual(card.main?.info.lastActivity, at(30))
        }
    }

    func testOldTurnCompletionCannotOverrideNewHookTurnEvenWhenDeliveredLater() throws {
        try journal { file, store in
            try append(event("UserPromptSubmit", at: 0), to: file)
            try append(event("UserPromptSubmit", at: 20, turn: "second"), to: file)
            try append(event("PreToolUse", at: 21, turn: "second", tool: "exec_command", call: "new"), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(30), reconciling: [local(.done, activity: 30)]).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.info.openTools.map(\.id), ["new"])
            XCTAssertEqual(card.main?.info.lastActivity, at(21))
        }
    }

    func testLateOldToolDeliveryCannotBlockANewerConfirmedTurn() throws {
        try journal { file, store in
            try append(event("UserPromptSubmit", at: 10), to: file)
            try append(event("PreToolUse", at: 50, tool: "exec_command", call: "late-old"), to: file)
            let next = local(.working, turn: "second", start: 30, activity: 60)
            var card = try XCTUnwrap(store.readCards(now: at(60), reconciling: [next]).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.info.turnStartedAt, at(30))
            XCTAssertTrue(card.main?.info.openTools.isEmpty ?? false)
            try append(event("PreToolUse", at: 80, tool: "exec_command", call: "even-later-old"), to: file)
            card = try XCTUnwrap(store.readCards(now: at(80), reconciling: [local(.done, turn: "second", start: 30, activity: 70)]).first)
            XCTAssertEqual(card.main?.status, .done)
            XCTAssertEqual(card.main?.info.lastActivity, at(70))
        }
    }

    func testOlderPromptInLaterJournalBatchCannotRetireConfirmedNewTurn() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "exec_command", call: "old"), to: file)
            let next = local(.working, turn: "second", start: 20, activity: 30)
            XCTAssertEqual(store.readCards(now: at(30), reconciling: [next]).first?.main?.info.codexTurnID, "second")
            try append(event("UserPromptSubmit", at: 10, turn: "intermediate"), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(40), reconciling: [local(.done, turn: "second", start: 20, activity: 40)]).first)
            XCTAssertEqual(card.main?.status, .done)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.info.turnStartedAt, at(20))
            XCTAssertEqual(card.main?.info.lastActivity, at(40))
        }
    }

    func testOlderSessionEndCannotCloseNewTurnWhileOlderChildStopStillApplies() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "exec_command", call: "old"), to: file)
            try append(event("SubagentStart", at: 1, child: "child"), to: file)
            let next = local(.working, turn: "second", start: 20, activity: 30)
            _ = store.readCards(now: at(30), reconciling: [next])
            try append(event("SessionEnd", at: 10), to: file)
            try append(event("SubagentStop", at: 15, child: "child"), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(31), reconciling: [next]).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.info.lastActivity, at(30))
            XCTAssertFalse(card.closed)
            XCTAssertEqual(card.agents.first?.status, .done)
        }
    }

    func testOlderStopWithoutTurnIDCannotEndConfirmedNewTurn() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "exec_command", call: "old"), to: file)
            let next = local(.working, turn: "second", start: 20, activity: 30)
            _ = store.readCards(now: at(30), reconciling: [next])
            try append(event("Stop", at: 10, turn: nil), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(31), reconciling: [next]).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.info.lastActivity, at(30))
            XCTAssertEqual(store.readCards(now: at(40), reconciling: [local(.done, turn: "second", start: 20, activity: 40)]).first?.main?.status, .done)
        }
    }

    func testRetiredTurnSessionEndCannotClearCurrentPermissionEvenWithLaterDeliveryTime() throws {
        try journal { file, store in
            try append(event("UserPromptSubmit", at: 0), to: file)
            try append(event("UserPromptSubmit", at: 20, turn: "second"), to: file)
            try append(event("PreToolUse", at: 21, turn: "second", tool: "exec_command", call: "new"), to: file)
            try append(event("PermissionRequest", at: 22, turn: "second", tool: "exec_command"), to: file)
            _ = store.readCards(now: at(22))
            let tokens = store.pendingApprovalTokens
            XCTAssertFalse(tokens.isEmpty)
            try append(event("SessionEnd", at: 50), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(50), reconciling: [local(.working, turn: "second", start: 20, activity: 30)]).first)
            XCTAssertEqual(card.main?.status, .needsYou)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(store.pendingApprovalTokens, tokens)
            XCTAssertFalse(card.closed)
            try append(event("SessionEnd", at: 60, turn: "second"), to: file)
            let closed = try XCTUnwrap(store.readCards(now: at(60)).first)
            XCTAssertEqual(closed.main?.status, .done)
            XCTAssertTrue(closed.closed)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
        }
    }

    func testCurrentPermissionAndRichHookStepSurviveActivityUntilExplicitCompletion() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "exec_command", call: "shell"), to: file)
            try append(event("PermissionRequest", at: 1, tool: "exec_command"), to: file)
            let original = try XCTUnwrap(store.readCards(now: at(1)).first?.main)
            let tokens = store.pendingApprovalTokens
            XCTAssertFalse(tokens.isEmpty)
            let active = local(.working, activity: 20)
            let waiting = try XCTUnwrap(store.readCards(now: at(20), reconciling: [active]).first?.main)
            XCTAssertEqual(waiting.status, .needsYou)
            XCTAssertEqual(waiting.info.lastStep, original.info.lastStep)
            XCTAssertEqual(waiting.info.lastStepAsRun, original.info.lastStepAsRun)
            XCTAssertEqual(waiting.info.lastActivity, at(1))
            XCTAssertEqual(store.pendingApprovalTokens, tokens)
            XCTAssertEqual(store.readCards(now: at(30), reconciling: [local(.done, activity: 30)]).first?.main?.status, .done)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
        }
    }

    func testFinishingParentDoesNotFinishItsIndependentChildren() throws {
        try journal { file, store in
            try append(event("UserPromptSubmit", at: 0), to: file)
            try append(event("SubagentStart", at: 1, child: "child"), to: file)
            var card = try XCTUnwrap(store.readCards(now: at(10), reconciling: [local(.done, activity: 10)]).first)
            XCTAssertEqual(card.main?.status, .done)
            XCTAssertEqual(card.agents.first?.status, .working)
            try append(event("SubagentStop", at: 11, child: "child"), to: file)
            card = try XCTUnwrap(store.readCards(now: at(11), reconciling: [local(.done, activity: 10)]).first)
            XCTAssertEqual(card.main?.info.lastActivity, at(10))
            XCTAssertEqual(card.agents.first?.status, .done)
        }
    }

    func testPermissionArrivingBeforeNewTurnEvidenceIsReplayedOnlyAfterConfirmation() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "apply_patch", call: "old"), to: file)
            try append(event("PreToolUse", at: 20, turn: "second", tool: "exec_command", call: "new"), to: file)
            try append(event("PermissionRequest", at: 21, turn: "second", tool: "exec_command"), to: file)
            var card = try XCTUnwrap(store.readCards(now: at(21)).first)
            XCTAssertEqual(card.main?.info.codexTurnID, "first")
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
            let active = local(.working, turn: "second", start: 10, activity: 15)
            card = try XCTUnwrap(store.readCards(now: at(22), reconciling: [active]).first)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertEqual(card.main?.status, .needsYou)
            XCTAssertEqual(card.main?.info.openTools.map(\.id), ["new"])
            XCTAssertFalse(store.pendingApprovalTokens.isEmpty)
            XCTAssertEqual(store.readCards(now: at(30), reconciling: [local(.done, turn: "second", start: 10, activity: 30)]).first?.main?.status, .done)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
        }
    }

    func testRealPromptCanAlsoConfirmDeferredPermissionWithoutRollout() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "apply_patch", call: "old"), to: file)
            try append(event("PreToolUse", at: 10, turn: "second", tool: "exec_command", call: "new"), to: file)
            try append(event("PermissionRequest", at: 11, turn: "second", tool: "exec_command"), to: file)
            _ = store.readCards(now: at(11))
            // The earlier prompt record is encountered in a later journal batch.
            try append(event("UserPromptSubmit", at: 8, turn: "second"), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(12)).first)
            XCTAssertEqual(card.main?.status, .needsYou)
            XCTAssertEqual(card.main?.info.codexTurnID, "second")
            XCTAssertFalse(store.pendingApprovalTokens.isEmpty)
        }
    }

    func testDeferredUnknownTurnCannotReviveAfterItsConfirmedCompletion() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "apply_patch", call: "old"), to: file)
            try append(event("PermissionRequest", at: 20, turn: "second", tool: "exec_command"), to: file)
            _ = store.readCards(now: at(20))
            let finished = local(.done, turn: "second", start: 10, activity: 15)
            XCTAssertEqual(store.readCards(now: at(21), reconciling: [finished]).first?.main?.status, .done)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
            XCTAssertTrue(store.readCards(now: at(75), visibleFor: 60, reconciling: [finished]).isEmpty)
        }
    }

    func testDeferredQueueIsBoundedAndCannotGrantPermissionFromEvictedMetadata() throws {
        for (selected, expected) in [(0, AgentStatus.working), (256, AgentStatus.needsYou)] {
            try journal { file, store in
                try append(event("PreToolUse", at: 0, tool: "apply_patch", call: "old"), to: file)
                for index in 0...256 {
                    try append(event("PermissionRequest", at: Double(index + 1), turn: "future-\(index)", tool: "exec_command"), to: file)
                }
                _ = store.readCards(now: at(300))
                let active = local(.working, turn: "future-\(selected)", start: 0.5, activity: 300)
                XCTAssertEqual(store.readCards(now: at(300), reconciling: [active]).first?.main?.status, expected)
                // No request has an identifiable matching open call; never invent a recovery token.
                XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
            }
        }
    }

    func testOldSameIDCompletionCannotStopExplicitPromptContinuation() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 0, tool: "apply_patch", call: "old"), to: file)
            let finished = local(.done, activity: 10)
            _ = store.readCards(now: at(10), reconciling: [finished])
            try append(event("UserPromptSubmit", at: 20), to: file)
            try append(event("PreToolUse", at: 21, tool: "exec_command", call: "new"), to: file)
            let card = try XCTUnwrap(store.readCards(now: at(21), reconciling: [finished]).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.turnStartedAt, at(20))
            XCTAssertEqual(card.main?.info.openTools.map(\.id), ["new"])
        }
    }

    func testUnknownHookTurnRequiresNewerEvidenceAndFinishedRowsDoNotResumeByActivity() throws {
        try journal { file, store in
            try append(event("PreToolUse", at: 10, turn: nil, tool: "exec_command", call: "call"), to: file)
            XCTAssertEqual(store.readCards(now: at(10), reconciling: [local(.done, activity: 5)]).first?.main?.status, .working)
            XCTAssertEqual(store.readCards(now: at(11), reconciling: [local(.done, turn: nil, activity: 11)]).first?.main?.status, .done)
            XCTAssertEqual(store.readCards(now: at(12), reconciling: [local(.working, turn: nil, activity: 12)]).first?.main?.status, .done)
        }
    }

    func testRolloutAloneCannotCreateAHookIdentityOrRecoveryToken() throws {
        try journal { _, store in
            XCTAssertTrue(store.readCards(now: at(1), reconciling: [local(.working, activity: 1)]).isEmpty)
            XCTAssertTrue(store.observedSessionIDs.isEmpty)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
        }
    }
}
