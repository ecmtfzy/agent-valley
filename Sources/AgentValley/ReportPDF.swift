import AppKit
import SwiftUI

/// A History report as A4 pages of PDF: a statement of work from the crew, on the printout
/// paper of the website. Each page is a SwiftUI view drawn into a PDF context, so its words stay
/// words: they can be picked out and searched.
enum ReportPDF {
    static let page = CGSize(width: 595, height: 842)
    /// Lines of the table on the first page, under the summary, and on each page after it. Rows
    /// are one line each and all as tall, so this is known before anything is drawn.
    static let firstRows = 19
    static let laterRows = 42
    static let row: CGFloat = 16

    /// Where the words over the costliest bar sit: from the bar rightwards in the first quarter of
    /// the chart, leftwards in the last, centred between.
    static func peakAlignment(_ index: Int, of count: Int) -> Alignment {
        let edge = max(1, count / 4)
        return index < edge ? .topLeading : index >= count - edge ? .topTrailing : .top
    }

    @MainActor static func data(_ document: HistoryDocument, calendar: Calendar) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let pages = HistoryDocument.pages(lines: document.lines.count, first: firstRows, later: laterRows)
        for (index, lines) in pages.enumerated() {
            let sheet = ReportPage(document: document, calendar: calendar, lines: lines, number: index + 1, of: pages.count)
                .frame(width: page.width, height: page.height)
                .environment(\.colorScheme, .light)
                // Fine enough that every cell of the logo and the faces lands on the same grid.
                .environment(\.displayScale, 8)
            let renderer = ImageRenderer(content: sheet)
            renderer.proposedSize = ProposedViewSize(page)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// Writes the report as `document.fileName` in `folder`, made if missing. A report of the same
    /// name there is replaced: the folder is the app's own, and one worth keeping has been moved.
    /// Folders made here are closed to other accounts: a report can be the first thing to make the
    /// app's folder, and the answers socket refuses one that others can enter.
    @MainActor static func write(_ document: HistoryDocument, calendar: Calendar,
                                 folder: URL = AnswerServer.defaultDirectory.appendingPathComponent("Reports")) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(document.fileName(calendar: calendar))
        try data(document, calendar: calendar).write(to: file, options: .atomic)
        return file
    }
}

// MARK: - The paper

/// The website's printout paper and ink.
private enum Ink {
    static let paper = rgb(0xFBF7EE)
    static let type = rgb(0x2A2118)
    static let dim = rgb(0x6B6052)
    static let faint = rgb(0x9A8F80)
    static let rule = rgb(0xD8CDB8)
    static let greenbar = rgb(0xE3ECD4)
    /// The costliest bar: the guru's shirt, as what is picked on the panel.
    static let peak = rgb(0xE07B39)
    /// A split's parts by place: amber glass, a darker cream for paper, warm grey.
    static let parts = [rgb(0xE0A030), rgb(0xC9B48A), rgb(0x8C8378)]
}

private extension Font {
    static let paperText = Font.system(size: 9)
    static let figure = Font.system(size: 9, design: .monospaced)
    static let small = Font.system(size: 7.5)
}

/// A small label in capitals, as on a form.
private struct Caps: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Ink.dim)
    }
}

private struct Rule: View {
    var weight: CGFloat = 0.5
    var color = Ink.rule

    var body: some View { Rectangle().fill(color).frame(height: weight) }
}

/// The block-letter name of the website's logo, drawn from its own pixels.
private struct Wordmark: View {
    let height: CGFloat

