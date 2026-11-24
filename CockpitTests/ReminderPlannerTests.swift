import Foundation
import Testing
@testable import Cockpit

struct ReminderPlannerTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Monday, 16 Nov 2026.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func todays(_ reminders: [PlannedReminder]) -> [PlannedReminder] {
        reminders.filter { berlin.isDate($0.date, inSameDayAs: date(16, 12)) }
    }

    @Test func mondayEarlyGetsWeighInMorningAndEvening() {
        let reminders = ReminderPlanner.dailyReminders(now: date(16, 7), status: [:], calendar: berlin)
        let today = todays(reminders)
        #expect(today.map(\.route) == [ReminderRoute.weighIn, ReminderRoute.morning, ReminderRoute.midday, ReminderRoute.evening])
        #expect(today.map(\.date) == [date(16, 8, 30), date(16, 9), date(16, 13, 30), date(16, 22, 30)])
    }

    @Test func pastTimesAndDoneChecksAreSkipped() {
        var status = ReminderDayStatus()
        status.eveningComplete = true
        status.middayAnswered = true
        let reminders = ReminderPlanner.dailyReminders(now: date(16, 10), status: [date(16, 0): status], calendar: berlin)
        #expect(todays(reminders).isEmpty)
    }

    @Test func weighInOnlyOnMondayWednesdayFriday() {
        let reminders = ReminderPlanner.dailyReminders(now: date(16, 7), status: [:], calendar: berlin)
        let weekdays = Set(reminders.filter { $0.route == ReminderRoute.weighIn }.map { berlin.component(.weekday, from: $0.date) })
        #expect(weekdays == [2, 4, 6])
        #expect(reminders.count <= 64)
    }

    @Test func idsAreUniqueAndPrefixed() {
        let reminders = ReminderPlanner.dailyReminders(now: date(16, 7), status: [:], calendar: berlin)
        #expect(Set(reminders.map(\.id)).count == reminders.count)
        #expect(reminders.allSatisfy { $0.id.hasPrefix(ReminderPlanner.dailyPrefix) })
    }

    private func session(end: Date, hasRPE: Bool = false, kind: SessionKind = .handball) -> SessionReminderInput {
        SessionReminderInput(key: "w1", kind: kind, start: end.addingTimeInterval(-5400), end: end, hasRPE: hasRPE)
    }

    @Test func sessionReminderIsScheduledThirtyMinutesAfterEnd() {
        let plan = ReminderPlanner.sessionReminders([session(end: date(16, 20, 35))], notified: [], now: date(16, 20, 40), inForeground: false)
        #expect(plan.schedule.map(\.date) == [date(16, 21, 5)])
        #expect(plan.schedule.first?.body.contains("Wurfvolumen") == true)
        #expect(plan.markNotified.isEmpty)
    }

    @Test func lateSyncNotifiesOnceInBackgroundOnly() {
        let late = [session(end: date(16, 19))]
        let background = ReminderPlanner.sessionReminders(late, notified: [], now: date(16, 21), inForeground: false)
        #expect(background.schedule.count == 1)
        #expect(background.markNotified == ["w1"])

        let again = ReminderPlanner.sessionReminders(late, notified: ["w1"], now: date(16, 21, 10), inForeground: false)
        #expect(again.schedule.isEmpty)

        let foreground = ReminderPlanner.sessionReminders(late, notified: [], now: date(16, 21), inForeground: true)
        #expect(foreground.schedule.isEmpty)
        #expect(foreground.markNotified == ["w1"])
    }

    @Test func loggedSessionCancelsItsReminder() {
        let plan = ReminderPlanner.sessionReminders([session(end: date(16, 20), hasRPE: true, kind: .gym)], notified: [], now: date(16, 20, 5), inForeground: false)
        #expect(plan.schedule.isEmpty)
        #expect(plan.cancel == [ReminderPlanner.sessionPrefix + "w1"])
    }
}
