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
    @State private var sync = HealthSync.shared
    @State private var router = NotificationRouter.shared
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
            .task {
                await refresh()
                await ReminderCenter.shared.requestAuthorizationIfNeeded()
                await ReminderCenter.shared.refresh(context: context, inForeground: true)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refresh() }
                }
            }
            .onChange(of: sheet == nil) { _, closed in
                // A saved check-in or session changes which reminders are still needed.
                if closed {
                    Task { await ReminderCenter.shared.refresh(context: context, inForeground: true) }
                }
            }
            .onChange(of: router.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                router.pendingRoute = nil
                open(route)
            }
        }
    }

    private func refresh() async {
        now = .now
        await sync.run(context: context)
        await ReminderCenter.shared.refresh(context: context, inForeground: scenePhase == .active)
    }

    /// Opens what a tapped notification points to.
    private func open(_ route: String) {
        now = .now
        path = []
        switch route {
        case ReminderRoute.morning, ReminderRoute.weighIn:
            sheet = .checkIn(.morning)
        case ReminderRoute.evening:
            sheet = .checkIn(.evening)
        default:
            guard route.hasPrefix(ReminderRoute.sessionPrefix) else { return }
            let key = String(route.dropFirst(ReminderRoute.sessionPrefix.count))
            let recent = workouts.filter { $0.end >= now.addingTimeInterval(-36 * 3600) }
            guard let session = WorkoutGrouping.sessions(from: recent.map(\.info)).first(where: { $0.workoutIDs.first?.uuidString == key })
            else { return }
            let log = sessions.first { $0.matches(session) }
            sheet = .session(SessionDraft(day: LocalDay.start(of: session.start), suggested: session, existing: log))
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
