import Darwin
import Foundation
import XCTest
@testable import AgentValley

final class ClaudeUsageSourceTests: XCTestCase {
    private let limits = PlanLimits(fiveHour: PlanLimit(usedPercent: 17, resetsAt: nil), week: nil)

    func testNormalPrimaryAndUnrelatedFailuresNeverLaunchCLI() throws {
        for result: Result<PlanLimits, LimitsFailure> in [.success(limits), .failure(.noLogin), .failure(.offline),
                                                         .failure(.refused(429)), .failure(.unreadable)] {
            let primary = Stub(result)
            let recovery = Stub(.success(limits))
            let source = ClaudeUsageSource(primary: primary, recovery: recovery)
            XCTAssertEqual(read(source), result)
            XCTAssertEqual(primary.calls, 1)
            XCTAssertEqual(recovery.calls, 0)
        }
    }

    func testExpiredLoginUsesCLIThenFutureFetchReturnsToPrimary() {
        let primary = Stub(.failure(.loginExpired))
        let recovery = Stub(.success(limits))
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        XCTAssertEqual(read(source), .success(limits))
        primary.result = .success(limits)
        XCTAssertEqual(read(source), .success(limits))
        XCTAssertEqual(primary.calls, 2)
        XCTAssertEqual(recovery.calls, 1)
    }

    func testConfirmedAuthFailuresHaveFiveMinuteCooldownButPrimaryStillRuns() {
        for failure: LimitsFailure in [.loginExpired, .noLogin, .refused(401), .refused(403)] {
            var now = Date(timeIntervalSince1970: 10_000)
            let primary = Stub(.failure(.loginExpired))
            let recovery = Stub(.failure(failure))
            let source = ClaudeUsageSource(primary: primary, recovery: recovery, now: { now })
            XCTAssertEqual(read(source), .failure(failure))
            now.addTimeInterval(299)
            XCTAssertEqual(read(source), .failure(.loginExpired))
            XCTAssertEqual(recovery.calls, 1)
            now.addTimeInterval(1)
            recovery.result = .success(limits)
            XCTAssertEqual(read(source), .success(limits))
            XCTAssertEqual(recovery.calls, 2)
            XCTAssertEqual(primary.calls, 4)
        }
    }


    func testFailedUsageRechecksClearedLoginAndDoesNotRetryCLI() {
        let primary = Stub(.failure(.noLogin))
        primary.sequence = [.failure(.loginExpired), .failure(.noLogin)]
        let recovery = Stub(.failure(.unreadable))
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        XCTAssertEqual(read(source), .failure(.noLogin))
        XCTAssertEqual(read(source), .failure(.noLogin))
        XCTAssertEqual(primary.calls, 3)
        XCTAssertEqual(recovery.calls, 1)
    }

    func testFailedUsageRecoversWhenCLIAlreadyRenewedKeychain() {
        let primary = Stub(.success(limits))
        primary.sequence = [.failure(.loginExpired), .success(limits)]
        let recovery = Stub(.failure(.unreadable))
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        XCTAssertEqual(read(source), .success(limits))
        XCTAssertEqual(primary.calls, 2)
        XCTAssertEqual(recovery.calls, 1)
    }

    func testFailedUsageWithStillExpiredLoginPreservesTransientFailure() {
        let primary = Stub(.failure(.loginExpired))
        let recovery = Stub(.failure(.offline))
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        XCTAssertEqual(read(source), .failure(.offline))
        XCTAssertEqual(read(source), .failure(.offline))
        XCTAssertEqual(primary.calls, 4)
        XCTAssertEqual(recovery.calls, 2)
    }

    func testManualLoginDuringCooldownRecoversThroughPrimaryImmediately() {
        let primary = Stub(.failure(.loginExpired))
        let recovery = Stub(.failure(.loginExpired))
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        XCTAssertEqual(read(source), .failure(.loginExpired))
        primary.result = .success(limits)
        XCTAssertEqual(read(source), .success(limits))
        XCTAssertEqual(recovery.calls, 1)
    }

    func testNetworkTimeoutAndMalformedReplyDoNotImposeLongCooldown() {
        for failure: LimitsFailure in [.offline, .noAnswer, .unreadable, .refused(429)] {
            let primary = Stub(.failure(.loginExpired))
            let recovery = Stub(.failure(failure))
            let source = ClaudeUsageSource(primary: primary, recovery: recovery)
            XCTAssertEqual(read(source), .failure(failure))
            recovery.result = .success(limits)
            XCTAssertEqual(read(source), .success(limits))
            XCTAssertEqual(recovery.calls, 2)
        }
    }

    func testCancelPrimaryNeverLaunchesRecoveryOrAnswers() {
        let primary = Stub(nil)
        let recovery = Stub(.success(limits))
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        var answered = false
        let cancel = source.fetch { _ in answered = true }
        cancel()
        primary.reply?(.failure(.loginExpired))
        pump()
        XCTAssertEqual(primary.cancels, 1)
        XCTAssertEqual(recovery.calls, 0)
        XCTAssertFalse(answered)
    }

    func testSynchronousPrimaryDoesNotReplaceRecoveryCancellation() {
        let primary = Stub(.failure(.loginExpired))
        let recovery = Stub(nil)
        let source = ClaudeUsageSource(primary: primary, recovery: recovery)
        var answered = false
        let cancel = source.fetch { _ in answered = true }
        cancel()
        recovery.reply?(.success(limits))
        pump()
        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(recovery.cancels, 1)
        XCTAssertFalse(answered)
    }

