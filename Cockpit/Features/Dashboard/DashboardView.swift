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
                    LastNightView(metrics: today, assessments: DailyMetrics.assessments(on: .now, from: days))
                } header: {
                    Text("Letzte Nacht")
                } footer: {
                    BaselineMethodFooter()
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
    let assessments: [MetricAssessment]

    var body: some View {
        if let metrics, metrics.asleepMin != nil || metrics.hrvNightMeanMs != nil || metrics.restingHR != nil {
            ForEach(assessments, id: \.metric) { assessment in
                AssessmentRow(assessment: assessment, detail: detail(for: assessment.metric, metrics: metrics))
            }
        } else {
            Text("Für heute sind noch keine Werte da. Vielleicht hat die Tracker-App noch nicht mit Apple Health synchronisiert.")
                .foregroundStyle(.secondary)
        }
    }

    private func detail(for metric: BaselineMetric, metrics: DailyMetrics) -> String? {
        switch metric {
        case .sleep:
            guard let start = metrics.inBedStart, let end = metrics.inBedEnd else { return nil }
            return "Im Bett \(MetricsFormat.timeRange(start, end))"
        case .hrv:
            let count = metrics.hrvSamples.count
            return count > 0 ? "Mittel aus \(count) \(count == 1 ? "Wert" : "Werten") der Nacht" : nil
        case .restingHR:
            return nil
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
