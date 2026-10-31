import SwiftUI
import XCTest
@testable import Grains

final class ThemeTests: XCTestCase {
    func testPaletteMatchesDesignDoc() {
        XCTAssertEqual(Theme.Hex.bg, 0x161a20)
        XCTAssertEqual(Theme.Hex.sub, 0x646f7e)
        XCTAssertEqual(Theme.Hex.text, 0xd1d7e0)
        XCTAssertEqual(Theme.Hex.accent, 0xe2b714)
        XCTAssertEqual(Theme.Hex.elapsed, 0x8a93a3)
        XCTAssertEqual(Theme.Hex.error, 0xca4754)
        XCTAssertEqual(Theme.accentDimOpacity, 0.25)
        XCTAssertEqual(Theme.panelOpacity, 0.96)
        XCTAssertEqual(Theme.hairlineOpacity, 0.06)
    }

    func testGeometryAndTypeScale() {
        XCTAssertEqual(Theme.Metrics.overlayWidth, 640)
        XCTAssertEqual(Theme.Metrics.cornerRadius, 14)
        XCTAssertEqual(Theme.Metrics.topFraction, 0.22)
        XCTAssertEqual(Theme.Metrics.mainLane, 72)
        XCTAssertEqual(Theme.Metrics.elapsedLane, 6)
        XCTAssertEqual(Theme.Metrics.laneGap, 10)
        XCTAssertEqual(Theme.Metrics.weekdayRow, 14)
        XCTAssertEqual(Theme.Metrics.activePointRadius, 5)
        XCTAssertEqual(Theme.Metrics.activeGlowRadius, 12)
        XCTAssertEqual(Theme.Size.entryLine, 28)
        XCTAssertEqual(Theme.Size.elapsed, 44)
        XCTAssertEqual(Theme.Size.metric, 22)
        XCTAssertEqual(Theme.Size.metricLabel, 11)
        XCTAssertEqual(Theme.Size.weekday, 10)
    }

    func testHexColorComponents() throws {
        let color = try XCTUnwrap(NSColor(hex: Theme.Hex.accent).usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 0xe2 / 255, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0xb7 / 255, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0x14 / 255, accuracy: 0.001)
    }

