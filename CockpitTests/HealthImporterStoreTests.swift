import Foundation
import SwiftData
import Testing
@testable import Cockpit

/// Upsert behaviour against an in-memory store. All data is synthetic.
@MainActor
struct HealthImporterStoreTests {
    private let container: ModelContainer
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))

    init() throws {
        container = try ModelContainer(
            for: DailyMetrics.self, HealthWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func values(hrv: [Double], resting: Double?) -> DailyValues {
        var values = DailyValues(day: day)
        values.hrvSamples = hrv.enumerated().map { HRVSample(time: day.addingTimeInterval(Double($0.offset) * 3600), ms: $0.element) }
        values.hrvNightMeanMs = hrv.isEmpty ? nil : hrv.reduce(0, +) / Double(hrv.count)
        values.restingHR = resting
        return values
    }

    private func workout(_ id: UUID) -> SampleRecord {
        SampleRecord(start: day.addingTimeInterval(18 * 3600), end: day.addingTimeInterval(19 * 3600),
                     sourceName: "Tracker", sourceBundleID: "com.example.tracker",
                     value: 60, category: 3000, label: "Andere", healthID: id)
    }

    @Test func reimportUpdatesDayAndDoesNotDuplicate() throws {
        let context = container.mainContext
        let id = UUID()

        let first = try HealthImporter.store(values: [values(hrv: [], resting: nil)], workouts: [workout(id)],
                                             in: context, fetchedAt: .now)
        let second = try HealthImporter.store(values: [values(hrv: [30, 40], resting: 58)], workouts: [workout(id)],
                                              in: context, fetchedAt: .now)

        #expect(first.newWorkouts == 1)
        #expect(second.newWorkouts == 0)

        let stored = try context.fetch(FetchDescriptor<DailyMetrics>())
        #expect(stored.count == 1)
        #expect(stored[0].restingHR == 58)
        #expect(stored[0].hrvNightMeanMs == 35)
        #expect(stored[0].hrvMetric == HRVMetric.id)
        #expect(stored[0].hrvSamples.map(\.ms) == [30, 40])
        #expect(try context.fetch(FetchDescriptor<HealthWorkout>()).count == 1)
    }

    @Test func missingValuesStayNil() throws {
        let context = container.mainContext
        _ = try HealthImporter.store(values: [values(hrv: [], resting: nil)], workouts: [], in: context, fetchedAt: .now)
        let stored = try #require(try context.fetch(FetchDescriptor<DailyMetrics>()).first)
        #expect(stored.hrvMetric == nil)
        #expect(stored.hrvSamplesJSON == nil)
        #expect(stored.asleepMin == nil)
        #expect(stored.restingHR == nil)
    }
}
