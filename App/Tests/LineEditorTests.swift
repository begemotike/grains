import XCTest
@testable import Grains

final class LineEditorTests: XCTestCase {
    func testInsertAndDeleteBackward() {
        var e = LineEditor()
        e.insert("Denali")
        e.apply(.deleteBackward)
        XCTAssertEqual(e.text, "Denal")
        XCTAssertEqual(e.caret, 5)
    }

    func testDeleteBackwardRemovesWholeComposedCharacter() {
        var e = LineEditor(text: "ok 👍🏽")
        e.apply(.deleteBackward)
        XCTAssertEqual(e.text, "ok ")
    }

    func testShiftArrowSelectionAndReplace() {
        var e = LineEditor(text: "Denali")
        e.apply(.move(.left, .character, extend: true))
        e.apply(.move(.left, .character, extend: true))
        XCTAssertEqual(e.selectedText, "li")
        e.insert("X")
        XCTAssertEqual(e.text, "DenaX")
    }

    func testArrowCollapsesSelection() {
        var e = LineEditor(text: "abc")
        e.apply(.selectAll)
        e.apply(.move(.left, .character, extend: false))
        XCTAssertEqual(e.caret, 0)
        XCTAssertFalse(e.hasSelection)
    }

    func testSelectAllThenDelete() {
        var e = LineEditor(text: "Denali - iPad")
        e.apply(.selectAll)
        e.apply(.deleteBackward)
        XCTAssertEqual(e.text, "")
    }

    func testOptionDeleteRemovesWord() {
        var e = LineEditor(text: "Denali - iPad enrollment")
        e.apply(.deleteWordBackward)
        XCTAssertEqual(e.text, "Denali - iPad ")
        e.apply(.deleteWordBackward)
        XCTAssertEqual(e.text, "Denali - ")
    }

    func testCommandDeleteRemovesToLineStart() {
        var e = LineEditor(text: "Denali - iPad")
        e.apply(.move(.left, .word, extend: false))
        e.apply(.deleteToLineStart)
        XCTAssertEqual(e.text, "iPad")
        XCTAssertEqual(e.caret, 0)
    }

    func testWordMovement() {
        var e = LineEditor(text: "one two three")
        e.apply(.move(.left, .word, extend: false))
        XCTAssertEqual(e.caret, 8)
        e.apply(.move(.left, .word, extend: false))
        XCTAssertEqual(e.caret, 4)
        e.apply(.move(.right, .word, extend: false))
        XCTAssertEqual(e.caret, 7)
    }

    func testLineMovementWithSelection() {
        var e = LineEditor(text: "abc def")
        e.apply(.moveUp(extend: true))
        XCTAssertEqual(e.selectedText, "abc def")
        e.apply(.moveDown(extend: false))
        XCTAssertEqual(e.caret, 7)
    }

    func testPasteCollapsesNewlines() {
        var e = LineEditor()
        e.paste("Denali\n- iPad\r\n\tenrollment")
        XCTAssertEqual(e.text, "Denali - iPad enrollment")
    }

    func testMarkedTextThenCommit() {
        var e = LineEditor(text: "caf")
        e.setMarked("´", selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(e.text, "caf´")
        XCTAssertEqual(e.markedRange, NSRange(location: 3, length: 1))
        e.insert("é")
        XCTAssertEqual(e.text, "café")
        XCTAssertNil(e.markedRange)
        XCTAssertEqual(e.caret, 4)
    }

    func testDeleteSelectionForCut() {
        var e = LineEditor(text: "abc")
        e.apply(.move(.left, .character, extend: true))
        XCTAssertEqual(e.deleteSelection(), "c")
        XCTAssertEqual(e.text, "ab")
    }
}
