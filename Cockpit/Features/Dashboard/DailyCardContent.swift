import SwiftUI

/// The daily card, independent of SwiftData queries and HealthKit so it can be previewed and rendered with synthetic data.
struct DailyCardContent: View {
    let now: Date
    let days: [DailyMetrics]
    let workouts: [HealthWorkout]
    var entries: [QuestionnaireEntry] = []
    var sessions: [CompletedSession] = []
    let syncState: HealthSync.State
    let lastSync: Date?
    var requestAccess: () -> Void = {}
    var retry: () -> Void = {}
    var showMethod: () -> Void = {}
    var openCheckIn: (CheckInPhase) -> Void = { _ in }
    var openSession: (SessionDraft) -> Void = { _ in }

    private var today: Date { LocalDay.start(of: now) }
    private var todayMetrics: DailyMetrics? { days.first { $0.day == today } }

    private var todaySessions: [TrainingRow] {
        let logs = sessions.filter { $0.day == today }
        let suggested = WorkoutGrouping.sessions(from: workouts.filter { $0.day == today }.map(\.info))
        let fromHealth = suggested.map { session in TrainingRow(suggested: session, log: logs.first { $0.matches(session) }) }
        let manual = logs.filter { $0.workoutIDs.isEmpty }.map { TrainingRow(suggested: nil, log: $0) }
        return (fromHealth + manual).sorted { $0.start < $1.start }
    }

    /// Health sessions that ended at least 30 minutes ago and have no RPE yet.
    private var pendingRPE: TrainingRow? {
        todaySessions.first { row in
            row.suggested != nil && row.log?.sessionRPE == nil && row.end.addingTimeInterval(SessionScales.rpeDelay) <= now
        }
    }

    private var zeppAssessment: MetricAssessment {
        let morning = entries.filter { $0.phase == CheckInPhase.morning.rawValue }
        return BaselineCalculator.assess(.zeppRMSSD, on: now, values: QuestionnaireEntry.values(of: "hrv_rmssd_zepp", from: morning))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            header

            switch syncState {
            case .needsAuthorization:
                AccessCard(requestAccess: requestAccess)
            case .unavailable:
                InfoCard(systemImage: "heart.slash", text: "Apple Health ist auf diesem Gerät nicht verfügbar.")
            case .failed(let message):
                ErrorCard(message: message, retry: retry)
            case .idle, .importing:
                EmptyView()
            }

            if let pending = pendingRPE, let suggested = pending.suggested {
                RPEPromptCard(row: pending) {
                    openSession(SessionDraft(day: today, suggested: suggested, existing: pending.log))
                }
            }

            CheckInCard(now: now, entries: entries.filter { $0.day == today }, open: openCheckIn)

            ForEach(MetricTileModel.tiles(on: now, from: days)) { model in
                switch model.metric {
                case .sleep:
                    SleepTile(assessment: model.assessment, night: todayMetrics)
                case .hrv:
                    MetricTile(model: model, detail: hrvDetail, secondary: zeppAssessment)
                default:
                    MetricTile(model: model)
                }
            }

            TrainingTodayCard(rows: todaySessions, now: now) { row in
                openSession(SessionDraft(day: today, suggested: row.suggested, existing: row.log))
            } addManual: {
                openSession(SessionDraft(day: today))
            }

            Button(action: showMethod) {
                Label("Wie wird die Norm berechnet?", systemImage: "info.circle")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ExplorerFormat.locale)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            SyncIndicator(state: syncState, lastSync: lastSync)
        }
    }

    private var hrvDetail: String? {
        guard let count = todayMetrics?.hrvSamples.count, count > 0 else { return nil }
        return "SDNN aus Apple Health, Mittel aus \(count) \(count == 1 ? "Wert" : "Werten") der Nacht"
    }
}

/// A Health session (possibly merged from several workouts) or a manual log, with its RPE log if any.
struct TrainingRow: Identifiable {
    let suggested: SuggestedSession?
    let log: CompletedSession?

    var id: String { suggested.map { "\($0.start.timeIntervalSince1970)" } ?? log?.id.uuidString ?? "" }
    var kind: SessionKind { log?.sessionKind ?? suggested?.kind ?? .other }
    var start: Date { suggested?.start ?? log?.start ?? .distantPast }
    var end: Date { suggested?.end ?? log?.end ?? .distantPast }
    var minutes: Double { log.map { Double($0.durationMin) } ?? suggested?.activeMinutes ?? 0 }
}

private struct SyncIndicator: View {
    let state: HealthSync.State
    let lastSync: Date?

