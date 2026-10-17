import PDFKit
import SwiftUI
import XCTest
@testable import AgentValley

@MainActor
final class ReportPDFTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { TranscriptReader.date(from: text)! }

    /// One project's report, a session for each title, the first the costliest.
    private func report(_ titles: [String]) throws -> HistoryDocument {
        let anchor = date("2026-10-15T12:00:00.000Z")
        let answers = titles.indices.map { index in
            LedgerAnswer(id: "\(index)", at: date("2026-10-12T10:00:00.000Z").addingTimeInterval(Double(index) * 60), folder: "/Users/me/app",
                         session: "s\(index)", model: "claude-opus-5-5", output: (titles.count - index) * 50_000)
        }
        let slice = LedgerSlice(answers: answers, titles: Dictionary(uniqueKeysWithValues: titles.indices.map { ("s\($0)", titles[$0]) }),
                                interval: HistoryReport.interval(of: .month, around: anchor, calendar: utc))
        return try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: anchor, project: "app"), calendar: utc,
                                                  home: "/Users/me", printed: date("2026-10-17T08:00:00.000Z")))
    }

    private func pages(_ document: HistoryDocument) -> Int {
        HistoryDocument.pages(lines: document.lines.count, first: ReportPDF.firstRows, later: ReportPDF.laterRows).count
    }

    func testEveryLineIsInThePDF() throws {
        let document = try report((1...60).map { String(format: "Task %02d", $0) })
        let pdf = try XCTUnwrap(PDFDocument(data: ReportPDF.data(document, calendar: utc)))
        XCTAssertGreaterThan(pages(document), 1)
        XCTAssertEqual(pdf.pageCount, pages(document))
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Statement of work"))
        for word in ["Task 01", "Task 60", "Total", "$1,830.00"] {
            XCTAssertTrue(text.contains(word), word)
        }
        // The total is on the last page.
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)?.string).contains("Total"))
    }

    func testALongThaiTitleStaysOnItsRow() throws {
        let long = String(repeating: "งานปรับหน้า History ให้แสดงต้นทุนแยกตามโปรเจกต์และ session ", count: 5)
        let document = try report([long] + (1...30).map { "Short \($0)" })
        let pdf = try XCTUnwrap(PDFDocument(data: ReportPDF.data(document, calendar: utc)))
        XCTAssertEqual(pdf.pageCount, pages(document))
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 0)?.string).contains("งานปรับหน้า"))
        // Cut on its row, not wrapped onto the next.
        XCTAssertFalse(try XCTUnwrap(pdf.string).contains(long))
    }

    func testAPeriodAsAStatementGivesIt() {
        func period(_ span: Span, _ at: String, _ calendar: Calendar) -> String {
            Format.reportPeriod(HistoryReport.interval(of: span, around: date(at), calendar: calendar), calendar: calendar)
        }
        var monday = utc
        monday.firstWeekday = 2
        XCTAssertEqual(period(.month, "2026-10-15T12:00:00.000Z", utc), "Oct 1 – 31, 2026")
        XCTAssertEqual(period(.week, "2026-10-14T12:00:00.000Z", monday), "Oct 12 – 18, 2026")
        XCTAssertEqual(period(.week, "2026-10-01T12:00:00.000Z", monday), "Sep 28 – Oct 4, 2026")
        XCTAssertEqual(period(.day, "2026-10-12T12:00:00.000Z", utc), "Mon, Oct 12, 2026")
    }

    /// The words over the costliest bar start at it near the left edge and end at it near the
    /// right, so they never hang out into the margin.
    func testAPeakLabelStaysOverTheChart() {
        XCTAssertEqual(ReportPDF.peakAlignment(0, of: 31), .topLeading)
        XCTAssertEqual(ReportPDF.peakAlignment(15, of: 31), .top)
        XCTAssertEqual(ReportPDF.peakAlignment(30, of: 31), .topTrailing)
        XCTAssertEqual(ReportPDF.peakAlignment(0, of: 7), .topLeading)
        XCTAssertEqual(ReportPDF.peakAlignment(3, of: 7), .top)
        XCTAssertEqual(ReportPDF.peakAlignment(6, of: 7), .topTrailing)
        XCTAssertEqual(ReportPDF.peakAlignment(23, of: 24), .topTrailing)
    }

    func testAWriteReplacesTheFileOfTheSameName() throws {
        let document = try report(["One", "Two"])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try ReportPDF.write(document, calendar: utc, folder: folder)
        let second = try ReportPDF.write(document, calendar: utc, folder: folder)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "app October 2026.pdf")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["app October 2026.pdf"])
        XCTAssertNotNil(PDFDocument(url: second))
    }

    // The app's folder is closed to other accounts (the answers socket refuses one that is not),
    // and a report may be the first thing to make it: it and every folder made with it stay private.
    func testTheReportsFolderIsPrivate() throws {
        let document = try report(["One"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("AgentValley/Reports")
        _ = try ReportPDF.write(document, calendar: utc, folder: folder)
        for url in [folder, folder.deletingLastPathComponent()] {
            let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
            XCTAssertEqual(mode & 0o077, 0, url.path)
        }
    }
}
