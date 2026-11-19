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
            ScrollViewReader { proxy in
                Form {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.questions) { question in
                                QuestionRow(question: question, answer: binding(for: question.id))
                                    .id(question.id)
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
                .safeAreaInset(edge: .bottom) {
                    ProgressBar(phase: phase, answers: answers) { id in
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .navigationTitle(phase.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", systemImage: "checkmark", action: save)
                        .fontWeight(.semibold)
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

/// Bottom bar: how much is answered, and a jump to the first open question.
private struct ProgressBar: View {
    let phase: CheckInPhase
    let answers: [String: AnswerValue]
    let jump: (String) -> Void

    var body: some View {
        let required = QuestionCatalog.questions(for: phase).filter { !$0.optional && QuestionCatalog.isVisible($0, answers: answers) }
        let missing = QuestionCatalog.missing(answers, phase: phase)
        let done = required.count - missing.count

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if missing.isEmpty {
                    Label("Alles beantwortet", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(done) von \(required.count) beantwortet")
                            .font(.subheadline.weight(.semibold))
                        Text("Offen: \(missing.map(\.title).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button("Zur offenen Frage") {
                        if let first = missing.first { jump(first.id) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProgressView(value: Double(done), total: Double(max(required.count, 1)))
                .tint(missing.isEmpty ? .green : .accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
