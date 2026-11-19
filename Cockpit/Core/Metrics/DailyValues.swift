import Foundation

/// Identifier of the HRV metric stored by Cockpit.
/// HealthKit's `heartRateVariabilitySDNN` as written by the source app. Tracker apps may show a different
/// measure (e.g. RMSSD) in their own UI; those numbers are not comparable and must never be mixed with this one.
nonisolated enum HRVMetric {
    static let id = "healthkit_sdnn"
    static let title = "HRV (SDNN, Apple Health)"
}

nonisolated struct HRVSample: Codable, Sendable, Equatable {
    let time: Date
    let ms: Double
}

/// All Apple Health values for one local calendar day. A night belongs to the day you wake up.
/// Missing values stay `nil`, they are never filled with 0.
nonisolated struct DailyValues: Sendable, Equatable {
    let day: Date

    var inBedStart: Date?
    var inBedEnd: Date?
    var asleepMin: Int?
    var awakeMin: Int?
    var coreMin: Int?
    var deepMin: Int?
    var remMin: Int?
    var unspecifiedMin: Int?
    var sleepSource: String?

    /// Raw HRV samples of the night, kept so the aggregation can be changed later.
    var hrvSamples: [HRVSample] = []
    /// Mean of `hrvSamples`.
    var hrvNightMeanMs: Double?
    var hrvSource: String?

    var restingHR: Double?
    var restingHRSource: String?

    init(day: Date) {
        self.day = day
    }
}

nonisolated enum DailyValuesBuilder {
    /// HRV samples count for a night if they start within the sleep window, extended by this much on both sides.
    static let hrvWindowPadding: TimeInterval = 30 * 60
    /// Without a sleep window, HRV samples from 18:00 the evening before until 12:00 count.
    static let hrvFallbackStartHours = -6
    static let hrvFallbackEndHours = 12
    /// Sleep samples closer together than this form one sleep session if the source writes no "in bed" samples.
    static let sleepClusterGap: TimeInterval = 60 * 60

    static func build(
        sleep: [SampleRecord],
        hrv: [SampleRecord],
        restingHR: [SampleRecord],
        days: [Date],
        calendar: Calendar = .current
    ) -> [DailyValues] {
        let sleep = filterToDominantSource(sleep)
        let hrv = filterToDominantSource(hrv)
        let restingHR = filterToDominantSource(restingHR)

        let nights = mainSleepSessions(sleep, calendar: calendar)
        let restingByDay = Dictionary(grouping: restingHR) { LocalDay.start(of: $0.start, calendar: calendar) }

        return days.map { day in
            var values = DailyValues(day: day)

            if let night = nights[day] {
                applySleep(night, records: sleep, to: &values)
            }

            let window = hrvWindow(for: values, day: day, calendar: calendar)
            let nightHRV = hrv
                .filter { window.contains($0.start) && $0.value != nil }
                .sorted { $0.start < $1.start }
            if !nightHRV.isEmpty {
                values.hrvSamples = nightHRV.map { HRVSample(time: $0.start, ms: $0.value!) }
                values.hrvNightMeanMs = values.hrvSamples.map(\.ms).reduce(0, +) / Double(nightHRV.count)
                values.hrvSource = nightHRV[0].sourceBundleID
            }

            if let latest = restingByDay[day]?.filter({ $0.value != nil }).max(by: { $0.end < $1.end }) {
                values.restingHR = latest.value
                values.restingHRSource = latest.sourceBundleID
            }

            return values
        }
    }

    // MARK: - Sources

    /// Sources are never mixed: only the source with the most samples is used (ties: alphabetical bundle ID).
    static func filterToDominantSource(_ records: [SampleRecord]) -> [SampleRecord] {
        let counts = Dictionary(grouping: records, by: \.sourceBundleID).mapValues(\.count)
        guard let dominant = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else {
            return []
        }
        return records.filter { $0.sourceBundleID == dominant }
    }

    // MARK: - Sleep

    private struct SleepSession {
        let start: Date
        let end: Date
        let fromInBed: Bool
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The longest sleep session per wake day. Shorter ones (naps) are ignored.
    private static func mainSleepSessions(_ records: [SampleRecord], calendar: Calendar) -> [Date: SleepSession] {
        let inBed = records.filter { $0.category == SleepStage.inBed.rawValue }
        let sessions: [SleepSession]
        if !inBed.isEmpty {
            sessions = inBed.map { SleepSession(start: $0.start, end: $0.end, fromInBed: true) }
        } else {
            sessions = clusters(of: records.filter { $0.category != SleepStage.inBed.rawValue })
        }
        return Dictionary(grouping: sessions) { LocalDay.wakeDay(forSleepEndingAt: $0.end, calendar: calendar) }
            .compactMapValues { $0.max { $0.duration < $1.duration } }
    }

    private static func clusters(of records: [SampleRecord]) -> [SleepSession] {
        var result: [SleepSession] = []
        for record in records.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, record.start.timeIntervalSince(last.end) <= sleepClusterGap {
                result[result.count - 1] = SleepSession(start: last.start, end: max(last.end, record.end), fromInBed: false)
            } else {
                result.append(SleepSession(start: record.start, end: record.end, fromInBed: false))
            }
        }
        return result
    }

    /// Stage samples belong to the night if their midpoint lies inside the session.
    private static func applySleep(_ night: SleepSession, records: [SampleRecord], to values: inout DailyValues) {
        values.inBedStart = night.start
        values.inBedEnd = night.end

        let stageRecords = records.filter { record in
            guard record.category != SleepStage.inBed.rawValue else { return false }
            let mid = record.start.addingTimeInterval(record.end.timeIntervalSince(record.start) / 2)
            return mid >= night.start && mid <= night.end
        }
        guard !stageRecords.isEmpty else { return }

        let minutes = Dictionary(grouping: stageRecords) { $0.category.flatMap(SleepStage.init(rawValue:)) }
            .mapValues { $0.reduce(0) { $0 + $1.durationMinutes } }
        let rounded: (SleepStage) -> Int? = { stage in minutes[stage].map { Int($0.rounded()) } }

        values.coreMin = rounded(.asleepCore)
        values.deepMin = rounded(.asleepDeep)
        values.remMin = rounded(.asleepREM)
        values.unspecifiedMin = rounded(.asleepUnspecified)
        values.awakeMin = rounded(.awake)

        let asleep = SleepStage.allCases.filter(\.isAsleep).compactMap { minutes[$0] }
        values.asleepMin = asleep.isEmpty ? nil : Int(asleep.reduce(0, +).rounded())
        values.sleepSource = stageRecords[0].sourceBundleID
    }

    // MARK: - HRV

    private static func hrvWindow(for values: DailyValues, day: Date, calendar: Calendar) -> DateInterval {
        if let start = values.inBedStart, let end = values.inBedEnd {
            return DateInterval(start: start.addingTimeInterval(-hrvWindowPadding), end: end.addingTimeInterval(hrvWindowPadding))
        }
        let start = calendar.date(byAdding: .hour, value: hrvFallbackStartHours, to: day) ?? day
        let end = calendar.date(byAdding: .hour, value: hrvFallbackEndHours, to: day) ?? day
        return DateInterval(start: start, end: end)
    }
}
