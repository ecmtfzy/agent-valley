import XCTest
@testable import AgentValley

final class PricingTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_791_900_005)
    private let million = 1_000_000

    private func answer(_ model: String, input: Int = 0, write5m: Int = 0, write1h: Int = 0, read: Int = 0, output: Int = 0,
                        searches: Int = 0, fast: Bool = false, us: Bool = false) -> LedgerAnswer {
        LedgerAnswer(id: "m", at: at, model: model, fast: fast, us: us, input: input, write5m: write5m, write1h: write1h,
                     read: read, output: output, searches: searches)
    }

    private func cost(_ answer: LedgerAnswer, file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        try XCTUnwrap(Pricing.cost(of: answer), answer.model, file: file, line: line)
    }

    // MARK: - A line

    /// An answer's line as Claude Code wrote one on 2026-10-15, cut to what is read.
    private let real = #"{"type":"assistant","timestamp":"2026-10-13T14:00:05.000Z","cwd":"/Users/me/.superset/worktrees/shop-web/brave-otter","sessionId":"0b21c37f","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":1630,"cache_read_input_tokens":104656,"output_tokens":1291,"server_tool_use":{"web_search_requests":2,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":1630,"ephemeral_5m_input_tokens":0},"inference_geo":"global","speed":"standard"},"content":[]}}"#

    func testAnAnswersLineSaysWhatItUsedWhereAndByWhom() throws {
        let found = try XCTUnwrap(LedgerAnswer(line: Data(real.utf8), agent: "Explore"))
        XCTAssertEqual(found, LedgerAnswer(id: "msg_1", at: at, folder: "/Users/me/.superset/worktrees/shop-web/brave-otter",
                                           session: "0b21c37f", agent: "Explore", model: "claude-opus-5-5",
                                           input: 2, write1h: 1630, read: 104_656, output: 1291, searches: 2))
        XCTAssertEqual(found.tokens, 2 + 1630 + 104_656 + 1291)
        XCTAssertEqual(found.prompt, 2 + 1630 + 104_656)
        let fastInTheUS = real.replacingOccurrences(of: #""inference_geo":"global","speed":"standard""#, with: #""inference_geo":"us","speed":"fast""#)
        let other = try XCTUnwrap(LedgerAnswer(line: Data(fastInTheUS.utf8), agent: "main"))
        XCTAssertTrue(other.fast)
        XCTAssertTrue(other.us)
    }

    func testAnOlderLineWithOneCountForTheCacheIsTakenAsFiveMinutes() throws {
        let old = #"{"type":"assistant","timestamp":"2026-10-13T14:00:05.000Z","message":{"id":"m","model":"claude-opus-4-7","usage":{"input_tokens":3,"cache_creation_input_tokens":400,"cache_read_input_tokens":9000,"output_tokens":120}}}"#
        let found = try XCTUnwrap(LedgerAnswer(line: Data(old.utf8), agent: "main"))
        XCTAssertEqual([found.input, found.write5m, found.write1h, found.read, found.output], [3, 400, 0, 9000, 120])
        // A line with no folder and no session says none: the history names it later.
        XCTAssertEqual(found.folder, "")
        XCTAssertEqual(found.session, "")
    }

    func testOtherLinesSayNothing() {
        let lines = [
            #"{"type":"user","timestamp":"2026-10-13T14:00:05.000Z","message":{"id":"m","usage":{"input_tokens":5,"output_tokens":5}}}"#,
            #"{"type":"assistant","timestamp":"2026-10-13T14:00:05.000Z","message":{"usage":{"input_tokens":5,"output_tokens":5}}}"#,
            #"{"type":"assistant","message":{"id":"m","usage":{"input_tokens":5,"output_tokens":5}}}"#,
            #"{"type":"assistant","timestamp":"yesterday","message":{"id":"m","usage":{"input_tokens":5,"output_tokens":5}}}"#,
            // What Claude Code writes itself, as "<synthetic>": nothing used.
            #"{"type":"assistant","timestamp":"2026-10-13T14:00:05.000Z","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}"#,
            #"{"type":"assistant","timestamp":"2026-10-13T14:00:05.000Z","message":{"id":"m","usage":"none"}}"#,
            #"{"type":"assistant","usage":"#,
            "",
        ]
        for text in lines { XCTAssertNil(LedgerAnswer(line: Data(text.utf8), agent: "main"), text) }
        // A count below nothing is a count of nothing.
        let negative = #"{"type":"assistant","timestamp":"2026-10-13T14:00:05.000Z","message":{"id":"m","usage":{"input_tokens":-5,"output_tokens":7}}}"#
        XCTAssertEqual(LedgerAnswer(line: Data(negative.utf8), agent: "main")?.input, 0)
    }

    // MARK: - Its price

    func testEachKindOfTokenAtItsOwnPrice() throws {
        // Opus 5.5 on the pricing page, 2026-10-15: $4 in, $5 and $8 written to the cache for
        // five minutes and for an hour, $0.20 read back, $20 out.
        XCTAssertEqual(try cost(answer("claude-opus-5-5", input: million)), 4, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-5-5", write5m: million)), 5, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-5-5", write1h: million)), 8, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-5-5", read: million)), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-5-5", output: million)), 20, accuracy: 1e-9)
        // The real answer above.
        XCTAssertEqual(try cost(answer("claude-opus-5-5", input: 2, write1h: 1630, read: 104_656, output: 1291)),
                       (2 * 4 + 1630 * 8 + 104_656 * 0.2 + 1291 * 20) / 1e6, accuracy: 1e-12)
    }

    func testEveryModelInTheTable() throws {
        // $ per million out, and read back from the cache, which differs most from model to model.
        let table: [(String, Double, Double)] = [
            ("claude-fable-5-1", 50, 0.25), ("claude-fable-5", 50, 1), ("claude-opus-5-5", 20, 0.2), ("claude-opus-5", 25, 0.5),
            ("claude-opus-4-8", 25, 0.5), ("claude-opus-4-7", 25, 0.5), ("claude-opus-4-6", 25, 0.5), ("claude-opus-4-5", 25, 0.5),
            ("claude-opus-4-1", 75, 1.5), ("claude-opus-4", 75, 1.5), ("claude-sonnet-5-5", 10, 0.1), ("claude-sonnet-5", 10, 0.2),
            ("claude-sonnet-4-6", 15, 0.3), ("claude-sonnet-4-5", 15, 0.3), ("claude-sonnet-4", 15, 0.3),
            ("claude-haiku-5-5", 0.5, 0.01), ("claude-haiku-4-5", 5, 0.1),
        ]
        for (model, output, read) in table {
            XCTAssertEqual(try cost(answer(model, output: million)), output, accuracy: 1e-9, model)
            // A tenth of a million read: no prompt passes Haiku 5.5's step.
            XCTAssertEqual(try cost(answer(model, read: million / 10)), read / 10, accuracy: 1e-12, model)
        }
    }

    func testADatedIdIsItsModelAndANewerModelHasNoPrice() throws {
        XCTAssertEqual(try cost(answer("claude-haiku-4-5-20251001", output: million)), 5, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-4-20250514", output: million)), 75, accuracy: 1e-9)
        // Not taken for a model whose name it starts with: no price is guessed.
        for model in ["claude-opus-5-7", "claude-opus-4-8-fast", "claude-sonnet-6", "<synthetic>", "", "gpt-5"] {
            XCTAssertNil(Pricing.cost(of: answer(model, output: million)), model)
        }
    }

    func testHaikuFivePointFiveCostsMoreOverAHundredThousandTokensIn() throws {
        // The prompt counts what was read from and written to the cache too: 100,000 is not over.
        XCTAssertEqual(try cost(answer("claude-haiku-5-5", input: 50_000, read: 50_000, output: million)),
                       (50_000 * 0.1 + 50_000 * 0.01) / 1e6 + 0.5, accuracy: 1e-12)
        XCTAssertEqual(try cost(answer("claude-haiku-5-5", input: 50_000, write5m: 1, read: 50_000, output: million)),
                       (50_000 * 0.5 + 1 * 0.625 + 50_000 * 0.05) / 1e6 + 2.5, accuracy: 1e-12)
    }

    func testFastModeAndUSOnly() throws {
        XCTAssertEqual(try cost(answer("claude-opus-5-5", output: million, fast: true)), 40, accuracy: 1e-9)
        // The cache's prices go up with it.
        XCTAssertEqual(try cost(answer("claude-opus-5-5", read: million, fast: true)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-5", output: million, fast: true)), 50, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-4-8", output: million, fast: true)), 50, accuracy: 1e-9)
        // Opus 4.6 asked for fast runs at standard speed, and is billed so.
        XCTAssertEqual(try cost(answer("claude-opus-4-6", output: million, fast: true)), 25, accuracy: 1e-9)
        // Fast where fast has no price: not guessed.
        XCTAssertNil(Pricing.cost(of: answer("claude-sonnet-5-5", output: million, fast: true)))
        XCTAssertEqual(try cost(answer("claude-opus-5-5", output: million, us: true)), 22, accuracy: 1e-9)
        XCTAssertEqual(try cost(answer("claude-opus-5-5", output: million, fast: true, us: true)), 44, accuracy: 1e-9)
    }

    func testWebSearchesAtTenDollarsAThousand() throws {
        XCTAssertEqual(try cost(answer("claude-opus-5-5", searches: 3)), 0.03, accuracy: 1e-12)
        // A search is priced on its own: fast mode and US-only do not raise it.
        XCTAssertEqual(try cost(answer("claude-opus-5-5", searches: 3, fast: true, us: true)), 0.03, accuracy: 1e-12)
    }
}
