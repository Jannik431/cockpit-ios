import SwiftData
import SwiftUI

@main
struct CockpitApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(for: [DailyMetrics.self, HealthWorkout.self])
    }
}
