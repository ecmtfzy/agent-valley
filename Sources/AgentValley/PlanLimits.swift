import Foundation

/// One usage window of an account's plan.
struct PlanLimit: Equatable {
    enum Level: Equatable {
        case normal, high, critical
    }

    let usedPercent: Double
    let resetsAt: Date?

    var level: Level {
        usedPercent >= 95 ? .critical : usedPercent >= 80 ? .high : .normal
    }

    /// Whether the time until reset is the thing to know: near the limit, the question is when
    /// work can go on. Its reset time is the last to give way when room runs out.
    var resetMatters: Bool { level != .normal }

    var percentLabel: String { "\(Int(usedPercent.rounded()))%" }

    /// How much of its track the bar fills. Over the limit still fills the track and no more.
    var fraction: Double { min(max(usedPercent / 100, 0), 1) }

    /// "45m", "2h 10m" or "3d 4h" until the window resets; nil once that time has passed.
    func resetLabel(now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let minutes = Int(resetsAt.timeIntervalSince(now) / 60)
        if minutes < 60 { return "\(max(1, minutes))m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" }
        return "\(minutes / 1440)d \(minutes % 1440 / 60)h"
    }
}

enum PlanLimitsProvider: String, Hashable {
    case claude, codex
}

struct PlanLimits: Equatable {
    var fiveHour: PlanLimit?
    var week: PlanLimit?
    var provider: PlanLimitsProvider = .claude
    /// Codex's explicit account permission. A percentage or reset time alone must
    /// not stand in for this value, including when the server omits it.
    var ordinaryUsageAllowed: Bool? = nil

    /// The window that has run out and comes back last, or nil while there is room: Claude Code
    /// waits for it. Out once its meter reads 100%. Past its reset time it is back, whatever the
    /// last numbers said.
    func runOut(now: Date) -> RunOut? {
        if provider == .codex, ordinaryUsageAllowed != false { return nil }
        let out = [(false, fiveHour), (true, week)].compactMap { weekly, limit -> RunOut? in
            guard let limit else { return nil }
            if provider == .codex {
                // Keep a confirmed block until a fresh account response says otherwise.
                // Crossing the displayed reset time is not proof that Codex can run.
                guard limit.usedPercent >= 100 else { return nil }
            } else {
                guard limit.usedPercent.rounded() >= 100,
                      limit.resetsAt.map({ $0 > now }) ?? true else { return nil }
            }
            return RunOut(weekly: weekly, resetsAt: limit.resetsAt)
        }
        return out.max { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }
}

/// A plan window that has run out: the crew has gone fishing until it resets.
struct RunOut: Equatable {
    let weekly: Bool
    let resetsAt: Date?
}

/// The account window selected for the collapsed notch ring.
struct LimitRing: Equatable {
    let limit: PlanLimit
    /// The latest refresh failed and this is the number from before it.
    let stale: Bool
    var weekly = false
}

/// Why there are no numbers. It names a cause the person can act on and nothing else: no part
/// of the login or of a reply is ever carried in it.
enum LimitsFailure: Error, Equatable {
    /// No Claude Code item in the Keychain, or it could not be read.
    case noLogin
    /// The login in it has run out. Recovery delegates renewal to official Claude Code.
    case loginExpired
    /// No answer from the usage endpoint.
    case offline
    /// It answered with this HTTP status.
    case refused(Int)
    /// It answered with something that holds no limits.
    case unreadable
    /// A fetch exceeded its source's bounded waiting time.
    case noAnswer
}

/// Reads what Claude Code keeps in the Keychain and what the usage endpoint replies. Pure:
/// it never touches the Keychain or the network itself.
enum PlanLimitsReader {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()

    /// The access token in the Keychain item, or nil when it is missing, malformed or expired.
    /// The item looks like `{"claudeAiOauth":{"accessToken":…,"expiresAt":<milliseconds>}}`.
    static func token(fromKeychainItem data: Data, now: Date) -> String? {
        try? login(fromKeychainItem: data, now: now).get()
    }

