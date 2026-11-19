import Foundation

/// HealthKit-independent copy of one sample. Keeps analysis code testable with synthetic data.
nonisolated struct SampleRecord: Sendable, Hashable {
    var start: Date
    var end: Date
    var sourceName: String
    var sourceBundleID: String
    var deviceName: String?
    /// Quantity value in the metric's unit, or workout duration in minutes.
    var value: Double?
    /// Raw category value: a `SleepStage`, or the workout activity type.
    var category: Int?
    /// Free label, e.g. the workout activity type name.
    var label: String?
    /// HealthKit object UUID, used to de-duplicate workouts on re-import.
    var healthID: UUID? = nil

    var durationMinutes: Double { end.timeIntervalSince(start) / 60 }
}
