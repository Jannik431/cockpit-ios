import Foundation
import SwiftData

/// Answers of one check-in (morning or evening) on one local day. Not re-importable: handle with care.
@Model
final class QuestionnaireEntry {
    var day: Date
    /// `CheckInPhase` raw value.
    var phase: String
    /// `QuestionCatalog.version` the answers were given in.
    var catalogVersion: Int
    /// `[questionID: AnswerValue]`. Unanswered questions are absent (null in exports).
    var answersJSON: Data
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(day: Date, phase: CheckInPhase, now: Date = .now) {
        self.day = day
        self.phase = phase.rawValue
        self.catalogVersion = QuestionCatalog.version
        self.answersJSON = Data("{}".utf8)
        self.createdAt = now
        self.updatedAt = now
    }

    var checkInPhase: CheckInPhase? { CheckInPhase(rawValue: phase) }

    var answers: [String: AnswerValue] {
        (try? JSONDecoder().decode([String: AnswerValue].self, from: answersJSON)) ?? [:]
    }

    func save(answers: [String: AnswerValue], note: String?, now: Date = .now) {
        let phase = checkInPhase ?? .morning
        answersJSON = (try? JSONEncoder().encode(QuestionCatalog.cleaned(answers, phase: phase))) ?? Data("{}".utf8)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmed?.isEmpty == false ? trimmed : nil
        catalogVersion = QuestionCatalog.version
        updatedAt = now
    }

    var isComplete: Bool {
        guard let phase = checkInPhase else { return false }
        return QuestionCatalog.missing(answers, phase: phase).isEmpty
    }

    /// Numeric values of one question keyed by day, e.g. for the Zepp RMSSD norm.
    static func values(of questionID: String, from entries: [QuestionnaireEntry]) -> [Date: Double] {
        Dictionary(
            entries.compactMap { entry in entry.answers[questionID]?.doubleValue.map { (entry.day, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
