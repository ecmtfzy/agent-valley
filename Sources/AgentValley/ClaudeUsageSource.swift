import Darwin
import Foundation

/// Keep the normal Keychain/GET path fast. Only an expired login asks the
/// installed Claude CLI to read usage and renew its own credentials if necessary.
/// The app never reads a refresh token or implements token rotation itself.
final class ClaudeUsageSource: PlanLimitsSource {
    static let rejectedLoginCooldown: TimeInterval = 5 * 60
    /// Covers the first account read, bounded CLI recovery, and one final account read.
    var fetchTimeout: TimeInterval { 110 }

    private let primary: PlanLimitsSource
    private let recovery: PlanLimitsSource
    private let now: () -> Date
    private let lock = NSLock()
    private var retryAfter: Date?

    init(primary: PlanLimitsSource = KeychainLimitsSource(),
         recovery: PlanLimitsSource = ClaudeCLIUsageSource(), now: @escaping () -> Date = Date.init) {
        self.primary = primary
        self.recovery = recovery
        self.now = now
    }

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        let flight = Flight()
        func answer(_ result: Result<PlanLimits, LimitsFailure>) {
            DispatchQueue.main.async { if flight.finish() { done(result) } }
        }
        func start(_ source: PlanLimitsSource, _ receive: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) {
            guard let generation = flight.begin() else { return }
            let cancel = source.fetch { result in
                guard flight.isCurrent(generation) else { return }
                receive(result)
            }
            flight.install(cancel, generation: generation)
        }
        start(primary) { [self] result in
            guard case .failure(.loginExpired) = result else { answer(result); return }
            lock.lock()
            let mayRecover = retryAfter.map { $0 <= now() } ?? true
            lock.unlock()
            guard mayRecover else { answer(result); return }
            func recoveredAnswer(_ recovered: Result<PlanLimits, LimitsFailure>) {
                lock.lock()
                switch recovered {
                case .failure(.loginExpired), .failure(.noLogin), .failure(.refused(401)), .failure(.refused(403)):
                    retryAfter = now().addingTimeInterval(Self.rejectedLoginCooldown)
                case .success: retryAfter = nil
                default: break // A temporary network/timeout failure keeps the client's short retry schedule.
                }
                lock.unlock()
                answer(recovered)
            }
            start(recovery) { [self] recovered in
                guard case .failure = recovered else { recoveredAnswer(recovered); return }
                // The CLI's experimental usage API may omit windows even after
                // it renewed the login. Its invalid_grant handling can also clear
                // an expired login. Re-read through the existing primary once to
                // distinguish those cases, without touching refresh tokens here.
                start(primary) { refreshed in
                    switch refreshed {
                    case .success, .failure(.noLogin): recoveredAnswer(refreshed)
                    default: recoveredAnswer(recovered)
                    }
                }
            }
        }
        return flight.cancel
    }

    /// Generation guards cover even synchronous test sources: an old source's
    /// returned cancellation must not overwrite a recovery that already began.
    private final class Flight {
        private let lock = NSLock()
        private var ended = false
        private var generation = 0
        private var stop: (() -> Void)?

        func begin() -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard !ended else { return nil }
            generation += 1
            stop = nil
            return generation
        }

        func isCurrent(_ value: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return !ended && generation == value
        }

        func install(_ cancel: @escaping () -> Void, generation value: Int) {
            lock.lock()
            let current = !ended && generation == value
            if current { stop = cancel }
            lock.unlock()
            if !current { cancel() }
        }

        func finish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !ended else { return false }
            ended = true
            stop = nil
            return true
        }

        func cancel() {
            lock.lock()
            ended = true
            let cancel = stop
            stop = nil
            lock.unlock()
            cancel?()
        }
    }
}

/// The bounded, cancellable transport for the installed CLI's experimental
/// get_usage control request. Its helper emits only the existing two UI windows.
final class ClaudeCLIUsageSource: PlanLimitsSource {
    static let timeout: TimeInterval = 50
    static let maximumOutputBytes = 32_768

    struct Command {
        let executable: URL
        let arguments: [String]
    }

    private let command: () -> Command?
    private let timeout: TimeInterval
    private let terminationGrace: TimeInterval
    private let queue: DispatchQueue

    convenience init() { self.init(command: Self.helperCommand) }

