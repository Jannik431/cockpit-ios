import Foundation
import SwiftData
import UserNotifications

/// Applies `ReminderPlanner` plans to the system's local notifications.
final class ReminderCenter {
    static let shared = ReminderCenter()

    private let center = UNUserNotificationCenter.current()
    private let notifiedKey = "notifiedSessionKeys"

    func requestAuthorizationIfNeeded() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Re-plans all reminders from the current data. Cheap; called after every sync and every saved check-in.
    func refresh(context: ModelContext, now: Date = .now, inForeground: Bool) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        await refreshDaily(context: context, now: now)
        await refreshSessions(context: context, now: now, inForeground: inForeground)
    }

    private func refreshDaily(context: ModelContext, now: Date) async {
        let today = LocalDay.start(of: now)
        let entries = (try? context.fetch(FetchDescriptor<QuestionnaireEntry>(predicate: #Predicate { $0.day >= today }))) ?? []
        var status: [Date: ReminderDayStatus] = [:]
        for entry in entries {
            var day = status[entry.day] ?? ReminderDayStatus()
            switch entry.checkInPhase {
            case .morning:
                day.morningComplete = entry.isComplete
                day.weightEntered = entry.answers["body_weight"] != nil
            case .evening:
                day.eveningComplete = entry.isComplete
            case nil:
                break
            }
            status[entry.day] = day
        }

        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(ReminderPlanner.dailyPrefix) })
        for reminder in ReminderPlanner.dailyReminders(now: now, status: status) {
            try? await center.add(request(for: reminder, now: now))
        }

        // Clear already delivered reminders for checks that are done now.
        let done = status[today] ?? ReminderDayStatus()
        var routes: [String] = []
        if done.morningComplete { routes.append(ReminderRoute.morning) }
        if done.weightEntered { routes.append(ReminderRoute.weighIn) }
        if done.eveningComplete { routes.append(ReminderRoute.evening) }
        center.removeDeliveredNotifications(withIdentifiers: ReminderPlanner.dailyIDs(for: today, routes: routes))
    }

    private func refreshSessions(context: ModelContext, now: Date, inForeground: Bool) async {
        let since = now.addingTimeInterval(-24 * 3600)
        let workouts = (try? context.fetch(FetchDescriptor<HealthWorkout>(predicate: #Predicate { $0.end >= since }))) ?? []
        let logs = (try? context.fetch(FetchDescriptor<CompletedSession>(predicate: #Predicate { $0.end >= since }))) ?? []

        let inputs: [SessionReminderInput] = WorkoutGrouping.sessions(from: workouts.map(\.info)).compactMap { session in
            guard let key = session.workoutIDs.first?.uuidString else { return nil }
            let log = logs.first { $0.matches(session) }
            return SessionReminderInput(key: key, kind: log?.sessionKind ?? session.kind, start: session.start,
                                        end: session.end, hasRPE: log?.sessionRPE != nil)
        }

        var notified = notifiedSessions(now: now)
        let plan = ReminderPlanner.sessionReminders(inputs, notified: Set(notified.keys), now: now, inForeground: inForeground)
        center.removePendingNotificationRequests(withIdentifiers: plan.cancel)
        center.removeDeliveredNotifications(withIdentifiers: plan.cancel)
        for reminder in plan.schedule {
            try? await center.add(request(for: reminder, now: now))
        }
        for key in plan.markNotified { notified[key] = now }
        UserDefaults.standard.set(notified.mapValues(\.timeIntervalSince1970), forKey: notifiedKey)
    }

    /// Session keys already notified, kept for three days.
    private func notifiedSessions(now: Date) -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: notifiedKey) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }.filter { now.timeIntervalSince($0.value) < 3 * 24 * 3600 }
    }

    private func request(for reminder: PlannedReminder, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["route": reminder.route]
        content.threadIdentifier = reminder.route.hasPrefix(ReminderRoute.sessionPrefix) ? "sessions" : "checkins"

        let trigger: UNNotificationTrigger
        if reminder.date.timeIntervalSince(now) < 60 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSince(now)), repeats: false)
        } else {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}
