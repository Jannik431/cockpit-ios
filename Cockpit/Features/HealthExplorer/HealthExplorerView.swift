import SwiftUI

/// Debug view: lists which Apple Health data actually arrives, from which source, how often and with which gaps.
struct HealthExplorerView: View {
    @State private var model = HealthExplorerModel()

    var body: some View {
        content
            .navigationTitle("Health Explorer")
            .toolbar {
                if model.state == .loaded {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: model.report) {
                            Label("Bericht teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task { await model.start() }
            .refreshable { await model.load() }
            .onChange(of: model.rangeDays) {
                Task { await model.load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            loadingView

        case .loading where model.summaries.isEmpty:
            loadingView

        case .unavailable:
            ContentUnavailableView(
                "Apple Health nicht verfügbar",
                systemImage: "heart.slash",
                description: Text("Auf diesem Gerät gibt es keine Health-Daten.")
            )

        case .needsAuthorization:
            ContentUnavailableView {
                Label("Zugriff auf Apple Health", systemImage: "heart.text.square")
            } description: {
                Text("Cockpit liest Schlaf, HRV, Ruhepuls, Herzfrequenz und Workouts. Es wird nichts geschrieben, die Daten bleiben auf dem iPhone.")
            } actions: {
                Button("Zugriff erlauben") {
                    Task { await model.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Fehler beim Lesen", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") {
                    Task { await model.start() }
                }
            }

        case .loading, .loaded:
            resultList
        }
    }

    private var loadingView: some View {
        ProgressView("Lese Apple Health …")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $model.rangeDays) {
                    ForEach(HealthExplorerModel.rangeOptions, id: \.self) { days in
                        Text("\(days) Tage").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.state == .loading)
            } footer: {
                if let loadedAt = model.loadedAt {
                    Text("Stand: \(ExplorerFormat.dateTime(loadedAt)). Zum Aktualisieren nach unten ziehen.")
                }
            }

            Section {
                ForEach(model.summaries) { summary in
                    NavigationLink {
                        MetricDetailView(summary: summary)
                    } label: {
                        MetricRow(summary: summary)
                    }
                }
            } footer: {
                Text("„Keine Daten“ heißt: Es gibt keine Werte oder Cockpit hat keinen Lesezugriff. iOS verrät nicht, welches von beiden. Prüfen in der Health-App: Profil → Apps → Cockpit.")
            }
        }
        .overlay {
            if model.state == .loading {
                ProgressView()
            }
        }
    }
}

private struct MetricRow: View {
    let summary: MetricSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.metric.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.metric.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.hasMultipleSources {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Mehrere Quellen")
            }
        }
    }

    private var subtitle: String {
        guard summary.totalCount > 0 else { return "Keine Daten" }
        let sources = summary.sources.count == 1 ? "1 Quelle" : "\(summary.sources.count) Quellen"
        let covered = summary.days.count - summary.missingDays.count
        return "\(summary.totalCount) Werte · \(sources) · \(covered)/\(summary.days.count) Tage"
    }
}

#Preview {
    NavigationStack {
        HealthExplorerView()
    }
}
