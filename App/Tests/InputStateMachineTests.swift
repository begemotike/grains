import XCTest
@testable import Grains

/// Every row of both key tables in docs/interaction.md.
final class InputStateMachineTests: XCTestCase {
    private func control(_ text: String = "", committed: Bool = false, recovery: Bool = false) -> InputStateMachine.Context {
        .init(mode: .control, lineText: text, lineIsCommitted: committed, hasRecovery: recovery)
    }

    private func typing(_ text: String = "") -> InputStateMachine.Context {
        .init(mode: .typing, lineText: text)
    }

    private func act(_ input: KeyInput, _ context: InputStateMachine.Context) -> [OverlayAction] {
        InputStateMachine.actions(for: input, in: context)
    }

    // MARK: Control mode

    func testControlSpaceToggles() {
        XCTAssertEqual(act(.space, control()), [.toggleTimer])
        XCTAssertEqual(act(.space, control("Denali - iPad", committed: true)), [.toggleTimer])
    }

    func testControlReturnTogglesOnlyWithText() {
        XCTAssertEqual(act(.returnKey, control("Denali")), [.toggleTimer])
        XCTAssertEqual(act(.returnKey, control()), [])
        XCTAssertEqual(act(.returnKey, control("   ")), [])
    }

    func testControlFirstPrintableEntersTypingAndInserts() {
        XCTAssertEqual(act(.text("D"), control()), [.enterTyping, .insert("D")])
    }

    func testControlPrintableClearsCommittedLineFirst() {
        XCTAssertEqual(act(.text("x"), control("Denali - iPad", committed: true)), [.enterTyping, .clearLine, .insert("x")])
    }

    func testControlPrintableKeepsDraft() {
        XCTAssertEqual(act(.text("x"), control("draft", committed: false)), [.enterTyping, .insert("x")])
    }

    func testControlBackspaceEntersTypingEditingLine() {
        XCTAssertEqual(act(.command(.deleteBackward), control("Denali", committed: true)), [.enterTyping, .deleteBackward])
    }

    func testControlLeftRightNavigateWeeks() {
        XCTAssertEqual(act(.command(.move(.left, .character, extend: false)), control()), [.previousWeek])
        XCTAssertEqual(act(.command(.move(.right, .character, extend: false)), control()), [.nextWeek])
    }

    func testControlUpDownCycleRecent() {
        XCTAssertEqual(act(.command(.moveUp(extend: false)), control()), [.cycleRecent(1)])
        XCTAssertEqual(act(.command(.moveDown(extend: false)), control()), [.cycleRecent(-1)])
    }

    func testControlCommandComma() {
        XCTAssertEqual(act(.shortcut(","), control()), [.openSettings])
    }

    func testControlCommandZUndoesStop() {
        XCTAssertEqual(act(.shortcut("z"), control()), [.undoStop])
    }

    func testControlEscapeHides() {
        XCTAssertEqual(act(.escape, control()), [.hide])
        XCTAssertEqual(act(.escape, control("draft")), [.hide])
    }

    func testControlRecoveryKeysOnlyWithRecovery() {
        XCTAssertEqual(act(.text("r"), control(recovery: true)), [.resumeRecovered])
        XCTAssertEqual(act(.text("R"), control(recovery: true)), [.resumeRecovered])
        XCTAssertEqual(act(.text("a"), control(recovery: true)), [.acceptRecovered])
        XCTAssertEqual(act(.text("A"), control(recovery: true)), [.acceptRecovered])
        XCTAssertEqual(act(.text("r"), control()), [.enterTyping, .insert("r")])
        XCTAssertEqual(act(.text("a"), control()), [.enterTyping, .insert("a")])
    }

    func testRecoveryKeysAreLettersInTypingMode() {
        var context = typing("x")
        context.hasRecovery = true
        XCTAssertEqual(act(.text("r"), context), [.insert("r")])
    }

    func testControlComposeEntersTyping() {
        XCTAssertEqual(act(.composeBegan, control()), [.enterTyping])
        XCTAssertEqual(act(.composeBegan, control("Denali", committed: true)), [.enterTyping, .clearLine])
    }

    func testControlPasteEntersTyping() {
        XCTAssertEqual(act(.shortcut("v"), control()), [.enterTyping, .paste])
    }

    func testControlIgnoresOtherMovement() {
        XCTAssertEqual(act(.command(.move(.left, .word, extend: false)), control()), [])
        XCTAssertEqual(act(.command(.selectAll), control()), [])
    }

    // MARK: Typing mode

    func testTypingSpaceInsertsSpace() {
        XCTAssertEqual(act(.space, typing("Denali")), [.insert(" ")])
    }

    func testTypingReturnCommitsAndExits() {
        XCTAssertEqual(act(.returnKey, typing("Denali - iPad")), [.commit("Denali - iPad"), .exitTyping])
    }

    func testTypingReturnOnEmptyLineOnlyExits() {
        XCTAssertEqual(act(.returnKey, typing("  ")), [.exitTyping])
    }

    func testTypingEscapeExitsKeepingText() {
        XCTAssertEqual(act(.escape, typing("Denali")), [.exitTyping])
    }

    func testEscapeTwiceHides() {
        let first = act(.escape, typing("Denali"))
        XCTAssertEqual(first, [.exitTyping])
        XCTAssertEqual(act(.escape, control("Denali")), [.hide])
    }

