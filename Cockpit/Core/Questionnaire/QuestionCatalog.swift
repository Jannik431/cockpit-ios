import Foundation

nonisolated enum CheckInPhase: String, Codable, CaseIterable, Sendable {
    case morning
    /// One quick question (energy at noon), usually answered right from the notification.
    case midday
    case evening

    var title: String {
        switch self {
        case .morning: "Morgen-Check"
        case .midday: "Mittag"
        case .evening: "Abend-Check"
        }
    }

    /// From this hour on the evening check is offered on the daily card.
    static let eveningStartHour = 17
    /// From this hour on the midday question is offered on the daily card.
    static let middayStartHour = 12
}

nonisolated enum QuestionKind: Sendable, Equatable {
    /// Integer scale, higher = better. Labels describe both ends.
    case scale(range: ClosedRange<Int>, low: String, high: String)
    /// Pain 0–10 (numeric rating scale), 0 = none.
    case pain
    /// Single choice, stored as the option index.
    case choice([String])
    /// Several options, stored as a sorted list of option indices.
    case multiChoice([String])
    case yesNo
    /// Decimal number, e.g. body weight.
    case number(unit: String, range: ClosedRange<Double>)
    /// Whole number, e.g. drinks: first "none" or "some", then a stepper starting at 1.
    case count(one: String, many: String, range: ClosedRange<Int>, noneLabel: String, someLabel: String)
    /// Clock time, stored as minutes since midnight.
    case time
}

/// When a follow-up question is shown.
nonisolated enum QuestionCondition: Sendable, Equatable {
    /// The yes/no question was answered with yes.
    case yes(String)
    /// The choice question was answered with something other than the given index.
    case choiceNot(String, Int)

    var parentID: String {
        switch self {
        case .yes(let id), .choiceNot(let id, _): id
        }
    }
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
    var shownIf: QuestionCondition?
    var hint: String?
}

/// The questions of the daily check-ins.
/// Changing IDs, scales or meanings requires `version + 1`; old answers keep their version and their IDs.
///
/// History:
/// - 1: first catalog.
/// - 2: evening knee (`pain_knee_*_evening`) replaced by knee in everyday life (`knee_daily_*`),
///      symptoms after illness, energy at noon (`energy_midday`, own phase).
nonisolated enum QuestionCatalog {
    static let version = 2

    static let painRegions: [(id: String, title: String)] = [
        ("knee_left", "Knie links"),
        ("knee_right", "Knie rechts"),
        ("shoulder_left", "Schulter links"),
        ("shoulder_right", "Schulter rechts"),
        ("back", "Rücken"),
        ("elbow", "Ellenbogen"),
    ]

    static let symptoms = ["Hals", "Schnupfen", "Husten", "Fieber", "Magen-Darm", "Gliederschmerzen"]

    static let questions: [Question] = morning + midday + evening

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
                 kind: .choice(["keine", "leichte", "krank"])),
        Question(id: "symptoms", phase: .morning, section: "Befinden", title: "Symptome",
                 kind: .multiChoice(symptoms), shownIf: .choiceNot("illness", 0)),
    ] + painRegions.map { region in
        Question(id: "pain_\(region.id)_morning", phase: .morning, section: "Beschwerden morgens", title: region.title, kind: .pain)
    } + [
        Question(id: "hrv_rmssd_zepp", phase: .morning, section: "Messwerte", title: "HRV laut Zepp (RMSSD)",
                 kind: .number(unit: "ms", range: 5...250), optional: true,
                 hint: "Nicht vergleichbar mit der HRV aus Apple Health (SDNN)"),
        Question(id: "body_weight", phase: .morning, section: "Messwerte", title: "Körpergewicht",
                 kind: .number(unit: "kg", range: 30...200), optional: true),
    ]

    static let midday: [Question] = [
        Question(id: "energy_midday", phase: .midday, section: "Mittag", title: "Energie am Mittag",
                 kind: .scale(range: 1...5, low: "sehr müde", high: "hellwach")),
    ]

    static let evening: [Question] = [
        Question(id: "knee_daily_left", phase: .evening, section: "Knie im Alltag", title: "Knie links", kind: .pain,
                 hint: "Beim Gehen, Treppensteigen, Sitzen – ohne Training"),
        Question(id: "knee_daily_right", phase: .evening, section: "Knie im Alltag", title: "Knie rechts", kind: .pain),
    ] + painRegions.filter { !$0.id.hasPrefix("knee") }.map { region in
        Question(id: "pain_\(region.id)_evening", phase: .evening, section: "Beschwerden abends", title: region.title, kind: .pain)
    } + [
        Question(id: "food_amount", phase: .evening, section: "Ernährung", title: "Gegessen",
                 kind: .choice(["zu wenig", "passt", "zu viel"])),
        Question(id: "protein_ok", phase: .evening, section: "Ernährung", title: "Genug Eiweiß", kind: .yesNo),
        Question(id: "caffeine_today", phase: .evening, section: "Ernährung", title: "Koffein heute", kind: .yesNo),
        Question(id: "last_caffeine_time", phase: .evening, section: "Ernährung", title: "Letztes Koffein um",
                 kind: .time, shownIf: .yes("caffeine_today")),
        Question(id: "alcohol_drinks", phase: .evening, section: "Ernährung", title: "Alkohol",
                 kind: .count(one: "Drink", many: "Drinks", range: 0...20,
                              noneLabel: "Kein Alkohol", someLabel: "Alkohol getrunken")),
    ]

    /// IDs of earlier versions that are no longer asked. Their stored answers are kept as they are.
    static let retiredIDs: Set<String> = ["pain_knee_left_evening", "pain_knee_right_evening"]

    /// Verbal anchors of the 0–10 pain scale.
    static func painLabel(_ value: Int) -> String {
        switch value {
        case ...0: "keine"
        case 1...3: "leicht"
        case 4...6: "mittel"
        case 7...9: "stark"
        default: "stärkste vorstellbar"
        }
    }

    /// Weekdays (Calendar: 1 = Sunday) on which weighing is suggested.
    static let weighInWeekdays: Set<Int> = [2, 4, 6]

    static func questions(for phase: CheckInPhase) -> [Question] {
        questions.filter { $0.phase == phase }
    }

    static func question(_ id: String) -> Question? {
        questions.first { $0.id == id }
    }

    static func isVisible(_ question: Question, answers: [String: AnswerValue]) -> Bool {
        switch question.shownIf {
        case nil: true
        case .yes(let parent): answers[parent]?.boolValue == true
        case .choiceNot(let parent, let index): answers[parent]?.intValue.map { $0 != index } ?? false
        }
    }

    /// Answers of hidden follow-up questions are dropped, so a "no" never keeps a stale value.
    /// Answers to questions this catalog does not know (older versions) are kept unchanged.
    static func cleaned(_ answers: [String: AnswerValue], phase: CheckInPhase) -> [String: AnswerValue] {
        let hiddenIDs = Set(questions(for: phase).filter { !isVisible($0, answers: answers) }.map(\.id))
        return answers.filter { !hiddenIDs.contains($0.key) }
    }

    /// Visible, required questions without an answer.
    static func missing(_ answers: [String: AnswerValue], phase: CheckInPhase) -> [Question] {
        questions(for: phase).filter { !$0.optional && isVisible($0, answers: answers) && answers[$0.id] == nil }
    }
}
