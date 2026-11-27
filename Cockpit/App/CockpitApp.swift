import SwiftData
import SwiftUI

@main
struct CockpitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // As early as possible: a tap that launches the app is delivered right after launch.
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationRouter.shared.install()
        ReminderCenter.shared.registerCategories()
        HealthBackgroundObserver.shared.start()
        return true
    }
}
