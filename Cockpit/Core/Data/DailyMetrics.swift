import Foundation
import SwiftData

/// Stored Apple Health values per local calendar day (see `DailyValues`). Re-importable from Apple Health.
@Model
final class DailyMetrics {
    @Attribute(.unique) var day: Date

    var inBedStart: Date?
    var inBedEnd: Date?
    var asleepMin: Int?
    var awakeMin: Int?
    var coreMin: Int?
    var deepMin: Int?
    var remMin: Int?
    var unspecifiedMin: Int?
    var sleepSource: String?

    /// Always `HRVMetric.id` when HRV values are present.
    var hrvMetric: String?
    var hrvSamplesJSON: Data?
    var hrvNightMeanMs: Double?
    var hrvSource: String?

    var restingHR: Double?
    var restingHRSource: String?

    var fetchedAt: Date

    init(day: Date, fetchedAt: Date = .now) {
        self.day = day
        self.fetchedAt = fetchedAt
    }

    var hrvSamples: [HRVSample] {
        guard let hrvSamplesJSON else { return [] }
        return (try? JSONDecoder().decode([HRVSample].self, from: hrvSamplesJSON)) ?? []
    }

    func apply(_ values: DailyValues, fetchedAt: Date) {
        inBedStart = values.inBedStart
        inBedEnd = values.inBedEnd
        asleepMin = values.asleepMin
        awakeMin = values.awakeMin
        coreMin = values.coreMin
        deepMin = values.deepMin
        remMin = values.remMin
        unspecifiedMin = values.unspecifiedMin
        sleepSource = values.sleepSource

        hrvMetric = values.hrvSamples.isEmpty ? nil : HRVMetric.id
        hrvSamplesJSON = values.hrvSamples.isEmpty ? nil : try? JSONEncoder().encode(values.hrvSamples)
        hrvNightMeanMs = values.hrvNightMeanMs
        hrvSource = values.hrvSource

        restingHR = values.restingHR
        restingHRSource = values.restingHRSource

        self.fetchedAt = fetchedAt
    }
}
