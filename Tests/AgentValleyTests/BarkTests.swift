import XCTest
@testable import AgentValley

final class BarkTests: XCTestCase {
    private func row(_ tools: [String]) -> AgentRow {
        var info = AgentInfo()
        info.openTools = tools.map { OpenTool(id: "t", tool: $0, input: [:]) }
        return AgentRow(id: "r", info: info, status: .needsYou, elapsed: 0)
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testTheToolSaysWhatTheWaitIsAbout() {
        let cases: [(String, WaitTopic)] = [
            ("ExitPlanMode", .plan), ("AskUserQuestion", .question), ("Bash", .run),
            ("Edit", .edit), ("Write", .edit), ("MultiEdit", .edit), ("NotebookEdit", .edit),
            ("WebFetch", .web), ("WebSearch", .web), ("Grep", .generic),
        ]
        for (tool, topic) in cases {
            XCTAssertEqual(Barks.waitTopic(row([tool]), greet: false), topic, tool)
        }
        XCTAssertEqual(Barks.waitTopic(row(["Bash", "Edit"]), greet: false), .edit)
    }

    func testAGreetingOnlyReplacesTheGenericLine() {
        XCTAssertEqual(Barks.waitTopic(row([]), greet: true), .first)
        XCTAssertEqual(Barks.waitTopic(row([]), greet: false), .generic)
        XCTAssertEqual(Barks.waitTopic(row(["ExitPlanMode"]), greet: true), .plan)
        XCTAssertEqual(Barks.waitTopic(row(["Bash"]), greet: true), .run)
    }

    func testDoneTopicsInOrder() {
        XCTAssertEqual(Barks.doneTopic(group: true, worked: 700, hour: 23, first: true), .group)
        XCTAssertEqual(Barks.doneTopic(group: false, worked: 700, hour: 23, first: true), .long)
        XCTAssertEqual(Barks.doneTopic(group: false, worked: 100, hour: 23, first: true), .night)
        XCTAssertEqual(Barks.doneTopic(group: false, worked: 100, hour: 1, first: false), .night)
        XCTAssertEqual(Barks.doneTopic(group: false, worked: 100, hour: 9, first: true), .first)
        XCTAssertEqual(Barks.doneTopic(group: false, worked: 100, hour: 15, first: true), .short)
        XCTAssertEqual(Barks.doneTopic(group: false, worked: 599, hour: 12, first: false), .short)
    }

    func testTheDayBeginsAtFive() {
        let c = utc
        XCTAssertEqual(Barks.day(date("2026-10-25T04:59:00Z"), calendar: c), Barks.day(date("2026-10-24T05:00:00Z"), calendar: c))
        XCTAssertNotEqual(Barks.day(date("2026-10-25T05:00:00Z"), calendar: c), Barks.day(date("2026-10-24T05:00:00Z"), calendar: c))
        XCTAssertTrue(Barks.firstOfDay(last: nil, now: date("2026-10-25T05:00:00Z"), calendar: c))
        XCTAssertFalse(Barks.firstOfDay(last: date("2026-10-24T06:00:00Z"), now: date("2026-10-25T04:00:00Z"), calendar: c))
        XCTAssertTrue(Barks.firstOfDay(last: date("2026-10-24T06:00:00Z"), now: date("2026-10-25T05:00:00Z"), calendar: c))
        XCTAssertTrue(Barks.morning(hour: 5))
        XCTAssertFalse(Barks.morning(hour: 12))
        XCTAssertFalse(Barks.morning(hour: 4))
    }

    func testNoLineTwiceUntilTheRestAreSaid() {
        var p = LinePicker()
        let abc = ["a", "b", "c"]
        XCTAssertEqual((0..<5).map { _ in p.pick(abc, group: "g", random: { _ in 0 }) }, ["a", "b", "c", "a", "b"])

        var q = LinePicker()
        let picks = (0..<4).map { _ in q.pick(abc, group: "g", random: { $0 - 1 }) }
        XCTAssertEqual(Set(picks.prefix(3).compactMap { $0 }), Set(abc))
        XCTAssertNotEqual(picks[3], picks[2])

        var s = LinePicker()
        XCTAssertEqual([s.pick(["x"], group: "g", random: { _ in 0 }), s.pick(["x"], group: "g", random: { _ in 0 })], ["x", "x"])
        XCTAssertNil(s.pick([], group: "g", random: { _ in 0 }))

        var r = LinePicker()
        XCTAssertEqual(r.pick(abc, group: "g1", random: { _ in 0 }), "a")
        XCTAssertEqual(r.pick(abc, group: "g2", random: { _ in 0 }), "a")
        XCTAssertEqual(r.pick(abc, group: "g1", random: { _ in 0 }), "b")
    }

    func testLimitScenes() {
        let now = date("2026-10-24T12:00:00Z")
        func s(_ a: LimitState, _ b: LimitState, _ r: Date? = nil) -> CrewScene? {
            Barks.scene(from: a, to: b, resetsAt: r, now: now)
        }
        XCTAssertEqual(s(.open, .fishing), .fishout)
        XCTAssertEqual(s(.open, .vacation), .vanout)
        XCTAssertEqual(s(.fishing, .vacation), .vanout)
        XCTAssertNil(s(.vacation, .fishing))
        for st in [LimitState.open, .fishing, .vacation] { XCTAssertNil(s(st, st)) }
        XCTAssertEqual(s(.fishing, .open, now.addingTimeInterval(-1)), .fishback)
        XCTAssertEqual(s(.vacation, .open, now.addingTimeInterval(-1)), .vanback)
        XCTAssertEqual(s(.fishing, .open, now.addingTimeInterval(60)), .fishback)
        XCTAssertNil(s(.fishing, .open, now.addingTimeInterval(61)))
        XCTAssertNil(s(.vacation, .open, now.addingTimeInterval(3600)))
        XCTAssertNil(s(.fishing, .open, nil))
        XCTAssertEqual(LimitState(nil), .open)
        XCTAssertEqual(LimitState(RunOut(weekly: true, resetsAt: nil)), .vacation)
        XCTAssertEqual(LimitState(RunOut(weekly: false, resetsAt: nil)), .fishing)
    }
}
