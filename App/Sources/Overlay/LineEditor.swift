import Foundation

/// The single-line text buffer behind the entry line: text, caret/anchor selection and
/// marked (composing) text. Positions are UTF-16 offsets because `NSTextInputClient` speaks
/// `NSRange`; every edit snaps to composed-character boundaries, so emoji and accented
/// letters are never split. Pure value type; no AppKit.
struct LineEditor: Equatable, Sendable {
    private(set) var text: String = ""
    /// Where the caret is (the moving end of the selection).
    private(set) var caret: Int = 0
    /// The fixed end of the selection; equal to `caret` when nothing is selected.
    private(set) var anchor: Int = 0
    /// Range of composing text from a dead key or an IME, if any.
    private(set) var markedRange: NSRange?

    init(text: String = "") {
        self.text = Self.singleLine(text)
        caret = (self.text as NSString).length
        anchor = caret
    }

    var length: Int { (text as NSString).length }
    var selectedRange: NSRange { NSRange(location: min(caret, anchor), length: abs(caret - anchor)) }
    var hasSelection: Bool { caret != anchor }
    var isEmpty: Bool { text.isEmpty }
    var selectedText: String { (text as NSString).substring(with: selectedRange) }

    /// Newlines and tabs collapse to single spaces (paste, IME), other control characters drop.
    static func singleLine(_ s: String) -> String {
        var out = ""
        var lastWasBreak = false
        for ch in s {
            if ch.isNewline || ch == "\t" {
                if !lastWasBreak { out.append(" ") }
                lastWasBreak = true
                continue
            }
            lastWasBreak = false
            if ch.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) { continue }
            out.append(ch)
        }
        return out
    }

    // MARK: Whole-line operations

    /// Replace everything, caret at the end.
    mutating func set(_ newText: String) {
        self = LineEditor(text: newText)
    }

    mutating func clear() { set("") }

    // MARK: Insertion and composition

    /// Insert text over the marked range or the selection.
    mutating func insert(_ raw: String) {
        let s = Self.singleLine(raw)
        let target = markedRange ?? selectedRange
        replace(target, with: s)
        markedRange = nil
    }

    /// Paste: same as insert after collapsing newlines.
    mutating func paste(_ raw: String) { insert(raw) }

    /// `setMarkedText`: replace the marked range (or selection) with composing text.
    /// `selection` is relative to `marked`.
    mutating func setMarked(_ raw: String, selection: NSRange) {
        let s = Self.singleLine(raw)
        let target = markedRange ?? selectedRange
        replace(target, with: s)
        let len = (s as NSString).length
        markedRange = len == 0 ? nil : NSRange(location: target.location, length: len)
        let pos = target.location + min(max(0, selection.location), len)
        caret = min(pos + max(0, selection.length), length)
        anchor = pos
    }

    /// `unmarkText`: keep the composed text as ordinary text.
    mutating func unmark() { markedRange = nil }

    /// Removes the current selection (for cut). Returns the removed text.
    @discardableResult
    mutating func deleteSelection() -> String {
        let removed = selectedText
        if hasSelection { replace(selectedRange, with: "") }
        return removed
    }

    // MARK: Commands

    mutating func apply(_ command: EditCommand) {
        markedRange = nil
        switch command {
        case .deleteBackward:
            if hasSelection { replace(selectedRange, with: ""); return }
            guard caret > 0 else { return }
            let r = ns.rangeOfComposedCharacterSequence(at: caret - 1)
            replace(r, with: "")
        case .deleteForward:
            if hasSelection { replace(selectedRange, with: ""); return }
            guard caret < length else { return }
            replace(ns.rangeOfComposedCharacterSequence(at: caret), with: "")
        case .deleteWordBackward:
            if hasSelection { replace(selectedRange, with: ""); return }
            let start = wordBoundary(from: caret, direction: .left)
            replace(NSRange(location: start, length: caret - start), with: "")
        case .deleteWordForward:
            if hasSelection { replace(selectedRange, with: ""); return }
            let end = wordBoundary(from: caret, direction: .right)
            replace(NSRange(location: caret, length: end - caret), with: "")
        case .deleteToLineStart:
            if hasSelection { replace(selectedRange, with: ""); return }
            replace(NSRange(location: 0, length: caret), with: "")
        case .deleteToLineEnd:
            if hasSelection { replace(selectedRange, with: ""); return }
            replace(NSRange(location: caret, length: length - caret), with: "")
        case .move(let direction, let unit, let extend):
            move(direction, unit, extend: extend)
        case .moveUp(let extend):
            move(.left, .line, extend: extend)
        case .moveDown(let extend):
            move(.right, .line, extend: extend)
        case .selectAll:
            anchor = 0
            caret = length
        }
    }

    // MARK: Internals

    private var ns: NSString { text as NSString }

    private mutating func replace(_ range: NSRange, with s: String) {
        let location = min(max(0, range.location), length)
        let safe = NSRange(location: location, length: min(max(0, range.length), length - location))
        text = ns.replacingCharacters(in: safe, with: s)
        caret = safe.location + (s as NSString).length
        anchor = caret
    }

    private mutating func move(_ direction: EditCommand.Direction, _ unit: EditCommand.Unit, extend: Bool) {
        if !extend, hasSelection, unit == .character {
            caret = direction == .left ? selectedRange.location : NSMaxRange(selectedRange)
            anchor = caret
            return
        }
        let target: Int
        switch (unit, direction) {
        case (.character, .left):
            target = caret > 0 ? ns.rangeOfComposedCharacterSequence(at: caret - 1).location : 0
        case (.character, .right):
            target = caret < length ? NSMaxRange(ns.rangeOfComposedCharacterSequence(at: caret)) : length
        case (.word, let d):
            target = wordBoundary(from: caret, direction: d)
        case (.line, .left):
            target = 0
        case (.line, .right):
            target = length
        }
        caret = target
        if !extend { anchor = caret }
    }

    /// Option-arrow semantics: skip separators, then a run of word characters.
    private func wordBoundary(from position: Int, direction: EditCommand.Direction) -> Int {
        var pos = position
        func isWord(_ range: NSRange) -> Bool {
            let piece = ns.substring(with: range)
            return piece.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }
        switch direction {
        case .left:
            var seenWord = false
            while pos > 0 {
                let r = ns.rangeOfComposedCharacterSequence(at: pos - 1)
                let word = isWord(r)
                if seenWord && !word { break }
                if word { seenWord = true }
                pos = r.location
            }
        case .right:
            var seenWord = false
            while pos < length {
                let r = ns.rangeOfComposedCharacterSequence(at: pos)
                let word = isWord(r)
                if seenWord && !word { break }
                if word { seenWord = true }
                pos = NSMaxRange(r)
            }
        }
        return pos
    }
}
