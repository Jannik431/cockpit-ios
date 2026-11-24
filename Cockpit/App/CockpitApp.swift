import SwiftData
import SwiftUI
import UserNotifications

@main
struct CockpitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(Persistence.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        ReminderCenter.shared.registerCategories()
        HealthBackgroundObserver.shared.start()
        return true
    }
}
