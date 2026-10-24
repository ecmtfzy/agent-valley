import XCTest
@testable import AgentValley

final class AwayModeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func testLockingTheScreenTurnsItOnAndUnlockingTurnsItOff() {
        var mode = AwayMode(); mode.turnOn(.screenLocked, at: t0); XCTAssertTrue(mode.on)
        mode.noteLastInput(at: t0.addingTimeInterval(30)); XCTAssertTrue(mode.on, "input on a locked screen is not someone back at work")
        mode.screenUnlocked(); XCTAssertFalse(mode.on)
    }
    func testThePanelsOwnClickDoesNotTurnItOff() {
        var mode = AwayMode(); mode.turnOn(.panelButton, at: t0)
        mode.noteLastInput(at: t0.addingTimeInterval(9)); XCTAssertTrue(mode.on)
        mode.noteLastInput(at: t0.addingTimeInterval(11)); XCTAssertFalse(mode.on)
    }
    func testFromThePhoneAnyTouchOfTheMacAfterwardsTurnsItOff() {
        var mode = AwayMode(); mode.turnOn(.phoneMessage, at: t0)
        mode.noteLastInput(at: t0.addingTimeInterval(-5)); XCTAssertTrue(mode.on)
        mode.noteLastInput(at: t0.addingTimeInterval(1)); XCTAssertFalse(mode.on)
    }
    func testTurningItOnAgainKeepsWhenItBegan() {
        var mode = AwayMode(); mode.turnOn(.phoneButton, at: t0); mode.turnOn(.phoneMessage, at: t0.addingTimeInterval(60))
        mode.noteLastInput(at: t0.addingTimeInterval(30)); XCTAssertFalse(mode.on)
    }
    func testTheButtonTurnsItOff() { var mode = AwayMode(); mode.turnOn(.phoneButton, at: t0); mode.turnOff(); XCTAssertFalse(mode.on) }
}
