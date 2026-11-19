import Charts
import SwiftUI

/// Everything one tile needs, derived from stored days.
struct MetricTileModel: Identifiable {
    let assessment: MetricAssessment
    /// Last `chartDays` days including the assessed day.
    let points: [ChartPoint]
    /// Colour of each charted day, judged against that day's own norm.
    let impacts: [Date: Impact]
    let chartDays: [Date]
    let normRange: ClosedRange<Double>?

    /// 10 days show day-to-day changes; 30 days looked too flat.
    static let chartDayCount = 10

    var id: BaselineMetric { assessment.metric }
    var metric: BaselineMetric { assessment.metric }

    static func tiles(on day: Date, from all: [DailyMetrics], calendar: Calendar = .current) -> [MetricTileModel] {
        let days = LocalDay.window(endingAt: day, count: chartDayCount, calendar: calendar)
        return BaselineMetric.allCases.map { metric in
            let values = DailyMetrics.values(for: metric, from: all)
            let assessment = BaselineCalculator.assess(metric, on: day, values: values, calendar: calendar)
            var impacts: [Date: Impact] = [:]
            for chartDay in days {
                impacts[chartDay] = BaselineCalculator.assess(metric, on: chartDay, values: values, calendar: calendar).impact
            }
            return MetricTileModel(
                assessment: assessment,
                points: ChartSeries.points(days: days, values: values),
                impacts: impacts,
                chartDays: days,
                normRange: assessment.norm.map { BaselineCalculator.normRange($0, logScale: metric.usesLogScale) }
            )
        }
    }
}

/// Shared top part of every tile: title, status chip, big value, difference to the norm.
struct TileHeader: View {
    let assessment: MetricAssessment

    var body: some View {
        HStack {
            Label(assessment.metric.shortTitle, systemImage: assessment.metric.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(assessment.metric.accent)
            Spacer()
            chip
        }

        HStack(alignment: .firstTextBaseline) {
            BigValue(parts: MetricsFormat.valueParts(assessment.value, for: assessment.metric))
            Spacer()
            if case .available(let deviation) = assessment.status {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(MetricsFormat.difference(deviation.difference, for: assessment.metric))
                        .font(.headline)
                        .monospacedDigit()
                    Text("zur Norm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var chip: some View {
        switch assessment.status {
        case .available(let deviation):
            StatusChip(text: deviation.band.shortTitle, tint: assessment.impact?.tint ?? .gray)
        case .missingValue:
            StatusChip(text: "noch kein Wert", tint: .gray)
        case .insufficientData:
            StatusChip(text: "Norm im Aufbau", tint: .gray)
        }
    }
}

/// Norm summary and 7-day trend.
struct TileFooter: View {
    let assessment: MetricAssessment

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            switch assessment.status {
            case .insufficientData(let count, let required):
                Text("Norm ab \(required) Tagen mit Wert, bisher \(count)")
            case .available, .missingValue:
                if let norm = assessment.norm {
                    Text("Norm \(MetricsFormat.value(norm.median, for: assessment.metric)) · \(norm.count)/\(norm.windowDays) Tage")
                }
            }
            Spacer(minLength: 8)
            if let trend = assessment.shortTermDeviation {
                Text("7 Tage \(MetricsFormat.difference(trend.difference, for: assessment.metric))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// HRV and resting heart rate: value plus the last 10 days.
struct MetricTile: View {
    let model: MetricTileModel
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(assessment: model.assessment)

            RecentDaysChart(model: model)
                .frame(height: 96)

            TileFooter(assessment: model.assessment)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: model.assessment))
    }
}

func accessibilityText(for assessment: MetricAssessment) -> String {
    "\(assessment.metric.title): \(MetricsFormat.value(assessment.value, for: assessment.metric)). \(MetricsFormat.assessmentLine(assessment))"
}

/// Large number with smaller units, e.g. "7 h 40 min".
struct BigValue: View {
    let parts: [MetricsFormat.ValuePart]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            ForEach(parts, id: \.self) { part in
                Text(part.number)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if !part.unit.isEmpty {
                    Text(part.unit)
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Last 10 days as points coloured by impact, the norm range as a band. Gaps stay gaps.
struct RecentDaysChart: View {
    let model: MetricTileModel

    var body: some View {
        let color = model.metric.accent
        let today = model.assessment.day

        Chart {
            if let range = model.normRange, let median = model.assessment.norm?.median {
                RectangleMark(
                    xStart: .value("Beginn", domain.lowerBound),
                    xEnd: .value("Ende", domain.upperBound),
                    yStart: .value("Norm unten", range.lowerBound),
                    yEnd: .value("Norm oben", range.upperBound)
                )
                .foregroundStyle(color.opacity(0.12))

                RuleMark(y: .value("Norm", median))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(color.opacity(0.45))
            }

            ForEach(model.points) { point in
                LineMark(
                    x: .value("Tag", point.day),
                    y: .value("Wert", point.value),
                    series: .value("Abschnitt", point.segment)
                )
                .foregroundStyle(color.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(model.points) { point in
                let isToday = point.day == today
                PointMark(x: .value("Tag", point.day), y: .value("Wert", point.value))
                    .foregroundStyle(Theme.cardBackground)
                    .symbolSize(isToday ? 170 : 75)
                PointMark(x: .value("Tag", point.day), y: .value("Wert", point.value))
                    .foregroundStyle(model.impacts[point.day]?.tint ?? color)
                    .symbolSize(isToday ? 85 : 32)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: model.chartDays) { value in
                if let day = value.as(Date.self) {
                    AxisValueLabel(anchor: .top) {
                        Text(day.formatted(.dateTime.weekday(.short).locale(ExplorerFormat.locale)))
                            .font(.caption2)
                            .fontWeight(day == today ? .bold : .regular)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Half a day of padding on both sides so the outer points are not clipped.
    private var domain: ClosedRange<Date> {
        let first = model.chartDays.first ?? model.assessment.day
        let last = model.chartDays.last ?? model.assessment.day
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    private var yDomain: ClosedRange<Double> {
        var values = model.points.map(\.value)
        if let range = model.normRange {
            values += [range.lowerBound, range.upperBound]
        }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.18, 1)
        return (low - padding)...(high + padding)
    }
}