    func testResultIsDeliveredOnceOnMainAndCancelSuppressesQueuedResult() {
        let primary = Stub(.success(limits))
        let source = ClaudeUsageSource(primary: primary, recovery: Stub(nil))
        var answers = 0
        let cancel = source.fetch { _ in XCTAssertTrue(Thread.isMainThread); answers += 1 }
        XCTAssertTrue(wait { answers == 1 })
        primary.reply?(.success(limits))
        pump()
        XCTAssertEqual(answers, 1)
        cancel()
        let cancelQueued = source.fetch { _ in answers += 1 }
        cancelQueued()
        pump()
        XCTAssertEqual(answers, 1)
    }

    func testCLITransportUsesProductionParserAndRejectsNonzeroSuccessBody() throws {
        for (script, expected) in [
            ("print('{\"limits\":[{\"kind\":\"session\",\"percent\":17}]}')", Result<PlanLimits, LimitsFailure>.success(limits)),
            ("print('{\"limits\":[{\"kind\":\"session\",\"percent\":17}]}'); raise SystemExit(1)", .failure(.offline)),
            ("print('{}')", .failure(.unreadable))
        ] {
            let fixture = try Fixture(script)
            defer { fixture.remove() }
            XCTAssertEqual(read(ClaudeCLIUsageSource(command: { fixture.command })), expected)
        }
    }

    func testHelperFailuresRemainCategoricalWithoutLeakingResponse() throws {
        for (category, expected) in [("loginExpired", LimitsFailure.loginExpired), ("noLogin", .noLogin),
                                    ("refused", .refused(403)), ("noAnswer", .noAnswer),
                                    ("unreadable", .unreadable), ("private-secret", .offline)] {
            let fixture = try Fixture("print('{\"error\":\"\(category)\"}'); raise SystemExit(1)")
            defer { fixture.remove() }
            XCTAssertEqual(read(ClaudeCLIUsageSource(command: { fixture.command })), .failure(expected))
        }
    }

    func testCLITransportTimeoutAndOversizedOutputStopOwnedHelper() throws {
        for (script, expected) in [
            ("signal.signal(signal.SIGTERM, signal.SIG_IGN); mark_pid(); time.sleep(60)", LimitsFailure.noAnswer),
            ("mark_pid(); sys.stdout.write('x' * 40000); sys.stdout.flush(); time.sleep(60)", .unreadable)
        ] {
            let fixture = try Fixture(script)
            defer { fixture.remove() }
            let source = ClaudeCLIUsageSource(command: { fixture.command }, timeout: 0.3, terminationGrace: 0.1)
            XCTAssertEqual(read(source), .failure(expected))
            XCTAssertTrue(wait { fixture.isGone })
        }
    }

    func testCLITransportCancellationIsQuickAndSuppressesAnswer() throws {
        let fixture = try Fixture("signal.signal(signal.SIGTERM, signal.SIG_IGN); mark_pid(); time.sleep(60)")
        defer { fixture.remove() }
        let source = ClaudeCLIUsageSource(command: { fixture.command }, terminationGrace: 0.1)
        var answered = false
        let cancel = source.fetch { _ in answered = true }
        defer { cancel() }
        // A cold Python launch on CI is setup, not part of cancellation latency.
        // Only begin the strict timing checks once the owned child is ready.
        let ready = wait(timeout: 15) { fixture.pid != nil }
        XCTAssertTrue(ready, "Fixture Python process did not report readiness within 15 seconds")
        guard ready else { return }
        let before = ProcessInfo.processInfo.systemUptime
        cancel()
        XCTAssertTrue(ProcessInfo.processInfo.systemUptime - before < 0.1)
        XCTAssertTrue(wait { fixture.isGone })
        pump()
        XCTAssertFalse(answered)
    }

    private func read(_ source: PlanLimitsSource) -> Result<PlanLimits, LimitsFailure>? {
        var result: Result<PlanLimits, LimitsFailure>?
        let cancel = source.fetch { result = $0 }
        defer { cancel() }
        XCTAssertTrue(wait(timeout: ClaudeCLIUsageSource.timeout + 2) { result != nil })
        return result
    }

    private func wait(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }

    private func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

    private final class Stub: PlanLimitsSource {
        var result: Result<PlanLimits, LimitsFailure>?
        var sequence: [Result<PlanLimits, LimitsFailure>] = []
        var reply: ((Result<PlanLimits, LimitsFailure>) -> Void)?
        var calls = 0
        var cancels = 0
        init(_ result: Result<PlanLimits, LimitsFailure>?) { self.result = result }
        func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
            calls += 1
            reply = done
            let response = sequence.isEmpty ? result : sequence.removeFirst()
            if let response { done(response) }
            return { self.cancels += 1 }
        }
    }

    private struct Fixture {
        let directory: URL
        let script: URL
        let pidFile: URL
        init(_ body: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            script = directory.appendingPathComponent("fixture.py")
            pidFile = directory.appendingPathComponent("pid")
            let contents = "import os, signal, sys, time\ndef mark_pid():\n    open(\(pidFile.path.debugDescription), 'w').write(str(os.getpid()))\n" + body + "\n"
            try contents.write(to: script, atomically: true, encoding: .utf8)
        }
        var command: ClaudeCLIUsageSource.Command {
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
