import Foundation
import SwiftData

/// Reads Apple Health and upserts `DailyMetrics` and `HealthWorkout`.
/// First run: the last `initialDays` days. Later runs: from the latest stored day minus `overlapDays`,
/// so late syncs from the tracker app are picked up.
final class HealthImporter {
    static let initialDays = 90
    static let overlapDays = 3
    /// Raise when stored fields change; the next run then re-imports all `initialDays` once.
    /// 2: sleep stage segments.
    static let dataVersion = 2
    private static let versionKey = "healthImportDataVersion"

    struct Result: Equatable {
        let days: Int
        let newWorkouts: Int
    }

    private let reader: HealthKitReader
    private let defaults: UserDefaults

    init(reader: HealthKitReader = HealthKitReader(), defaults: UserDefaults = .standard) {
        self.reader = reader
        self.defaults = defaults
    }

    func importRecent(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) async throws -> Result {
        let days = try daysToImport(context: context, now: now, calendar: calendar)
        guard let first = days.first else { return Result(days: 0, newWorkouts: 0) }

        // Sleep ending on the first day may start the evening before.
        let queryStart = calendar.date(byAdding: .hour, value: DailyValuesBuilder.hrvFallbackStartHours, to: first) ?? first
        let interval = DateInterval(start: queryStart, end: now)

        let sleep = try await reader.samples(for: .sleep, in: interval)
        let hrv = try await reader.samples(for: .hrv, in: interval)
        let resting = try await reader.samples(for: .restingHeartRate, in: interval)
        let workouts = try await reader.samples(for: .workouts, in: DateInterval(start: first, end: now))

        let values = DailyValuesBuilder.build(sleep: sleep, hrv: hrv, restingHR: resting, days: days, calendar: calendar)
        let result = try Self.store(values: values, workouts: workouts, in: context, fetchedAt: now, calendar: calendar)
        defaults.set(Self.dataVersion, forKey: Self.versionKey)
        return result
    }

    private func daysToImport(context: ModelContext, now: Date, calendar: Calendar) throws -> [Date] {
        var latest = FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.day, order: .reverse)])
        latest.fetchLimit = 1
        let today = LocalDay.start(of: now, calendar: calendar)

        let upToDate = defaults.integer(forKey: Self.versionKey) >= Self.dataVersion
        guard upToDate, let lastDay = try context.fetch(latest).first?.day else {
            return LocalDay.window(endingAt: today, count: Self.initialDays, calendar: calendar)
        }
        let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        let count = min(max(gap + 1 + Self.overlapDays, 1), Self.initialDays)
        return LocalDay.window(endingAt: today, count: count, calendar: calendar)
    }

    /// Upserts by day and by HealthKit UUID. Separate from HealthKit so it can be tested with an in-memory store.
    static func store(
        values: [DailyValues],
        workouts: [SampleRecord],
        in context: ModelContext,
        fetchedAt: Date,
        calendar: Calendar = .current
    ) throws -> Result {
        guard let first = values.map(\.day).min() else { return Result(days: 0, newWorkouts: 0) }

        let existing = try context.fetch(FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.day >= first }))
        let byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for value in values {
            let metrics = byDay[value.day] ?? {
                let new = DailyMetrics(day: value.day, fetchedAt: fetchedAt)
                context.insert(new)
                return new
            }()
            metrics.apply(value, fetchedAt: fetchedAt)
        }

        let workoutRecords = DailyValuesBuilder.filterToDominantSource(workouts)
        let ids = workoutRecords.compactMap(\.healthID)
        let known = Set(try context.fetch(FetchDescriptor<HealthWorkout>(predicate: #Predicate { ids.contains($0.healthID) })).map(\.healthID))
        var inserted = 0
        for record in workoutRecords {
            guard let id = record.healthID, !known.contains(id) else { continue }
            context.insert(HealthWorkout(
                healthID: id,
                day: LocalDay.start(of: record.start, calendar: calendar),
                start: record.start,
                end: record.end,
                activityTypeRaw: record.category ?? -1,
                activityTypeName: record.label,
                sourceBundleID: record.sourceBundleID
            ))
            inserted += 1
        }

        try context.save()
        return Result(days: values.count, newWorkouts: inserted)
    }
}
