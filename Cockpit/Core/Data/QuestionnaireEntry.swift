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

    /// Sets one answer directly (e.g. energy at noon from a notification button), creating the entry if needed.
    static func setAnswer(_ value: AnswerValue?, for questionID: String, phase: CheckInPhase, day: Date,
                          context: ModelContext, now: Date = .now) {
        let phaseRaw = phase.rawValue
        let existing = try? context.fetch(FetchDescriptor<QuestionnaireEntry>(
            predicate: #Predicate { $0.day == day && $0.phase == phaseRaw }
        )).first
        let entry = existing ?? {
            let new = QuestionnaireEntry(day: day, phase: phase, now: now)
            context.insert(new)
            return new
        }()
        var answers = entry.answers
        answers[questionID] = value
        entry.save(answers: answers, note: entry.note, now: now)
        try? context.save()
    }

    /// Numeric values of one question keyed by day, e.g. for the Zepp RMSSD norm.
    static func values(of questionID: String, from entries: [QuestionnaireEntry]) -> [Date: Double] {
        Dictionary(
            entries.compactMap { entry in entry.answers[questionID]?.doubleValue.map { (entry.day, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
