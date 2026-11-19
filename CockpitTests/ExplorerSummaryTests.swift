import Foundation
import Testing
@testable import Cockpit

/// All data here is synthetic.
struct ExplorerSummaryTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func days(_ range: ClosedRange<Int>) -> [Date] {
        range.map { date($0) }
    }

    private func hrv(_ day: Int, _ hour: Int, _ value: Double, source: String = "Tracker") -> SampleRecord {
        let start = date(day, hour)
        return SampleRecord(start: start, end: start, sourceName: source, sourceBundleID: "com.example.\(source.lowercased())", value: value)
    }

    private func sleep(_ stage: SleepStage, from start: Date, minutes: Double) -> SampleRecord {
        SampleRecord(
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            sourceName: "Tracker",
            sourceBundleID: "com.example.tracker",
            category: stage.rawValue
        )
    }

    @Test func emptyInputMarksAllDaysMissing() {
        let summary = ExplorerSummaryBuilder.summarize([], metric: .hrv, days: days(10...16), calendar: berlin)
        #expect(summary.sources.isEmpty)
        #expect(summary.totalCount == 0)
        #expect(summary.missingDays.count == 7)
    }

    @Test func groupsBySourceAndSortsByCount() {
        let records = [
            hrv(10, 3, 50), hrv(11, 3, 60), hrv(12, 3, 70),
            hrv(12, 9, 40, source: "Phone"),
        ]
        let summary = ExplorerSummaryBuilder.summarize(records, metric: .hrv, days: days(10...12), calendar: berlin)
        #expect(summary.hasMultipleSources)
        #expect(summary.sources.map(\.name) == ["Tracker", "Phone"])
        #expect(summary.sources[0].count == 3)
        #expect(summary.sources[0].daysWithData == 3)
    }

    @Test func missingDaysAreReported() {
        let records = [hrv(10, 3, 50), hrv(12, 3, 60)]
        let summary = ExplorerSummaryBuilder.summarize(records, metric: .hrv, days: days(10...13), calendar: berlin)
        #expect(summary.missingDays == [date(11), date(13)])
    }

    @Test func valueStatsUseMedianAndLatest() {
        let records = [hrv(10, 3, 40), hrv(11, 3, 80), hrv(12, 3, 50), hrv(13, 3, 60)]
        let stats = ExplorerSummaryBuilder.summarize(records, metric: .hrv, days: days(10...13), calendar: berlin)
            .sources[0].values
        #expect(stats == ValueStats(min: 40, median: 55, max: 80, latest: 60))
    }

    @Test func commonHoursAndSamplesPerDay() {
        let records = [hrv(10, 3, 50), hrv(10, 4, 50), hrv(11, 3, 50), hrv(12, 3, 50), hrv(12, 4, 50), hrv(12, 22, 50)]
        let source = ExplorerSummaryBuilder.summarize(records, metric: .hrv, days: days(10...12), calendar: berlin).sources[0]
        #expect(source.commonHours == [3, 4, 22])
        #expect(source.medianSamplesPerDay == 2)
    }

    @Test func sleepIsAssignedToWakeDayAndCountsOnlyAsleepStages() {
        // Night 16 → 17: in bed 23:00–07:00, asleep core 23:30–03:30 + deep 03:30–05:30, awake 05:30–06:00.
        let records = [
            sleep(.inBed, from: date(16, 23), minutes: 480),
            sleep(.asleepCore, from: date(16, 23, 30), minutes: 240),
            sleep(.asleepDeep, from: date(17, 3, 30), minutes: 120),
            sleep(.awake, from: date(17, 5, 30), minutes: 30),
        ]
        let summary = ExplorerSummaryBuilder.summarize(records, metric: .sleep, days: days(16...17), calendar: berlin)
        let sleepSummary = summary.sources[0].sleep

        // The night belongs to the 17th, so the 16th is missing.
        #expect(summary.missingDays == [date(16)])
        #expect(sleepSummary?.nights == 1)
        #expect(sleepSummary?.medianAsleepMinutesPerNight == 360)
        #expect(sleepSummary?.stages.map(\.stage) == [.inBed, .awake, .asleepCore, .asleepDeep])
        #expect(summary.sources[0].values == nil)
    }

    @Test func workoutLabelsAreCounted() {
        let workout: (Int, String) -> SampleRecord = { day, label in
            SampleRecord(start: self.date(day, 18), end: self.date(day, 19), sourceName: "Tracker",
                         sourceBundleID: "com.example.tracker", value: 60, label: label)
        }
        let records = [workout(10, "Krafttraining"), workout(11, "Handball"), workout(12, "Krafttraining")]
        let source = ExplorerSummaryBuilder.summarize(records, metric: .workouts, days: days(10...12), calendar: berlin).sources[0]
        #expect(source.labels == [LabelCount(label: "Krafttraining", count: 2), LabelCount(label: "Handball", count: 1)])
    }

    @Test func medianOfEvenAndOddCounts() {
        #expect(ExplorerSummaryBuilder.median([]) == nil)
        #expect(ExplorerSummaryBuilder.median([3, 1, 2]) == 2)
        #expect(ExplorerSummaryBuilder.median([4, 1, 3, 2]) == 2.5)
    }
}
