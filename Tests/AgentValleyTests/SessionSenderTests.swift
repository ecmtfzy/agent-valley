import XCTest
@testable import AgentValley

final class SessionSenderTests: XCTestCase {
    private let process = SessionProcess(pid: 42, startedAt: Date(timeIntervalSince1970: 1))
    private let place = TabPlace(terminal: .ghostty, key: "/tmp/x")
    private var statuses: [(UUID, SendStatus)] = []
    private var statusSessions: [String] = []
    private var typed: [String] = []
    private var supersetCalls: [[String]] = []
    private var asking = false
    private var holds = true
    private var guardPlaces: [TabPlace?] = []
    private var route: SendRoute? = nil
    private var typeResult: TypingResult = .typed
    private var typeBody: ((@escaping () -> Bool) -> Void)?
    private var awayCalls: [AwayMode.Trigger] = []
    private let desk = StopDesk()
    private let worker = DispatchQueue(label: "sender-test")

    override func setUp() {
        route = .tab(place)
    }

    private var senders: [SessionSender] = []   // the sender is held weakly by its own callbacks

    private func makeSender(limit: Int = 1000) -> SessionSender {
        let sender = SessionSender(
            reach: { [unowned self] _ in route.map { SessionReach(process: process, route: $0, waitingOnPerson: false) } },
            asking: { [unowned self] _ in asking },
            holdsTab: { [unowned self] _, place in guardPlaces.append(place); return holds },
            type: { [unowned self] text, _, check in
                typeBody?(check)
                typed.append(text)
                return typeResult
            },
            superset: { [unowned self] ws, term, text, check in
                typeBody?(check)
                supersetCalls.append([ws, term, text])
                return typeResult
            },
            desk: desk,
            away: { [unowned self] in awayCalls.append($0) },
            worker: worker,
            onStatus: { [unowned self] in statuses.append(($0, $2)); statusSessions.append($1) },
            remembering: limit)
        senders.append(sender)
        return sender
    }

    private func message(_ text: String, id: UUID = UUID()) -> PhoneMessage {
        PhoneMessage(id: id, session: "s1", text: text)
    }

    private func lastStatus(_ id: UUID) -> SendStatus? { statuses.last { $0.0 == id }?.1 }

    /// Spins the main run loop until `done`, at most 3 seconds.
    private func wait(_ done: () -> Bool) {
        let end = Date().addingTimeInterval(3)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(done(), "timed out")
    }

    func testEveryStatusNamesTheMessagesSession() {
        let sender = makeSender()
        let m = message("hi")
        sender.send(m)
        wait { lastStatus(m.id) == .sent }
        XCTAssertFalse(statusSessions.isEmpty)
        XCTAssertTrue(statusSessions.allSatisfy { $0 == "s1" })
    }

    func testTheSameMessageTwiceIsTypedOnce() {
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        typeBody = { _ in started.signal(); release.wait() }
        let sender = makeSender()
        let m = message("hi")
        sender.send(m)
        XCTAssertEqual(started.wait(timeout: .now() + 3), .success)
        sender.send(m)   // mid-typing
        XCTAssertEqual(statuses.map(\.1), [.received, .received])
        release.signal()
        wait { lastStatus(m.id) == .sent }
        sender.send(m)   // after it finished
        XCTAssertEqual(lastStatus(m.id), .sent)
        XCTAssertEqual(typed, ["hi"])
    }

    func testBlankAndTooLongAreRefusedBeforeAnythingRuns() {
        let sender = makeSender()
        let blank = message("  "), long = message(String(repeating: "a", count: 8001))
        sender.send(blank)
        sender.send(long)
        XCTAssertEqual(statuses.map(\.1), [.received, .notSent(.empty), .received, .notSent(.tooLong)])
        worker.sync {}
        XCTAssertTrue(typed.isEmpty)
    }

    func testAnEndedSessionIsSaidSo() {
        route = nil
        let m = message("hi")
        makeSender().send(m)
        XCTAssertEqual(lastStatus(m.id), .notSent(.sessionGone))
    }

    func testAMessageWaitsWhileClaudeAsksAndGoesInOrderAfter() {
        asking = true
        let sender = makeSender()
        let a = message("a"), b = message("b")
        sender.send(a)
        sender.send(b)
        XCTAssertEqual(lastStatus(a.id), .heldForAnswer)
        XCTAssertEqual(lastStatus(b.id), .heldForAnswer)
        asking = false
        sender.askingChanged()
        wait { lastStatus(a.id) == .sent && lastStatus(b.id) == .sent }
        XCTAssertEqual(typed, ["a", "b"])
    }

