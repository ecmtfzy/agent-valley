import XCTest
@testable import AgentValley

final class StopDeskTests: XCTestCase {
    private var desk: StopDesk!
    private var replies: [Data?] = []
    private var accept = true
    private var sent: [[UUID]] = []
    private var back: [[UUID]] = []

    override func setUp() {
        desk = StopDesk()
        replies = []
        accept = true
        sent = []
        back = []
        desk.holds = { _ in true }
        desk.onSent = { [unowned self] in sent.append($0) }
        desk.onBackAtDesk = { [unowned self] in back.append($0) }
    }

    private func stop(_ session: String = "s1") -> StopWait { StopWait(session: session, lastMessage: "done") }

    @discardableResult
    private func arrive(_ session: String = "s1") -> UUID {
        desk.arrived(stop(session)) { [unowned self] in replies.append($0); return accept }
    }

    private func block(_ text: String) -> Data { AnswerProtocol.block(reason: text) }

    func testAtTheDeskTheHookIsLetGoAtOnce() {
        desk.awayOn = false
        arrive()
        XCTAssertEqual(replies, [nil])
    }

    func testAwayTheHookWaitsForAMessage() {
        desk.awayOn = true
        arrive()
        XCTAssertTrue(replies.isEmpty)
    }

    func testASessionThatIsToldAnotherWayIsNeverHeld() {
        desk.awayOn = true
        desk.holds = { _ in false }
        arrive()
        XCTAssertEqual(replies, [nil])
        XCTAssertEqual(desk.deliver(id: UUID(), session: "s1", text: "x"), .waitingForTurnEnd)
    }

    func testAMessageGoesStraightToAWaitingHook() {
        desk.awayOn = true
        arrive()
        let id = UUID()
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "go"), .sent)
        XCTAssertEqual(replies, [block("go")])
        XCTAssertEqual(sent, [[id]])
    }

    func testAMessageWaitsForTheNextStop() {
        desk.awayOn = true
        let id = UUID()
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "go"), .waitingForTurnEnd)
        XCTAssertTrue(sent.isEmpty)
        arrive()
        XCTAssertEqual(replies, [block("go")])
        XCTAssertEqual(sent, [[id]])
    }

    func testTwoWaitingMessagesGoAsOne() {
        desk.awayOn = true
        let a = UUID(), b = UUID()
        _ = desk.deliver(id: a, session: "s1", text: "a")
        _ = desk.deliver(id: b, session: "s1", text: "b")
        arrive()
        XCTAssertEqual(replies, [block("a\n\nb")])
        XCTAssertEqual(sent, [[a, b]])
    }

    func testAHookThatIsGoneKeepsTheMessage() {
        desk.awayOn = true
        accept = false
        arrive()
        let id = UUID()
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "go"), .waitingForTurnEnd)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(replies, [block("go")])
        XCTAssertEqual(desk.deliver(id: UUID(), session: "s1", text: "again"), .waitingForTurnEnd)
        XCTAssertEqual(replies.count, 1, "the gone hook is forgotten, not tried twice")
    }

    func testAGoneHookOnArrivalKeepsTheQueue() {
        desk.awayOn = true
        let id = UUID()
        _ = desk.deliver(id: id, session: "s1", text: "go")
        accept = false
        arrive()
        XCTAssertTrue(sent.isEmpty)
        accept = true
        arrive()
        XCTAssertEqual(replies, [block("go"), block("go")])
        XCTAssertEqual(sent, [[id]])
    }

    func testBackAtTheDeskLetsEveryHookGoAndKeepsWhatWasNotSent() {
        desk.awayOn = true
        arrive("s1")
        let a = UUID(), b = UUID()
        _ = desk.deliver(id: a, session: "s2", text: "a")
        _ = desk.deliver(id: b, session: "s2", text: "b")
        desk.release()
        XCTAssertEqual(replies, [nil])
        XCTAssertEqual(desk.leftOver, [LeftOver(id: a, session: "s2", text: "a"), LeftOver(id: b, session: "s2", text: "b")])
        XCTAssertEqual(back, [[a, b]])
    }

    func testReleaseWithNothingLeftDoesNotCallBack() {
        desk.release()
        XCTAssertTrue(back.isEmpty)
    }

    func testAHookLetGoIsNeverAnsweredTwice() {
        desk.awayOn = true
        arrive()
        desk.release()
        XCTAssertEqual(replies, [nil])
        XCTAssertEqual(desk.deliver(id: UUID(), session: "s1", text: "late"), .waitingForTurnEnd)
        XCTAssertEqual(replies, [nil])
    }

    func testASentMessageIsNotLeftOverWhenAwayEnds() {
        desk.awayOn = true
        arrive()
        let id = UUID()
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "go"), .sent)
        desk.release()
        XCTAssertTrue(desk.leftOver.isEmpty)
        XCTAssertTrue(back.isEmpty)
        XCTAssertEqual(sent, [[id]])
    }

    func testASecondStopOfTheSameSessionReplacesTheFirst() {
        desk.awayOn = true
        arrive()
        arrive()
        XCTAssertEqual(replies, [nil])
    }

    func testALateCloseOfAnOldHookDoesNotDropTheNewOne() {
        desk.awayOn = true
        let first = arrive()
        arrive()
        desk.hookGone(first)
        let id = UUID()
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "go"), .sent)
        XCTAssertEqual(replies, [nil, block("go")])
    }

    func testAClosedHookIsForgotten() {
        desk.awayOn = true
        let h = arrive()
        desk.hookGone(h)
        XCTAssertEqual(desk.deliver(id: UUID(), session: "s1", text: "go"), .waitingForTurnEnd)
        XCTAssertTrue(replies.isEmpty)
    }

    func testDismissRemovesALeftOver() {
        let a = UUID(), b = UUID()
        _ = desk.deliver(id: a, session: "s1", text: "a")
        _ = desk.deliver(id: b, session: "s1", text: "b")
        desk.release()
        desk.dismiss(a)
        XCTAssertEqual(desk.leftOver.map(\.id), [b])
    }

    func testReleaseReenteredFromAReplyDoesNotAnswerTwice() {
        desk.awayOn = true
        desk.arrived(stop()) { [unowned self] in replies.append($0); desk.release(); return true }
        desk.release()
        XCTAssertEqual(replies, [nil])
    }

    func testTheSameIdTwiceIsQueuedOnce() {
        let id = UUID()
        _ = desk.deliver(id: id, session: "s1", text: "a")
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "a"), .waitingForTurnEnd)
        desk.release()
        XCTAssertEqual(desk.leftOver.map(\.id), [id])
        XCTAssertEqual(back, [[id]])
    }

    func testAFailedReplyThatReleasedDuringItGivesTheMessageAnOutcome() {
        desk.awayOn = true
        desk.arrived(stop()) { [unowned self] _ in desk.release(); return false }
        let id = UUID()
        XCTAssertEqual(desk.deliver(id: id, session: "s1", text: "go"), .waitingForTurnEnd)
        XCTAssertEqual(back, [[id]])
        XCTAssertEqual(desk.leftOver.map(\.id), [id])
        XCTAssertTrue(sent.isEmpty)
    }
}
