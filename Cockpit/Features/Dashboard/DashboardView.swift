import SwiftData
import SwiftUI

/// Start screen: the daily card plus Apple Health sync.
struct DashboardView: View {
    /// Switches the tab of the root view (e.g. the "Belastung" link on the daily card).
    var openTab: (AppTab) -> Void = { _ in }

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
    @State private var sheet: ActiveSheet?
    @State private var pendingAction: PendingAction?
    @State private var now = Date.now
    /// `nil` = today.
    @State private var selectedDay: Date?
    /// Edge the next day slides in from.
    @State private var slideEdge: Edge = .trailing
    @Query(sort: \DailyMetrics.day, order: .reverse) private var days: [DailyMetrics]
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]
    @Query(sort: \QuestionnaireEntry.day, order: .reverse) private var entries: [QuestionnaireEntry]
    @Query(sort: \CompletedSession.start) private var sessions: [CompletedSession]

    private var shownDay: Date { selectedDay ?? LocalDay.logicalToday(now) }

    var body: some View {
        NavigationStack {
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
                    goToToday: { changeDay(to: nil) },
                    answerMidday: { value in
                        QuestionnaireEntry.setAnswer(value.map { .int($0) }, for: "energy_midday", phase: .midday,
                                                     day: shownDay, context: context)
                        afterChange()
                    },
                    hideSession: { pendingAction = .hide($0) },
                    deleteLog: { pendingAction = .delete($0) },
                    openLink: { link in
                        switch link {
                        case .load: openTab(.load)
                        case .weight: openTab(.weight)
                        }
                    }
                )
                .id(shownDay)
                .transition(.push(from: slideEdge))
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .simultaneousGesture(daySwipe)
            .sensoryFeedback(.selection, trigger: shownDay)
            .background(Theme.screenBackground)
            .navigationTitle(selectedDay == nil ? "Heute" : "Rückblick")
            .refreshable { await refresh() }
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
                         ? "Das Workout bleibt in Apple Health, zählt in Cockpit aber nicht mehr mit. Wieder einblenden unter „Daten“ → „Gespeicherte Tage“."
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
                guard phase == .active else { return }
                selectedDay = nil
                Task { await refresh() }
            }
            .onChange(of: sheet == nil) { _, closed in
                // A saved check-in or session changes reminders and the export.
                if closed { afterChange() }
            }
        }
    }

    /// Horizontal swipe: to the left = next day, to the right = previous day. Vertical scrolling stays untouched.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.8 else { return }
                changeDay(dx < 0 ? 1 : -1)
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
        changeDay(to: target == today ? nil : target)
    }

    private func changeDay(to day: Date?) {
        let target = day ?? LocalDay.logicalToday(now)
        guard target != shownDay else { return }
        slideEdge = target > shownDay ? .trailing : .leading
        withAnimation(.snappy(duration: 0.3)) { selectedDay = day }
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
