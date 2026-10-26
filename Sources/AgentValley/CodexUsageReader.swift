import Darwin
import Foundation

/// Usage from the local rollouts of sessions already known to AgentValley's hooks.
/// No transcript text, credentials, or rate-limit/credit details are retained. The
/// existing ledger and history render these answers, including its unknown-price state.
final class CodexUsageReader {
    struct Source {
        let id: String
        let path: String
    }

    struct Snapshot {
        var sources: [Source] = []
        var titles: [String: String] = [:]
    }

    struct Counts: Codable, Equatable {
        var input: Int
        var cached: Int
        var written: Int
        var output: Int

        init?(object: [String: Any]?) {
            guard let object else { return nil }
            func number(_ key: String, optional: Bool = false) -> Int? {
                guard let value = object[key] else { return optional ? 0 : nil }
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                      (0...1_000_000_000_000).contains(number.doubleValue) else { return nil }
                return number.intValue
            }
            guard let input = number("input_tokens"), let cached = number("cached_input_tokens", optional: true),
                  let written = number("cache_write_input_tokens", optional: true), let output = number("output_tokens"),
                  cached <= input, written <= input - cached else { return nil }
            self.input = input; self.cached = cached; self.written = written; self.output = output
        }

        init(input: Int, cached: Int, written: Int, output: Int) {
            self.input = input; self.cached = cached; self.written = written; self.output = output
        }

        func increase(over old: Counts) -> Counts? {
            guard input >= old.input, cached >= old.cached, written >= old.written, output >= old.output else { return nil }
            let change = Counts(input: input - old.input, cached: cached - old.cached,
                                written: written - old.written, output: output - old.output)
            return change.cached + change.written <= change.input ? change : nil
        }
    }

    /// Persisted next to the ledger's file cursor. It contains only usage/context metadata,
    /// so restarting the app does not count the previous cumulative total a second time.
    struct State: Codable, Equatable {
        var offset: UInt64 = 0
        var device: UInt64 = 0
        var inode: UInt64 = 0
        var skippingLongLine = false
        var verified = false
        var rejected = false
        var session = ""
        var folder = ""
        var model = ""
        var agent = "main"
        var turn = ""
        var createdAt: Date?
        var total: Counts?

        var json: String? {
            (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
        }

        static func decode(_ text: String?) -> State {
            text.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        }
    }

    struct Batch {
        var state: State
        var answers: [LedgerAnswer] = []
    }

    static let maxReadBytes = 2 * 1024 * 1024
    static let maxLineBytes = 1024 * 1024
    private let home: URL
    private let journal: URL

    init(home: URL, journal: URL) {
        self.home = home.standardizedFileURL
        self.journal = journal
    }

