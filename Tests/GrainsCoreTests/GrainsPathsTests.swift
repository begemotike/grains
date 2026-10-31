import XCTest
@testable import GrainsCore

final class GrainsPathsTests: XCTestCase {
    func testEnvironmentOverrideCreatesParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GrainsPathsTests-\(UUID().uuidString)/nested", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let path = directory.appending(path: "custom.sqlite").path(percentEncoded: false)
        let url = GrainsPaths.databaseURL(environment: [GrainsPaths.databasePathEnvironmentKey: path])
        XCTAssertEqual(url.path(percentEncoded: false), path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testDefaultLocations() {
        let url = GrainsPaths.databaseURL(environment: [:], createDirectory: false)
        XCTAssertTrue(url.path(percentEncoded: false).hasSuffix("Library/Application Support/Grains/grains.sqlite"))
        let export = GrainsPaths.defaultExportDirectory
        XCTAssertEqual(export.lastPathComponent, "Grains")
        XCTAssertEqual(export.deletingLastPathComponent().lastPathComponent, "Documents")
    }
}
