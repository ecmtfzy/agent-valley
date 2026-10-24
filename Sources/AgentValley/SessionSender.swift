import Foundation

struct PhoneMessage: Equatable {
    let id: UUID
    let session: String
    let text: String
}

enum NotSentReason: Equatable {
    case empty, tooLong, sessionGone, claudeNotRunning, tabNotFound, ambiguousTab, notAllowed, timedOut
    case superset(String)
    case failed(String)
    case stoppedBeforeEnter, leftBeforeEnter, backAtDesk

    var message: String {
        switch self {
        case .empty: return "Nothing to send."
        case .tooLong: return "That's over 8,000 characters. Send it in parts."
        case .sessionGone: return "That session has ended."
        case .claudeNotRunning: return "Claude isn't running in that tab anymore."
        case .tabNotFound: return "That terminal tab is gone."
        case .ambiguousTab: return "Two Ghostty tabs share that folder, so I didn't guess."
        case .notAllowed: return "macOS hasn't let AgentValley type into that terminal. Allow it in System Settings › Privacy & Security › Automation."
        case .timedOut: return "The terminal didn't answer in time."
        case .superset(let x): return "Superset said: \(x)"
        case .failed(let x): return "Couldn't send it: \(x)"
        case .stoppedBeforeEnter: return "Typed, not sent: Claude asked you something first. It's waiting in the box."
        case .leftBeforeEnter: return "Not sent: Claude left that tab before Enter. Start it there again and resend."
        case .backAtDesk: return "Not sent: you're back at the desk."
        }
    }

    /// The case name alone, for the log.
    var caseName: String {
        switch self {
        case .empty: return "empty"
        case .tooLong: return "tooLong"
        case .sessionGone: return "sessionGone"
        case .claudeNotRunning: return "claudeNotRunning"
        case .tabNotFound: return "tabNotFound"
        case .ambiguousTab: return "ambiguousTab"
        case .notAllowed: return "notAllowed"
        case .timedOut: return "timedOut"
        case .superset: return "superset"
        case .failed: return "failed"
        case .stoppedBeforeEnter: return "stoppedBeforeEnter"
        case .leftBeforeEnter: return "leftBeforeEnter"
        case .backAtDesk: return "backAtDesk"
        }
    }
}

enum SendStatus: Equatable {
    case received, sent, waitingForTurnEnd, heldForAnswer
    case notSent(NotSentReason)
}

/// The one place a phone message goes to a session, and says how it went.
/// Main thread only; typing runs on `worker` and comes back to main before any status is told.
/// The app logs from `onStatus` with `reach(session)?.route.kind` (SendLog), so the sender itself keeps no log.
final class SessionSender {
    private let limit: Int

    private let reach: (String) -> SessionReach?
    private let asking: (String) -> Bool
    /// Whether Claude still holds that tab; with no tab (Superset), whether it is in front of its terminal.
    private let holdsTab: (SessionProcess, TabPlace?) -> Bool
    private let type: (String, TabPlace, @escaping () -> Bool) -> TypingResult
    private let superset: (String, String, String, @escaping () -> Bool) -> TypingResult
    private let desk: StopDesk
    private let away: (AwayMode.Trigger) -> Void
    private let worker: DispatchQueue
    private let onStatus: (UUID, String, SendStatus) -> Void

    private var statuses: [UUID: SendStatus] = [:]
    private var sessionOf: [UUID: String] = [:]   // the desk tells ids only
    private var order: [UUID] = []
    private var queues: [String: [PhoneMessage]] = [:]
    private var inFlight: Set<String> = []

    init(reach: @escaping (String) -> SessionReach?,
         asking: @escaping (String) -> Bool,
         holdsTab: @escaping (SessionProcess, TabPlace?) -> Bool,
         type: @escaping (String, TabPlace, @escaping () -> Bool) -> TypingResult,
         superset: @escaping (String, String, String, @escaping () -> Bool) -> TypingResult,
         desk: StopDesk,
         away: @escaping (AwayMode.Trigger) -> Void,
         worker: DispatchQueue,
         onStatus: @escaping (UUID, String, SendStatus) -> Void,
         remembering limit: Int = 1000) {
        self.limit = limit
        self.reach = reach
        self.asking = asking
        self.holdsTab = holdsTab
        self.type = type
        self.superset = superset
        self.desk = desk
        self.away = away
        self.worker = worker
        self.onStatus = onStatus
        desk.onSent = { [weak self] ids in ids.forEach { self?.set($0, .sent) } }
        desk.onBackAtDesk = { [weak self] ids in ids.forEach { self?.set($0, .notSent(.backAtDesk)) } }
    }

    func send(_ message: PhoneMessage) {
        if let known = statuses[message.id] {
            onStatus(message.id, message.session, known)
            return
        }
        remember(message.id, session: message.session)
        set(message.id, .received)
        guard let text = PhoneText.clean(message.text) else { return set(message.id, .notSent(.empty)) }
        guard text.count <= PhoneText.maxCharacters else { return set(message.id, .notSent(.tooLong)) }
        let clean = PhoneMessage(id: message.id, session: message.session, text: text)
        guard let reach = reach(message.session) else { return set(message.id, .notSent(.sessionGone)) }
        if reach.route == .stopHook {
            handToDesk(clean)
        } else {
            queues[message.session, default: []].append(clean)
            pump(message.session)
        }
    }

