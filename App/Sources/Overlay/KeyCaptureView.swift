import AppKit

/// What `KeyCaptureView` needs from its owner: somewhere to send keys, and the line buffer
/// for the text input system (marked text, ranges, caret rectangle).
@MainActor
protocol KeyCaptureDelegate: AnyObject {
    /// `isRepeat`: the key event is an auto-repeat (`NSEvent.isARepeat`).
    func keyCapture(_ input: KeyInput, isRepeat: Bool)
    var editor: LineEditor { get set }
    func editorDidChange()
    /// Caret rectangle in window coordinates, for IME candidate windows.
    func caretRectInWindow() -> NSRect
    /// Accessibility hint for the line (the inline completion, D67); never part of the value.
    var editorAccessibilityHint: String? { get }
}

extension KeyCaptureDelegate {
    var editorAccessibilityHint: String? { nil }
}

/// The overlay's first responder. Turns `NSEvent`s into `KeyInput` deterministically:
/// Space/Return/Escape by key code, ⌘ shortcuts in `performKeyEquivalent`, everything else
/// through `interpretKeyEvents` so key bindings, dead keys and IMEs work (`NSTextInputClient`).
/// No `TextField` is involved, so nothing needs a click and Space never leaks into a field.
final class KeyCaptureView: NSView, @preconcurrency NSTextInputClient {
    weak var delegate: (any KeyCaptureDelegate)?

    /// ⌘ shortcuts the overlay handles (lowercased `charactersIgnoringModifiers`).
    static let shortcutKeys: Set<Character> = ["z", "a", "v", "c", "x", ",", "w"]

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override var isFlipped: Bool { true }

    // MARK: Key events

    /// Whether the key event being handled is an auto-repeat; inputs produced while handling
    /// it (directly or via `interpretKeyEvents`) carry the flag.
    private var handlingRepeat = false

    private func send(_ input: KeyInput) {
        delegate?.keyCapture(input, isRepeat: handlingRepeat)
    }

