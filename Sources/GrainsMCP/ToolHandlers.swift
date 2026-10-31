import Foundation
import GrainsCore
import GrainsReports

extension MCPServer {
    func runTool(_ name: String, _ args: Arguments) throws -> ToolOutput {
        let now = options.now()
        switch name {
        case "list_sessions": return try listSessions(args, now: now)
        case "get_session": return try getSession(args, now: now)
        case "search_sessions": return try searchSessions(args, now: now)
        case "aggregate": return try aggregate(args, now: now)
        case "list_client_labels": return try listClientLabels(now: now)
        case "current_week": return try currentWeek(args, now: now)
        case "running_session": return try runningSession(now: now)
        case "list_exports": return try listExports()
        case "export_week": return try exportWeek(args, now: now)
        default: throw ToolFailure("Unknown tool \(name).")
        }
    }

    private var timeZoneID: JSONValue { .string(spec.calendar.timeZone.identifier) }

    // MARK: Range parsing

    func range(_ args: Arguments) throws -> DateInterval {
        let fromText = try args.requiredString("from")
        let toText = try args.requiredString("to")
        guard let from = dates.parse(fromText, as: .start) else {
            throw ToolFailure("\(args.tool): could not parse from \"\(fromText)\". Use \(Tools.dateFormatNote).")
        }
        guard let to = dates.parse(toText, as: .end) else {
            throw ToolFailure("\(args.tool): could not parse to \"\(toText)\". Use \(Tools.dateFormatNote).")
        }
        guard to > from else {
            throw ToolFailure("\(args.tool): \"to\" (\(dates.rfc3339(to))) must be after \"from\" (\(dates.rfc3339(from))).")
        }
        return DateInterval(start: from, end: to)
    }

    func rangeJSON(_ range: DateInterval) -> [String: JSONValue] {
        ["from": .string(dates.rfc3339(range.start)), "to": .string(dates.rfc3339(range.end)), "time_zone": timeZoneID]
    }

    // MARK: Entries

    /// Applies `--redact-notes` (D42): no note, raw_text replaced by the client label.
    func redacted(_ entry: Entry) -> Entry {
        guard options.redactNotes else { return entry }
        var copy = entry
        copy.rawText = entry.clientText ?? "[redacted]"
        copy.note = nil
        return copy
    }

    func sessionJSON(_ original: Entry, now: Date, within range: DateInterval? = nil) -> JSONValue {
        let entry = redacted(original)
        var object: [String: JSONValue] = [
            "id": .string(entry.id.uuidString),
            "raw_text": .string(entry.rawText),
            "client_text": .optional(entry.clientText),
            "client_id": .optional(entry.clientID?.uuidString),
            "started_at": .string(dates.rfc3339(entry.startedAt)),
            "stopped_at": .optional(entry.stoppedAt.map(dates.rfc3339)),
            "running": .bool(entry.isRunning),
            "duration_seconds": .double(entry.duration(asOf: now)),
            "recovered": .bool(entry.metadata.recovered.map { !$0.reconciled } ?? false),
        ]
        if !options.redactNotes { object["note"] = .optional(entry.note) }
        if let range { object["seconds_in_range"] = .double(entry.seconds(within: range, asOf: now)) }
        return .object(object)
    }

    // MARK: Tools

    private func listSessions(_ args: Arguments, now: Date) throws -> ToolOutput {
        let range = try range(args)
        let client = try args.string("client")
        let limit = try args.int("limit", default: 200, range: 1...1000)
        var entries = try store.entries(overlapping: range)
        if let client {
            entries = entries.filter { $0.clientText?.caseInsensitiveCompare(client) == .orderedSame }
        }
        let shown = entries.prefix(limit)
        var result = rangeJSON(range)
        result["client"] = .optional(client)
        result["count"] = .int(Int64(shown.count))
        result["total_matching"] = .int(Int64(entries.count))
        result["truncated"] = .bool(entries.count > shown.count)
        result["sessions"] = .array(shown.map { sessionJSON($0, now: now, within: range) })
        return .object(.object(result))
    }

    private func getSession(_ args: Arguments, now: Date) throws -> ToolOutput {
        let text = try args.requiredString("id")
        guard let id = UUID(uuidString: text.trimmingCharacters(in: .whitespaces)) else {
            throw ToolFailure("get_session: \"\(text)\" is not a session id (expected a UUID).")
        }
        guard let entry = try store.entry(id: id) else {
            throw ToolFailure("get_session: no session with id \(id.uuidString).")
        }
        return .object(["time_zone": timeZoneID, "session": sessionJSON(entry, now: now)])
    }

