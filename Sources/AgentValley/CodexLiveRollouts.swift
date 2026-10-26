import Darwin
import Foundation

/// Read-only fallback for indexed desktop sessions whose execution host emits no hooks.
/// Keeps lifecycle/tool names and context only; never makes an approval or message route.
final class CodexLiveRollouts {
    static let maxCandidates = 128
    static let maxReadBytes = 4 * 1024 * 1024
    static let maxLineBytes = 1024 * 1024
    static let tailBytes = 1024 * 1024
    static let discoveryInterval: TimeInterval = 10

    private struct Entry {
        var device: UInt64 = 0
        var inode: UInt64 = 0
        var offset: UInt64 = 0
        var headerEnd: UInt64 = 0
        var modified: Date = .distantPast
        var observedSize: UInt64 = 0
        var waitingForAppend = false
        var readTick: UInt64 = 0
        var verified = false
        var rejected = false
        var bootstrapped = false
        var skippingLine = false
        var info = AgentInfo()
        var status: AgentStatus = .quiet
        var turn: String?
        var retired: [String] = []
        var createdAt: Date?

        mutating func retire(_ id: String?) {
            guard let id, !retired.contains(id) else { return }
            retired.append(id)
            if retired.count > 32 { retired.removeFirst(retired.count - 32) }
        }
    }

    private let home: URL
    private let discovery: CodexUsageReader
    private var lastDiscovery: Date = .distantPast
    private var sources: [CodexUsageReader.Source] = []
    private var titles: [String: String] = [:]
    private var entries: [String: Entry] = [:]
    private var tick: UInt64 = 0
    /// Rollout bytes only. Discovery separately reuses the index/journal reader's bounded
    /// 16 MiB inputs, at most once per ten seconds; it never recursively scans transcripts.
    private(set) var lastReadBytes = 0

    init(home: URL, journal: URL? = nil) {
        self.home = home.standardizedFileURL
        discovery = CodexUsageReader(home: home, journal: journal)
    }

