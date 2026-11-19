import Foundation
import Testing
@testable import Cockpit

struct ChartSeriesTests {
    private let days = (0..<7).map { Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 86_400) }

    @Test func gapsStartNewSegmentsAndMarkIsolatedPoints() {
        // Values on days 0, 1, 3, 5, 6 → segments [0, 1], [3], [5, 6].
        let values = Dictionary(uniqueKeysWithValues: [0, 1, 3, 5, 6].map { (days[$0], Double($0)) })
        let points = ChartSeries.points(days: days, values: values)
        #expect(points.map(\.segment) == [0, 0, 1, 2, 2])
        #expect(points.map(\.isolated) == [false, false, true, false, false])
    }

    @Test func leadingGapDoesNotCreateEmptySegment() {
        let values = [days[2]: 1.0, days[3]: 2.0]
        #expect(ChartSeries.points(days: days, values: values).map(\.segment) == [0, 0])
    }

    @Test func normRangeIsLinearOrLogarithmic() {
        let linear = Baseline(windowDays: 30, count: 30, median: 60, mad: 2)
        let range = BaselineCalculator.normRange(linear, logScale: false)
        #expect(abs(range.lowerBound - (60 - 2 * 1.4826)) < 1e-9)
        #expect(abs(range.upperBound - (60 + 2 * 1.4826)) < 1e-9)

        // On the log scale the range is symmetric as a ratio: lower × upper = median².
        let log = Baseline(windowDays: 30, count: 30, median: 40, mad: 0.2)
        let logRange = BaselineCalculator.normRange(log, logScale: true)
        #expect(abs(logRange.lowerBound * logRange.upperBound - 1600) < 1e-6)
        #expect(logRange.lowerBound < 40 && logRange.upperBound > 40)
    }
}
