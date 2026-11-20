import XCTest
import SQLite3
@testable import Graphene

final class ImporterTests: XCTestCase {
    func testHistoryReadThrowsAfterPartialResults() throws {
        let file = try historyDatabase("""
            CREATE TABLE visits (url TEXT, title TEXT, last_visit_time INTEGER);
            CREATE INDEX visit_time ON visits(last_visit_time);
            INSERT INTO visits VALUES
                ('https://example.com/first', 'First', 1),
                ('https://example.com/second', 'Second', 2);
            CREATE VIEW urls AS SELECT url,
                CASE WHEN last_visit_time = 2 THEN abs(-9223372036854775808) ELSE title END AS title,
                last_visit_time FROM visits;
            """)
        defer { try? FileManager.default.removeItem(at: file) }

        // The index streams the first row before the second row's integer overflow.
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ERROR)

        XCTAssertThrowsError(try Importer.readHistory(file, safari: false)) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.fileReadCorruptFile.rawValue)
        }
    }

    func testHistoryReadCompletesAndSkipsInvalidURLs() throws {
        let file = try historyDatabase("""
            CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER);
            INSERT INTO urls VALUES
                ('https://example.com/first', 'First', 11644473601000000),
                ('chrome://settings', 'Settings', 11644473602000000),
                ('https://example.com/last', 'Last', 11644473603000000);
            """)
        defer { try? FileManager.default.removeItem(at: file) }

        let rows = try Importer.readHistory(file, safari: false)
        XCTAssertEqual(rows.map { $0.url.absoluteString }, ["https://example.com/first", "https://example.com/last"])
        XCTAssertEqual(rows.map { $0.title }, ["First", "Last"])
        XCTAssertEqual(rows.map { $0.date }, [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 3)])
    }

    func testEmptyHistoryReadCompletes() throws {
        let file = try historyDatabase("CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER);")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(try Importer.readHistory(file, safari: false).isEmpty)
    }

    private func historyDatabase(_ sql: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("graphene-history-test-\(UUID()).sqlite")
        var database: OpaquePointer?
        guard sqlite3_open(file.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            try? FileManager.default.removeItem(at: file)
            throw CocoaError(.fileWriteUnknown)
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            try? FileManager.default.removeItem(at: file)
            throw CocoaError(.fileWriteUnknown)
        }
        return file
    }
}