    /// The command/queue seam permits real subprocess cleanup tests without
    /// reading account state or running the actual Claude CLI.
    init(command: @escaping () -> Command?, timeout: TimeInterval = ClaudeCLIUsageSource.timeout,
         terminationGrace: TimeInterval = 4,
         queue: DispatchQueue = .global(qos: .utility)) {
        self.command = command
        self.timeout = max(0.01, timeout.isFinite ? timeout : Self.timeout)
        self.terminationGrace = max(0.01, terminationGrace.isFinite ? terminationGrace : 4)
        self.queue = queue
    }

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        let flight = Flight()
        queue.async { [command, timeout, terminationGrace] in
            guard !flight.isCancelled else { return }
            let result: Result<PlanLimits, LimitsFailure>
            if let command = command(), !flight.isCancelled {
                result = Self.run(command, flight: flight, timeout: timeout, grace: terminationGrace)
            } else {
                result = .failure(.offline)
            }
            DispatchQueue.main.async {
                if flight.takeAnswer() { done(result) }
            }
        }
        // Cancellation only changes small locked state and wakes the worker;
        // subprocess termination and waiting never block the main thread.
        return flight.cancel
    }

    private static func run(_ command: Command, flight: Flight,
                            timeout: TimeInterval, grace: TimeInterval) -> Result<PlanLimits, LimitsFailure> {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal(); flight.wake.signal() }
        defer {
            process.terminationHandler = nil
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        let descriptor = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return .failure(.offline)
        }
        guard !flight.isCancelled else { return .failure(.offline) }
        do { try process.run() } catch { return .failure(.offline) }
        try? output.fileHandleForWriting.close()
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var badOutput = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

        func drain() {
            // Nonblocking reads cannot hang on an inherited pipe after the
            // helper exits, and a noisy/malformed helper cannot exhaust memory.
            while bytes.count <= maximumOutputBytes {
                let count = Darwin.read(descriptor, &buffer, min(buffer.count, maximumOutputBytes + 1 - bytes.count))
                if count > 0 { bytes.append(contentsOf: buffer.prefix(count)) }
                else if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK { break }
                else if errno != EINTR { badOutput = true; break }
            }
            if bytes.count > maximumOutputBytes { badOutput = true }
        }

        while process.isRunning && !flight.isCancelled && !badOutput
                && ProcessInfo.processInfo.systemUptime < deadline {
            drain()
            if process.isRunning && !badOutput {
                _ = flight.wake.wait(timeout: .now() + 0.025)
            }
        }
        let timedOut = process.isRunning && !flight.isCancelled && !badOutput
            && ProcessInfo.processInfo.systemUptime >= deadline
        if process.isRunning {
            // The helper unwinds its own CLI on TERM. Escalation targets only
            // this owned helper PID, never the other Claude processes or a process group.
            process.terminate()
            if finished.wait(timeout: .now() + grace) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.1)
            }
        }
        if timedOut { return .failure(.noAnswer) }
        guard !flight.isCancelled else { return .failure(.offline) }
        drain()
        guard !badOutput else { return .failure(.unreadable) }
        guard !process.isRunning, process.terminationReason == .exit else { return .failure(.offline) }
        if let error = SafeJSON.object(bytes)?["error"] as? String {
            switch error {
            case "loginExpired": return .failure(.loginExpired)
            case "noLogin": return .failure(.noLogin)
            case "refused": return .failure(.refused(403))
            case "noAnswer": return .failure(.noAnswer)
            case "unreadable": return .failure(.unreadable)
            default: return .failure(.offline)
            }
        }
        guard process.terminationStatus == 0 else { return .failure(.offline) }
        return PlanLimitsReader.parse(bytes).map(Result.success) ?? .failure(.unreadable)
    }

    private static func helperCommand() -> Command? {
        guard let resources = Bundle.main.resourceURL,
              let claude = claudeExecutable() else { return nil }
        let script = resources.appendingPathComponent("claude/usage_probe.py")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }
        return Command(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                       arguments: [script.path, "--claude", claude, "--timeout", "45"])
    }

    /// Prefer the native CLI already installed by Claude Desktop. Older CLIs
    /// without the guarded usage control API fail closed instead of running a prompt.
    private static func claudeExecutable() -> String? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = ((try? manager.contentsOfDirectory(atPath: base.path)) ?? [])
            .filter { $0.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }.prefix(32)
        var candidates: [String] = []
        for version in versions {
            let directory = base.appendingPathComponent(version)
            for build in ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).prefix(32) {
                guard build.range(of: #"^[a-zA-Z0-9_-]{1,64}$"#, options: .regularExpression) != nil else { continue }
                candidates.append(directory.appendingPathComponent(build)
                    .appendingPathComponent("claude.app/Contents/MacOS/claude").path)
            }
        }
        candidates.append(home.appendingPathComponent(".local/bin/claude").path)
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").filter { $0.hasPrefix("/") }.prefix(64)
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("claude").path }
        return candidates.first { path in
            var directory: ObjCBool = false
            return manager.fileExists(atPath: path, isDirectory: &directory)
                && !directory.boolValue && manager.isExecutableFile(atPath: path)
        }
    }

    private final class Flight {
        let wake = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var cancelled = false
        private var answered = false

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
            wake.signal()
        }

        func takeAnswer() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled && !answered else { return false }
            answered = true
            return true
        }
    }
}
