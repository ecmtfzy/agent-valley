import SwiftUI
import XCTest
@testable import AgentValley

final class MotionTests: XCTestCase {
    func testStaggerIsCappedSoALongListNeverKeepsAnyoneWaiting() {
        let motion = Motion(reduced: false)
        XCTAssertEqual(motion.revealDelay(index: 0), 0.07, accuracy: 0.0001)
        XCTAssertEqual(motion.revealDelay(index: 2), 0.14, accuracy: 0.0001)
        XCTAssertEqual(motion.revealDelay(index: 4), 0.21, accuracy: 0.0001)
        XCTAssertEqual(motion.revealDelay(index: 40), 0.21, accuracy: 0.0001)
    }

    func testFullMotionTravels() {
        let motion = Motion(reduced: false)
        XCTAssertNotNil(motion.resize(opening: true))
        XCTAssertNotNil(motion.resize(opening: false))
        XCTAssertNotEqual(motion.resize(opening: true), motion.resize(opening: false))
        XCTAssertLessThan(motion.travel, 0)
        XCTAssertLessThan(motion.hop, 0)
        // The red count swells for a moment when someone starts to wait, and never outgrows the bar.
        XCTAssertGreaterThan(motion.pulse, 1)
        XCTAssertLessThanOrEqual(18 * motion.pulse, 32)
        XCTAssertEqual(motion.pulseDim, 1)
        // And it beats again every few seconds for as long as someone waits: a mark made once
        // is missed by anyone who was not looking at that second.
        XCTAssertEqual(motion.waitingBeat, 3)
        // On each beat the whole bar glows red and fades: the count alone, at 18 points, was
        // too small to catch the eye however it moved.
        XCTAssertGreaterThan(motion.flash, 0.4)
        // Three swells mark the start of a wait, and a beat never lands on top of them: two at
        // once made the count more than twice its size, taller than the bar.
        XCTAssertEqual(motion.arrivalSwells.filter { $0 > 1 }.count, 3)
        XCTAssertEqual(motion.arrivalSwells.last, 1)
        XCTAssertEqual(motion.arrivalDips.filter { $0 < 1 }.count, 0)
        XCTAssertLessThanOrEqual(18 * (motion.arrivalSwells.max() ?? 1), NotchState().barHeight)
        XCTAssertFalse(motion.beats(sinceArrival: 0.1))
        XCTAssertFalse(motion.beats(sinceArrival: motion.arrivalLasts - 0.01))
        XCTAssertTrue(motion.beats(sinceArrival: motion.arrivalLasts))
    }

    // Reduce Motion: nothing travels or changes size over time, and nothing waits its turn.
    func testReduceMotionDropsEverythingThatTravels() {
        let motion = Motion(reduced: true)
        XCTAssertNil(motion.resize(opening: true))
        XCTAssertNil(motion.resize(opening: false))
        XCTAssertEqual(motion.travel, 0)
        XCTAssertEqual(motion.hop, 0)
        XCTAssertEqual(motion.revealDelay(index: 3), 0)
        // The same moment is marked by a fade in place of a change of size.
        XCTAssertEqual(motion.pulse, 1)
        XCTAssertLessThan(motion.pulseDim, 1)
        // Nothing keeps blinking: the fade marks the moment once and the red count then stands still.
        XCTAssertNil(motion.waitingBeat)
        XCTAssertEqual(motion.flash, 0)
        // One dip and back, once. No change of size, and no beat ever.
        XCTAssertEqual(motion.arrivalSwells.filter { $0 != 1 }.count, 0)
        XCTAssertEqual(motion.arrivalDips.filter { $0 < 1 }.count, 1)
        XCTAssertEqual(motion.arrivalDips.last, 1)
        XCTAssertFalse(motion.beats(sinceArrival: 60))
    }
}