    func testATabWithoutClaudeIsNotTypedInto() {
        holds = false
        let m = message("hi")
        makeSender().send(m)
        XCTAssertEqual(lastStatus(m.id), .notSent(.claudeNotRunning))
        worker.sync {}
        XCTAssertTrue(typed.isEmpty)
    }

    func testTheCheckBeforeEnterAsksAboutRequestsToo() {
        var answers: [Bool] = []
        typeBody = { [unowned self] check in
            answers.append(check())
            asking = true   // a request shows up mid-typing
            answers.append(check())
            holds = false
            asking = false
            answers.append(check())
        }
        let m = message("hi")
        makeSender().send(m)
        wait { lastStatus(m.id) == .sent }
        XCTAssertEqual(answers, [true, false, false])
    }

    func testTypingResultsBecomeStatuses() {
        let cases: [(TypingResult, SendStatus)] = [
            (.typed, .sent), (.stoppedBeforeEnter, .notSent(.leftBeforeEnter)),
            (.notAllowed, .notSent(.notAllowed)), (.ambiguous, .notSent(.ambiguousTab)),
            (.tabNotFound, .notSent(.tabNotFound)), (.timedOut, .notSent(.timedOut)),
            (.failed("x"), .notSent(.failed("x"))),
            (.stoppedBeforeText, .notSent(.claudeNotRunning)),
        ]
        for (result, expected) in cases {
            typeResult = result
            let m = message("hi")
            makeSender().send(m)
            wait { lastStatus(m.id) != .received }
            XCTAssertEqual(lastStatus(m.id), expected)
        }
    }

    // The look before Enter failed: a request opened, or Claude left the tab. Each is told as it was.
    func testStoppedBeforeEnterSaysWhy() {
        typeResult = .stoppedBeforeEnter
        typeBody = { [unowned self] _ in asking = true }
        let asked = message("a")
        makeSender().send(asked)
        wait { lastStatus(asked.id) != .received }
        XCTAssertEqual(lastStatus(asked.id), .notSent(.stoppedBeforeEnter))
        typeBody = nil
        asking = false
        let left = message("b")
        makeSender().send(left)
        wait { lastStatus(left.id) != .received }
        XCTAssertEqual(lastStatus(left.id), .notSent(.leftBeforeEnter))
        XCTAssertEqual(NotSentReason.stoppedBeforeEnter.message, "Typed, not sent: Claude asked you something first. It's waiting in the box.")
        XCTAssertEqual(NotSentReason.leftBeforeEnter.message, "Not sent: Claude left that tab before Enter. Start it there again and resend.")
        XCTAssertEqual(NotSentReason.leftBeforeEnter.caseName, "leftBeforeEnter")
    }

    func testStoppedBeforeTextWhileAskingGoesBackToTheFront() {
        typeBody = { [unowned self] _ in asking = true }
        typeResult = .stoppedBeforeText
        let sender = makeSender()
        let a = message("a"), b = message("b")
        sender.send(a)
        sender.send(b)
        wait { lastStatus(a.id) == .heldForAnswer }
        typeBody = nil
        typeResult = .typed
        asking = false
        sender.askingChanged()
        wait { lastStatus(a.id) == .sent && lastStatus(b.id) == .sent }
        XCTAssertEqual(typed, ["a", "a", "b"])
    }

    func testSupersetSessionsGoThroughSuperset() {
        route = .superset(workspace: "w1", terminal: "t1")
        typeResult = .failed("x")
        let m = message("hi")
        makeSender().send(m)
        wait { lastStatus(m.id) != .received }
        XCTAssertEqual(supersetCalls, [["w1", "t1", "hi"]])
        XCTAssertEqual(lastStatus(m.id), .notSent(.superset("x")))
        XCTAssertTrue(typed.isEmpty)
    }

    // Superset tells no tab: only whether Claude is in front of its terminal is asked, before anything goes.
    func testASupersetTerminalWithoutClaudeInFrontGetsNothing() {
        route = .superset(workspace: "w1", terminal: "t1")
        holds = false
        let m = message("hi")
        makeSender().send(m)
        XCTAssertEqual(lastStatus(m.id), .notSent(.claudeNotRunning))
        worker.sync {}
        XCTAssertTrue(supersetCalls.isEmpty)
        XCTAssertEqual(guardPlaces, [nil])
    }

    func testSupersetsLookBeforeEnterAsksAboutTheFrontAndRequests() {
        route = .superset(workspace: "w1", terminal: "t1")
        var answers: [Bool] = []
        typeBody = { [unowned self] check in
            answers.append(check())
            asking = true   // a request shows up mid-send
            answers.append(check())
            asking = false
            holds = false
            answers.append(check())
        }
        let m = message("hi")
        makeSender().send(m)
        wait { lastStatus(m.id) == .sent }
        XCTAssertEqual(answers, [true, false, false])
        XCTAssertTrue(guardPlaces.allSatisfy { $0 == nil })
    }

