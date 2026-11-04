import XCTest
import SQLite3
@testable import Graphene

final class ImporterTests: XCTestCase {
    private func withHistory(_ sql: String, body: (URL) throws -> Void) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-history-test-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        do {
            defer { sqlite3_close(database) }
            XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        }
        try body(file)
    }

    func testHistoryReadThrowsAfterPartialSQLiteResult() throws {
        try withHistory("""
            CREATE TABLE visits (url TEXT, title TEXT, last_visit_time INTEGER);
            CREATE INDEX visits_by_time ON visits(last_visit_time);
            INSERT INTO visits VALUES ('https://example.com/first', 'First', 1),
                                      ('https://example.com/second', 'Second', 2);
            CREATE VIEW urls AS SELECT url,
                CASE WHEN last_visit_time = 2 THEN abs(-9223372036854775808) ELSE title END AS title,
                last_visit_time FROM visits;
            """) { file in
            // The index streams the first row before the second row's expression overflows.
            var database: OpaquePointer?
            XCTAssertEqual(sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
            defer { sqlite3_close(database) }
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time", -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ERROR)

            XCTAssertThrowsError(try Importer.readHistory(file, safari: false)) { error in
                XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
                XCTAssertEqual((error as NSError).code, CocoaError.Code.fileReadUnknown.rawValue)
            }
        }
    }

    func testHistoryReadCompletesAndSkipsInvalidURLs() throws {
        try withHistory("""
            CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER);
            INSERT INTO urls VALUES ('https://example.com/first', 'First', 11644473601000000),
                                    ('file:///private', 'Invalid', 11644473602000000),
                                    ('https://example.com/last', 'Last', 11644473603000000);
            """) { file in
            let rows = try Importer.readHistory(file, safari: false)
            XCTAssertEqual(rows.map(\.url.absoluteString), ["https://example.com/first", "https://example.com/last"])
            XCTAssertEqual(rows.map(\.title), ["First", "Last"])
            XCTAssertEqual(rows.map(\.date), [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 3)])
        }
    }

    func testEmptyHistoryReadCompletes() throws {
        try withHistory("CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER);") { file in
            XCTAssertTrue(try Importer.readHistory(file, safari: false).isEmpty)
        }
    }
}
