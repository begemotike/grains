import Foundation
import GrainsReports

/// Locale-independent date parsing and formatting for tool inputs and outputs, in one fixed
/// time zone (the `WeekSpec`'s). Output matches the CSV export: whole seconds, RFC 3339 with a
/// numeric offset (`+00:00`, never `Z`).
struct DateCoding: Sendable {
    let calendar: Calendar
    var timeZone: TimeZone { calendar.timeZone }

    init(timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        calendar = cal
    }

    // MARK: Formatting

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// `2026-10-27`
    func dateString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: Self.wholeSeconds(date))
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0, 2))-\(pad(c.day ?? 0, 2))"
    }

    /// `2026-10-27T09:14:03-08:00`
    func rfc3339(_ date: Date) -> String {
        let whole = Self.wholeSeconds(date)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        let offset = timeZone.secondsFromGMT(for: whole)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0, 2))-\(pad(c.day ?? 0, 2))T"
            + "\(pad(c.hour ?? 0, 2)):\(pad(c.minute ?? 0, 2)):\(pad(c.second ?? 0, 2))"
            + "\(sign)\(pad(minutes / 60, 2)):\(pad(minutes % 60, 2))"
    }

    private func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        return (value < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    // MARK: Parsing

    enum Bound { case start, end }

    /// Parses `YYYY-MM-DD` (a local day in this time zone) or an RFC 3339 timestamp
    /// (`YYYY-MM-DDTHH:MM:SS[.fff](Z|±HH:MM)`). A date-only value is the start of that day,
    /// or, for `.end`, the start of the next day (so `to: 2026-10-27` includes all of the 27th).
    func parse(_ text: String, as bound: Bound) -> Date? {
        let s = Array(text.trimmingCharacters(in: .whitespaces).utf8)
        guard s.count >= 10, let year = number(s, 0, 4), s[4] == UInt8(ascii: "-"),
              let month = number(s, 5, 2), s[7] == UInt8(ascii: "-"), let day = number(s, 8, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        if s.count == 10 {
            guard let start = validDate(year: year, month: month, day: day, hour: 0, minute: 0, second: 0, in: calendar) else { return nil }
            switch bound {
            case .start: return start
            case .end: return calendar.date(byAdding: .day, value: 1, to: start).map { calendar.startOfDay(for: $0) }
            }
        }

        // Time part.
        guard s.count >= 20, [UInt8(ascii: "T"), UInt8(ascii: "t"), UInt8(ascii: " ")].contains(s[10]),
              let hour = number(s, 11, 2), s[13] == UInt8(ascii: ":"), let minute = number(s, 14, 2),
              s[16] == UInt8(ascii: ":"), let second = number(s, 17, 2),
              hour < 24, minute < 60, second < 60 else { return nil }
        var i = 19
        var fraction = 0.0
        if s[i] == UInt8(ascii: ".") {
            i += 1
            let digitsStart = i
            while i < s.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(s[i]) { i += 1 }
            guard i > digitsStart, let f = Double("0." + String(decoding: s[digitsStart..<i], as: UTF8.self)) else { return nil }
            fraction = f
        }
        guard i < s.count else { return nil }
        let offsetSeconds: Int
        if s[i] == UInt8(ascii: "Z") || s[i] == UInt8(ascii: "z") {
            guard i + 1 == s.count else { return nil }
            offsetSeconds = 0
        } else if s[i] == UInt8(ascii: "+") || s[i] == UInt8(ascii: "-") {
            guard s.count == i + 6, let oh = number(s, i + 1, 2), s[i + 3] == UInt8(ascii: ":"),
                  let om = number(s, i + 4, 2), oh < 24, om < 60 else { return nil }
            offsetSeconds = (s[i] == UInt8(ascii: "-") ? -1 : 1) * (oh * 3600 + om * 60)
        } else {
            return nil
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let wall = validDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second, in: utc) else { return nil }
        return wall.addingTimeInterval(fraction - Double(offsetSeconds))
    }

    private func number(_ s: [UInt8], _ start: Int, _ length: Int) -> Int? {
        guard start + length <= s.count else { return nil }
        var value = 0
        for byte in s[start..<(start + length)] {
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    /// Builds a date and rejects impossible ones (Feb 30) instead of letting Calendar roll over.
    private func validDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, in cal: Calendar) -> Date? {
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = cal.date(from: comps) else { return nil }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        // A local midnight skipped by DST resolves to the first valid instant of that day.
        return date
    }

    // MARK: ISO weeks

    /// Resolves `2026-W44` to the `spec` week whose `isoIdentifier` is that id (the week whose
    /// first day lies in that ISO week, which is also the week the CSV file of that name covers).
    func week(isoIdentifier text: String, spec: WeekSpec) -> Week? {
        let s = Array(text.trimmingCharacters(in: .whitespaces).utf8)
        guard s.count == 8, let year = number(s, 0, 4), s[4] == UInt8(ascii: "-"),
              s[5] == UInt8(ascii: "W") || s[5] == UInt8(ascii: "w"), let weekNumber = number(s, 6, 2),
              (1...53).contains(weekNumber) else { return nil }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        let comps = DateComponents(hour: 12, weekday: 2, weekOfYear: weekNumber, yearForWeekOfYear: year)
        guard let monday = iso.date(from: comps) else { return nil }
        let check = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monday)
        guard check.yearForWeekOfYear == year, check.weekOfYear == weekNumber else { return nil }
        let id = "\(pad(year, 4))-W\(pad(weekNumber, 2))"
        let containing = spec.week(containing: monday)
        if containing.isoIdentifier == id { return containing }
        let next = containing.next(spec: spec)
        return next.isoIdentifier == id ? next : nil
    }
}