    override func keyDown(with event: NSEvent) {
        handlingRepeat = event.isARepeat
        defer { handlingRepeat = false }
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !mods.contains(.command) && !mods.contains(.control) {
            switch event.keyCode {
            case 49: send(.space); return
            case 36, 76: send(.returnKey); return
            case 53: send(.escape); return
            default: break
            }
        }
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.isKeyWindow == true, !hasMarkedText() else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.control), !mods.contains(.option), !mods.contains(.shift),
              let key = event.charactersIgnoringModifiers?.lowercased().first,
              Self.shortcutKeys.contains(key) else { return false }
        delegate?.keyCapture(.shortcut(key), isRepeat: event.isARepeat)
        return true
    }

    override func doCommand(by selector: Selector) {
        let name = NSStringFromSelector(selector)
        if let command = Self.editCommands[name] {
            send(.command(command))
        } else if name == "insertNewline:" || name == "insertLineBreak:" {
            send(.returnKey)
        } else if name == "cancelOperation:" {
            send(.escape)
        } else if name == "insertTab:" {
            send(.tab)
        }
        // Everything else (insertBacktab:, noop:, ...) is ignored without a beep.
    }

    /// AppKit standard key-binding selectors → editing commands.
    static let editCommands: [String: EditCommand] = [
        "moveLeft:": .move(.left, .character, extend: false),
        "moveBackward:": .move(.left, .character, extend: false),
        "moveRight:": .move(.right, .character, extend: false),
        "moveForward:": .move(.right, .character, extend: false),
        "moveLeftAndModifySelection:": .move(.left, .character, extend: true),
        "moveBackwardAndModifySelection:": .move(.left, .character, extend: true),
        "moveRightAndModifySelection:": .move(.right, .character, extend: true),
        "moveForwardAndModifySelection:": .move(.right, .character, extend: true),
        "moveWordLeft:": .move(.left, .word, extend: false),
        "moveWordBackward:": .move(.left, .word, extend: false),
        "moveWordRight:": .move(.right, .word, extend: false),
        "moveWordForward:": .move(.right, .word, extend: false),
        "moveWordLeftAndModifySelection:": .move(.left, .word, extend: true),
        "moveWordBackwardAndModifySelection:": .move(.left, .word, extend: true),
        "moveWordRightAndModifySelection:": .move(.right, .word, extend: true),
        "moveWordForwardAndModifySelection:": .move(.right, .word, extend: true),
        "moveToBeginningOfLine:": .move(.left, .line, extend: false),
        "moveToLeftEndOfLine:": .move(.left, .line, extend: false),
        "moveToBeginningOfParagraph:": .move(.left, .line, extend: false),
        "moveToBeginningOfDocument:": .move(.left, .line, extend: false),
        "moveToEndOfLine:": .move(.right, .line, extend: false),
        "moveToRightEndOfLine:": .move(.right, .line, extend: false),
        "moveToEndOfParagraph:": .move(.right, .line, extend: false),
        "moveToEndOfDocument:": .move(.right, .line, extend: false),
        "moveToBeginningOfLineAndModifySelection:": .move(.left, .line, extend: true),
        "moveToLeftEndOfLineAndModifySelection:": .move(.left, .line, extend: true),
        "moveToBeginningOfDocumentAndModifySelection:": .move(.left, .line, extend: true),
        "moveToEndOfLineAndModifySelection:": .move(.right, .line, extend: true),
        "moveToRightEndOfLineAndModifySelection:": .move(.right, .line, extend: true),
        "moveToEndOfDocumentAndModifySelection:": .move(.right, .line, extend: true),
        "moveUp:": .moveUp(extend: false),
        "moveDown:": .moveDown(extend: false),
        "moveUpAndModifySelection:": .moveUp(extend: true),
        "moveDownAndModifySelection:": .moveDown(extend: true),
        "deleteBackward:": .deleteBackward,
        "deleteBackwardByDecomposingPreviousCharacter:": .deleteBackward,
        "deleteForward:": .deleteForward,
        "deleteWordBackward:": .deleteWordBackward,
        "deleteWordForward:": .deleteWordForward,
        "deleteToBeginningOfLine:": .deleteToLineStart,
        "deleteToBeginningOfParagraph:": .deleteToLineStart,
        "deleteToEndOfLine:": .deleteToLineEnd,
        "deleteToEndOfParagraph:": .deleteToLineEnd,
        "selectAll:": .selectAll,
    ]

    // Edit-menu actions, in case a menu routes them here.
    @objc func paste(_ sender: Any?) { send(.shortcut("v")) }
    @objc func copy(_ sender: Any?) { send(.shortcut("c")) }
    @objc func cut(_ sender: Any?) { send(.shortcut("x")) }
    override func selectAll(_ sender: Any?) { send(.shortcut("a")) }

    // MARK: NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = Self.plain(string)
        guard let delegate else { return }
        if delegate.editor.markedRange != nil {
            // Finishing a composition: the mode switch already happened in setMarkedText.
            delegate.editor.insert(text)
            delegate.editorDidChange()
        } else {
            send(.text(text))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let delegate else { return }
        if delegate.editor.markedRange == nil {
            send(.composeBegan)
        }
        delegate.editor.setMarked(Self.plain(string), selection: selectedRange)
        delegate.editorDidChange()
    }

    func unmarkText() {
        delegate?.editor.unmark()
        delegate?.editorDidChange()
    }

    func selectedRange() -> NSRange {
        delegate?.editor.selectedRange ?? NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        delegate?.editor.markedRange ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        delegate?.editor.markedRange != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let text = delegate?.editor.text else { return nil }
        let ns = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        actualRange?.pointee = clamped
        return NSAttributedString(string: ns.substring(with: clamped))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        guard let window, let rect = delegate?.caretRectInWindow() else { return .zero }
        return window.convertToScreen(rect)
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    private static func plain(_ string: Any) -> String {
        (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
    override func accessibilityValue() -> Any? { delegate?.editor.text }
    override func accessibilityLabel() -> String? { "Entry" }
    override func accessibilityHelp() -> String? { delegate?.editorAccessibilityHint }
}
