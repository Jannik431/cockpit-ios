import SwiftData
import SwiftUI

/// Morning or evening check-in for one day. Can be saved incomplete; unanswered questions stay empty.
struct CheckInView: View {
    let phase: CheckInPhase
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [QuestionnaireEntry]
    @State private var answers: [String: AnswerValue] = [:]
    @State private var note = ""
    @State private var loaded = false

    init(phase: CheckInPhase, day: Date) {
        self.phase = phase
        self.day = day
        let phaseRaw = phase.rawValue
        _entries = Query(filter: #Predicate<QuestionnaireEntry> { $0.day == day && $0.phase == phaseRaw })
    }

    private var sections: [(title: String, questions: [Question])] {
        var result: [(String, [Question])] = []
        for question in QuestionCatalog.questions(for: phase) where QuestionCatalog.isVisible(question, answers: answers) {
            if let index = result.firstIndex(where: { $0.0 == question.section }) {
                result[index].1.append(question)
            } else {
                result.append((question.section, [question]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.questions) { question in
                            QuestionRow(question: question, answer: binding(for: question.id))
                        }
                    } header: {
                        sectionHeader(section.title, questions: section.questions)
                    } footer: {
                        sectionFooter(section.title)
                    }
                }

                Section("Notiz") {
                    TextField("Besonderheiten, optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(phase.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .status) {
                    let missing = QuestionCatalog.missing(answers, phase: phase).count
                    Text(missing == 0 ? "Alles beantwortet" : "Noch \(missing) offen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, questions: [Question]) -> some View {
        let painQuestions = questions.filter { $0.kind == .pain }
        if painQuestions.isEmpty {
            Text(title)
        } else {
            HStack {
                Text(title)
                Spacer()
                Button("Keine Beschwerden") {
                    for question in painQuestions { answers[question.id] = .int(0) }
                }
                .font(.caption.weight(.semibold))
                .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func sectionFooter(_ title: String) -> some View {
        if title == "Messwerte", QuestionCatalog.weighInWeekdays.contains(Calendar.current.component(.weekday, from: day)) {
            Text("Heute ist ein Wiegetag: morgens nach dem Aufstehen, vor dem Frühstück.")
        }
    }

    private func binding(for id: String) -> Binding<AnswerValue?> {
        Binding(get: { answers[id] }, set: { answers[id] = $0 })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let entry = entries.first {
            answers = entry.answers
            note = entry.note ?? ""
        }
    }

    private func save() {
        let entry = entries.first ?? {
            let new = QuestionnaireEntry(day: day, phase: phase)
            context.insert(new)
            return new
        }()
        entry.save(answers: answers, note: note)
        try? context.save()
        dismiss()
    }
}
