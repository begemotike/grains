import XCTest
@testable import GrainsCore

final class EntryParserTests: XCTestCase {
    func testHyphenSeparator() {
        let result = EntryParser.parse("Denali - iPad enrollment")
        XCTAssertEqual(result.clientText, "Denali")
        XCTAssertEqual(result.note, "iPad enrollment")
    }

    func testEnDashAndEmDash() {
        XCTAssertEqual(EntryParser.parse("Denali – iPad").clientText, "Denali")
        XCTAssertEqual(EntryParser.parse("Denali – iPad").note, "iPad")
        XCTAssertEqual(EntryParser.parse("Denali — iPad").clientText, "Denali")
        XCTAssertEqual(EntryParser.parse("Denali — iPad").note, "iPad")
    }

    func testNoSeparatorIsAllNote() {
        let result = EntryParser.parse("  Administrative work ")
        XCTAssertNil(result.clientText)
        XCTAssertEqual(result.note, "Administrative work")
        XCTAssertNil(result.separatorRange)
    }

    func testHyphenWithoutSpacesIsNotASeparator() {
        let result = EntryParser.parse("Wi-Fi survey")
        XCTAssertNil(result.clientText)
        XCTAssertEqual(result.note, "Wi-Fi survey")
    }

    func testEmptyPiecesBecomeNil() {
        let leading = EntryParser.parse(" - just a note")
        XCTAssertNil(leading.clientText)
        XCTAssertEqual(leading.note, "just a note")

        let trailing = EntryParser.parse("Denali - ")
        XCTAssertEqual(trailing.clientText, "Denali")
        XCTAssertNil(trailing.note)

        let empty = EntryParser.parse("")
        XCTAssertNil(empty.clientText)
        XCTAssertNil(empty.note)
    }

    func testFirstSeparatorWinsAcrossKinds() {
        let result = EntryParser.parse("A — b - c")
        XCTAssertEqual(result.clientText, "A")
        XCTAssertEqual(result.note, "b - c")
    }

    func testSeparatorRangeIsExact() throws {
        let raw = "Denali – iPad - more"
        let result = EntryParser.parse(raw)
        let range = try XCTUnwrap(result.separatorRange)
        XCTAssertEqual(String(raw[range]), " – ")
        XCTAssertEqual(raw.distance(from: raw.startIndex, to: range.lowerBound), 6)
        XCTAssertEqual(raw.distance(from: raw.startIndex, to: range.upperBound), 9)
    }

    func testEntryCapturingParsesButKeepsRawText() {
        let entry = Entry(capturing: "  Denali - iPad  ", at: TestDate.reference)
        XCTAssertEqual(entry.rawText, "  Denali - iPad  ")
        XCTAssertEqual(entry.clientText, "Denali")
        XCTAssertEqual(entry.note, "iPad")
    }
}
