import Foundation

nonisolated struct PlannedReminder: Sendable, Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
    /// What a tap opens, see `ReminderRoute`.
    let route: String
}

nonisolated enum ReminderRoute {
    static let morning = "checkin.morning"
    static let midday = "checkin.midday"
    static let evening = "checkin.evening"
    static let weighIn = "weighin"
    static let sessionPrefix = "session."

    static func session(_ key: String) -> String { sessionPrefix + key }
}

/// What has already been done on a day, so reminders for it can be skipped.
nonisolated struct ReminderDayStatus: Sendable, Equatable {
    var morningComplete = false
    var middayAnswered = false
    var eveningComplete = false
    var weightEntered = false
}

/// A Health session that may need an RPE reminder.
nonisolated struct SessionReminderInput: Sendable, Equatable {
    /// Stable key: the first Health workout UUID of the session.
    let key: String
    let kind: SessionKind
    let start: Date
    let end: Date
    let hasRPE: Bool
}

nonisolated struct SessionReminderPlan: Sendable, Equatable {
    var schedule: [PlannedReminder] = []
    var cancel: [String] = []
    var markNotified: [String] = []
}

/// Decides which local notifications should exist. Pure, so it can be tested; `ReminderCenter` applies the plan.
nonisolated enum ReminderPlanner {
    static let morningTime = (hour: 9, minute: 0)
    static let weighInTime = (hour: 8, minute: 30)
    static let middayTime = (hour: 13, minute: 30)
    static let eveningTime = (hour: 22, minute: 30)
    /// Notification category with the answer buttons 1–5 for the energy at noon.
    static let middayCategory = "energy_midday"
    /// Daily reminders are planned this far ahead and refreshed whenever the app runs (iOS allows 64 pending).
    static let daysAhead = 14

    static let dailyPrefix = "cockpit.daily."
    static let sessionPrefix = "cockpit.session."

    static func dailyReminders(now: Date, status: [Date: ReminderDayStatus], calendar: Calendar = .current) -> [PlannedReminder] {
        let today = calendar.startOfDay(for: now)
        var result: [PlannedReminder] = []
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let done = status[day] ?? ReminderDayStatus()
            let stamp = dayStamp(day, calendar: calendar)

            func at(_ time: (hour: Int, minute: Int)) -> Date? {
                calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
            }

            if QuestionCatalog.weighInWeekdays.contains(calendar.component(.weekday, from: day)),
               !done.weightEntered, let date = at(weighInTime), date > now {
                result.append(PlannedReminder(
                    id: dailyPrefix + "weighin." + stamp, date: date, title: "Wiegetag",
                    body: "Vor dem Frühstück wiegen und das Gewicht im Morgen-Check eintragen.",
                    route: ReminderRoute.weighIn))
            }
            if !done.morningComplete, let date = at(morningTime), date > now {
                result.append(PlannedReminder(
                    id: dailyPrefix + "morning." + stamp, date: date, title: "Morgen-Check",
                    body: "Wie hast du geschlafen? Dauert etwa 30 Sekunden.",
                    route: ReminderRoute.morning))
            }
            if !done.middayAnswered, let date = at(middayTime), date > now {
                result.append(PlannedReminder(
                    id: dailyPrefix + "midday." + stamp, date: date, title: "Energie am Mittag",
                    body: "Wie wach bist du gerade? Lange drücken und 1–5 antippen.",
                    route: ReminderRoute.midday))
            }
            if !done.eveningComplete, let date = at(eveningTime), date > now {
                result.append(PlannedReminder(
                    id: dailyPrefix + "evening." + stamp, date: date, title: "Abend-Check",
                    body: "Beschwerden, Essen, Koffein und Alkohol kurz eintragen.",
                    route: ReminderRoute.evening))
            }
        }
        return result
    }

    /// One reminder per Health session without RPE, `SessionScales.rpeDelay` after it ended.
    /// If that moment has passed, it is sent right away, but only once and only while the app is in the background
    /// (in the foreground the daily card already shows the prompt).
    static func sessionReminders(
        _ sessions: [SessionReminderInput],
        notified: Set<String>,
        now: Date,
        inForeground: Bool
    ) -> SessionReminderPlan {
        var plan = SessionReminderPlan()
        for session in sessions {
            let id = sessionPrefix + session.key
            if session.hasRPE {
                plan.cancel.append(id)
                continue
            }
            let due = session.end.addingTimeInterval(SessionScales.rpeDelay)
            if due > now {
                plan.schedule.append(reminder(for: session, id: id, date: due))
            } else if !notified.contains(session.key) {
                plan.markNotified.append(session.key)
                if !inForeground {
                    plan.schedule.append(reminder(for: session, id: id, date: now.addingTimeInterval(2)))
                }
            }
        }
        return plan
    }

    private static func reminder(for session: SessionReminderInput, id: String, date: Date) -> PlannedReminder {
        let time = "\(clock(session.start))–\(clock(session.end))"
        let body = session.kind == .handball
            ? "Session-RPE und Wurfvolumen für \(time) eintragen."
            : "Session-RPE für \(time) eintragen."
        return PlannedReminder(id: id, date: date, title: "Wie anstrengend war \(session.kind.title)?",
                               body: body, route: ReminderRoute.session(session.key))
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// IDs of a day's daily reminders, e.g. to clear delivered ones once the check is done.
    static func dailyIDs(for day: Date, routes: [String], calendar: Calendar = .current) -> [String] {
        let stamp = dayStamp(day, calendar: calendar)
        return routes.map { route in
            switch route {
            case ReminderRoute.weighIn: dailyPrefix + "weighin." + stamp
            case ReminderRoute.midday: dailyPrefix + "midday." + stamp
            case ReminderRoute.evening: dailyPrefix + "evening." + stamp
            default: dailyPrefix + "morning." + stamp
            }
        }
    }

    private static func dayStamp(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
