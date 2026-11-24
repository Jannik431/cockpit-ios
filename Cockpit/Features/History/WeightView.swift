import Charts
import SwiftData
import SwiftUI

/// Body weight from the morning check: weigh-ins as points, trend (mean of the last 3) as a line.
struct WeightView: View {
    @Query(sort: \QuestionnaireEntry.day) private var entries: [QuestionnaireEntry]
    @State private var rangeDays = 90

    private static let ranges = [30, 90, 365]

    private var allPoints: [WeightPoint] { TrainingData.weightPoints(from: entries) }

    private var points: [WeightPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: .now) ?? .distantPast
        return allPoints.filter { $0.day >= start }
    }

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $rangeDays) {
                    ForEach(Self.ranges, id: \.self) { days in
                        Text(days == 365 ? "1 Jahr" : "\(days) Tage").tag(days)
                    }
                }
                .pickerStyle(.segmented)

                if points.isEmpty {
                    ContentUnavailableView("Noch keine Wiegung", systemImage: "scalemass",
                                           description: Text("Das Gewicht trägst du im Morgen-Check ein, am besten Mo, Mi und Fr vor dem Frühstück."))
                } else {
                    chart
                        .frame(height: 220)
                        .padding(.vertical, 8)
                }
            }

            if let last = allPoints.last {
                Section("Kennzahlen") {
                    LabeledContent("Letzte Wiegung", value: "\(ExplorerFormat.number(last.kg)) kg · \(ExplorerFormat.day(last.day))")
                    if let trend = WeightTrend.trend(allPoints).last {
                        LabeledContent("Trend", value: "\(ExplorerFormat.number(trend.kg)) kg")
                    }
                    LabeledContent("Veränderung", value: WeightTrend.weeklyChange(allPoints).map {
                        "\($0 < 0 ? "−" : "+")\(ExplorerFormat.number(abs($0), digits: 2)) kg pro Woche"
                    } ?? "ab 2 Wochen Daten")
                }

                Section("Wiegungen") {
                    ForEach(allPoints.reversed().prefix(15)) { point in
                        LabeledContent(ExplorerFormat.day(point.day), value: "\(ExplorerFormat.number(point.kg)) kg")
                    }
                }
            }

            Section {
            } footer: {
                Text("Trend = Mittel der letzten \(WeightTrend.window) Wiegungen, also etwa einer Woche. Einzelne Wiegungen schwanken durch Wasser und Essen um 1–2 kg; aussagekräftig ist der Trend.")
            }
        }
        .navigationTitle("Gewicht")
    }

    private var chart: some View {
        let trend = WeightTrend.trend(allPoints).filter { point in points.contains { $0.day == point.day } }
        let values = points.map(\.kg) + trend.map(\.kg)
        let low = (values.min() ?? 0) - 0.5
        let high = (values.max() ?? 1) + 0.5

        return Chart {
            ForEach(points) { point in
                PointMark(x: .value("Tag", point.day), y: .value("Gewicht", point.kg))
                    .foregroundStyle(Color.blue.opacity(0.45))
                    .symbolSize(30)
            }
            ForEach(trend) { point in
                LineMark(x: .value("Tag", point.day), y: .value("Trend", point.kg))
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: low...high)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kg = value.as(Double.self) { Text("\(ExplorerFormat.number(kg)) kg") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(ExplorerFormat.locale))
            }
        }
    }
}
