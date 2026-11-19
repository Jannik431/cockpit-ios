import Foundation

nonisolated struct ChartPoint: Sendable, Equatable, Identifiable {
    let day: Date
    let value: Double
    /// Points are only connected within a segment, so missing days show up as gaps instead of being interpolated.
    let segment: Int
    /// True if the point has no neighbour in its segment (would be invisible as a line).
    let isolated: Bool

    var id: Date { day }
}

nonisolated enum ChartSeries {
    static func points(days: [Date], values: [Date: Double]) -> [ChartPoint] {
        var raw: [(day: Date, value: Double, segment: Int)] = []
        var segment = 0
        var previousMissing = false
        for day in days {
            guard let value = values[day] else {
                previousMissing = true
                continue
            }
            if previousMissing, !raw.isEmpty { segment += 1 }
            previousMissing = false
            raw.append((day, value, segment))
        }
        let sizes = Dictionary(grouping: raw, by: \.segment).mapValues(\.count)
        return raw.map { ChartPoint(day: $0.day, value: $0.value, segment: $0.segment, isolated: sizes[$0.segment] == 1) }
    }
}
