import AppKit

/// The two moments the app makes a sound for.
enum SoundEvent: Equatable {
    case needsYou, finished

    /// The name of a macOS system sound, one of those in /System/Library/Sounds.
    var sound: String {
        switch self {
        case .needsYou: return "Glass"
        case .finished: return "Pop"
        }
    }
}

/// What decides whether a sound plays. No clock and no speaker here: everything is handed in.
enum Sound {
    /// A session that was at it for less than this ends without a sound: the person was most
    /// likely still at the terminal.
    // ponytail: one length for everyone; make it a setting if people ask.
    static let shortTurn: TimeInterval = 30

    /// Whether `hour` falls in the quiet hours: from `start` up to, not including, `end`. A
    /// start after the end runs through midnight. The same hour for both is no quiet at all.
    static func isQuiet(hour: Int, from start: Int, until end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (start..<end).contains(hour) : hour >= start || hour < end
    }

    /// An hour of the day moved by `step` hours, round the clock.
    static func hour(_ hour: Int, movedBy step: Int) -> Int {
        ((hour + step) % 24 + 24) % 24
    }

    /// Whether a sound may play. In the order the reasons against are checked.
    static func plays(sounds: Bool, enabled: Bool, locked: Bool, quiet: Bool) -> Bool {
        sounds && enabled && !locked && !quiet
    }

    /// Whether it is time to say again that someone waits.
    static func remindDue(every minutes: Int, since last: Date?, now: Date) -> Bool {
        guard minutes > 0, let last else { return false }
        return now.timeIntervalSince(last) >= TimeInterval(minutes * 60)
    }

    /// Follows how long each session has been at it. `since` says when each session that is not
    /// idle began; what comes back says the same for this list. Finished: a session in `since`
    /// is idle now, and wrote its last line at least `shortTurn` after it began: a row is only
    /// called done some seconds after that line. A session first seen idle has finished
    /// nothing, and one first seen at work began when its longest-running agent did.
    static func finished(_ cards: [SessionCard], since: [String: Date], now: Date) -> (finished: Bool, since: [String: Date]) {
        var going: [String: Date] = [:]
        var finished = false
        for card in cards {
            if card.isIdle {
                if let began = since[card.id], (card.movedAt ?? now).timeIntervalSince(began) >= shortTurn { finished = true }
            } else {
                let longest = card.rows.filter { $0.status != .done }.map(\.elapsed).max() ?? 0
                going[card.id] = since[card.id] ?? now.addingTimeInterval(-longest)
            }
        }
        return (finished, going)
    }
}

/// Makes the app's sounds. Told what the list holds and when the bar's timer ticks; decides
/// with `Sound`, and remembers only what it was last told. Used on the main thread alone.
final class SoundPlayer {
    private let settings: Settings
    private let center: NotificationCenter
    /// Takes the name of each sound in place of the speaker. For tests.
    var sink: ((String) -> Void)?
    /// The hour of the day at a moment. For tests, which cannot wait for the evening.
    var hour: (Date) -> Int = { Calendar.current.component(.hour, from: $0) }

    /// Two marks, not one: the screen saver stops at a key press while the lock is still up.
    private var screenLocked = false
    private var saverRunning = false
    /// Nobody is at the screen to hear anything.
    var locked: Bool { screenLocked || saverRunning }

    /// How many rows waited on the person in each session, as last listed. nil until the first
    /// list has been read: what was already there when the app opened is not news.
    private var waiting: [String: Int]?
    /// When each session that is not idle began.
    private var since: [String: Date] = [:]
    /// Whether the person has looked since someone last started to wait.
    private var watch = WaitWatch()
    /// When the wait was last sounded, or would have been: reminders count from here. nil until
    /// someone starts to wait while the app runs.
    private var soundedAt: Date?
    /// A wait's sound came due under a locked screen, and is owed once it is not.
    private var held = false
    private var playing: NSSound?
    private var observers: [NSObjectProtocol] = []

    /// `center`: where macOS says the screen has locked. Another one in tests.
    init(settings: Settings, center: NotificationCenter = DistributedNotificationCenter.default()) {
        self.settings = settings
        self.center = center
        observe("com.apple.screenIsLocked", \.screenLocked, true)
        observe("com.apple.screenIsUnlocked", \.screenLocked, false)
        observe("com.apple.screensaver.didstart", \.saverRunning, true)
        observe("com.apple.screensaver.didstop", \.saverRunning, false)
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    /// No queue: the distributed center posts on the main thread, and the mark is set as it does.
    private func observe(_ name: String, _ mark: ReferenceWritableKeyPath<SoundPlayer, Bool>, _ value: Bool) {
        observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [weak self] _ in
            self?[keyPath: mark] = value
        })
    }

    /// Whether this moment is in the person's quiet hours.
    func quiet(at now: Date) -> Bool {
        settings.quietHours && Sound.isQuiet(hour: hour(now), from: settings.quietFrom, until: settings.quietUntil)
    }

    /// The list as it is now. `looks`: how many times the panel has been looked at. `looking`:
    /// the person is at the open panel right now, and sees what happens as it does.
    func listed(_ cards: [SessionCard], loaded: Bool, looks: Int, looking: Bool, now: Date = Date()) {
        guard loaded else { return }
        let turn = Sound.finished(cards, since: since, now: now)
        since = turn.since
        let before = waiting
        let after = AgentStore.waiting(cards)
        waiting = after
        guard let before else { return }
        if WaitWatch.arrived(from: before, to: after) {
            watch.arrived(looks: looks, lookingNow: looking)
            soundedAt = now
            held = false
            // Seen as it happens: a sound would only say what the person is looking at.
            if !looking { ring(.needsYou, now: now) }
        } else if turn.finished {
            // Never on top of a wait's sound: the wait is the one that asks for something.
            ring(.finished, now: now)
        }
    }

    /// Every few seconds, from the bar's own timer: the reminder, and the sound a locked
    /// screen held back.
    func beat(waiting: Bool, looks: Int, now: Date = Date()) {
        // Nobody waits, or the person has looked: nothing is owed and nothing is said again.
        guard waiting, soundedAt != nil, !watch.seen(looks: looks) else { return held = false }
        guard held || Sound.remindDue(every: settings.remindMinutes, since: soundedAt, now: now) else { return }
        soundedAt = now
        ring(.needsYou, now: now)
    }

    /// The sound of a wait, on the person's own click: they have just turned sounds on, and
    /// hear what that means. Not held back by the quiet hours.
    func sample() {
        emit(SoundEvent.needsYou.sound)
    }

    private func ring(_ event: SoundEvent, now: Date) {
        // A wait's sound is owed while the lock is up, and no longer: unlocked into the quiet
        // hours, it is dropped. A finished turn's is never owed.
        if event == .needsYou { held = locked }
        let enabled = event == .needsYou ? settings.soundNeedsYou : settings.soundFinished
        if Sound.plays(sounds: settings.sounds, enabled: enabled, locked: locked, quiet: quiet(at: now)) { emit(event.sound) }
    }

    private func emit(_ name: String) {
        if let sink { return sink(name) }
        // A name the system does not have is no sound: a beep in its place would say something else.
        playing?.stop()
        playing = NSSound(named: name)
        playing?.play()
    }
}
