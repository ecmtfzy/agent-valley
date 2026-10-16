import AppKit
import XCTest
@testable import AgentValley

final class TabPlaceTests: XCTestCase {
    private let terminals: [TabPlace.Terminal] = [.terminal, .iterm, .ghostty]

    func testOnlyThreeTerminalsCanBeAskedForATab() {
        XCTAssertEqual(TabPlace.terminal(bundleID: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(TabPlace.terminal(bundleID: "com.googlecode.iterm2"), .iterm)
        XCTAssertEqual(TabPlace.terminal(bundleID: "com.mitchellh.ghostty"), .ghostty)
        XCTAssertNil(TabPlace.terminal(bundleID: "com.superset.desktop"))
        XCTAssertNil(TabPlace.terminal(bundleID: "com.apple.Terminal.other"))
        XCTAssertNil(TabPlace.terminal(bundleID: nil))
    }

    func testATTYIsTakenOnlyInTheSystemsOwnShape() {
        XCTAssertTrue(TabPlace.isTTY("/dev/ttys0"))
        XCTAssertTrue(TabPlace.isTTY("/dev/ttys012"))
        // A mark that rides on a digit makes one character of the two: still not a digit.
        let marked = "/dev/ttys1" + String(repeating: "\u{0301}", count: 40)
        for bad in ["", "/dev/ttys", "/dev/console", "ttys012", "/dev/ttys012\"", "/dev/ttys01\n2", "/dev/ttys1234567", "/dev/ttys\u{0663}", "/dev/ttys012 & quit", "/dev/ttys1\u{0301}", marked] {
            XCTAssertFalse(TabPlace.isTTY(bad), bad)
        }
    }

    func testATabIsFoundByTTYInTerminalAndITermAndByFolderInGhostty() {
        XCTAssertEqual(TabPlace.place(bundleID: "com.apple.Terminal", tty: { "/dev/ttys012" }, folder: { "/work" }),
                       TabPlace(terminal: .terminal, key: "/dev/ttys012"))
        XCTAssertEqual(TabPlace.place(bundleID: "com.googlecode.iterm2", tty: { "/dev/ttys3" }, folder: { nil }),
                       TabPlace(terminal: .iterm, key: "/dev/ttys3"))
        XCTAssertEqual(TabPlace.place(bundleID: "com.mitchellh.ghostty", tty: { nil }, folder: { "/work/app" }),
                       TabPlace(terminal: .ghostty, key: "/work/app"))
    }

    func testNoTabWithoutWhatFindsIt() {
        XCTAssertNil(TabPlace.place(bundleID: "com.apple.Terminal", tty: { nil }, folder: { "/work" }))
        XCTAssertNil(TabPlace.place(bundleID: "com.apple.Terminal", tty: { "/dev/console" }, folder: { "/work" }))
        XCTAssertNil(TabPlace.place(bundleID: "com.mitchellh.ghostty", tty: { "/dev/ttys1" }, folder: { nil }))
        XCTAssertNil(TabPlace.place(bundleID: "com.mitchellh.ghostty", tty: { "/dev/ttys1" }, folder: { "" }))
        // Not a whole path: it could be read as an option of the command that runs the script.
        XCTAssertNil(TabPlace.place(bundleID: "com.mitchellh.ghostty", tty: { nil }, folder: { "-e" }))
    }

    // An app that is not asked is not read for: nothing of its process is looked at.
    func testNothingIsReadForAnAppThatCannotBeAsked() {
        var reads = 0
        XCTAssertNil(TabPlace.place(bundleID: "com.superset.desktop", tty: { reads += 1; return "/dev/ttys1" }, folder: { reads += 1; return "/work" }))
        XCTAssertEqual(reads, 0)
        // And of a terminal's, only what that terminal is asked by.
        _ = TabPlace.place(bundleID: "com.apple.Terminal", tty: { "/dev/ttys1" }, folder: { reads += 1; return "/work" })
        XCTAssertEqual(reads, 0)
    }

    // What comes out of another process is handed over beside the script, never written into it.
    func testTheValueIsTheScriptsArgumentAndNeverPartOfIt() {
        let hostile = "/work/\" & (do shell script \"id\") & \""
        let place = TabPlace(terminal: .ghostty, key: hostile)
        // After a divider: nothing that follows it is read as an option, whatever it begins with.
        XCTAssertEqual(place.arguments, ["-e", TabPlace(terminal: .ghostty, key: "/x").script, "--", hostile])
        for terminal in terminals {
            let script = TabPlace(terminal: terminal, key: "/dev/ttys1").script
            XCTAssertTrue(script.contains("item 1 of argv"), "\(terminal)")
            XCTAssertFalse(script.contains("/dev/ttys1"), "\(terminal)")
        }
    }

    // The scripts select a tab and do nothing else: no typing, no reading, no closing.
    func testTheScriptsOnlySelect() {
        for terminal in terminals {
            let script = TabPlace(terminal: terminal, key: "/x").script
            for word in ["do script", "do shell script", "write text", "input text", "send key", "close", "contents", "history", "keystroke", "quit", "delete"] {
                XCTAssertFalse(script.contains(word), "\(terminal): \(word)")
            }
        }
    }

    /// Compiles a script against the app's own dictionary, without running it or opening the app.
    /// Skipped where the app is not installed: AppleScript would ask the person where it is.
    private func compiles(_ terminal: TabPlace.Terminal, bundleID: String) throws {
        try XCTSkipIf(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil, "\(bundleID) is not on this Mac")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".scpt")
        defer { try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", out.path, "-e", TabPlace(terminal: terminal, key: "/x").script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, said)
    }

    func testTheTerminalScriptCompilesAgainstTerminal() throws { try compiles(.terminal, bundleID: "com.apple.Terminal") }
    func testTheITermScriptCompilesAgainstITerm() throws { try compiles(.iterm, bundleID: "com.googlecode.iterm2") }
    func testTheGhosttyScriptCompilesAgainstGhostty() throws { try compiles(.ghostty, bundleID: "com.mitchellh.ghostty") }

    func testAProcessTellsItsTTYIfItHasOne() {
        // A test run may have no terminal at all; with one, it is named as the system names it.
        if let tty = AgentStore.tty(ofProcess: getpid()) { XCTAssertTrue(TabPlace.isTTY(tty), tty) }
        XCTAssertNil(AgentStore.tty(ofProcess: 99_999_999))
    }

    // Claude Code moves itself into a worktree, and a path can run through a link. Ghostty
    // still names the folder the session was started in, as the shell told it: so does this.
    func testGhosttyIsAskedByTheFolderTheSessionWasStartedIn() throws {
        try XCTSkipIf(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") == nil, "Ghostty is not on this Mac")
        let ghostty = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty").map { OwnerApp(bundle: $0, name: "Ghostty") } ?? nil, "Ghostty is not on this Mac")
        let started = try XCTUnwrap(ProcessInfo.processInfo.environment["PWD"])
        let here = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(here) }
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath("/usr"))
        XCTAssertEqual(AgentStore.tabPlace(ofProcess: getpid(), in: ghostty), TabPlace(terminal: .ghostty, key: started))
    }

    // A command that brings a window forward changes which one is "window 2". Whatever is
    // still to be done to the tab is done first, and a window that has to be moved twice is
    // named by its id.
    func testNoWindowIsAskedForByItsPlaceOnceTheWindowsHaveMoved() throws {
        let iterm = TabPlace(terminal: .iterm, key: "/dev/ttys1").script
        let session = try XCTUnwrap(iterm.range(of: "select s")).lowerBound
        let tab = try XCTUnwrap(iterm.range(of: "select t")).lowerBound
        let window = try XCTUnwrap(iterm.range(of: "select w")).lowerBound
        XCTAssertLessThan(session, tab)
        XCTAssertLessThan(tab, window)

        let terminal = TabPlace(terminal: .terminal, key: "/dev/ttys1").script
        let named = try XCTUnwrap(terminal.range(of: "set theID to id of w")).lowerBound
        let chosen = try XCTUnwrap(terminal.range(of: "set selected tab of w to t")).lowerBound
        let restored = try XCTUnwrap(terminal.range(of: "set miniaturized of window id theID to false")).lowerBound
        let raised = try XCTUnwrap(terminal.range(of: "set index of window id theID to 1")).lowerBound
        XCTAssertLessThan(named, chosen)
        XCTAssertLessThan(chosen, restored)
        XCTAssertLessThan(restored, raised)
        XCTAssertFalse(terminal.contains("of w to false"))
        XCTAssertFalse(terminal.contains("set index of w to"))
    }

    // A known app with no tab known is what every app was before: equal to one made without it.
    func testAnAppCarriesNoTabUnlessGivenOne() {
        let app = OwnerApp(bundle: URL(fileURLWithPath: "/Applications/Ghostty.app"), name: "Ghostty")
        XCTAssertNil(app.tab)
        var there = app
        there.tab = TabPlace(terminal: .ghostty, key: "/work")
        XCTAssertNotEqual(app, there)
    }
}
