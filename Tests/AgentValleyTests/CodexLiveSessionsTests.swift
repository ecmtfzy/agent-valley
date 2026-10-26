import Foundation
import XCTest
@testable import AgentValley

final class CodexLiveSessionsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_792_972_800)

    private final class Jobs {
        var queued: [() -> Void] = []
        func add(_ work: @escaping () -> Void) { queued.append(work) }
        func run() { if !queued.isEmpty { queued.removeFirst()() } }
    }

    private func card(_ id: String = "codex-fixture", status: AgentStatus = .working,
                      activity: TimeInterval? = 0) -> SessionCard {
        var info = AgentInfo()
        info.startedAt = epoch.addingTimeInterval(-100)
        info.turnStartedAt = epoch.addingTimeInterval(-20)
        info.lastActivity = activity.map { epoch.addingTimeInterval($0) }
        info.turnEnded = status == .done
        info.model = "gpt-fixture"
        return SessionCard(id: id, project: "fixture", branch: "",
                           main: AgentRow(id: id + "-main", info: info, status: status, elapsed: 0),
                           agents: [], startedAt: epoch.addingTimeInterval(-100))
    }

    func testPendingReadNeverRunsInlineOrQueuesDuplicateWork() {
        let jobs = Jobs()
        let source = card()
        var requests: [(Date, TimeInterval, Set<String>)] = []
        let cache = CodexLiveSessions(read: { now, visible, excluded in
            requests.append((now, visible, excluded))
            return [source]
        }, schedule: jobs.add)
        let exclusions: Set<String> = ["codex-hook"]
        for second in 0..<20 {
            XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(Double(second)), visibleFor: 60,
                                      excluding: exclusions).isEmpty)
        }
        XCTAssertEqual(jobs.queued.count, 1)
        XCTAssertTrue(requests.isEmpty)
        jobs.run()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.0, epoch)
        XCTAssertEqual(requests.first?.1, 60)
        XCTAssertEqual(requests.first?.2, exclusions)
        XCTAssertEqual(cache.cards(now: epoch.addingTimeInterval(20), visibleFor: 60, excluding: []).map(\.id), [source.id])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(jobs.queued.count, 1)
    }

    func testHookArrivalImmediatelyExcludesCachedAndLateSnapshots() {
        let jobs = Jobs()
        let hooked = card("codex-hooked"), local = card("codex-local")
        var reads = 0
        let cache = CodexLiveSessions(read: { _, _, _ in
            reads += 1
            return [hooked, local]
        }, schedule: jobs.add)
        _ = cache.cards(now: epoch, visibleFor: 60, excluding: [])
        jobs.run()
        XCTAssertEqual(cache.cards(now: epoch.addingTimeInterval(1), visibleFor: 60, excluding: []).map(\.id),
                       [hooked.id, local.id])
        // The next read already captured an empty exclusion set. A new hook still wins
        // immediately, both while that read is pending and after its stale result arrives.
        XCTAssertEqual(cache.cards(now: epoch.addingTimeInterval(2), visibleFor: 60,
                                   excluding: [hooked.id]).map(\.id), [local.id])
        XCTAssertEqual(jobs.queued.count, 1)
        jobs.run()
        XCTAssertEqual(cache.cards(now: epoch.addingTimeInterval(3), visibleFor: 60,
                                   excluding: [hooked.id]).map(\.id), [local.id])
        XCTAssertEqual(reads, 2)
    }

    func testPendingRefreshAgesWorkingToQuietThenExpiresIt() throws {
        let jobs = Jobs()
        let source = card()
        var reads = 0
        let cache = CodexLiveSessions(read: { _, _, _ in reads += 1; return [source] }, schedule: jobs.add)
        _ = cache.cards(now: epoch, visibleFor: 60, excluding: [])
        jobs.run()
        let beforeQuiet = try XCTUnwrap(cache.cards(now: epoch.addingTimeInterval(AgentStore.stuckAfter - 1),
                                                   visibleFor: 60, excluding: []).first?.main)
        XCTAssertEqual(beforeQuiet.status, .working)
        let quiet = try XCTUnwrap(cache.cards(now: epoch.addingTimeInterval(AgentStore.stuckAfter),
                                             visibleFor: 60, excluding: []).first?.main)
        XCTAssertEqual(quiet.status, .quiet)
        XCTAssertTrue(quiet.calledBusy)
        XCTAssertEqual(quiet.quietFor, AgentStore.stuckAfter)
        XCTAssertEqual(quiet.elapsed, AgentStore.stuckAfter + 20)
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(AgentStore.forgetAfter), visibleFor: 60, excluding: []).isEmpty)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(jobs.queued.count, 1)
        // Even a slow refresh returning the same old working row cannot revive it.
        jobs.run()
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(AgentStore.forgetAfter + 1), visibleFor: 60, excluding: []).isEmpty)
    }

    func testFinishedRowsKeepFixedElapsedAndRespectCurrentRetention() throws {
        let jobs = Jobs()
        let source = card(status: .done)
        let cache = CodexLiveSessions(read: { _, _, _ in [source] }, schedule: jobs.add)
        _ = cache.cards(now: epoch, visibleFor: 60, excluding: [])
        jobs.run()
        let finished = try XCTUnwrap(cache.cards(now: epoch.addingTimeInterval(5), visibleFor: 10, excluding: []).first?.main)
        XCTAssertEqual(finished.status, .done)
        XCTAssertEqual(finished.elapsed, 20)
        XCTAssertEqual(finished.quietFor, 0)
        // A setting change must apply to the cached snapshot without waiting for disk.
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(5), visibleFor: 0, excluding: []).isEmpty)
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(5), visibleFor: -1, excluding: []).isEmpty)
        XCTAssertEqual(cache.cards(now: epoch.addingTimeInterval(9), visibleFor: 10, excluding: []).first?.main?.status, .done)
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(10), visibleFor: 10, excluding: []).isEmpty)
        XCTAssertEqual(jobs.queued.count, 1)
        jobs.run()
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(11), visibleFor: 10, excluding: []).isEmpty)
    }

    func testACompletedEmptyRefreshReplacesThePreviousSnapshot() {
        let jobs = Jobs()
        var next = [card()]
        let cache = CodexLiveSessions(read: { _, _, _ in next }, schedule: jobs.add)
        _ = cache.cards(now: epoch, visibleFor: 60, excluding: [])
        jobs.run()
        XCTAssertEqual(cache.cards(now: epoch.addingTimeInterval(1), visibleFor: 60, excluding: []).count, 1)
        next = []
        jobs.run()
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(2), visibleFor: 60, excluding: []).isEmpty)
    }

    func testRowsWithoutObservedActivityCannotBecomeCachedLiveCards() {
        let jobs = Jobs()
        let source = card(activity: nil)
        let cache = CodexLiveSessions(read: { _, _, _ in [source] }, schedule: jobs.add)
        _ = cache.cards(now: epoch, visibleFor: 60, excluding: [])
        jobs.run()
        XCTAssertTrue(cache.cards(now: epoch.addingTimeInterval(1), visibleFor: 60, excluding: []).isEmpty)
    }
}
