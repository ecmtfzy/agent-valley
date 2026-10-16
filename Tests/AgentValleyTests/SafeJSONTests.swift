import XCTest
@testable import AgentValley

final class SafeJSONTests: XCTestCase {
    private func objects(_ depth: Int) -> String {
        String(repeating: #"{"a":"#, count: depth) + "1" + String(repeating: "}", count: depth)
    }

    private func arrays(_ depth: Int) -> String {
        String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    }

    private func parsed(_ text: String) -> Bool { SafeJSON.object(Data(text.utf8)) != nil }

    /// Runs `body` on a thread with the stack of a dispatch worker: where the app reads
    /// transcripts, and where Foundation's parser overruns its stack before its own limit.
    private func onASmallStack(_ body: @escaping () -> Void) {
        let ran = expectation(description: "ran")
        let thread = Thread {
            body()
            ran.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [ran], timeout: 60)
    }

    func testTextNestedPastTheLimitIsNotParsed() {
        XCTAssertTrue(parsed(#"{"a":[1,{"b":"c"}]}"#))
        XCTAssertTrue(parsed(objects(SafeJSON.maxDepth)))
        XCTAssertFalse(parsed(objects(SafeJSON.maxDepth + 1)))
        XCTAssertTrue(parsed(#"{"a":"# + arrays(SafeJSON.maxDepth - 1) + "}"))
        XCTAssertFalse(parsed(#"{"a":"# + arrays(SafeJSON.maxDepth) + "}"))
        // Wide is not deep.
        XCTAssertTrue(parsed(#"{"a":["# + Array(repeating: "[[1]]", count: 1000).joined(separator: ",") + "]}"))
        // Not an object, and not JSON: turned away as before.
        XCTAssertFalse(parsed("[1,2]"))
        XCTAssertFalse(parsed("oops"))
        XCTAssertFalse(parsed(""))
    }

    // A file's contents or a shell command, as a tool's input carries them, are full of brackets.
    func testBracketsInsideAStringAreNotCounted() {
        let brackets = String(repeating: "[{", count: 500)
        XCTAssertTrue(parsed(#"{"a":"\#(brackets)"}"#))
        // An escaped quote does not end the string, and an escaped backslash does not escape the quote after it.
        XCTAssertTrue(parsed(#"{"a":"\"\#(brackets)"}"#))
        XCTAssertFalse(parsed(#"{"a":"\\","b":\#(arrays(SafeJSON.maxDepth))}"#))
        XCTAssertTrue(SafeJSON.nests(Data(#""\\" [[ "\"" ]]"#.utf8), atMost: 2))
        XCTAssertFalse(SafeJSON.nests(Data(#""\\" [[[ "\"" ]]]"#.utf8), atMost: 2))
    }

    // The parser reads UTF-16 as well. There a quote's byte can be half of another character,
    // which would hide every bracket after it from the count.
    func testTextThatIsNotUTF8IsNotParsed() {
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: #"{"a":1}"#.data(using: .utf16LittleEndian)!))
        XCTAssertNil(SafeJSON.object(#"{"a":1}"#.data(using: .utf16LittleEndian)!))
        XCTAssertNil(SafeJSON.object(#"{"a":1}"#.data(using: .utf16)!))
        XCTAssertNil(SafeJSON.object(#"{"a":1}"#.data(using: .utf32)!))
        // U+2200 holds the byte of a quote.
        let hidden = (#"{"∀":"# + objects(600) + "}").data(using: .utf16LittleEndian)!
        XCTAssertNil(SafeJSON.object(hidden))
        XCTAssertNotNil(SafeJSON.object(Data(#"{"a":"∀ é 中"}"#.utf8)))
    }

    // A transcript line whose tool input nested 4,000 deep shut the app at every launch, for as
    // long as the file was there.
    func testEveryReaderOfOutsideTextTurnsDeepNestingAway() {
        for depth in [500, 4_000, 100_000] {
            let deep = objects(depth)
            let line = Data((#"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","message":{"id":"m1","usage":{"input_tokens":5},"content":[{"type":"tool_use","name":"Read","input":"# + deep + "}]}}").utf8)
            let hook = Data((#"{"tool_name":"Bash","transcript_path":"/r/p/s1.jsonl","tool_input":"# + deep + "}").utf8)
            let record = Data((#"{"pid":1,"sessionId":"s1","startedAt":1,"status":"busy","extra":"# + deep + "}").utf8)
            let keychain = Data((#"{"claudeAiOauth":{"accessToken":"t","extra":"# + deep + "}}").utf8)
            let reply = Data((#"{"limits":[{"kind":"session","percent":5,"extra":"# + deep + "}]}").utf8)
            var info = AgentInfo()
            var metaRead = true
            var results: [Bool] = []
            onASmallStack {
                TranscriptReader.apply(line: line, to: &info)
                metaRead = TranscriptReader.applyMeta(Data((#"{"agentType":"Explore","extra":"# + deep + "}").utf8), to: &info)
                results = [
                    LedgerAnswer(line: line, agent: "main") == nil,
                    SessionRecords.parse(record) == nil,
                    Ask(hookInput: hook) == nil,
                    PlanLimitsReader.login(fromKeychainItem: keychain, now: Date(timeIntervalSince1970: 0)) == .failure(.noLogin),
                    PlanLimitsReader.parse(reply) == nil,
                ]
            }
            XCTAssertEqual(info, AgentInfo(), "\(depth)")
            XCTAssertFalse(metaRead, "\(depth)")
            XCTAssertEqual(results, [true, true, true, true, true], "\(depth)")
        }
    }

    // The same texts, shallow, are read: the test above turns nothing away for another reason.
    func testTheSameTextsAreReadWhenShallow() {
        let shallow = objects(20)
        let line = Data((#"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","message":{"id":"m1","usage":{"input_tokens":5},"content":[{"type":"tool_use","name":"Read","input":"# + shallow + "}]}}").utf8)
        var info = AgentInfo()
        TranscriptReader.apply(line: line, to: &info)
        XCTAssertNotEqual(info, AgentInfo())
        XCTAssertTrue(TranscriptReader.applyMeta(Data((#"{"agentType":"Explore","extra":"# + shallow + "}").utf8), to: &info))
        XCTAssertNotNil(LedgerAnswer(line: line, agent: "main"))
        XCTAssertNotNil(SessionRecords.parse(Data((#"{"pid":1,"sessionId":"s1","startedAt":1,"status":"busy","extra":"# + shallow + "}").utf8)))
        XCTAssertNotNil(Ask(hookInput: Data((#"{"tool_name":"Bash","transcript_path":"/r/p/s1.jsonl","tool_input":"# + shallow + "}").utf8)))
        XCTAssertEqual(PlanLimitsReader.login(fromKeychainItem: Data((#"{"claudeAiOauth":{"accessToken":"t","extra":"# + shallow + "}}").utf8),
                                              now: Date(timeIntervalSince1970: 0)), .success("t"))
        XCTAssertNotNil(PlanLimitsReader.parse(Data((#"{"limits":[{"kind":"session","percent":5,"extra":"# + shallow + "}]}").utf8)))
    }
}
