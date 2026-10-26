import AppKit
import SwiftUI

/// A History report as A4 pages of PDF: a statement of work from the crew, on the printout
/// paper of the website. Each page is a SwiftUI view drawn into a PDF context, so its words stay
/// words: they can be picked out and searched.
enum ReportPDF {
    static let page = CGSize(width: 595, height: 842)
    /// Table-row units available on the first and later pages. Token annotations
    /// and wrapped model names consume additional units before pagination.
    static let firstRows = 23
    static let laterRows = 43
    static let row: CGFloat = 16
    static let modelNameWidth: CGFloat = 350

    struct ModelPart: Identifiable {
        let id: Int
        let name: String
        /// Only the first piece of a long model name carries its amount.
        let line: CostLine?
        var units: Int {
            let measured = (name as NSString).boundingRect(with: CGSize(width: ReportPDF.modelNameWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 9)])
            return max(1, Int(ceil(measured.height / ReportPDF.row))) + ((line?.unpriced ?? 0) > 0 ? 1 : 0)
        }
    }

    /// Keep the first page's compact summary. Longer model lists get complete,
    /// separately paginated details rather than overflowing the fixed summary.
    static func modelParts(_ document: HistoryDocument) -> [ModelPart] {
        guard document.models.count > 3 || document.models.contains(where: {
            ($0.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)]).width > 110
        }) else { return [] }
        var parts: [ModelPart] = []
        for line in document.models {
            var rest = line.name[...]
            var first = true
            repeat {
                let name = String(rest.prefix(128))
                parts.append(ModelPart(id: parts.count, name: name, line: first ? line : nil))
                rest = rest.dropFirst(name.count)
                first = false
            } while !rest.isEmpty
        }
        return parts
    }

    static func statementPages(_ document: HistoryDocument) -> [Range<Int>] {
        let crewHeight = document.crew.count * 18 + document.crew.filter { $0.unpriced > 0 }.count * 12
        let models = Array(document.models.prefix(3))
        let modelHeight = models.count * 18 + models.filter { $0.unpriced > 0 }.count * 12
        // The original budget already allowed five 18-point summary rows.
        let extra = Int(ceil(Double(max(0, max(crewHeight, modelHeight) - 90)) / Double(row)))
            + (document.unpriced > 0 ? 1 : 0)
        return HistoryDocument.pages(heights: document.lines.map { $0.unpriced > 0 ? 2 : 1 },
                                     total: document.unpriced > 0 ? 2 : 1,
                                     first: max(1, firstRows - extra), later: laterRows)
    }

    static func modelPages(_ document: HistoryDocument, parts: [ModelPart]) -> [Range<Int>] {
        guard !parts.isEmpty else { return [] }
        return HistoryDocument.pages(heights: parts.map(\.units), total: document.unpriced > 0 ? 2 : 1,
                                     first: laterRows, later: laterRows)
    }

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
        let statements = statementPages(document)
        let parts = modelParts(document)
        let models = modelPages(document, parts: parts)
        let pages = statements + models
        for (index, lines) in pages.enumerated() {
            let modelPage = index >= statements.count
            let sheet = ReportPage(document: document, calendar: calendar, lines: lines, number: index + 1, of: pages.count,
                                   modelParts: modelPage ? parts : nil,
                                   last: modelPage ? index == pages.count - 1 : index == statements.count - 1)
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
    /// The costliest bar: the guru's shirt, as what is picked on the panel.
    static let peak = rgb(0xE07B39)
    /// A split's parts by place: amber glass, a darker cream for paper, warm grey.
    static let parts = [rgb(0xE0A030), rgb(0xC9B48A), rgb(0x8C8378)]
}

private extension Font {
    static let paperText = Font.system(size: 9)
    static let figure = Font.system(size: 9, design: .monospaced)
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

// MARK: - A page

private struct ReportPage: View {
    let document: HistoryDocument
    let calendar: Calendar
    let lines: Range<Int>
    let number: Int
    let of: Int
    let modelParts: [ReportPDF.ModelPart]?
    let last: Bool

