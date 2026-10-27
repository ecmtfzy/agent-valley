import XCTest
@testable import AgentValley

/// Stands in for the Keychain and the network: counts what the client asks for and answers on demand.
private final class FakeSource: PlanLimitsSource {
    var fetchTimeout: TimeInterval = 60
    private(set) var fetches = 0
    private(set) var cancels = 0
    private var waiting: [(Result<PlanLimits, LimitsFailure>) -> Void] = []

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        fetches += 1
        waiting.append(done)
        return { [weak self] in self?.cancels += 1 }
    }

    /// Answers the fetch at `index`, or the latest one.
    /// A nil answer is a failed fetch, for `reason`.
    func answer(_ limits: PlanLimits?, because reason: LimitsFailure = .offline, fetch index: Int? = nil) {
        let index = index ?? waiting.count - 1
        guard waiting.indices.contains(index) else { return XCTFail("fetch \(index) was never started") }
        waiting[index](limits.map(Result.success) ?? .failure(reason))
    }
}

private final class RetryScheduler {
    final class Job {
        let delay: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(delay: TimeInterval, action: @escaping () -> Void) { self.delay = delay; self.action = action }
    }
    private(set) var jobs: [Job] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        let job = Job(delay: delay, action: action)
        jobs.append(job)
        return { job.cancelled = true }
    }
    // Even a cancelled action may already be queued; the client's generation must reject it.
    func fire(_ index: Int) { jobs[index].action() }
}

