import Foundation

/// Supplies the same card fields as a transcript does, from the shared daemon's
/// real thread summary. Slow reads run separately from the store and UI queues.
final class CodexSessionMetadata {
    struct Details: Equatable {
        let threadID: String
        let status: String
        let name: String?
        let cwd: String?
        let model: String?
        let branch: String?
        let parentID: String?
        let role: String?
        let task: String?

        init?(_ object: [String: Any], expected: String) {
            guard Self.id(expected) != nil, object["thread_id"] as? String == expected else { return nil }
            threadID = expected
            status = object["status"] as? String ?? "unknown"
            func text(_ key: String, limit: Int = TranscriptReader.stepDetailLimit) -> String? {
                guard let raw = object[key] as? String else { return nil }
                let value = TranscriptReader.clipped(raw, limit: limit).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            name = text("name")
            if let raw = object["cwd"] as? String, raw.hasPrefix("/"), raw.utf8.count <= 4096,
               !raw.utf8.contains(0) { cwd = raw } else { cwd = nil }
            model = text("model", limit: 128).map(Format.model)
            let branch = text("git_branch")
            self.branch = branch == "HEAD" ? nil : branch
            parentID = (object["parent_thread_id"] as? String).flatMap(Self.id)
            role = text("agent_role", limit: 80)
            task = text("task_preview") ?? text("agent_nickname")
        }

        static func id(_ value: String) -> String? {
            guard let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value.lowercased() else { return nil }
            return uuid.uuidString.lowercased()
        }
    }

    private struct Candidate {
        let id: String
        let revision: String
        let active: Bool
    }

    private struct Entry {
        var details: Details?
        var revision: String
        var lastAttempt: TimeInterval = -.infinity
        var nextAttempt: TimeInterval = -.infinity
        var verifiedLoaded = false
        var verifiedAt: TimeInterval = -.infinity
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var inFlight: String?
    private let now: () -> TimeInterval
    private let read: (String) -> [String: Any]?
    private let schedule: (@escaping () -> Void) -> Void
    private let desktop: OwnerApp?

    convenience init() {
        let worker = DispatchQueue(label: "agent-valley.codex-metadata", qos: .utility)
        self.init(reader: { CodexRuntimeStatus.readObject($0, details: true) },
                  desktop: Self.desktopApp(), schedule: { worker.async(execute: $0) })
    }

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         reader: @escaping (String) -> [String: Any]?, desktop: OwnerApp?,
         schedule: @escaping (@escaping () -> Void) -> Void) {
        self.now = now
        self.read = reader
        self.desktop = desktop
        self.schedule = schedule
    }

    /// Called on the store queue. The lock covers only small in-memory dictionaries;
    /// neither a subprocess nor AppKit is asked while it is held.
    func enrich(cards: [SessionCard]) -> [SessionCard] {
        var candidates: [String: Candidate] = [:]
        func add(_ id: String, row: AgentRow?) {
            guard candidates.count < 1024 else { return }
            let revision = "\(row?.info.turnStartedAt?.timeIntervalSince1970 ?? 0):\(row?.status == .done)"
            candidates[id] = Candidate(id: id, revision: revision, active: row?.status != .done)
        }
        for card in cards {
            guard let id = Self.threadID(card.id) else { continue }
            add(id, row: card.main)
            for row in card.agents {
                if let child = Self.childID(row.id, cardID: card.id) { add(child, row: row) }
            }
        }
        let at = now()
        lock.lock()
        cache = cache.filter { candidates[$0.key] != nil }
        for candidate in candidates.values {
            if var entry = cache[candidate.id] {
                if entry.revision != candidate.revision {
                    entry.revision = candidate.revision
                    // A new turn or a completed turn can acquire a new title. Avoid
                    // turning rapid events into repeated metadata subprocesses.
                    entry.nextAttempt = min(entry.nextAttempt, max(at, entry.lastAttempt + 5))
                    cache[candidate.id] = entry
                }
            } else {
                cache[candidate.id] = Entry(revision: candidate.revision)
            }
        }
        var next: Candidate?
        if inFlight == nil, let oldest = cache.filter({ $0.value.nextAttempt <= at }).min(by: {
            ($0.value.lastAttempt, $0.key) < ($1.value.lastAttempt, $1.key)
        }), let candidate = candidates[oldest.key] {
            next = candidate
            inFlight = candidate.id
            cache[candidate.id]?.lastAttempt = at
        }
        let details = cache.compactMapValues(\.details)
        lock.unlock()

        if let next {
            schedule { [weak self] in
                guard let self else { return }
                let value = self.read(next.id).flatMap { Details($0, expected: next.id) }
                let finished = self.now()
                self.lock.lock()
                if var entry = self.cache[next.id] {
                    if let value { entry.details = value }
                    entry.nextAttempt = finished + (value == nil ? 60 : 30)
                    entry.verifiedLoaded = value.map { ["active", "idle"].contains($0.status) } ?? false
                    entry.verifiedAt = finished
                    self.cache[next.id] = entry
                }
                self.inFlight = nil
                self.lock.unlock()
            }
        }

        return cards.map { card in
            guard let id = Self.threadID(card.id) else { return card }
            var shown = details[id].map { self.apply($0, to: card) } ?? card
            shown.agents = shown.agents.map { row in
                guard let child = Self.childID(row.id, cardID: card.id),
                      let childDetails = details[child], childDetails.parentID == id else { return row }
                var info = row.info
                if let model = childDetails.model { info.model = model }
                if let role = childDetails.role { info.type = role }
                if let task = childDetails.task { info.task = task }
                return Self.row(row, info: info)
            }
            return shown
        }
    }

