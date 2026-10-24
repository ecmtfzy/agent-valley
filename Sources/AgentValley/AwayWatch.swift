import AppKit
import Combine

/// Joins Away's rules to the Mac: the clock, the last touch, the lock screen and the desk.
/// Main thread only. Away can only be on while a phone is linked.
final class AwayWatch: ObservableObject {
    @Published private(set) var mode = AwayMode() {
        didSet {
            guard mode.on != oldValue.on else { return }
            desk.awayOn = mode.on
            markFlag()
            updateTimer()
            if !mode.on { desk.release() }
        }
    }
    @Published var phoneLinked = false {
        didSet { if !phoneLinked, mode.on { mode.turnOff() } }
    }
    /// Whether the panel shows the Away button. Set by the app from the sessions and the link.
    @Published var buttonShown = false

    private let desk: StopDesk
    /// There only while Away is on: without it the Stop hook's script ends the turn at once, so
    /// an app that hangs never holds anyone's turn end.
    private let flag: URL
    private let now: () -> Date
    private let lastInput: () -> Date
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private(set) var timer: Timer?

    init(desk: StopDesk, folder: URL = AnswerServer.defaultDirectory, now: @escaping () -> Date = Date.init, lastInput: @escaping () -> Date) {
        self.desk = desk
        flag = folder.appendingPathComponent("away")
        self.now = now
        self.lastInput = lastInput
    }

    func turnOn(_ trigger: AwayMode.Trigger) {
        guard phoneLinked else { return }
        mode.turnOn(trigger, at: now())
    }

    func toggleFromPanel() {
        if mode.on { mode.turnOff() } else { turnOn(.panelButton) }
    }

    func screenLocked() { turnOn(.screenLocked) }

    func screenUnlocked() { mode.screenUnlocked() }

    func tick() { mode.noteLastInput(at: lastInput()) }

    /// At launch: a flag left by a copy that quit while Away was on goes, the one-second timer
    /// may run, and the lock screen is listened to.
    func start() {
        try? FileManager.default.removeItem(at: flag)
        started = true
        updateTimer()
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked() },
            center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.screenUnlocked() },
        ]
    }

    private func markFlag() {
        if mode.on {
            try? FileManager.default.createDirectory(at: flag.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: flag.path, contents: nil)
        } else {
            try? FileManager.default.removeItem(at: flag)
        }
    }

    /// The last touch only matters while Away is on, so the timer runs only then.
    private func updateTimer() {
        if started, mode.on {
            if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() } }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
}
