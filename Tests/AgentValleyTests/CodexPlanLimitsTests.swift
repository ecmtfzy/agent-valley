import Darwin
import Foundation
import XCTest
@testable import AgentValley

final class CodexPlanLimitsTests: XCTestCase {
    private func window(_ percent: Any = 25, minutes: Any = 300, reset: Any = 1_900_000_000) -> [String: Any] {
        ["usedPercent": percent, "windowDurationMins": minutes, "resetsAt": reset]
    }

    private func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    private func reply(_ primary: [String: Any], secondary: [String: Any]? = nil,
                       ordinary: Any = true) throws -> Data {
        try data(["rateLimitsByLimitId": ["codex": ["limitId": "codex", "planType": "pro",
                    "primary": primary, "secondary": secondary as Any? ?? NSNull()]],
                  "ordinaryUsageAllowed": ordinary])
    }

    func testWindowsAreMappedByDurationRatherThanPosition() throws {
        let snapshot = try XCTUnwrap(CodexPlanLimitsReader.read(reply(window(4, minutes: 10_080), secondary: window(35))))
        XCTAssertEqual(snapshot.limits.fiveHour?.usedPercent, 35)
        XCTAssertEqual(snapshot.limits.week?.usedPercent, 4)
        XCTAssertEqual(snapshot.limits.provider, .codex)
        XCTAssertEqual(snapshot.limits.ordinaryUsageAllowed, true)
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.limitID, "codex")
        XCTAssertEqual(snapshot.limits.week?.resetsAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testAbsentSecondaryDoesNotInventFiveHourWindow() throws {
        let limits = try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(4, minutes: 10_080))))
        XCTAssertNil(limits.fiveHour)
        XCTAssertEqual(limits.week?.usedPercent, 4)
        XCTAssertNil(PlanLimitsClient.Display.limits(limits, asOf: nil).ring)
    }

    func testUnknownPermissionCannotAnnounceRecoveryFromOldBlockedNumbers() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_001)
        func shown(_ percent: Int, ordinary: Any) throws -> PlanLimitsClient.Display {
            .limits(try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(percent), ordinary: ordinary))), asOf: nil)
        }
        let exhausted = try shown(100, ordinary: false)
        let unknown = try shown(100, ordinary: NSNull())
        let otherBlock = try shown(4, ordinary: false)
        let available = try shown(4, ordinary: true)
        XCTAssertTrue(exhausted.knowsAvailability(now: now))
        XCTAssertFalse(unknown.knowsAvailability(now: now))
        // Spend controls can block an account with quota left: neither a quota
        // fishing scene nor a recovered sound is justified by those percentages.
        XCTAssertFalse(otherBlock.knowsAvailability(now: now))
        XCTAssertTrue(available.knowsAvailability(now: now))
        let claude = PlanLimitsClient.Display.limits(PlanLimits(fiveHour: PlanLimit(usedPercent: 4, resetsAt: nil)), asOf: nil)
        XCTAssertTrue(claude.knowsAvailability(now: now))
    }

    func testAuthoritativeMapNeverFallsBackToLegacyOrAnotherProduct() throws {
        let legacy: [String: Any] = ["limitId": "codex", "primary": window(99)]
        for map: Any in [[:], ["images": legacy], ["codex": NSNull()], false, "malformed",
                         ["codex": ["limitId": "images", "primary": window()]]] {
            XCTAssertNil(CodexPlanLimitsReader.parse(try data(["rateLimitsByLimitId": map, "rateLimits": legacy])))
        }
        let preferred = try XCTUnwrap(CodexPlanLimitsReader.parse(data([
            "rateLimitsByLimitId": ["codex": ["primary": window(12)]], "rateLimits": legacy])))
        XCTAssertEqual(preferred.fiveHour?.usedPercent, 12)
    }

    func testLegacyRequiresMissingNullOrCodexIdentity() throws {
        for identity in [nil, NSNull(), "codex"] as [Any?] {
            var bucket: [String: Any] = ["primary": window()]
            if let identity { bucket["limitId"] = identity }
            let parsed = CodexPlanLimitsReader.parse(try data(["rateLimitsByLimitId": NSNull(), "rateLimits": bucket]))
            XCTAssertEqual(parsed?.fiveHour?.usedPercent, 25)
        }
        for identity: Any in ["images", "", 0, true] {
            XCTAssertNil(CodexPlanLimitsReader.parse(try data(["rateLimits": ["limitId": identity, "primary": window()]])))
        }
    }

    func testMalformedNumbersAndUnsupportedWindowsDoNotBecomeZero() throws {
        for value: Any in [true, false, "25", "nan", "inf", -1, 100_001, NSNull()] {
            XCTAssertNil(CodexPlanLimitsReader.parse(try reply(window(value))))
        }
        for duration: Any in [true, 0, -300, 300.5, "300", 60, 1_000_001, NSNull()] {
            XCTAssertNil(CodexPlanLimitsReader.parse(try reply(window(minutes: duration))))
        }
        XCTAssertNil(CodexPlanLimitsReader.parse(Data(#"{"rateLimits":{"primary":{"usedPercent":1e309,"windowDurationMins":300}}}"#.utf8)))
        XCTAssertNil(CodexPlanLimitsReader.parse(Data(#"{"rateLimits":{"primary":{"usedPercent":NaN,"windowDurationMins":300}}}"#.utf8)))
        XCTAssertNil(CodexPlanLimitsReader.parse(Data("not json".utf8)))
        XCTAssertNil(CodexPlanLimitsReader.parse(Data(repeating: 32, count: CodexLimitsSource.maximumOutputBytes + 1)))
        let partial = try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(40, minutes: 60), secondary: window(0, minutes: 10_080))))
        XCTAssertNil(partial.fiveHour)
        XCTAssertEqual(partial.week?.usedPercent, 0)
    }

    func testInvalidResetPreservesMeasurementWithoutInventingADate() throws {
        for value: Any in [true, "1900000000", -1, 1.5, 1e50, NSNull()] {
            let limits = try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(reset: value))))
            XCTAssertEqual(limits.fiveHour?.usedPercent, 25)
            XCTAssertNil(limits.fiveHour?.resetsAt)
        }
    }

    func testUsagePermissionAndSpendControlAreStrictSeparateBooleans() throws {
        for value: Any in [0, 1, "true", "false", NSNull()] {
            let snapshot = try XCTUnwrap(CodexPlanLimitsReader.read(reply(window(100), ordinary: value)))
            XCTAssertNil(snapshot.ordinaryUsageAllowed)
            XCTAssertNil(snapshot.limits.runOut(now: Date(timeIntervalSince1970: 1_800_000_000)))
        }
        let snapshot = try XCTUnwrap(CodexPlanLimitsReader.read(data([
            "rateLimitsByLimitId": ["codex": ["primary": window(100), "spendControlReached": true,
                "rateLimitReachedType": "credits"]], "ordinaryUsageAllowed": true])))
        XCTAssertEqual(snapshot.spendControlReached, true)
        XCTAssertEqual(snapshot.rateLimitReachedType, "credits")
        XCTAssertNil(snapshot.limits.runOut(now: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testOnlyConfirmedOrdinaryExhaustionStopsWorkAndPastResetCannotPromiseRecovery() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let rounded = try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(99.5), ordinary: false)))
        XCTAssertNil(rounded.runOut(now: now))
        let blocked = try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(100), ordinary: false)))
        XCTAssertEqual(blocked.runOut(now: now), RunOut(weekly: false, resetsAt: Date(timeIntervalSince1970: 1_900_000_000)))
        let allowed = try XCTUnwrap(CodexPlanLimitsReader.parse(reply(window(100), ordinary: true)))
        XCTAssertNil(allowed.runOut(now: now))
        let claude = PlanLimits(fiveHour: PlanLimit(usedPercent: 99.5, resetsAt: nil), week: nil)
        XCTAssertEqual(claude.runOut(now: now), RunOut(weekly: false, resetsAt: nil))
    }

    func testSourceCompletesOnceOnMainThreadWithProductionParser() throws {
        let fixture = try Fixture(script: "print('{\"rateLimits\": {\"limitId\": \"codex\", \"primary\": {\"usedPercent\": 6, \"windowDurationMins\": 300}}, \"ordinaryUsageAllowed\": true}')")
        defer { fixture.remove() }
        let source = CodexLimitsSource(command: { fixture.command })
        var results: [Result<PlanLimits, LimitsFailure>] = []
        let cancel = source.fetch { result in
            XCTAssertTrue(Thread.isMainThread)
            results.append(result)
        }
        defer { cancel() }
        XCTAssertTrue(wait { !results.isEmpty })
        let limits = try results.first?.get()
        XCTAssertEqual(limits?.fiveHour?.usedPercent, 6)
        pump(for: 0.1)
        XCTAssertEqual(results.count, 1)
    }

    func testCancellationBeforeLaunchNeverAsksTheCommandFactory() {
        let queue = DispatchQueue(label: "codex-limits-cancel-before-launch")
        queue.suspend()
        var asked = false
        var answered = false
        let source = CodexLimitsSource(command: { asked = true; return nil }, queue: queue)
        let cancel = source.fetch { _ in answered = true }
        cancel()
        queue.resume()
        queue.sync {}
        pump(for: 0.05)
        XCTAssertFalse(asked)
        XCTAssertFalse(answered)
    }

    func testTurningOffClientCancelsAndKillsOwnedHelperWithoutBlockingMain() throws {
        let fixture = try Fixture(script: "import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nmark_pid()\ntime.sleep(60)")
        defer { fixture.remove() }
        let source = CodexLimitsSource(command: { fixture.command }, timeout: 10, terminationGrace: 0.1)
        let client = PlanLimitsClient(source: source)
        client.refreshIfStale()
        client.tick()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.pidFile.path))
        client.setEnabled(true)
        XCTAssertTrue(wait { fixture.pid != nil })
        let before = ProcessInfo.processInfo.systemUptime
        client.setEnabled(false)
        XCTAssertTrue(ProcessInfo.processInfo.systemUptime - before < 0.1)
        XCTAssertTrue(wait { fixture.isGone })
        pump(for: 0.1)
        XCTAssertEqual(client.display, .off)
        XCTAssertNil(client.limits)
        XCTAssertNil(client.failure)
    }

    func testTimeoutEscalatesTermIgnoringHelperAndReturnsNoAnswer() throws {
        let fixture = try Fixture(script: "import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nmark_pid()\ntime.sleep(60)")
        defer { fixture.remove() }
        let source = CodexLimitsSource(command: { fixture.command }, timeout: 0.2, terminationGrace: 0.1)
        var result: Result<PlanLimits, LimitsFailure>?
        let before = ProcessInfo.processInfo.systemUptime
        let cancel = source.fetch { result = $0 }
        defer { cancel() }
        XCTAssertTrue(wait { result != nil })
        XCTAssertEqual(result, .failure(.noAnswer))
        XCTAssertTrue(ProcessInfo.processInfo.systemUptime - before < 2)
        XCTAssertTrue(wait { fixture.isGone })
    }

    func testOutputIsBoundedAndNoisyHelperIsStopped() throws {
        let fixture = try Fixture(script: "import sys, time\nmark_pid()\nsys.stdout.write('x' * 40000)\nsys.stdout.flush()\ntime.sleep(60)")
        defer { fixture.remove() }
        let source = CodexLimitsSource(command: { fixture.command }, timeout: 5, terminationGrace: 0.1)
        var result: Result<PlanLimits, LimitsFailure>?
        let cancel = source.fetch { result = $0 }
        defer { cancel() }
        XCTAssertTrue(wait { result != nil })
        XCTAssertEqual(result, .failure(.unreadable))
        XCTAssertTrue(wait { fixture.isGone })
    }

    func testFailedOrMalformedHelperNeverBecomesAZeroQuota() throws {
        for (script, expected) in [("raise SystemExit(1)", LimitsFailure.offline),
                                   ("print('{}')", LimitsFailure.unreadable)] {
            let fixture = try Fixture(script: script)
            defer { fixture.remove() }
            let source = CodexLimitsSource(command: { fixture.command })
            var result: Result<PlanLimits, LimitsFailure>?
            let cancel = source.fetch { result = $0 }
            defer { cancel() }
            XCTAssertTrue(wait { result != nil })
            XCTAssertEqual(result, .failure(expected))
        }
    }

    private func wait(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }

    private func pump(for seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private struct Fixture {
        let directory: URL
        let script: URL
        let pidFile: URL

        init(script body: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-limits-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            script = directory.appendingPathComponent("fixture.py")
            pidFile = directory.appendingPathComponent("pid")
            let contents = "import os\ndef mark_pid():\n    open(\(pidFile.path.debugDescription), 'w').write(str(os.getpid()))\n" + body + "\n"
            try contents.write(to: script, atomically: true, encoding: .utf8)
        }

        var command: CodexLimitsSource.Command {
            .init(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path])
        }
        var pid: pid_t? { (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap(Int32.init) }
        var isGone: Bool { guard let pid else { return false }; return Darwin.kill(pid, 0) == -1 && errno == ESRCH }
        func remove() {
            if let pid, !isGone { Darwin.kill(pid, SIGKILL) }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