    func testTypingPrintableInserts() {
        XCTAssertEqual(act(.text("é"), typing("caf")), [.insert("é")])
    }

    func testTypingEditingCommands() {
        XCTAssertEqual(act(.shortcut("a"), typing("x")), [.edit(.selectAll)])
        XCTAssertEqual(act(.command(.deleteToLineStart), typing("x")), [.edit(.deleteToLineStart)])
        XCTAssertEqual(act(.command(.deleteWordBackward), typing("x")), [.edit(.deleteWordBackward)])
        XCTAssertEqual(act(.command(.deleteBackward), typing("x")), [.deleteBackward])
        XCTAssertEqual(act(.command(.move(.left, .character, extend: true)), typing("x")), [.edit(.move(.left, .character, extend: true))])
        XCTAssertEqual(act(.command(.move(.right, .word, extend: false)), typing("x")), [.edit(.move(.right, .word, extend: false))])
    }

    func testTypingArrowsEditInsteadOfNavigating() {
        XCTAssertEqual(act(.command(.move(.left, .character, extend: false)), typing("x")), [.edit(.move(.left, .character, extend: false))])
        XCTAssertEqual(act(.command(.moveUp(extend: false)), typing("x")), [.edit(.moveUp(extend: false))])
    }

    func testTypingPaste() {
        XCTAssertEqual(act(.shortcut("v"), typing("x")), [.paste])
    }

    func testTypingCommandZDoesNotUndoStop() {
        XCTAssertEqual(act(.shortcut("z"), typing("x")), [])
    }

    func testTypingNewlinesInTextCollapse() {
        XCTAssertEqual(act(.text("a\nb"), typing()), [.insert("a b")])
    }

    // MARK: Whole flows

    /// Space toggles in control, is a space in typing; Return returns to control.
    func testSpaceRoutingAcrossModeSwitch() {
        var mode = InputMode.control
        var editor = LineEditor()
        var log: [OverlayAction] = []
        func send(_ input: KeyInput) {
            let actions = InputStateMachine.actions(for: input, in: .init(mode: mode, lineText: editor.text))
            log += actions
            for action in actions {
                switch action {
                case .enterTyping: mode = .typing
                case .exitTyping: mode = .control
                case .insert(let s): editor.insert(s)
                default: break
                }
            }
        }
        send(.text("A"))
        send(.space)
        send(.text("B"))
        XCTAssertEqual(editor.text, "A B")
        send(.returnKey)
        XCTAssertEqual(mode, .control)
        send(.space)
        XCTAssertEqual(log.last, .toggleTimer)
    }

    // MARK: Key auto-repeat

    func testControlIgnoresRepeatedToggleAndNavigationKeys() {
        let c = control("Denali", committed: true)
        for input: KeyInput in [.space, .returnKey, .escape, .text(" "),
                                .command(.move(.left, .character, extend: false)),
                                .command(.move(.right, .character, extend: false)),
                                .command(.moveUp(extend: false)), .command(.moveDown(extend: false))] {
            XCTAssertEqual(InputStateMachine.actions(for: input, in: c, isRepeat: true), [], "\(input)")
        }
        // The first press still acts.
        XCTAssertEqual(InputStateMachine.actions(for: .space, in: c, isRepeat: false), [.toggleTimer])
    }

    func testTypingKeepsRepeatedKeys() {
        let t = typing("ab")
        XCTAssertEqual(InputStateMachine.actions(for: .space, in: t, isRepeat: true), [.insert(" ")])
        XCTAssertEqual(InputStateMachine.actions(for: .command(.deleteBackward), in: t, isRepeat: true), [.deleteBackward])
        XCTAssertEqual(InputStateMachine.actions(for: .command(.move(.left, .character, extend: false)), in: t, isRepeat: true),
                       [.edit(.move(.left, .character, extend: false))])
        XCTAssertEqual(InputStateMachine.actions(for: .text("a"), in: t, isRepeat: true), [.insert("a")])
    }
}

/// `KeyCaptureView` forwards `NSEvent.isARepeat` with the inputs it produces.
@MainActor
final class KeyCaptureRepeatTests: XCTestCase {
    private final class Recorder: KeyCaptureDelegate {
        var received: [(KeyInput, Bool)] = []
        var editor = LineEditor()
        func keyCapture(_ input: KeyInput, isRepeat: Bool) { received.append((input, isRepeat)) }
        func editorDidChange() {}
        func caretRectInWindow() -> NSRect { .zero }
    }

    private func key(_ code: UInt16, _ chars: String, repeat isRepeat: Bool) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: isRepeat, keyCode: code)
    }

    func testSpaceRepeatFlagIsForwarded() throws {
        let view = KeyCaptureView(frame: .zero)
        let recorder = Recorder()
        view.delegate = recorder
        view.keyDown(with: try XCTUnwrap(key(49, " ", repeat: false)))
        view.keyDown(with: try XCTUnwrap(key(49, " ", repeat: true)))
        view.keyDown(with: try XCTUnwrap(key(36, "\r", repeat: true)))
        XCTAssertEqual(recorder.received.map(\.0), [.space, .space, .returnKey])
        XCTAssertEqual(recorder.received.map(\.1), [false, true, true])
        // Held Space in control mode toggles once.
        let toggles = recorder.received.flatMap {
            InputStateMachine.actions(for: $0.0, in: .init(mode: .control), isRepeat: $0.1)
        }
        XCTAssertEqual(toggles, [.toggleTimer])
    }
}
