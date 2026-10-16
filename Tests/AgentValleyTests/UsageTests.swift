import SwiftUI
import XCTest
@testable import AgentValley

final class UsageTests: XCTestCase {
    /// 2026-10-13 14:30:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_901_800)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ secondsAgo: TimeInterval, output: Int = 1, input: Int = 0) -> UsageEntry {
        UsageEntry(at: now.addingTimeInterval(-secondsAgo), totals: TokenTotals(input: input, output: output))
    }

    func testTheLastFiveHoursAndToday() {
        let summary = Usage.summary(of: [
            entry(0, output: 1),                      // this moment
            entry(5 * 3600 - 1, output: 10),          // just inside five hours
            entry(5 * 3600, output: 100),             // five hours to the second: outside
            entry(14 * 3600 + 30 * 60, output: 1000), // midnight to the second: today
            entry(14 * 3600 + 30 * 60 + 1, output: 10_000), // a second before midnight: yesterday
            entry(-60, output: 100_000),              // a clock that ran ahead: not counted
        ], now: now, calendar: utc)
        XCTAssertEqual(summary.fiveHours.output, 11)
        XCTAssertEqual(summary.today.output, 1111)
    }

    func testOutputHourByHour() {
        // Now is 14:30: the hour under way began 30 minutes ago.
        let summary = Usage.summary(of: [
            entry(0, output: 1),                 // 14:30, this hour
            entry(30 * 60, output: 2),           // 14:00 sharp, this hour
            entry(30 * 60 + 1, output: 10),      // 13:59:59, the hour before
            entry(90 * 60, output: 20),          // 13:00 sharp, the hour before
            entry(11 * 3600 + 30 * 60, output: 100),     // 03:00 sharp: the first bar
            entry(11 * 3600 + 30 * 60 + 1, output: 1000), // 02:59:59: before the bars
        ], now: now, calendar: utc)
        XCTAssertEqual(summary.hourly.count, 12)
        XCTAssertEqual(summary.hourly.last, 3)
        XCTAssertEqual(summary.hourly[10], 30)
        XCTAssertEqual(summary.hourly[0], 100)
        XCTAssertEqual(summary.hourly.reduce(0, +), 133)
        XCTAssertTrue(UsageSummary().isEmpty)
        XCTAssertFalse(summary.isEmpty)
    }

    // "5h" stood for two things: the plan's 5-hour limit on the row under the notch, and the
    // last five hours on this line. Three testers who had both in view read them as one. The
    // line says "last 5h", and still fits beside its bars with every number at its widest.
    @MainActor func testTheLineSaysLastFiveHoursAndStillFits() {
        var summary = UsageSummary()
        summary.fiveHours = TokenTotals(input: 0, cacheWrite: 999_900_000, cacheRead: 0, output: 999_900_000)
        summary.today = summary.fiveHours
        let widest = Format.usageLine(summary, named: false)
        XCTAssertEqual(widest, "last 5h 999.9M in, 999.9M out · today 999.9M in, 999.9M out")
        let bars = CGFloat(Usage.bars) * 3 + CGFloat(Usage.bars - 1)
        // The list's width, less its padding on both sides, the bars and the gap before them.
        let room = NotchGeometry.expandedWidth - 12 * 2 - bars - 8
        let line = NSHostingView(rootView: Text(verbatim: widest).font(.system(size: 12, design: .monospaced)).fixedSize())
        XCTAssertGreaterThan(line.fittingSize.width, 300)
        XCTAssertLessThanOrEqual(line.fittingSize.width, room)
    }

    func testTheLineSaysInAndOut() {
        var summary = UsageSummary()
        summary.fiveHours = TokenTotals(input: 2000, cacheWrite: 420_000, cacheRead: 3_100_000, output: 96_400)
        summary.today = TokenTotals(input: 2000, cacheWrite: 920_000, cacheRead: 7_800_000, output: 233_000)
        XCTAssertEqual(Format.usageLine(summary), "Tokens · last 5h 422.0k in, 96.4k out · today 922.0k in, 233.0k out")
        // With less room the word goes: both stretches of time are what the line is for.
        XCTAssertEqual(Format.usageLine(summary, named: false), "last 5h 422.0k in, 96.4k out · today 922.0k in, 233.0k out")
        XCTAssertEqual(Format.usageHelp(summary), "Last 5 hours: 422.0k in, 96.4k out, 3.1M read from cache. Today: 922.0k in, 233.0k out, 7.8M read from cache. Bars: tokens out in each of the last 12 hours.")
        XCTAssertEqual(Format.usageCaption, "Tokens used in the last 5 hours and today, and the History page. Counted from Claude Code's files on this Mac, and kept in AgentValley's own folder so History goes back further than Claude Code keeps its files. Nothing is sent anywhere.")
    }

    // Each bar beside the busiest hour's. An hour with none keeps a mark, so twelve places
    // always show; one with any stands clear of that mark.
    func testBarsStandBesideTheBusiestHour() {
        XCTAssertEqual(UsageBars.heights([0, 5, 10], full: 10), [1, 5, 10])
        XCTAssertEqual(UsageBars.heights([1, 1000], full: 10), [2, 10])
        XCTAssertEqual(UsageBars.heights([0, 0], full: 10), [1, 1])
        XCTAssertEqual(UsageBars.heights([], full: 10), [])
    }
}
