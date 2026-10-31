import XCTest
@testable import GrainsReports

final class AtomicFileWriterTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GrainsReportsTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreatesDirectoryReplacesFileAndLeavesNoTemp() throws {
        let dir = root.appendingPathComponent("a/b")
        let url = dir.appendingPathComponent("Grains-2026-W44.csv")
        try AtomicFileWriter.write(Data("first\n".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first\n")
        try AtomicFileWriter.write(Data("second\n".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["Grains-2026-W44.csv"])
    }

    func testEmptyData() throws {
        let url = root.appendingPathComponent("empty.csv")
        try AtomicFileWriter.write(Data(), to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    func testFailureLeavesOriginalAndNoTemp() throws {
        // Target is an existing non-empty directory: rename(2) fails, nothing else changes.
        let target = root.appendingPathComponent("occupied")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("child"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try AtomicFileWriter.write(Data("x".utf8), to: target))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["occupied"])
    }
}
