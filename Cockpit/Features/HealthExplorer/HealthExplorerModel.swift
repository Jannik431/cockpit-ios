import Foundation
import Observation

@Observable
final class HealthExplorerModel {
    enum State: Equatable {
        case idle
        case unavailable
        case needsAuthorization
        case loading
        case loaded
        case failed(String)
    }

    static let rangeOptions = [7, 30, 90]

    private(set) var state: State = .idle
    private(set) var summaries: [MetricSummary] = []
    private(set) var loadedAt: Date?
    var rangeDays = 30

    private let reader = HealthKitReader()

    var report: String {
        ExplorerReport.markdown(summaries, rangeDays: rangeDays, generatedAt: loadedAt ?? .now)
    }

    func start() async {
        guard HealthKitReader.isAvailable else {
            state = .unavailable
            return
        }
        do {
            if try await reader.needsAuthorizationRequest() {
                state = .needsAuthorization
            } else {
                await load()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestAccess() async {
        do {
            try await reader.requestAuthorization()
            await load()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func load() async {
        state = .loading
        let now = Date.now
        let days = LocalDay.window(endingAt: now, count: rangeDays)
        guard let first = days.first else { return }
        // Sleep ending on the first day started the evening before, so query from 18:00 the day before.
        let queryStart = Calendar.current.date(byAdding: .hour, value: -6, to: first) ?? first
        let interval = DateInterval(start: queryStart, end: now)

        do {
            var result: [MetricSummary] = []
            for metric in HealthMetric.allCases {
                let records = try await reader.samples(for: metric, in: interval)
                    .filter { metric.usesWakeDay ? $0.end >= first : $0.start >= first }
                result.append(ExplorerSummaryBuilder.summarize(records, metric: metric, days: days))
            }
            summaries = result
            loadedAt = now
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
