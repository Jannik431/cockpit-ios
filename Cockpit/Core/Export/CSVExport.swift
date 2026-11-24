import Foundation

/// Everything the export needs for one day, independent of SwiftData so it can be tested.
nonisolated struct ExportDay: Sendable {
    let day: Date
    var asleepMin: Int?
    var restingHR: Double?
    var morning: [String: AnswerValue] = [:]
    var midday: [String: AnswerValue] = [:]
    var evening: [String: AnswerValue] = [:]
    var notes: [String] = []
    var sessions: [ExportSession] = []
}

nonisolated struct ExportSession: Sendable {
    let kind: SessionKind
    var rpe: Int?
    var durationMin: Int
    var isMatch: Bool?
    var throwVolume: Int?
    var kneePainLeft: Int?
    var kneePainRight: Int?
    var minutesPlayed: Int?
}

/// The daily CSV read by the training planning (spec, section 7).
/// UTF-8, comma separated, decimal point, one row per day, `YYYY-MM-DD`.
/// Empty = not captured (never 0). Units are part of the column names.
/// Columns are only ever added at the end; `schema_version` changes when meanings change.
nonisolated enum CSVExport {
    static let schemaVersion = 1
    static let fileName = "cockpit_export.csv"

    static let columns = [
        "datum",
        "knie_morgen_links", "knie_morgen_rechts",
        "knie_belastung_links", "knie_belastung_rechts",
        "knie_alltag_links", "knie_alltag_rechts",
        "schulter_links", "schulter_rechts", "ruecken", "ellenbogen",
        "schlaf_h", "hrv_rmssd_ms", "gewicht_kg", "notiz",
        "ruhepuls_bpm", "alkohol_drinks", "krank", "symptome",
        "handball_belastung", "spielminuten", "wurfvolumen",
        "kaffee", "letzter_kaffee_uhrzeit", "energie_mittag",
        "trainingslast_au", "schema_version",
    ]

    static func csv(days: [ExportDay], calendar: Calendar = .current) -> String {
        var lines = [columns.joined(separator: ",")]
        for day in days.sorted(by: { $0.day < $1.day }) {
            let values = row(for: day, calendar: calendar)
            lines.append(columns.map { escape(values[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Non-empty values of one day keyed by column.
    static func row(for day: ExportDay, calendar: Calendar = .current) -> [String: String] {
        var row: [String: String] = [:]
        row["datum"] = date(day.day, calendar: calendar)
        row["schema_version"] = "\(schemaVersion)"

        func int(_ answers: [String: AnswerValue], _ id: String) -> String? { answers[id]?.intValue.map(String.init) }

        // Pain: morning both sides, knee in everyday life (evening), knee under load (max of the day's sessions).
        row["knie_morgen_links"] = int(day.morning, "pain_knee_left_morning")
        row["knie_morgen_rechts"] = int(day.morning, "pain_knee_right_morning")
        row["knie_alltag_links"] = int(day.evening, "knee_daily_left")
        row["knie_alltag_rechts"] = int(day.evening, "knee_daily_right")
        row["knie_belastung_links"] = day.sessions.compactMap(\.kneePainLeft).max().map(String.init)
        row["knie_belastung_rechts"] = day.sessions.compactMap(\.kneePainRight).max().map(String.init)
        row["schulter_links"] = int(day.morning, "pain_shoulder_left_morning")
        row["schulter_rechts"] = int(day.morning, "pain_shoulder_right_morning")
        row["ruecken"] = int(day.morning, "pain_back_morning")
        row["ellenbogen"] = int(day.morning, "pain_elbow_morning")

        // Measurements. Sleep: the night that ends on the morning of this day.
        row["schlaf_h"] = day.asleepMin.map { number(Double($0) / 60) }
        row["hrv_rmssd_ms"] = day.morning["hrv_rmssd_zepp"]?.doubleValue.map { number($0) }
        row["gewicht_kg"] = day.morning["body_weight"]?.doubleValue.map { number($0) }
        row["ruhepuls_bpm"] = day.restingHR.map { number($0, maxDecimals: 0) }

        let notes = day.notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        row["notiz"] = notes.isEmpty ? nil : notes.joined(separator: " | ")

        // Illness: 1 already for slight signs; details in `symptome`.
        if let illness = day.morning["illness"]?.intValue {
            row["krank"] = illness > 0 ? "1" : "0"
        }
        if let indices = day.morning["symptoms"]?.listValue, !indices.isEmpty {
            row["symptome"] = indices.compactMap { QuestionCatalog.symptoms.indices.contains($0) ? QuestionCatalog.symptoms[$0] : nil }
                .joined(separator: ";")
        }

        // Evening.
        row["alkohol_drinks"] = int(day.evening, "alcohol_drinks")
        if let caffeine = day.evening["caffeine_today"]?.boolValue {
            row["kaffee"] = caffeine ? "1" : "0"
            if caffeine, let minutes = day.evening["last_caffeine_time"]?.minutes {
                row["letzter_kaffee_uhrzeit"] = String(format: "%02d:%02d", minutes / 60, minutes % 60)
            }
        }
        row["energie_mittag"] = int(day.midday, "energy_midday")

        // Handball: band from the hardest session's RPE, minutes played summed, highest throwing volume.
        let handball = day.sessions.filter { $0.kind == .handball }
        row["handball_belastung"] = handball.compactMap(\.rpe).max().map(SessionScales.handballLoadBand)
        let minutes = handball.compactMap(\.minutesPlayed)
        row["spielminuten"] = minutes.isEmpty ? nil : "\(minutes.reduce(0, +))"
        row["wurfvolumen"] = handball.compactMap(\.throwVolume).max().flatMap {
            SessionScales.throwVolumes.indices.contains($0) ? SessionScales.throwVolumes[$0] : nil
        }

        // Session load (Foster): sum of RPE × minutes over sessions with an RPE.
        let loads = day.sessions.compactMap { session in session.rpe.map { $0 * session.durationMin } }
        row["trainingslast_au"] = loads.isEmpty ? nil : "\(loads.reduce(0, +))"

        return row.compactMapValues { $0 }
    }

    /// Quotes a field if it contains a comma, quote or line break (RFC 4180).
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Decimal point, at most `maxDecimals` digits, no trailing zeros: 7.4, 41, 86.3.
    static func number(_ value: Double, maxDecimals: Int = 1) -> String {
        let factor = pow(10, Double(maxDecimals))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.\(maxDecimals)f", rounded)
    }

    static func date(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
