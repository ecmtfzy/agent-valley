import XCTest
@testable import AgentValley

final class PhoneTextTests: XCTestCase {
    func testControlCharactersGoAndLinesStay() {
        XCTAssertEqual(PhoneText.clean("a\u{1B}[201~b\r\nc\rd\u{7}\u{2028}e"), "a[201~b\nc\nd\ne")
    }
    func testTabsBecomeSpaces() { XCTAssertEqual(PhoneText.clean("a\tb"), "a b") }
    func testBlankIsNothing() { XCTAssertNil(PhoneText.clean(" \n\t \u{1B}")) }
    func testEndsAreTrimmedInsideIsNot() { XCTAssertEqual(PhoneText.clean("  a  b \n"), "a  b") }
    func testThaiQuotesAndSlashCommandsPassUntouched() {
        for text in ["ตอบคำว่า \"ไทย-OK\" ด้วย it's fine", "/compact", "แก้บั๊ก 👍🏽 ที่ไฟล์ a.swift"] {
            XCTAssertEqual(PhoneText.clean(text), text)
        }
    }
    func testOnlyLinesAreWrappedAsAPasteAndNeverInGhostty() {
        XCTAssertEqual(PhoneText.typed("one", for: .iterm), "one")
        XCTAssertEqual(PhoneText.typed("one\ntwo", for: .iterm), "\u{1B}[200~one\ntwo\u{1B}[201~")
        XCTAssertEqual(PhoneText.typed("one\ntwo", for: .ghostty), "one\ntwo")
    }
    // Terminal's do script presses Return after the text on its own (found on the live run): a
    // backslash before it makes that Return a new line, so only the Enter step sends.
    func testTerminalsTextEndsInABackslash() {
        XCTAssertEqual(PhoneText.typed("one", for: .terminal), "one\\")
        XCTAssertEqual(PhoneText.typed("one\ntwo", for: .terminal), "\u{1B}[200~one\ntwo\u{1B}[201~\\")
        XCTAssertEqual(PhoneText.typed("C:\\", for: .terminal), "C:\\ \\")
    }
}
