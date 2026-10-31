import Foundation
import GrainsCore
import XCTest
@testable import GrainsMCP

/// Spawns the built `grains-mcp` binary (run `swift build` first) against a temp database.
final class EndToEndTests: XCTestCase {
    private var binary: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/debug/grains-mcp")
    }

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: binary.path(percentEncoded: false)) else {
            throw XCTSkip("grains-mcp is not built at \(binary.path(percentEncoded: false)); run `swift build` first")
        }
        tempDirectory = FileManager.default.temporaryDirectory.appending(path: "grains-mcp-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
    }

    private func run(_ arguments: [String], input: String) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: GrainsPaths.databasePathEnvironmentKey)
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    func testInitializeAndToolsListOverStdio() throws {
        let db = tempDirectory.appending(path: "grains.sqlite")
        do {
            let store = try SQLiteEntryStore.open(at: db)
            try store.insert(Entry(id: Fixture.id(1), rawText: "Denali - iPad", clientText: "Denali", note: "iPad",
                                   startedAt: Date().addingTimeInterval(-600)))
        }
        let messages: [JSONValue] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "e2e", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "running_session", "arguments": [:]]],
        ]
        let input = messages.map { $0.compactString() + "\n" }.joined()
        let result = try run(["--db", db.path(percentEncoded: false), "--export-dir", tempDirectory.path(percentEncoded: false)], input: input)

        XCTAssertEqual(result.status, 0, result.stderr)
        let lines = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3, "one line per request, none for the notification:\n\(result.stdout)")
        let responses = try lines.map { try JSONValue.parse(Data($0.utf8)) }
        XCTAssertEqual(responses.map { $0["id"] }, [1, 2, 3])
        XCTAssertEqual(responses[0]["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(responses[0]["result"]?["serverInfo"]?["name"], "grains")
        XCTAssertEqual(responses[1]["result"]?["tools"]?.arrayValue?.count, 9)
        XCTAssertEqual(responses[2]["result"]?["structuredContent"]?["running"]?["id"], .string(Fixture.id(1).uuidString))
        XCTAssertTrue(result.stderr.contains("[grains-mcp]"), "logs go to stderr")
    }

    func testMissingDatabaseExitsWithCode2() throws {
        let missing = tempDirectory.appending(path: "missing.sqlite").path(percentEncoded: false)
        let result = try run(["--db", missing], input: "")
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Grains database not found at \(missing). Launch Grains once to create it."), result.stderr)
    }

    func testVersionAndBadArguments() throws {
        let version = try run(["--version"], input: "")
        XCTAssertEqual(version.status, 0)
        XCTAssertTrue(version.stdout.contains(ServerInfo.version))
        let bad = try run(["--week-start", "9"], input: "")
        XCTAssertNotEqual(bad.status, 0)
        XCTAssertTrue(bad.stderr.contains("--week-start"))
    }
}
