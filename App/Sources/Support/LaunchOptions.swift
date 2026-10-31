import Foundation

/// Development launch arguments: `--show` opens the overlay at launch; `--demo-state
/// idle|typing|running|stopped` puts it in a state for screenshots (`typing` shows an inline
/// completion, D67).
struct LaunchOptions: Equatable {
    enum DemoState: String { case idle, typing, running, stopped }

    var show = false
    var demoState: DemoState?
    /// `--snapshot <path>`: write a PNG of the overlay after the demo state settles, then quit.
    var snapshotPath: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        show = arguments.contains("--show")
        if let i = arguments.firstIndex(of: "--demo-state"), arguments.indices.contains(i + 1) {
            demoState = DemoState(rawValue: arguments[i + 1])
            show = true
        }
        if let i = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(i + 1) {
            snapshotPath = arguments[i + 1]
            show = true
        }
    }

    /// True when Sparkle should stay quiet (screenshots, demos).
    var isDemo: Bool { demoState != nil || snapshotPath != nil }

    /// The process hosts XCTest (GrainsAppTests): skip all app setup.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
}
