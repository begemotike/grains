import Foundation

/// Well-known file locations (docs/data-model.md "Path resolution", D4).
public enum GrainsPaths {
    /// Environment variable that overrides the database location (tests, development).
    public static let databasePathEnvironmentKey = "GRAINS_DB_PATH"

    /// The SQLite database shared by the app (read/write) and `grains-mcp` (read-only).
    ///
    /// `$GRAINS_DB_PATH` when set (a leading `~` is expanded), otherwise
    /// `~/Library/Application Support/Grains/grains.sqlite`. The containing directory is
    /// created on demand; if that fails, opening the store reports the real error.
    public static var databaseURL: URL {
        databaseURL(environment: ProcessInfo.processInfo.environment)
    }

    /// Default folder for weekly CSV exports: `~/Documents/Grains`. Not created here;
    /// the exporter creates it when it first writes.
    public static var defaultExportDirectory: URL {
        URL.documentsDirectory.appending(path: "Grains", directoryHint: .isDirectory)
    }

    /// Testable form of `databaseURL`.
    static func databaseURL(environment: [String: String], createDirectory: Bool = true) -> URL {
        let url: URL
        if let override = environment[databasePathEnvironmentKey], !override.isEmpty {
            url = URL(filePath: (override as NSString).expandingTildeInPath)
        } else {
            url = URL.applicationSupportDirectory
                .appending(path: "Grains", directoryHint: .isDirectory)
                .appending(path: "grains.sqlite", directoryHint: .notDirectory)
        }
        if createDirectory {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return url
    }
}
