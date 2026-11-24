import Foundation

nonisolated struct WeightPoint: Sendable, Equatable, Identifiable {
    let day: Date
    let kg: Double

    var id: Date { day }
}

/// Body weight trend from irregular weigh-ins (about three per week).
nonisolated enum WeightTrend {
    /// Mean of the last this-many weigh-ins, i.e. roughly one week.
    static let window = 3

    /// Trend value at each weigh-in, oldest first.
    static func trend(_ points: [WeightPoint]) -> [WeightPoint] {
        let sorted = points.sorted { $0.day < $1.day }
        return sorted.indices.map { index in
            let slice = sorted[max(0, index - window + 1)...index]
            return WeightPoint(day: sorted[index].day, kg: slice.map(\.kg).reduce(0, +) / Double(slice.count))
        }
    }

    /// Change of the trend in kg per week, measured over at least 14 days. `nil` with too little data.
    static func weeklyChange(_ points: [WeightPoint], minimumSpanDays: Int = 14) -> Double? {
        let trend = trend(points)
        guard let last = trend.last else { return nil }
        let earlier = trend.last { last.day.timeIntervalSince($0.day) >= Double(minimumSpanDays) * 86_400 }
        guard let earlier else { return nil }
        let days = last.day.timeIntervalSince(earlier.day) / 86_400
        return (last.kg - earlier.kg) / days * 7
    }
}
