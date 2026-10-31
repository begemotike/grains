import AppKit
import GrainsCore
import KeyboardShortcuts
import SwiftUI

/// Callbacks Settings needs from the app.
struct SettingsActions {
    /// Writes every week; returns files written and failed.
    var exportAll: @MainActor () async -> (written: Int, failed: Int)
    /// The export service's last write error, if the most recent write of any week failed.
    var exportError: @MainActor () -> String?
    var checkForUpdates: @MainActor () -> Void
    var settingsDidChange: @MainActor () -> Void
}

/// The Settings window: shortcut, corner trigger, export, week, target, menu bar, login,
/// overlay behavior, AI sharing and Claude configuration, updates, version.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var exportStatus: String?
    @State private var exportError: String?
    @State private var copied: String?
    @State private var hotCorners = CornerZone.systemHotCorners()

    var body: some View {
        Form {
            Section("Summon") {
                KeyboardShortcuts.Recorder("Shortcut", name: .toggleOverlay)
                Toggle("Corner trigger", isOn: $settings.cornerTriggerEnabled)
                Picker("Corner", selection: $settings.cornerTriggerCorner) {
                    ForEach(ScreenCorner.allCases) { corner in
                        Text(hotCorners.contains(corner) ? "\(corner.title) (used by Hot Corners)" : corner.title).tag(corner)
                    }
                }
                .disabled(!settings.cornerTriggerEnabled)
                if settings.cornerTriggerEnabled && hotCorners.contains(settings.cornerTriggerCorner) {
                    Text("The system Hot Corners use this corner, so Grains will not trigger there.")
                        .font(.caption).foregroundStyle(Theme.error)
                }
                Toggle("Hide overlay when I click elsewhere", isOn: $settings.hideWhenClickingElsewhere)
            }

            Section("Week") {
                Picker("Week starts on", selection: $settings.weekStartsOn) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.autoupdatingCurrent.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                Toggle("Weekly target", isOn: Binding(
                    get: { settings.targetHours != nil },
                    set: { settings.targetHours = $0 ? (settings.targetHours ?? 40) : nil }
                ))
                if let target = settings.targetHours {
                    Stepper(value: Binding(get: { target }, set: { settings.targetHours = max(1, min(168, $0)) }), in: 1...168, step: 1) {
                        Text("Target: \(Int(target)) hours")
                    }
                }
            }

            Section("Menu bar and login") {
                Toggle("Show elapsed time in the menu bar", isOn: $settings.showElapsedInMenuBar)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(Theme.error)
                }
            }

            Section("CSV export") {
                LabeledContent("Folder") {
                    Text(settings.exportFolderURL.path(percentEncoded: false))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Choose…") { chooseFolder() }
                        .disabled(settings.exportFolderIsOverridden)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.exportFolderURL])
                    }
                    Spacer()
                    Button("Export all weeks now") {
                        exportStatus = "Exporting…"
                        Task {
                            let result = await actions.exportAll()
                            let count = result.written
                            exportStatus = "Wrote \(count) file\(count == 1 ? "" : "s")."
                                + (result.failed > 0 ? " \(result.failed) failed." : "")
                            exportError = actions.exportError()
                        }
                    }
                }
                if let exportStatus {
                    Text(exportStatus).font(.caption).foregroundStyle(.secondary)
                }
                if let exportError {
                    Text("Last export error: \(exportError)").font(.caption).foregroundStyle(Theme.error)
                }
            }

            Section("AI (Claude via MCP)") {
                Toggle("Share notes with AI", isOn: Binding(
                    get: { !settings.redactNotes },
                    set: { settings.redactNotes = !$0 }
                ))
                Text(settings.redactNotes
                     ? "Claude sees client labels and durations, not notes (adds --redact-notes)."
                     : "Claude can read entry text, client labels, notes and durations. Read-only.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Copy Claude Code command") { copy(claudeCode, label: "command") }
                    Button("Copy Claude Desktop JSON") { copy(claudeDesktop, label: "JSON") }
                    if let copied { Text("Copied \(copied).").font(.caption).foregroundStyle(.secondary) }
                }
            }

            Section("Updates") {
                HStack {
                    Text("Grains \(Self.version)")
                    Spacer()
                    Button("Check for Updates…") { actions.checkForUpdates() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.weekStartsOn) { actions.settingsDidChange() }
        .onChange(of: settings.targetHours) { actions.settingsDidChange() }
        .onAppear {
            hotCorners = CornerZone.systemHotCorners()
            exportError = actions.exportError()
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var binaryPath: String {
        ClaudeConfiguration.binaryURL(bundleURL: Bundle.main.bundleURL).path(percentEncoded: false)
    }
    /// The export folder, only when it differs from the server's default.
    private var exportArgument: String? {
        let path = settings.exportFolderURL.standardizedFileURL.path(percentEncoded: false)
        let standard = GrainsPaths.defaultExportDirectory.standardizedFileURL.path(percentEncoded: false)
        return path.trimmingSuffix("/") == standard.trimmingSuffix("/") ? nil : path.trimmingSuffix("/")
    }
    private var claudeCode: String {
        ClaudeConfiguration.claudeCodeCommand(binaryPath: binaryPath, redactNotes: settings.redactNotes,
                                              exportDirectory: exportArgument, weekStartsOn: settings.weekStartsOn)
    }
    private var claudeDesktop: String {
        ClaudeConfiguration.claudeDesktopJSON(binaryPath: binaryPath, redactNotes: settings.redactNotes,
                                              exportDirectory: exportArgument, weekStartsOn: settings.weekStartsOn)
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.exportFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportFolderPath = url.path(percentEncoded: false)
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > 1 ? String(dropLast(suffix.count)) : self
    }
}
