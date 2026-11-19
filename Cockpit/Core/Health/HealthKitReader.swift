import HealthKit

/// Read-only access to Apple Health. Cockpit never writes to HealthKit.
final class HealthKitReader {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        Set(HealthMetric.allCases.map(\.sampleType))
    }

    /// Whether the permission sheet still has to be shown.
    /// Note: iOS never reveals if read access was denied; denied types simply return no samples.
    func needsAuthorizationRequest() async throws -> Bool {
        try await store.statusForAuthorizationRequest(toShare: [], read: readTypes) == .shouldRequest
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func samples(for metric: HealthMetric, in interval: DateInterval) async throws -> [SampleRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: metric.sampleType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { Self.record(from: $0, metric: metric) }
    }

    private static func record(from sample: HKSample, metric: HealthMetric) -> SampleRecord {
        var record = SampleRecord(
            start: sample.startDate,
            end: sample.endDate,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
            deviceName: sample.device?.name ?? sample.device?.model,
            healthID: sample.uuid
        )
        switch sample {
        case let quantity as HKQuantitySample:
            if let unit = metric.unit {
                record.value = quantity.quantity.doubleValue(for: unit)
            }
        case let category as HKCategorySample:
            record.category = category.value
        case let workout as HKWorkout:
            record.value = workout.duration / 60
            record.category = Int(workout.workoutActivityType.rawValue)
            record.label = workout.workoutActivityType.displayName
        default:
            break
        }
        return record
    }
}

private extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining: "Krafttraining"
        case .functionalStrengthTraining: "Funktionelles Krafttraining"
        case .handball: "Handball"
        case .running: "Laufen"
        case .walking: "Gehen"
        case .cycling: "Radfahren"
        case .highIntensityIntervalTraining: "HIIT"
        case .coreTraining: "Core-Training"
        case .flexibility: "Beweglichkeit"
        case .mixedCardio: "Gemischtes Cardio"
        case .swimming: "Schwimmen"
        case .surfingSports: "Surfen"
        case .other: "Andere"
        default: "Typ \(rawValue)"
        }
    }
}
