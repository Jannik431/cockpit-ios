import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case load
    case weight
    case data
}

/// Tab bar: daily card, load monitoring, weight, data tools.
/// Also opens the form a tapped notification points to, from the top level, so it works on every tab.
struct RootView: View {
    private enum RouteSheet: Identifiable {
        case checkIn(CheckInPhase, Date)
        case session(SessionDraft)

        var id: String {
            switch self {
            case .checkIn(let phase, let day): "checkIn-\(phase.rawValue)-\(day.timeIntervalSince1970)"
            case .session(let draft): "session-\(draft.id)"
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .today
    @State private var router = NotificationRouter.shared
    @State private var routeSheet: RouteSheet?
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]
    @Query(sort: \CompletedSession.start) private var sessions: [CompletedSession]

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(openTab: { tab = $0 })
                .tabItem { Label("Heute", systemImage: "sun.max") }
                .tag(AppTab.today)

            NavigationStack { LoadView() }
                .tabItem { Label("Belastung", systemImage: "chart.bar") }
                .tag(AppTab.load)

            NavigationStack { WeightView() }
                .tabItem { Label("Gewicht", systemImage: "scalemass") }
                .tag(AppTab.weight)

            NavigationStack { DataHubView() }
                .tabItem { Label("Daten", systemImage: "tray.full") }
                .tag(AppTab.data)
        }
        .sheet(item: $routeSheet) { sheet in
            switch sheet {
            case .checkIn(let phase, let day): CheckInView(phase: phase, day: day)
            case .session(let draft): SessionLogView(draft: draft)
            }
        }
        .onAppear {
            DiagnosticsLog.shared.add("App sichtbar, Status \(phaseName)")
            handlePendingRoute()
        }
        .onChange(of: router.pendingRoute) { handlePendingRoute() }
        .onChange(of: scenePhase) { handlePendingRoute() }
        .onChange(of: routeSheet == nil) { _, closed in
            // A form saved from a notification changes reminders and the export.
            guard closed else { return }
            ExportService.shared.exportIfLinked(context: context)
            Task { await ReminderCenter.shared.refresh(context: context, inForeground: true) }
        }
    }

    private var phaseName: String {
        switch scenePhase {
        case .active: "aktiv"
        case .inactive: "inaktiv"
        case .background: "Hintergrund"
        @unknown default: "unbekannt"
        }
    }

    /// Waits until the app is really active: sheets presented while the app is launching or
    /// coming back from the background are dropped by iOS.
    private func handlePendingRoute() {
        guard let route = router.pendingRoute else { return }
        guard scenePhase == .active else {
            DiagnosticsLog.shared.add("Ziel \(route) wartet, App ist \(phaseName)")
            return
        }
        router.pendingRoute = nil
        tab = .today
        Task { @MainActor in
            if routeSheet != nil {
                routeSheet = nil
                try? await Task.sleep(for: .milliseconds(500))
            } else {
                try? await Task.sleep(for: .milliseconds(350))
            }
            open(route)
        }
    }

    private func open(_ route: String) {
        let now = Date.now
        let today = LocalDay.logicalToday(now)
        switch route {
        case ReminderRoute.morning, ReminderRoute.weighIn:
            routeSheet = .checkIn(.morning, today)
        case ReminderRoute.midday:
            routeSheet = .checkIn(.midday, today)
        case ReminderRoute.evening:
            routeSheet = .checkIn(.evening, today)
        default:
            guard route.hasPrefix(ReminderRoute.sessionPrefix) else {
                DiagnosticsLog.shared.add("Unbekanntes Ziel \(route)")
                return
            }
            let key = String(route.dropFirst(ReminderRoute.sessionPrefix.count))
            let recent = workouts.filter { $0.end >= now.addingTimeInterval(-36 * 3600) && !$0.isHidden }
            guard let session = WorkoutGrouping.sessions(from: recent.map(\.info))
                .first(where: { $0.workoutIDs.map(\.uuidString).contains(key) }) else {
                DiagnosticsLog.shared.add("Einheit zu \(route) nicht gefunden")
                return
            }
            let log = sessions.first { $0.matches(session) }
            routeSheet = .session(SessionDraft(day: LocalDay.start(of: session.start), suggested: session, existing: log))
        }
        DiagnosticsLog.shared.add("Bogen geöffnet für \(route)")
    }
}

/// Export, data tools and the notification check.
private struct DataHubView: View {
    @State private var log = DiagnosticsLog.shared

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Die Tages-CSV für die Trainingsplanung.")
            }

            Section {
                NavigationLink {
                    StoredDaysView()
                } label: {
                    Label("Gespeicherte Tage", systemImage: "calendar")
                }
                NavigationLink {
                    HealthExplorerView()
                } label: {
                    Label("Health Explorer", systemImage: "stethoscope")
                }
            } footer: {
                Text("Werte aus Apple Health prüfen, ausgeblendete Workouts wieder einblenden.")
            }

            Section {
                Button("Test-Benachrichtigung in 5 Sekunden", systemImage: "bell.badge") {
                    Task { await NotificationRouter.shared.sendTestNotification() }
                }
                if log.lines.isEmpty {
                    Text("Noch keine Einträge")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(log.lines.reversed().prefix(20).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("Protokoll leeren", role: .destructive) { log.clear() }
                }
            } header: {
                Text("Benachrichtigungen prüfen")
            } footer: {
                Text("Knopf drücken, App sofort in den Hintergrund schicken oder iPhone sperren, dann die Benachrichtigung antippen. Der Morgen-Check sollte sich öffnen.")
            }
        }
        .navigationTitle("Daten")
    }
}
