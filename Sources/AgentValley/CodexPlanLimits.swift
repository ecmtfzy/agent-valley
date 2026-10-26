import CoreFoundation
import Darwin
import Foundation

/// Reads the account/rateLimits/read projection returned by the local Codex helper.
/// It knows neither account credentials nor the user's transcript contents.
enum CodexPlanLimitsReader {
    struct Snapshot: Equatable {
        let limits: PlanLimits
        let planType: String?
        let limitID: String?
        let rateLimitReachedType: String?
        let spendControlReached: Bool?
        let ordinaryUsageAllowed: Bool?
    }

    static func parse(_ data: Data) -> PlanLimits? { read(data)?.limits }

    static func read(_ data: Data) -> Snapshot? {
        guard data.count <= CodexLimitsSource.maximumOutputBytes,
              let object = SafeJSON.object(data) else { return nil }
        let bucket: [String: Any]
        if let supplied = object["rateLimitsByLimitId"], !(supplied is NSNull) {
            // The map is authoritative when present. An empty map or a different
            // product must not accidentally fall back to a legacy aggregate.
            guard let map = supplied as? [String: Any],
                  let codex = map["codex"] as? [String: Any] else { return nil }
            bucket = codex
        } else {
            guard let legacy = object["rateLimits"] as? [String: Any] else { return nil }
            bucket = legacy
        }
        if let identity = bucket["limitId"], !(identity is NSNull), identity as? String != "codex" {
            return nil
        }

        let ordinary = boolean(object["ordinaryUsageAllowed"])
        var limits = PlanLimits()
        limits.provider = .codex
        limits.ordinaryUsageAllowed = ordinary
        for key in ["primary", "secondary"] {
            guard let window = bucket[key] as? [String: Any],
                  let used = number(window["usedPercent"], range: 0...100_000),
                  let minutes = integer(window["windowDurationMins"], range: 1...1_000_000) else { continue }
            let reset = integer(window["resetsAt"], range: 0...253_402_300_799)
                .map { Date(timeIntervalSince1970: $0) }
            let limit = PlanLimit(usedPercent: used, resetsAt: reset)
            switch minutes {
            case 300: if limits.fiveHour == nil { limits.fiveHour = limit }
            case 10_080: if limits.week == nil { limits.week = limit }
            default: break
            }
        }
        guard limits.fiveHour != nil || limits.week != nil else { return nil }
        return Snapshot(limits: limits, planType: text(bucket["planType"]),
                        limitID: text(bucket["limitId"]),
                        rateLimitReachedType: text(bucket["rateLimitReachedType"]),
                        spendControlReached: boolean(bucket["spendControlReached"]),
                        ordinaryUsageAllowed: ordinary)
    }

    /// JSON booleans are NSNumber subclasses, but are not numeric measurements.
    private static func number(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        return number.isFinite && range.contains(number) ? number : nil
    }

    private static func integer(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        guard let value = number(value, range: range), value.rounded(.towardZero) == value else { return nil }
        return value
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 256 else { return nil }
        return value
    }
}

/// A cancellable, bounded account read. The helper prefers the existing daemon;
/// without its control socket it uses an owned, temporary stdio account reader.
/// Nothing runs until PlanLimitsClient enables and fetches this source.
final class CodexLimitsSource: PlanLimitsSource {
    static let timeout: TimeInterval = 10
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
    /// reading account state or running the actual Codex proxy.
    init(command: @escaping () -> Command?, timeout: TimeInterval = CodexLimitsSource.timeout,
         terminationGrace: TimeInterval = 0.5,
         queue: DispatchQueue = .global(qos: .utility)) {
        self.command = command
        self.timeout = max(0.01, timeout.isFinite ? timeout : Self.timeout)
        self.terminationGrace = max(0.01, terminationGrace.isFinite ? terminationGrace : 0.5)
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
            // The helper unwinds its own proxy on TERM. Escalation targets only
            // this owned helper PID, never the shared daemon or a process group.
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
        guard !process.isRunning, process.terminationReason == .exit, process.terminationStatus == 0 else {
            return .failure(.offline)
        }
        return CodexPlanLimitsReader.parse(bytes).map(Result.success) ?? .failure(.unreadable)
    }

    private static func helperCommand() -> Command? {
        guard let resources = Bundle.main.resourceURL,
              let codex = codexExecutable() else { return nil }
        let script = resources.appendingPathComponent("codex/runtime_probe.py")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }
        return Command(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                       arguments: [script.path, "--limits", "--codex", codex, "--timeout", "8"])
    }

    private static func codexExecutable() -> String? {
        let manager = FileManager.default
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
        let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        return (paths + [bundled]).first { path in
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
