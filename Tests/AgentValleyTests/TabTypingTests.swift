import XCTest
@testable import AgentValley

final class TabTypingTests: XCTestCase {
    func testTheTextIsAnArgumentAndNeverPartOfTheScript() {
        let args = TabTyping.arguments(.iterm, action: "text", key: "/dev/ttys004", text: "\" & do shell script \"x")
        XCTAssertEqual(Array(args.suffix(4)), ["--", "text", "/dev/ttys004", "\" & do shell script \"x"])
        XCTAssertFalse(args[1].contains("do shell script"))
    }
    func testEachTerminalIsToldInItsOwnWords() {
        XCTAssertTrue(TabTyping.script(.iterm).contains("newline NO"))
        XCTAssertTrue(TabTyping.script(.terminal).contains("do script \"\" in t"))   // its own Return is the Enter
        XCTAssertTrue(TabTyping.script(.ghostty).contains("send key \"enter\""))
    }
    // Inside `tell application "Ghostty"` the word tab is Ghostty's own tab class, which reads
    // back as the letters "tab": the probe joins with the character itself (found on the live run).
    func testGhosttysProbeJoinsWithARealTab() {
        XCTAssertTrue(TabTyping.script(.ghostty).contains("& (character id 9) &"))
        XCTAssertFalse(TabTyping.script(.ghostty).contains("& tab &"))
    }
    func testTextThenAPauseThenEnterEachAfterACheck() {
        var calls: [String] = []
        let result = TabTyping.send("one\ntwo", to: TabPlace(terminal: .iterm, key: "/dev/ttys004"), check: { calls.append("check"); return true },
                                    run: { calls.append($0[$0.count - 3]); return ScriptRun(status: 0, out: "ok", err: "", timedOut: false) },
                                    wait: { calls.append("wait \($0)") })
        XCTAssertEqual(result, .typed)
        XCTAssertEqual(calls, ["check", "text", "wait 0.5", "check", "enter"])
    }
    func testTheTextStepTypesTheTerminalsOwnForm() {
        var typed: [String] = []
        for terminal in [TabPlace.Terminal.terminal, .iterm] {
            _ = TabTyping.send("go", to: TabPlace(terminal: terminal, key: "/dev/ttys004"), check: { true },
                               run: { if $0[$0.count - 3] == "text" { typed.append($0[$0.count - 1]) }; return ScriptRun(status: 0, out: "ok", err: "", timedOut: false) },
                               wait: { _ in })
        }
        XCTAssertEqual(typed, ["go\\", "go"])
    }
    func testARequestBetweenTextAndEnterStopsTheEnter() {
        var checks = 0, actions: [String] = []
        let result = TabTyping.send("go", to: TabPlace(terminal: .terminal, key: "/dev/ttys004"), check: { checks += 1; return checks == 1 },
                                    run: { actions.append($0[$0.count - 3]); return ScriptRun(status: 0, out: "ok", err: "", timedOut: false) }, wait: { _ in })
        XCTAssertEqual(result, .stoppedBeforeEnter)
        XCTAssertEqual(actions, ["text"])
    }
    func testNothingIsTypedWhenTheFirstCheckFails() {
        var ran = false
        let result = TabTyping.send("go", to: TabPlace(terminal: .terminal, key: "/dev/ttys004"), check: { false },
                                    run: { _ in ran = true; return ScriptRun(status: 0, out: "ok", err: "", timedOut: false) }, wait: { _ in })
        XCTAssertEqual(result, .stoppedBeforeText)
        XCTAssertFalse(ran)
    }
    func testGhosttyTypesOnlyIntoOneTabThatClaudeNamed() {
        func run(_ probe: String) -> ([String]) -> ScriptRun { { $0[$0.count - 3] == "probe" ? ScriptRun(status: 0, out: probe, err: "", timedOut: false) : ScriptRun(status: 0, out: "ok", err: "", timedOut: false) } }
        let place = TabPlace(terminal: .ghostty, key: "/work")
        XCTAssertEqual(TabTyping.send("go", to: place, check: { true }, run: run("1\t✳ Fix login"), wait: { _ in }), .typed)
        XCTAssertEqual(TabTyping.send("go", to: place, check: { true }, run: run("2\t✳ Fix login"), wait: { _ in }), .ambiguous)
        XCTAssertEqual(TabTyping.send("go", to: place, check: { true }, run: run("1\t…/work"), wait: { _ in }), .stoppedBeforeText)
    }
    func testWhatTheScriptSaysBecomesAResult() {
        let place = TabPlace(terminal: .iterm, key: "/dev/ttys004")
        func result(_ run: ScriptRun) -> TypingResult { TabTyping.send("go", to: place, check: { true }, run: { _ in run }, wait: { _ in }) }
        XCTAssertEqual(result(ScriptRun(status: 0, out: "no tab", err: "", timedOut: false)), .tabNotFound)
        XCTAssertEqual(result(ScriptRun(status: 1, out: "", err: "execution error: Not authorized to send Apple events to iTerm. (-1743)", timedOut: false)), .notAllowed)
        XCTAssertEqual(result(ScriptRun(status: 0, out: "", err: "", timedOut: true)), .timedOut)
        XCTAssertEqual(result(ScriptRun(status: 1, out: "", err: "boom\nmore", timedOut: false)), .failed("boom"))
    }
    // A child left holding the pipes must not hold the send worker: the run ends soon after the program does.
    func testAChildHoldingThePipesDoesNotHoldTheRun() {
        let started = Date()
        let run = ScriptRun.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep 6 &"], timeout: 10)
        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(run.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }
    func testOsascriptReadsStdoutTrimmed() {
        let run = TabTyping.osascript(["-e", "return \"hi\""])
        XCTAssertEqual(run, ScriptRun(status: 0, out: "hi", err: "", timedOut: false))
    }
}
