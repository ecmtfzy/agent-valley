import Darwin
import Foundation

/// An opt-in, read-only view of the small event journal written by the Codex hook bridge.
/// This never reads Codex transcripts, sends an answer, or changes either app's settings.
/// Call on the store queue. A journal is separate from Claude's transcripts and usage ledger.
final class CodexEventStore {
    static let environmentKey = "AGENTVALLEY_CODEX_EVENTS"
    /// Installing the hook bridge creates this journal explicitly. Its presence opts Finder
    /// and login launches into Codex monitoring without a shell environment variable.
    static func configuredJournal(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        if let path = environment[environmentKey] {
            return path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
        }
        let journal = home.appendingPathComponent("Library/Application Support/AgentValley/codex/events.jsonl")
        return FileManager.default.fileExists(atPath: journal.path) ? journal : nil
    }
    static let maxEventBytes = 32 * 1024
    static let maxReadBytes = 2 * 1024 * 1024
    static let maxSessions = 256
    static let maxChildren = 64

    private struct Row {
        var info = AgentInfo()
        var status: AgentStatus = .quiet
        var at: Date

        mutating func touch(_ date: Date) {
            at = max(at, date)
            info.lastActivity = at
        }

        mutating func finish(at date: Date) {
            touch(date)
            status = .done
            info.turnEnded = true
            info.asking = false
            info.openTools = []
        }

        func shown(id: String, now: Date) -> AgentRow {
            let quietFor = max(0, now.timeIntervalSince(at))
            // There is no hook heartbeat or proof that a missing result still waits for a person.
            let shown: AgentStatus = status == .needsYou && quietFor >= AgentStore.askingVisibleFor ? .quiet : status
            return AgentRow(id: id, info: info, status: shown,
                            elapsed: max(0, (status == .done ? at : now).timeIntervalSince(info.turnStartedAt ?? info.startedAt ?? at)),
                            quietFor: status == .done ? 0 : quietFor)
        }
    }

    private struct Session {
        struct Permission {
            let toolID: String?
            let step: String
            let stepAsRun: String
            let sequence: Int
        }
        var main: Row
        var children: [String: Row] = [:]
        var turn: String?
        var retiredTurns: [String] = []
        var legacyWaitingTools: Set<String> = []
        var legacyUnmatchedPermission = false
        var permissions: [String: Permission] = [:]
        var waitingTools: Set<String> { legacyWaitingTools.union(permissions.values.compactMap(\.toolID)) }
        var unmatchedPermission: Bool { legacyUnmatchedPermission || permissions.values.contains { $0.toolID == nil } }
        var permissionSequence = 0
        var permissionAt: Date?
        var permissionStep = ""
        var permissionStepAsRun = ""
        var toolSteps: [String: (label: String, asRun: String)] = [:]
        var runtimePermissionEligible = false
        var closed = false
        var movedAt: Date { max(main.at, children.values.map(\.at).max() ?? main.at) }

        var waitingStep: String {
            permissions.values.max { $0.sequence < $1.sequence }?.step ?? permissionStep
        }
        var waitingStepAsRun: String {
            permissions.values.max { $0.sequence < $1.sequence }?.stepAsRun ?? permissionStepAsRun
        }

        mutating func clearPermissions() {
            legacyWaitingTools = []
            legacyUnmatchedPermission = false
            permissions = [:]
        }

        mutating func retire(_ turn: String?) {
            guard let turn, !retiredTurns.contains(turn) else { return }
            retiredTurns.append(turn)
            if retiredTurns.count > 32 { retiredTurns.removeFirst(retiredTurns.count - 32) }
        }
    }

    private struct Event {
        let kind: String
        let session: String
        let at: Date
        let cwd: String
        let model: String
        let turn: String?
        let tool: String?
        let toolID: String?
        let agent: String?
        let agentType: String?
        let requestID: String?
        let decision: String?
        let displayInput: [String: Any]

