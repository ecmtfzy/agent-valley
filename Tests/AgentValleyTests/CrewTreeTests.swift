import XCTest
@testable import AgentValley

final class CrewTreeTests: XCTestCase {
    private func row(_ status: AgentStatus) -> AgentRow {
        AgentRow(id: "a", info: AgentInfo(), status: status, elapsed: 0)
    }

    func testABranchIsTheMockupsThreeBlocks() {
        // trunk at x 22 (snapped 22), top 40, child centre y 81 (snapped 82), end x 46
        let r = CrewTree.rects(trunkX: 22, top: 40, to: .init(id: "a", y: 81, endX: 46, hot: false))
        XCTAssertEqual(r, [CGRect(x: 21, y: 40, width: 2, height: 39),   // down to cy - 3
                           CGRect(x: 23, y: 79, width: 2, height: 2),    // the one step
                           CGRect(x: 25, y: 81, width: 21, height: 2)])  // across to endX
    }

    func testEveryBlockLandsOnWholePoints() {
        let r = CrewTree.rects(trunkX: 21.3, top: 39.6, to: .init(id: "a", y: 77.7, endX: 50.2, hot: false))
        XCTAssertTrue(r.allSatisfy { [$0.minX, $0.minY, $0.width, $0.height].allSatisfy { $0 == $0.rounded() } })
    }

    func testTheRouteGoesDownThenAcross() {
        XCTAssertEqual(CrewTree.route(trunkX: 22, top: 40, to: .init(id: "a", y: 81, endX: 46, hot: false)),
                       [CGPoint(x: 22, y: 40), CGPoint(x: 22, y: 80), CGPoint(x: 24, y: 82), CGPoint(x: 46, y: 82)])
    }

    func testOnlyAWaitingSubAgentTurnsItsBranchRed() {
        XCTAssertTrue(CrewTree.hot(row(.needsYou), requests: 0))
        XCTAssertTrue(CrewTree.hot(row(.working), requests: 1))
        XCTAssertFalse(CrewTree.hot(row(.working), requests: 0))
        XCTAssertFalse(CrewTree.hot(row(.done), requests: 0))
    }

    func testANewSubAgentStartsAndADoneOneFinishes() {
        let old = ["s": ["a": AgentStatus.working]]
        let new = ["s": ["a": AgentStatus.done, "b": .working]]
        XCTAssertEqual(Set(CrewTree.events(old: old, new: new)),
                       [.finished(card: "s", agent: "a"), .started(card: "s", agent: "b")])
    }

    func testANewSessionBringsNoEvents() {
        XCTAssertEqual(CrewTree.events(old: [:], new: ["s": ["a": .working]]), [])
    }

    func testARowThatVanishesIsNoEvent() {
        XCTAssertEqual(CrewTree.events(old: ["s": ["a": .working]], new: ["s": [:]]), [])
    }

    func testAnAgentBornDoneIsNoEvent() {
        XCTAssertEqual(CrewTree.events(old: ["s": [:]], new: ["s": ["a": .done]]), [])
    }

    func testEventsSendPacketsOnlyOpenUnreducedAndInView() {
        let old = ["s": ["a": AgentStatus.working], "t": [:]]
        let new = ["s": ["a": AgentStatus.done], "t": ["b": .working]]
        let sent = CrewTree.pulses(old: old, new: new, open: true, reduced: false, leftOut: [])
        XCTAssertEqual(Set(sent.map { "\($0.card)/\($0.agent)/\($0.up)" }), ["s/a/true", "t/b/false"])
        XCTAssertTrue(sent.allSatisfy { !$0.arrived })
        XCTAssertEqual(CrewTree.pulses(old: old, new: new, open: true, reduced: false, leftOut: ["s"]).map(\.card), ["t"])
        XCTAssertEqual(CrewTree.pulses(old: old, new: new, open: false, reduced: false, leftOut: []), [])
        XCTAssertEqual(CrewTree.pulses(old: old, new: new, open: true, reduced: true, leftOut: []), [])
        // Nothing seen yet, as on opening or back from a page: nothing plays.
        XCTAssertEqual(CrewTree.pulses(old: [:], new: new, open: true, reduced: false, leftOut: []), [])
    }

    func testProgressEasesAndEnds() {
        let t = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(CrewTree.progress(start: t, now: t), 0)
        XCTAssertEqual(CrewTree.progress(start: t, now: t + 0.4)!, 0.5, accuracy: 0.001)
        XCTAssertNil(CrewTree.progress(start: t, now: t + 0.81))
    }

    func testThePacketStepsOnTheGridAndRunsBothWays() {
        let route = [CGPoint(x: 22, y: 40), CGPoint(x: 22, y: 80), CGPoint(x: 24, y: 82), CGPoint(x: 46, y: 82)]
        let down = CrewTree.packet(route: route, progress: 0.25, up: false)
        XCTAssertEqual(down.count, 3)
        XCTAssertTrue(down.allSatisfy { Int($0.x) % 2 == 0 && Int($0.y) % 2 == 0 })
        XCTAssertEqual(CrewTree.packet(route: route, progress: 1, up: false).first, CGPoint(x: 46, y: 82))
        XCTAssertEqual(CrewTree.packet(route: route, progress: 1, up: true).first, CGPoint(x: 22, y: 40))
    }

    func testTheTrailGrowsWithTheHead() {
        let route = [CGPoint(x: 22, y: 40), CGPoint(x: 22, y: 80), CGPoint(x: 24, y: 82), CGPoint(x: 46, y: 82)]
        XCTAssertLessThan(CrewTree.trail(route: route, progress: 0.3).count, CrewTree.trail(route: route, progress: 0.9).count)
    }

    func testAFullTrailIsTheStillBranch() {
        let route = CrewTree.route(trunkX: 22, top: 40, to: .init(id: "a", y: 81, endX: 46, hot: false))
        XCTAssertEqual(CrewTree.trail(route: route, progress: 1),
                       CrewTree.rects(trunkX: 22, top: 40, to: .init(id: "a", y: 81, endX: 46, hot: false)))
    }
}
