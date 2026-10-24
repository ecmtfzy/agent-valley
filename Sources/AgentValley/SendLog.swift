import Foundation

extension SendRoute {
    /// The route's name for the log. Ids and tab details stay out.
    var kind: String {
        switch self {
        case .superset: return "superset"
        case .tab: return "tab"
        case .stopHook: return "stopHook"
        }
    }
}

extension SendStatus {
    /// The status kind for the log. Never the message, never the detail inside `failed(x)` or `superset(x)`.
    var logKind: String {
        switch self {
        case .received: return "received"
        case .sent: return "sent"
        case .waitingForTurnEnd: return "waitingForTurnEnd"
        case .heldForAnswer: return "heldForAnswer"
        case .notSent(let reason): return "notSent.\(reason.caseName)"
        }
    }
}

/// One line per status: time, id, route, status kind. Nothing the person typed.
enum SendLog {
    static let maxBytes = 256 * 1024

    /// `route` is `SendRoute.kind`, or "none" when the session had no route.
    static func write(id: UUID, route: String, status: SendStatus, to file: URL) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(id.uuidString) \(route) \(status.logKind)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = (try? Data(contentsOf: file)) ?? Data()
        data.append(Data(line.utf8))
        if data.count > maxBytes {
            // Keep the latter half, starting at a line boundary.
            var tail = data.suffix(data.count / 2)
            if let newline = tail.firstIndex(of: 0x0A) { tail = tail[tail.index(after: newline)...] }
            data = Data(tail)
        }
        try? data.write(to: file, options: .atomic)
    }
}
