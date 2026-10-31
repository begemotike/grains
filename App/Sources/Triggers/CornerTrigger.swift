import AppKit

/// Corner hit-testing and Hot Corners detection. Pure, tested.
enum CornerZone {
    /// Hit zone size (D13).
    static let size: CGFloat = 12

    /// Whether `point` (AppKit screen coordinates, y up) is inside `corner`'s zone of `screen`.
    static func contains(_ point: CGPoint, corner: ScreenCorner, of screen: CGRect, size: CGFloat = size) -> Bool {
        let left = point.x >= screen.minX && point.x < screen.minX + size
        let right = point.x <= screen.maxX && point.x > screen.maxX - size
        let bottom = point.y >= screen.minY && point.y < screen.minY + size
        let top = point.y <= screen.maxY && point.y > screen.maxY - size
        switch corner {
        case .topLeft: return top && left
        case .topRight: return top && right
        case .bottomLeft: return bottom && left
        case .bottomRight: return bottom && right
        }
    }

    /// Corners the system Hot Corners already use: `wvous-*-corner` non-zero and not 1
    /// (1 = "–", no action).
    static func systemHotCorners(dockPreferences: [String: Any]) -> Set<ScreenCorner> {
        Set(ScreenCorner.allCases.filter { corner in
            let value = (dockPreferences[corner.dockPreferenceKey] as? NSNumber)?.intValue ?? 0
            return value != 0 && value != 1
        })
    }

    /// Reads the live `com.apple.dock` preferences.
    static func systemHotCorners() -> Set<ScreenCorner> {
        systemHotCorners(dockPreferences: UserDefaults(suiteName: "com.apple.dock")?.dictionaryRepresentation() ?? [:])
    }
}

/// Summons the overlay when the pointer rests ≥ 350 ms in the chosen corner (D13). Uses a
/// global + local `mouseMoved` monitor (no permission). Re-arms only after the pointer leaves
/// the zone. Off by default; skips a corner the system Hot Corners already use.
@MainActor
final class CornerTrigger {
    static let dwell: Duration = .milliseconds(350)

    private let action: @MainActor () -> Void
    private var monitors: [Any] = []
    private var corner: ScreenCorner = .bottomLeft
    private var armed = true
    private var dwellTask: Task<Void, Never>?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Apply the settings. Returns false when the corner is taken by Hot Corners (inactive).
    @discardableResult
    func configure(enabled: Bool, corner: ScreenCorner) -> Bool {
        self.corner = corner
        let conflict = CornerZone.systemHotCorners().contains(corner)
        if enabled && !conflict { install() } else { uninstall() }
        return !conflict
    }

    private func install() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func uninstall() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        dwellTask?.cancel()
        dwellTask = nil
        armed = true
    }

    private func inZone() -> Bool {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.contains { CornerZone.contains(point, corner: corner, of: $0.frame) }
    }

    private func pointerMoved() {
        guard inZone() else {
            dwellTask?.cancel()
            dwellTask = nil
            armed = true
            return
        }
        guard armed, dwellTask == nil else { return }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard let self, !Task.isCancelled else { return }
            self.dwellTask = nil
            if self.inZone() {
                self.armed = false
                self.action()
            }
        }
    }
}
