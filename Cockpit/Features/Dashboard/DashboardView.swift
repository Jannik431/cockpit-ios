import SwiftData
import SwiftUI

/// Start screen. Shows last night's raw values until the daily card with baselines exists.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var sync = HealthSync()
    @Query(sort: \DailyMetrics.day, order: .reverse) private var days: [DailyMetrics]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LastNightView(metrics: today)
                } header: {
                    Text("Letzte Nacht")
                } footer: {
                    Text("Rohwerte. Der Vergleich mit deiner Norm kommt mit der Tageskarte.")
                }

                Section("Apple Health") {
                    SyncStatusView(sync: sync) {
                        Task { await sync.requestAccess(context: context) }
                    } retry: {
                        Task { await sync.run(context: context) }
                    }
                }

                Section("Daten") {
                    NavigationLink {
                        StoredDaysView()
                    } label: {
                        LabeledContent("Gespeicherte Tage", value: "\(days.count)")
                    }
                    NavigationLink("Health Explorer") {
                        HealthExplorerView()
                    }
                }
            }
            .navigationTitle("Heute")
            .task { await sync.run(context: context) }
            .refreshable { await sync.run(context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await sync.run(context: context) }
                }
            }
        }
    }

    private var today: DailyMetrics? {
        let start = LocalDay.start(of: .now)
        return days.first { $0.day == start }
    }
}

private struct LastNightView: View {
    let metrics: DailyMetrics?

    var body: some View {
        if let metrics, metrics.asleepMin != nil || metrics.hrvNightMeanMs != nil || metrics.restingHR != nil {
            LabeledContent("Schlaf", value: MetricsFormat.minutes(metrics.asleepMin))
            if let start = metrics.inBedStart, let end = metrics.inBedEnd {
                LabeledContent("Im Bett", value: MetricsFormat.timeRange(start, end))
            }
            LabeledContent(HRVMetric.title, value: MetricsFormat.hrv(metrics.hrvNightMeanMs, count: metrics.hrvSamples.count))
            LabeledContent("Ruhepuls", value: MetricsFormat.bpm(metrics.restingHR))
        } else {
            Text("Für heute sind noch keine Werte da. Vielleicht hat die Tracker-App noch nicht mit Apple Health synchronisiert.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SyncStatusView: View {
    let sync: HealthSync
    let requestAccess: () -> Void
    let retry: () -> Void

    var body: some View {
        switch sync.state {
        case .importing:
            HStack {
                ProgressView()
                Text("Lese Apple Health …")
            }
        case .needsAuthorization:
            Text("Cockpit braucht Lesezugriff auf Schlaf, HRV, Ruhepuls und Workouts.")
            Button("Zugriff erlauben", action: requestAccess)
        case .unavailable:
            Text("Apple Health ist auf diesem Gerät nicht verfügbar.")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Button("Erneut versuchen", action: retry)
        case .idle:
            if let lastRun = sync.lastRun, let result = sync.lastResult {
                LabeledContent("Aktualisiert", value: lastRun.formatted(date: .omitted, time: .shortened))
                Text("\(result.days) Tage gelesen, \(result.newWorkouts) neue Workouts")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Noch nicht importiert")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [DailyMetrics.self, HealthWorkout.self], inMemory: true)
}
