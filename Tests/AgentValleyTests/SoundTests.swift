import AppKit
import XCTest
@testable import AgentValley

final class SoundTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var center: NotificationCenter!
    private var player: SoundPlayer!
    private var played: [String] = []

    /// Sounds on, the middle of the day, and a list of names in place of the speaker.
    override func setUp() {
        defaults = throwawayDefaults()
        settings = Settings(defaults: defaults)
        settings.sounds = true
        center = NotificationCenter()
        player = SoundPlayer(settings: settings, center: center)
        player.hour = { _ in 12 }
        played = []
        player.sink = { [unowned self] in self.played.append($0) }
    }

    override func tearDown() {
        player = nil
    }

    private func after(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    private func list(_ cards: [SessionCard], at seconds: TimeInterval = 0, looking: Bool = false) {
        player.listed(cards, loaded: true, looks: 0, looking: looking, now: after(seconds))
    }

    private func beat(at seconds: TimeInterval, waiting: Bool = true, looks: Int = 0) {
        player.beat(waiting: waiting, looks: looks, now: after(seconds))
    }

    /// What macOS says when the screen locks, unlocks, or the screen saver starts and stops.
    private func post(_ name: String) {
        center.post(name: Notification.Name(name), object: nil)
    }

    /// The one session of a test that has only one.
    private func card(_ status: AgentStatus, ran: TimeInterval = 0, agents: [AgentStatus] = [], moved: Date? = nil) -> SessionCard {
        card("s", status, ran: ran, agents: agents, moved: moved)
    }

    /// A session whose rows have all run for `ran` seconds, and wrote their last line at `moved`.
    private func card(_ id: String, _ status: AgentStatus, ran: TimeInterval = 0, agents: [AgentStatus] = [], moved: Date? = nil) -> SessionCard {
        func row(_ name: String, _ status: AgentStatus) -> AgentRow {
            var info = AgentInfo()
            info.lastActivity = moved
            return AgentRow(id: id + name, info: info, status: status, elapsed: ran)
        }
        return SessionCard(id: id, project: id, branch: "", main: row("/main", status),
                           agents: agents.enumerated().map { row("/agent\($0.offset)", $0.element) }, startedAt: now)
    }

    // MARK: - What decides

    func testQuietHoursInsideOneDay() {
        XCTAssertFalse(Sound.isQuiet(hour: 11, from: 12, until: 14))
        XCTAssertTrue(Sound.isQuiet(hour: 12, from: 12, until: 14))
        XCTAssertTrue(Sound.isQuiet(hour: 13, from: 12, until: 14))
        XCTAssertFalse(Sound.isQuiet(hour: 14, from: 12, until: 14))
    }

    func testQuietHoursThroughMidnight() {
        for hour in [22, 23, 0, 7] { XCTAssertTrue(Sound.isQuiet(hour: hour, from: 22, until: 8), "\(hour)") }
        for hour in [8, 12, 21] { XCTAssertFalse(Sound.isQuiet(hour: hour, from: 22, until: 8), "\(hour)") }
    }

    func testTheSameHourForBothIsNoQuietAtAll() {
        for hour in 0..<24 { XCTAssertFalse(Sound.isQuiet(hour: hour, from: 8, until: 8), "\(hour)") }
    }

    func testAnHourStepsRoundTheClock() {
        XCTAssertEqual(Sound.hour(22, movedBy: 1), 23)
        XCTAssertEqual(Sound.hour(23, movedBy: 1), 0)
        XCTAssertEqual(Sound.hour(0, movedBy: -1), 23)
    }

    func testEveryReasonAgainstSilencesASound() {
        XCTAssertTrue(Sound.plays(sounds: true, enabled: true, locked: false, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: false, enabled: true, locked: false, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: true, enabled: false, locked: false, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: true, enabled: true, locked: true, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: true, enabled: true, locked: false, quiet: true))
    }

    func testAReminderIsDueOnceItsMinutesHavePassed() {
        XCTAssertFalse(Sound.remindDue(every: 0, since: now, now: after(3600)))
        XCTAssertFalse(Sound.remindDue(every: 1, since: nil, now: now))
        XCTAssertFalse(Sound.remindDue(every: 1, since: now, now: after(59)))
        XCTAssertTrue(Sound.remindDue(every: 1, since: now, now: after(60)))
    }

    func testASessionThatStopsAfterALongTurnHasFinished() {
        let began = Sound.finished([card(.working)], since: [:], now: now)
        XCTAssertFalse(began.finished)
        XCTAssertEqual(began.since, ["s": now])
        XCTAssertFalse(Sound.finished([card(.done)], since: began.since, now: after(29)).finished)
        let ended = Sound.finished([card(.done)], since: began.since, now: after(30))
        XCTAssertTrue(ended.finished)
        XCTAssertEqual(ended.since, [:])
    }

    // A row is called done some seconds after its last line: the turn ended when that line
    // was written, and that is where its length is measured to.
    func testATurnIsMeasuredToItsLastLineNotToWhenItWasSeenDone() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        XCTAssertFalse(Sound.finished([card(.done, moved: after(22))], since: began, now: after(32)).finished)
        XCTAssertTrue(Sound.finished([card(.done, moved: after(30))], since: began, now: after(40)).finished)
    }

    func testASessionFirstSeenIdleHasFinishedNothing() {
        XCTAssertFalse(Sound.finished([card(.done)], since: [:], now: now).finished)
    }

    // The app opened in the middle of a turn: it began when the transcript says, not just now.
    func testASessionFirstSeenAtWorkBeganWhenItsLongestAgentDid() {
        let seen = Sound.finished([card(.working, ran: 120)], since: [:], now: now)
        XCTAssertEqual(seen.since, ["s": after(-120)])
        XCTAssertTrue(Sound.finished([card(.done)], since: seen.since, now: after(1)).finished)
    }

    // The main agent has ended its turn and a sub-agent works on: the session has not finished.
    func testASessionIsNotFinishedWhileASubAgentWorks() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        let behind = Sound.finished([card(.done, agents: [.working])], since: began, now: after(60))
        XCTAssertFalse(behind.finished)
        XCTAssertEqual(behind.since, ["s": now])
        XCTAssertTrue(Sound.finished([card(.done, agents: [.done])], since: behind.since, now: after(90)).finished)
    }

    func testAWaitThatEndsInAFinishedTurnHasFinished() {
        let began = Sound.finished([card(.needsYou)], since: [:], now: now).since
        XCTAssertTrue(Sound.finished([card(.done)], since: began, now: after(45)).finished)
    }

    // A name that is not on this Mac would be silence, with nothing to say so.
    func testBothSoundsAreOnThisMac() {
        XCTAssertNotNil(NSSound(named: SoundEvent.needsYou.sound))
        XCTAssertNotNil(NSSound(named: SoundEvent.finished.sound))
    }

    // MARK: - The player

    // What was already there when the app opened is not news.
    func testTheFirstListMakesNoSound() {
        player.listed([card(.needsYou)], loaded: false, looks: 0, looking: false, now: now)
        list([card(.needsYou)])
        XCTAssertEqual(played, [])
    }

    func testAnAgentThatStartsToWaitSounds() {
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, ["Glass"])
    }

    // The app opened with nothing running: the first session to wait is news.
    func testAWaitAfterAnEmptyFirstListSounds() {
        list([])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, ["Glass"])
    }

    func testSeveralStartingToWaitAtOnceSoundOnce() {
        list([card("a", .working), card("b", .working)])
        list([card("a", .needsYou), card("b", .needsYou)], at: 5)
        XCTAssertEqual(played, ["Glass"])
    }

    func testAWaitSeenAsItHappensMakesNoSound() {
        list([card(.working)])
        list([card(.needsYou)], at: 5, looking: true)
        XCTAssertEqual(played, [])
    }

    func testAFinishedSessionSounds() {
        list([card(.working)])
        list([card(.done)], at: 40)
        XCTAssertEqual(played, ["Pop"])
    }

    func testAShortTurnEndsWithoutASound() {
        list([card(.working)])
        list([card(.done)], at: 10)
        XCTAssertEqual(played, [])
    }

    // One sound for one list: the wait is the one that asks for something.
    func testAWaitComesBeforeAFinishInTheSameList() {
        list([card("a", .working), card("b", .working)])
        list([card("a", .done), card("b", .needsYou)], at: 40)
        XCTAssertEqual(played, ["Glass"])
    }

    func testSwitchedOffNothingSounds() {
        settings.sounds = false
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        list([card(.done)], at: 40)
        XCTAssertEqual(played, [])
    }

    func testEachMomentHasItsOwnSwitch() {
        settings.soundNeedsYou = false
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, [])
        list([card(.done)], at: 40)
        XCTAssertEqual(played, ["Pop"])

        settings.soundNeedsYou = true
        settings.soundFinished = false
        list([card(.working)], at: 50)
        list([card(.done)], at: 100)
        XCTAssertEqual(played, ["Pop"])
        list([card(.needsYou)], at: 110)
        XCTAssertEqual(played, ["Pop", "Glass"])
    }

    func testQuietHoursAreSilentAndNothingFollowsThem() {
        settings.quietHours = true
        player.hour = { _ in 23 }
        XCTAssertTrue(player.quiet(at: now))
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, [])
        // Morning: nothing is owed for the night.
        player.hour = { _ in 9 }
        XCTAssertFalse(player.quiet(at: now))
        beat(at: 36_000)
        XCTAssertEqual(played, [])
    }

    func testALockedScreenHoldsAWaitsSoundUntilItIsUnlocked() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        beat(at: 8)
        XCTAssertEqual(played, [])
        post("com.apple.screenIsUnlocked")
        beat(at: 11)
        XCTAssertEqual(played, ["Glass"])
        beat(at: 14)
        XCTAssertEqual(played, ["Glass"])
    }

    func testNothingIsOwedOnceThePersonHasLooked() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        post("com.apple.screenIsUnlocked")
        beat(at: 8, looks: 1)
        XCTAssertEqual(played, [])
    }

    func testNothingIsOwedOnceNobodyWaits() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        post("com.apple.screenIsUnlocked")
        beat(at: 8, waiting: false)
        beat(at: 11)
        XCTAssertEqual(played, [])
    }

    func testAFinishedTurnUnderALockIsDropped() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.done)], at: 40)
        post("com.apple.screenIsUnlocked")
        beat(at: 43, waiting: false)
        XCTAssertEqual(played, [])
    }

    // The screen saver stops when the person touches a key, and the lock screen is still up.
    func testAScreenSaverThatStopsUnderALockLeavesTheScreenLocked() {
        XCTAssertFalse(player.locked)
        post("com.apple.screensaver.didstart")
        post("com.apple.screenIsLocked")
        post("com.apple.screensaver.didstop")
        XCTAssertTrue(player.locked)
        post("com.apple.screenIsUnlocked")
        XCTAssertFalse(player.locked)
    }

    func testAScreenSaverAloneSilences() {
        list([card(.working)])
        post("com.apple.screensaver.didstart")
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, [])
        post("com.apple.screensaver.didstop")
        beat(at: 8)
        XCTAssertEqual(played, ["Glass"])
    }

    // Unlocked in the quiet hours: the sound is owed no more, and none follows in the morning.
    func testAHeldSoundIsDroppedWhenTheUnlockFallsInQuietHours() {
        settings.quietHours = true
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        post("com.apple.screenIsUnlocked")
        player.hour = { _ in 23 }
        beat(at: 8)
        player.hour = { _ in 9 }
        beat(at: 36_000)
        XCTAssertEqual(played, [])
    }

    func testRemindersRepeatUntilThePersonLooks() {
        settings.remindMinutes = 1
        list([card(.working)])
        list([card(.needsYou)])
        beat(at: 59)
        XCTAssertEqual(played.count, 1)
        beat(at: 60)
        XCTAssertEqual(played, ["Glass", "Glass"])
        beat(at: 119)
        XCTAssertEqual(played.count, 2)
        beat(at: 120)
        XCTAssertEqual(played.count, 3)
        // Looked: the reminders stop, as the bar's glow does.
        beat(at: 180, looks: 1)
        XCTAssertEqual(played.count, 3)
    }

    func testAnotherAgentStartingToWaitStartsTheCountAgain() {
        settings.remindMinutes = 1
        list([card("a", .working), card("b", .working)])
        list([card("a", .needsYou), card("b", .working)])
        list([card("a", .needsYou), card("b", .needsYou)], at: 50)
        XCTAssertEqual(played.count, 2)
        beat(at: 60)
        XCTAssertEqual(played.count, 2)
        beat(at: 110)
        XCTAssertEqual(played.count, 3)
    }

    func testNoRemindersWhenTheyAreOff() {
        list([card(.working)])
        list([card(.needsYou)])
        beat(at: 3600)
        XCTAssertEqual(played, ["Glass"])
    }

    // Waiting since before the app opened: never sounded, so never sounded again.
    func testNoRemindersForAWaitFromBeforeTheAppOpened() {
        settings.remindMinutes = 1
        list([card(.needsYou)])
        beat(at: 600)
        XCTAssertEqual(played, [])
    }

    func testAReminderUnderALockIsOwed() {
        settings.remindMinutes = 1
        list([card(.working)])
        list([card(.needsYou)])
        post("com.apple.screenIsLocked")
        beat(at: 60)
        XCTAssertEqual(played, ["Glass"])
        post("com.apple.screenIsUnlocked")
        beat(at: 63)
        XCTAssertEqual(played, ["Glass", "Glass"])
    }

    // The person's own click: they hear what turning sounds on means, whatever the hour.
    func testTheSamplePlaysWhateverTheHour() {
        settings.quietHours = true
        player.hour = { _ in 23 }
        player.sample()
        XCTAssertEqual(played, ["Glass"])
    }
}
