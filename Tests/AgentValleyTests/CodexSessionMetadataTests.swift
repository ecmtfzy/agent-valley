import Foundation
import XCTest
@testable import AgentValley

final class CodexSessionMetadataTests: XCTestCase {
    private let parent = "00000000-0000-4000-8000-000000000001"
    private let child = "00000000-0000-4000-8000-000000000002"
    private let other = "00000000-0000-4000-8000-000000000003"

    private final class Jobs {
        var queued: [() -> Void] = []
        func add(_ work: @escaping () -> Void) { queued.append(work) }
        func run() { if !queued.isEmpty { queued.removeFirst()() } }
    }

    private func card(_ id: String, child: String? = nil) -> SessionCard {
        let key = "codex-" + id
        var info = AgentInfo()
        info.cwd = "/tmp/project"
        info.folder = info.cwd
        info.model = "gpt-original"
        let main = AgentRow(id: key + "-main", info: info, status: .working, elapsed: 3)
        let children = child.map { [AgentRow(id: key + "-" + $0, info: AgentInfo(), status: .working, elapsed: 1)] } ?? []
        return SessionCard(id: key, project: "project", branch: "", main: main, agents: children, startedAt: .distantPast)
    }

    func testReadIsScheduledAndSuppliesRealTitleModelAndExactNavigation() throws {
        let jobs = Jobs()
        var reads = 0
        let desktop = OwnerApp(bundle: URL(fileURLWithPath: "/Applications/ChatGPT.app"), name: "ChatGPT")
        let cache = CodexSessionMetadata(now: { 0 }, reader: { id in
            reads += 1
            return ["thread_id": id, "status": "active", "name": "Review the parser", "model": "gpt-6-astra", "git_branch": "feature/parity"]
        }, desktop: desktop, schedule: jobs.add)
        let original = card(parent)
        XCTAssertEqual(cache.enrich(cards: [original]), [original])
        XCTAssertEqual(reads, 0)
        XCTAssertFalse(cache.canReceiveMessages(for: original.id))
        jobs.run()
        let shown = try XCTUnwrap(cache.enrich(cards: [original]).first)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(shown.title, "Review the parser")
        XCTAssertEqual(shown.main?.info.model, "gpt-6-astra")
        XCTAssertEqual(shown.branch, "feature/parity")
        XCTAssertEqual(shown.owner?.link?.absoluteString, "codex://threads/" + parent)
        XCTAssertEqual(shown.main?.status, original.main?.status)
        XCTAssertTrue(cache.canReceiveMessages(for: original.id))
    }

    func testChildDataRequiresTheExactParentAndNeverInheritsItsModel() throws {
        let jobs = Jobs()
        var time: TimeInterval = 0
        var childParent = other
        let cache = CodexSessionMetadata(now: { time }, reader: { id in
            if id == self.parent { return ["thread_id": id, "status": "idle", "model": "gpt-parent"] }
            return ["thread_id": id, "status": "active", "parent_thread_id": childParent,
                    "model": "gpt-child", "agent_role": "explorer", "task_preview": "Inspect the parser"]
        }, desktop: nil, schedule: jobs.add)
        let original = card(parent, child: child)
        _ = cache.enrich(cards: [original]); jobs.run()
        _ = cache.enrich(cards: [original]); jobs.run()
        XCTAssertEqual(cache.enrich(cards: [original]).first?.agents.first?.info.model, "")
        childParent = parent
        time = 31
        _ = cache.enrich(cards: [original]); jobs.run()
        _ = cache.enrich(cards: [original]); jobs.run()
        let shown = try XCTUnwrap(cache.enrich(cards: [original]).first?.agents.first)
        XCTAssertEqual(shown.info.model, "gpt-child")
        XCTAssertEqual(shown.info.task, "Inspect the parser")
        XCTAssertEqual(shown.info.type, "explorer")
    }

    func testFailureRetainsTitleButWithdrawsMessageRoutingAndBacksOff() throws {
        let jobs = Jobs()
        var time: TimeInterval = 0
        var fails = false
        var reads = 0
        let cache = CodexSessionMetadata(now: { time }, reader: { id in
            reads += 1
            return fails ? nil : ["thread_id": id, "status": "idle", "name": "Saved title"]
        }, desktop: nil, schedule: jobs.add)
        let original = card(parent)
        _ = cache.enrich(cards: [original]); jobs.run()
        XCTAssertTrue(cache.canReceiveMessages(for: original.id))
        time = 31; fails = true
        _ = cache.enrich(cards: [original]); jobs.run()
        XCTAssertEqual(cache.enrich(cards: [original]).first?.title, "Saved title")
        XCTAssertFalse(cache.canReceiveMessages(for: original.id))
        time = 70
        _ = cache.enrich(cards: [original]); jobs.run()
        XCTAssertEqual(reads, 2)
    }

    func testNotLoadedAndMismatchedSummariesNeverEnableMessageRouting() {
        let jobs = Jobs()
        let cache = CodexSessionMetadata(now: { 0 }, reader: { id in
            ["thread_id": id, "status": "notLoaded", "name": "Finished"]
        }, desktop: nil, schedule: jobs.add)
        let original = card(parent)
        _ = cache.enrich(cards: [original]); jobs.run()
        XCTAssertFalse(cache.canReceiveMessages(for: original.id))
        XCTAssertNil(CodexSessionMetadata.Details(["thread_id": other, "name": "Wrong"], expected: parent))
        XCTAssertNil(CodexSessionMetadata.link(threadID: parent + "?hostId=other"))
        XCTAssertNil(CodexSessionMetadata.link(threadID: "../another-thread"))
    }

    func testOnlyOneReadCanBeInFlightAndEveryCardGetsATurn() {
        let jobs = Jobs()
        var reads: [String] = []
        let cache = CodexSessionMetadata(now: { 0 }, reader: { id in
            reads.append(id)
            return ["thread_id": id, "status": "active"]
        }, desktop: nil, schedule: jobs.add)
        let cards = [card(parent), card(other)]
        for _ in 0..<5 { _ = cache.enrich(cards: cards) }
        XCTAssertEqual(jobs.queued.count, 1)
        jobs.run()
        _ = cache.enrich(cards: cards); jobs.run()
        XCTAssertEqual(Set(reads), Set([parent, other]))
    }

    func testDesktopOwnerRequiresTheVerifiedBundleAndScheme() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func bundle(_ name: String, identifier: String, scheme: String) throws -> URL {
            let app = directory.appendingPathComponent(name + ".app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleName": name,
                                       "CFBundleURLTypes": [["CFBundleURLSchemes": [scheme]]]]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }
        let wrong = try bundle("Wrong", identifier: "example.other", scheme: "codex")
        let noScheme = try bundle("NoScheme", identifier: "com.openai.codex", scheme: "other")
        let expected = try bundle("Expected", identifier: "com.openai.codex", scheme: "codex")
        XCTAssertNil(CodexSessionMetadata.desktopApp(at: wrong))
        XCTAssertNil(CodexSessionMetadata.desktopApp(at: noScheme))
        XCTAssertNotNil(CodexSessionMetadata.desktopApp(at: expected))
    }
}
