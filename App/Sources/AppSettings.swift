import Foundation
import Observation

/// A screen corner for the corner trigger.
enum ScreenCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    /// The `com.apple.dock` Hot Corners key for this corner.
    var dockPreferenceKey: String {
        switch self {
        case .topLeft: "wvous-tl-corner"
        case .topRight: "wvous-tr-corner"
        case .bottomLeft: "wvous-bl-corner"
        case .bottomRight: "wvous-br-corner"
        }
    }
}

/// User preferences, persisted in `UserDefaults`. Observable so views and the model react.
/// Launch at login is not stored here: `SMAppService` is its source of truth.
@MainActor @Observable
final class AppSettings {
    /// UserDefaults keys. `redactNotes` is read by the "Copy Claude configuration" snippet.
    enum Key {
        static let weekStartsOn = "weekStartsOn"
        static let targetHours = "targetHours"
        static let showElapsedInMenuBar = "showElapsedInMenuBar"
        static let hideWhenClickingElsewhere = "hideWhenClickingElsewhere"
        static let suggestPreviousEntries = "suggestPreviousEntries"
        static let cornerTriggerEnabled = "cornerTriggerEnabled"
        static let cornerTriggerCorner = "cornerTriggerCorner"
        static let exportFolderPath = "exportFolderPath"
        static let redactNotes = "redactNotes"
    }

    /// Defaults, as one table (docs/interaction.md, D13, D17, D66, D67).
    enum Default {
        static let weekStartsOn = 2
        static let showElapsedInMenuBar = true
        static let hideWhenClickingElsewhere = true
        static let suggestPreviousEntries = true
        static let cornerTriggerEnabled = false
        static let cornerTriggerCorner = ScreenCorner.bottomLeft
        static let redactNotes = false
    }

    /// Environment override for the export folder (development runs keep dev CSVs out of
    /// `~/Documents/Grains`).
    static let exportDirectoryEnvironmentKey = "GRAINS_EXPORT_DIR"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let environment: [String: String]

    /// Calendar weekday the week starts on (1 = Sunday, 2 = Monday...).
    var weekStartsOn: Int { didSet { defaults.set(weekStartsOn, forKey: Key.weekStartsOn) } }
    /// Optional weekly target in hours; nil hides the target trajectory.
    var targetHours: Double? { didSet { defaults.set(targetHours ?? 0, forKey: Key.targetHours) } }
    var showElapsedInMenuBar: Bool { didSet { defaults.set(showElapsedInMenuBar, forKey: Key.showElapsedInMenuBar) } }
    var hideWhenClickingElsewhere: Bool { didSet { defaults.set(hideWhenClickingElsewhere, forKey: Key.hideWhenClickingElsewhere) } }
    /// Inline completion from previous entries while typing (D67).
    var suggestPreviousEntries: Bool { didSet { defaults.set(suggestPreviousEntries, forKey: Key.suggestPreviousEntries) } }
    var cornerTriggerEnabled: Bool { didSet { defaults.set(cornerTriggerEnabled, forKey: Key.cornerTriggerEnabled) } }
    var cornerTriggerCorner: ScreenCorner { didSet { defaults.set(cornerTriggerCorner.rawValue, forKey: Key.cornerTriggerCorner) } }
    /// Export folder as a plain path (not sandboxed, D3: no bookmarks needed).
    var exportFolderPath: String { didSet { defaults.set(exportFolderPath, forKey: Key.exportFolderPath) } }
    /// "Share notes with AI" off ⇒ true; adds `--redact-notes` to the Claude configuration.
    var redactNotes: Bool { didSet { defaults.set(redactNotes, forKey: Key.redactNotes) } }

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment, defaultExportFolder: String) {
        self.defaults = defaults
        self.environment = environment
        let start = defaults.object(forKey: Key.weekStartsOn) as? Int ?? Default.weekStartsOn
        weekStartsOn = (1...7).contains(start) ? start : Default.weekStartsOn
        let target = defaults.double(forKey: Key.targetHours)
        targetHours = target > 0 ? target : nil
        showElapsedInMenuBar = defaults.object(forKey: Key.showElapsedInMenuBar) as? Bool ?? Default.showElapsedInMenuBar
        hideWhenClickingElsewhere = defaults.object(forKey: Key.hideWhenClickingElsewhere) as? Bool ?? Default.hideWhenClickingElsewhere
        suggestPreviousEntries = defaults.object(forKey: Key.suggestPreviousEntries) as? Bool ?? Default.suggestPreviousEntries
        cornerTriggerEnabled = defaults.object(forKey: Key.cornerTriggerEnabled) as? Bool ?? Default.cornerTriggerEnabled
        cornerTriggerCorner = defaults.string(forKey: Key.cornerTriggerCorner).flatMap(ScreenCorner.init(rawValue:)) ?? Default.cornerTriggerCorner
        exportFolderPath = defaults.string(forKey: Key.exportFolderPath) ?? defaultExportFolder
        redactNotes = defaults.object(forKey: Key.redactNotes) as? Bool ?? Default.redactNotes
    }

    /// The folder CSVs are written to: `$GRAINS_EXPORT_DIR` when set, else the setting.
    var exportFolderURL: URL {
        if let override = environment[Self.exportDirectoryEnvironmentKey], !override.isEmpty {
            return URL(filePath: (override as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return URL(filePath: (exportFolderPath as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    /// True when the export folder comes from the environment (Settings shows it read-only).
    var exportFolderIsOverridden: Bool {
        !(environment[Self.exportDirectoryEnvironmentKey] ?? "").isEmpty
    }
}
