import Foundation
import Observation
import OSLog
import UserNotifications

nonisolated let notificationLog = Logger(subsystem: "de.jannikpasch.cockpit", category: "notifications")

/// Receives notification taps and answer buttons and hands them to the app (see `ReminderRoute`).
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Set when a notification was tapped; `RootView` opens the matching form and clears it.
    var pendingRoute: String?

    /// Must run before the app finishes launching, otherwise the tap that launched the app is lost.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

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

        await MainActor.run {
            DiagnosticsLog.shared.add("Benachrichtigung angetippt: \(route ?? "ohne Ziel"), Aktion \(action)")
            if action.hasPrefix("energy."), let value = Int(action.dropFirst("energy.".count)) {
                Self.saveMiddayEnergy(value, deliveredAt: delivered)
            } else if action == UNNotificationDefaultActionIdentifier {
                self.pendingRoute = route
            }
        }
    }

    /// Answer from the notification button, stored for the day the notification was shown.
    private static func saveMiddayEnergy(_ value: Int, deliveredAt date: Date) {
        let context = Persistence.container.mainContext
        QuestionnaireEntry.setAnswer(.int(value), for: "energy_midday", phase: .midday,
                                     day: LocalDay.logicalToday(date), context: context)
        DiagnosticsLog.shared.add("Energie am Mittag aus der Benachrichtigung gespeichert: \(value)")
        ExportService.shared.exportIfLinked(context: context)
        Task { await ReminderCenter.shared.refresh(context: context, inForeground: false) }
    }

    /// For checking taps: a notification for the morning check in a few seconds.
    func sendTestNotification(in seconds: TimeInterval = 5) async {
        let content = UNMutableNotificationContent()
        content.title = "Test: Morgen-Check"
        content.body = "Antippen sollte den Morgen-Check öffnen."
        content.sound = .default
        content.userInfo = ["route": ReminderRoute.morning]
        let request = UNNotificationRequest(identifier: "cockpit.test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(request)
            DiagnosticsLog.shared.add("Test-Benachrichtigung geplant (in \(Int(seconds)) s)")
        } catch {
            DiagnosticsLog.shared.add("Test-Benachrichtigung fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