    func testOtherTerminalsTurnOnAwayAndWaitForTheStop() {
        route = .stopHook
        let m = message("hi")
        makeSender().send(m)
        XCTAssertEqual(awayCalls, [.phoneMessage])
        XCTAssertEqual(statuses.map(\.1), [.received, .waitingForTurnEnd])
    }

    func testAHeldStopHookSendsAndBackAtDeskIsTold() {
        route = .stopHook
        desk.awayOn = true
        desk.holds = { _ in true }
        let sender = makeSender()
        let a = message("a")
        sender.send(a)
        desk.arrived(StopWait(session: "s1", lastMessage: ""), reply: { _ in true })
        XCTAssertEqual(lastStatus(a.id), .sent)
        let b = message("b")
        sender.send(b)
        desk.release()
        XCTAssertEqual(lastStatus(b.id), .notSent(.backAtDesk))
    }

    func testEveryStatusIsLoggedWithoutTheWords() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sendlog-\(UUID())")
        let file = dir.appendingPathComponent("send.log")
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        SendLog.write(id: id, route: "tab", status: .received, to: file)
        SendLog.write(id: id, route: "tab", status: .notSent(.failed("echo: secret words")), to: file)
        SendLog.write(id: id, route: "superset", status: .notSent(.superset("secret words")), to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 3)
        XCTAssertTrue(text.contains(id.uuidString))
        XCTAssertTrue(text.contains("received") && text.contains("notSent.failed") && text.contains("notSent.superset"))
        XCTAssertFalse(text.contains("secret"))
    }

    func testTheLogKeepsTheLatterHalfWhenTooBig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sendlog-\(UUID())")
        let file = dir.appendingPathComponent("send.log")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = String(repeating: "old line of the log\n", count: 14_000)   // ~280 KB
        try old.write(to: file, atomically: true, encoding: .utf8)
        let id = UUID()
        SendLog.write(id: id, route: "none", status: .sent, to: file)
        let data = try Data(contentsOf: file)
        XCTAssertLessThan(data.count, SendLog.maxBytes)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("old line of the log\n"))
        XCTAssertTrue(text.hasSuffix("none sent\n"))
    }

    func testAnUnfinishedIdIsNotForgottenWhenTheCapFills() {
        asking = true
        let sender = makeSender(limit: 2)
        let held = message("held")
        sender.send(held)
        for n in 0..<3 { sender.send(PhoneMessage(id: UUID(), session: "other", text: "x\(n)")) }
        route = nil   // the others end at once; the held one still waits
        asking = false
        sender.send(held)
        XCTAssertEqual(lastStatus(held.id), .heldForAnswer)
        worker.sync {}
        XCTAssertTrue(typed.isEmpty)
    }

    func testFinishedIdsAreForgottenOldestFirst() {
        route = nil
        let sender = makeSender(limit: 2)
        let first = message("1"), second = message("2"), third = message("3")
        [first, second, third].forEach(sender.send)
        let before = statuses.count
        sender.send(third)
        XCTAssertEqual(statuses.count, before + 1)   // still remembered: repeats its status
        sender.send(first)                           // forgotten: treated as new
        XCTAssertEqual(statuses.count, before + 3)
    }

    func testAHeldMessageWhoseRouteBecomesStopHookGoesToTheDesk() {
        asking = true
        let sender = makeSender()
        let m = message("hi")
        sender.send(m)
        XCTAssertEqual(lastStatus(m.id), .heldForAnswer)
        route = .stopHook
        sender.askingChanged()
        XCTAssertEqual(awayCalls, [.phoneMessage])
        XCTAssertEqual(lastStatus(m.id), .waitingForTurnEnd)
    }

    func testStopHookIgnoresAskingButSupersetWaitsForIt() {
        asking = true
        route = .stopHook
        let a = message("a")
        let sender = makeSender()
        sender.send(a)
        XCTAssertEqual(lastStatus(a.id), .waitingForTurnEnd)

        route = .superset(workspace: "w1", terminal: "t1")
        let b = message("b")
        sender.send(b)
        XCTAssertEqual(lastStatus(b.id), .heldForAnswer)
        worker.sync {}
        XCTAssertTrue(supersetCalls.isEmpty)
        asking = false
        sender.askingChanged()
        wait { lastStatus(b.id) == .sent }
        XCTAssertEqual(supersetCalls, [["w1", "t1", "b"]])
    }
}
