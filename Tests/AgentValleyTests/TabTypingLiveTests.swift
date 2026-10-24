import XCTest
import AppKit
@testable import AgentValley

/// Manual harness: opens real windows and runs the real Claude Code in them. Skipped unless
/// LIVE_TERMINALS=1, and meant for a Mac nobody is using. Quit AgentValley first: a running copy
/// keeps the test sessions in History and gives their folders crew faces for good.
final class TabTypingLiveTests: XCTestCase {
    private let home = NSHomeDirectory()

    func testTerminal() throws { try drive(.terminal, app: "Terminal", bundle: "com.apple.Terminal") }
    func testSuperset() throws { try driveSuperset() }
    func testITerm() throws { try drive(.iterm, app: "iTerm2", bundle: "com.googlecode.iterm2") }
    func testGhostty() throws { try drive(.ghostty, app: "Ghostty", bundle: "com.mitchellh.ghostty") }

    // MARK: setup

    /// Opens a window, starts a clean Claude Code in it, and returns the tab's key.
    private func open(_ terminal: TabPlace.Terminal, dir: String, launch: String) throws -> String {
        let script: String
        switch terminal {
        case .terminal:
            script = "on run argv\ntell application \"Terminal\"\nset t to do script (item 2 of argv)\nreturn tty of t\nend tell\nend run"
        case .iterm:
            script = "on run argv\ntell application id \"com.googlecode.iterm2\"\nset w to (create window with default profile)\ntell current session of w to write text (item 2 of argv)\nreturn tty of current session of w\nend tell\nend run"
        case .ghostty:
            script = "on run argv\ntell application \"Ghostty\"\nset cfg to new surface configuration\nset initial working directory of cfg to (item 1 of argv)\nset win to new window with configuration cfg\nset t to terminal 1 of selected tab of win\ndelay 1\ninput text (item 2 of argv) to t\nsend key \"enter\" to t\nreturn item 1 of argv\nend tell\nend run"
        }
        let run = TabTyping.osascript(["-e", script, "--", dir, launch])
        XCTAssertEqual(run.status, 0, run.err)
        return run.out
    }

