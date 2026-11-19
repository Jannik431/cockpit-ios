import Foundation

/// Scales for logging a training session. Version 1, same rules as `QuestionCatalog`.
nonisolated enum SessionScales {
    static let version = 1

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
}
