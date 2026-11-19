import SwiftData
import SwiftUI

/// What the session sheet edits: a workout from Apple Health, an existing log, or a session without the watch.
struct SessionDraft: Identifiable {
    let id = UUID()
    let day: Date
    var suggested: SuggestedSession?
    var existing: CompletedSession?
}

struct SessionLogView: View {
    let draft: SessionDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SessionKind = .gym
    @State private var start = Date.now
    @State private var durationMin = 60
    @State private var rpe: Int?
    @State private var matchIndex: Int?
    @State private var throwVolume: Int?
    @State private var note = ""
    @State private var loaded = false

    private var fromHealth: Bool { draft.suggested != nil || draft.existing?.workoutIDs.isEmpty == false }

    var body: some View {
        NavigationStack {
            Form {
                Section("Einheit") {
                    OptionButtons(options: SessionKind.allCases.map(\.title), selection: Binding(
                        get: { SessionKind.allCases.firstIndex(of: kind) },
                        set: { kind = $0.map { SessionKind.allCases[$0] } ?? kind }
                    ))
                    if fromHealth {
                        LabeledContent("Zeit", value: MetricsFormat.timeRange(start, start.addingTimeInterval(Double(durationMin) * 60)))
                    } else {
                        DatePicker("Beginn", selection: $start, displayedComponents: .hourAndMinute)
                    }
                    Stepper("Dauer: \(durationMin) min", value: $durationMin, in: 5...300, step: 5)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Session-RPE")
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(rpe.map { "\($0) · \(SessionScales.rpeLabel($0))" } ?? "nicht angegeben")
                                .font(.body.weight(rpe == nil ? .regular : .semibold))
                                .foregroundStyle(rpe == nil ? Color.secondary : Color.accentColor)
                        }
                        ScaleSlider(range: 0...10, value: $rpe, low: "Ruhe", high: "maximal")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Wie anstrengend war die Einheit insgesamt?")
                        .textCase(nil)
                } footer: {
                    Text("Session-RPE (Borg CR10). Am aussagekräftigsten etwa 30 Minuten nach dem Training. Belastung = RPE × Dauer\(rpe.map { ": \($0 * durationMin)" } ?? "").")
                }

                if kind == .handball {
                    Section("Handball") {
                        OptionButtons(options: ["Training", "Spiel"], selection: $matchIndex)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Wurfvolumen")
                                .font(.body.weight(.medium))
                            OptionButtons(options: SessionScales.throwVolumes, selection: $throwVolume)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Notiz") {
                    TextField("optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let existing = draft.existing {
                    Section {
                        Button("Eintrag löschen", role: .destructive) {
                            context.delete(existing)
                            try? context.save()
                            dismiss()
                        }
                    } footer: {
                        Text(fromHealth ? "Das Workout in Apple Health bleibt erhalten." : "")
                    }
                }
            }
            .navigationTitle(draft.existing == nil ? "Einheit erfassen" : "Einheit bearbeiten")
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

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing = draft.existing {
            kind = existing.sessionKind
            start = existing.start
            durationMin = existing.durationMin
            rpe = existing.sessionRPE
            matchIndex = existing.isMatch.map { $0 ? 1 : 0 }
            throwVolume = existing.throwVolume
            note = existing.note ?? ""
        } else if let suggested = draft.suggested {
            kind = suggested.kind
            start = suggested.start
            durationMin = max(5, Int(suggested.activeMinutes.rounded()))
        } else {
            let now = Date.now
            let rounded = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
            start = rounded.addingTimeInterval(-3600)
        }
    }

    private func save() {
        let end = start.addingTimeInterval(Double(durationMin) * 60)
        let session = draft.existing ?? {
            let new = CompletedSession(
                day: draft.day,
                start: start,
                end: end,
                kind: kind,
                durationMin: durationMin,
                workoutIDs: draft.suggested?.workoutIDs ?? []
            )
            context.insert(new)
            return new
        }()
        session.kind = kind.rawValue
        session.start = start
        session.end = draft.suggested?.end ?? end
        session.durationMin = durationMin
        session.sessionRPE = rpe
        session.isMatch = kind == .handball ? matchIndex.map { $0 == 1 } : nil
        session.throwVolume = kind == .handball ? throwVolume : nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.note = trimmed.isEmpty ? nil : trimmed
        session.scalesVersion = SessionScales.version
        session.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