    private static let rows = [
        "d.LLLLLLd.LLLLLLd.LLLLLLd.LLLLLLd.LLLLLLd.LLd.LLd.LLLLLLd.LLd.d.d.LLd.d.d.LLLLLLd.LLd.LL",
        "..LLLLLL..LLLLLL..LLLLLL..LLLLLL..LLLLLL..LL..LL..LLLLLL..LL......LL......LLLLLL..LL..LL",
        ".dLL..LL.dLL.....dLL.....dLL..LL.d..LL...dLL.dLL.dLL..LL.dLL.d.d.dLL.d.d.dLL.....dLL.dLL",
        "..LL..LL..LL......LL......LL..LL....LL....LL..LL..LL..LL..LL......LL......LL......LL..LL",
        "d.LLLLLLd.LLd.LLd.LLLLLLd.LLd.LLd.d.LLd.d..LLLL.d.LLLLLLd.LLd.d.d.LLd.d.d.LLLLLLd.d.LLd.",
        "..LLLLLL..LL..LL..LLLLLL..LL..LL....LL.....LLLL...LLLLLL..LL......LL......LLLLLL....LL..",
        ".dLL..LL.dLL.dLL.dLL.....dLL.dLL.d.dLL.d.d.LLLL..dLL..LL.dLL.d.d.dLL.d.d.dLL.....d.dLL.d",
        "..LL..LL..LL..LL..LL......LL..LL....LL.....LLLL...LL..LL..LL......LL......LL........LL..",
        "d.LLd.LLd.LLLLLLd.LLLLLLd.LLd.LLd.d.LLd.d.d.LLd.d.LLd.LLd.LLLLLLd.LLLLLLd.LLLLLLd.d.LLd.",
        "..LL..LL..LLLLLL..LLLLLL..LL..LL....LL......LL....LL..LL..LLLLLL..LLLLLL..LLLLLL....LL..",
        ".d...d...d.......d.......d...d...d.d...d.d.d...d.d...d...d.......d.......d.......d.d...d",
        "........................................................................................",
    ].map(Array.init)

    var body: some View {
        Pixels(cells: Self.rows, size: height * 88 / 12) { cell in
            switch cell {
            case "L": rgb(0x23190F)
            case "d": rgb(0xB8A685)
            default: nil
            }
        }
        .accessibilityLabel(Text(verbatim: "AgentValley"))
    }
}

private struct Face: View {
    let person: Person
    let size: CGFloat

    var body: some View {
        Pixels(cells: person.rows.map(Array.init), size: size, colour: person.colour)
    }
}

// MARK: - A page

private struct ReportPage: View {
    let document: HistoryDocument
    let calendar: Calendar
    let lines: Range<Int>
    let number: Int
    let of: Int

