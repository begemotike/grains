import GrainsCore
import XCTest
@testable import Grains

/// The pure inline-completion rules (D67).
final class AutocompleteTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// `hoursAgo` larger = older.
    private func entry(_ raw: String, hoursAgo: Double, deleted: Bool = false) -> Entry {
        let parsed = EntryParser.parse(raw)
        let start = base.addingTimeInterval(-hoursAgo * 3600)
        return Entry(rawText: raw, clientText: parsed.clientText, note: parsed.note, startedAt: start,
                     stoppedAt: start.addingTimeInterval(1800), deletedAt: deleted ? start : nil)
    }

    private func label(_ text: String, count: Int = 1) -> ClientLabelCount {
        ClientLabelCount(clientText: text, clientID: nil, count: count, totalSeconds: 0)
    }

    private func source(_ entries: [Entry], labels: [ClientLabelCount] = []) -> Autocomplete.Source {
        Autocomplete.Source(entries: entries, labels: labels)
    }

    func testPrefixMatchReturnsRemainder() {
        let s = source([entry("Administrative work", hoursAgo: 1)])
        XCTAssertEqual(s.suggestion(for: "Adm"), "inistrative work")
        XCTAssertNil(s.suggestion(for: "work"))
    }

    func testMostRecentWins() {
        let s = source([entry("Denali - Shared iPad cart setup", hoursAgo: 30),
                        entry("Denali - iPad enrollment issue", hoursAgo: 2),
                        entry("Denali - Old thing", hoursAgo: 90)])
        XCTAssertEqual(s.suggestion(for: "Denali - "), "iPad enrollment issue")
        XCTAssertEqual(s.suggestion(for: "Denali - S"), "hared iPad cart setup")
    }

    func testClientLabelPhaseBeforeSeparator() {
        let entries = [entry("Denali - iPad enrollment issue", hoursAgo: 2)]
        let s = source(entries, labels: [label("Denali")])
        XCTAssertEqual(s.suggestion(for: "Den"), "ali - ")
        XCTAssertEqual(s.suggestion(for: "Denali"), " - ")
        XCTAssertEqual(s.suggestion(for: "Denali -"), " ")
        // Past the separator the full raw text completes.
        XCTAssertEqual(s.suggestion(for: "Denali - "), "iPad enrollment issue")
    }

    func testClientLabelPhaseUsesMostRecentlyUsedLabel() {
        let entries = [entry("Spruce - Policy engine", hoursAgo: 1),
                       entry("Spring Co - Audit", hoursAgo: 40),
                       entry("Sprocket - Fix", hoursAgo: 80)]
        let labels = [label("Sprocket", count: 9), label("Spring Co", count: 3), label("Spruce", count: 1)]
        XCTAssertEqual(source(entries, labels: labels).suggestion(for: "Spr"), "uce - ")
        XCTAssertEqual(source(entries, labels: labels).suggestion(for: "Spri"), "ng Co - ")
    }

    func testClientLabelUsesStoredSpelling() {
        let s = source([entry("ACME corp - x", hoursAgo: 1)], labels: [label("ACME corp")])
        XCTAssertEqual(s.suggestion(for: "acme c"), "orp - ")
    }

    func testFallsBackToRawTextWhenNoLabelMatches() {
        let s = source([entry("Administrative work", hoursAgo: 1), entry("Denali - x", hoursAgo: 2)],
                       labels: [label("Denali")])
        XCTAssertEqual(s.suggestion(for: "adm"), "inistrative work")
    }

    func testExactMatchIsExcluded() {
        let s = source([entry("Administrative work", hoursAgo: 1), entry("Administrative work - email", hoursAgo: 5)])
        XCTAssertEqual(s.suggestion(for: "Administrative work"), " - email")
        XCTAssertNil(source([entry("Administrative work", hoursAgo: 1)]).suggestion(for: "administrative WORK"))
        XCTAssertNil(source([], labels: [label("Denali")]).suggestion(for: "Denali - "))
    }

    func testDeletedEntriesAreExcluded() {
        let s = source([entry("Denali - secret", hoursAgo: 1, deleted: true), entry("Denali - visible", hoursAgo: 5)])
        XCTAssertEqual(s.suggestion(for: "Denali - "), "visible")
        XCTAssertNil(source([entry("Gone", hoursAgo: 1, deleted: true)]).suggestion(for: "Go"))
    }

    func testCaseInsensitive() {
        let s = source([entry("Global Credit Union - Jamf certificate troubleshooting", hoursAgo: 1)])
        XCTAssertEqual(s.suggestion(for: "global credit union - JAMF cert"), "ificate troubleshooting")
    }

    func testEmptyInputHasNoSuggestion() {
        let s = source([entry("Denali - x", hoursAgo: 1)], labels: [label("Denali")])
        XCTAssertNil(s.suggestion(for: ""))
        XCTAssertNil(s.suggestion(for: "   "))
        XCTAssertNil(Autocomplete.Source.empty.suggestion(for: "Den"))
    }

    func testDuplicateRawTextsCollapse() {
        let s = source([entry("A - one", hoursAgo: 1), entry("A - one", hoursAgo: 2), entry("A - two", hoursAgo: 3)])
        XCTAssertEqual(s.rawTexts, ["A - one", "A - two"])
    }
}

/// The model's cached completion respects mode, caret position and the setting.
@MainActor
final class AppModelCompletionTests: XCTestCase {
    private func makeModel(suggest: Bool = true) throws -> AppModel {
        let now = Date()
        let start = now.addingTimeInterval(-7200)
        let entries = [Entry(capturing: "Denali - iPad enrollment issue", at: start)].map {
            var e = $0
            e.stoppedAt = start.addingTimeInterval(1800)
            return e
        }
        let store = InMemoryEntryStore(entries: entries)
        let name = "GrainsAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults, environment: [:], defaultExportFolder: "/tmp/x")
        settings.suggestPreviousEntries = suggest
        return AppModel(store: store, engine: TimerEngine(store: store), settings: settings, now: now)
    }

    func testCompletionInTypingModeAtLineEnd() throws {
        let model = try makeModel()
        model.line.set("Den")
        XCTAssertNil(model.completion, "control mode shows no ghost text")
        model.mode = .typing
        XCTAssertEqual(model.completion, "ali - ")
        XCTAssertEqual(model.inputContext.completion, "ali - ")
        model.line.apply(.move(.left, .character, extend: false))
        XCTAssertNil(model.completion)
        XCTAssertFalse(model.inputContext.caretAtEnd)
    }

    func testSettingOffHidesCompletion() throws {
        let model = try makeModel(suggest: false)
        model.mode = .typing
        model.line.set("Den")
        XCTAssertNil(model.completion)
        XCTAssertEqual(InputStateMachine.actions(for: .tab, in: model.inputContext), [])
    }
}
