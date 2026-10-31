import Foundation
import GrainsCore

/// Tracked hours for one client label.
public struct ClientHours: Sendable, Hashable, Codable {
    /// Parsed client label exactly as captured; `nil` for entries without a client.
    public var clientText: String?
    /// Tracked hours (unrounded).
    public var hours: Double

    /// Creates a value.
    public init(clientText: String?, hours: Double) {
        self.clientText = clientText
        self.hours = hours
    }
}

/// The overlay's headline numbers. Everything is "as of `now`": time after `now` never counts.
public struct Stats: Sendable, Equatable {
    /// Tracked hours this week (overlaps counted once). Equals `WeekSeries.totalHours`.
    public var weekHours: Double
    /// Tracked hours within `today` up to `now`.
    public var todayHours: Double
    /// Elapsed seconds of the running entry, `nil` when nothing is running.
    public var sessionSeconds: TimeInterval?
    /// Hours per client label this week, descending by hours, ties by label (`nil` last).
    /// Clients with no time this week are omitted. Overlaps are merged within a client only.
    public var byClient: [ClientHours]

    /// Creates a value.
    public init(weekHours: Double, todayHours: Double, sessionSeconds: TimeInterval?, byClient: [ClientHours]) {
        self.weekHours = weekHours
        self.todayHours = todayHours
        self.sessionSeconds = sessionSeconds
        self.byClient = byClient
    }

    /// Computes the statistics. `today` is usually `spec.today(at: now)`.
    public static func compute(entries: [Entry], week: Week, today: DateInterval, now: Date) -> Stats {
        let live = entries.filter { !$0.isDeleted }
        let weekBounds = IntervalMath.upTo(week.interval, now: now)
        let todayBounds = IntervalMath.upTo(today, now: now)

        let weekMerged = IntervalMath.merge(IntervalMath.clipped(live, to: weekBounds, now: now))
        let todayMerged = IntervalMath.merge(IntervalMath.clipped(live, to: todayBounds, now: now))

        let running = live.filter(\.isRunning).max { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }

        var groups: [String?: [Entry]] = [:]
        for entry in live { groups[entry.clientText, default: []].append(entry) }
        var byClient: [ClientHours] = []
        for (client, group) in groups {
            let merged = IntervalMath.merge(IntervalMath.clipped(group, to: weekBounds, now: now))
            let seconds = merged.reduce(0) { $0 + $1.duration }
            if seconds > 0 { byClient.append(ClientHours(clientText: client, hours: seconds / 3600)) }
        }
        byClient.sort {
            $0.hours != $1.hours ? $0.hours > $1.hours : IntervalMath.clientPrecedes($0.clientText, $1.clientText)
        }

        return Stats(
            weekHours: weekMerged.reduce(0) { $0 + $1.duration } / 3600,
            todayHours: todayMerged.reduce(0) { $0 + $1.duration } / 3600,
            sessionSeconds: running.map { $0.duration(asOf: now) },
            byClient: byClient
        )
    }
}
