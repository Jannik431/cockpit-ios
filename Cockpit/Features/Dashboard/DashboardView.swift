import SwiftData
import SwiftUI

/// Start screen: the daily card plus Apple Health sync.
struct DashboardView: View {
    private enum Route: Hashable {
        case storedDays
        case explorer
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var sync = HealthSync()
    @State private var path: [Route] = []
    @State private var showsMethod = false
    @Query(sort: \DailyMetrics.day, order: .reverse) private var days: [DailyMetrics]
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                DailyCardContent(
                    now: .now,
                    days: days,
                    workouts: workouts,
                    syncState: sync.state,
                    lastSync: sync.lastRun,
                    requestAccess: { Task { await sync.requestAccess(context: context) } },
                    retry: { Task { await sync.run(context: context) } },
                    showMethod: { showsMethod = true }
                )
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Heute")
            .refreshable { await sync.run(context: context) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Gespeicherte Tage", systemImage: "calendar") { path.append(.storedDays) }
                        Button("Health Explorer", systemImage: "stethoscope") { path.append(.explorer) }
                    } label: {
                        Label("Daten", systemImage: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .storedDays: StoredDaysView()
                case .explorer: HealthExplorerView()
                }
            }
            .sheet(isPresented: $showsMethod) {
                MethodSheet()
            }
            .task { await sync.run(context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await sync.run(context: context) }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScrollView {
            DailyCardContent(
                now: .now,
                days: PreviewData.days(endingAt: .now),
                workouts: PreviewData.workouts(on: .now),
                syncState: .idle,
                lastSync: .now
            )
            .padding(.horizontal)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Heute")
    }
}
#endif
