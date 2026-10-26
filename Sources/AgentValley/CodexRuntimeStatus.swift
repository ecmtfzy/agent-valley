import Darwin
import Foundation

/// Native hooks report a permission request and its eventual tool result, but not the
/// moment the person answers. Read-only live status fills that interval without answering
/// a request, resuming a thread, or replacing the hook journal as the source of sessions.
/// Confined to the store's polling queue; no asynchronous result can outlive its token.
final class CodexRuntimeStatus {
    struct RuntimeState: Equatable {
        let status: String
        let flags: [String]
    }

    private struct Evidence {
        let token: String
        var sawApproval = false
        var resolved = false
        var waitsForPerson = false
        var lastAttempt: TimeInterval?
        var nextAttempt: TimeInterval = -.infinity
    }

    private let reader: (String) -> RuntimeState?
    private let now: () -> TimeInterval
    private var evidence: [String: Evidence] = [:]

    convenience init() { self.init(reader: Self.readRuntime) }

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         reader: @escaping (String) -> RuntimeState?) {
        self.now = now
        self.reader = reader
    }

    func adjust(cards: [SessionCard], tokens: [String: String]) -> [SessionCard] {
        let eligible = cards.filter { card in
            card.id.hasPrefix("codex-") && !card.closed
                && card.main != nil && card.main?.status != .done
                && !(tokens[card.id] ?? "").isEmpty
        }
        let present = Set(eligible.map(\.id))
        evidence = evidence.filter { present.contains($0.key) }
        for card in eligible {
            guard let token = tokens[card.id], evidence[card.id]?.token != token else { continue }
            // A new request keeps only the previous sample's timing, never its evidence
            // or failure backoff. Frequent publishes cannot exceed one sample per second.
            let previous = evidence[card.id]?.lastAttempt
            evidence[card.id] = Evidence(token: token, lastAttempt: previous,
                                         nextAttempt: previous.map { $0 + 1 } ?? -.infinity)
        }

        let at = now()
        let ready = evidence.filter { $0.value.nextAttempt <= at }
        let oldest = ready.min {
            ($0.value.lastAttempt ?? -.infinity, $0.key)
                < ($1.value.lastAttempt ?? -.infinity, $1.key)
        }
        // At most one helper per publish, including publishes caused by file events.
        // Oldest-first selection gives every eligible card a turn without a burst of
        // serial subprocess timeouts delaying all other session updates.
        if let (id, previous) = oldest {
            var observation = previous
            observation.lastAttempt = at
            let runtime = reader(String(id.dropFirst("codex-".count)))
            observation.nextAttempt = now() + (runtime == nil ? 10 : 1)
            if let runtime, runtime.status == "active" {
                if runtime.flags.contains("waitingOnApproval") {
                    observation.sawApproval = true
                    observation.resolved = false
                    observation.waitsForPerson = true
                } else if runtime.flags.contains("waitingOnUserInput") {
                    observation.resolved = false
                    observation.waitsForPerson = true
                } else if runtime.flags.isEmpty {
                    // The hook can run before the approval UI appears. An empty first
                    // reading is insufficient evidence that it was answered.
                    observation.resolved = observation.sawApproval
                    observation.waitsForPerson = false
                }
            }
            evidence[id] = observation
        }

        return cards.map { card in
            guard let observation = evidence[card.id], let main = card.main,
                  observation.waitsForPerson || observation.resolved else { return card }

            var shown = card
            var info = main.info
            if !observation.waitsForPerson {
                info.asking = false
            }
            shown.main = AgentRow(id: main.id, info: info,
                                  status: observation.waitsForPerson ? .needsYou : .working,
                                  elapsed: main.elapsed,
                                  quietFor: observation.waitsForPerson ? main.quietFor : 0,
                                  calledBusy: false)
            return shown
        }
    }

    /// A proxy attaches to the already-running daemon. It never starts a second daemon.
    /// The Python helper sends only initialize, initialized, and thread/read.
    private static func readRuntime(_ threadID: String) -> RuntimeState? {
        guard let object = readObject(threadID),
              let status = object["status"] as? String,
              let flags = object["active_flags"] as? [String] else { return nil }
        return RuntimeState(status: status, flags: flags)
    }

    /// Shared bounded transport for live status and the background metadata cache.
    /// Call on a worker queue; no app or session is opened by this read-only request.
    static func readObject(_ threadID: String, details: Bool = false) -> [String: Any]? {
        guard let resources = Bundle.main.resourceURL,
              let codex = codexExecutable() else { return nil }
        let script = resources.appendingPathComponent("codex/runtime_probe.py")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }

        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, threadID, "--codex", codex, "--timeout", "1"]
            + (details ? ["--details"] : [])
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        defer {
            process.terminationHandler = nil
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        do { try process.run() } catch { return nil }
        try? output.fileHandleForWriting.close()

        guard finished.wait(timeout: .now() + 2) == .success else {
            // The helper handles SIGTERM by unwinding and closing its own proxy. Its
            // TERM/KILL cleanup is bounded to 0.2 seconds; allow 0.5 before escalation.
            // Never signal a process group or the shared Codex daemon.
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.1)
            }
            return nil
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let data = try? output.fileHandleForReading.read(upToCount: 32769),
              data.count <= 32768,
              let object = SafeJSON.object(data),
              object["thread_id"] as? String == threadID else { return nil }
        return object
    }

    private static func codexExecutable() -> String? {
        let manager = FileManager.default
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
        let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        return (paths + [bundled]).first { path in
            var directory: ObjCBool = false
            return manager.fileExists(atPath: path, isDirectory: &directory)
                && !directory.boolValue && manager.isExecutableFile(atPath: path)
        }
    }
}
