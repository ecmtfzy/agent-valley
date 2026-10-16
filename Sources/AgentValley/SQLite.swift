import Foundation
import SQLite3

/// A value bound into a statement, or read out of a row.
enum SQLValue: Equatable {
    case int(Int64), real(Double), text(String), null

    var int: Int {
        switch self {
        case .int(let value): return Int(value)
        case .real(let value): return Int(value)
        default: return 0
        }
    }

    var real: Double {
        switch self {
        case .real(let value): return value
        case .int(let value): return Double(value)
        default: return 0
        }
    }

    var text: String {
        if case .text(let value) = self { return value }
        return ""
    }
}

struct SQLiteError: Error, Equatable, CustomStringConvertible {
    let code: Int32
    let message: String

    var description: String { message }
    /// The file is not a database, or is one damaged past reading.
    var isBroken: Bool { code == SQLITE_NOTADB || code == SQLITE_CORRUPT }
}

/// One connection to one database file, and the few things the app asks of it. Not for more
/// than one thread: whoever holds it uses it from one queue.
final class SQLite {
    private var db: OpaquePointer?
    /// Statements kept by their text, made once and used again.
    private var statements: [String: OpaquePointer] = [:]

    init(path: String) throws {
        let code = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard code == SQLITE_OK else {
            let error = SQLiteError(code: code, message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)")
            sqlite3_close(db)
            throw error
        }
        // Another copy of the app writing at the same moment is waited for, not failed.
        sqlite3_busy_timeout(db, 2000)
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close(db)
    }

    /// Runs statements that take no values and give no rows.
    func execute(_ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw error(code) }
    }

    /// Runs one statement with `values` bound in order, and gives back its rows.
    @discardableResult
    func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [[SQLValue]] {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (index, value) in values.enumerated() {
            let place = Int32(index + 1)
            switch value {
            case .int(let value): sqlite3_bind_int64(statement, place, value)
            case .real(let value): sqlite3_bind_double(statement, place, value)
            case .text(let value): sqlite3_bind_text(statement, place, value, -1, transient)
            case .null: sqlite3_bind_null(statement, place)
            }
        }
        var rows: [[SQLValue]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return rows }
            guard code == SQLITE_ROW else { throw error(code) }
            rows.append((0..<sqlite3_column_count(statement)).map { column -> SQLValue in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: return .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
                default: return .null
                }
            })
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw error(code) }
        statements[sql] = statement
        return statement
    }

    private func error(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(db)))
    }
}

/// Tells SQLite to copy a bound text before the call returns.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