    private func searchSessions(_ args: Arguments, now: Date) throws -> ToolOutput {
        let query = try args.requiredString("query")
        let limit = try args.int("limit", default: 50, range: 1...500)
        let hits: [Entry]
        if options.redactNotes {
            // Matching on hidden text would leak it; only the visible label is searchable.
            // The store returns newest first; over-fetch then filter on client_text.
            hits = Array(try store.search(query, limit: Int.max / 2)
                .filter { $0.clientText?.range(of: query, options: .caseInsensitive) != nil }
                .prefix(limit))
        } else {
            hits = try store.search(query, limit: limit)
        }
        return .object([
            "query": .string(query),
            "time_zone": timeZoneID,
            "count": .int(Int64(hits.count)),
            "sessions": .array(hits.map { sessionJSON($0, now: now) }),
        ])
    }

    private func aggregate(_ args: Arguments, now: Date) throws -> ToolOutput {
        let requested = try range(args)
        let groupText = try args.requiredString("group_by")
        let groupBy: GroupBy
        switch groupText {
        case "day": groupBy = .day
        case "week": groupBy = .week
        case "client": groupBy = .client
        case "client_day", "clientDay": groupBy = .clientDay
        default: throw ToolFailure("aggregate: group_by must be one of day, week, client, client_day (got \"\(groupText)\").")
        }
        // Buckets outside the data are always empty, so clamp the range to [earliest entry, now + 1 week]
        // before bucketing: a "whole history" request (0001..9999) must not iterate millions of
        // calendar days and stall the single-threaded stdio loop.
        let dataStart = try store.earliestStart() ?? now
        let clampedStart = max(requested.start, dataStart)
        let clampedEnd = min(requested.end, now.addingTimeInterval(7 * 86_400))
        let range = clampedStart < clampedEnd ? DateInterval(start: clampedStart, end: clampedEnd) : DateInterval(start: clampedStart, duration: 0)
        let entries = range.duration > 0 ? try store.entries(overlapping: range) : []
        let rows = Aggregator.aggregate(entries: entries, range: range, groupBy: groupBy, spec: spec, now: now)
        // Day buckets are disjoint and merged within themselves, so their sum is the merged
        // total for the range, whatever group_by is (client rows may overlap each other).
        let totalSeconds = groupBy == .day
            ? rows.reduce(0) { $0 + $1.seconds }
            : Aggregator.aggregate(entries: entries, range: range, groupBy: .day, spec: spec, now: now).reduce(0) { $0 + $1.seconds }
        var result = rangeJSON(requested)
        result["group_by"] = .string(groupBy == .clientDay ? "client_day" : groupBy.rawValue)
        result["rows"] = .array(rows.map { row in
            [
                "key": .string(row.key),
                "client_text": .optional(row.clientText),
                "seconds": .double(row.seconds),
                "hours": .double(row.hours),
                "entry_count": .int(Int64(row.entryCount)),
            ]
        })
        result["total_seconds"] = .double(totalSeconds)
        result["total_hours"] = .double(Self.hours(totalSeconds))
        return .object(.object(result))
    }

    private func listClientLabels(now: Date) throws -> ToolOutput {
        var labels: [JSONValue] = try store.clientLabels().map { label in
            [
                "client_text": .string(label.clientText),
                "client_id": .optional(label.clientID?.uuidString),
                "entry_count": .int(Int64(label.count)),
                "total_seconds": .double(label.totalSeconds),
                "total_hours": .double(Self.hours(label.totalSeconds)),
            ]
        }
        // `clientLabels()` leaves out unlabeled entries; the spec wants them as one null row.
        if let earliest = try store.earliestStart() {
            let unlabeled = try store.entries(overlapping: DateInterval(start: earliest, end: .distantFuture))
                .filter { $0.clientText == nil }
            if !unlabeled.isEmpty {
                let seconds = unlabeled.reduce(0) { $0 + $1.duration(asOf: now) }
                labels.append([
                    "client_text": .null,
                    "client_id": .null,
                    "entry_count": .int(Int64(unlabeled.count)),
                    "total_seconds": .double(seconds),
                    "total_hours": .double(Self.hours(seconds)),
                ])
            }
        }
        return .object(["count": .int(Int64(labels.count)), "labels": .array(labels)])
    }