        init?(_ data: Data, now: Date) {
            guard data.count <= CodexEventStore.maxEventBytes,
                  let object = SafeJSON.object(data), object["version"] as? Int == 1,
                  let kind = object["event"] as? String, CodexEventStore.events.contains(kind),
                  let session = object["session_id"] as? String, CodexEventStore.isID(session),
                  let timestamp = object["timestamp"] as? String,
                  let at = TranscriptReader.date(from: timestamp) else { return nil }
            // Even a local journal is untrusted. A bad clock cannot pin a card in the future.
            self.at = min(at, now)
            self.kind = kind
            self.session = session
            let cwd = object["cwd"] as? String ?? ""
            self.cwd = cwd.hasPrefix("/") && cwd.utf8.count <= 4096 ? cwd : ""
            model = TranscriptReader.clipped(object["model"] as? String ?? "", limit: 128)
            turn = (object["turn_id"] as? String).flatMap { CodexEventStore.isID($0) ? $0 : nil }
            tool = (object["tool_name"] as? String).map { TranscriptReader.clipped($0, limit: 128) }
            toolID = (object["tool_use_id"] as? String).flatMap { CodexEventStore.isID($0) ? $0 : nil }
            agent = (object["agent_id"] as? String).flatMap { CodexEventStore.isID($0) ? $0 : nil }
            agentType = (object["agent_type"] as? String).map { TranscriptReader.clipped($0, limit: 80) }
            requestID = (object["request_id"] as? String).flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
            decision = object["decision"] as? String
            // This is only a bounded display summary. Never put it in OpenTool.input:
            // it is not the original request and cannot authorize or identify an answer.
            var summary: [String: Any] = [:]
            var remaining = 8192
            if let input = object["display_input"] as? [String: Any] {
                for key in ["command", "description", "file_path", "path", "pattern", "query", "url", "name"] {
                    if let text = input[key] as? String, text.utf8.count <= remaining {
                        summary[key] = text
                        remaining -= text.utf8.count
                    }
                }
            }
            if summary["file_path"] == nil { summary["file_path"] = summary["path"] }
            displayInput = summary
            if kind == "PermissionResolved", requestID == nil || !["allow", "deny"].contains(decision ?? "") { return nil }
        }
    }