    private var title: String { Format.spanTitle(document.span, document.interval, calendar: calendar) }
    private var subject: String { document.project ?? "All projects" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if number == 1 { summary } else { runningHead }
            if let modelParts {
                ModelDetailTable(parts: Array(modelParts[lines]), document: document, last: last)
            } else {
                LineTable(document: document, calendar: calendar, lines: lines, last: last)
            }
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

    /// What the client looks for first: whose work, which month, how much. The period keeps its
    /// room; a name too long for the rest is cut in the middle.
    @ViewBuilder private var summary: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Caps("Statement of work")
                Text(verbatim: subject).font(.system(size: 22, weight: .bold)).tracking(-0.3).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: title).font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(verbatim: Format.reportPeriod(document.interval, calendar: calendar))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Ink.dim)
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.bottom, 12)
        Rule(weight: 1.5, color: Ink.type)

        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: Format.reportFacts(document))
                if document.unpriced > 0 { Text(verbatim: Format.unpriced(document.unpriced)) }
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Ink.dim)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Caps("Total at API prices")
                Text(verbatim: Format.dollars(document.total, unpriced: document.unpriced)).font(.system(size: 26, weight: .bold, design: .monospaced)).fixedSize()
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        Rule()

        Chart(document: document, calendar: calendar)
            .padding(.top, 20)
            .padding(.bottom, 16)

        HStack(alignment: .top, spacing: 24) {
            AgentTable(crew: document.crew).frame(maxWidth: .infinity, alignment: .leading)
            ModelTable(models: document.models, continued: !ReportPDF.modelParts(document).isEmpty).frame(width: 196)
        }
        .padding(.bottom, 18)
    }

    // MARK: Later pages

    @ViewBuilder private var runningHead: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: subject).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            Spacer()
            Caps("Statement of work · \(title)")
        }
        .padding(.bottom, 8)
        Rule(weight: 1, color: Ink.type)
            .padding(.bottom, 12)
    }

    // MARK: The foot of every page

    /// The note on the amounts, in type a client reads, and the block-letter mark over the page
    /// number in the corner.
    private var foot: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .bottom, spacing: 24) {
                Text(verbatim: Format.reportNote(printed: document.printed, calendar: calendar))
                    .font(.system(size: 8))
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Wordmark(height: 9)
                    Text(verbatim: Format.pageLabel(number, of: of))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Ink.faint)
                }
                .fixedSize()
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
            if document.unpriced > 0 {
                Text(verbatim: Format.unpricedChartNote).font(.system(size: 7)).foregroundStyle(Ink.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// By agent: a line for each kind of agent, its rows level with By model's beside it, under that
/// table's bar.
private struct AgentTable: View {
    let crew: [HistoryCrewLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps("By agent").padding(.bottom, 18)
            ForEach(crew.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    HStack {
                        Text(verbatim: crew[index].name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: Format.dollars(crew[index].cost, unpriced: crew[index].unpriced)).font(.figure)
                    }
                    .frame(height: 18)
                    if crew[index].unpriced > 0 {
                        Text(verbatim: Format.unpricedTokens(crew[index].unpriced))
                            .font(.system(size: 7)).foregroundStyle(Ink.dim)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 12)
                    }
                    Rule()
                }
            }
        }
    }
}

private struct ModelTable: View {
    let models: [CostLine]
    let continued: Bool

    var body: some View {
        let total = models.reduce(0) { $0 + $1.cost }
        VStack(alignment: .leading, spacing: 0) {
            Caps(continued ? "By model · full list follows" : "By model").padding(.bottom, 9)
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
            ForEach(Array(models.indices.prefix(3)), id: \.self) { index in
                VStack(spacing: 0) {
                    HStack {
                        Text(verbatim: models[index].name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: Format.dollars(models[index])).font(.figure)
                    }
                    .frame(height: 18)
                    if models[index].unpriced > 0 {
                        Text(verbatim: Format.unpricedTokens(models[index].unpriced))
                            .font(.system(size: 7)).foregroundStyle(Ink.dim)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 12)
                    }
                    Rule()
                }
            }
        }
    }
}

