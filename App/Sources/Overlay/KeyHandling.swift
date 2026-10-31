import Foundation

/// Which of the two overlay modes is active (D12, docs/interaction.md).
enum InputMode: Equatable, Sendable {
    /// Block caret; Space toggles the timer.
    case control
    /// Bar caret; Space is a space, Return commits.
    case typing
}

/// A text-editing command, normalized from AppKit's `doCommand(by:)` selectors.
enum EditCommand: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case left, right }
    enum Unit: Equatable, Sendable { case character, word, line }

    case deleteBackward
    case deleteForward
    case deleteWordBackward
    case deleteWordForward
    case deleteToLineStart
    case deleteToLineEnd
    case move(Direction, Unit, extend: Bool)
    case moveUp(extend: Bool)
    case moveDown(extend: Bool)
    case selectAll
}

/// One key event as the overlay sees it, independent of `NSEvent` so the state machine is
/// testable. Produced by `KeyCaptureView`.
enum KeyInput: Equatable, Sendable {
    /// Text committed by the input system (`insertText`): printable characters, dead-key and
    /// IME results. Space never arrives this way from the keyboard; it is `.space`.
    case text(String)
    case space
    case returnKey
    case escape
    /// A `doCommand(by:)` editing/movement command (arrows, ⌫, ⌥⌫, ⌘⌫, ⇧-arrows...).
    case command(EditCommand)
    /// ⌘ plus a key, lowercased (`"z"`, `"a"`, `"v"`, `"c"`, `"x"`, `","`, `"w"`).
    case shortcut(Character)
    /// The input system started marked text (dead key or IME composition).
    case composeBegan
}

/// What the overlay must do in response to a key. Executed in order by `OverlayController`.
enum OverlayAction: Equatable, Sendable {
    case toggleTimer
    case commit(String)
    case insert(String)
    case deleteBackward
    case edit(EditCommand)
    case paste
    case copy
    case cut
    case clearLine
    case hide
    case previousWeek
    case nextWeek
    /// +1 = older, -1 = newer.
    case cycleRecent(Int)
    case undoStop
    case resumeRecovered
    case acceptRecovered
    case enterTyping
    case exitTyping
    case openSettings
}

/// The control/typing state machine of docs/interaction.md, as a pure function.
/// It never touches AppKit, the engine or timers; the caller applies the actions.
enum InputStateMachine {
    /// Everything the machine needs to know about the overlay.
    struct Context: Equatable, Sendable {
        var mode: InputMode
        /// The line's current text.
        var lineText: String
        /// The line shows a committed/running/stopped/recalled entry's text rather than a draft,
        /// so the first printable character replaces it.
        var lineIsCommitted: Bool
        /// A recovered entry awaits R (resume) / A (accept).
        var hasRecovery: Bool

        init(mode: InputMode, lineText: String = "", lineIsCommitted: Bool = false, hasRecovery: Bool = false) {
            self.mode = mode
            self.lineText = lineText
            self.lineIsCommitted = lineIsCommitted
            self.hasRecovery = hasRecovery
        }

        var lineHasText: Bool { !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The actions for `input` in `context`.
    static func actions(for input: KeyInput, in context: Context) -> [OverlayAction] {
        switch context.mode {
        case .control: return control(input, context)
        case .typing: return typing(input, context)
        }
    }

    // MARK: Control mode

    private static func control(_ input: KeyInput, _ c: Context) -> [OverlayAction] {
        switch input {
        case .space:
            return [.toggleTimer]
        case .returnKey:
            return c.lineHasText ? [.toggleTimer] : []
        case .escape:
            return [.hide]
        case .text(let text):
            if c.hasRecovery, text.count == 1 {
                switch text.lowercased() {
                case "r": return [.resumeRecovered]
                case "a": return [.acceptRecovered]
                default: break
                }
            }
            let cleaned = LineEditor.singleLine(text)
            if cleaned.isEmpty { return [] }
            if cleaned.trimmingCharacters(in: .whitespaces).isEmpty { return [.toggleTimer] }
            return beginTyping(c) + [.insert(cleaned)]
        case .composeBegan:
            return beginTyping(c)
        case .command(let command):
            switch command {
            case .deleteBackward: return [.enterTyping, .deleteBackward]
            case .move(.left, .character, extend: false): return [.previousWeek]
            case .move(.right, .character, extend: false): return [.nextWeek]
            case .moveUp(extend: false): return [.cycleRecent(1)]
            case .moveDown(extend: false): return [.cycleRecent(-1)]
            default: return []
            }
        case .shortcut(let key):
            switch key {
            case "z": return [.undoStop]
            case ",": return [.openSettings]
            case "w": return [.hide]
            case "v": return beginTyping(c) + [.paste]
            case "c": return c.lineHasText ? [.copy] : []
            default: return []
            }
        }
    }

    /// Enter typing; a committed entry's text is cleared first (interaction.md).
    private static func beginTyping(_ c: Context) -> [OverlayAction] {
        c.lineIsCommitted ? [.enterTyping, .clearLine] : [.enterTyping]
    }

    // MARK: Typing mode

    private static func typing(_ input: KeyInput, _ c: Context) -> [OverlayAction] {
        switch input {
        case .space:
            return [.insert(" ")]
        case .returnKey:
            return c.lineHasText ? [.commit(c.lineText), .exitTyping] : [.exitTyping]
        case .escape:
            return [.exitTyping]
        case .text(let text):
            let cleaned = LineEditor.singleLine(text)
            return cleaned.isEmpty ? [] : [.insert(cleaned)]
        case .composeBegan:
            return []
        case .command(.deleteBackward):
            return [.deleteBackward]
        case .command(let command):
            return [.edit(command)]
        case .shortcut(let key):
            switch key {
            case "a": return [.edit(.selectAll)]
            case "v": return [.paste]
            case "c": return [.copy]
            case "x": return [.cut]
            case ",": return [.openSettings]
            case "w": return [.hide]
            default: return []
            }
        }
    }
}
