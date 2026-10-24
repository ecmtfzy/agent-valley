import XCTest
@testable import AgentValley

/// Manual harness: the real Claude Code with the real plugin's Stop hook, against a desk, an
/// Away watch and a server of the test's own. Skipped unless LIVE_TERMINALS=1. The plugin is a
/// copy whose folder is the test's, so the app the person is running is never touched. Quit
/// AgentValley first all the same: a running copy keeps the test session in History.
final class StopHookLiveTests: XCTestCase {
    private let home = NSHomeDirectory()

    /// Runs the main queue (where the server answers) until `ok`, or the time is up.
    private func spin(_ seconds: Double, _ ok: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !ok() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        return ok()
    }

    func testAPhoneMessageCarriesTheTurnOnUntilTheMacIsTouched() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TERMINALS"] == "1")
        let root = URL(fileURLWithPath: NSTemporaryDirectory() + "av-stop-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        let app = root.appendingPathComponent("app"), work = root.appendingPathComponent("work"), plugin = root.appendingPathComponent("plugin")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let real = realpath(work.path, nil).map { path in defer { free(path) }; return String(cString: path) } ?? work.path
        let projects = home + "/.claude/projects/" + String(real.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(atPath: projects)
        }

        // The plugin as shipped, but pointing at this test's folder.
        let shipped = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin/notch-answers")
        try FileManager.default.copyItem(at: shipped, to: plugin)
        // Both hooks, each by its one line: without it the copy would talk to the person's own app.
        for (name, line, mine) in [("stop.sh", "DIR=\"$HOME/Library/Application Support/AgentValley\"", "DIR='\(app.path)'"),
                                   ("ask.sh", "SOCK=\"$HOME/Library/Application Support/AgentValley/answers.sock\"", "SOCK='\(app.path)/answers.sock'")] {
            let script = plugin.appendingPathComponent(name)
            let original = try String(contentsOf: script, encoding: .utf8)
            guard original.contains(line), original.components(separatedBy: "Application Support").count == 2 else {
                return XCTFail("\(name) no longer names its folder in one line")
            }
            try original.replacingOccurrences(of: line, with: mine).write(to: script, atomically: true, encoding: .utf8)
        }

        // As the app wires them, with a phone linked and a last touch the test moves.
        let desk = StopDesk()
        desk.holds = { _ in true }
        var touched = Date.distantPast
        let away = AwayWatch(desk: desk, folder: app, lastInput: { touched })
        away.phoneLinked = true
        away.start()
        let server = AnswerServer(directory: app, onAsk: { _, connection in connection.reply(nil) }, onStop: { stop, connection in
            let hook = desk.arrived(stop) { connection.reply($0) }
            connection.onClose = { [weak desk] in desk?.hookGone(hook) }
        })
        try server.start()
        defer { server.stop() }
        var statuses: [UUID: [SendStatus]] = [:]
        let session = UUID().uuidString.lowercased()
        let sender = SessionSender(
            reach: { _ in SessionReach(process: SessionProcess(pid: 0, startedAt: Date()), route: .stopHook, waitingOnPerson: false) },
            asking: { _ in false }, holdsTab: { _, _ in false },
            type: { _, _, _ in .failed("no tab here") }, superset: { _, _, _, _ in .failed("no Superset here") },
            desk: desk, away: { away.turnOn($0) }, worker: .main,
            onStatus: { id, _, status in statuses[id, default: []].append(status) })

        let claude = Process()
        claude.executableURL = URL(fileURLWithPath: home + "/.local/bin/claude")
        claude.arguments = ["-p", "Reply with exactly: FIRST-DONE", "--model", "haiku", "--session-id", session, "--plugin-dir", plugin.path]
        claude.currentDirectoryURL = work
        claude.environment = ["HOME": home, "USER": NSUserName(), "SHELL": "/bin/zsh", "LANG": "en_US.UTF-8", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let out = Pipe()
        claude.standardOutput = out
        claude.standardError = FileHandle.nullDevice
        try claude.run()
        defer { if claude.isRunning { claude.terminate() } }

        // 1. Sent while the first turn still runs: Away turns on, and the words wait for the turn's end.
        let second = UUID()
        sender.send(PhoneMessage(id: second, session: session, text: "Now reply with exactly: SECOND-DONE"))
        XCTAssertTrue(away.mode.on)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("away").path))
        XCTAssertEqual(statuses[second], [.received, .waitingForTurnEnd])
        XCTAssertTrue(spin(90) { statuses[second]?.last == .sent }, "the first turn's end never took the message")

        // 2. Sent while the second turn's end is held: it goes at once.
        let transcript = projects + "/\(session).jsonl"
        XCTAssertTrue(spin(90) { ((try? String(contentsOfFile: transcript, encoding: .utf8)) ?? "").contains("\"text\":\"SECOND-DONE\"") })
        _ = spin(3) { false }   // the second turn's hook reaches the desk
        let third = UUID()
        sender.send(PhoneMessage(id: third, session: session, text: "Now reply with exactly: THIRD-DONE"))
        XCTAssertTrue(spin(30) { statuses[third]?.last == .sent }, "a held turn end did not take the message")

        // 3. A touch on the Mac: Away goes, the held turn end is let go, and Claude finishes.
        XCTAssertTrue(spin(90) { ((try? String(contentsOfFile: transcript, encoding: .utf8)) ?? "").contains("\"text\":\"THIRD-DONE\"") })
        _ = spin(3) { false }
        XCTAssertTrue(claude.isRunning && away.mode.on, "the third turn's end was not held")
        touched = Date()
        XCTAssertTrue(spin(5) { !away.mode.on })
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("away").path))
        XCTAssertTrue(spin(30) { !claude.isRunning }, "Claude still waits after the Mac was touched")
        let printed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(printed.contains("THIRD-DONE"), printed)
    }
}
