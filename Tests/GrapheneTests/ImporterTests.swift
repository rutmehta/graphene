import Foundation
import SQLite3
import XCTest
@testable import Graphene

final class ImporterTests: XCTestCase {
    func testHistoryReadCompletesWithAllRows() throws {
        try withHistoryDatabase("""
            CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER);
            INSERT INTO urls VALUES ('https://example.com', 'Example', 11644473600000000);
            ""
        ) { file, _ in
            let rows = try Importer.readHistory(file, safari: false)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.url.absoluteString, "https://example.com")
            XCTAssertEqual(rows.first?.title, "Example")
            XCTAssertEqual(rows.first?.date, Date(timeIntervalSince1970: 0))
        }
    }

    func testEmptyHistoryReadCompletesSuccessfully() throws {
        try withHistoryDatabase("CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER);") { file, _ in
            XCTAssertTrue(try Importer.readHistory(file, safari: false).isEmpty)
        }
    }

    func testHistoryReadThrowsInsteadOfReturningPartialRows() throws {
        try withHistoryDatabase("""
            CREATE TABLE history_entries (url TEXT, title TEXT, last_visit_time INTEGER);
            CREATE INDEX history_visit_time ON history_entries(last_visit_time);
            INSERT INTO history_entries VALUES ('https://example.com/first', 'First', 1),
                                               ('https://example.com/second', 'Second', 2);
            CREATE VIEW urls AS
                SELECT url, CASE WHEN last_visit_time = 2 THEN abs(-9223372036854775808) ELSE title END AS title,
                       last_visit_time FROM history_entries;
            ""
        ) { file, database in
            // The indexed query yields a row before the view's integer overflow fails the next step.
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time", -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ERROR)

            XCTAssertThrowsError(try Importer.readHistory(file, safari: false)) { error in
                XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
            }
        }
    }

    private func withHistoryDatabase(_ sql: String, body: (URL, OpaquePointer?) throws -> Void) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-history-test-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        try body(file, database)
    }
}