    var body: some View {
        Group {
            if state == .importing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Aktualisiere …")
                }
            } else if let lastSync {
                Label(lastSync.formatted(date: .omitted, time: .shortened), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct RPEPromptCard: View {
    let row: TrainingRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: row.kind.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wie anstrengend war \(row.kind.title)?")
                        .font(.body.weight(.semibold))
                    Text("\(MetricsFormat.timeRange(row.start, row.end)) · Session-RPE eintragen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

private struct CheckInCard: View {
    let now: Date
    let entries: [QuestionnaireEntry]
    let open: (CheckInPhase) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.morning, systemImage: "sun.max.fill", tint: .orange)
            Divider()
                .padding(.leading, 48)
            row(.evening, systemImage: "moon.stars.fill", tint: .indigo)
        }
        .card()
    }

    private func row(_ phase: CheckInPhase, systemImage: String, tint: Color) -> some View {
        let entry = entries.first { $0.phase == phase.rawValue }
        let available = phase == .morning || Calendar.current.component(.hour, from: now) >= CheckInPhase.eveningStartHour || entry != nil

        return Button {
            open(phase)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(available ? tint : .secondary)
                    .frame(width: 36, height: 36)
                    .background((available ? tint : .secondary).opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(.body.weight(.medium))
                    Text(status(entry: entry, phase: phase, available: available))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if entry?.isComplete == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else if available {
                    Text(entry == nil ? "Ausfüllen" : "Fortsetzen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func status(entry: QuestionnaireEntry?, phase: CheckInPhase, available: Bool) -> String {
        guard let entry else {
            return available ? "Etwa 30 Sekunden" : "Ab \(CheckInPhase.eveningStartHour) Uhr"
        }
        let answers = entry.answers
        let missing = QuestionCatalog.missing(answers, phase: phase).count
        let summary = Self.summary(answers, phase: phase)
        if missing > 0 { return "Noch \(missing) offen" + (summary.isEmpty ? "" : " · " + summary) }
        return summary
    }

    static func summary(_ answers: [String: AnswerValue], phase: CheckInPhase) -> String {
        var parts: [String] = []
        switch phase {
        case .morning:
            if let v = answers["sleep_quality"]?.intValue { parts.append("Schlaf \(v)") }
            if let v = answers["energy"]?.intValue { parts.append("Energie \(v)") }
            if let v = answers["training_motivation"]?.intValue { parts.append("Lust \(v)") }
        case .evening:
            if case .choice(let options) = QuestionCatalog.question("food_amount")?.kind,
               let index = answers["food_amount"]?.intValue, options.indices.contains(index) {
                parts.append("Essen \(options[index])")
            }
            if let v = answers["alcohol_drinks"]?.intValue { parts.append(v == 0 ? "kein Alkohol" : "\(v) Drinks") }
        }
        for region in QuestionCatalog.painRegions {
            let id = "pain_\(region.id)_\(phase.rawValue)"
            if let v = answers[id]?.intValue, v > 0 { parts.append("\(region.title) \(v)") }
        }
        return parts.joined(separator: " · ")
    }
}

private struct AccessCard: View {
    let requestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zugriff auf Apple Health", systemImage: "heart.text.square")
                .font(.headline)
            Text("Cockpit liest Schlaf, HRV, Ruhepuls und Workouts. Es wird nichts geschrieben, die Daten bleiben auf diesem iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Zugriff erlauben", action: requestAccess)
                .buttonStyle(.borderedProminent)
        }
        .card()
    }
}

private struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health konnte nicht gelesen werden")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Erneut versuchen", action: retry)
                    .font(.subheadline)
            }
        }
        .card()
    }
}

private struct InfoCard: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .card()
    }
}

private struct TrainingTodayCard: View {
    let rows: [TrainingRow]
    let now: Date
    let open: (TrainingRow) -> Void
    let addManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Training heute", systemImage: "figure.run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            if rows.isEmpty {
                Text("Noch kein Workout in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                Button { open(row) } label: { rowView(row) }
                    .buttonStyle(.plain)
            }

            Button(action: addManual) {
                Label("Einheit ohne Uhr erfassen", systemImage: "plus")
                    .font(.subheadline)
            }
            .padding(.top, 2)
        }
        .card()
    }

    private func rowView(_ row: TrainingRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(row))
                    .font(.body.weight(.medium))
                Text(subtitle(row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let rpe = row.log?.sessionRPE {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("RPE \(rpe)")
                        .font(.subheadline.weight(.semibold))
                    if let load = row.log?.load {
                        Text("Last \(load)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if row.end <= now {
                Text("RPE")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12), in: .capsule)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func title(_ row: TrainingRow) -> String {
        guard row.kind == .handball, let isMatch = row.log?.isMatch else { return row.kind.title }
        return isMatch ? "Handball · Spiel" : "Handball · Training"
    }

    private func subtitle(_ row: TrainingRow) -> String {
        var parts = [MetricsFormat.timeRange(row.start, row.end), ExplorerFormat.duration(minutes: row.minutes)]
        if let count = row.suggested?.workoutIDs.count, count > 1 { parts.append("\(count) Teile") }
        if row.suggested == nil { parts.append("ohne Uhr") }
        return parts.joined(separator: " · ")
    }
}