    /// The same, saying why when there is none: the person is told different things for a login
    /// that is missing and one that has expired.
    static func login(fromKeychainItem data: Data, now: Date) -> Result<String, LimitsFailure> {
        guard let object = SafeJSON.object(data),
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .failure(.noLogin) }
        if let expires = oauth["expiresAt"] as? NSNumber,
           Date(timeIntervalSince1970: expires.doubleValue / 1000) <= now { return .failure(.loginExpired) }
        return .success(token)
    }

    /// The 5-hour and weekly limits in a usage reply, or nil when it holds neither. The reply is
    /// undocumented: it has come as a `limits` list and, before that, as top-level windows.
    static func parse(_ data: Data) -> PlanLimits? {
        guard let object = SafeJSON.object(data) else { return nil }
        var limits = PlanLimits()
        for item in object["limits"] as? [[String: Any]] ?? [] {
            guard let percent = number(item["percent"]) else { continue }
            let limit = PlanLimit(usedPercent: percent, resetsAt: date(item["resets_at"]))
            switch item["kind"] as? String {
            case "session": if limits.fiveHour == nil { limits.fiveHour = limit }
            case "weekly_all": if limits.week == nil { limits.week = limit }
            default: break
            }
        }
        func legacy(_ key: String) -> PlanLimit? {
            guard let item = object[key] as? [String: Any], let used = number(item["utilization"]) else { return nil }
            return PlanLimit(usedPercent: used, resetsAt: date(item["resets_at"]))
        }
        if limits.fiveHour == nil { limits.fiveHour = legacy("five_hour") }
        if limits.week == nil { limits.week = legacy("seven_day") }
        return limits.fiveHour == nil && limits.week == nil ? nil : limits
    }

    /// A percentage the app can show. "nan", "inf" and absurd magnitudes are no data: rounding
    /// one to an Int would trap, and the status row is drawn even while the panel is closed.
    private static func number(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let text = value as? String {
            number = Double(text)
        } else {
            number = nil
        }
        guard let number, number.isFinite, (0...100_000).contains(number) else { return nil }
        return number
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
        // A fraction the formatter will not take: read the time without it.
        return plain.date(from: text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }
}

/// Refuses every redirect, so a request carrying the token can never follow one to another host.
/// The 3xx reply then ends the task and reads as a failed fetch.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Where the limits come from. `fetch` answers on the main thread, once, unless it is cancelled
/// first; it returns the way to cancel.
protocol PlanLimitsSource {
    /// The maximum time needed for a complete read, including any bounded recovery.
    var fetchTimeout: TimeInterval { get }
    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void
}

extension PlanLimitsSource {
    var fetchTimeout: TimeInterval { 60 }
}

/// The real source: the Claude Code login in the Keychain, then Anthropic's usage endpoint.
/// Reads the login and sends only the usage GET; renewal belongs to ClaudeUsageSource.
final class KeychainLimitsSource: PlanLimitsSource {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    /// `security` is stopped if it has not answered by then, for instance while it waits on a prompt.
    static let securityTimeout: TimeInterval = 10

    private let session = KeychainLimitsSource.makeSession()

