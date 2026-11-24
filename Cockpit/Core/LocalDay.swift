import Foundation

/// Calendar helpers. All metrics are stored per local calendar day (spec, section 5).
nonisolated enum LocalDay {
    /// Until this hour the app still treats the previous day as "today" (evening check after midnight).
    static let rolloverHour = 4

    /// The day the app shows and the evening check belongs to: before 04:00 that is still yesterday.
    static func logicalToday(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -rolloverHour, to: now) ?? now
        return calendar.startOfDay(for: shifted)
    }

    /// Start of the local calendar day that contains `date`.
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// A night is assigned to the day the person wakes up, i.e. the local day of the sleep end.
    static func wakeDay(forSleepEndingAt end: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: end)
    }

    /// The `count` local days ending with (and including) `day`, oldest first.
    /// Uses calendar arithmetic, so days with DST changes (23 h / 25 h) are handled correctly.
    static func window(endingAt day: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let last = calendar.startOfDay(for: day)
        return (0..<count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: last)
        }
    }
}
