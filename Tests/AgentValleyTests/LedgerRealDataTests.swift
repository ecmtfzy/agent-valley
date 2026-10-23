import XCTest
@testable import AgentValley

/// Reads every transcript on this Mac into a database of its own, as the app's first pass does,
/// and says what this month came to. For checking the ledger against another count of the same
/// files; it writes nothing the app uses. Skipped unless LEDGER_REAL is set; LEDGER_FROM names a database to begin from.
final class LedgerRealDataTests: XCTestCase {
    func testThisMonthFromTheRealTranscripts() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_REAL"] != nil else {
            throw XCTSkip("Reads every transcript on this Mac: run with LEDGER_REAL=1.")
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-ledger-real-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let database = base.appendingPathComponent("history.sqlite")
        // With LEDGER_FROM, begun from a copy of that database, as the app's own after an update.
        if let from = ProcessInfo.processInfo.environment["LEDGER_FROM"] {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: from, toPath: database.path)
        }
        let ledger = UsageLedger(database: database)
        let started = Date()
        let pass = ledger.scan(now: Date())
        XCTAssertNil(pass.problem)
        let seconds = Date().timeIntervalSince(started)
        let pick = HistoryPick(span: .month, anchor: Date())
        let calendar = HistoryReport.calendar()
        let report = HistoryReport.make(try ledger.slice(HistoryReport.interval(of: .month, around: Date(), calendar: calendar)),
                                        pick: pick, calendar: calendar, home: NSHomeDirectory())
        let all = try ledger.slice(DateInterval(start: .distantPast, end: .distantFuture))
        print("ledger-real: first pass \(String(format: "%.1f", seconds))s, \(all.answers.count) answers, \(all.checkouts.count) folders with a checkout")
        print("ledger-real: month \(Format.dollars(report.total)), \(report.unpriced) tokens with no price")
        for line in report.projects.prefix(8) { print("ledger-real: project \(line.name) \(Format.dollars(line))") }
        for line in report.models { print("ledger-real: model \(line.name) \(Format.dollars(line))") }
        for line in report.agents { print("ledger-real: agent \(line.name) \(Format.dollars(line))") }
    }
}
