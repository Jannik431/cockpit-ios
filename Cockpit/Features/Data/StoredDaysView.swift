import SwiftData
import SwiftUI

/// All stored days, newest first. Meant for spot checks against the Health app.
struct StoredDaysView: View {
    @Query(sort: \DailyMetrics.day, order: .reverse) private var days: [DailyMetrics]
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]

    var body: some View {
        List(days) { metrics in
            NavigationLink {
                DayDetailView(
                    metrics: metrics,
                    workouts: workouts.filter { $0.day == metrics.day },
                    assessments: DailyMetrics.assessments(on: metrics.day, from: days)
                )
            } label: {
                DayRow(metrics: metrics, workoutCount: workouts.count { $0.day == metrics.day })
            }
        }
        .overlay {
            if days.isEmpty {
                ContentUnavailableView("Noch keine Tage", systemImage: "calendar",
                                       description: Text("Der Import startet automatisch, sobald Cockpit Zugriff auf Apple Health hat."))
            }
        }
        .navigationTitle("Gespeicherte Tage")
    }
}

private struct DayRow: View {
    let metrics: DailyMetrics
    let workoutCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ExplorerFormat.day(metrics.day))
                    .font(.headline)
                Spacer()
                if workoutCount > 0 {
                    Label("\(workoutCount)", systemImage: "figure.run")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Schlaf \(MetricsFormat.minutes(metrics.asleepMin)) · HRV \(MetricsFormat.hrv(metrics.hrvNightMeanMs)) · RP \(MetricsFormat.bpm(metrics.restingHR))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct DayDetailView: View {
    let metrics: DailyMetrics
    let workouts: [HealthWorkout]
    let assessments: [MetricAssessment]

    var body: some View {
        List {
            ForEach(assessments, id: \.metric) { assessment in
                AssessmentDetailSection(assessment: assessment)
            }
            Section {
            } footer: {
                BaselineMethodFooter()
            }

            Section("Schlafphasen") {
                if let start = metrics.inBedStart, let end = metrics.inBedEnd {
                    LabeledContent("Im Bett", value: MetricsFormat.timeRange(start, end))
                }
                LabeledContent("Schlaf gesamt", value: MetricsFormat.minutes(metrics.asleepMin))
                LabeledContent(SleepStage.asleepCore.title, value: MetricsFormat.minutes(metrics.coreMin))
                LabeledContent(SleepStage.asleepDeep.title, value: MetricsFormat.minutes(metrics.deepMin))
                LabeledContent(SleepStage.asleepREM.title, value: MetricsFormat.minutes(metrics.remMin))
                if metrics.unspecifiedMin != nil {
                    LabeledContent(SleepStage.asleepUnspecified.title, value: MetricsFormat.minutes(metrics.unspecifiedMin))
                }
                LabeledContent(SleepStage.awake.title, value: MetricsFormat.minutes(metrics.awakeMin))
                source(metrics.sleepSource)
            }

            Section {
                LabeledContent("Mittel der Nacht", value: MetricsFormat.hrv(metrics.hrvNightMeanMs))
                ForEach(metrics.hrvSamples, id: \.time) { sample in
                    LabeledContent(MetricsFormat.time(sample.time), value: MetricsFormat.hrv(sample.ms))
                }
                source(metrics.hrvSource)
            } header: {
                Text(HRVMetric.title)
            } footer: {
                Text("Nicht vergleichbar mit dem HRV-Wert in der Tracker-App, die oft RMSSD anzeigt.")
            }

            Section("Ruhepuls") {
                LabeledContent("Wert", value: MetricsFormat.bpm(metrics.restingHR))
                source(metrics.restingHRSource)
            }

            let hidden = workouts.filter(\.isHidden)
            if !hidden.isEmpty {
                Section {
                    ForEach(hidden) { workout in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(workout.activityTypeName ?? "Typ \(workout.activityTypeRaw)")
                                Text(MetricsFormat.timeRange(workout.start, workout.end))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Einblenden") {
                                workout.isHidden = false
                                try? workout.modelContext?.save()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Ausgeblendete Workouts")
                }
            }

            Section {
                let sessions = WorkoutGrouping.sessions(from: workouts.filter { !$0.isHidden }.map(\.info))
                if sessions.isEmpty {
                    Text("Keine Workouts")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions, id: \.start) { session in
                    LabeledContent {
                        Text("\(MetricsFormat.timeRange(session.start, session.end)) · \(ExplorerFormat.duration(minutes: session.activeMinutes))")
                    } label: {
                        Text(session.kind.title)
                        if session.workoutIDs.count > 1 {
                            Text("aus \(session.workoutIDs.count) Workouts zusammengefasst")
                        }
                    }
                }
            } header: {
                Text("Training (Vorschlag)")
            } footer: {
                if !workouts.isEmpty {
                    Text("Aus Apple Health: " + workouts.map { $0.activityTypeName ?? "Typ \($0.activityTypeRaw)" }.joined(separator: ", "))
                }
            }
        }
        .navigationTitle(ExplorerFormat.day(metrics.day))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func source(_ bundleID: String?) -> some View {
        if let bundleID {
            LabeledContent("Quelle", value: bundleID)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