    /// Ephemeral: nothing about these requests is cached or stored on disk. Redirects are refused.
    static func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentValley", forHTTPHeaderField: "User-Agent")
        return request
    }

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        let flight = Flight()
        let answer: (Result<PlanLimits, LimitsFailure>) -> Void = { result in
            DispatchQueue.main.async {
                if !flight.isCancelled { done(result) }
            }
        }
        DispatchQueue.global(qos: .utility).async { [session] in
            // The token exists only inside this closure: read, used for one request, gone.
            // This source only reads. ClaudeUsageSource delegates renewal to the
            // official CLI so its credential rotation and locking stay coordinated.
            let token: String
            switch Self.readToken(for: flight) {
            case .success(let read): token = read
            case .failure(let reason): return answer(.failure(reason))
            }
            let task = session.dataTask(with: Self.request(token: token)) { data, response, error in
                answer(Self.outcome(data: data, response: response, failed: error != nil))
            }
            if flight.begin({ task.cancel() }) { task.resume() }
        }
        return flight.cancel
    }

    /// Sorts a reply into numbers or the reason there are none. The reason is a category and at
    /// most a status code; nothing of the reply's content is kept.
    static func outcome(data: Data?, response: URLResponse?, failed: Bool) -> Result<PlanLimits, LimitsFailure> {
        guard !failed, let status = (response as? HTTPURLResponse)?.statusCode else { return .failure(.offline) }
        // The wrapper can ask official Claude Code to renew a refused login.
        if status == 401 { return .failure(.loginExpired) }
        guard status == 200 else { return .failure(.refused(status)) }
        return data.flatMap(PlanLimitsReader.parse).map(Result.success) ?? .failure(.unreadable)
    }

    /// Asks the Keychain through `security`, which Claude Code's own item already trusts.
    /// Cancelling the flight stops `security` at once: with Plan limits off it must not keep running.
    private static func readToken(for flight: Flight) -> Result<String, LimitsFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard flight.begin({ if process.isRunning { process.terminate() } }) else { return .failure(.noLogin) }
        do { try process.run() } catch { return .failure(.noLogin) }
        // Cancelled between the two lines above: the stop ran before there was anything to stop.
        if flight.isCancelled, process.isRunning { process.terminate() }
        let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + securityTimeout, execute: stop)
        let item = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()
        guard process.terminationStatus == 0 else { return .failure(.noLogin) }
        return PlanLimitsReader.login(fromKeychainItem: item, now: Date())
    }

    /// One fetch, shared between the thread that runs it and the one that may cancel it.
    final class Flight {
        private let lock = NSLock()
        private var cancelled = false
        /// Stops the step now under way: the Keychain read, then the request.
        private var stop: (() -> Void)?

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        /// Takes the way to stop the next step; false if the fetch was cancelled before it began.
        func begin(_ stop: @escaping () -> Void) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { return false }
            self.stop = stop
            return true
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let stop = self.stop
            self.stop = nil
            lock.unlock()
            stop?()
        }
    }
}

/// Decides when to fetch and what to show. Touches neither the Keychain nor the network itself,
/// and asks its source for nothing while disabled. All state lives on the main thread.
final class PlanLimitsClient: ObservableObject {
    static let refreshEvery: TimeInterval = 300
    /// Opening the panel refreshes only if the last attempt is older than this.
    static let staleAfter: TimeInterval = 60
    /// A failed fetch keeps showing the last numbers for this long.
    static let keepLastFor: TimeInterval = 900
    /// Minimum waiting budget; a source may declare a longer bounded recovery.
    static let giveUpAfter: TimeInterval = 60
    static let retryDelays: [TimeInterval] = [10, 30, 60]
    /// Wake and unlock can arrive separately for the same return to the Mac.
    static let resumeRefreshInterval: TimeInterval = 10

    /// Unknown usage has its own track; it must never become a zero-percent value.
    enum RingState: Equatable {
        case loading
        case unavailable(LimitsFailure)
        case value(LimitRing)
    }

    /// What the status row shows where the limits go.
    enum Display: Equatable {
        case off
        /// On, and the first answer has not come back yet.
        case loading
        /// On, but there are no numbers to show, and why.
        case unavailable(LimitsFailure)
        /// `asOf`: set when the latest refresh failed, to the time these older numbers are from.
        case limits(PlanLimits, asOf: Date?)

        /// Claude shows its weekly window. Codex prefers 5 hours, then its weekly window.
        /// A missing selected window stays unknown instead of changing what the ring means.
        var ring: LimitRing? {
            guard case .limits(let limits, let asOf) = self else { return nil }
            if limits.provider == .claude {
                return limits.week.map { LimitRing(limit: $0, stale: asOf != nil, weekly: true) }
            }
            if let limit = limits.fiveHour { return LimitRing(limit: limit, stale: asOf != nil) }
            if let limit = limits.week { return LimitRing(limit: limit, stale: asOf != nil, weekly: true) }
            return nil
        }