/// Full-width model names and measured unpriced use, on as many pages as needed.
private struct ModelDetailTable: View {
    let parts: [ReportPDF.ModelPart]
    let document: HistoryDocument
    let last: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Caps("By model"); Spacer(); Caps("Amount") }.frame(height: ReportPDF.row)
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: part.name).fixedSize(horizontal: false, vertical: true)
                            .frame(width: ReportPDF.modelNameWidth, alignment: .leading)
                        Spacer(minLength: 0)
                        if let line = part.line { Text(verbatim: Format.dollars(line)).font(.figure) }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    if let line = part.line, line.unpriced > 0 {
                        Text(verbatim: Format.unpricedTokens(line.unpriced)).font(.system(size: 8)).foregroundStyle(Ink.dim)
                            .frame(height: ReportPDF.row)
                    }
                }
                .frame(height: CGFloat(part.units) * ReportPDF.row)
                .overlay(alignment: .bottom) { Rule() }
            }
            if last {
                Rule(weight: 1, color: Ink.type)
                HStack {
                    Text(verbatim: "Total").bold()
                    Spacer()
                    Text(verbatim: Format.dollars(document.total, unpriced: document.unpriced)).font(.figure.bold())
                }.frame(height: ReportPDF.row)
                if document.unpriced > 0 {
                    Text(verbatim: Format.unpricedTokens(document.unpriced)).font(.system(size: 8)).foregroundStyle(Ink.dim)
                        .frame(height: ReportPDF.row)
                }
            }
        }
    }
}

// MARK: - The lines

/// The lines of the statement on one page, costliest first, a thin rule under each; on the last
/// page, the total under them.
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
                VStack(alignment: .leading, spacing: 0) {
                    row(index: String(format: "%02d", index + 1),
                    name: Text(verbatim: line.name),
                    middle: sessions
                        ? Text(verbatim: Format.reportDays(line, hourly: hourly, calendar: calendar)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.dim)
                        : Text(verbatim: Format.count(line.sessions)).font(.figure).foregroundStyle(Ink.type),
                    answers: Text(verbatim: Format.count(line.answers)).font(.figure),
                        amount: Text(verbatim: Format.dollars(line)).font(.figure))
                    if line.unpriced > 0 { unpriced(line.unpriced) }
                }.overlay(alignment: .bottom) { Rule() }
            }
            if last {
                Rule(weight: 1, color: Ink.type)
                row(index: "", name: Text(verbatim: "Total").bold(),
                    middle: sessions ? Text(verbatim: "") : Text(verbatim: Format.count(document.sessions)).font(.figure.bold()),
                    answers: Text(verbatim: Format.count(document.answers)).font(.figure.bold()),
                    amount: Text(verbatim: Format.dollars(document.total, unpriced: document.unpriced)).font(.figure.bold()))
                if document.unpriced > 0 { unpriced(document.unpriced) }
            }
        }
    }

    private func unpriced(_ tokens: Int) -> some View {
        Text(verbatim: Format.unpricedTokens(tokens)).font(.system(size: 8)).foregroundStyle(Ink.dim)
            .padding(.leading, 29).frame(maxWidth: .infinity, alignment: .leading).frame(height: ReportPDF.row)
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
    /// "Page 2 of 3".
    static func pageLabel(_ number: Int, of count: Int) -> String { "Page \(number) of \(count)" }

    /// The foot's note: what the amounts are, the prices they come from, and the day printed.
    static func reportNote(printed: Date, calendar: Calendar) -> String {
        "Amounts are what Anthropic's API would charge for the same tokens, at API prices of \(Pricing.checkedOn). "
            + "Printed \(date("EEE, MMM d, yyyy", printed, calendar))."
    }

    /// The whole stretch, as a statement gives its period: "Oct 1 – 31, 2026", "Oct 12 – 18, 2026",
    /// "Sep 28 – Oct 4, 2026", "Mon, Oct 12, 2026".
    static func reportPeriod(_ interval: DateInterval, calendar: Calendar) -> String {
        let last = interval.end.addingTimeInterval(-1)
        if calendar.isDate(interval.start, inSameDayAs: last) { return date("EEE, MMM d, yyyy", interval.start, calendar) }
        let sameMonth = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
        return date("MMM d", interval.start, calendar) + " – " + date(sameMonth ? "d, yyyy" : "MMM d, yyyy", last, calendar)
    }
}
