import Foundation
import Testing
@testable import Cockpit

/// All data here is synthetic.
struct LoadMetricsTests {
    private let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// Tuesday, 24 Nov 2026.
    private var today: Date { berlin.date(from: DateComponents(year: 2026, month: 11, day: 24))! }

    private func day(_ offset: Int) -> Date { berlin.date(byAdding: .day, value: offset, to: today)! }

    @Test func acuteSumsSevenDaysAndCountsUnrated() {
        let entries = [
            LoadEntry(day: day(0), kind: .gym, load: 300),
            LoadEntry(day: day(-6), kind: .handball, load: 500),
            LoadEntry(day: day(-7), kind: .handball, load: 999),   // outside
            LoadEntry(day: day(-2), kind: .handball, load: nil),
        ]
        let summary = LoadMetrics.summary(entries, today: today, firstDay: day(-10), calendar: berlin)
        #expect(summary.acute == 800)
        #expect(summary.unrated == 1)
        #expect(summary.chronicWeekly == nil)
        #expect(summary.ratio == nil)
    }

    @Test func chronicAndRatioWithFullHistory() {
        // 400 AU every day for 28 days → chronic 2800/week, acute 2800, ratio 1, no variation → no monotony.
        let entries = (0..<28).map { LoadEntry(day: day(-$0), kind: .gym, load: 400) }
        let summary = LoadMetrics.summary(entries, today: today, firstDay: day(-40), calendar: berlin)
        #expect(summary.chronicWeekly == 2800)
        #expect(summary.ratio == 1)
        #expect(summary.monotony == nil)
    }

    @Test func monotonyAndStrain() {
        // Loads over the week: 600 on two days, 0 on five days.
        let entries = [LoadEntry(day: day(0), kind: .handball, load: 600), LoadEntry(day: day(-3), kind: .gym, load: 600)]
        let summary = LoadMetrics.summary(entries, today: today, firstDay: day(-3), calendar: berlin)
        let mean = 1200.0 / 7
        let sd = ((2 * pow(600 - mean, 2) + 5 * pow(mean, 2)) / 7).squareRoot()
        #expect(abs(summary.monotony! - mean / sd) < 1e-9)
        #expect(abs(summary.strain! - 1200 * mean / sd) < 1e-6)
    }

    @Test func weeksStartOnMondayAndSplitByKind() {
        let entries = [
            LoadEntry(day: day(-1), kind: .gym, load: 300),            // Monday 23 Nov
            LoadEntry(day: day(0), kind: .handball, load: 500, throwVolume: 2),
            LoadEntry(day: day(-2), kind: .handball, load: 400),        // Sunday 22 Nov → previous week
            LoadEntry(day: day(0), kind: .handball, load: nil),
        ]
        let weeks = LoadMetrics.weeks(entries, endingAt: today, count: 2, calendar: berlin)
        #expect(weeks.map(\.weekStart) == [day(-8), day(-1)])
        #expect(weeks[1].byKind == [.gym: 300, .handball: 500])
        #expect(weeks[1].unrated == 1)
        #expect(weeks[1].throwVolumes == [2: 1])
        #expect(weeks[0].total == 400)
    }
}

struct WeightTrendTests {
    private func point(_ day: Int, _ kg: Double) -> WeightPoint {
        WeightPoint(day: Date(timeIntervalSince1970: Double(day) * 86_400), kg: kg)
    }

    @Test func trendIsMeanOfLastThreeWeighIns() {
        let trend = WeightTrend.trend([point(0, 86), point(2, 87), point(4, 85), point(7, 84)])
        #expect(trend.map(\.kg) == [86, 86.5, 86, 85.333333333333333])
    }

    @Test func weeklyChangeNeedsTwoWeeks() {
        #expect(WeightTrend.weeklyChange([point(0, 86), point(7, 85)]) == nil)
        let points = [point(0, 86), point(2, 86), point(4, 86), point(14, 85), point(16, 85), point(18, 85)]
        let change = WeightTrend.weeklyChange(points)!
        #expect(abs(change - (-1.0 / 14 * 7)) < 1e-9)
    }
}
