import Foundation

/// How far the first reading of every transcript has got.
struct ReadingProgress: Equatable {
    let done: Int
    let of: Int
}

/// What one pass over the transcripts came to.
struct LedgerPass: Equatable {
    var summary = UsageSummary()
    /// Whether it found answers it had not seen, or more of ones it had.
    var added = false
    /// Why the history is not being kept, or what became of a file that could not be read.
    var problem: String?
}

/// The answers of a stretch of time, and what names them, for the History page.
struct LedgerSlice: Equatable {
    var answers: [LedgerAnswer] = []
    /// Session ids to the names Claude Code gave them.
    var titles: [String: String] = [:]
    /// Every folder in the history: a session's scratch folder names its session's folder only
    /// in encoded form, and is named by them.
    var folders: [String] = []
    /// When the first answer in the history was given.
    var since: Date?
    /// The stretch it was read for. None until one has been read.
    var interval: DateInterval?
}

/// Counts token use from the transcripts under `root`, and keeps every answer in a database of
/// the app's own, so that History reaches back further than Claude Code keeps its files. The
/// one place that reads the transcripts for token use, and the one place that touches the
/// database. Works on a queue of its own; the database is used from there only, or by a test
/// that calls `scan` and `slice` itself.
final class UsageLedger: ObservableObject {
    static let every: TimeInterval = 60
    /// How far back the line at the foot of the list looks: today, and its twelve hours of bars.
    static let reach: TimeInterval = 24 * 3600
    static var defaultDatabase: URL { AnswerServer.defaultDirectory.appendingPathComponent("history.sqlite") }

    static let schema = """
        CREATE TABLE IF NOT EXISTS answers (id TEXT PRIMARY KEY, at REAL NOT NULL, folder TEXT NOT NULL,
          session TEXT NOT NULL, agent TEXT NOT NULL, model TEXT NOT NULL, fast INTEGER NOT NULL, us INTEGER NOT NULL,
          input INTEGER NOT NULL, write5m INTEGER NOT NULL, write1h INTEGER NOT NULL, read INTEGER NOT NULL,
          output INTEGER NOT NULL, searches INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS answers_at ON answers(at);
        CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, title TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, bytes INTEGER NOT NULL);
        PRAGMA user_version = 1;
        """

    /// An answer met again, on another line or in another transcript: the later time and the
    /// larger of each count. It is the main agent's if either says so, since a session's answer
    /// can be carried in a sub-agent's transcript too, and it takes a sub-agent's type once the
    /// meta file is there to say it.
    private static let upsert = """
        INSERT INTO answers VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET at = max(at, excluded.at),
          agent = CASE WHEN excluded.agent = 'main' OR agent = 'subagent' THEN excluded.agent ELSE agent END,
          input = max(input, excluded.input), write5m = max(write5m, excluded.write5m),
          write1h = max(write1h, excluded.write1h), read = max(read, excluded.read),
          output = max(output, excluded.output), searches = max(searches, excluded.searches)
        """

    /// The last day added up, for the line at the foot of the list. nil while off or not counted yet.
    @Published private(set) var summary: UsageSummary?
    /// Goes up each time a pass has added to the history, for an open History page to read again.
    @Published private(set) var revision = 0
    /// While the first pass reads every transcript there is.
    @Published private(set) var reading: ReadingProgress?
    @Published private(set) var problem: String?

    private let root: String
    private let database: URL
    /// How much of a transcript is read at a time.
    private let piece: Int
    private let queue = DispatchQueue(label: "agent-valley.ledger", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// Only touched on `queue`, or by a test that calls `scan` and `slice` itself.
    private var db: SQLite?
    /// How far each transcript has been read, by path: the `files` table, kept at hand.
    private var bytes: [String: UInt64] = [:]
    /// What became of a database file that could not be read, said on every pass while the app runs.
    private var putAside: String?

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
         database: URL = UsageLedger.defaultDatabase, piece: Int = 1 << 20) {
        self.root = root.resolvingSymlinksInPath().path
        self.database = database
        self.piece = max(1, piece)
    }

