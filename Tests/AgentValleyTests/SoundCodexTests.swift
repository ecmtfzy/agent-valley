import Foundation
import XCTest
@testable import AgentValley

/// Pure lifecycle fixtures also run without audio hardware in the standalone smoke test.
final class SoundCodexTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ value: Double) -> Date { epoch.addingTimeInterval(value) }
    private func receipt(_ turn: String = "first", start: Double? = 0, end: Double = 40) -> CodexTurnCompletion {
        CodexTurnCompletion(turnID: turn, startedAt: start.map(at), endedAt: at(end))
    }
    private func card(_ status: AgentStatus = .working, turn: String = "first", start: Double? = 0,
                      moved: Double = 0, receipts: [CodexTurnCompletion] = [],
                      children: [AgentStatus] = [], childMoved: Double? = nil, closed: Bool = false) -> SessionCard {
        var info = AgentInfo()
        info.codexTurnID = turn
        info.turnStartedAt = start.map(at)
        info.lastActivity = at(moved)
        info.turnEnded = status == .done
        info.codexCompletedTurns = receipts
        return SessionCard(id: "codex-fixture", project: "fixture", branch: "",
                           main: AgentRow(id: "codex-fixture-main", info: info, status: status, elapsed: max(0, moved - (start ?? moved))),
                           agents: children.enumerated().map { index, status in
                               var child = AgentInfo()
                               child.lastActivity = at(childMoved ?? moved)
                               return AgentRow(id: "child-\(index)", info: child, status: status, elapsed: 0)
                           }, startedAt: at(0), closed: closed)
    }

    func testCompletionBetweenPollsSoundsWhileNextTurnIsAlreadyWorkingExactlyOnce() {
        var observer = Sound.CodexCompletions()
        XCTAssertTrue(observer.finished([card()], now: at(0)).isEmpty)
        let next = card(turn: "second", start: 40.016, moved: 41, receipts: [receipt()])
        XCTAssertEqual(observer.finished([next], now: at(41)), [Sound.Finish(id: "codex-fixture", worked: 40)])
        XCTAssertTrue(observer.finished([next], now: at(42)).isEmpty)
    }

    func testChangingTurnWithoutSuccessfulCompletionNeverInventsSound() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertTrue(observer.finished([card(turn: "second", start: 40, moved: 41)], now: at(41)).isEmpty)
        XCTAssertTrue(observer.finished([card(.done, turn: "second", start: 40, moved: 80)], now: at(80)).isEmpty)
    }

    func testLateFirstHookUsesActualSuccessfulTurnDuration() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card(start: nil, moved: 29)], now: at(29))
        _ = observer.finished([card(start: 0, moved: 30)], now: at(30))
        let finished = observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(41))
        XCTAssertEqual(finished, [Sound.Finish(id: "codex-fixture", worked: 40)])
    }

    func testStartLearnedOnlyAtCompletionStillCorrectsLateObservation() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card(start: nil, moved: 29)], now: at(29))
        XCTAssertEqual(observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(41)).count, 1)
    }

    func testRestartDuringActiveTurnSkipsHistoryButSoundsItsFutureCompletion() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([], now: at(99))
        let old = receipt("old", start: 0, end: 90)
        XCTAssertTrue(observer.finished([card(turn: "current", start: 95, moved: 100, receipts: [old])], now: at(100)).isEmpty)
        let current = receipt("current", start: 95, end: 140)
        XCTAssertEqual(observer.finished([card(.done, turn: "current", start: 95, moved: 140, receipts: [old, current])], now: at(141)).count, 1)
    }

    func testFirstSeenIdleAndUnobservedHistoricalTurnsNeverSound() {
        var observer = Sound.CodexCompletions()
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(41)).isEmpty)
        _ = observer.finished([card(turn: "current", start: 50, moved: 51)], now: at(51))
        XCTAssertTrue(observer.finished([card(turn: "current", start: 50, moved: 52,
                                             receipts: [receipt("unseen", end: 50)])], now: at(52)).isEmpty)
    }

    func testOldCompletionDiscoveredInLaterBatchDoesNotSound() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(161)).isEmpty)
    }

    func testFinalAndTaskCompleteWithDifferentTimestampsSoundOnlyOnce() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertEqual(observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(40)).count, 1)
        XCTAssertTrue(observer.finished([card(.done, moved: 40.1, receipts: [receipt(end: 40.1)])], now: at(41)).isEmpty)
    }

    func testShortTurnKeepsTheSharedThirtySecondRule() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertTrue(observer.finished([card(.done, moved: 29, receipts: [receipt(end: 29)])], now: at(30)).isEmpty)
        _ = observer.finished([card(turn: "second", start: 40, moved: 40)], now: at(40))
        XCTAssertEqual(observer.finished([card(.done, turn: "second", start: 40, moved: 70,
                                              receipts: [receipt("second", start: 40, end: 70)])], now: at(70)).count, 1)
    }

    func testChildrenHoldTheReceiptUntilTheyFinishWithoutConsumingItEarly() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card(children: [.working])], now: at(0))
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()], children: [.working])], now: at(41)).isEmpty)
        XCTAssertEqual(observer.finished([card(.done, moved: 40, receipts: [receipt()], children: [.done])], now: at(60)).count, 1)
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()], children: [.done])], now: at(61)).isEmpty)
    }

    func testFreshCompletionCanWaitOverTwoMinutesForItsObservedChild() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card(children: [.working])], now: at(0))
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()], children: [.working])], now: at(41)).isEmpty)
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()], children: [.working], childMoved: 200)], now: at(201)).isEmpty)
        XCTAssertEqual(observer.finished([card(.done, moved: 40, receipts: [receipt()], children: [.done], childMoved: 300)], now: at(301)),
                       [Sound.Finish(id: "codex-fixture", worked: 300)])
    }

    func testNewTurnChildrenDoNotHoldAnEarlierObservedTurnsCompletion() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        let next = card(turn: "second", start: 40.016, moved: 41, receipts: [receipt()], children: [.working])
        XCTAssertEqual(observer.finished([next], now: at(41)), [Sound.Finish(id: "codex-fixture", worked: 40)])
    }

    func testClosedSessionConsumesItsReceiptWithoutSoundingLater() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()], closed: true)], now: at(41)).isEmpty)
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(42)).isEmpty)
    }

    func testExplicitLaterContinuationOfSameTurnIDCanSoundAgain() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertEqual(observer.finished([card(.done, moved: 40, receipts: [receipt()])], now: at(40)).count, 1)
        _ = observer.finished([card(start: 50, moved: 50, receipts: [receipt()])], now: at(50))
        XCTAssertEqual(observer.finished([card(.done, start: 50, moved: 90, receipts: [receipt(start: 50, end: 90)])], now: at(90)).count, 1)
    }

    func testWaitingTimeIsNotCountedAsWorkForTheSpokenTopic() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        _ = observer.finished([card(.needsYou, moved: 20)], now: at(20))
        _ = observer.finished([card(moved: 60)], resumed: ["codex-fixture": at(60)], now: at(60))
        XCTAssertEqual(observer.finished([card(.done, moved: 70, receipts: [receipt(end: 70)])],
                                         resumed: ["codex-fixture": at(60)], now: at(71)),
                       [Sound.Finish(id: "codex-fixture", worked: 10)])
    }

    func testMalformedIDsAndFutureOrInvalidDatesCannotSound() {
        for turn in ["", String(repeating: "a", count: 129), "bad/id"] {
            var observer = Sound.CodexCompletions()
            _ = observer.finished([card(turn: turn)], now: at(0))
            XCTAssertTrue(observer.finished([card(.done, turn: turn, moved: 40, receipts: [receipt(turn)])], now: at(41)).isEmpty)
        }
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card()], now: at(0))
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt(end: 50)])], now: at(41)).isEmpty)
        XCTAssertTrue(observer.finished([card(.done, moved: 40, receipts: [receipt(start: 50, end: 40)])], now: at(41)).isEmpty)
    }

    func testMissingStartUsesOnlyActuallyObservedDuration() {
        var observer = Sound.CodexCompletions()
        _ = observer.finished([card(start: nil, moved: 29)], now: at(29))
        XCTAssertTrue(observer.finished([card(.done, start: nil, moved: 40, receipts: [receipt(start: nil)])], now: at(41)).isEmpty)
    }
}

