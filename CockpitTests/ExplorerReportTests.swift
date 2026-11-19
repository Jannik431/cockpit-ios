import Foundation
import Testing
@testable import Cockpit

struct ExplorerReportTests {
    @Test func reportListsMetricsAndMarksEmptyOnes() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let record = SampleRecord(start: start, end: start, sourceName: "Tracker",
                                  sourceBundleID: "com.example.tracker", value: 55)
        let days = LocalDay.window(endingAt: start, count: 3)
        let summaries = [
            ExplorerSummaryBuilder.summarize([record], metric: .hrv, days: days),
            ExplorerSummaryBuilder.summarize([], metric: .restingHeartRate, days: days),
        ]

        let report = ExplorerReport.markdown(summaries, rangeDays: 3, generatedAt: start)

        #expect(report.contains("## HRV (SDNN)"))
        #expect(report.contains("### Tracker (`com.example.tracker`)"))
        #expect(report.contains("Tage ohne Daten: 2 von 3"))
        #expect(report.contains("## Ruhepuls\nKeine Daten."))
    }
}