    /// Applies the "Token use" setting. Off, nothing is read or written and the database is let
    /// go; what it holds stays.
    func setEnabled(_ on: Bool) {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            guard on else {
                db = nil
                bytes = [:]
                DispatchQueue.main.async { [weak self] in
                    self?.summary = nil
                    self?.reading = nil
                }
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            // By the clock on the wall: after a night asleep the count is brought up to date at
            // once, not a minute into the day.
            timer.schedule(wallDeadline: .now(), repeating: Self.every)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let pass = self.scan(now: Date()) { done, of in
                    DispatchQueue.main.async { [weak self] in self?.reading = ReadingProgress(done: done, of: of) }
                }
                self.publish(pass)
            }
            timer.resume()
            self.timer = timer
        }
    }

    /// Reads what the transcripts have gained since the last pass into the database, and adds
    /// up the last day for the line at the foot of the list. On a first pass, when every
    /// transcript there is is read whole, `progress` hears how many files of how many are done.
    func scan(now: Date, calendar: Calendar = .current, progress: (Int, Int) -> Void = { _, _ in }) -> LedgerPass {
        let db: SQLite
        do {
            db = try opened()
        } catch {
            return LedgerPass(problem: Self.cannotSave(error))
        }
        // Walked by name under the root, and each path built from the root as it stands here:
        // walked by URL, a root under /var comes back spelled /private/var.
        var files: [(path: String, size: UInt64)] = []
        if let walker = FileManager.default.enumerator(atPath: root) {
            for case let relative as String in walker where relative.hasSuffix(".jsonl") {
                let path = root + "/" + relative
                guard AgentStore.classify(path, root: root) != nil,
                      let size = (walker.fileAttributes?[.size] as? NSNumber)?.uint64Value else { continue }
                files.append((path, size))
            }
        }
        let before = bytes
        var added = false
        do {
            try db.execute("BEGIN")
            for (index, file) in files.enumerated() {
                if before.isEmpty, index % 50 == 0 { progress(index, files.count) }
                if try read(file.path, size: file.size, into: db) { added = true }
            }
            // A transcript that is gone: its place is forgotten, its answers kept.
            let seen = Set(files.map(\.path))
            for gone in bytes.keys where !seen.contains(gone) {
                bytes[gone] = nil
                try db.rows("DELETE FROM files WHERE path = ?", [.text(gone)])
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            // Read again next time, from where the last pass that was kept had got.
            bytes = before
            return LedgerPass(summary: (try? lastDay(db, now: now, calendar: calendar)) ?? UsageSummary(), problem: Self.cannotSave(error))
        }
        return LedgerPass(summary: (try? lastDay(db, now: now, calendar: calendar)) ?? UsageSummary(), added: added, problem: putAside)
    }

    /// Every answer given in `interval`, and what names them. Empty while off.
    func slice(_ interval: DateInterval) throws -> LedgerSlice {
        guard let db else { return LedgerSlice() }
        let span: [SQLValue] = [.real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970)]
        let answers = try db.rows("""
            SELECT id, at, folder, session, agent, model, fast, us, input, write5m, write1h, read, output, searches
            FROM answers WHERE at >= ? AND at < ?
            """, span).map {
            LedgerAnswer(id: $0[0].text, at: Date(timeIntervalSince1970: $0[1].real), folder: $0[2].text, session: $0[3].text,
                         agent: $0[4].text, model: $0[5].text, fast: $0[6].int != 0, us: $0[7].int != 0, input: $0[8].int,
                         write5m: $0[9].int, write1h: $0[10].int, read: $0[11].int, output: $0[12].int, searches: $0[13].int)
        }
        let titles = try db.rows("SELECT id, title FROM sessions WHERE id IN (SELECT session FROM answers WHERE at >= ? AND at < ?)", span)
        let folders = try db.rows("SELECT DISTINCT folder FROM answers ORDER BY folder").map { $0[0].text }
        let first = try db.rows("SELECT min(at) FROM answers").first?.first ?? .null
        return LedgerSlice(answers: answers,
                           titles: Dictionary(titles.map { ($0[0].text, $0[1].text) }, uniquingKeysWith: { first, _ in first }),
                           folders: folders, since: first == .null ? nil : Date(timeIntervalSince1970: first.real))
    }

    /// `slice` on the ledger's queue, for the History page. `done` hears on the main thread.
    func load(_ interval: DateInterval, done: @escaping (LedgerSlice) -> Void) {
        queue.async { [self] in
            var slice = (try? slice(interval)) ?? LedgerSlice()
            slice.interval = interval
            DispatchQueue.main.async { done(slice) }
        }
    }

    // MARK: - Inside

    /// The database, opened or made at first need. One that cannot be read is put aside under
    /// another name, never deleted, and a new one is begun from the transcripts still there.
    private func opened() throws -> SQLite {
        if let db { return db }
        // Shared with the socket of "Answer from the notch", which refuses a folder others can enter.
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let made: SQLite
        do {
            made = try Self.prepare(database.path)
        } catch let error as SQLiteError where error.isBroken {
            let aside = database.path + ".broken-" + Self.stamp(Date())
            try FileManager.default.moveItem(atPath: database.path, toPath: aside)
            putAside = "An earlier history file could not be read. It was kept as \((aside as NSString).lastPathComponent)."
            made = try Self.prepare(database.path)
        }
        bytes = try Dictionary(made.rows("SELECT path, bytes FROM files").map { ($0[0].text, UInt64(max(0, $0[1].int))) },
                               uniquingKeysWith: { first, _ in first })
        db = made
        return made
    }

    private static func prepare(_ path: String) throws -> SQLite {
        let db = try SQLite(path: path)
        try db.execute(schema)
        return db
    }

    /// Reads whatever was appended to a transcript since it was last read, into the database.
    /// Whether it found an answer.
    private func read(_ path: String, size: UInt64, into db: SQLite) throws -> Bool {
        var done = bytes[path] ?? 0
        // Shorter than what was read: written anew. Read again from its start; its answers are
        // known by their ids, so none is counted twice.
        if size < done { done = 0 }
        guard size > done, let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: done)) != nil else { return false }
        let agent = Self.agent(of: path, root: root)
        // A main transcript is named for its session: a title line that does not say whose is its.
        let session = agent == "main" ? String((path as NSString).lastPathComponent.dropLast(".jsonl".count)) : nil
        var found = false
        // A piece at a time, each let go before the next. What follows a piece's last newline is
        // carried into the next piece.
        var rest = Data()
        var more = true
        while more {
            more = try autoreleasepool {
                guard let next = try? handle.read(upToCount: piece), !next.isEmpty else { return false }
                rest.append(next)
                // Up to the last whole line: one caught half-written is read when the rest is there.
                let (lines, consumed) = TranscriptReader.completeLines(in: rest)
                for line in lines {
                    if let answer = LedgerAnswer(line: line, agent: agent) {
                        try db.rows(Self.upsert, Self.values(answer))
                        found = true
                    } else if let title = Self.title(fromLine: line, session: session) {
                        try db.rows("INSERT INTO sessions VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title",
                                    [.text(title.session), .text(title.title)])
                    }
                }
                done += UInt64(consumed)
                rest.removeSubrange(rest.startIndex..<rest.startIndex + consumed)
                return true
            }
        }
        bytes[path] = done
        try db.rows("INSERT INTO files VALUES (?, ?) ON CONFLICT(path) DO UPDATE SET bytes = excluded.bytes", [.text(path), .int(Int64(done))])
        return found
    }

    /// "main" for a session's own transcript. For a sub-agent's, its type from the meta file
    /// beside it, or "subagent" while there is none.
    static func agent(of path: String, root: String) -> String {
        guard case .sub? = AgentStore.classify(path, root: root) else { return "main" }
        guard let meta = FileManager.default.contents(atPath: String(path.dropLast(".jsonl".count)) + ".meta.json"),
              let type = SafeJSON.object(meta)?["agentType"] as? String, !type.isEmpty else { return "subagent" }
        return type
    }

    /// The name Claude Code gave a session, from its `ai-title` line. One that does not say
    /// whose it is is `session`'s, when that is known.
    static func title(fromLine line: Data, session: String?) -> (session: String, title: String)? {
        guard line.range(of: Data("\"ai-title\"".utf8)) != nil, let object = SafeJSON.object(line),
              object["type"] as? String == "ai-title", let title = object["aiTitle"] as? String, !title.isEmpty,
              let id = object["sessionId"] as? String ?? session, !id.isEmpty else { return nil }
        return (id, title)
    }

    private static func values(_ answer: LedgerAnswer) -> [SQLValue] {
        [.text(answer.id), .real(answer.at.timeIntervalSince1970), .text(answer.folder), .text(answer.session),
         .text(answer.agent), .text(answer.model), .int(answer.fast ? 1 : 0), .int(answer.us ? 1 : 0),
         .int(Int64(answer.input)), .int(Int64(answer.write5m)), .int(Int64(answer.write1h)), .int(Int64(answer.read)),
         .int(Int64(answer.output)), .int(Int64(answer.searches))]
    }

    /// The line at the foot of the list: the last day's answers, added up as before.
    private func lastDay(_ db: SQLite, now: Date, calendar: Calendar) throws -> UsageSummary {
        let rows = try db.rows("SELECT at, input, write5m + write1h, read, output FROM answers WHERE at > ?",
                               [.real(now.addingTimeInterval(-Self.reach).timeIntervalSince1970)])
        return Usage.summary(of: rows.map {
            UsageEntry(at: Date(timeIntervalSince1970: $0[0].real),
                       totals: TokenTotals(input: $0[1].int, cacheWrite: $0[2].int, cacheRead: $0[3].int, output: $0[4].int))
        }, now: now, calendar: calendar)
    }

    private static func cannotSave(_ error: Error) -> String {
        "History can't be saved: " + ((error as? SQLiteError)?.message ?? error.localizedDescription)
    }

    /// "2026-10-15-143005", for the name of a file put aside.
    private static func stamp(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        return format.string(from: date)
    }

    private func publish(_ pass: LedgerPass) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.summary != pass.summary { self.summary = pass.summary }
            if self.problem != pass.problem { self.problem = pass.problem }
            if self.reading != nil { self.reading = nil }
            if pass.added { self.revision += 1 }
        }
    }
}
