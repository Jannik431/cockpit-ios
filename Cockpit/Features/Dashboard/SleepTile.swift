import Charts
import SwiftUI

/// Sleep: duration compared with the norm, plus last night's stages as a hypnogram.
struct SleepTile: View {
    let assessment: MetricAssessment
    let night: DailyMetrics?

    private var segments: [SleepSegment] {
        night?.sleepSegments.filter { $0.sleepStage != nil && $0.sleepStage != .inBed } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(assessment: assessment)

            if segments.isEmpty {
                Text(night?.asleepMin == nil ? "Für letzte Nacht gibt es noch keine Schlafdaten." : "Für diese Nacht sind keine Schlafphasen gespeichert.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                Hypnogram(segments: segments, start: night?.inBedStart, end: night?.inBedEnd)
                    .frame(height: 118)
                StageLegend(night: night)
            }

            TileFooter(assessment: assessment)

            if let start = night?.inBedStart, let end = night?.inBedEnd {
                Text("Im Bett \(MetricsFormat.timeRange(start, end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: assessment) + legendAccessibility)
    }

    private var legendAccessibility: String {
        guard let night else { return "" }
        let parts = StageLegend.entries(for: night).map { "\($0.stage.shortTitle) \(MetricsFormat.minutes($0.minutes))" }
        return parts.isEmpty ? "" : ". " + parts.joined(separator: ", ")
    }
}

/// Stage rows from deep (bottom) to awake (top) across the night.
private struct Hypnogram: View {
    let segments: [SleepSegment]
    let start: Date?
    let end: Date?

    private static let rows: [SleepStage] = [.asleepDeep, .asleepCore, .asleepREM, .awake]

    /// Vertical connectors where one stage directly follows another.
    private var transitions: [(time: Date, from: Int, to: Int)] {
        zip(segments, segments.dropFirst()).compactMap { current, next in
            guard abs(next.start.timeIntervalSince(current.end)) < 120,
                  let a = current.sleepStage?.level, let b = next.sleepStage?.level, a != b
            else { return nil }
            return (next.start, a, b)
        }
    }

    var body: some View {
        Chart {
            ForEach(Array(transitions.enumerated()), id: \.offset) { _, transition in
                RuleMark(
                    x: .value("Wechsel", transition.time),
                    yStart: .value("von", Double(min(transition.from, transition.to))),
                    yEnd: .value("bis", Double(max(transition.from, transition.to)))
                )
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }

            ForEach(segments, id: \.start) { segment in
                let stage = segment.sleepStage ?? .asleepUnspecified
                RectangleMark(
                    xStart: .value("Beginn", segment.start),
                    xEnd: .value("Ende", segment.end),
                    yStart: .value("unten", Double(stage.level) - 0.4),
                    yEnd: .value("oben", Double(stage.level) + 0.4)
                )
                .foregroundStyle(stage.color)
                .cornerRadius(2)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -0.55...3.55)
        .chartYAxis {
            AxisMarks(position: .leading, values: Self.rows.map { Double($0.level) }) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let level = value.as(Double.self), let stage = Self.rows.first(where: { Double($0.level) == level }) {
                        Text(stage.shortTitle)
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.15))
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(MetricsFormat.time(date))
                            .font(.caption2)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var domain: ClosedRange<Date> {
        let first = min(start ?? .distantFuture, segments.first?.start ?? .now)
        let last = max(end ?? .distantPast, segments.map(\.end).max() ?? .now)
        return first...max(last, first.addingTimeInterval(60))
    }
}

/// "● Tief 1 h 12 min  ● Kern …"
private struct StageLegend: View {
    let night: DailyMetrics?

    struct Entry {
        let stage: SleepStage
        let minutes: Int
    }

    static func entries(for night: DailyMetrics) -> [Entry] {
        let all: [(SleepStage, Int?)] = [
            (.asleepDeep, night.deepMin),
            (.asleepCore, night.coreMin),
            (.asleepUnspecified, night.unspecifiedMin),
            (.asleepREM, night.remMin),
            (.awake, night.awakeMin),
        ]
        return all.compactMap { stage, minutes in minutes.map { Entry(stage: stage, minutes: $0) } }
    }

    var body: some View {
        if let night {
            HStack(spacing: 0) {
                ForEach(Self.entries(for: night), id: \.stage) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(entry.stage.color)
                                .frame(width: 7, height: 7)
                            Text(entry.stage.shortTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(MetricsFormat.minutes(entry.minutes))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
