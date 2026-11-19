import Foundation

/// What the Health Explorer shows per metric: which sources write data, how often, when, and where gaps are.
nonisolated struct MetricSummary: Sendable, Identifiable {
    let metric: HealthMetric
    /// Local calendar days covered by the query, oldest first.
    let days: [Date]
    let sources: [SourceSummary]
    /// Days on which no source delivered anything.
    let missingDays: [Date]

    var id: HealthMetric { metric }
    var totalCount: Int { sources.reduce(0) { $0 + $1.count } }
    var hasMultipleSources: Bool { sources.count > 1 }
}

nonisolated struct SourceSummary: Sendable, Identifiable {
    let name: String
    let bundleID: String
    let devices: [String]
    let count: Int
    let firstStart: Date
    let lastEnd: Date
    let daysWithData: Int
    /// Median number of samples on days that have data.
    let medianSamplesPerDay: Double
    /// Up to three most frequent local start hours (0–23), most frequent first.
    let commonHours: [Int]
    let values: ValueStats?
    let sleep: SleepSummary?
    let labels: [LabelCount]
    /// Most recent samples, newest first (at most 5).
    let recent: [SampleRecord]

    var id: String { bundleID + "|" + name }
}

nonisolated struct ValueStats: Sendable, Equatable {
    let min: Double
    let median: Double
    let max: Double
    let latest: Double
}

nonisolated struct SleepSummary: Sendable, Equatable {
    struct Stage: Sendable, Equatable {
        let stage: SleepStage?
        let rawValue: Int
        let count: Int
        let totalMinutes: Double
    }

    let stages: [Stage]
    /// Distinct wake days with at least one asleep sample.
    let nights: Int
    /// Median of summed asleep minutes per wake day. Can be inflated if a source writes overlapping samples.
    let medianAsleepMinutesPerNight: Double?
}

nonisolated struct LabelCount: Sendable, Equatable {
    let label: String
    let count: Int
}

nonisolated enum ExplorerSummaryBuilder {
    static func summarize(
        _ records: [SampleRecord],
        metric: HealthMetric,
        days: [Date],
        calendar: Calendar = .current
    ) -> MetricSummary {
        let dayOf: (SampleRecord) -> Date = { record in
            metric.usesWakeDay
                ? LocalDay.wakeDay(forSleepEndingAt: record.end, calendar: calendar)
                : LocalDay.start(of: record.start, calendar: calendar)
        }

        let grouped = Dictionary(grouping: records) { SourceKey(name: $0.sourceName, bundleID: $0.sourceBundleID) }
        let sources = grouped
            .map { key, records in summarizeSource(key: key, records: records, metric: metric, dayOf: dayOf, calendar: calendar) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        let coveredDays = Set(records.map(dayOf))
        let missing = days.filter { !coveredDays.contains($0) }

        return MetricSummary(metric: metric, days: days, sources: sources, missingDays: missing)
    }

    private struct SourceKey: Hashable {
        let name: String
        let bundleID: String
    }

    private static func summarizeSource(
        key: SourceKey,
        records: [SampleRecord],
        metric: HealthMetric,
        dayOf: (SampleRecord) -> Date,
        calendar: Calendar
    ) -> SourceSummary {
        let newestFirst = records.sorted { $0.end > $1.end }
        let perDay = Dictionary(grouping: records, by: dayOf)
        let hourCounts = Dictionary(grouping: records) { calendar.component(.hour, from: $0.start) }
            .mapValues(\.count)
        let commonHours = hourCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map(\.key)

        let values = metric == .sleep || metric == .workouts
            ? nil
            : valueStats(newestFirst.compactMap(\.value))

        let labels = Dictionary(grouping: records.compactMap(\.label)) { $0 }
            .map { LabelCount(label: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }

        return SourceSummary(
            name: key.name,
            bundleID: key.bundleID,
            devices: Array(Set(records.compactMap(\.deviceName))).sorted(),
            count: records.count,
            firstStart: records.map(\.start).min() ?? .distantPast,
            lastEnd: newestFirst.first?.end ?? .distantPast,
            daysWithData: perDay.count,
            medianSamplesPerDay: median(perDay.values.map { Double($0.count) }) ?? 0,
            commonHours: commonHours,
            values: values,
            sleep: metric == .sleep ? sleepSummary(records, dayOf: dayOf) : nil,
            labels: labels,
            recent: Array(newestFirst.prefix(5))
        )
    }

    private static func valueStats(_ newestFirst: [Double]) -> ValueStats? {
        guard let latest = newestFirst.first,
              let min = newestFirst.min(),
              let max = newestFirst.max(),
              let median = median(newestFirst)
        else { return nil }
        return ValueStats(min: min, median: median, max: max, latest: latest)
    }

    private static func sleepSummary(_ records: [SampleRecord], dayOf: (SampleRecord) -> Date) -> SleepSummary {
        let byValue = Dictionary(grouping: records.filter { $0.category != nil }) { $0.category! }
        let stages = byValue
            .map { raw, records in
                SleepSummary.Stage(
                    stage: SleepStage(rawValue: raw),
                    rawValue: raw,
                    count: records.count,
                    totalMinutes: records.reduce(0) { $0 + $1.durationMinutes }
                )
            }
            .sorted { $0.rawValue < $1.rawValue }

        let asleep = records.filter { record in
            record.category.flatMap(SleepStage.init(rawValue:))?.isAsleep ?? false
        }
        let minutesPerNight = Dictionary(grouping: asleep, by: dayOf)
            .mapValues { $0.reduce(0) { $0 + $1.durationMinutes } }

        return SleepSummary(
            stages: stages,
            nights: minutesPerNight.count,
            medianAsleepMinutesPerNight: median(Array(minutesPerNight.values))
        )
    }

    static func median(_ values: [Double]) -> Double? {
        Statistics.median(values)
    }
}
