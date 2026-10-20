import XCTest
@testable import AgentValley
import Sparkle

final class UpdatesTests: XCTestCase {
    // A build to work on the app carries no feed: it must never replace itself with a release.
    func testNoFeedMeansNoUpdater() {
        XCTAssertFalse(Updates.isConfigured([:]))
        XCTAssertFalse(Updates.isConfigured(["SUFeedURL": "https://x", "SUPublicEDKey": ""]))
        XCTAssertFalse(Updates.isConfigured(["SUFeedURL": "", "SUPublicEDKey": "k"]))
        XCTAssertTrue(Updates.isConfigured(["SUFeedURL": "https://x", "SUPublicEDKey": "k"]))
        XCTAssertFalse(Updates(info: [:]).isAvailable)
        XCTAssertNil(Updates(info: [:]).waiting)
    }

    // Sparkle counts the minute after launch, at login too, as a good time for its window. The
    // person may be typing by then: a check on its own never shows it, the panel's line does.
    func testACheckOnItsOwnNeverShowsAWindow() {
        let updates = Updates(info: [:])
        XCTAssertFalse(updates.standardUserDriverShouldHandleShowingScheduledUpdate(.empty(), andInImmediateFocus: true))
        XCTAssertFalse(updates.standardUserDriverShouldHandleShowingScheduledUpdate(.empty(), andInImmediateFocus: false))
    }

    // Have a look and Check now both open Sparkle's window under the panel. The panel gets out
    // of its way, as a menu does when one of its items opens a window (screen test, 2026-10-20).
    // A build to work on has no window to show, so nothing is put away for it.
    func testThePanelMakesWayForTheUpdateWindow() throws {
        let updates = Updates(info: [:])
        var asked = 0
        updates.willShowWindow = { asked += 1 }
        updates.checkNow()
        updates.show()
        XCTAssertEqual(asked, 0)
        let window = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentValley/NotchWindow.swift")
        XCTAssertTrue(try String(contentsOf: window, encoding: .utf8).contains("updates.willShowWindow = { [weak self] in self?.closeFromKeyboard() }"))
    }
}