        var ringState: RingState? {
            switch self {
            case .off: return nil
            case .loading: return .loading
            case .unavailable(let reason): return .unavailable(reason)
            case .limits: return ring.map(RingState.value) ?? .unavailable(.unreadable)
            }
        }

        /// Whether the panel has numbers to go by.
        var hasNumbers: Bool {
            if case .limits = self { return true }
            return false
        }

        /// A valid percentage does not establish Codex's permission to work.
        /// Unknown permission, or a block outside the represented quota windows,
        /// must reset the sound baseline instead of announcing a recovery.
        func knowsAvailability(now: Date) -> Bool {
            guard case .limits(let limits, _) = self else { return false }
            return limits.provider == .claude || limits.ordinaryUsageAllowed == true
                || limits.runOut(now: now) != nil
        }

        func runOut(now: Date) -> RunOut? {
            guard case .limits(let limits, _) = self else { return nil }
            return limits.runOut(now: now)
        }
    }

    @Published private(set) var limits: PlanLimits?
    @Published private(set) var enabled = false
    /// Why the latest fetch brought no numbers, or nil when it did or none has finished yet.
    @Published private(set) var failure: LimitsFailure?

    var display: Display {
        guard enabled else { return .off }
        if let limits { return .limits(limits, asOf: failure == nil ? nil : fetchedAt) }
        return failure.map(Display.unavailable) ?? .loading
    }

    private let source: PlanLimitsSource
    private var flightTimeout: TimeInterval { max(Self.giveUpAfter, source.fetchTimeout) }
    private let now: () -> Date
    private var inFlight = false
    private var cancelFlight: (() -> Void)?
    /// Names the fetch in progress. An answer carrying an older number is dropped.
    private var flight = 0
    private var attemptedAt: Date?
    private var fetchedAt: Date?
    private var timer: Timer?
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> () -> Void
    private let schedule: Schedule
    private var cancelRetry: (() -> Void)?
    private var retryIndex = 0
    private var retryGeneration = 0
    private var resumedAt: Date?
    private var cancelResumeCheck: (() -> Void)?
    private var resumeGeneration = 0
    private var checkAfterFlight = false

    init(source: PlanLimitsSource = ClaudeUsageSource(), now: @escaping () -> Date = Date.init,
         schedule: @escaping Schedule = PlanLimitsClient.scheduleOnMain) {
        self.source = source
        self.now = now
        self.schedule = schedule
    }

    deinit {
        timer?.invalidate()
        cancelRetry?()
        cancelResumeCheck?()
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        timer?.invalidate()
        timer = nil
        guard on else {
            resetRetries()
            resetResumeCheck()
            abandonFlight()
            limits = nil
            failure = nil
            fetchedAt = nil
            attemptedAt = nil
            resumedAt = nil
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshEvery, repeats: true) { [weak self] _ in
            self?.tick()
        }
        refresh()
    }

    /// Called when the panel opens: current numbers without polling harder than needed.
    func refreshIfStale() {
        if let attemptedAt, now().timeIntervalSince(attemptedAt) < Self.staleAfter { return }
        refresh()
    }

    /// A returned Mac gets one prompt check, even if the last attempt was recent.
    /// The app also coalesces notifications; this guard covers later duplicate events.
    func refreshAfterResume() {
        guard enabled else { return }
        let time = now()
        if inFlight, let attemptedAt, time.timeIntervalSince(attemptedAt) < flightTimeout {
            // An official account reader may still be recovering a login when unlock
            // arrives. Keep the request until its answer; success makes another read needless.
            checkAfterFlight = true
            return
        }
        if let resumedAt, time.timeIntervalSince(resumedAt) < Self.resumeRefreshInterval {
            // Wake may precede unlock. If that read failed (or is still running), keep
            // one check after the rate limit, so a locked Keychain need not cost five minutes.
            if failure != nil || inFlight, cancelResumeCheck == nil {
                let mine = resumeGeneration
                cancelResumeCheck = schedule(Self.resumeRefreshInterval - time.timeIntervalSince(resumedAt)) { [weak self] in
                    guard let self, self.enabled, self.resumeGeneration == mine else { return }
                    self.cancelResumeCheck = nil
                    if self.inFlight || self.failure != nil { self.refreshAfterResume() }
                }
            }
            return
        }
        resetResumeCheck()
        resumedAt = time
        show(Self.resolve(result: nil, last: limits, lastFetchedAt: fetchedAt, now: time))
        refresh()
    }

