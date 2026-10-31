import Foundation

/// The "Copy Claude configuration" snippets (docs/mcp-server.md "Client setup"), built from
/// the real path of the running app's bundled `grains-mcp`. Pure, tested.
enum ClaudeConfiguration {
    static let serverName = "grains"
    static let redactFlag = "--redact-notes"

    /// `<bundle>/Contents/MacOS/grains-mcp`.
    static func binaryURL(bundleURL: URL) -> URL {
        bundleURL.appending(path: "Contents/MacOS/grains-mcp", directoryHint: .notDirectory)
    }

    /// Server arguments mirroring the app's settings (D46, D56): `--redact-notes` when notes
    /// are not shared, `--export-dir` when the folder is not the default, `--week-start` when
    /// the week does not start on Monday.
    static func arguments(redactNotes: Bool, exportDirectory: String? = nil, weekStartsOn: Int = 2) -> [String] {
        var args: [String] = []
        if redactNotes { args.append(redactFlag) }
        if let exportDirectory { args += ["--export-dir", exportDirectory] }
        if weekStartsOn != 2 { args += ["--week-start", String(weekStartsOn)] }
        return args
    }

    /// `claude mcp add grains -- '<path>' [args]`
    static func claudeCodeCommand(binaryPath: String, redactNotes: Bool, exportDirectory: String? = nil, weekStartsOn: Int = 2) -> String {
        let args = arguments(redactNotes: redactNotes, exportDirectory: exportDirectory, weekStartsOn: weekStartsOn)
        return (["claude mcp add \(serverName) -- \(shellQuoted(binaryPath))"] + args.map(shellQuoted)).joined(separator: " ")
    }

    /// The `claude_desktop_config.json` fragment.
    static func claudeDesktopJSON(binaryPath: String, redactNotes: Bool, exportDirectory: String? = nil, weekStartsOn: Int = 2) -> String {
        var server: [String: Any] = ["command": binaryPath]
        let args = arguments(redactNotes: redactNotes, exportDirectory: exportDirectory, weekStartsOn: weekStartsOn)
        if !args.isEmpty { server["args"] = args }
        let root: [String: Any] = ["mcpServers": [serverName: server]]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// Single-quotes for the shell when needed (`'` becomes `'\''`).
    static func shellQuoted(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:@")
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
