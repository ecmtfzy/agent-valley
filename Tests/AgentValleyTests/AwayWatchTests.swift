import XCTest
@testable import AgentValley

final class AwayWatchTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)
    private var input = Date(timeIntervalSince1970: 0)
    private let desk = StopDesk()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("away-\(UUID().uuidString)")
    private var flagThere: Bool { FileManager.default.fileExists(atPath: folder.appendingPathComponent("away").path) }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeWatch(linked: Bool = true) -> AwayWatch {
        let watch = AwayWatch(desk: desk, folder: folder, now: { [unowned self] in now }, lastInput: { [unowned self] in input })
        watch.phoneLinked = linked
        return watch
    }

    func testTurningOffLetsTheDeskGo() {
        let watch = makeWatch()
        desk.holds = { _ in true }
        watch.turnOn(.phoneButton)
        XCTAssertTrue(watch.mode.on)
        XCTAssertTrue(desk.awayOn)
        var replies: [Data?] = []
        desk.arrived(StopWait(session: "s1", lastMessage: "")) { replies.append($0); return true }
        XCTAssertTrue(replies.isEmpty)
        now = now.addingTimeInterval(5)
        input = now.addingTimeInterval(1)
        watch.tick()
        XCTAssertFalse(watch.mode.on)
        XCTAssertFalse(desk.awayOn)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
    }

    func testThePanelButtonTogglesWithItsGrace() {
        let watch = makeWatch()
        watch.toggleFromPanel()
        XCTAssertTrue(watch.mode.on)
        input = now.addingTimeInterval(5)
        watch.tick()
        XCTAssertTrue(watch.mode.on)
        watch.toggleFromPanel()
        XCTAssertFalse(watch.mode.on)
        XCTAssertFalse(desk.awayOn)
    }

    func testLockAndUnlockComeThroughTheWatch() {
        let watch = makeWatch()
        watch.screenLocked()
        XCTAssertTrue(watch.mode.on)
        XCTAssertTrue(desk.awayOn)
        watch.screenUnlocked()
        XCTAssertFalse(watch.mode.on)
        XCTAssertFalse(desk.awayOn)
    }

    func testNotLinkedNothingTurnsItOn() {
        let watch = makeWatch(linked: false)
        watch.screenLocked()
        watch.turnOn(.phoneMessage)
        watch.toggleFromPanel()
        XCTAssertFalse(watch.mode.on)
        XCTAssertFalse(desk.awayOn)
    }

    func testUnlinkingWhileOnTurnsItOff() {
        let watch = makeWatch()
        watch.turnOn(.phoneButton)
        watch.phoneLinked = false
        XCTAssertFalse(watch.mode.on)
        XCTAssertFalse(desk.awayOn)
    }

    // The Stop hook's script waits for the app only while this file is there.
    func testTheFlagIsThereExactlyWhileAwayIsOn() {
        let watch = makeWatch()
        XCTAssertFalse(flagThere)
        watch.turnOn(.phoneButton)
        XCTAssertTrue(flagThere)
        watch.toggleFromPanel()
        XCTAssertFalse(flagThere)
        watch.screenLocked()
        XCTAssertTrue(flagThere)
        watch.phoneLinked = false
        XCTAssertFalse(flagThere)
    }

    // A copy that quit while Away was on left its flag: the next launch takes it away. The
    // one-second look at the last touch runs only while Away is on.
    func testStartingRemovesAStaleFlagAndTicksOnlyWhileOn() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("away").path, contents: nil)
        let watch = makeWatch()
        watch.start()
        XCTAssertFalse(flagThere)
        XCTAssertNil(watch.timer)
        watch.turnOn(.phoneButton)
        XCTAssertNotNil(watch.timer)
        watch.toggleFromPanel()
        XCTAssertNil(watch.timer)
    }
}
