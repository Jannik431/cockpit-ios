import Foundation
import Observation

/// Small on-device log of notification handling (last 60 lines), shown under "Daten".
/// Exists because notification taps cannot be debugged without a cable and Console.
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private(set) var lines: [String]

    @ObservationIgnored private let key = "diagnosticsLog"
    @ObservationIgnored private let limit = 60

    init() {
        lines = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ message: String, now: Date = .now) {
        let stamp = now.formatted(.dateTime.day().month(.twoDigits).hour().minute().second().locale(ExplorerFormat.locale))
        lines.append("\(stamp)  \(message)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        UserDefaults.standard.set(lines, forKey: key)
        notificationLog.info("\(message, privacy: .public)")
    }

    func clear() {
        lines = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
