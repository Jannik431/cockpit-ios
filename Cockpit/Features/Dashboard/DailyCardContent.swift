import SwiftUI

/// The daily card, independent of SwiftData queries and HealthKit so it can be previewed and rendered with synthetic data.
struct DailyCardContent: View {
    let now: Date
    let days: [DailyMetrics]
    let workouts: [HealthWorkout]
    let syncState: HealthSync.State
    let lastSync: Date?
    var requestAccess: () -> Void = {}
    var retry: () -> Void = {}
    var showMethod: () -> Void = {}

    private var today: Date { LocalDay.start(of: now) }
    private var todayMetrics: DailyMetrics? { days.first { $0.day == today } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            header

            switch syncState {
            case .needsAuthorization:
                AccessCard(requestAccess: requestAccess)
            case .unavailable:
                InfoCard(systemImage: "heart.slash", text: "Apple Health ist auf diesem Gerät nicht verfügbar.")
            case .failed(let message):
                ErrorCard(message: message, retry: retry)
            case .idle, .importing:
                EmptyView()
            }

            ForEach(MetricTileModel.tiles(on: now, from: days)) { model in
                if model.metric == .sleep {
                    SleepTile(assessment: model.assessment, night: todayMetrics)
                } else {
                    MetricTile(model: model, detail: detail(for: model.metric))
                }
            }

            TrainingTodayCard(sessions: WorkoutGrouping.sessions(from: workouts.filter { $0.day == today }.map(\.info)))

            QuestionnairePlaceholderCard()

            Button(action: showMethod) {
                Label("Wie wird die Norm berechnet?", systemImage: "info.circle")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ExplorerFormat.locale)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            SyncIndicator(state: syncState, lastSync: lastSync)
        }
    }

    private func detail(for metric: BaselineMetric) -> String? {
        guard let metrics = todayMetrics else { return nil }
        switch metric {
        case .sleep:
            return nil
        case .hrv:
            let count = metrics.hrvSamples.count
            return count > 0 ? "SDNN aus Apple Health, Mittel aus \(count) \(count == 1 ? "Wert" : "Werten") der Nacht" : nil
        case .restingHR:
            return nil
        }
    }
}

private struct SyncIndicator: View {
    let state: HealthSync.State
    let lastSync: Date?

    var body: some View {
        Group {
            if state == .importing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Aktualisiere …")
                }
            } else if let lastSync {
                Label(lastSync.formatted(date: .omitted, time: .shortened), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct AccessCard: View {
    let requestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zugriff auf Apple Health", systemImage: "heart.text.square")
                .font(.headline)
            Text("Cockpit liest Schlaf, HRV, Ruhepuls und Workouts. Es wird nichts geschrieben, die Daten bleiben auf diesem iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Zugriff erlauben", action: requestAccess)
                .buttonStyle(.borderedProminent)
        }
        .card()
    }
}

private struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health konnte nicht gelesen werden")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Erneut versuchen", action: retry)
                    .font(.subheadline)
            }
        }
        .card()
    }
}

private struct InfoCard: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .card()
    }
}

private struct TrainingTodayCard: View {
    let sessions: [SuggestedSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Training heute", systemImage: "figure.run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            if sessions.isEmpty {
                Text("Noch kein Workout in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions, id: \.start) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.kind.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.green)
                            .frame(width: 36, height: 36)
                            .background(Color.green.opacity(0.14), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.kind.title)
                                .font(.body.weight(.medium))
                            Text(subtitle(for: session))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ExplorerFormat.duration(minutes: session.activeMinutes))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Art aus Apple Health vorgeschlagen")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    private func subtitle(for session: SuggestedSession) -> String {
        let time = MetricsFormat.timeRange(session.start, session.end)
        let parts = session.workoutIDs.count
        return parts > 1 ? "\(time) · aus \(parts) Teilen" : time
    }
}

private struct QuestionnairePlaceholderCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wohlbefinden")
                    .font(.body.weight(.medium))
                Text("Der tägliche Fragebogen kommt als Nächstes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
