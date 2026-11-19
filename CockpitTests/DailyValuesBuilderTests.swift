import Foundation
import Testing
@testable import Cockpit

/// All data here is synthetic.
struct DailyValuesBuilderTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sleep(_ stage: SleepStage, _ start: Date, minutes: Double, source: String = "com.example.tracker") -> SampleRecord {
        SampleRecord(start: start, end: start.addingTimeInterval(minutes * 60), sourceName: "Tracker",
                     sourceBundleID: source, category: stage.rawValue)
    }

    private func quantity(_ time: Date, _ value: Double, source: String = "com.example.tracker") -> SampleRecord {
        SampleRecord(start: time, end: time, sourceName: "Tracker", sourceBundleID: source, value: value)
    }

    /// Night 16 → 17 Nov: in bed 22:30–07:00, stages partly before midnight.
    private var night: [SampleRecord] {
        [
            sleep(.inBed, date(11, 16, 22, 30), minutes: 510),
            sleep(.asleepCore, date(11, 16, 22, 45), minutes: 60),   // ends before midnight
            sleep(.asleepDeep, date(11, 16, 23, 45), minutes: 90),
            sleep(.asleepREM, date(11, 17, 1, 15), minutes: 45),
            sleep(.awake, date(11, 17, 2), minutes: 15),
            sleep(.asleepCore, date(11, 17, 2, 15), minutes: 270),
        ]
    }

    private func build(sleep: [SampleRecord] = [], hrv: [SampleRecord] = [], resting: [SampleRecord] = [],
                       days: [Date]) -> [DailyValues] {
        DailyValuesBuilder.build(sleep: sleep, hrv: hrv, restingHR: resting, days: days, calendar: berlin)
    }

    @Test func nightIsAssignedToWakeDayIncludingStagesBeforeMidnight() {
        let result = build(sleep: night, days: [date(11, 16), date(11, 17)])

        #expect(result[0].asleepMin == nil)
        #expect(result[0].inBedStart == nil)

        let day = result[1]
        #expect(day.inBedStart == date(11, 16, 22, 30))
        #expect(day.inBedEnd == date(11, 17, 7))
        #expect(day.coreMin == 330)
        #expect(day.deepMin == 90)
        #expect(day.remMin == 45)
        #expect(day.awakeMin == 15)
        #expect(day.unspecifiedMin == nil)
        #expect(day.asleepMin == 465)
        #expect(day.sleepSource == "com.example.tracker")
    }

    @Test func napIsIgnored() {
        let nap = [
            sleep(.inBed, date(11, 17, 14), minutes: 40),
            sleep(.asleepCore, date(11, 17, 14, 5), minutes: 30),
        ]
        let day = build(sleep: night + nap, days: [date(11, 17)])[0]
        #expect(day.inBedStart == date(11, 16, 22, 30))
        #expect(day.coreMin == 330)
    }

    @Test func sleepWithoutInBedSamplesIsClustered() {
        let stagesOnly = night.filter { $0.category != SleepStage.inBed.rawValue }
        let day = build(sleep: stagesOnly, days: [date(11, 17)])[0]
        #expect(day.inBedStart == date(11, 16, 22, 45))
        #expect(day.inBedEnd == date(11, 17, 6, 45))
        #expect(day.asleepMin == 465)
    }

    @Test func hrvUsesOnlySamplesInsideTheNight() {
        let hrv = [
            quantity(date(11, 16, 22), 99),      // before window (22:30 - 30 min = 22:00 is the edge) → included
            quantity(date(11, 17, 3), 30),
            quantity(date(11, 17, 5), 34),
            quantity(date(11, 17, 7, 20), 38),   // within 30 min after wake
            quantity(date(11, 17, 15), 80),      // afternoon → excluded
        ]
        let day = build(sleep: night, hrv: hrv, days: [date(11, 17)])[0]
        #expect(day.hrvSamples.map(\.ms) == [99, 30, 34, 38])
        #expect(day.hrvNightMeanMs == 50.25)
        #expect(day.hrvSource == "com.example.tracker")
    }

    @Test func hrvFallbackWindowWithoutSleep() {
        let hrv = [
            quantity(date(11, 16, 17), 10),  // before 18:00 → excluded
            quantity(date(11, 16, 23), 30),
            quantity(date(11, 17, 11), 40),
            quantity(date(11, 17, 13), 50),  // after 12:00 → excluded
        ]
        let day = build(hrv: hrv, days: [date(11, 17)])[0]
        #expect(day.hrvSamples.map(\.ms) == [30, 40])
        #expect(day.hrvNightMeanMs == 35)
    }

    @Test func restingHeartRateUsesCalendarDayIncludingDSTOffsets() {
        // Date stamps at 00:00, and at 01:00 during summer time.
        let resting = [
            quantity(date(10, 24, 1), 58),
            quantity(date(10, 26, 0), 61),
        ]
        let result = build(resting: resting, days: [date(10, 24), date(10, 25), date(10, 26)])
        #expect(result.map(\.restingHR) == [58, nil, 61])
    }

    @Test func missingDayStaysNil() {
        let day = build(days: [date(11, 17)])[0]
        #expect(day == DailyValues(day: date(11, 17)))
    }

    @Test func onlyTheDominantSourceIsUsed() {
        let hrv = [
            quantity(date(11, 17, 3), 30),
            quantity(date(11, 17, 4), 32),
            quantity(date(11, 17, 5), 90, source: "com.example.phone"),
        ]
        let day = build(sleep: night, hrv: hrv, days: [date(11, 17)])[0]
        #expect(day.hrvSamples.map(\.ms) == [30, 32])
    }
}