    static func configured(environment: [String: String] = ProcessInfo.processInfo.environment,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CodexUsageReader? {
        guard let journal = CodexEventStore.configuredJournal(environment: environment, home: home) else { return nil }
        let configured = environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        return CodexUsageReader(home: configured ?? home.appendingPathComponent(".codex"), journal: journal)
    }

    /// UUID v7 encodes the creation date. Only three possible date folders for each known
    /// session are listed, rather than walking all of the user's conversation history.
    func snapshot() -> Snapshot {
        guard let journalData = Self.privateData(journal, limit: 16 * 1024 * 1024) else { return Snapshot() }
        let ids = Set(journalData.split(separator: 10).flatMap { line -> [String] in
            guard line.count <= 32 * 1024, let object = SafeJSON.object(Data(line)),
                  object["version"] as? Int == 1,
                  let session = Self.sessionID(object["session_id"] as? String) else { return [] }
            if ["SubagentStart", "SubagentStop"].contains(object["event"] as? String ?? ""),
               let child = Self.sessionID(object["agent_id"] as? String) { return [session, child] }
            return [session]
        })
        guard !ids.isEmpty else { return Snapshot() }
        let manager = FileManager.default
        var wanted: [String: Set<String>] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for id in ids {
            guard let date = Self.creationDate(id) else { continue }
            for shift in -1...1 {
                let day = date.addingTimeInterval(Double(shift) * 86400)
                let fields = calendar.dateComponents([.year, .month, .day], from: day)
                let suffix = String(format: "%04d/%02d/%02d", fields.year!, fields.month!, fields.day!)
                wanted[home.appendingPathComponent("sessions/" + suffix).path, default: []].insert(id)
            }
        }
        // Archived rollouts are flat in current Codex releases. Listing names does not read
        // their contents; only an exact journal-known UUID can become a source.
        wanted[home.appendingPathComponent("archived_sessions").path] = ids
        var sources: [String: Source] = [:]
        for (directory, allowed) in wanted.sorted(by: { $0.key < $1.key }) {
            guard let names = try? manager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names.sorted() where name.hasPrefix("rollout-") && name.hasSuffix(".jsonl") {
                guard name.count > 42, let id = Self.sessionID(String(name.dropLast(6).suffix(36))), allowed.contains(id) else { continue }
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                // Refuse escaped symlinks and non-files. The transcript verifies its own id too.
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(home.resolvingSymlinksInPath().path + "/"),
                      (try? manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular,
                      sources[id] == nil || url.path.hasPrefix(home.appendingPathComponent("sessions").path + "/") else { continue }
                sources[id] = Source(id: id, path: url.path)
            }
        }
        var titles: [String: String] = [:]
        if let index = Self.privateData(home.appendingPathComponent("session_index.jsonl"), limit: 16 * 1024 * 1024) {
            for line in index.split(separator: 10) where line.count <= 32 * 1024 {
                guard let object = SafeJSON.object(Data(line)), let id = Self.sessionID(object["id"] as? String), ids.contains(id),
                      let title = object["thread_name"] as? String, !title.isEmpty else { continue }
                titles["codex-" + id] = TranscriptReader.clipped(title)
            }
        }
        return Snapshot(sources: sources.values.sorted { $0.id < $1.id }, titles: titles)
    }

    /// Bounded incremental reading. A partial line is read again next time, never persisted
    /// as transcript text; oversized lines are skipped without stalling the cursor.
    func read(_ source: Source, state original: State) -> Batch {
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return Batch(state: original) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var stat = Darwin.stat()
        guard fstat(descriptor, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG, stat.st_size >= 0 else { return Batch(state: original) }
        var state = original
        let device = UInt64(bitPattern: Int64(stat.st_dev)), inode = UInt64(stat.st_ino)
        if state.device != device || state.inode != inode || state.offset > UInt64(stat.st_size) {
            state = State(device: device, inode: inode)
        }
        guard UInt64(stat.st_size) > state.offset, (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.read(upToCount: Self.maxReadBytes), !data.isEmpty else { return Batch(state: state) }
        var answers: [LedgerAnswer] = []
        var start = data.startIndex
        while start < data.endIndex {
            guard let end = data[start...].firstIndex(of: 10) else {
                if state.skippingLongLine || data.endIndex - start > Self.maxLineBytes {
                    state.skippingLongLine = true
                    start = data.endIndex
                }
                break
            }
            if !state.skippingLongLine, end - start <= Self.maxLineBytes,
               let answer = Self.consume(Data(data[start..<end]), source: source, state: &state) {
                answers.append(answer)
            }
            state.skippingLongLine = false
            start = end + 1
        }
        state.offset += UInt64(start - data.startIndex)
        return Batch(state: state, answers: answers)
    }

    static func consume(_ line: Data, source: Source, state: inout State) -> LedgerAnswer? {
        guard let object = SafeJSON.object(line), let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return nil }
        if type == "session_meta" {
            guard Self.sessionID(payload["id"] as? String) == source.id else { state.rejected = true; return nil }
            guard !state.rejected else { return nil }
            state.verified = true
            state.session = "codex-" + source.id
            state.folder = Self.folder(payload["cwd"])
            state.createdAt = (payload["timestamp"] as? String).flatMap(TranscriptReader.date(from:))
            if let source = payload["source"] as? [String: Any], let sub = source["subagent"] as? [String: Any],
               let spawn = sub["thread_spawn"] as? [String: Any] {
                if let parent = Self.sessionID(spawn["parent_thread_id"] as? String) { state.session = "codex-" + parent }
                state.agent = (spawn["agent_role"] as? String).flatMap { $0.isEmpty ? nil : TranscriptReader.clipped($0, limit: 80) } ?? "subagent"
            }
            return nil
        }
        guard state.verified, !state.rejected else { return nil }
        if type == "turn_context" {
            if let model = payload["model"] as? String, !model.isEmpty { state.model = TranscriptReader.clipped(model, limit: 128) }
            if let turn = payload["turn_id"] as? String { state.turn = TranscriptReader.clipped(turn, limit: 128) }
            let folder = Self.folder(payload["cwd"])
            if !folder.isEmpty { state.folder = folder }
            return nil
        }
        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = Counts(object: info["total_token_usage"] as? [String: Any]),
              let last = Counts(object: info["last_token_usage"] as? [String: Any]),
              let stamp = object["timestamp"] as? String, let at = TranscriptReader.date(from: stamp) else { return nil }
        // A fork can carry earlier conversation lines. They are already charged to the
        // source session; only usage after this session was created belongs here.
        if let created = state.createdAt, at < created { state.total = total; return nil }
        let previous = state.total
        state.total = total
        guard previous != total else { return nil } // Rate-limit-only updates repeat the usage.
        // A file may begin after a fork, or a reset may start a fresh cumulative counter.
        // Only the explicitly reported last response is attributable in either case.
        let counts = previous.flatMap { total.increase(over: $0) } ?? last
        guard counts.input + counts.output > 0 else { return nil }
        let id = "codex-" + source.id + ":usage:" + stamp + ":\(total.input):\(total.cached):\(total.written):\(total.output)"
        // Codex input includes cache reads/writes; reasoning is already included in output.
        return LedgerAnswer(id: id, at: at, folder: state.folder, session: state.session,
                            agent: state.agent, model: state.model,
                            input: counts.input - counts.cached - counts.written,
                            write5m: counts.written, read: counts.cached, output: counts.output)
    }

    private static func folder(_ value: Any?) -> String {
        guard let text = value as? String, text.hasPrefix("/"), text.utf8.count <= 4096 else { return "" }
        return text
    }

    static func sessionID(_ text: String?) -> String? {
        guard let text, UUID(uuidString: text)?.uuidString.lowercased() == text.lowercased() else { return nil }
        return text.lowercased()
    }

    private static func creationDate(_ id: String) -> Date? {
        let hex = id.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32, hex[hex.index(hex.startIndex, offsetBy: 12)] == "7",
              let milliseconds = UInt64(hex.prefix(12), radix: 16) else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private static func privateData(_ url: URL, limit: Int) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var stat = Darwin.stat()
        guard fstat(descriptor, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG,
              stat.st_size >= 0, stat.st_size <= limit else { return nil }
        return try? handle.read(upToCount: limit)
    }
}
