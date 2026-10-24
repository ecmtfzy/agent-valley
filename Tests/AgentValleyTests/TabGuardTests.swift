import XCTest
@testable import AgentValley

final class TabGuardTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    let process = SessionProcess(pid: 42, startedAt: Date(timeIntervalSince1970: 1_000))
    let tab = TabPlace(terminal: .iterm, key: "/dev/ttys004")

    func facts(tty: String? = "/dev/ttys004", group: Int32 = 42, ttyGroup: Int32 = 42, startedAt: Date? = nil) -> ProcessFacts {
        ProcessFacts(tty: tty, group: group, ttyGroup: ttyGroup, startedAt: startedAt ?? start)
    }

    func testClaudeInFrontOfItsOwnTabMayBeTypedTo() { XCTAssertTrue(TabGuard.claudeHoldsTab(facts(), process: process, place: tab)) }
    func testAShellInFrontMeansNo() { XCTAssertFalse(TabGuard.claudeHoldsTab(facts(ttyGroup: 7), process: process, place: tab)) }
    func testAPidTakenOverByAnotherProgramMeansNo() {
        XCTAssertFalse(TabGuard.claudeHoldsTab(facts(startedAt: start.addingTimeInterval(5)), process: process, place: tab))
    }
    func testAnotherTabMeansNo() { XCTAssertFalse(TabGuard.claudeHoldsTab(facts(tty: "/dev/ttys009"), process: process, place: tab)) }
    func testNoProcessMeansNo() { XCTAssertFalse(TabGuard.claudeHoldsTab(nil, process: process, place: tab)) }
    func testGhosttyIsNotCheckedByTTY() {
        XCTAssertTrue(TabGuard.claudeHoldsTab(facts(tty: "/dev/ttys009"), process: process, place: TabPlace(terminal: .ghostty, key: "/work")))
    }
    // Superset's terminal tells no tab: only that Claude is the one in front on its terminal.
    func testInFrontNeedsTheSameProcessInFrontOfItsTerminal() {
        XCTAssertTrue(TabGuard.claudeInFront(facts(), process: process))
        XCTAssertTrue(TabGuard.claudeInFront(facts(tty: "/dev/ttys009"), process: process))
        XCTAssertFalse(TabGuard.claudeInFront(facts(ttyGroup: 7), process: process))
        XCTAssertFalse(TabGuard.claudeInFront(facts(startedAt: start.addingTimeInterval(5)), process: process))
        XCTAssertFalse(TabGuard.claudeInFront(nil, process: process))
    }
    func testThisTestsOwnProcessHasFacts() {
        let mine = AgentStore.facts(ofProcess: getpid())
        XCTAssertEqual(mine?.startedAt, AgentStore.startTime(ofProcess: getpid()))
    }
}
