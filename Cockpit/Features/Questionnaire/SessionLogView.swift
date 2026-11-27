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
    @State private var planUnit: String?
    @State private var start = Date.now
    @State private var durationMin = 60
    @State private var rpe: Int?
    @State private var matchIndex: Int?
    @State private var throwVolume: Int?
    @State private var kneeLeft: Int?
    @State private var kneeRight: Int?
    @State private var minutesPlayed: Int?
    @State private var note = ""
    @State private var loaded = false
    @State private var confirmHide = false

    private var fromHealth: Bool { draft.suggested != nil || draft.existing?.workoutIDs.isEmpty == false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChoiceGrid(options: SessionScales.planUnits, selection: Binding(
                        get: { planUnit.flatMap { SessionScales.planUnits.firstIndex(of: $0) } },
                        set: { index in selectPlanUnit(index.map { SessionScales.planUnits[$0] }) }
                    ))
                    if fromHealth {
                        LabeledContent("Zeit", value: MetricsFormat.timeRange(start, start.addingTimeInterval(Double(durationMin) * 60)))
                    } else {
                        DatePicker("Beginn", selection: $start, displayedComponents: .hourAndMinute)
                    }
                    Stepper("Dauer: \(durationMin) min", value: $durationMin, in: 5...300, step: 5)
                } header: {
                    Text("Einheit laut Plan")
                } footer: {
                    if planUnit == nil {
                        Text("Bitte die Einheit aus dem Plan wählen. Erkannt: \(kind.title).")
                    }
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

                Section {
                    kneeRow("Knie links", value: $kneeLeft)
                    kneeRow("Knie rechts", value: $kneeRight)
                } header: {
                    HStack {
                        Text("Knie während der Einheit")
                        Spacer()
                        Button("Keine Beschwerden") {
                            kneeLeft = 0
                            kneeRight = 0
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }

                if kind == .handball {
                    Section("Handball") {
                        if matchIndex == 1 {
                            Stepper(value: Binding(get: { minutesPlayed ?? 0 }, set: { minutesPlayed = $0 }), in: 0...120, step: 5) {
                                LabeledContent("Spielminuten", value: minutesPlayed.map { "\($0) min" } ?? "nicht angegeben")
                            }
                        }
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

                if draft.existing != nil || draft.suggested != nil {
                    Section {
                        if let existing = draft.existing {
                            Button(fromHealth ? "RPE-Eintrag löschen" : "Einheit löschen", role: .destructive) {
                                context.delete(existing)
                                try? context.save()
                                dismiss()
                            }
                        }
                        if draft.suggested != nil {
                            Button("Workout ausblenden (falsch erkannt)", role: .destructive) { confirmHide = true }
                        }
                    } footer: {
                        Text(fromHealth ? "Das Workout in Apple Health bleibt erhalten. Ausgeblendete Workouts lassen sich unter „Gespeicherte Tage“ wieder einblenden." : "")
                    }
                }
            }
            .confirmationDialog("Workout ausblenden?", isPresented: $confirmHide, titleVisibility: .visible) {
                Button("Ausblenden", role: .destructive, action: hideWorkout)
            } message: {
                Text("Es zählt dann nirgends mehr mit. Ein RPE-Eintrag dazu wird gelöscht.")
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
            planUnit = existing.effectivePlanUnit
            start = existing.start
            durationMin = existing.durationMin
            rpe = existing.sessionRPE
            matchIndex = existing.isMatch.map { $0 ? 1 : 0 }
            throwVolume = existing.throwVolume
            kneeLeft = existing.kneePainLeft
            kneeRight = existing.kneePainRight
            minutesPlayed = existing.minutesPlayed
            note = existing.note ?? ""
        } else if let suggested = draft.suggested {
            kind = suggested.kind
            // Handball is detected reliably; gym units (A–D, Plyo2) have to be picked.
            if suggested.kind == .handball { selectPlanUnit("Handball") }
            start = suggested.start
            durationMin = max(5, Int(suggested.activeMinutes.rounded()))
        } else if Calendar.current.isDate(draft.day, inSameDayAs: .now) {
            let now = Date.now
            let rounded = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
            start = rounded.addingTimeInterval(-3600)
        } else {
            // A past day: default to the evening of that day.
            start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: draft.day) ?? draft.day
        }
    }

    /// The plan unit decides the kind and, for handball, match or practice.
    private func selectPlanUnit(_ unit: String?) {
        planUnit = unit
        guard let unit else { return }
        kind = SessionScales.kind(forPlanUnit: unit)
        switch unit {
        case "Spiel": matchIndex = 1
        case "Handball": matchIndex = 0
        default: matchIndex = nil
        }
    }

    private func kneeRow(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                Text(value.wrappedValue.map { "\($0) · \(QuestionCatalog.painLabel($0))" } ?? "nicht angegeben")
                    .font(.body.weight(value.wrappedValue == nil ? .regular : .semibold))
                    .foregroundStyle(value.wrappedValue == nil ? Color.secondary : Color.accentColor)
            }
            ScaleSlider(range: 0...10, value: value, low: "keine", high: "stärkste vorstellbar")
        }
        .padding(.vertical, 4)
    }

    private func hideWorkout() {
        guard let suggested = draft.suggested else { return }
        let ids = suggested.workoutIDs
        let workouts = (try? context.fetch(FetchDescriptor<HealthWorkout>(predicate: #Predicate { ids.contains($0.healthID) }))) ?? []
        for workout in workouts { workout.isHidden = true }
        if let existing = draft.existing { context.delete(existing) }
        try? context.save()
        dismiss()
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
        session.planUnit = planUnit
        session.start = start
        session.end = draft.suggested?.end ?? end
        session.durationMin = durationMin
        session.sessionRPE = rpe
        session.isMatch = kind == .handball ? matchIndex.map { $0 == 1 } : nil
        session.throwVolume = kind == .handball ? throwVolume : nil
        session.minutesPlayed = kind == .handball && matchIndex == 1 ? minutesPlayed : nil
        session.kneePainLeft = kneeLeft
        session.kneePainRight = kneeRight
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.note = trimmed.isEmpty ? nil : trimmed
        session.scalesVersion = SessionScales.version
        session.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
