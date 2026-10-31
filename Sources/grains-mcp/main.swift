// grains-mcp: read-only MCP server for Grains over stdio. All logic lives in GrainsMCP;
// this file only parses arguments, opens the database read-only and runs the loop.
import Foundation
import GrainsCore
import GrainsMCP
import GrainsReports

let usage = """
usage: grains-mcp [--db <path>] [--export-dir <path>] [--redact-notes] [--week-start <1-7>]
       grains-mcp --version | --help

Read-only MCP server (JSON-RPC 2.0 over stdio, protocol \(ServerInfo.protocolVersion)) for the Grains time tracker.

  --db <path>          database file (default: $GRAINS_DB_PATH, else
                       ~/Library/Application Support/Grains/grains.sqlite)
  --export-dir <path>  CSV export folder listed by list_exports (default: ~/Documents/Grains)
  --redact-notes       hide notes; raw_text is replaced by the client label
  --week-start <1-7>   first weekday of a week, 1 = Sunday, 2 = Monday (default 2)
  --version            print the version and exit
  --help               print this help and exit

Logs go to stderr; stdout carries only protocol messages.
"""

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func expandedURL(_ path: String) -> URL {
    URL(filePath: (path as NSString).expandingTildeInPath)
}

var databaseURL: URL?
var exportDirectory: URL?
var redactNotes = false
var weekStart = 2

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    func value() -> String {
        guard let next = arguments.next(), !next.isEmpty else { fail("grains-mcp: \(argument) needs a value\n\n\(usage)", code: 64) }
        return next
    }
    switch argument {
    case "--db": databaseURL = expandedURL(value())
    case "--export-dir": exportDirectory = expandedURL(value())
    case "--redact-notes": redactNotes = true
    case "--week-start":
        let text = value()
        guard let n = Int(text), (1...7).contains(n) else { fail("grains-mcp: --week-start must be 1...7 (1 = Sunday, 2 = Monday), got \(text)", code: 64) }
        weekStart = n
    case "--version", "-V":
        print("grains-mcp \(ServerInfo.version) (MCP \(ServerInfo.protocolVersion))")
        exit(0)
    case "--help", "-h":
        print(usage)
        exit(0)
    default:
        fail("grains-mcp: unknown argument \(argument)\n\n\(usage)", code: 64)
    }
}

// A closed stdout must surface as a write error (handled in runStdio), not kill the process.
signal(SIGPIPE, SIG_IGN)

let dbURL = databaseURL ?? GrainsPaths.databaseURL
guard FileManager.default.fileExists(atPath: dbURL.path(percentEncoded: false)) else {
    fail("Grains database not found at \(dbURL.path(percentEncoded: false)). Launch Grains once to create it.", code: 2)
}

let store: any EntryReading
do {
    store = try SQLiteEntryStore.openReadOnly(at: dbURL)
} catch {
    fail("grains-mcp: could not open the Grains database at \(dbURL.path(percentEncoded: false)): \(error)", code: 2)
}

let server = MCPServer(
    store: store,
    spec: WeekSpec(startsOn: weekStart, calendar: .autoupdatingCurrent),
    exportDirectory: exportDirectory ?? GrainsPaths.defaultExportDirectory,
    options: MCPServer.Options(redactNotes: redactNotes)
)
server.runStdio()
exit(0)
