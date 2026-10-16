import XCTest
@testable import AgentValley

final class SQLiteTests: XCTestCase {
    private func path() -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-sqlite-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("test.sqlite").path
    }

    func testValuesGoInAndComeBackOut() throws {
        let file = path()
        let db = try SQLite(path: file)
        try db.execute("CREATE TABLE t (a INTEGER, b REAL, c TEXT, d TEXT)")
        // The same statement twice: it is kept, and its values are bound anew.
        try db.rows("INSERT INTO t VALUES (?, ?, ?, ?)", [.int(1), .real(2.5), .text("ข้อความ"), .null])
        try db.rows("INSERT INTO t VALUES (?, ?, ?, ?)", [.int(Int64.max), .real(-1), .text(""), .text("x")])
        XCTAssertEqual(try db.rows("SELECT a, b, c, d FROM t ORDER BY a"),
                       [[.int(1), .real(2.5), .text("ข้อความ"), .null], [.int(Int64.max), .real(-1), .text(""), .text("x")]])
        // On the disk: a second connection reads it.
        XCTAssertEqual(try SQLite(path: file).rows("SELECT count(*) FROM t"), [[.int(2)]])
    }

    func testAMistakeSaysWhat() throws {
        let db = try SQLite(path: path())
        XCTAssertThrowsError(try db.execute("CREATE TABLE")) { error in
            XCTAssertFalse((error as? SQLiteError)?.message.isEmpty ?? true)
            XCTAssertEqual((error as? SQLiteError)?.isBroken, false)
        }
        XCTAssertThrowsError(try db.rows("SELECT * FROM nowhere"))
    }

    func testAFileThatIsNotADatabaseIsToldApart() throws {
        let file = path()
        try Data(String(repeating: "not a database ", count: 400).utf8).write(to: URL(fileURLWithPath: file))
        let db = try SQLite(path: file)
        XCTAssertThrowsError(try db.rows("PRAGMA user_version")) { error in
            XCTAssertEqual((error as? SQLiteError)?.isBroken, true)
        }
    }

    func testTheReadersTakeWhatTheyCan() {
        XCTAssertEqual(SQLValue.int(3).int, 3)
        XCTAssertEqual(SQLValue.real(2.9).int, 2)
        XCTAssertEqual(SQLValue.int(3).real, 3)
        XCTAssertEqual(SQLValue.null.text, "")
        XCTAssertEqual(SQLValue.null.int, 0)
    }
}