    /// The periodic pass: take down numbers that have gone stale, then fetch again.
    func tick() {
        guard enabled else { return }
        show(Self.resolve(result: nil, last: limits, lastFetchedAt: fetchedAt, now: now()))
        refresh()
    }

    /// What to show after a fetch: the new numbers, or the last ones while they are still recent.
    static func resolve(result: PlanLimits?, last: PlanLimits?, lastFetchedAt: Date?, now: Date) -> PlanLimits? {
        if let result { return result }
        guard let lastFetchedAt, now.timeIntervalSince(lastFetchedAt) <= keepLastFor else { return nil }
        return last
    }

    private func refresh(resetRetrySequence: Bool = true) {
        guard enabled else { return }
        if inFlight, let attemptedAt, now().timeIntervalSince(attemptedAt) >= flightTimeout {
            abandonFlight()
            failure = .noAnswer
        }
        guard !inFlight else { return }
        if resetRetrySequence { resetRetries() }
        checkAfterFlight = false
        inFlight = true
        attemptedAt = now()
        flight += 1
        let mine = flight
        let cancel = source.fetch { [weak self] result in self?.finish(result, flight: mine) }
        // A source may answer before `fetch` returns; only a fetch still under way keeps its cancel.
        if inFlight, flight == mine { cancelFlight = cancel }
    }

    private func finish(_ outcome: Result<PlanLimits, LimitsFailure>, flight answered: Int) {
        guard enabled, inFlight, answered == flight else { return }
        inFlight = false
        cancelFlight = nil
        let time = now()
        let result = try? outcome.get()
        show(Self.resolve(result: result, last: limits, lastFetchedAt: fetchedAt, now: time))
        if result != nil { fetchedAt = time }
        var reason: LimitsFailure?
        if case .failure(let why) = outcome { reason = why }
        if failure != reason { failure = reason }
        if let reason {
            if checkAfterFlight {
                checkAfterFlight = false
                refreshAfterResume()
            } else {
                retry(after: reason)
            }
        } else {
            resetRetries()
            resetResumeCheck()
        }
    }

    /// Only transport/server failures get a short retry sequence. A missing or expired
    /// login, a rejected request, or an unknown schema waits for the regular check.
    private func retry(after failure: LimitsFailure) {
        let transient: Bool
        switch failure {
        case .offline, .noAnswer: transient = true
        case .refused(let status): transient = (500...599).contains(status)
        default: transient = false
        }
        guard transient, retryIndex < Self.retryDelays.count else { return }
        let delay = Self.retryDelays[retryIndex]
        retryIndex += 1
        retryGeneration += 1
        let mine = retryGeneration
        cancelRetry = schedule(delay) { [weak self] in
            guard let self, self.enabled, self.retryGeneration == mine else { return }
            self.cancelRetry = nil
            self.refresh(resetRetrySequence: false)
        }
    }

    private func resetRetries() {
        cancelRetry?()
        cancelRetry = nil
        retryIndex = 0
        retryGeneration += 1
    }

    private func resetResumeCheck() {
        cancelResumeCheck?()
        cancelResumeCheck = nil
        resumeGeneration += 1
        checkAfterFlight = false
    }

    static func scheduleOnMain(after delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }

    /// Stops the fetch under way and disowns it, so an answer already on its way changes nothing.
    private func abandonFlight() {
        cancelFlight?()
        cancelFlight = nil
        inFlight = false
        flight += 1
    }

    private func show(_ next: PlanLimits?) {
        if limits != next { limits = next }
    }
}
