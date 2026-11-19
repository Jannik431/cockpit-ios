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

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(ExplorerFormat.locale))
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }
}