    private static let events: Set<String> = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PermissionResolved",
                                              "PostToolUse", "Stop", "Interrupt", "SessionEnd",
                                              "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"]
    private static func isID(_ text: String) -> Bool {
        (1...128).contains(text.utf8.count) && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 95 || $0 == 46 || $0 == 58
        }
    }

    let path: String
    private var identity: (device: Int32, inode: UInt64)?
    private var offset: UInt64 = 0
    private var pending = Data()
    private var skippingLongLine = false
    private var sessions: [String: Session] = [:]

    init(path: String) { self.path = path }

    /// Each new request invalidates any live-status evidence about an older approval.
    /// Tool progress does not change this token; concurrent results must not re-arm a wait.
    var pendingApprovalTokens: [String: String] {
        Dictionary(uniqueKeysWithValues: sessions.compactMap { id, session in
            guard session.runtimePermissionEligible, session.waitingTools.count == 1,
                  !session.unmatchedPermission,
                  let at = session.permissionAt else { return nil }
            return ("codex-" + id, "\(session.turn ?? ""):\(at.timeIntervalSince1970):\(session.permissionSequence)")
        })
    }

    /// One-shot diagnostics drain the bridge's maximum 16 MiB journal, rather than showing
    /// only its first polling batch. The live UI keeps the smaller per-tick work budget.
    func readAllCards(now: Date = Date(), visibleFor: TimeInterval = AgentStore.defaultVisibleFor) -> [SessionCard] {
        var cards: [SessionCard] = []
        for _ in 0..<8 {
            let before = offset
            cards = readCards(now: now, visibleFor: visibleFor)
            if offset == before { break }
        }
        return cards
    }

    /// Reads a bounded amount per tick. Incomplete final lines wait for the next read; malformed
    /// records are skipped. Replacement or truncation starts a fresh view of that journal.
    func readCards(now: Date = Date(), visibleFor: TimeInterval = AgentStore.defaultVisibleFor) -> [SessionCard] {
        read(now: now)
        sessions = sessions.filter { now.timeIntervalSince($0.value.movedAt) < AgentStore.forgetAfter }
        return sessions.compactMap { id, session in
            let allDone = session.main.status == .done && session.children.values.allSatisfy { $0.status == .done }
            guard !allDone || now.timeIntervalSince(session.movedAt) < max(0, visibleFor) else { return nil }
            let key = "codex-" + id // The final component itself is namespaced: AnswerStore strips parent paths.
            let source = session.main.info
            let cwd = source.cwd
            let project = TranscriptReader.clipped((cwd as NSString).lastPathComponent)
            // Project paths can live behind a cloud provider or a macOS permission prompt.
            // Even O_NONBLOCK cannot bound opening a regular placeholder file. Keep the
            // polling queue on the private journal; git metadata comes from the daemon.
            let repo = cwd.isEmpty ? "" : Projects.name(of: cwd, home: NSHomeDirectory())
            return SessionCard(id: key, project: project.isEmpty ? "Session" : project, branch: source.branch,
                               main: session.main.shown(id: key + "-main", now: now),
                               agents: session.children.sorted { ($0.value.info.startedAt ?? .distantPast, $0.key) < ($1.value.info.startedAt ?? .distantPast, $1.key) }
                                   .map { $0.value.shown(id: key + "-" + $0.key, now: now) },
                               startedAt: session.main.info.startedAt ?? session.main.at,
                               title: source.title,
                               repo: repo,
                               closed: session.closed).asShown
        }.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
    }

    private func read(now: Date) {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var stat = Darwin.stat()
        guard fstat(descriptor, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG, stat.st_size >= 0 else { return }
        let next = (device: stat.st_dev, inode: stat.st_ino)
        if identity?.device != next.device || identity?.inode != next.inode || UInt64(stat.st_size) < offset {
            identity = next
            offset = 0
            pending = Data()
            skippingLongLine = false
            sessions = [:]
        }
        guard lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else { return }
        var remaining = Self.maxReadBytes
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        while remaining > 0 {
            let count = Darwin.read(descriptor, &bytes, min(bytes.count, remaining))
            guard count > 0 else { break }
            offset += UInt64(count)
            remaining -= count
            consume(Data(bytes.prefix(count)), now: now)
        }
    }

    private func consume(_ bytes: Data, now: Date) {
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let newline = bytes[start...].firstIndex(of: 10)
            let end = newline ?? bytes.endIndex
            if !skippingLongLine {
                if pending.count + end - start <= Self.maxEventBytes {
                    pending.append(bytes[start..<end])
                } else {
                    pending.removeAll(keepingCapacity: true)
                    skippingLongLine = true
                }
            }
            guard let newline else { break }
            if !skippingLongLine, let event = Event(pending, now: now) { apply(event) }
            pending.removeAll(keepingCapacity: true)
            skippingLongLine = false
            start = newline + 1
        }
    }

    private func apply(_ event: Event) {
        var session = sessions[event.session] ?? Session(main: Row(at: event.at))
        if session.main.info.startedAt == nil {
            session.main.info.startedAt = event.at
            session.main.info.type = "main"
            session.main.info.entrypoint = "codex-hook"
        }
        // Turn ids outrank arrival order for delayed callbacks from a completed or replaced turn.
        let childLifecycle = event.kind == "SubagentStart" || event.kind == "SubagentStop"
        if let turn = event.turn, session.retiredTurns.contains(turn),
           event.kind != "SessionEnd", event.kind != "UserPromptSubmit", !childLifecycle { return }
        if event.kind == "UserPromptSubmit" {
            if session.turn != event.turn || session.main.status == .done {
                if session.turn != event.turn { session.retire(session.turn) }
                session.turn = event.turn
                session.main.info.turnStartedAt = event.at
            } else if session.main.info.turnStartedAt == nil {
                session.main.info.turnStartedAt = event.at
            }
            // An explicit new prompt is authoritative, including continuation of the same turn.
            session.retiredTurns.removeAll { $0 == event.turn }
        } else if let turn = event.turn, !childLifecycle {
            if let current = session.turn, current != turn, event.kind != "SessionEnd" { return }
            if session.turn == nil { session.turn = turn }
        }
        if session.closed && event.kind != "SessionStart" && event.kind != "UserPromptSubmit" { return }
        // A bridge response belongs to exactly one outstanding request. Delayed or duplicate
        // answers must not refresh a finished card or clear a different request in this turn.
        if event.kind == "PermissionResolved",
           event.requestID.flatMap({ session.permissions[$0] }) == nil { return }
        if !event.cwd.isEmpty {
            // The first folder names the project; a later cwd only changes the current place.
            if session.main.info.cwd.isEmpty { session.main.info.cwd = event.cwd }
            session.main.info.folder = event.cwd
        }
        if !event.model.isEmpty { session.main.info.model = Format.model(event.model) }

        switch event.kind {
        case "SessionStart":
            if session.closed { session.main.status = .quiet; session.main.info.turnEnded = false }
            session.closed = false
            session.main.touch(event.at)
        case "UserPromptSubmit":
            session.closed = false
            session.main.touch(event.at)
            session.main.status = .working
            session.main.info.turnEnded = false
            session.main.info.asking = false
            session.main.info.openTools = []
            session.toolSteps = [:]
            session.clearPermissions()
        case "SubagentStart", "SubagentStop":
            guard let id = event.agent else { return }
            if session.children[id] == nil, session.children.count >= Self.maxChildren { return }
            var row = session.children[id] ?? Row(at: event.at)
            if row.status == .done, event.kind == "SubagentStart" { return }
            row.info.startedAt = row.info.startedAt ?? event.at
            row.info.turnStartedAt = row.info.turnStartedAt ?? event.at
            row.info.type = event.agentType ?? "general-purpose"
            row.info.cwd = session.main.info.cwd
            row.info.folder = session.main.info.folder
            // Parent lifecycle hooks do not establish the child model or its individual tool calls.
            if event.kind == "SubagentStart" {
                row.touch(event.at)
                row.status = .working
                row.info.turnEnded = false
            } else {
                row.finish(at: event.at)
            }
            session.children[id] = row
        case "Stop", "Interrupt":
            session.main.finish(at: event.at)
            session.clearPermissions()
            session.retire(event.turn ?? session.turn)
        case "SessionEnd":
            session.main.finish(at: event.at)
            for id in Array(session.children.keys) { session.children[id]?.finish(at: event.at) }
            session.closed = true
            session.clearPermissions()
            session.retire(event.turn ?? session.turn)
        case "PermissionResolved":
            guard let requestID = event.requestID,
                  let answered = session.permissions.removeValue(forKey: requestID) else { return }
            session.main.touch(event.at)
            session.main.info.asking = false
            let waiting = session.unmatchedPermission || !session.waitingTools.isEmpty
            session.main.status = waiting ? .needsYou : .working
            session.main.info.lastStep = waiting ? session.waitingStep : answered.step
            session.main.info.lastStepAsRun = waiting ? session.waitingStepAsRun : answered.stepAsRun
        default:
            // No turn id means a delayed result cannot be distinguished from new work. A finished
            // main row resumes only on a new prompt or session, never from a stray tool callback.
            guard session.main.status != .done else { return }
            session.main.touch(event.at)
            session.main.info.asking = false // The bridge does not transmit the question or command.
            session.main.info.turnEnded = false
            let name = event.tool ?? "Tool"
            if event.kind == "PreToolUse" {
                session.main.info.steps += 1
                session.main.info.lastStep = TranscriptReader.stepLabel(tool: Self.animationTool(name), input: event.displayInput)
                session.main.info.lastStepAsRun = TranscriptReader.stepLabel(tool: Self.animationTool(name), input: event.displayInput, asRun: true)
                if let id = event.toolID {
                    session.main.info.openTools.removeAll { $0.id == id }
                    session.main.info.openTools.append(OpenTool(id: id, tool: Self.animationTool(name), input: [:]))
                    session.main.info.openTools = Array(session.main.info.openTools.suffix(TranscriptReader.openToolLimit))
                    session.toolSteps[id] = (session.main.info.lastStep, session.main.info.lastStepAsRun)
                    let open = Set(session.main.info.openTools.map(\.id))
                    session.toolSteps = session.toolSteps.filter { open.contains($0.key) }
                }
            } else if event.kind == "PermissionRequest" {
                session.permissionSequence += 1
                session.permissionAt = event.at
                // PermissionRequest does not document a tool_use_id. A single matching open
                // call is enough to identify it; two calls with the same name are ambiguous
                // because this observer deliberately never receives their arguments.
                let matches = session.main.info.openTools.filter { $0.tool == Self.animationTool(name) }
                let permissionID = event.toolID ?? (matches.count == 1 ? matches[0].id : nil)
                let labels = permissionID.flatMap { session.toolSteps[$0] }
                session.permissionStep = labels?.label ?? TranscriptReader.stepLabel(tool: Self.animationTool(name), input: event.displayInput)
                session.permissionStepAsRun = labels?.asRun ?? TranscriptReader.stepLabel(tool: Self.animationTool(name), input: event.displayInput, asRun: true)
                // Live status is thread-wide, so an overlapping request cannot safely use
                // another request's waiting → active transition as approval evidence.
                session.runtimePermissionEligible = session.waitingTools.isEmpty
                    && !session.unmatchedPermission && permissionID != nil
                    && session.main.info.openTools.count == 1
                if let requestID = event.requestID,
                   session.permissions[requestID] != nil || session.permissions.count < TranscriptReader.openToolLimit {
                    session.permissions[requestID] = Session.Permission(toolID: permissionID,
                        step: session.permissionStep, stepAsRun: session.permissionStepAsRun, sequence: session.permissionSequence)
                } else if let id = permissionID,
                   session.waitingTools.contains(id) || session.waitingTools.count < TranscriptReader.openToolLimit {
                    session.legacyWaitingTools.insert(id)
                } else {
                    // A separate flag cannot accidentally match an actual tool-use id.
                    session.legacyUnmatchedPermission = true
                }
            } else if event.kind != "PreCompact" && event.kind != "PostCompact" {
                if let id = event.toolID {
                    session.main.info.openTools.removeAll { $0.id == id }
                    session.toolSteps.removeValue(forKey: id)
                    session.legacyWaitingTools.remove(id)
                    session.permissions = session.permissions.filter { $0.value.toolID != id }
                }
            }
            let waiting = session.unmatchedPermission || !session.waitingTools.isEmpty
            session.main.status = waiting ? .needsYou : .working
            if waiting {
                session.main.info.lastStep = session.waitingStep
                session.main.info.lastStepAsRun = session.waitingStepAsRun
            }
        }
        sessions[event.session] = session
        if sessions.count > Self.maxSessions,
           let oldest = sessions.min(by: { ($0.value.movedAt, $0.key) < ($1.value.movedAt, $1.key) })?.key {
            sessions[oldest] = nil
        }
    }

    /// Hook tool names mapped to the existing step formatter and animation selector.
    /// These display names are never sent to either agent.
    private static func animationTool(_ name: String) -> String {
        let leaf = name.components(separatedBy: ".").last ?? name
        switch leaf {
        case "exec_command", "shell", "shell_command", "write_stdin": return "Bash"
        case "apply_patch": return "Edit"
        case "read_file", "view_image": return "Read"
        case "search_query", "web_search", "grep", "glob": return "Grep"
        case "spawn_agent", "send_message", "followup_task": return "Agent"
        default: return name
        }
    }

    /// A diagnostic view with no prompt, tool input, tool output, credential or approval path.
    static func diagnostic(_ cards: [SessionCard]) -> [[String: Any]] {
        cards.map { card in
            ["id": card.id, "project": card.project, "name": card.name, "closed": card.closed,
             "rows": card.rows.map { row -> [String: Any] in
                let status: String
                switch row.status {
                case .working: status = "working"
                case .quiet: status = "quiet"
                case .needsYou: status = "needsYou"
                case .done: status = "done"
                }
                return ["id": row.id, "type": row.info.type, "model": row.info.model,
                        "status": status, "step": row.step, "steps": row.info.steps]
             }]
        }
    }
}