    /// A failed or old read can still supply a title, but cannot claim that the
    /// daemon can receive a new message. The routing layer also checks its live hook.
    func canReceiveMessages(for cardID: String) -> Bool {
        guard let id = Self.threadID(cardID) else { return false }
        let at = now()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[id] else { return false }
        return entry.verifiedLoaded && at - entry.verifiedAt <= 35
    }

    private func apply(_ details: Details, to card: SessionCard) -> SessionCard {
        var info = card.main?.info ?? AgentInfo()
        if let name = details.name { info.title = name }
        if let cwd = details.cwd {
            if info.cwd.isEmpty { info.cwd = cwd }
            if info.folder.isEmpty { info.folder = cwd }
        }
        if let model = details.model { info.model = model }
        let project = info.cwd.isEmpty ? card.project : TranscriptReader.clipped((info.cwd as NSString).lastPathComponent)
        // Applying cached metadata must remain memory-only: a project may be a cloud
        // placeholder whose filesystem calls wait indefinitely for a provider or TCC.
        let place = card.git
        let repo = !card.repo.isEmpty ? card.repo : info.cwd.isEmpty ? "" : place.map {
            TranscriptReader.clipped(($0.checkout as NSString).lastPathComponent)
        } ?? Projects.name(of: info.cwd, home: NSHomeDirectory())
        let branch = card.branch.isEmpty ? details.branch ?? "" : card.branch
        let owner = desktop.flatMap { app in
            Self.link(threadID: details.threadID).map { OwnerApp(bundle: app.bundle, name: app.name, link: $0) }
        } ?? card.owner
        return SessionCard(id: card.id, project: project, branch: branch,
                           main: card.main.map { Self.row($0, info: info) }, agents: card.agents,
                           startedAt: card.startedAt, title: details.name ?? card.title, owner: owner,
                           worktree: card.worktree,
                           look: card.look, repo: repo, git: place, jobs: card.jobs,
                           onlyForJobs: card.onlyForJobs, closed: card.closed)
    }

    private static func row(_ row: AgentRow, info: AgentInfo) -> AgentRow {
        AgentRow(id: row.id, info: info, status: row.status, elapsed: row.elapsed,
                 quietFor: row.quietFor, calledBusy: row.calledBusy)
    }

    private static func threadID(_ cardID: String) -> String? {
        guard cardID.hasPrefix("codex-") else { return nil }
        return Details.id(String(cardID.dropFirst("codex-".count)))
    }

    private static func childID(_ rowID: String, cardID: String) -> String? {
        let prefix = cardID + "-"
        guard rowID.hasPrefix(prefix) else { return nil }
        return Details.id(String(rowID.dropFirst(prefix.count)))
    }

    static func link(threadID: String) -> URL? {
        Details.id(threadID).flatMap { URL(string: "codex://threads/\($0)") }
    }

    /// This is the verified desktop bundle that owns the shared daemon and the
    /// codex URL scheme. OwnerApp also checks the registered opener on every click.
    static func desktopApp(at url: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app")) -> OwnerApp? {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.openai.codex",
              let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              types.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains("codex") == true }) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Codex"
        return OwnerApp(bundle: url, name: TranscriptReader.clipped(name))
    }
}