    private func records(in dir: String) -> [(pid: Int32, id: String, status: String)] {
        let folder = home + "/.claude/sessions"
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).compactMap { name in
            guard SessionRecords.isRecordName(name), let data = FileManager.default.contents(atPath: folder + "/" + name),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (o["cwd"] as? String).map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == dir,
                  let pid = (o["pid"] as? NSNumber)?.int32Value, let id = o["sessionId"] as? String else { return nil }
            return (pid, id, o["status"] as? String ?? "")
        }
    }

    private func until(_ seconds: Double, _ ok: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if ok() { return true }; Thread.sleep(forTimeInterval: 0.5) }
        return ok()
    }

    /// Claude Code names a project's folder after the real path: /var/folders is /private/var/folders
    /// to it, while URL.resolvingSymlinksInPath drops the /private.
    private func projectFolder(_ dir: String) -> String {
        let real = realpath(dir, nil).map { defer { free($0) }; return String(cString: $0) } ?? dir
        return home + "/.claude/projects/" + String(real.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// A message as the transcript holds it, whole, so a stray backslash or line at its end shows.
    private func whole(_ text: String) -> String {
        ":\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private func transcript(_ dir: String) -> String {
        let folder = projectFolder(dir)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".jsonl") }
            .compactMap { try? String(contentsOfFile: folder + "/" + $0, encoding: .utf8) }.joined()
    }

    /// The real binary, not the wrapper in ~/.superset/bin; a clean environment so it saves transcripts;
    /// the shell goes with Claude, so no window is left behind.
    private func launch(in dir: String) -> String {
        let env = ProcessInfo.processInfo.environment
        return "cd '\(dir)' && env -i HOME='\(home)' USER='\(NSUserName())' SHELL='/bin/zsh' LANG='en_US.UTF-8' PATH='/usr/bin:/bin:/usr/sbin:/sbin' TERM='\(env["TERM"] ?? "xterm-256color")' TERM_PROGRAM='\(env["TERM_PROGRAM"] ?? "")' '\(home)/.local/bin/claude' --model haiku --allowedTools 'Bash(sleep:*)'; exit"
    }

    // MARK: the run

    private func drive(_ terminal: TabPlace.Terminal, app: String, bundle: String) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TERMINALS"] == "1")
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "av-live-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let projects = projectFolder(dir)   // while the folder exists: realpath needs it
        let launch = launch(in: dir)
        // An app opened by its first Apple event is not ready for a new window yet.
        if !wasRunning {
            _ = ScriptRun.run(URL(fileURLWithPath: "/usr/bin/open"), ["-g", "-b", bundle], timeout: 15)
            _ = until(20) { !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty }
            Thread.sleep(forTimeInterval: 3)
        }
        let key = try open(terminal, dir: dir, launch: launch)
        let place = TabPlace(terminal: terminal, key: key)
        defer {
            // Whatever way this ends, no Claude is left running in the tab.
            if let pid = records(in: dir).first?.pid { kill(pid, SIGTERM) }
            try? FileManager.default.removeItem(atPath: dir)
            try? FileManager.default.removeItem(atPath: projects)
            // Windows first: iTerm2 asks before it quits with a session open, and the question stays on screen.
            if !wasRunning { _ = TabTyping.osascript(["-e", "tell application id \"\(bundle)\"\ntry\nclose every window\nend try\nquit\nend tell"]) }
        }

        guard until(90, { records(in: dir).first?.status == "idle" }) else { return XCTFail("Claude never came up idle") }
        // Built as the app's store builds a session's reach: the kernel's start time, from the
        // store's own default `processStart` (AgentStore.startTime), never the record's later one.
        guard let record = records(in: dir).first, let started = AgentStore.startTime(ofProcess: record.pid) else { return XCTFail("no Claude process") }
        let process = SessionProcess(pid: record.pid, startedAt: started)
        let check = { TabGuard.claudeHoldsTab(AgentStore.facts(ofProcess: process.pid), process: process, place: place) }
        func send(_ text: String) -> TypingResult {
            TabTyping.send(PhoneText.clean(text) ?? "", to: place, check: check, run: TabTyping.osascript, wait: { Thread.sleep(forTimeInterval: $0) })
        }
        func idle() -> Bool { until(90) { records(in: dir).first?.status == "idle" } }

        // 1. idle
        XCTAssertEqual(send("Reply with exactly: PONG-ONE"), .typed)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("Reply with exactly: PONG-ONE")) }); XCTAssertTrue(idle())
        // 1b. the text step alone sends nothing: only Enter does
        func step(_ action: String, _ text: String = "") -> String {
            TabTyping.osascript(TabTyping.arguments(terminal, action: action, key: key, text: text)).out
        }
        XCTAssertEqual(step("text", PhoneText.typed("STAGED-ONLY", for: terminal)), "ok")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(transcript(dir).contains("STAGED-ONLY"), "the text step sent on its own")
        XCTAssertEqual(step("enter"), "ok")
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("STAGED-ONLY")) }); XCTAssertTrue(idle())
        // 2. while a sleep runs; the guard holds the whole time
        XCTAssertEqual(send("Run bash `sleep 15`, then say DONE-TWO"), .typed)
        XCTAssertTrue(until(30) { records(in: dir).first?.status == "busy" })
        XCTAssertTrue(check(), "guard must pass while sleep runs")
        XCTAssertEqual(send("midway note KAPPA"), .typed)
        XCTAssertTrue(until(90) { transcript(dir).contains(whole("midway note KAPPA")) }); XCTAssertTrue(idle())
        // 3. Thai and quotes
        XCTAssertEqual(send("สวัสดี \"ครับ\" 'ok' แล้วตอบว่า THAI-OK"), .typed)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("สวัสดี \"ครับ\" 'ok' แล้วตอบว่า THAI-OK")) }); XCTAssertTrue(idle())
        // 4. two lines, one message
        XCTAssertEqual(send("LINE-A\nLINE-B"), .typed)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("LINE-A\nLINE-B")) }); XCTAssertTrue(idle())
        // 5. /exit waits for Enter too; after it nothing is typed
        XCTAssertEqual(step("text", PhoneText.typed("/exit", for: terminal)), "ok")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotNil(AgentStore.facts(ofProcess: process.pid), "/exit ran from the text step alone")
        XCTAssertEqual(step("enter"), "ok")
        XCTAssertTrue(until(30) { AgentStore.facts(ofProcess: process.pid) == nil })
        XCTAssertEqual(send("should not land"), .stoppedBeforeText)
    }

    /// A new terminal in the workspace this runs from (never this session's own), closed at the end.
    private func driveSuperset() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TERMINALS"] == "1")
        let binary = SupersetSend.binary(home: URL(fileURLWithPath: home))
        guard let workspace = ProcessInfo.processInfo.environment["SUPERSET_WORKSPACE_ID"],
              FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("not inside a Superset workspace") }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "av-live-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let projects = projectFolder(dir)
        let made = ScriptRun.run(binary, ["terminals", "create", "--local", "--workspace", workspace, "--cwd", dir, "--command", launch(in: dir), "--json"], timeout: 30)
        let terminal = (try? JSONSerialization.jsonObject(with: Data(made.out.utf8)) as? [String: Any])?["terminalId"] as? String ?? ""
        defer {
            if let pid = records(in: dir).first?.pid { kill(pid, SIGTERM) }
            if !terminal.isEmpty { _ = ScriptRun.run(binary, ["terminals", "close", "--local", "--workspace", workspace, "--terminal", terminal], timeout: 15) }
            try? FileManager.default.removeItem(atPath: dir)
            try? FileManager.default.removeItem(atPath: projects)
        }
        guard made.status == 0, OwnerApp.isID(terminal) else { return XCTFail("no terminal: \(made.err) \(made.out)") }

        guard until(90, { records(in: dir).first?.status == "idle" }) else { return XCTFail("Claude never came up idle") }
        guard let record = records(in: dir).first, let started = AgentStore.startTime(ofProcess: record.pid) else { return XCTFail("no Claude process") }
        let process = SessionProcess(pid: record.pid, startedAt: started)
        let check = { TabGuard.claudeInFront(AgentStore.facts(ofProcess: process.pid), process: process) }
        func send(_ text: String) -> TypingResult {
            SupersetSend.send(workspace: workspace, terminal: terminal, text: PhoneText.clean(text) ?? "", check: check,
                              run: SupersetSend.run(binary), wait: { Thread.sleep(forTimeInterval: $0) })
        }
        func idle() -> Bool { until(90) { records(in: dir).first?.status == "idle" } }

        XCTAssertEqual(send("Reply with exactly: PONG-ONE"), .typed)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("Reply with exactly: PONG-ONE")) }); XCTAssertTrue(idle())
        // The text step alone sends nothing: only Enter does.
        XCTAssertEqual(SupersetSend.run(binary)(SupersetSend.arguments(workspace: workspace, terminal: terminal, text: "STAGED-ONLY")).status, 0)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(transcript(dir).contains("STAGED-ONLY"), "the text step sent on its own")
        XCTAssertEqual(SupersetSend.run(binary)(SupersetSend.enterArguments(workspace: workspace, terminal: terminal)).status, 0)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("STAGED-ONLY")) }); XCTAssertTrue(idle())
        XCTAssertEqual(send("สวัสดี \"ครับ\" 'ok' แล้วตอบว่า THAI-OK"), .typed)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("สวัสดี \"ครับ\" 'ok' แล้วตอบว่า THAI-OK")) }); XCTAssertTrue(idle())
        XCTAssertEqual(send("LINE-A\nLINE-B"), .typed)
        XCTAssertTrue(until(60) { transcript(dir).contains(whole("LINE-A\nLINE-B")) }); XCTAssertTrue(idle())
        XCTAssertEqual(SupersetSend.run(binary)(SupersetSend.arguments(workspace: workspace, terminal: terminal, text: "/exit")).status, 0)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotNil(AgentStore.facts(ofProcess: process.pid), "/exit ran from the text step alone")
        XCTAssertEqual(SupersetSend.run(binary)(SupersetSend.enterArguments(workspace: workspace, terminal: terminal)).status, 0)
        XCTAssertTrue(until(30) { AgentStore.facts(ofProcess: process.pid) == nil })
        XCTAssertEqual(send("should not land"), .stoppedBeforeText)
    }
}
