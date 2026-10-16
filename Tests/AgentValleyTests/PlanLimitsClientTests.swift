import XCTest
@testable import AgentValley

/// Stands in for the Keychain and the network: counts what the client asks for and answers on demand.
private final class FakeSource: PlanLimitsSource {
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

final class PlanLimitsClientTests: XCTestCase {
    private var source: FakeSource!
    private var client: PlanLimitsClient!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let some = PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil)

    override func setUp() {
        source = FakeSource()
        client = PlanLimitsClient(source: source, now: { [unowned self] in self.clock })
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
}
