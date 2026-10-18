import Foundation
@testable import Notchlet
import Testing

struct OpenCodeHistorySourceTests {
    @Test func parsesRowsAsSqliteJSONPrintsThem() throws {
        let rows = Data("""
        [{"ms":1756900000000,"model":"claude-sonnet-4-5","cost":0.0123,"input":100,"output":50,"reasoning":10,"cacheRead":400,"cacheWrite":20},
         {"ms":1756903600000,"model":"kimi-k2","cost":0,"input":5,"output":1,"reasoning":null,"cacheRead":null,"cacheWrite":null}]
        """.utf8)
        let events = try OpenCodeHistorySource.events(fromRows: rows)

        #expect(events.count == 2)
        #expect(events[0].model == "claude-sonnet-4-5")
        #expect(events[0].timestamp == Date(timeIntervalSince1970: 1_756_900_000))
        #expect(events[0].tokens == TokenCount(input: 100, cacheRead: 400, cacheWrite5m: 20, output: 60))
        #expect(events[0].reportedCost == 0.0123)
        #expect(events[1].tokens == TokenCount(input: 5, output: 1))
        #expect(events[1].reportedCost == nil)
        #expect(try OpenCodeHistorySource.events(fromRows: Data()).isEmpty)
    }

    @Test func queriesHostedAssistantMessagesSinceTheCutoff() {
        let sql = OpenCodeHistorySource.sql(since: Date(timeIntervalSince1970: 1_756_900_000))
        #expect(sql.contains("time_created >= 1756900000000"))
        #expect(sql.contains("IN ('opencode-go','opencode')"))
        #expect(sql.contains("'$.role') = 'assistant'"))
        #expect(OpenCodeHistorySource.sql(since: nil).contains("time_created >= 0"))
    }

    @Test func findsEveryChannelsDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-opencode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["opencode.db", "opencode-next.db", "opencode.db-wal", "auth.json"] {
            try Data().write(to: directory.appending(path: name))
        }

        #expect(OpenCodeHistorySource.databases(in: directory).map(\.lastPathComponent) == [
            "opencode-next.db",
            "opencode.db",
        ])
        #expect(OpenCodeHistorySource.databases(in: directory.appending(path: "missing")).isEmpty)
    }

    @Test func readsARealDatabaseThroughSqlite() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-opencode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appending(path: "opencode.db")
        let setup = """
        CREATE TABLE message (id TEXT PRIMARY KEY, time_created INTEGER, data TEXT);
        INSERT INTO message VALUES ('a', 1756900000000, '{"role":"assistant","providerID":"opencode-go","modelID":"claude-sonnet-4-5","cost":0.5,"tokens":{"input":10,"output":5,"reasoning":0,"cache":{"read":0,"write":0}}}');
        INSERT INTO message VALUES ('b', 1756900000000, '{"role":"user","providerID":"opencode-go","modelID":"claude-sonnet-4-5"}');
        INSERT INTO message VALUES ('c', 1756900000000, '{"role":"assistant","providerID":"anthropic","modelID":"claude-opus-5","cost":0,"tokens":{"input":10,"output":5}}');
        INSERT INTO message VALUES ('d', 1000, '{"role":"assistant","providerID":"opencode","modelID":"kimi-k2","cost":0.1,"tokens":{"input":1,"output":1}}');
        """
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [database.path, setup]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let events = try await OpenCodeHistorySource(dataDirectory: directory)
            .events(since: Date(timeIntervalSince1970: 1_000_000))

        #expect(events.count == 1)
        #expect(events[0].model == "claude-sonnet-4-5")
        #expect(events[0].reportedCost == 0.5)
    }
}
