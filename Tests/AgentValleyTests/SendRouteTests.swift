import XCTest
@testable import AgentValley

final class SendRouteTests: XCTestCase {
    let ws = "3F2504E0-4F89-11D3-9A0C-0305E82C3301", term = "9B2C1A7E-0D44-4C1B-8E6F-2A3B4C5D6E7F"
    func env(_ values: [String: String]) -> (String) -> String? { { values[$0] } }

    func testSupersetGoesBySupersetWhenItNamesBothIDs() {
        XCTAssertEqual(SendRoute.route(bundleID: "com.superset.desktop", environment: env(["SUPERSET_WORKSPACE_ID": ws, "SUPERSET_TERMINAL_ID": term]), tab: { nil }),
                       .superset(workspace: ws, terminal: term))
    }
    func testSupersetWithABadIDFallsToTheStopHook() {
        XCTAssertEqual(SendRoute.route(bundleID: "com.superset.desktop", environment: env(["SUPERSET_WORKSPACE_ID": ws, "SUPERSET_TERMINAL_ID": "x; rm"]), tab: { nil }), .stopHook)
    }
    func testTheThreeTerminalsTypeIntoTheirTab() {
        let place = TabPlace(terminal: .iterm, key: "/dev/ttys004")
        XCTAssertEqual(SendRoute.route(bundleID: "com.googlecode.iterm2", environment: env([:]), tab: { place }), .tab(place))
    }
    func testATerminalWithoutItsTabFallsToTheStopHook() {
        XCTAssertEqual(SendRoute.route(bundleID: "com.apple.Terminal", environment: env([:]), tab: { nil }), .stopHook)
    }
    func testEveryOtherAppUsesTheStopHook() {
        for id in ["com.microsoft.VSCode", "dev.warp.Warp-Stable", "com.todesktop.230313mzl4w4u92", nil] as [String?] {
            XCTAssertEqual(SendRoute.route(bundleID: id, environment: env([:]), tab: { nil }), .stopHook)
        }
    }
}
