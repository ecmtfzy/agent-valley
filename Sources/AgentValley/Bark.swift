import Foundation

/// The plan window a limit is in: free, run out for now (fishing), or run out for the week (vacation).
enum LimitState: Equatable {
    case open, fishing, vacation

    init(_ out: RunOut?) {
        guard let out else { self = .open; return }
        self = out.weekly ? .vacation : .fishing
    }
}

/// The rules for who speaks and about what. Pure: no clock reads, no playback.
enum Barks {
    /// A turn this long ends with a long-turn line.
    static let longTurn: TimeInterval = 600

    /// The newest open tool: ExitPlanMode → plan, AskUserQuestion → question, Bash → run,
    /// Edit/Write/MultiEdit/NotebookEdit → edit, WebFetch/WebSearch → web; otherwise
    /// first when `greet`, else generic.
    static func waitTopic(_ row: AgentRow, greet: Bool) -> WaitTopic {
        switch row.info.openTools.last?.tool {
        case "ExitPlanMode": return .plan
        case "AskUserQuestion": return .question
        case "Bash": return .run
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .edit
        case "WebFetch", "WebSearch": return .web
        default: return greet ? .first : .generic
        }
    }

    /// group > long (worked ≥ longTurn) > night (hour ≥ 22 or < 5) > first (first and morning) > short.
    static func doneTopic(group: Bool, worked: TimeInterval, hour: Int, first: Bool) -> DoneTopic {
        if group { return .group }
        if worked >= longTurn { return .long }
        if hour >= 22 || hour < 5 { return .night }
        if first && morning(hour: hour) { return .first }
        return .short
    }

    static func morning(hour: Int) -> Bool { (5..<12).contains(hour) }

    /// The day a moment belongs to: days begin at 05:00.
    static func day(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-5 * 3600))
    }

    static func firstOfDay(last: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let last else { return true }
        return day(last, calendar: calendar) != day(now, calendar: calendar)
    }

    /// nil when nothing is to be said. `resetsAt`: the old run-out's. Back only once it has passed (60 s slack).
    static func scene(from old: LimitState, to new: LimitState, resetsAt: Date?, now: Date) -> CrewScene? {
        switch (old, new) {
        case (.open, .fishing): return .fishout
        case (.open, .vacation), (.fishing, .vacation): return .vanout
        case (.fishing, .open), (.vacation, .open):
            guard let resetsAt, now >= resetsAt.addingTimeInterval(-60) else { return nil }
            return old == .fishing ? .fishback : .vanback
        default: return nil
        }
    }
}

/// No line twice from one group until the rest of the group has been said.
struct LinePicker {
    private var said: [String: [String]] = [:]

    /// `random` gets the number of candidates and returns an index in 0..<n.
    mutating func pick(_ lines: [String], group: String, random: (Int) -> Int) -> String? {
        guard let fallback = lines.first else { return nil }
        var round = said[group] ?? []
        var left = lines.filter { !round.contains($0) }
        if left.isEmpty {
            round = round.last.map { [$0] } ?? []
            left = lines.filter { !round.contains($0) }
        }
        guard !left.isEmpty else { return round.last ?? fallback }
        let line = left[min(max(random(left.count), 0), left.count - 1)]
        said[group] = round + [line]
        return line
    }
}
