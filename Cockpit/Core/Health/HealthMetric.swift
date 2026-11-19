import HealthKit

/// The Apple Health data types Cockpit reads (spec, section 3).
nonisolated enum HealthMetric: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case hrv
    case restingHeartRate
    case heartRate
    case workouts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Schlaf"
        case .hrv: "HRV (SDNN)"
        case .restingHeartRate: "Ruhepuls"
        case .heartRate: "Herzfrequenz"
        case .workouts: "Workouts"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .hrv: "waveform.path.ecg"
        case .restingHeartRate: "heart.fill"
        case .heartRate: "heart.text.square"
        case .workouts: "figure.strengthtraining.traditional"
        }
    }

    var sampleType: HKSampleType {
        switch self {
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .heartRate: HKQuantityType(.heartRate)
        case .workouts: HKWorkoutType.workoutType()
        }
    }

    /// Unit in which quantity values are read. Workouts are stored as duration in minutes.
    var unit: HKUnit? {
        switch self {
        case .hrv: .secondUnit(with: .milli)
        case .restingHeartRate, .heartRate: .count().unitDivided(by: .minute())
        case .sleep, .workouts: nil
        }
    }

    var unitLabel: String {
        switch self {
        case .hrv: "ms"
        case .restingHeartRate, .heartRate: "bpm"
        case .sleep, .workouts: "min"
        }
    }

    /// Sleep is assigned to the wake day (sample end), everything else to the day it started.
    var usesWakeDay: Bool { self == .sleep }
}

/// Sleep analysis values as delivered by HealthKit. Raw values match `HKCategoryValueSleepAnalysis`.
nonisolated enum SleepStage: Int, CaseIterable, Sendable {
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepREM = 5

    var title: String {
        switch self {
        case .inBed: "Im Bett"
        case .asleepUnspecified: "Schlaf (ohne Phase)"
        case .awake: "Wach"
        case .asleepCore: "Kernschlaf"
        case .asleepDeep: "Tiefschlaf"
        case .asleepREM: "REM"
        }
    }

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake: false
        }
    }
}
