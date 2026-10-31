import Foundation
import GrainsCore
@testable import GrainsReports

/// Every test uses this fixed calendar and time zone, never the machine's.
enum Fixtures {
    static let timeZone = TimeZone(identifier: "America/Anchorage")!

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    static var spec: WeekSpec { WeekSpec(startsOn: 2, calendar: calendar) }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static func entry(
        _ n: Int, _ start: Date, _ stop: Date?, client: String? = nil, raw: String = "work",
        deleted: Bool = false
    ) -> Entry {
        Entry(id: id(n), rawText: raw, clientText: client, startedAt: start, stoppedAt: stop,
              deletedAt: deleted ? start : nil)
    }

    static let hour: TimeInterval = 3600
}
