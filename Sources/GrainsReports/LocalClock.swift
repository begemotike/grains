import Foundation

/// Locale-independent wall-clock formatting in a fixed time zone (Gregorian, whole seconds).
/// Used instead of `DateFormatter`/`ISO8601DateFormatter` so output never depends on the
/// user's locale, calendar or fractional-second options.
struct LocalClock: Sendable {
    let calendar: Calendar

    init(timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        calendar = cal
    }

    /// Whole Unix seconds, truncated toward negative infinity.
    static func wholeSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    private func components(_ date: Date) -> DateComponents {
        let whole = Date(timeIntervalSince1970: Double(Self.wholeSeconds(date)))
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
    }

    /// `2026-10-27`
    func dateString(_ date: Date) -> String {
        let c = components(date)
        return "\(Self.pad(c.year ?? 0, 4))-\(Self.pad(c.month ?? 0, 2))-\(Self.pad(c.day ?? 0, 2))"
    }

    /// `09:14:03`
    func timeString(_ date: Date) -> String {
        let c = components(date)
        return "\(Self.pad(c.hour ?? 0, 2)):\(Self.pad(c.minute ?? 0, 2)):\(Self.pad(c.second ?? 0, 2))"
    }

    /// `2026-10-27T09:14:03-08:00` (UTC is written `+00:00`).
    func rfc3339(_ date: Date) -> String {
        let whole = Date(timeIntervalSince1970: Double(Self.wholeSeconds(date)))
        let offset = calendar.timeZone.secondsFromGMT(for: whole)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(dateString(date))T\(timeString(date))\(sign)\(Self.pad(minutes / 60, 2)):\(Self.pad(minutes % 60, 2))"
    }

    /// Zero-pads a non-negative integer to `width` digits.
    static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return value < 0 ? "-" + padded : padded
    }
}