    static func configured(environment: [String: String] = ProcessInfo.processInfo.environment,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CodexLiveRollouts? {
        guard let journal = CodexEventStore.configuredJournal(environment: environment, home: home) else { return nil }
        let selected = environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        return CodexLiveRollouts(home: selected ?? home.appendingPathComponent(".codex"), journal: journal)
    }

    func readCards(now: Date = Date(), visibleFor: TimeInterval = AgentStore.defaultVisibleFor,
                   excluding: Set<String> = []) -> [SessionCard] {
        if now < lastDiscovery || now.timeIntervalSince(lastDiscovery) >= Self.discoveryInterval {
            let snapshot = discovery.snapshot()
            sources = snapshot.sources.filter {
                $0.path.hasPrefix(home.appendingPathComponent("sessions").path + "/") && $0.path.hasSuffix(".jsonl")
            }
            titles = snapshot.titles
            lastDiscovery = now
        }
        let candidates = sources.compactMap { source -> (CodexUsageReader.Source, Date)? in
            guard !excluding.contains(source.id), !excluding.contains("codex-" + source.id),
                  contained(source.path) else { return nil }
            var info = Darwin.stat()
            guard lstat(source.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { return nil }
            let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                                + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard now.timeIntervalSince(modified) < AgentStore.forgetAfter else { return nil }
            return (source, modified)
        }.sorted { ($0.1, $0.0.id) > ($1.1, $1.0.id) }.prefix(Self.maxCandidates)
        let present = Set(candidates.map { $0.0.id })
        entries = entries.filter { present.contains($0.key) }
        var budget = Self.maxReadBytes
        tick &+= 1
        // A continuously growing file or an incomplete EOF cannot starve other candidates.
        let readOrder = candidates.sorted {
            let first = entries[$0.0.id]?.readTick ?? 0, second = entries[$1.0.id]?.readTick ?? 0
            return first == second ? ($0.1, $0.0.id) > ($1.1, $1.0.id) : first < second
        }
        for (source, modified) in readOrder {
            var entry = entries[source.id] ?? Entry()
            if budget > 0 {
                read(source, modified: modified, entry: &entry, now: now, budget: &budget)
                entry.readTick = tick
            }
            entries[source.id] = entry
        }
        lastReadBytes = Self.maxReadBytes - budget
        return candidates.compactMap { source, _ in
            guard let entry = entries[source.id], entry.verified, !entry.rejected,
                  let at = entry.info.lastActivity ?? entry.createdAt,
                  now.timeIntervalSince(at) < AgentStore.forgetAfter,
                  entry.status != .done || now.timeIntervalSince(at) < max(0, visibleFor) else { return nil }
            var info = entry.info
            info.codexTurnID = entry.turn
            info.title = titles["codex-" + source.id] ?? ""
            let id = "codex-" + source.id
            let project = TranscriptReader.clipped((info.cwd as NSString).lastPathComponent)
            let row = AgentRow(id: id + "-main", info: info, status: entry.status,
                               elapsed: max(0, (entry.status == .done ? at : now).timeIntervalSince(info.turnStartedAt ?? at)),
                               quietFor: entry.status == .done ? 0 : max(0, now.timeIntervalSince(at)))
            return SessionCard(id: id, project: project.isEmpty ? "Session" : project, branch: "",
                               main: row, agents: [], startedAt: info.startedAt ?? at,
                               title: info.title, repo: project).asShown
        }.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
    }

    /// Recheck every parent on cached paths: O_NOFOLLOW alone protects only the final name.
    private func contained(_ path: String) -> Bool {
        let prefix = home.path + "/"
        guard path.hasPrefix(prefix) else { return false }
        let components = path.dropFirst(prefix.count).split(separator: "/")
        guard components.first == "sessions", components.count == 5 else { return false }
        var current = home
        for component in components.dropLast() {
            guard component != ".", component != ".." else { return false }
            current.appendPathComponent(String(component))
            var info = Darwin.stat()
            guard lstat(current.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return false }
        }
        return true
    }

    private func read(_ source: CodexUsageReader.Source, modified: Date, entry: inout Entry,
                      now: Date, budget: inout Int) {
        guard contained(source.path) else { entry = Entry(); return }
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var info = Darwin.stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { return }
        let size = UInt64(info.st_size)
        let device = UInt64(bitPattern: Int64(info.st_dev)), inode = UInt64(info.st_ino)
        if entry.device != device || entry.inode != inode || size < entry.observedSize
            || (entry.bootstrapped && size == entry.offset && modified != entry.modified) {
            entry = Entry(device: device, inode: inode)
        }
        if entry.waitingForAppend, entry.observedSize == size, entry.modified == modified { return }
        entry.waitingForAppend = false
        entry.observedSize = size
        entry.modified = modified
        guard !entry.rejected else { return }
        if !entry.verified {
            var header = Data()
            while header.count <= Self.maxLineBytes, UInt64(header.count) < size, budget > 0 {
                let count = min(16 * 1024, Self.maxLineBytes + 1 - header.count)
                guard count > 0, let bytes = Self.bytes(descriptor, offset: UInt64(header.count), count: count, budget: &budget), !bytes.isEmpty else { break }
                header.append(bytes)
                if let end = header.firstIndex(of: 10) {
                    guard end <= Self.maxLineBytes,
                          let object = SafeJSON.object(Data(header[..<end])), object["type"] as? String == "session_meta",
                          let payload = object["payload"] as? [String: Any],
                          CodexUsageReader.sessionID(payload["id"] as? String) == source.id,
                          let origin = payload["source"] as? String,
                          ["cli", "vscode", "exec", "appserver"].contains(origin.lowercased()),
                          payload["parent_thread_id"] == nil || payload["parent_thread_id"] is NSNull,
                          payload["parentThreadId"] == nil || payload["parentThreadId"] is NSNull else {
                        entry.rejected = true; return
                    }
                    entry.verified = true
                    entry.headerEnd = UInt64(end + 1)
                    entry.info.type = "main"
                    entry.info.entrypoint = "codex-rollout"
                    entry.info.cwd = Self.folder(payload["cwd"]) ?? ""
                    entry.info.folder = entry.info.cwd
                    guard let created = Self.date(payload["timestamp"]) ?? Self.date(object["timestamp"]),
                          created <= now.addingTimeInterval(300) else { entry.rejected = true; return }
                    entry.createdAt = min(created, now)
                    entry.info.startedAt = entry.createdAt
                    break
                }
            }
            if !entry.verified {
                if header.count > Self.maxLineBytes { entry.rejected = true }
                else if UInt64(header.count) >= size { entry.waitingForAppend = true }
                return
            }
        }
        guard budget > 0 else { return }
        let bootstrap = !entry.bootstrapped
        if bootstrap {
            // Only session identity/context comes from the header. Never carry an old
            // active turn over the skipped middle of a large file.
            entry.offset = max(entry.headerEnd, size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0)
            if entry.offset > entry.headerEnd {
                guard let previous = Self.bytes(descriptor, offset: entry.offset - 1, count: 1, budget: &budget) else { return }
                entry.skippingLine = previous.first != 10
            }
            entry.bootstrapped = true
        }
        guard size > entry.offset, budget > 0,
              let data = Self.bytes(descriptor, offset: entry.offset,
                                    count: bootstrap ? Self.tailBytes : Self.maxLineBytes + 1, budget: &budget), !data.isEmpty else { return }
        var start = data.startIndex
        while start < data.endIndex {
            guard let end = data[start...].firstIndex(of: 10) else {
                if entry.skippingLine || data.endIndex - start > Self.maxLineBytes {
                    entry.skippingLine = true
                    start = data.endIndex
                } else if entry.offset + UInt64(data.count) >= size {
                    entry.waitingForAppend = true
                }
                break // An incomplete line is reread next time; no transcript text is retained.
            }
            if !entry.skippingLine, end - start <= Self.maxLineBytes {
                consume(Data(data[start..<end]), source: source, entry: &entry, now: now)
            }
            entry.skippingLine = false
            start = end + 1
        }
        entry.offset += UInt64(start)
    }

    private static func bytes(_ descriptor: Int32, offset: UInt64, count: Int, budget: inout Int) -> Data? {
        let limit = min(count, budget)
        guard limit > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: limit)
        let count = pread(descriptor, &buffer, limit, off_t(offset))
        guard count >= 0 else { return nil }
        budget -= count
        return Data(buffer.prefix(count))
    }

    private func consume(_ line: Data, source: CodexUsageReader.Source, entry: inout Entry, now: Date) {
        guard let object = SafeJSON.object(line), let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any],
              let timestamp = Self.date(object["timestamp"]), timestamp <= now.addingTimeInterval(300),
              entry.createdAt.map({ timestamp >= $0 }) ?? true else { return }
        if type == "session_meta" { entry.rejected = true; return } // A different embedded stream is not this file.
        let at = min(timestamp, now)
        if let thread = payload["thread_id"] {
            guard let thread = thread as? String, CodexUsageReader.sessionID(thread) == source.id else { return }
        }
        let turn = Self.identifier(payload["turn_id"])
        if let raw = payload["turn_id"], !(raw is NSNull), turn == nil { return }
        if let turn, entry.retired.contains(turn) { return }
        if type == "turn_context" {
            if let turn, let current = entry.turn, turn != current { return }
            if entry.turn == nil { entry.turn = turn }
            if let model = Self.text(payload["model"], limit: 128) { entry.info.model = Format.model(model) }
            if let folder = Self.folder(payload["cwd"]) {
                if entry.info.cwd.isEmpty { entry.info.cwd = folder }
                entry.info.folder = folder
            }
            return // Context and token accounting cannot make a finished turn active again.
        }
        let event = type == "event_msg" ? payload["type"] as? String : nil
        if event == "task_started" {
            guard let turn, entry.info.lastActivity.map({ at >= $0 }) ?? true else { return }
            if entry.turn != turn { entry.retire(entry.turn) }
            entry.turn = turn
            entry.info.turnStartedAt = at
            entry.info.openTools = []
            entry.info.lastStep = ""
            entry.info.lastStepAsRun = ""
            touch(&entry, at: at, done: false)
            return
        }
        if let turn, let current = entry.turn, turn != current { return }
        if entry.turn == nil { entry.turn = turn }
        if event == "task_complete" || event == "turn_aborted" {
            touch(&entry, at: at, done: true, completed: event == "task_complete")
            return
        }
        if event == "item_completed" {
            guard let item = payload["item"] as? [String: Any], let kind = item["type"] as? String else { return }
            switch kind {
            case "AgentMessage":
                message(item, entry: &entry, at: at)
            case "UserMessage":
                if entry.status != .done { touch(&entry, at: at, done: false) }
            case "Reasoning":
                activity(&entry, at: at)
            case "CommandExecution":
                activity(&entry, at: at, tool: "Bash")
            case "FileChange":
                activity(&entry, at: at, tool: "Edit")
            default: break
            }
        } else if type == "response_item" {
            switch payload["type"] as? String {
            case "message":
                if payload["role"] as? String == "assistant" { message(payload, entry: &entry, at: at) }
            case "reasoning": activity(&entry, at: at)
            case "function_call", "custom_tool_call":
                guard let name = Self.text(payload["name"], limit: 128) else { return }
                activity(&entry, at: at, tool: Self.tool(name), call: Self.identifier(payload["call_id"]))
            case "function_call_output", "custom_tool_call_output":
                guard entry.status == .working || !entry.info.openTools.isEmpty else { return }
                if let call = Self.identifier(payload["call_id"]) { entry.info.openTools.removeAll { $0.id == call } }
                activity(&entry, at: at)
            default: break
            }
        }
    }

