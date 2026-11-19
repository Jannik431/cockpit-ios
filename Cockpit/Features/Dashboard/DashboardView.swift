import SwiftData
import SwiftUI

/// Start screen: the daily card plus Apple Health sync.
struct DashboardView: View {
    private enum Route: Hashable {
        case storedDays
        case explorer
    }

    private enum ActiveSheet: Identifiable {
        case method
        case checkIn(CheckInPhase)
        case session(SessionDraft)

        var id: String {
            switch self {
            case .method: "method"
            case .checkIn(let phase): "checkIn-\(phase.rawValue)"
            case .session(let draft): "session-\(draft.id)"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var sync = HealthSync()
    @State private var path: [Route] = []
    @State private var sheet: ActiveSheet?
    @State private var now = Date.now
    @Query(sort: \DailyMetrics.day, order: .reverse) private var days: [DailyMetrics]
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]
    @Query(sort: \QuestionnaireEntry.day, order: .reverse) private var entries: [QuestionnaireEntry]
    @Query(sort: \CompletedSession.start) private var sessions: [CompletedSession]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                DailyCardContent(
                    now: now,
                    days: days,
                    workouts: workouts,
                    entries: entries,
                    sessions: sessions,
                    syncState: sync.state,
                    lastSync: sync.lastRun,
                    requestAccess: { Task { await sync.requestAccess(context: context) } },
                    retry: { Task { await sync.run(context: context) } },
                    showMethod: { sheet = .method },
                    openCheckIn: { sheet = .checkIn($0) },
                    openSession: { sheet = .session($0) }
                )
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Heute")
            .refreshable { await refresh() }
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
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .method: MethodSheet()
                case .checkIn(let phase): CheckInView(phase: phase, day: LocalDay.start(of: now))
                case .session(let draft): SessionLogView(draft: draft)
                }
            }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refresh() }
                }
            }
        }
    }

    private func refresh() async {
        now = .now
        await sync.run(context: context)
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
                entries: PreviewData.entries(endingAt: .now),
                sessions: PreviewData.sessions(on: .now),
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
