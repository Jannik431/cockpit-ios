import Foundation

/// Scales for logging a training session. Same versioning rules as `QuestionCatalog`.
///
/// History:
/// - 1: kind, duration, session RPE, handball match/practice, throwing volume.
/// - 2: knee pain during the session (left/right, 0–10), minutes played in a match.
nonisolated enum SessionScales {
    static let version = 2

    /// Borg CR10 labels for session RPE (Foster): "How hard was the whole session?"
    static let rpeLabels: [Int: String] = [
        0: "Ruhe",
        1: "sehr, sehr leicht",
        2: "leicht",
        3: "moderat",
        4: "etwas schwer",
        5: "schwer",
        7: "sehr schwer",
        10: "maximal",
    ]

    static func rpeLabel(_ value: Int) -> String {
        rpeLabels[value] ?? (value == 6 ? "schwer bis sehr schwer" : "sehr schwer bis maximal")
    }

    /// Recommended: ask about 30 minutes after the session.
    static let rpeDelay: TimeInterval = 30 * 60

    /// Handball throwing volume, stored as index.
    static let throwVolumes = ["kaum", "wenig", "mittel", "viel"]

    /// Handball load band derived from session RPE (for the export): up to 4 light, 5–6 medium, from 7 hard.
    static func handballLoadBand(rpe: Int) -> String {
        switch rpe {
        case ...4: "leicht"
        case 5...6: "mittel"
        default: "hart"
        }
    }
}