    func testMonoFontIsFixedPitch() {
        XCTAssertTrue(Theme.monoNSFont(28).isFixedPitch)
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    private func freshDefaults() throws -> UserDefaults {
        let name = "GrainsAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaults() throws {
        let s = AppSettings(defaults: try freshDefaults(), environment: [:], defaultExportFolder: "/tmp/x")
        XCTAssertEqual(s.weekStartsOn, 2)
        XCTAssertNil(s.targetHours)
        XCTAssertTrue(s.showElapsedInMenuBar)
        XCTAssertTrue(s.hideWhenClickingElsewhere)
        XCTAssertTrue(s.suggestPreviousEntries)
        XCTAssertFalse(s.cornerTriggerEnabled)
        XCTAssertEqual(s.cornerTriggerCorner, .bottomLeft)
        XCTAssertEqual(s.exportFolderPath, "/tmp/x")
        XCTAssertFalse(s.redactNotes)
    }

    func testRoundTrip() throws {
        let defaults = try freshDefaults()
        let s = AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/tmp/x")
        s.weekStartsOn = 1
        s.targetHours = 32
        s.showElapsedInMenuBar = false
        s.hideWhenClickingElsewhere = false
        s.suggestPreviousEntries = false
        s.cornerTriggerEnabled = true
        s.cornerTriggerCorner = .topRight
        s.exportFolderPath = "/tmp/exports"
        s.redactNotes = true
        let t = AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/tmp/x")
        XCTAssertEqual(t.weekStartsOn, 1)
        XCTAssertEqual(t.targetHours, 32)
        XCTAssertFalse(t.showElapsedInMenuBar)
        XCTAssertFalse(t.hideWhenClickingElsewhere)
        XCTAssertFalse(t.suggestPreviousEntries)
        XCTAssertTrue(t.cornerTriggerEnabled)
        XCTAssertEqual(t.cornerTriggerCorner, .topRight)
        XCTAssertEqual(t.exportFolderPath, "/tmp/exports")
        XCTAssertTrue(t.redactNotes)
        XCTAssertEqual(defaults.bool(forKey: "redactNotes"), true)
        t.targetHours = nil
        XCTAssertNil(AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/tmp/x").targetHours)
    }

    /// D66: click-outside hides by default.
    func testHideOnClickOutsideDefaultsOn() throws {
        XCTAssertTrue(AppSettings.Default.hideWhenClickingElsewhere)
        XCTAssertTrue(AppSettings(defaults: try freshDefaults(), environment: [:], defaultExportFolder: "/").hideWhenClickingElsewhere)
    }

    /// D67: suggestions are on by default; a stored false wins.
    func testAutocompleteDefaultsOn() throws {
        let defaults = try freshDefaults()
        XCTAssertTrue(AppSettings.Default.suggestPreviousEntries)
        XCTAssertTrue(AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/").suggestPreviousEntries)
        defaults.set(false, forKey: AppSettings.Key.suggestPreviousEntries)
        XCTAssertFalse(AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/").suggestPreviousEntries)
    }

    func testInvalidWeekStartFallsBack() throws {
        let defaults = try freshDefaults()
        defaults.set(9, forKey: AppSettings.Key.weekStartsOn)
        XCTAssertEqual(AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/").weekStartsOn, 2)
    }

    func testExportFolderEnvironmentOverride() throws {
        let s = AppSettings(defaults: try freshDefaults(), environment: ["GRAINS_EXPORT_DIR": "/tmp/dev-csv"], defaultExportFolder: "/tmp/x")
        XCTAssertEqual(s.exportFolderURL.path(percentEncoded: false), "/tmp/dev-csv/")
        XCTAssertTrue(s.exportFolderIsOverridden)
    }
}

final class ClaudeConfigurationTests: XCTestCase {
    let path = "/Applications/Grains.app/Contents/MacOS/grains-mcp"

    func testBinaryPath() {
        XCTAssertEqual(ClaudeConfiguration.binaryURL(bundleURL: URL(filePath: "/Applications/Grains.app")).path(percentEncoded: false), path)
    }

    func testClaudeCodeCommand() {
        XCTAssertEqual(ClaudeConfiguration.claudeCodeCommand(binaryPath: path, redactNotes: false), "claude mcp add grains -- \(path)")
        XCTAssertEqual(ClaudeConfiguration.claudeCodeCommand(binaryPath: path, redactNotes: true), "claude mcp add grains -- \(path) --redact-notes")
        XCTAssertEqual(ClaudeConfiguration.claudeCodeCommand(binaryPath: "/Users/me/My Apps/Grains.app/x", redactNotes: false),
                       "claude mcp add grains -- '/Users/me/My Apps/Grains.app/x'")
    }

    func testDesktopJSON() throws {
        let json = ClaudeConfiguration.claudeDesktopJSON(binaryPath: path, redactNotes: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        let grains = try XCTUnwrap(servers["grains"] as? [String: Any])
        XCTAssertEqual(grains["command"] as? String, path)
        XCTAssertEqual(grains["args"] as? [String], ["--redact-notes"])
        XCTAssertFalse(json.contains("\\/"))
        let plain = ClaudeConfiguration.claudeDesktopJSON(binaryPath: path, redactNotes: false)
        XCTAssertFalse(plain.contains("args"))
    }

    func testNonDefaultExportFolderAndWeekStartArePassed() {
        XCTAssertEqual(ClaudeConfiguration.arguments(redactNotes: false, exportDirectory: "/tmp/csv", weekStartsOn: 1),
                       ["--export-dir", "/tmp/csv", "--week-start", "1"])
        XCTAssertEqual(ClaudeConfiguration.claudeCodeCommand(binaryPath: path, redactNotes: true, exportDirectory: "/My CSV", weekStartsOn: 2),
                       "claude mcp add grains -- \(path) --redact-notes --export-dir '/My CSV'")
    }
}
