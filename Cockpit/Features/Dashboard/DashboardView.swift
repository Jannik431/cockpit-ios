import SwiftData
import SwiftUI

/// Start screen: the daily card plus Apple Health sync.
struct DashboardView: View {
    private enum Route: Hashable {
        case storedDays
        case explorer
        case export
        case link(DashboardLink)
    }

    private enum ActiveSheet: Identifiable {
        case method
        case checkIn(CheckInPhase, Date)
        case session(SessionDraft)

        var id: String {
            switch self {
            case .method: "method"
            case .checkIn(let phase, let day): "checkIn-\(phase.rawValue)-\(day.timeIntervalSince1970)"
            case .session(let draft): "session-\(draft.id)"
            }
        }
    }

    /// Destructive actions wait for a confirmation.
    private enum PendingAction: Identifiable {
        case hide(TrainingRow)
        case delete(CompletedSession)

        var id: String {
            switch self {
            case .hide(let row): "hide-\(row.id)"
            case .delete(let log): "delete-\(log.id)"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var sync = HealthSync.shared
    @State private var router = NotificationRouter.shared
    @State private var path: [Route] = []
    @State private var sheet: ActiveSheet?
    @State private var pendingAction: PendingAction?
    @State private var now = Date.now
    /// `nil` = today.
    @State private var selectedDay: Date?
    @Query(sort: \DailyMetrics.day, order: .reverse) private var days: [DailyMetrics]
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]
    @Query(sort: \QuestionnaireEntry.day, order: .reverse) private var entries: [QuestionnaireEntry]
    @Query(sort: \CompletedSession.start) private var sessions: [CompletedSession]

    private var shownDay: Date { selectedDay ?? LocalDay.logicalToday(now) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                DailyCardContent(
                    now: now,
                    day: selectedDay,
                    days: days,
                    workouts: workouts,
                    entries: entries,
                    sessions: sessions,
                    syncState: sync.state,
                    lastSync: sync.lastRun,
                    requestAccess: { Task { await sync.requestAccess(context: context) } },
                    retry: { Task { await sync.run(context: context) } },
                    showMethod: { sheet = .method },
                    openCheckIn: { sheet = .checkIn($0, shownDay) },
                    openSession: { sheet = .session($0) },
                    changeDay: changeDay,
                    goToToday: { selectedDay = nil },
                    answerMidday: { value in
                        QuestionnaireEntry.setAnswer(value.map { .int($0) }, for: "energy_midday", phase: .midday,
                                                     day: shownDay, context: context)
                        afterChange()
                    },
                    hideSession: { pendingAction = .hide($0) },
                    deleteLog: { pendingAction = .delete($0) },
                    openLink: { path.append(.link($0)) }
                )
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.screenBackground)
            .navigationTitle(selectedDay == nil ? "Heute" : "Rückblick")
            .refreshable { await refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Belastung", systemImage: "chart.bar") { path.append(.link(.load)) }
                        Button("Gewicht", systemImage: "scalemass") { path.append(.link(.weight)) }
                        Button("Export", systemImage: "square.and.arrow.up") { path.append(.export) }
                        Divider()
                        Button("Gespeicherte Tage", systemImage: "calendar") { path.append(.storedDays) }
                        Button("Health Explorer", systemImage: "stethoscope") { path.append(.explorer) }
                    } label: {
                        Label("Mehr", systemImage: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .storedDays: StoredDaysView()
                case .explorer: HealthExplorerView()
                case .export: ExportView()
                case .link(.load): LoadView()
                case .link(.weight): WeightView()
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .method: MethodSheet()
                case .checkIn(let phase, let day): CheckInView(phase: phase, day: day)
                case .session(let draft): SessionLogView(draft: draft)
                }
            }
            .confirmationDialog(confirmationTitle, isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ), titleVisibility: .visible, presenting: pendingAction) { action in
                switch action {
                case .hide(let row):
                    Button("Workout ausblenden", role: .destructive) { hide(row) }
                case .delete(let log):
                    Button("Löschen", role: .destructive) { delete(log) }
                }
            } message: { action in
                switch action {
                case .hide(let row):
                    Text(row.log == nil
                         ? "Das Workout bleibt in Apple Health, zählt in Cockpit aber nicht mehr mit. Wieder einblenden unter „Gespeicherte Tage“."
                         : "Das Workout bleibt in Apple Health, zählt in Cockpit aber nicht mehr mit. Der RPE-Eintrag dazu wird gelöscht.")
                case .delete:
                    Text("RPE, Notiz und weitere Angaben zu dieser Einheit werden gelöscht.")
                }
            }
            .task {
                await refresh()
                await ReminderCenter.shared.requestAuthorizationIfNeeded()
                await ReminderCenter.shared.refresh(context: context, inForeground: true)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    selectedDay = nil
                    Task { await refresh() }
                }
            }
            .onChange(of: sheet == nil) { _, closed in
                // A saved check-in or session changes reminders and the export.
                if closed { afterChange() }
            }
            .onChange(of: router.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                router.pendingRoute = nil
                open(route)
            }
        }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .hide: "Workout ausblenden?"
        case .delete: "Eintrag löschen?"
        case nil: ""
        }
    }

    private func changeDay(_ offset: Int) {
        let today = LocalDay.logicalToday(now)
        guard let target = Calendar.current.date(byAdding: .day, value: offset, to: shownDay), target <= today else { return }
        selectedDay = target == today ? nil : target
    }

    private func refresh() async {
        now = .now
        await sync.run(context: context)
        await ReminderCenter.shared.refresh(context: context, inForeground: scenePhase == .active)
        ExportService.shared.exportIfLinked(context: context)
    }

    private func afterChange() {
        now = .now
        ExportService.shared.exportIfLinked(context: context)
        Task { await ReminderCenter.shared.refresh(context: context, inForeground: true) }
    }

    private func hide(_ row: TrainingRow) {
        let ids = Set(row.workoutIDs)
        for workout in workouts where ids.contains(workout.healthID) {
            workout.isHidden = true
        }
        if let log = row.log { context.delete(log) }
        try? context.save()
        afterChange()
    }

    private func delete(_ log: CompletedSession) {
        context.delete(log)
        try? context.save()
        afterChange()
    }

    /// Opens what a tapped notification points to.
    private func open(_ route: String) {
        now = .now
        path = []
        selectedDay = nil
        let today = LocalDay.logicalToday(now)
        switch route {
        case ReminderRoute.morning, ReminderRoute.weighIn:
            sheet = .checkIn(.morning, today)
        case ReminderRoute.midday:
            sheet = .checkIn(.midday, today)
        case ReminderRoute.evening:
            sheet = .checkIn(.evening, today)
        default:
            guard route.hasPrefix(ReminderRoute.sessionPrefix) else { return }
            let key = String(route.dropFirst(ReminderRoute.sessionPrefix.count))
            let recent = workouts.filter { $0.end >= now.addingTimeInterval(-36 * 3600) && !$0.isHidden }
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
