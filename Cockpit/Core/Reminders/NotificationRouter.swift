import Foundation
import Observation
import UserNotifications

/// Receives notification taps and hands the route to the UI (see `ReminderRoute`).
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
        let route = response.notification.request.content.userInfo["route"] as? String
        await MainActor.run { self.pendingRoute = route }
    }
}
