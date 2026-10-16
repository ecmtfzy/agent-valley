import Foundation

/// Tokens counted over a stretch of time, as Claude Code's transcripts record them.
struct TokenTotals: Equatable {
    var input = 0
    /// Written to the cache: new, like what went in.
    var cacheWrite = 0
    /// Read back from the cache.
    var cacheRead = 0
    var output = 0

    /// What went in and was new: the "in" the panel shows.
    var incoming: Int { input + cacheWrite }

    var isEmpty: Bool { input == 0 && cacheWrite == 0 && cacheRead == 0 && output == 0 }

    static func + (a: TokenTotals, b: TokenTotals) -> TokenTotals {
        TokenTotals(input: a.input + b.input, cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead, output: a.output + b.output)
    }
}

/// What one answer used, and when.
struct UsageEntry: Equatable {
    let at: Date
    var totals: TokenTotals
}

/// What the panel says of token use.
struct UsageSummary: Equatable {
    var fiveHours = TokenTotals()
    var today = TokenTotals()
    /// Tokens out in each of the last twelve clock hours, oldest first; the last is the hour
    /// under way.
    var hourly = [Int](repeating: 0, count: Usage.bars)

    var isEmpty: Bool { fiveHours.isEmpty && today.isEmpty && hourly.allSatisfy { $0 == 0 } }
}

/// Token use added up by stretches of time. No disk and no clock here: everything is handed in.
enum Usage {
    static let window: TimeInterval = 5 * 3600
    static let bars = 12

    /// The totals of the last five hours and of today, and tokens out hour by hour. An answer
    /// dated after `now` is a clock that ran ahead, and is not counted.
    static func summary(of entries: some Sequence<UsageEntry>, now: Date, calendar: Calendar = .current) -> UsageSummary {
        var summary = UsageSummary()
        let dayStart = calendar.startOfDay(for: now)
        // Where the hour under way began: the bars step back from here.
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        for entry in entries where entry.at <= now {
            if now.timeIntervalSince(entry.at) < window { summary.fiveHours = summary.fiveHours + entry.totals }
            if entry.at >= dayStart { summary.today = summary.today + entry.totals }
            // 0 for the hour under way, 1 for the one before it, and so on back.
            let hoursBack = entry.at >= hourStart ? 0 : Int((hourStart.timeIntervalSince(entry.at) / 3600).rounded(.up))
            if hoursBack < bars { summary.hourly[bars - 1 - hoursBack] += entry.totals.output }
        }
        return summary
    }
}
