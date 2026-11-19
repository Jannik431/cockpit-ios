import Foundation

/// Markdown summary of the Health Explorer results, meant to be shared deliberately (e.g. pasted into a chat).
/// Contains aggregates only, no raw sample lists.
nonisolated enum ExplorerReport {
    static func markdown(_ summaries: [MetricSummary], rangeDays: Int, generatedAt: Date) -> String {
        var lines = [
            "# Health Explorer",
            "",
            "Zeitraum: letzte \(rangeDays) Tage · erstellt \(ExplorerFormat.dateTime(generatedAt))",
            "Hinweis: „keine Daten“ kann auch fehlender Lesezugriff sein.",
        ]

        for summary in summaries {
            lines.append("")
            lines.append("## \(summary.metric.title)")
            if summary.sources.isEmpty {
                lines.append("Keine Daten.")
                continue
            }
            lines.append("Werte gesamt: \(summary.totalCount) · Quellen: \(summary.sources.count) · Tage ohne Daten: \(summary.missingDays.count) von \(summary.days.count)")

            for source in summary.sources {
                lines.append("")
                lines.append("### \(source.name) (`\(source.bundleID)`)")
                if !source.devices.isEmpty {
                    lines.append("- Geräte: \(source.devices.joined(separator: ", "))")
                }
                lines.append("- Werte: \(source.count) an \(source.daysWithData) Tagen, Median \(ExplorerFormat.number(source.medianSamplesPerDay)) pro Tag")
                lines.append("- Zeitraum: \(ExplorerFormat.dateTime(source.firstStart)) bis \(ExplorerFormat.dateTime(source.lastEnd))")
                lines.append("- Häufigste Uhrzeiten: \(ExplorerFormat.hours(source.commonHours))")
                if let values = source.values {
                    let metric = summary.metric
                    lines.append("- Werte: min \(ExplorerFormat.value(values.min, metric: metric)), Median \(ExplorerFormat.value(values.median, metric: metric)), max \(ExplorerFormat.value(values.max, metric: metric))")
                }
                if let sleep = source.sleep {
                    lines.append("- Nächte: \(sleep.nights), Median Schlaf pro Nacht: \(sleep.medianAsleepMinutesPerNight.map { ExplorerFormat.duration(minutes: $0) } ?? "–")")
                    for stage in sleep.stages {
                        let name = stage.stage?.title ?? "Unbekannt (\(stage.rawValue))"
                        lines.append("  - \(name): \(stage.count)×, gesamt \(ExplorerFormat.duration(minutes: stage.totalMinutes))")
                    }
                }
                if !source.labels.isEmpty {
                    lines.append("- Typen: " + source.labels.map { "\($0.label) (\($0.count))" }.joined(separator: ", "))
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
