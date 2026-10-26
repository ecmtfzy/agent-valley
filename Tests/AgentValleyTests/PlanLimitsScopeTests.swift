import XCTest
@testable import AgentValley

final class PlanLimitsScopeTests: XCTestCase {
    func testBothAccountsKeepSeparateNamedRows() {
        let scope = PlanLimitsScope(sessionIDs: ["codex-session"], claudeEnabled: true, codexEnabled: true)
        XCTAssertEqual(scope.primary, .claude)
        XCTAssertEqual(scope.secondary, .codex)
        XCTAssertEqual(scope.global, .codex)
    }

    func testCodexOnlyNeedsNoClaudeAccount() {
        let scope = PlanLimitsScope(sessionIDs: ["codex-session"], claudeEnabled: false, codexEnabled: true)
        XCTAssertEqual(scope.primary, .codex)
        XCTAssertNil(scope.secondary)
        XCTAssertEqual(scope.global, .codex)
        let disabled = PlanLimitsScope(sessionIDs: ["codex-session"], claudeEnabled: true, codexEnabled: false)
        XCTAssertNil(disabled.global)
    }

    func testMixedSessionsNeverUseOneAccountsGlobalScenesOrRing() {
        for enabled in [(true, true), (true, false), (false, true)] {
            let scope = PlanLimitsScope(sessionIDs: ["/project/claude-session", "codex-session"],
                                        claudeEnabled: enabled.0, codexEnabled: enabled.1)
            XCTAssertNil(scope.global)
        }
    }

    func testNoSessionsRequireExactlyOneEnabledAccount() {
        XCTAssertNil(PlanLimitsScope(sessionIDs: [], claudeEnabled: true, codexEnabled: true).global)
        XCTAssertNil(PlanLimitsScope(sessionIDs: [], claudeEnabled: false, codexEnabled: false).global)
        XCTAssertEqual(PlanLimitsScope(sessionIDs: [], claudeEnabled: true, codexEnabled: false).global, .claude)
        XCTAssertEqual(PlanLimitsScope(sessionIDs: [], claudeEnabled: false, codexEnabled: true).global, .codex)
    }

    func testFailureDoesNotFallBackToAnotherAccountsNumbers() {
        let numbers = PlanLimitsClient.Display.limits(PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil), asOf: nil)
        XCTAssertEqual(PlanLimitsScope.display(for: .codex, claude: numbers, codex: .unavailable(.offline)), .unavailable(.offline))
        XCTAssertEqual(PlanLimitsScope.display(for: .claude, claude: .loading, codex: numbers), .loading)
        XCTAssertEqual(PlanLimitsScope.display(for: nil, claude: numbers, codex: numbers), .off)
    }

    func testClaudeOnlyGlobalBehaviorIsPreserved() {
        let scope = PlanLimitsScope(sessionIDs: ["/project/claude-session"], claudeEnabled: true, codexEnabled: false)
        XCTAssertEqual(scope.primary, .claude)
        XCTAssertNil(scope.secondary)
        XCTAssertEqual(scope.global, .claude)
    }
}