/// Full-player coverage uses a sink, so no test emits real sound or changes user settings.
final class SoundCodexPlayerTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ value: Double) -> Date { epoch.addingTimeInterval(value) }

    private func withPlayer(_ work: (SoundPlayer, Settings, () -> [String]) -> Void) {
        let name = "AgentValley-SoundCodexTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = Settings(defaults: defaults)
        settings.sounds = true
        settings.soundFinished = true
        settings.quietHours = false
        settings.soundStyle = .chimes
        let player = SoundPlayer(settings: settings, center: NotificationCenter(), memory: defaults)
        player.hour = { _ in 12 }
        var played: [String] = []
        player.sink = { name, done in played.append(name); done() }
        work(player, settings, { played })
    }

    private func card(_ status: AgentStatus, turn: String = "first", start: Double = 0, moved: Double,
                      receiptEnd: Double? = nil, id: String = "codex-fixture") -> SessionCard {
        var info = AgentInfo()
        info.codexTurnID = turn
        info.turnStartedAt = at(start)
        info.lastActivity = at(moved)
        info.turnEnded = status == .done
        if let receiptEnd {
            info.codexCompletedTurns = [CodexTurnCompletion(turnID: "first", startedAt: at(0), endedAt: at(receiptEnd))]
        }
        return SessionCard(id: id, project: "fixture", branch: "",
                           main: AgentRow(id: id + "-main", info: info, status: status, elapsed: moved - start),
                           agents: [], startedAt: at(0))
    }

    func testVisibleDoneAndReceiptUseOnePlaybackPathIncludingLaterTaskComplete() {
        withPlayer { player, _, played in
            player.listed([card(.working, moved: 0)], loaded: true, looks: 0, looking: false, now: at(0))
            player.listed([card(.done, moved: 40, receiptEnd: 40)], loaded: true, looks: 0, looking: false, now: at(40))
            player.listed([card(.done, moved: 40.1, receiptEnd: 40.1)], loaded: true, looks: 0, looking: false, now: at(41))
            XCTAssertEqual(played(), ["chime-done.m4a"])
        }
    }

    func testSixteenMillisecondContinuationStillPlaysCompletion() {
        withPlayer { player, _, played in
            player.listed([card(.working, moved: 0)], loaded: true, looks: 0, looking: false, now: at(0))
            player.listed([card(.working, turn: "second", start: 40.016, moved: 41, receiptEnd: 40)], loaded: true, looks: 0, looking: false, now: at(41))
            XCTAssertEqual(played(), ["chime-done.m4a"])
        }
    }

    func testTurningSoundBackOnDoesNotReplayAConsumedCompletion() {
        withPlayer { player, settings, played in
            player.listed([card(.working, moved: 0)], loaded: true, looks: 0, looking: false, now: at(0))
            settings.soundFinished = false
            player.listed([card(.done, moved: 40, receiptEnd: 40)], loaded: true, looks: 0, looking: false, now: at(40))
            settings.soundFinished = true
            player.listed([card(.done, moved: 40, receiptEnd: 40)], loaded: true, looks: 0, looking: false, now: at(41))
            XCTAssertTrue(played().isEmpty)
        }
    }

    func testCodexDoneWithoutSuccessReceiptDoesNotSoundAnAbort() {
        withPlayer { player, _, played in
            player.listed([card(.working, moved: 0)], loaded: true, looks: 0, looking: false, now: at(0))
            player.listed([card(.done, moved: 40)], loaded: true, looks: 0, looking: false, now: at(40))
            XCTAssertTrue(played().isEmpty)
        }
    }

    func testClaudeKeepsItsExistingDonePathWithoutCodexReceipt() {
        withPlayer { player, _, played in
            player.listed([card(.working, moved: 0, id: "claude-fixture")], loaded: true, looks: 0, looking: false, now: at(0))
            player.listed([card(.done, moved: 40, id: "claude-fixture")], loaded: true, looks: 0, looking: false, now: at(40))
            XCTAssertEqual(played(), ["chime-done.m4a"])
        }
    }
}
