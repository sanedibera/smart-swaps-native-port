import Foundation
import SQLite3

/// A minimal read-only SQLite reader over the system library.
///
/// DEVIATION FROM THE BRIEF, deliberate: the brief suggested GRDB or SQLite.swift. This
/// database is opened read-only and hit by exactly four statements, none of them a JOIN
/// or a write. An ORM buys nothing here and costs two things that matter for this port -
/// a network-fetched dependency, and a layer between the port and SQLite's row order,
/// which PORTING_INVENTORY.md §3.2 established is load-bearing (`SELECT * FROM foods` has
/// no ORDER BY, and that order fixes filter order, tie-break order and candidate
/// insertion order all the way through the engine).
public final class SQLiteDB {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            throw SQLiteError.open(path)
        }
        handle = h
    }

    deinit { if let handle { sqlite3_close_v2(handle) } }

    public enum SQLiteError: Error {
        case open(String)
        case prepare(String)
    }

    /// Streams rows in the order SQLite returns them.
    public func query(_ sql: String, _ each: (Row) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError.prepare(sql)
        }
        defer { sqlite3_finalize(stmt) }
        let row = Row(stmt: stmt)
        while sqlite3_step(stmt) == SQLITE_ROW { each(row) }
    }

    public struct Row {
        let stmt: OpaquePointer

        public func text(_ i: Int32) -> String? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL,
                  let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        public func double(_ i: Int32) -> Double {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? 0 : sqlite3_column_double(stmt, i)
        }
        public func doubleOrNil(_ i: Int32) -> Double? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
        }
        public func int(_ i: Int32) -> Int? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i))
        }
    }
}