final class PlanLimitsClientTests: XCTestCase {
    private var source: FakeSource!
    private var client: PlanLimitsClient!
    private var scheduler: RetryScheduler!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let some = PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil)

    override func setUp() {
        source = FakeSource()
        scheduler = RetryScheduler()
        client = PlanLimitsClient(source: source, now: { [unowned self] in self.clock }, schedule: scheduler.schedule)
    }

    override func tearDown() {
        client.setEnabled(false)
    }

    // "Plan limits" off: the Keychain and the network are never asked.
    func testWhileOffTheSourceIsNeverAsked() {
        client.refreshIfStale()
        client.tick()
        XCTAssertEqual(source.fetches, 0)

        client.setEnabled(true)
        XCTAssertEqual(source.fetches, 1)
        source.answer(some)

        client.setEnabled(false)
        clock += 3600
        client.refreshIfStale()
        client.tick()
        XCTAssertEqual(source.fetches, 1)
        XCTAssertNil(client.limits)
    }

    func testTurningOffCancelsTheFetchInFlightAndIgnoresItsAnswer() {
        client.setEnabled(true)
        client.setEnabled(false)
        XCTAssertEqual(source.cancels, 1)

        source.answer(some)
        XCTAssertNil(client.limits)

        // Back on: a fresh fetch starts, and the old answer arriving late still changes nothing.
        client.setEnabled(true)
        XCTAssertEqual(source.fetches, 2)
        source.answer(some, fetch: 0)
        XCTAssertNil(client.limits)
        source.answer(some, fetch: 1)
        XCTAssertEqual(client.limits, some)
    }

    func testOpeningThePanelRefetchesOnlyAfterAMinute() {
        client.setEnabled(true)
        source.answer(some)
        client.refreshIfStale()
        clock += 59
        client.refreshIfStale()
        XCTAssertEqual(source.fetches, 1)
        clock += 2
        client.refreshIfStale()
        XCTAssertEqual(source.fetches, 2)
    }

    // Numbers must not stay up indefinitely just because nothing ever answers again.
    func testNumbersExpireAfterFifteenMinutesEvenIfNoFetchEverFinishes() {
        client.setEnabled(true)
        source.answer(some)
        clock += 300
        client.tick()
        XCTAssertEqual(client.limits, some)
        clock += 300
        client.tick()
        XCTAssertEqual(client.limits, some)
        clock += 301
        client.tick()
        XCTAssertNil(client.limits)
    }

    // The status row must say why there are no numbers, not just leave a gap.
    func testDisplayFollowsTheFetch() {
        XCTAssertEqual(client.display, .off)
        client.setEnabled(true)
        XCTAssertEqual(client.display, .loading)
        source.answer(some)
        XCTAssertEqual(client.display, .limits(some, asOf: nil))

        // A refresh fails: the last numbers stay, with the time they are from.
        let fetched = clock
        clock += 300
        client.tick()
        source.answer(nil)
        XCTAssertEqual(client.display, .limits(some, asOf: fetched))

        // The next one works again.
        clock += 300
        client.tick()
        source.answer(some)
        XCTAssertEqual(client.display, .limits(some, asOf: nil))

        client.setEnabled(false)
        XCTAssertEqual(client.display, .off)
    }

    func testDisplayIsUnavailableWhenNoFetchHasWorked() {
        client.setEnabled(true)
        source.answer(nil, because: .loginExpired)
        // The reason is kept: "unavailable" alone leaves the person with nothing to do about it.
        XCTAssertEqual(client.display, .unavailable(.loginExpired))

        // Turning it off and on starts clean: loading, not the old failure.
        client.setEnabled(false)
        client.setEnabled(true)
        XCTAssertEqual(client.display, .loading)
    }

    func testDisplayIsUnavailableOnceAFetchIsGivenUpOn() {
        client.setEnabled(true)
        clock += 61
        client.tick()
        XCTAssertEqual(client.display, .unavailable(.noAnswer))
    }

    func testAFetchThatNeverAnswersIsAbandonedSoTheNextCanStart() {
        client.setEnabled(true)
        clock += 59
        client.tick()
        XCTAssertEqual(source.fetches, 1)
        clock += 2
        client.tick()
        XCTAssertEqual(source.cancels, 1)
        XCTAssertEqual(source.fetches, 2)

        source.answer(some, fetch: 0)
        XCTAssertNil(client.limits)
        source.answer(some, fetch: 1)
        XCTAssertEqual(client.limits, some)
    }

    func testResumeRefreshesOnceAndDropsExpiredNumbersWithoutInventingZero() {
        client.refreshAfterResume()
        XCTAssertEqual(source.fetches, 0)
        client.setEnabled(true)
        source.answer(some)
        clock += 3600
        client.refreshAfterResume()
        XCTAssertEqual(source.fetches, 2)
        XCTAssertNil(client.limits)
        XCTAssertEqual(client.display.ringState, .loading)
        XCTAssertNil(client.display.runOut(now: clock))
        XCTAssertFalse(client.display.knowsAvailability(now: clock))
        source.answer(some)
        clock += 9
        client.refreshAfterResume()
        XCTAssertEqual(source.fetches, 2)
        clock += 2
        client.refreshAfterResume()
        XCTAssertEqual(source.fetches, 3)
    }

    func testResumeAbandonsAFetchFromBeforeSleepAndIgnoresItsLateAnswer() {
        client.setEnabled(true)
        clock += 3600
        client.refreshAfterResume()
        XCTAssertEqual(source.cancels, 1)
        XCTAssertEqual(source.fetches, 2)
        source.answer(some, fetch: 0)
        XCTAssertNil(client.limits)
        source.answer(some, fetch: 1)
        XCTAssertEqual(client.limits, some)
    }

    func testTransientFailuresHaveOnlyThreeShortRetries() {
        client.setEnabled(true)
        source.answer(nil)
        XCTAssertEqual(scheduler.jobs.map(\.delay), [10])
        scheduler.fire(0)
        source.answer(nil, because: .noAnswer)
        XCTAssertEqual(scheduler.jobs.map(\.delay), [10, 30])
        scheduler.fire(1)
        source.answer(nil, because: .refused(529))
        XCTAssertEqual(scheduler.jobs.map(\.delay), [10, 30, 60])
        scheduler.fire(2)
        source.answer(nil)
        XCTAssertEqual(source.fetches, 4)
        XCTAssertEqual(scheduler.jobs.count, 3)
        clock += 300
        client.tick()
        source.answer(nil)
        XCTAssertEqual(scheduler.jobs.map(\.delay), [10, 30, 60, 10])
    }

    func testLoginAndPermanentFailuresDoNotScheduleShortRetries() {
        client.setEnabled(true)
        for reason: LimitsFailure in [.noLogin, .loginExpired, .refused(401), .refused(429), .unreadable] {
            source.answer(nil, because: reason)
            XCTAssertTrue(scheduler.jobs.isEmpty)
            clock += 300
            client.tick()
        }
    }

    func testDisablingCancelsRetriesAndRejectsAlreadyQueuedCallbacks() {
        client.setEnabled(true)
        source.answer(nil)
        client.setEnabled(false)
        XCTAssertTrue(scheduler.jobs[0].cancelled)
        scheduler.fire(0)
        XCTAssertEqual(source.fetches, 1)
        client.setEnabled(true)
        scheduler.fire(0)
        XCTAssertEqual(source.fetches, 2)
    }

    func testResumeSupersedesPendingRetryAndSuccessResetsTheSequence() {
        client.setEnabled(true)
        source.answer(nil)
        client.refreshAfterResume()
        XCTAssertTrue(scheduler.jobs[0].cancelled)
        XCTAssertEqual(source.fetches, 2)
        source.answer(some)
        scheduler.fire(0)
        XCTAssertEqual(source.fetches, 2)
        clock += 300
        client.tick()
        source.answer(nil)
        XCTAssertEqual(scheduler.jobs.map(\.delay), [10, 10])
    }

    func testUnlockAfterAFailedWakeGetsOneDeferredCheck() {
        client.setEnabled(true)
        source.answer(some)
        clock += 3600
        client.refreshAfterResume()
        source.answer(nil, because: .noLogin)
        clock += 1
        client.refreshAfterResume()
        client.refreshAfterResume()
        XCTAssertEqual(source.fetches, 2)
        XCTAssertEqual(scheduler.jobs.map(\.delay), [9])
        clock += 9
        scheduler.fire(0)
        XCTAssertEqual(source.fetches, 3)
        source.answer(some)
        XCTAssertEqual(client.limits, some)
    }

    func testASuccessfulLongWakeNeedsNoFurtherUnlockRead() {
        client.setEnabled(true)
        source.answer(some)
        clock += 3600
        client.refreshAfterResume()
        clock += 1
        client.refreshAfterResume()
        client.refreshAfterResume()
        XCTAssertTrue(scheduler.jobs.isEmpty)
        clock += 49
        source.answer(some)
        XCTAssertEqual(source.fetches, 2)
        XCTAssertTrue(scheduler.jobs.isEmpty)
    }

    func testAnUnlockDuringALongWakeReadSurvivesUntilItsFailure() {
        client.setEnabled(true)
        source.answer(some)
        clock += 3600
        client.refreshAfterResume()
        clock += 1
        client.refreshAfterResume()
        clock += 10
        client.refreshAfterResume()
        XCTAssertEqual(source.fetches, 2)
        XCTAssertTrue(scheduler.jobs.isEmpty)
        clock += 39
        source.answer(nil, because: .loginExpired)
        XCTAssertEqual(source.fetches, 3)
        // The repeated unlocks leave one check, not another burst after this failure.
        source.answer(nil, because: .loginExpired)
        XCTAssertEqual(source.fetches, 3)
        XCTAssertTrue(scheduler.jobs.isEmpty)
    }

    func testAFailedWakeStillHonorsTheResumeRateLimitAfterUnlock() {
        client.setEnabled(true)
        source.answer(some)
        clock += 3600
        client.refreshAfterResume()
        clock += 1
        client.refreshAfterResume()
        clock += 1
        source.answer(nil, because: .noLogin)
        XCTAssertEqual(source.fetches, 2)
        XCTAssertEqual(scheduler.jobs.map(\.delay), [8])
        clock += 8
        scheduler.fire(0)
        XCTAssertEqual(source.fetches, 3)
    }

    func testADeferredUnlockCheckWaitsForAReadThatStartedBeforeItFired() {
        client.setEnabled(true)
        source.answer(some)
        clock += 3600
        client.refreshAfterResume()
        source.answer(nil, because: .noLogin)
        clock += 1
        client.refreshAfterResume()
        clock += 1
        client.tick()
        XCTAssertEqual(source.fetches, 3)
        clock += 8
        scheduler.fire(0)
        XCTAssertEqual(source.fetches, 3)
        clock += 42
        source.answer(nil, because: .loginExpired)
        XCTAssertEqual(source.fetches, 4)
        source.answer(some)
        XCTAssertEqual(source.fetches, 4)
    }

    func testDisablingDropsAnUnlockWaitingForALongRead() {
        client.setEnabled(true)
        clock += 1
        client.refreshAfterResume()
        client.setEnabled(false)
        clock += 49
        source.answer(nil, because: .loginExpired)
        XCTAssertEqual(source.fetches, 1)
        XCTAssertTrue(scheduler.jobs.isEmpty)
        client.setEnabled(true)
        source.answer(nil, because: .loginExpired)
        XCTAssertEqual(source.fetches, 2)
    }

    func testASlowSourcesBudgetPreservesTheUnlockCheckPastOneMinute() {
        source.fetchTimeout = 110
        client.setEnabled(true)
        clock += 61
        client.refreshAfterResume()
        client.refreshIfStale()
        client.tick()
        XCTAssertEqual(source.fetches, 1)
        XCTAssertEqual(source.cancels, 0)
        clock += 40
        source.answer(nil, because: .loginExpired)
        XCTAssertEqual(source.fetches, 2)
        XCTAssertEqual(source.cancels, 0)
        source.answer(some)
        XCTAssertEqual(client.limits, some)
    }

    func testASlowSourceIsAbandonedOnlyWhenItsOwnBudgetExpires() {
        source.fetchTimeout = 110
        client.setEnabled(true)
        clock += 109
        client.tick()
        XCTAssertEqual(source.fetches, 1)
        XCTAssertEqual(source.cancels, 0)
        clock += 1
        client.tick()
        XCTAssertEqual(source.fetches, 2)
        XCTAssertEqual(source.cancels, 1)
        source.answer(some, fetch: 0)
        XCTAssertNil(client.limits)
        source.answer(some, fetch: 1)
        XCTAssertEqual(client.limits, some)
    }
}
