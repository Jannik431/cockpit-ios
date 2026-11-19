import Testing
@testable import Cockpit

struct ImpactTests {
    private func impact(_ band: DeviationBand, _ metric: BaselineMetric) -> Impact {
        Impact(Deviation(value: 0, difference: 0, z: 0, band: band), metric: metric)
    }

    @Test func withinNormIsGoodForAllMetrics() {
        for metric in BaselineMetric.allCases {
            #expect(impact(.withinNorm, metric) == .good)
            #expect(impact(.undetermined, metric) == .unknown)
        }
    }

    @Test func lessSleepAndLowerHRVAreUnfavorable() {
        for metric in [BaselineMetric.sleep, .hrv] {
            #expect(impact(.slightlyBelow, metric) == .caution)
            #expect(impact(.clearlyBelow, metric) == .warning)
            #expect(impact(.slightlyAbove, metric) == .good)
            #expect(impact(.clearlyAbove, metric) == .good)
        }
    }

    @Test func higherRestingHeartRateIsUnfavorable() {
        #expect(impact(.slightlyAbove, .restingHR) == .caution)
        #expect(impact(.clearlyAbove, .restingHR) == .warning)
        #expect(impact(.slightlyBelow, .restingHR) == .good)
        #expect(impact(.clearlyBelow, .restingHR) == .good)
    }
}
