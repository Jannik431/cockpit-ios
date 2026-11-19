import Foundation

/// Formatting for stored metrics. Missing values are shown as "–", never as 0.
nonisolated enum MetricsFormat {
    static let missing = "–"

    static func minutes(_ minutes: Int?) -> String {
        minutes.map { ExplorerFormat.duration(minutes: Double($0)) } ?? missing
    }

    static func hrv(_ ms: Double?, count: Int? = nil) -> String {
        guard let ms else { return missing }
        let value = "\(ExplorerFormat.number(ms)) ms"
        guard let count else { return value }
        return "\(value) (\(count) \(count == 1 ? "Wert" : "Werte"))"
    }

    static func bpm(_ value: Double?) -> String {
        value.map { "\(ExplorerFormat.number($0, digits: 0)) bpm" } ?? missing
    }

    static func value(_ value: Double?, for metric: BaselineMetric) -> String {
        switch metric {
        case .sleep: minutes(value.map { Int($0.rounded()) })
        case .hrv: hrv(value)
        case .restingHR: bpm(value)
        }
    }

    /// Signed difference, e.g. "+15 min", "−6,1 ms".
    static func difference(_ difference: Double, for metric: BaselineMetric) -> String {
        let sign = difference < 0 ? "−" : "+"
        let magnitude = abs(difference)
        switch metric {
        case .sleep: return sign + ExplorerFormat.duration(minutes: magnitude)
        case .hrv: return "\(sign)\(ExplorerFormat.number(magnitude)) ms"
        case .restingHR: return "\(sign)\(ExplorerFormat.number(magnitude, digits: 0)) bpm"
        }
    }

    static func z(_ z: Double?) -> String {
        guard let z else { return missing }
        let sign = z < 0 ? "−" : "+"
        return "z \(sign)\(ExplorerFormat.number(abs(z), digits: 1))"
    }

    /// One-line summary for lists: "Norm 7 h 25 min · +15 min · im Normbereich".
    static func assessmentLine(_ assessment: MetricAssessment) -> String {
        switch assessment.status {
        case .insufficientData(let count, let required):
            return "Norm ab \(required) Werten (bisher \(count))"
        case .missingValue:
            return "Kein Wert · Norm \(value(assessment.norm?.median, for: assessment.metric))"
        case .available(let deviation):
            let norm = value(assessment.norm?.median, for: assessment.metric)
            return "Norm \(norm) · \(difference(deviation.difference, for: assessment.metric)) · \(deviation.band.title)"
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(ExplorerFormat.locale))
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }
}
