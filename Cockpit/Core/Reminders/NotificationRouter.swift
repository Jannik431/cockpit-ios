import Foundation
import Observation
import UserNotifications

/// Receives notification taps and answer buttons and hands them to the app (see `ReminderRoute`).
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Set when a notification was tapped; the dashboard opens the matching sheet and clears it.
    var pendingRoute: String?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let route = response.notification.request.content.userInfo["route"] as? String
        let delivered = response.notification.date

        if action.hasPrefix("energy."), let value = Int(action.dropFirst("energy.".count)) {
            await MainActor.run { Self.saveMiddayEnergy(value, deliveredAt: delivered) }
        } else if action == UNNotificationDefaultActionIdentifier {
            await MainActor.run { self.pendingRoute = route }
        }
    }

    /// Answer from the notification button, stored for the day the notification was shown.
    private static func saveMiddayEnergy(_ value: Int, deliveredAt date: Date) {
        let context = Persistence.container.mainContext
        QuestionnaireEntry.setAnswer(.int(value), for: "energy_midday", phase: .midday,
                                     day: LocalDay.logicalToday(date), context: context)
        ExportService.shared.exportIfLinked(context: context)
        Task { await ReminderCenter.shared.refresh(context: context, inForeground: false) }
    }
}
