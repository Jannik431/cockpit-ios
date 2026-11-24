import Charts
import SwiftData
import SwiftUI

/// Training load (session RPE × minutes) over weeks and days, with knee pain alongside.
struct LoadView: View {
    @Query(sort: \HealthWorkout.start) private var workouts: [HealthWorkout]
    @Query(sort: \CompletedSession.start) private var sessions: [CompletedSession]
    @Query(sort: \QuestionnaireEntry.day) private var entries: [QuestionnaireEntry]

    private var today: Date { LocalDay.logicalToday() }
    private var loadEntries: [LoadEntry] { TrainingData.loadEntries(workouts: workouts, logs: sessions) }
    private var firstDay: Date { loadEntries.map(\.day).min() ?? today }

    var body: some View {
        let entries = loadEntries
        let summary = LoadMetrics.summary(entries, today: today, firstDay: firstDay)
        let weeks = LoadMetrics.weeks(entries, endingAt: today, count: 12)
        let days = LocalDay.window(endingAt: today, count: LoadMetrics.chronicDays)
        let daily = LoadMetrics.dailyLoads(entries, days: days)

        List {
            Section {
                SummaryGrid(summary: summary)
                if summary.unrated > 0 {
                    Label("\(summary.unrated) \(summary.unrated == 1 ? "Einheit" : "Einheiten") der letzten 7 Tage ohne RPE – die Last ist dadurch zu niedrig.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Überblick")
            } footer: {
                Text("Last = Session-RPE × Minuten (AU). Akut:Chronisch = 7-Tage-Last ÷ Ø Wochenlast der letzten 28 Tage; das Verhältnis ist in der Sportwissenschaft umstritten und nur ein grober Hinweis. Monotonie = Mittel ÷ Streuung der Tageslasten der letzten 7 Tage, Strain = Wochenlast × Monotonie (Foster).")
            }

            Section("Wochenlast (12 Wochen)") {
                WeeklyChart(weeks: weeks)
                    .frame(height: 200)
                    .padding(.vertical, 8)
            }

            Section {
                DailyChart(days: days, daily: daily)
                    .frame(height: 140)
                    .padding(.top, 8)
                KneeChart(days: days, entries: self.entries, sessions: sessions)
                    .frame(height: 150)
                    .padding(.bottom, 8)
            } header: {
                Text("Tageslast und Knie (28 Tage)")
            } footer: {
                Text("Knie morgens links/rechts als Linien, Knie während der Einheit (höherer Wert) als Punkte.")
            }

            Section("Wurfvolumen pro Woche") {
                ThrowChart(weeks: weeks)
                    .frame(height: 160)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle("Belastung")
    }
}

private struct SummaryGrid: View {
    let summary: LoadSummary

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                tile("7 Tage", MetricsFormat.load(summary.acute) + " AU")
                tile("Ø Woche (28 T.)", summary.chronicWeekly.map { MetricsFormat.load(Int($0.rounded())) + " AU" } ?? "ab 28 Tagen")
            }
            GridRow {
                tile("Akut:Chronisch", summary.ratio.map { ExplorerFormat.number($0, digits: 2) } ?? "–")
                tile("Monotonie · Strain", summary.monotony.map {
                    "\(ExplorerFormat.number($0, digits: 2)) · \(MetricsFormat.load(Int((summary.strain ?? 0).rounded())))"
                } ?? "–")
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeeklyChart: View {
    let weeks: [WeekLoad]

    var body: some View {
        Chart {
            ForEach(weeks) { week in
                ForEach(SessionKind.allCases, id: \.self) { kind in
                    if let load = week.byKind[kind], load > 0 {
                        BarMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Last", load))
                            .foregroundStyle(by: .value("Art", kind.title))
                    }
                }
            }
        }
        .chartForegroundStyleScale(["Gym": Color.indigo, "Handball": Color.green, "Sonstiges": Color.orange])
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.twoDigits).locale(ExplorerFormat.locale))
            }
        }
    }
}

private struct DailyChart: View {
    let days: [Date]
    let daily: [Date: Int]

    var body: some View {
        Chart {
            ForEach(days, id: \.self) { day in
                BarMark(x: .value("Tag", day, unit: .day), y: .value("Last", daily[day] ?? 0))
                    .foregroundStyle(Color.green.gradient)
            }
        }
        .chartXScale(domain: (days.first ?? .now)...(days.last ?? .now).addingTimeInterval(86_400))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
    }
}

private struct KneeChart: View {
    let days: [Date]
    let entries: [QuestionnaireEntry]
    let sessions: [CompletedSession]

    private struct Point: Identifiable {
        let day: Date
        let value: Int
        let series: String
        var id: String { "\(series)-\(day.timeIntervalSince1970)" }
    }

    private var morning: [Point] {
        let range = Set(days)
        return entries.filter { $0.phase == CheckInPhase.morning.rawValue && range.contains($0.day) }.flatMap { entry in
            [("pain_knee_left_morning", "Knie links"), ("pain_knee_right_morning", "Knie rechts")].compactMap { id, series in
                entry.answers[id]?.intValue.map { Point(day: entry.day, value: $0, series: series) }
            }
        }
        .sorted { $0.day < $1.day }
    }

    private var underLoad: [Point] {
        let range = Set(days)
        return Dictionary(grouping: sessions.filter { range.contains($0.day) }, by: \.day).compactMap { day, logs in
            let values = logs.flatMap { [$0.kneePainLeft, $0.kneePainRight].compactMap { $0 } }
            return values.max().map { Point(day: day, value: $0, series: "Knie unter Belastung") }
        }
    }

    var body: some View {
        Chart {
            ForEach(morning) { point in
                LineMark(x: .value("Tag", point.day, unit: .day), y: .value("Schmerz", point.value))
                    .foregroundStyle(by: .value("Reihe", point.series))
                    .symbol(by: .value("Reihe", point.series))
            }
            ForEach(underLoad) { point in
                PointMark(x: .value("Tag", point.day, unit: .day), y: .value("Schmerz", point.value))
                    .foregroundStyle(by: .value("Reihe", point.series))
                    .symbolSize(60)
            }
        }
        .chartForegroundStyleScale(["Knie links": Color.purple, "Knie rechts": Color.pink, "Knie unter Belastung": Color.orange])
        .chartYScale(domain: 0...10)
        .chartXScale(domain: (days.first ?? .now)...(days.last ?? .now).addingTimeInterval(86_400))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.twoDigits).locale(ExplorerFormat.locale))
            }
        }
        .chartLegend(position: .bottom)
    }
}

private struct ThrowChart: View {
    let weeks: [WeekLoad]

    var body: some View {
        Chart {
            ForEach(weeks) { week in
                ForEach(week.throwVolumes.keys.sorted(), id: \.self) { index in
                    BarMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Einheiten", week.throwVolumes[index] ?? 0))
                        .foregroundStyle(by: .value("Wurfvolumen", SessionScales.throwVolumes[index]))
                }
            }
        }
        .chartForegroundStyleScale(domain: SessionScales.throwVolumes, range: [Color.green.opacity(0.35), Color.green.opacity(0.55), Color.orange.opacity(0.75), Color.red.opacity(0.8)])
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.twoDigits).locale(ExplorerFormat.locale))
            }
        }
    }
}