    private func currentWeek(_ args: Arguments, now: Date) throws -> ToolOutput {
        let target = try args.double("target_hours", range: 0...168)
        let week = spec.week(containing: now)
        let entries = try store.entries(overlapping: week.interval)
        let series = WeekSeries.compute(entries: entries, week: week, now: now, targetHours: target)
        var result: [String: JSONValue] = [
            "week": .string(week.isoIdentifier),
            "start": .string(dates.rfc3339(week.interval.start)),
            "end": .string(dates.rfc3339(week.interval.end)),
            "now": .string(dates.rfc3339(now)),
            "time_zone": timeZoneID,
            "total_hours": .double(Self.round(series.totalHours, places: 2)),
            "elapsed_fraction": .double(Self.round(series.elapsedFraction, places: 4)),
            "week_length_hours": .double(Self.round(week.interval.duration / 3600, places: 2)),
            "days": .array(zip(week.days, series.dailyHours).map { day, hours in
                ["date": .string(dates.dateString(day.start)), "hours": .double(Self.round(hours, places: 2))]
            }),
            "running": .bool(entries.contains(where: \.isRunning)),
            "target_hours": .optional(target),
        ]
        if let target {
            result["target_hours_at_now"] = .double(Self.round(target * series.elapsedFraction, places: 2))
        }
        return .object(.object(result))
    }

    private func runningSession(now: Date) throws -> ToolOutput {
        let running = try store.runningEntry()
        return .object([
            "time_zone": timeZoneID,
            "now": .string(dates.rfc3339(now)),
            "running": running.map { sessionJSON($0, now: now) } ?? .null,
            "elapsed_seconds": running.map { .double($0.duration(asOf: now)) } ?? .null,
        ])
    }

    private func listExports() throws -> ToolOutput {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: exportDirectory.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
        var files: [JSONValue] = []
        if exists {
            let urls = try fm.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                guard name.hasPrefix("Grains-"), name.lowercased().hasSuffix(".csv") else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile ?? true else { continue }
                files.append([
                    "name": .string(name),
                    "week": .optional(Self.weekID(inFileName: name)),
                    "size_bytes": .int(Int64(values?.fileSize ?? 0)),
                    "modified": .optional(values?.contentModificationDate.map(dates.rfc3339)),
                ])
            }
        }
        return .object([
            "export_directory": .string(exportDirectory.path(percentEncoded: false)),
            "exists": .bool(exists),
            "time_zone": timeZoneID,
            "count": .int(Int64(files.count)),
            "files": .array(files),
        ])
    }

    private func exportWeek(_ args: Arguments, now: Date) throws -> ToolOutput {
        let text = try args.requiredString("week")
        guard let week = dates.week(isoIdentifier: text, spec: spec) else {
            throw ToolFailure("export_week: \"\(text)\" is not a valid ISO week id (expected YYYY-Www, for example 2026-W44).")
        }
        // Widen by one second at the start so a zero-length entry at the very start of the
        // week (kept by the CSV rules, D32) is fetched; CSVExporter does the exact filtering.
        let fetch = DateInterval(start: week.interval.start.addingTimeInterval(-1), end: week.interval.end)
        let entries = try store.entries(overlapping: fetch).map(redacted)
        let csv = CSVExporter(spec: spec).csv(for: week, entries: entries, now: now)
        let rowCount = Self.csvRecordCount(csv) - 1
        return .text(csv, structured: [
            "week": .string(week.isoIdentifier),
            "file_name": .string(CSVExporter.fileName(for: week)),
            "start": .string(dates.rfc3339(week.interval.start)),
            "end": .string(dates.rfc3339(week.interval.end)),
            "time_zone": timeZoneID,
            "row_count": .int(Int64(max(0, rowCount))),
            "csv": .string(csv),
        ])
    }

    // MARK: Number helpers

    /// `seconds / 3600` rounded to 2 decimals, the same rule as `AggregateRow.hours`.
    static func hours(_ seconds: TimeInterval) -> Double {
        (seconds / 36).rounded() / 100
    }

    static func round(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    /// `Grains-2026-W44.csv` → `2026-W44`.
    static func weekID(inFileName name: String) -> String? {
        let body = name.dropFirst("Grains-".count)
        guard body.count >= 8 else { return nil }
        let id = String(body.prefix(8))
        let chars = Array(id)
        guard chars[4] == "-", chars[5] == "W",
              chars.enumerated().allSatisfy({ i, c in i == 4 || i == 5 || c.isASCII && c.isNumber }) else { return nil }
        return id
    }
}

extension MCPServer {
    /// Number of CSV records in `csv`, counting newlines only outside quoted fields
    /// (a note may legitimately contain a line break inside quotes).
    static func csvRecordCount(_ csv: String) -> Int {
        var count = 0
        var inQuotes = false
        var sawContentOnLine = false
        for scalar in csv.unicodeScalars {
            switch scalar {
            case "\"": inQuotes.toggle(); sawContentOnLine = true
            case "\n" where !inQuotes:
                if sawContentOnLine { count += 1 }
                sawContentOnLine = false
            default: sawContentOnLine = true
            }
        }
        if sawContentOnLine { count += 1 }
        return count
    }
}
