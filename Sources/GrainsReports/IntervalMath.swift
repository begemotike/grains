import Foundation
import GrainsCore

/// Internal interval helpers shared by the series, stats and aggregator.
enum IntervalMath {
    /// Each non-deleted entry clipped to `bounds` (running entries end at `now`), empty ones dropped.
    /// Same arithmetic as `Entry.seconds(within:asOf:)`.
    static func clipped(_ entries: [Entry], to bounds: DateInterval, now: Date) -> [DateInterval] {
        var out: [DateInterval] = []
        for entry in entries where !entry.isDeleted {
            let start = max(entry.startedAt, bounds.start)
            let end = min(entry.stoppedAt ?? now, bounds.end)
            if end > start { out.append(DateInterval(start: start, end: end)) }
        }
        return out
    }

    /// Sorts and merges overlapping or touching intervals so overlapping time is counted once.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var out: [DateInterval] = []
        for iv in sorted {
            if let last = out.last, iv.start <= last.end {
                if iv.end > last.end { out[out.count - 1] = DateInterval(start: last.start, end: iv.end) }
            } else {
                out.append(iv)
            }
        }
        return out
    }

    /// Total seconds of (already merged) `intervals` inside `bounds`.
    static func seconds(of intervals: [DateInterval], within bounds: DateInterval) -> TimeInterval {
        var total: TimeInterval = 0
        for iv in intervals {
            let start = max(iv.start, bounds.start)
            let end = min(iv.end, bounds.end)
            if end > start { total += end.timeIntervalSince(start) }
        }
        return total
    }

    /// `bounds` truncated so it never extends past `now` (empty if `now` is before it).
    static func upTo(_ bounds: DateInterval, now: Date) -> DateInterval {
        DateInterval(start: bounds.start, end: min(max(now, bounds.start), bounds.end))
    }

    /// Deterministic ordering for optional client labels: named clients ascending, `nil` last.
    static func clientPrecedes(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case let (x?, y?): return x < y
        case (.some, nil): return true
        default: return false
        }
    }
}
