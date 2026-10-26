import Foundation
import XCTest
@testable import AgentValley

final class CodexEventsTests: XCTestCase {
    func testInstalledJournalEnablesFinderLaunchAndEnvironmentOverridesIt() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertNil(CodexEventStore.configuredJournal(environment: [:], home: home))
        let journal = home.appendingPathComponent("Library/Application Support/AgentValley/codex/events.jsonl")
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: journal)
        XCTAssertEqual(CodexEventStore.configuredJournal(environment: [:], home: home), journal)
        XCTAssertEqual(CodexEventStore.configuredJournal(environment: [CodexEventStore.environmentKey: "/tmp/override.jsonl"], home: home)?.path, "/tmp/override.jsonl")
        XCTAssertNil(CodexEventStore.configuredJournal(environment: [CodexEventStore.environmentKey: "relative.jsonl"], home: home))
    }

    private let epoch = Date(timeIntervalSince1970: 1_792_800_000)

    private func event(_ name: String, at seconds: TimeInterval = 0, session: String = "session-1", turn: String? = nil,
                       tool: String? = nil, toolID: String? = nil, agent: String? = nil, cwd: String = "/tmp/project",
                       request: String? = nil, decision: String? = nil, display: [String: String]? = nil) throws -> Data {
        var object: [String: Any] = ["version": 1, "event": name, "session_id": session,
                                     "cwd": cwd, "model": "gpt-example",
                                     "timestamp": epoch.addingTimeInterval(seconds).ISO8601Format(.init(includingFractionalSeconds: true))]
        if let turn { object["turn_id"] = turn }
        if let tool { object["tool_name"] = tool }
        if let toolID { object["tool_use_id"] = toolID }
        if let agent { object["agent_id"] = agent; object["agent_type"] = "explore" }
        if let request { object["request_id"] = request }
        if let decision { object["decision"] = decision }
        if let display { object["display_input"] = display }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
    }

    private func withJournal(_ work: (URL, CodexEventStore) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("events.jsonl")
        try Data().write(to: file)
        try work(file, CodexEventStore(path: file.path))
    }

    private func append(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func testSessionStartIsQuietAndToolsAnimateOnlyWhileOpen() throws {
        try withJournal { file, store in
            try append(event("SessionStart"), to: file)
            var card = try XCTUnwrap(store.readCards(now: epoch).first)
            XCTAssertEqual(card.main?.status, .quiet)
            XCTAssertEqual(card.id, "codex-session-1")
            XCTAssertEqual(AnswerStore.sessionID(of: card), "codex-session-1")
            XCTAssertEqual(card.title, "")
            XCTAssertEqual(card.name, "project")
            XCTAssertEqual(card.main?.step, "")
            XCTAssertNil(card.owner)
            try append(event("UserPromptSubmit", at: 1, turn: "turn-1"), to: file)
            try append(event("PreToolUse", at: 2, turn: "turn-1", tool: "functions.exec_command", toolID: "call:1.2"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(2)).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.activity, .running)
            XCTAssertEqual(card.main?.info.steps, 1)
            XCTAssertEqual(card.main?.step, "Bash")
            XCTAssertEqual(card.main?.info.openTools.first?.input, [:])
            try append(event("PostToolUse", at: 3, turn: "turn-1", tool: "functions.exec_command", toolID: "call:1.2"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(3)).first)
            XCTAssertEqual(card.main?.activity, .thinking)
            XCTAssertEqual(card.main?.info.openTools.count, 0)
            XCTAssertEqual(card.main?.step, "Bash")
        }
    }

    func testProjectPathsDoNotTriggerGitFileReadsOnThePollingQueue() throws {
        try withJournal { file, store in
            let checkout = file.deletingLastPathComponent().appendingPathComponent("project")
            let git = checkout.appendingPathComponent(".git")
            let first = checkout.appendingPathComponent("Sources")
            let latest = checkout.appendingPathComponent("Tests")
            for directory in [git, first, latest] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data("ref: refs/heads/feature/parity\n".utf8).write(to: git.appendingPathComponent("HEAD"))
            try append(event("SessionStart", cwd: first.path), to: file)
            try append(event("UserPromptSubmit", at: 1, cwd: latest.path), to: file)
            let card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(1)).first)
            XCTAssertEqual(card.name, "Sources")
            XCTAssertEqual(card.project, "Sources")
            XCTAssertEqual(card.repo, Projects.name(of: first.path, home: NSHomeDirectory()))
            // A real local HEAD is deliberately not consulted here. Daemon branch
            // enrichment is covered separately by CodexSessionMetadataTests.
            XCTAssertNil(card.git)
            XCTAssertEqual(card.branch, "")
            XCTAssertFalse(card.worktree)
            XCTAssertEqual(card.main?.info.cwd, first.path)
            XCTAssertEqual(card.main?.info.folder, latest.path)
        }
    }

    func testPermissionSurvivesAnUnrelatedConcurrentToolResult() throws {
        try withJournal { file, store in
            // Missing SessionStart and prompt callbacks still give a useful view.
            try append(event("PreToolUse", tool: "apply_patch", toolID: "edit"), to: file)
            // The documented PermissionRequest payload has a tool name but no tool-use id.
            try append(event("PermissionRequest", at: 1, tool: "apply_patch"), to: file)
            try append(event("PreToolUse", at: 2, tool: "exec_command", toolID: "read"), to: file)
            try append(event("PostToolUse", at: 3, tool: "exec_command", toolID: "read"), to: file)
            var card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(3)).first)
            XCTAssertEqual(card.main?.status, .needsYou)
            XCTAssertEqual(card.main?.step, "Edit")
            XCTAssertFalse(card.main?.info.asking ?? true)
            try append(event("PostToolUse", at: 4, tool: "apply_patch", toolID: "edit"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(4)).first)
            XCTAssertEqual(card.main?.status, .working)
        }
    }

    func testPermissionWithoutIDStaysUnresolvedWhenMatchingToolsAreAmbiguous() throws {
        try withJournal { file, store in
            try append(event("PreToolUse", tool: "apply_patch", toolID: "first"), to: file)
            try append(event("PreToolUse", at: 1, tool: "apply_patch", toolID: "second"), to: file)
            try append(event("PermissionRequest", at: 2, tool: "apply_patch"), to: file)
            try append(event("PostToolUse", at: 3, tool: "apply_patch", toolID: "first"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(3)).first?.main?.status, .needsYou)
            try append(event("PostToolUse", at: 4, tool: "apply_patch", toolID: "second"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(4)).first?.main?.status, .needsYou)
            try append(event("UserPromptSubmit", at: 5), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(5)).first?.main?.status, .working)
        }
    }

    func testRuntimeRecoveryTokenIsOnlyIssuedForAnUnambiguousSingleApproval() throws {
        try withJournal { file, store in
            try append(event("PreToolUse", tool: "apply_patch", toolID: "first"), to: file)
            try append(event("PermissionRequest", at: 1, tool: "apply_patch"), to: file)
            _ = store.readCards(now: epoch.addingTimeInterval(1))
            XCTAssertNotNil(store.pendingApprovalTokens["codex-session-1"])
            try append(event("PreToolUse", at: 2, tool: "exec_command", toolID: "second"), to: file)
            try append(event("PermissionRequest", at: 3, tool: "exec_command"), to: file)
            _ = store.readCards(now: epoch.addingTimeInterval(3))
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
            try append(event("PostToolUse", at: 4, tool: "apply_patch", toolID: "first"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(4)).first?.main?.status, .needsYou)
            XCTAssertTrue(store.pendingApprovalTokens.isEmpty)
        }
    }

    func testExplicitPermissionResolutionClearsOnlyItsOwnConcurrentRequest() throws {
        try withJournal { file, store in
            let first = "00000000-0000-4000-8000-000000000001"
            let second = "00000000-0000-4000-8000-000000000002"
            try append(event("PreToolUse", tool: "apply_patch", toolID: "edit"), to: file)
            try append(event("PermissionRequest", at: 1, tool: "apply_patch", request: first), to: file)
            try append(event("PreToolUse", at: 2, tool: "exec_command", toolID: "shell"), to: file)
            try append(event("PermissionRequest", at: 3, tool: "exec_command", request: second), to: file)
            try append(event("PermissionResolved", at: 4, request: first, decision: "allow"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(4)).first?.main?.status, .needsYou)
            try append(event("PermissionResolved", at: 5, request: second, decision: "deny"), to: file)
            let card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(5)).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.openTools.count, 2)
            XCTAssertEqual(card.main?.step, "Bash")
        }
    }

    func testDisplaySummaryUsesSharedToolLabelsWithoutBecomingApprovalInput() throws {
        try withJournal { file, store in
            let request = "00000000-0000-4000-8000-000000000006"
            try append(event("PreToolUse", tool: "exec_command", toolID: "shell",
                             display: ["description": "Run the checks", "command": "npm test"]), to: file)
            var card = try XCTUnwrap(store.readCards(now: epoch).first)
            XCTAssertEqual(card.main?.step, "Bash Run the checks")
            XCTAssertEqual(card.main?.info.openTools.first?.input, [:])
            try append(event("PermissionRequest", at: 1, tool: "exec_command", request: request), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(1)).first)
            XCTAssertEqual(card.main?.step, "Bash npm test")
            try append(event("PermissionResolved", at: 2, request: request, decision: "allow"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(2)).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.step, "Bash Run the checks")
            XCTAssertEqual(card.main?.info.openTools.first?.input, [:])
        }
    }

    func testUnmatchedRequestsResolveByTheirOwnIDWithoutClearingLegacyWaits() throws {
        try withJournal { file, store in
            let request = "00000000-0000-4000-8000-000000000003"
            try append(event("PermissionRequest", tool: "exec_command", request: request), to: file)
            try append(event("PermissionResolved", at: 1, request: "00000000-0000-4000-8000-000000000099", decision: "allow"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .needsYou)
            try append(event("PermissionRequest", at: 2, tool: "apply_patch"), to: file)
            try append(event("PermissionResolved", at: 3, request: request, decision: "allow"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(3)).first?.main?.status, .needsYou)
        }
    }

    func testOldOrInvalidPermissionResolutionCannotChangeANewTurn() throws {
        try withJournal { file, store in
            let old = "00000000-0000-4000-8000-000000000004"
            let new = "00000000-0000-4000-8000-000000000005"
            try append(event("UserPromptSubmit", turn: "old"), to: file)
            try append(event("PermissionRequest", at: 1, turn: "old", request: old), to: file)
            try append(event("UserPromptSubmit", at: 2, turn: "new"), to: file)
            try append(event("PermissionRequest", at: 3, turn: "new", request: new), to: file)
            try append(event("PermissionResolved", at: 4, turn: "old", request: old, decision: "allow"), to: file)
            try append(event("PermissionResolved", at: 5, turn: "new", request: new, decision: "maybe"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(5)).first?.main?.status, .needsYou)
            try append(event("PermissionResolved", at: 6, turn: "new", request: new, decision: "allow"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(6)).first?.main?.status, .working)
        }
    }

    func testChildCanFinishAfterTheParentTurnWithoutChangingTheParent() throws {
        try withJournal { file, store in
            try append(event("UserPromptSubmit", turn: "turn-1"), to: file)
            try append(event("SubagentStart", at: 1, turn: "turn-1", agent: "child-1"), to: file)
            var card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(1)).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.agents.first?.id, "codex-session-1-child-1")
            XCTAssertEqual(card.agents.first?.info.model, "")
            XCTAssertEqual(card.agents.first?.info.task, "")
            XCTAssertEqual(card.agents.first?.info.steps, 0)
            try append(event("Stop", at: 2, turn: "turn-1"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(2)).first)
            XCTAssertEqual(card.main?.status, .done)
            XCTAssertEqual(card.agents.first?.status, .working)
            XCTAssertEqual(card.workingAfterMain, 1)
            try append(event("SubagentStop", at: 3, turn: "turn-1", agent: "child-1"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(3)).first)
            XCTAssertTrue(card.isIdle)
            XCTAssertFalse(card.closed)
        }
    }

    func testOldTurnCallbacksDoNotOverwriteNewWorkAndSameTurnCanResume() throws {
        try withJournal { file, store in
            try append(event("UserPromptSubmit", turn: "old"), to: file)
            try append(event("Stop", at: 1, turn: "old"), to: file)
            try append(event("UserPromptSubmit", at: 2, turn: "new"), to: file)
            try append(event("PermissionRequest", at: 3, turn: "old", toolID: "old-call"), to: file)
            try append(event("Stop", at: 4, turn: "old"), to: file)
            var card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(4)).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.info.turnStartedAt, epoch.addingTimeInterval(2))
            try append(event("Stop", at: 5, turn: "new"), to: file)
            try append(event("PostToolUse", at: 6, tool: "exec_command", toolID: "late-call"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(6)).first)
            XCTAssertEqual(card.main?.status, .done)
            try append(event("UserPromptSubmit", at: 7, turn: "new"), to: file)
            try append(event("PreToolUse", at: 8, turn: "new", tool: "apply_patch", toolID: "new-call"), to: file)
            card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(8)).first)
            XCTAssertEqual(card.main?.status, .working)
            XCTAssertEqual(card.main?.activity, .typing)
        }
    }

    func testIncompleteMalformedAndOversizeLinesDoNotLoseFollowingEvents() throws {
        try withJournal { file, store in
            let first = try event("UserPromptSubmit", turn: "turn-1")
            try append(Data(first.dropLast()), to: file)
            XCTAssertTrue(store.readCards(now: epoch).isEmpty)
            try append(Data([10]), to: file)
            XCTAssertEqual(store.readCards(now: epoch).first?.main?.status, .working)
            try append(Data("not JSON\n".utf8), to: file)
            try append(Data(repeating: 65, count: CodexEventStore.maxEventBytes + 1), to: file)
            _ = store.readCards(now: epoch)
            try append(Data([10]) + event("Stop", at: 1, turn: "turn-1"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .done)
        }
    }

    func testTruncateAndAtomicReplacementResetOldState() throws {
        try withJournal { file, store in
            try append(event("UserPromptSubmit", session: "old-session"), to: file)
            XCTAssertEqual(store.readCards(now: epoch).count, 1)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 0)
            try handle.close()
            XCTAssertTrue(store.readCards(now: epoch).isEmpty)
            try event("SessionStart", session: "replacement").write(to: file, options: .atomic)
            XCTAssertEqual(store.readCards(now: epoch).map(\.id), ["codex-replacement"])
        }
    }

    func testSessionEndClosesChildrenButStopOnlyEndsTheTurn() throws {
        try withJournal { file, store in
            try append(event("UserPromptSubmit"), to: file)
            try append(event("SubagentStart", at: 1, agent: "child"), to: file)
            try append(event("SessionEnd", at: 2), to: file)
            let card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(2)).first)
            XCTAssertTrue(card.closed)
            XCTAssertTrue(card.isIdle)
            XCTAssertTrue(store.readCards(now: epoch.addingTimeInterval(12), visibleFor: 10).isEmpty)
        }
    }

    func testSilenceIsQuietInsteadOfInventedCompletionAndEventuallyExpires() throws {
        try withJournal { file, store in
            try append(event("UserPromptSubmit"), to: file)
            let card = try XCTUnwrap(store.readCards(now: epoch.addingTimeInterval(AgentStore.stuckAfter)).first)
            XCTAssertEqual(card.main?.status, .quiet)
            XCTAssertTrue(card.main?.calledBusy ?? false)
            XCTAssertFalse(card.isIdle)
            XCTAssertTrue(store.readCards(now: epoch.addingTimeInterval(AgentStore.forgetAfter)).isEmpty)
        }
    }

    func testCompactionEventsAndPermissionExpiry() throws {
        try withJournal { file, store in
            try append(event("PreCompact"), to: file)
            XCTAssertEqual(store.readCards(now: epoch).first?.main?.step, "")
            try append(event("PostCompact", at: 1), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(1)).first?.main?.step, "")
            try append(event("PermissionRequest", at: 2, toolID: "call"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(2)).first?.main?.status, .needsYou)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(2 + AgentStore.askingVisibleFor)).first?.main?.status, .quiet)
        }
    }

    func testUnknownVersionAndUnsafeSessionIDAreIgnored() throws {
        try withJournal { file, store in
            try append(Data("{\"version\":2,\"event\":\"SessionStart\",\"session_id\":\"unknown\",\"timestamp\":\"2026-10-23T00:00:00.000Z\"}\n".utf8), to: file)
            try append(event("SessionStart", session: "../not-a-session"), to: file)
            XCTAssertTrue(store.readCards(now: epoch).isEmpty)
            try append(event("SessionStart", session: "valid:id.1"), to: file)
            XCTAssertEqual(store.readCards(now: epoch).first?.id, "codex-valid:id.1")
        }
    }

    func testJournalSymlinkIsNotFollowed() throws {
        try withJournal { file, _ in
            try append(event("SessionStart"), to: file)
            let link = file.deletingLastPathComponent().appendingPathComponent("linked.jsonl")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            XCTAssertTrue(CodexEventStore(path: link.path).readCards(now: epoch).isEmpty)
        }
    }

    func testDiagnosticDrainsBeyondTheFirstPollingBatch() throws {
        try withJournal { file, store in
            try append(event("UserPromptSubmit", turn: "turn-1"), to: file)
            try append(Data(repeating: 65, count: CodexEventStore.maxReadBytes) + Data([10]), to: file)
            try append(event("Stop", at: 1, turn: "turn-1"), to: file)
            XCTAssertEqual(store.readCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .working)
            XCTAssertEqual(store.readAllCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .done)
            XCTAssertEqual(CodexEventStore(path: file.path).readAllCards(now: epoch.addingTimeInterval(1)).first?.main?.status, .done)
        }
    }
}
