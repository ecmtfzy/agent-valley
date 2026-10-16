import Foundation

/// What Claude Code itself says a session is doing.
enum SessionActivity: Equatable {
    case busy, waiting, idle
}

struct SessionState: Equatable {
    var activity: SessionActivity
    /// When the activity last changed, if the record says.
    var since: Date?
}

/// One `<pid>.json` record from `~/.claude/sessions`.
struct SessionRecord: Equatable {
    var pid: Int32
    var sessionId: String
    var startedAt: Date
    var state: SessionState
}

/// Reads the records Claude Code keeps of its own live sessions. Claude Code documents none of
/// this, so a record is only ever positive evidence: one that does not parse or check out counts
/// as absent. Never touches the disk, the clock or the process table.
enum SessionRecords {
    /// Whether a file in the folder is a record. The folder also holds `.key` secrets, which must never be opened.
    static func isRecordName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = name.dropLast(".json".count)
        return !stem.isEmpty && stem.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func parse(_ data: Data) -> SessionRecord? {
        guard let object = SafeJSON.object(data),
              let pid = (object["pid"] as? NSNumber)?.int32Value,
              let sessionId = object["sessionId"] as? String, !sessionId.isEmpty,
              let startedAt = (object["startedAt"] as? NSNumber)?.doubleValue,
              let status = object["status"] as? String else { return nil }
        let activity: SessionActivity
        switch status {
        case "busy": activity = .busy
        case "waiting": activity = .waiting
        case "idle": activity = .idle
        default: return nil
        }
        // Times are milliseconds since 1970.
        let since = (object["statusUpdatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return SessionRecord(
            pid: pid, sessionId: sessionId, startedAt: Date(timeIntervalSince1970: startedAt / 1000),
            state: SessionState(activity: activity, since: since)
        )
    }

    /// The state of each session whose record is still held by the process that wrote it, by session id.
    static func states(from records: [SessionRecord], processStart: (Int32) -> Date?) -> [String: SessionState] {
        live(from: records, processStart: processStart).mapValues(\.state)
    }

    /// The record that speaks for each session, by session id: the newest one still held by the process that wrote it.
    /// `processStart` returns when a pid's process started, or nil when there is no such process.
    static func live(from records: [SessionRecord], processStart: (Int32) -> Date?) -> [String: SessionRecord] {
        var newest: [String: SessionRecord] = [:]
        for record in records {
            // A program that took over the pid started after the record was written.
            guard let started = processStart(record.pid), started <= record.startedAt else { continue }
            if let other = newest[record.sessionId], other.startedAt >= record.startedAt { continue }
            newest[record.sessionId] = record
        }
        return newest
    }
}
