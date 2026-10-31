import Foundation

/// Display formatting for numbers that `GrainsReports` computed. Formatting only, never math.
enum Formatting {
    /// `HH:MM:SS`; hours are not capped at 24 (long sessions read `27:03:10`).
    static func clock(_ duration: Duration) -> String {
        clock(seconds: Int(duration.components.seconds))
    }

    /// `HH:MM:SS` for whole seconds (negative clamps to zero).
    static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// `HH:MM` for the menu bar title.
    static func shortClock(_ duration: Duration) -> String {
        let s = max(0, Int(duration.components.seconds))
        return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// Hours with one decimal (`23.7`), POSIX decimal point.
    static func hours(_ hours: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), max(0, hours))
    }

    /// `14:02` local time.
    static func time(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