    /// Call when a session starts or stops asking.
    func askingChanged() {
        for session in Array(queues.keys) { pump(session) }
    }

    // MARK: - Stop hook

    private func handToDesk(_ message: PhoneMessage) {
        away(.phoneMessage)
        // `.sent` arrives through desk.onSent, maybe before deliver returns; only the wait is told here.
        if desk.deliver(id: message.id, session: message.session, text: message.text) == .waitingForTurnEnd,
           statuses[message.id] == .received || statuses[message.id] == .heldForAnswer {
            set(message.id, .waitingForTurnEnd)
        }
    }

    // MARK: - Tab and Superset

    private func pump(_ session: String) {
        while !inFlight.contains(session), let head = queues[session]?.first {
            guard let reach = reach(session) else {
                fail(head, .sessionGone)
                continue
            }
            switch reach.route {
            case .stopHook:
                // The Stop hook ignores the asking gate.
                queues[session]?.removeFirst()
                handToDesk(head)
            case .tab(let place):
                if holdAll(session) { return }
                guard holdsTab(reach.process, place) else {
                    fail(head, .claudeNotRunning)
                    continue
                }
                start(head, session: session, isSuperset: false) { [type, asking, holdsTab] in
                    type(head.text, place) {
                        AgentStore.onMain { holdsTab(reach.process, place) && !asking(session) }
                    }
                }
            case .superset(let workspace, let terminal):
                if holdAll(session) { return }
                // Superset tells no tab: only that Claude is in front of its terminal.
                guard holdsTab(reach.process, nil) else {
                    fail(head, .claudeNotRunning)
                    continue
                }
                start(head, session: session, isSuperset: true) { [superset, asking, holdsTab] in
                    superset(workspace, terminal, head.text) {
                        AgentStore.onMain { holdsTab(reach.process, nil) && !asking(session) }
                    }
                }
            }
        }
    }

    /// While the session asks, everything queued for it waits. True when it did.
    private func holdAll(_ session: String) -> Bool {
        guard asking(session) else { return false }
        for held in queues[session] ?? [] where statuses[held.id] != .heldForAnswer { set(held.id, .heldForAnswer) }
        return true
    }

    private func start(_ message: PhoneMessage, session: String, isSuperset: Bool, run: @escaping () -> TypingResult) {
        queues[session]?.removeFirst()
        inFlight.insert(session)
        worker.async { [weak self] in
            let result = run()
            DispatchQueue.main.async { self?.finish(message, result, isSuperset: isSuperset) }
        }
    }

    private func finish(_ message: PhoneMessage, _ result: TypingResult, isSuperset: Bool) {
        let session = message.session
        inFlight.remove(session)
        switch result {
        case .typed: set(message.id, .sent)
        case .stoppedBeforeText:
            if asking(session) {
                queues[session, default: []].insert(message, at: 0)
                set(message.id, .heldForAnswer)
            } else {
                set(message.id, .notSent(.claudeNotRunning))
            }
        // A request open now stopped it; with none, Claude left the tab.
        case .stoppedBeforeEnter: set(message.id, .notSent(asking(session) ? .stoppedBeforeEnter : .leftBeforeEnter))
        case .tabNotFound: set(message.id, .notSent(.tabNotFound))
        case .ambiguous: set(message.id, .notSent(.ambiguousTab))
        case .notAllowed: set(message.id, .notSent(.notAllowed))
        case .timedOut: set(message.id, .notSent(.timedOut))
        case .failed(let x): set(message.id, .notSent(isSuperset ? .superset(x) : .failed(x)))
        }
        pump(session)
    }

    private func fail(_ message: PhoneMessage, _ reason: NotSentReason) {
        queues[message.session]?.removeFirst()
        set(message.id, .notSent(reason))
    }

    // MARK: - Memory of ids

    private func remember(_ id: UUID, session: String) {
        order.append(id)
        sessionOf[id] = session
        statuses[id] = .received
        // Only finished ids are forgotten; one still queued, held or at the desk stays remembered.
        while order.count > limit, let i = order.firstIndex(where: { isFinished(statuses[$0]) }) {
            let gone = order.remove(at: i)
            statuses[gone] = nil
            sessionOf[gone] = nil
        }
    }

    private func isFinished(_ status: SendStatus?) -> Bool {
        switch status {
        case .received, .heldForAnswer, .waitingForTurnEnd: return false
        default: return true
        }
    }

    private func set(_ id: UUID, _ status: SendStatus) {
        guard statuses[id] != nil else { return }   // a forgotten id stays forgotten
        statuses[id] = status
        onStatus(id, sessionOf[id] ?? "", status)
    }
}
