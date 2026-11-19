import Foundation

nonisolated enum CheckInPhase: String, Codable, CaseIterable, Sendable {
    case morning
    case evening

    var title: String {
        switch self {
        case .morning: "Morgen-Check"
        case .evening: "Abend-Check"
        }
    }

    /// From this hour on the evening check is offered on the daily card.
    static let eveningStartHour = 17
}

nonisolated enum QuestionKind: Sendable, Equatable {
    /// Integer scale, higher = better. Labels describe both ends.
    case scale(range: ClosedRange<Int>, low: String, high: String)
    /// Pain 0–10 (numeric rating scale), 0 = none.
    case pain
    /// Single choice, stored as the option index.
    case choice([String])
    case yesNo
    /// Decimal number, e.g. body weight.
    case number(unit: String, range: ClosedRange<Double>)
    /// Whole number with stepper, e.g. drinks.
    case count(unit: String, range: ClosedRange<Int>)
    /// Clock time, stored as minutes since midnight.
    case time
}

nonisolated struct Question: Sendable, Identifiable, Equatable {
    /// Stable ID. Never change or reuse it; changes need a new catalog version (spec, section 5).
    let id: String
    let phase: CheckInPhase
    let section: String
    let title: String
    let kind: QuestionKind
    /// Optional questions do not count for "complete".
    var optional = false
    /// Only shown if the given yes/no question was answered with yes.
    var shownIfYes: String?
    var hint: String?
}

/// The questions of the daily check-ins. Version 1.
/// Changing IDs, scales or meanings requires `version + 1`; old answers keep their version.
nonisolated enum QuestionCatalog {
    static let version = 1

    static let painRegions: [(id: String, title: String)] = [
        ("knee", "Knie"),
        ("shoulder", "Schulter"),
        ("back", "Rücken"),
        ("elbow", "Ellenbogen"),
    ]

    static let questions: [Question] = morning + evening

    static let morning: [Question] = [
        Question(id: "sleep_quality", phase: .morning, section: "Befinden", title: "Schlafqualität",
                 kind: .scale(range: 1...7, low: "sehr schlecht", high: "sehr gut")),
        Question(id: "energy", phase: .morning, section: "Befinden", title: "Energie",
                 kind: .scale(range: 1...7, low: "erschöpft", high: "voller Energie")),
        Question(id: "muscle_soreness", phase: .morning, section: "Befinden", title: "Muskelkater",
                 kind: .scale(range: 1...7, low: "stark", high: "keiner")),
        Question(id: "stress", phase: .morning, section: "Befinden", title: "Stress",
                 kind: .scale(range: 1...7, low: "sehr gestresst", high: "entspannt")),
        Question(id: "training_motivation", phase: .morning, section: "Befinden", title: "Lust auf Training",
                 kind: .scale(range: 1...7, low: "keine", high: "sehr groß")),
        Question(id: "illness", phase: .morning, section: "Befinden", title: "Krankheitszeichen",
                 kind: .choice(["keine", "leichte", "krank"]),
                 hint: "Halsschmerzen, Schnupfen, Fieber, Magen-Darm"),
    ] + painRegions.map { region in
        Question(id: "pain_\(region.id)_morning", phase: .morning, section: "Beschwerden morgens", title: region.title, kind: .pain)
    } + [
        Question(id: "hrv_rmssd_zepp", phase: .morning, section: "Messwerte", title: "HRV laut Zepp (RMSSD)",
                 kind: .number(unit: "ms", range: 5...250), optional: true,
                 hint: "Nicht vergleichbar mit der HRV aus Apple Health (SDNN)"),
        Question(id: "body_weight", phase: .morning, section: "Messwerte", title: "Körpergewicht",
                 kind: .number(unit: "kg", range: 30...200), optional: true),
    ]

    static let evening: [Question] = [
        Question(id: "pain_knee_evening", phase: .evening, section: "Beschwerden abends", title: "Knie", kind: .pain),
        Question(id: "food_amount", phase: .evening, section: "Ernährung", title: "Gegessen",
                 kind: .choice(["zu wenig", "passt", "zu viel"])),
        Question(id: "protein_ok", phase: .evening, section: "Ernährung", title: "Genug Eiweiß", kind: .yesNo),
        Question(id: "caffeine_today", phase: .evening, section: "Ernährung", title: "Koffein heute", kind: .yesNo),
        Question(id: "last_caffeine_time", phase: .evening, section: "Ernährung", title: "Letztes Koffein um",
                 kind: .time, shownIfYes: "caffeine_today"),
        Question(id: "alcohol_drinks", phase: .evening, section: "Ernährung", title: "Alkohol",
                 kind: .count(unit: "Drinks", range: 0...20)),
    ]

    /// Weekdays (Calendar: 1 = Sunday) on which weighing is suggested.
    static let weighInWeekdays: Set<Int> = [2, 4, 6]

    static func questions(for phase: CheckInPhase) -> [Question] {
        questions.filter { $0.phase == phase }
    }

    static func question(_ id: String) -> Question? {
        questions.first { $0.id == id }
    }

    static func isVisible(_ question: Question, answers: [String: AnswerValue]) -> Bool {
        guard let parent = question.shownIfYes else { return true }
        return answers[parent]?.boolValue == true
    }

    /// Answers of hidden questions are dropped, so a "no" never keeps a stale follow-up value.
    static func cleaned(_ answers: [String: AnswerValue], phase: CheckInPhase) -> [String: AnswerValue] {
        let visibleIDs = Set(questions(for: phase).filter { isVisible($0, answers: answers) }.map(\.id))
        return answers.filter { visibleIDs.contains($0.key) }
    }

    /// Visible, required questions without an answer.
    static func missing(_ answers: [String: AnswerValue], phase: CheckInPhase) -> [Question] {
        questions(for: phase).filter { !$0.optional && isVisible($0, answers: answers) && answers[$0.id] == nil }
    }
}