    private func message(_ payload: [String: Any], entry: inout Entry, at: Date) {
        // Desktop async question cards also use final_answer. They complete a message,
        // not the running turn; retain only activity, never the question or an approval.
        if let questions = payload["questions"] as? [Any], !questions.isEmpty {
            activity(&entry, at: at)
            return
        }
        switch payload["phase"] as? String {
        case "final", "final_answer": touch(&entry, at: at, done: true, completed: true)
        case "commentary": activity(&entry, at: at)
        default: break
        }
    }

    private func activity(_ entry: inout Entry, at: Date, tool: String? = nil, call: String? = nil) {
        guard entry.status != .done, entry.info.lastActivity.map({ at >= $0 }) ?? true else { return }
        if let tool {
            entry.info.steps += 1
            entry.info.lastStep = tool
            entry.info.lastStepAsRun = tool
            if let call {
                entry.info.openTools.removeAll { $0.id == call }
                entry.info.openTools.append(OpenTool(id: call, tool: tool, input: [:]))
                entry.info.openTools = Array(entry.info.openTools.suffix(TranscriptReader.openToolLimit))
            }
        }
        touch(&entry, at: at, done: false)
    }

    private func touch(_ entry: inout Entry, at: Date, done: Bool, completed: Bool = false) {
        guard entry.info.lastActivity.map({ at >= $0 }) ?? true else { return }
        if completed, let turn = entry.turn {
            let receipt = CodexTurnCompletion(turnID: turn, startedAt: entry.info.turnStartedAt, endedAt: at)
            entry.info.codexCompletedTurns = CodexTurnCompletion.recording(receipt, in: entry.info.codexCompletedTurns)
        }
        entry.info.lastActivity = at
        entry.info.turnStartedAt = entry.info.turnStartedAt ?? at
        entry.info.turnEnded = done
        entry.info.asking = false
        entry.status = done ? .done : .working
        if done { entry.info.openTools = [] }
    }

    private static func date(_ value: Any?) -> Date? { (value as? String).flatMap(TranscriptReader.date(from:)) }
    private static func text(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return TranscriptReader.clipped(value, limit: limit)
    }
    private static func folder(_ value: Any?) -> String? {
        guard let value = value as? String, value.hasPrefix("/"), value.utf8.count <= 4096,
              !value.utf8.contains(0) else { return nil }
        return value
    }
    private static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 128,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                  || [45, 46, 58, 95].contains($0) }) else { return nil }
        return value
    }
    private static func tool(_ name: String) -> String {
        switch name.components(separatedBy: ".").last ?? name {
        case "exec", "exec_command", "shell", "shell_command", "write_stdin": return "Bash"
        case "apply_patch": return "Edit"
        case "read_file", "view_image": return "Read"
        case "search_query", "web_search", "grep", "glob": return "Grep"
        case "spawn_agent", "send_message", "followup_task": return "Agent"
        default: return name
        }
    }
}
