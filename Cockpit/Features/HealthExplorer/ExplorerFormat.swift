import Foundation

/// Shared German formatting for the Health Explorer views and report.
nonisolated enum ExplorerFormat {
    static let locale = Locale(identifier: "de_DE")

    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let rest = total % 60
        return hours > 0 ? "\(hours) h \(rest) min" : "\(rest) min"
    }

    static func value(_ value: Double, metric: HealthMetric) -> String {
        "\(number(value, digits: metric == .hrv ? 1 : 0)) \(metric.unitLabel)"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).locale(locale))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(locale))
    }

    static func hours(_ hours: [Int]) -> String {
        hours.isEmpty ? "–" : hours.map { String(format: "%02d Uhr", $0) }.joined(separator: ", ")
    }

    static func sample(_ record: SampleRecord, metric: HealthMetric) -> String {
        switch metric {
        case .sleep:
            let stage = record.category.flatMap(SleepStage.init(rawValue:))?.title ?? "Wert \(record.category ?? -1)"
            return "\(stage), \(duration(minutes: record.durationMinutes))"
        case .workouts:
            return "\(record.label ?? "Workout"), \(duration(minutes: record.value ?? record.durationMinutes))"
        case .hrv, .restingHeartRate, .heartRate:
            return record.value.map { value($0, metric: metric) } ?? "–"
        }
    }
}
