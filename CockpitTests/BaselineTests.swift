import Foundation
import Testing
@testable import Cockpit

/// All data here is synthetic.
struct BaselineTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    /// `count` consecutive days ending the day before `end`, with values from `value(i)` (i = 0 is the oldest).
    private func series(before end: Date, count: Int, _ value: (Int) -> Double?) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for i in 0..<count {
            let day = berlin.date(byAdding: .day, value: -(count - i), to: end)!
            if let v = value(i) { result[day] = v }
        }
        return result
    }

    private var day: Date { date(11, 20) }

    @Test func medianAndMADAreRobust() {
        // One outlier barely moves median and MAD.
        let baseline = BaselineCalculator.baseline([60, 58, 59, 61, 57, 60, 95], windowDays: 7, logScale: false)
        #expect(baseline?.median == 60)
        #expect(baseline?.mad == 1)
        #expect(baseline?.count == 7)
        #expect(baseline?.missing == 0)
    }

    @Test func tooFewValuesGiveInsufficientData() {
        var values = series(before: day, count: 30) { $0 % 3 == 0 ? 60 : nil }   // 10 values
        values[day] = 62
        let result = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin)
        #expect(result.status == .insufficientData(count: 10, required: 14))
        #expect(result.norm == nil)
        #expect(result.value == 62)
    }

    @Test func normExcludesTheDayItselfAndIgnoresOlderDays() {
        var values = series(before: day, count: 30) { 55 + Double($0 % 5) }   // 55...59, median 57
        values[day] = 120                                                       // must not affect the norm
        values[date(10, 1)] = 200                                               // outside the window
        let result = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin)
        #expect(result.norm?.median == 57)
        #expect(result.norm?.count == 30)
        guard case .available(let deviation) = result.status else {
            Issue.record("expected deviation")
            return
        }
        #expect(deviation.difference == 63)
        #expect(deviation.band == .clearlyAbove)
    }

    @Test func missingDaysAreCountedNotFilled() {
        let values = series(before: day, count: 30) { $0 < 20 ? 60 : nil }
        let result = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin)
        #expect(result.norm?.count == 20)
        #expect(result.norm?.missing == 10)
        #expect(result.status == .missingValue)
    }

    @Test func robustZUsesScaledMAD() {
        // Values 58, 59, 60, 61, 62 repeated → median 60, MAD 1, spread 1.4826.
        var values = series(before: day, count: 30) { 58 + Double($0 % 5) }
        values[day] = 63
        let result = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin)
        guard case .available(let deviation) = result.status else {
            Issue.record("expected deviation")
            return
        }
        #expect(abs(deviation.z! - 3 / 1.4826) < 1e-9)
        #expect(deviation.band == .clearlyAbove)
    }

    @Test func hrvIsComparedOnLogScale() {
        // Symmetric on the log scale: half and double the median have the same |z|.
        var values = series(before: day, count: 30) { [30, 40, 50][$0 % 3] }
        let lower = { () -> Double in
            values[self.day] = 20
            guard case .available(let d) = BaselineCalculator.assess(.hrv, on: self.day, values: values, calendar: self.berlin).status
            else { return .nan }
            return d.z!
        }()
        values[day] = 80
        guard case .available(let upper) = BaselineCalculator.assess(.hrv, on: day, values: values, calendar: berlin).status else {
            Issue.record("expected deviation")
            return
        }
        #expect(abs(lower + upper.z!) < 1e-9)
        #expect(abs((BaselineCalculator.assess(.hrv, on: day, values: values, calendar: berlin).norm?.median ?? 0) - 40) < 1e-9)
    }

    @Test func zeroSpreadCannotBeJudged() {
        var values = series(before: day, count: 20) { _ in 60 }
        values[day] = 61
        guard case .available(let deviation) = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin).status else {
            Issue.record("expected deviation")
            return
        }
        #expect(deviation.z == nil)
        #expect(deviation.band == .undetermined)

        values[day] = 60
        guard case .available(let same) = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin).status else {
            Issue.record("expected deviation")
            return
        }
        #expect(same.band == .withinNorm)
    }

    @Test func bandThresholdsAreSymmetric() {
        #expect(BaselineCalculator.band(for: 0.99) == .withinNorm)
        #expect(BaselineCalculator.band(for: -0.99) == .withinNorm)
        #expect(BaselineCalculator.band(for: 1) == .slightlyAbove)
        #expect(BaselineCalculator.band(for: -1) == .slightlyBelow)
        #expect(BaselineCalculator.band(for: 2) == .clearlyAbove)
        #expect(BaselineCalculator.band(for: -2) == .clearlyBelow)
    }

    @Test func shortTermIncludesTheDayAndNeedsFourValues() {
        var values = series(before: day, count: 30) { 58 + Double($0 % 5) }
        // Last week: 3 values before the day plus the day itself.
        for offset in 1...6 { values[berlin.date(byAdding: .day, value: -offset, to: day)!] = offset <= 3 ? 70 : nil }
        values[day] = 70

        let result = BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin)
        #expect(result.shortTerm?.count == 4)
        #expect(result.shortTerm?.median == 70)
        #expect(result.shortTermDeviation?.band == .clearlyAbove)

        values[day] = nil
        #expect(BaselineCalculator.assess(.restingHR, on: day, values: values, calendar: berlin).shortTerm == nil)
    }

    @Test func windowAcrossDSTUsesCalendarDays() {
        // 30-day norm for 5 Nov reaches back over the clock change on 25 Oct.
        let target = date(11, 5)
        let values = series(before: target, count: 30) { _ in 60 }
        let result = BaselineCalculator.assess(.restingHR, on: target, values: values, calendar: berlin)
        #expect(result.norm?.count == 30)
    }
}
