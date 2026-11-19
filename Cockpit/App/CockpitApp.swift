import SwiftData
import SwiftUI

@main
struct CockpitApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(Persistence.container)
    }
}
