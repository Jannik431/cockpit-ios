import Foundation
import Testing
@testable import Cockpit

struct LocalDayTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func nightIsAssignedToWakeDay() {
        // Sleep from 23:30 on 16.11. until 07:10 on 17.11. belongs to 17.11.
        let wake = date(2026, 11, 17, 7, 10)
        #expect(LocalDay.wakeDay(forSleepEndingAt: wake, calendar: berlin) == date(2026, 11, 17))
    }

    @Test func windowHasRequestedLengthAndOrder() {
        let days = LocalDay.window(endingAt: date(2026, 11, 17, 15), count: 7, calendar: berlin)
        #expect(days.count == 7)
        #expect(days.first == date(2026, 11, 11))
        #expect(days.last == date(2026, 11, 17))
    }

    @Test func windowAcrossDSTChangeKeepsMidnights() {
        // Clocks go back on 25.10.2026 in Germany (25-hour day).
        let days = LocalDay.window(endingAt: date(2026, 10, 27), count: 4, calendar: berlin)
        let hours = days.map { berlin.component(.hour, from: $0) }
        #expect(days.first == date(2026, 10, 24))
        #expect(hours == [0, 0, 0, 0])
    }

    @Test func emptyWindowForNonPositiveCount() {
        #expect(LocalDay.window(endingAt: .now, count: 0, calendar: berlin).isEmpty)
    }
}
