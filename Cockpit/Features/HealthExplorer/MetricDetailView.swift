import SwiftUI

struct MetricDetailView: View {
    let summary: MetricSummary

    var body: some View {
        List {
            if summary.sources.isEmpty {
                ContentUnavailableView(
                    "Keine Daten",
                    systemImage: summary.metric.systemImage,
                    description: Text("Im gewählten Zeitraum gibt es keine Werte, oder Cockpit hat keinen Lesezugriff auf \(summary.metric.title).")
                )
            }

            if summary.hasMultipleSources {
                Section {
                    Label("Mehrere Quellen schreiben diesen Wert. Später nach Quelle filtern und Quellen nicht mischen.", systemImage: "square.stack.3d.up.fill")
                        .foregroundStyle(.orange)
                }
            }

            ForEach(summary.sources) { source in
                SourceSection(source: source, metric: summary.metric, totalDays: summary.days.count)
            }

            if !summary.sources.isEmpty {
                MissingDaysSection(days: summary.missingDays)
            }
        }
        .navigationTitle(summary.metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SourceSection: View {
    let source: SourceSummary
    let metric: HealthMetric
    let totalDays: Int

    var body: some View {
        Section {
            row("Bundle-ID", source.bundleID)
            if !source.devices.isEmpty {
                row("Geräte", source.devices.joined(separator: ", "))
            }
            row("Werte", "\(source.count)")
            row("Tage mit Daten", "\(source.daysWithData) von \(totalDays)")
            row("Werte pro Tag (Median)", ExplorerFormat.number(source.medianSamplesPerDay))
            row("Häufigste Uhrzeiten", ExplorerFormat.hours(source.commonHours))
            row("Erster Wert", ExplorerFormat.dateTime(source.firstStart))
            row("Letzter Wert", "\(ExplorerFormat.dateTime(source.lastEnd)) (\(source.lastEnd.formatted(.relative(presentation: .named).locale(ExplorerFormat.locale))))")

            if let values = source.values {
                row("Min / Median / Max", [values.min, values.median, values.max]
                    .map { ExplorerFormat.value($0, metric: metric) }
                    .joined(separator: " / "))
            }

            if let sleep = source.sleep {
                row("Nächte", "\(sleep.nights)")
                row("Schlaf pro Nacht (Median)", sleep.medianAsleepMinutesPerNight.map { ExplorerFormat.duration(minutes: $0) } ?? "–")
                ForEach(sleep.stages, id: \.rawValue) { stage in
                    row(stage.stage?.title ?? "Unbekannt (\(stage.rawValue))",
                        "\(stage.count)× · \(ExplorerFormat.duration(minutes: stage.totalMinutes))")
                }
            }

            if !source.labels.isEmpty {
                ForEach(source.labels, id: \.label) { label in
                    row(label.label, "\(label.count)×")
                }
            }

            DisclosureGroup("Letzte Werte") {
                ForEach(source.recent, id: \.self) { record in
                    row(ExplorerFormat.dateTime(record.start), ExplorerFormat.sample(record, metric: metric))
                }
            }
        } header: {
            Text(source.name)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct MissingDaysSection: View {
    let days: [Date]
    private let visibleLimit = 14

    var body: some View {
        Section {
            if days.isEmpty {
                Text("Keine Lücken")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(days.suffix(visibleLimit).reversed(), id: \.self) { day in
                    Text(ExplorerFormat.day(day))
                }
                if days.count > visibleLimit {
                    Text("und \(days.count - visibleLimit) weitere")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tage ohne Daten (\(days.count))")
        }
    }
}