    private var title: String { Format.spanTitle(document.span, document.interval, calendar: calendar) }
    private var subject: String { document.project ?? "All projects" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if number == 1 { summary } else { runningHead }
            LineTable(document: document, calendar: calendar, lines: lines, last: number == of)
            Spacer(minLength: 0)
            foot
        }
        .padding(.horizontal, 46)
        .padding(.top, 38)
        .padding(.bottom, 32)
        .foregroundStyle(Ink.type)
        .font(.paperText)
        .background(Ink.paper)
    }

    // MARK: The first page

    @ViewBuilder private var summary: some View {
        HStack(alignment: .bottom) {
            Wordmark(height: 15)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Caps("Statement of work")
                Text(verbatim: title).font(.system(size: 11, weight: .bold, design: .monospaced))
            }
        }
        .padding(.bottom, 12)
        Rule(weight: 1.5, color: Ink.type)

        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                if document.project != nil { Caps("Project") }
                Text(verbatim: subject).font(.system(size: 22, weight: .bold)).tracking(-0.3).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Caps("At API prices")
                Text(verbatim: Format.dollars(document.total)).font(.system(size: 26, weight: .bold, design: .monospaced)).fixedSize()
            }
        }
        .padding(.top, 16)
        HStack {
            Text(verbatim: Format.reportFacts(document))
            Spacer(minLength: 8)
            if document.unpriced > 0 { Text(verbatim: Format.unpriced(document.unpriced)) }
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(Ink.dim)
        .padding(.top, 5)
        .padding(.bottom, 10)
        Rule()

        HStack(alignment: .top, spacing: 12) {
            field("Period", Format.reportPeriod(document.interval, calendar: calendar))
            field("Printed", Format.date("EEE, MMM d, yyyy", document.printed, calendar))
            field("Priced at", "API prices of \(Pricing.checkedOn)")
        }
        .padding(.vertical, 9)

        Chart(document: document, calendar: calendar)
            .padding(.top, 14)
            .padding(.bottom, 16)

        HStack(alignment: .top, spacing: 24) {
            CrewTable(crew: document.crew).frame(maxWidth: .infinity, alignment: .leading)
            ModelTable(models: document.models).frame(width: 196)
        }
        .padding(.bottom, 18)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Caps(label)
            Text(verbatim: value).font(.system(size: 8.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Later pages

    @ViewBuilder private var runningHead: some View {
        HStack(alignment: .center, spacing: 10) {
            Wordmark(height: 9)
            Text(verbatim: subject).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            Spacer()
            Caps("Statement of work · \(title)")
        }
        .padding(.bottom, 8)
        Rule(weight: 1, color: Ink.type)
            .padding(.bottom, 12)
    }

    // MARK: The foot of every page

    /// Sunny, Walt, Norm, Pearl, Judy, Faye and Felix.
    private static let crew: [Person] = [.guru, .walrus, .engineer, .pearls, .coder, .afro, .beatnik]

    private var foot: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .bottom, spacing: 14) {
                HStack(spacing: 2) {
                    ForEach(Self.crew.indices, id: \.self) { index in Face(person: Self.crew[index], size: 18) }
                }
                Text(verbatim: Format.reportCrewNote)
                    .font(.small)
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: "\(number) / \(of)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Ink.faint)
            }
            .padding(.top, 10)
        }
    }
}

// MARK: - Parts of the first page

/// A bar a day, or an hour on a day's report. The costliest is orange and says what it was.
private struct Chart: View {
    let document: HistoryDocument
    let calendar: Calendar
    private let height: CGFloat = 34

    var body: some View {
        let hourly = document.span == .day
        let top = document.bars.map(\.cost).max() ?? 0
        let peak = top > 0 ? document.bars.firstIndex { $0.cost == top } : nil
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(document.bars.indices, id: \.self) { index in
                    let bar = document.bars[index]
                    let flat = bar.cost <= 0 || bar.interval.start > document.printed
                    Rectangle()
                        .fill(index == peak ? Ink.peak : flat ? Ink.rule : Ink.type)
                        .frame(height: flat ? 1.5 : max(1.5, height * bar.cost / top))
                        .overlay(alignment: ReportPDF.peakAlignment(index, of: document.bars.count)) {
                            if index == peak {
                                Text(verbatim: Format.peakLabel(bar, hourly: hourly, calendar: calendar))
                                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Ink.peak)
                                    .fixedSize()
                                    .offset(y: -11)
                            }
                        }
                }
            }
            .frame(height: height, alignment: .bottom)
            if let first = document.bars.first, let last = document.bars.last {
                HStack {
                    Text(verbatim: Format.axisLabel(first, hourly: hourly, calendar: calendar))
                    Spacer()
                    Text(verbatim: Format.axisLabel(last, hourly: hourly, calendar: calendar))
                }
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundStyle(Ink.faint)
            }
        }
    }
}

private struct CrewTable: View {
    let crew: [HistoryCrewLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps("Who did the work").padding(.bottom, 7)
            ForEach(crew.indices, id: \.self) { index in
                let line = crew[index]
                HStack(spacing: 8) {
                    Face(person: line.kind.person, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: line.name).font(.system(size: 9, weight: .semibold))
                        Text(verbatim: line.detail + " · " + Format.counted(line.answers, "answer", "answers"))
                            .font(.small)
                            .foregroundStyle(Ink.dim)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: Format.dollars(line.cost)).font(.figure)
                }
                .frame(height: 26)
            }
        }
    }
}

private struct ModelTable: View {
    let models: [CostLine]

    var body: some View {
        let total = models.reduce(0) { $0 + $1.cost }
        VStack(alignment: .leading, spacing: 0) {
            Caps("By model").padding(.bottom, 9)
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(models.indices, id: \.self) { index in
                        Rectangle().fill(Ink.parts[min(index, Ink.parts.count - 1)])
                            .frame(width: total > 0 ? geometry.size.width * models[index].cost / total : 0)
                    }
                }
            }
            .frame(height: 5)
            .clipShape(RoundedRectangle(cornerRadius: 2.5))
            .padding(.bottom, 4)
            ForEach(models.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    HStack {
                        Text(verbatim: models[index].name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: Format.dollars(models[index])).font(.figure)
                    }
                    .frame(height: 18)
                    Rule()
                }
            }
        }
    }
}

// MARK: - The lines

/// The lines of the statement on one page, costliest first, banded every three rows as
/// continuous-form paper is; on the last page, the total under them.
private struct LineTable: View {
    let document: HistoryDocument
    let calendar: Calendar
    let lines: Range<Int>
    let last: Bool

    private var sessions: Bool { document.project != nil }
    private var hourly: Bool { document.span == .day }

    var body: some View {
        VStack(spacing: 0) {
            row(index: "", name: Caps(sessions ? "Session" : "Project"),
                middle: Caps(sessions ? (hourly ? "Time" : "Days") : "Sessions"),
                answers: Caps("Answers"), amount: Caps("Amount"))
            ForEach(Array(lines), id: \.self) { index in
                let line = document.lines[index]
                row(index: String(format: "%02d", index + 1),
                    name: Text(verbatim: line.name),
                    middle: sessions
                        ? Text(verbatim: Format.reportDays(line, hourly: hourly, calendar: calendar)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.dim)
                        : Text(verbatim: Format.count(line.sessions)).font(.figure).foregroundStyle(Ink.type),
                    answers: Text(verbatim: Format.count(line.answers)).font(.figure),
                    amount: Text(verbatim: Format.dollars(line)).font(.figure))
                    .background(index % 6 < 3 ? Ink.greenbar : .clear)
            }
            if last {
                Rule(weight: 1, color: Ink.type)
                row(index: "", name: Text(verbatim: "Total").bold(),
                    middle: sessions ? Text(verbatim: "") : Text(verbatim: Format.count(document.sessions)).font(.figure.bold()),
                    answers: Text(verbatim: Format.count(document.answers)).font(.figure.bold()),
                    amount: Text(verbatim: Format.dollars(document.total)).font(.figure.bold()))
            }
        }
    }

    private func row(index: String, name: some View, middle: some View, answers: some View, amount: some View) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: index).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.faint)
                .frame(width: 24, alignment: .leading)
            name.lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            middle.lineLimit(1).frame(width: sessions ? 78 : 60, alignment: sessions ? .leading : .trailing)
            answers.lineLimit(1).frame(width: 60, alignment: .trailing)
            amount.lineLimit(1).frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .frame(height: ReportPDF.row)
    }
}

extension Format {
    static let reportCrewNote = "Prepared by the crew in the notch. Amounts are what Anthropic's API would charge for the same tokens."

    /// The whole stretch, as a statement gives its period: "Oct 1 – 31, 2026", "Oct 12 – 18, 2026",
    /// "Sep 28 – Oct 4, 2026", "Mon, Oct 12, 2026".
    static func reportPeriod(_ interval: DateInterval, calendar: Calendar) -> String {
        let last = interval.end.addingTimeInterval(-1)
        if calendar.isDate(interval.start, inSameDayAs: last) { return date("EEE, MMM d, yyyy", interval.start, calendar) }
        let sameMonth = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
        return date("MMM d", interval.start, calendar) + " – " + date(sameMonth ? "d, yyyy" : "MMM d, yyyy", last, calendar)
    }
}
