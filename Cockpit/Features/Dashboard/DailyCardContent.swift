import SwiftUI

/// Where the daily card can lead.
enum DashboardLink: Hashable {
    case load
    case weight
}

/// The daily card for one day, independent of SwiftData queries and HealthKit so it can be previewed and rendered with synthetic data.
struct DailyCardContent: View {
    let now: Date
    /// The day shown; `nil` = today (before 04:00 still yesterday).
    var day: Date?
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
    var changeDay: (Int) -> Void = { _ in }
    var goToToday: () -> Void = {}
    var answerMidday: (Int?) -> Void = { _ in }
    var hideSession: (TrainingRow) -> Void = { _ in }
    var deleteLog: (CompletedSession) -> Void = { _ in }
    var openLink: (DashboardLink) -> Void = { _ in }

    private var today: Date { LocalDay.logicalToday(now) }
    private var shownDay: Date { day ?? today }
    private var isToday: Bool { shownDay == today }
    private var dayMetrics: DailyMetrics? { days.first { $0.day == shownDay } }
    private var rows: [TrainingRow] { TrainingData.rows(on: shownDay, workouts: workouts, logs: sessions) }

    /// Today's Health sessions that ended at least 30 minutes ago and have no RPE yet.
    private var pendingRPE: TrainingRow? {
        guard isToday else { return nil }
        return rows.first { row in
            row.suggested != nil && row.log?.sessionRPE == nil && row.end.addingTimeInterval(SessionScales.rpeDelay) <= now
        }
    }

    private var zeppAssessment: MetricAssessment {
        let morning = entries.filter { $0.phase == CheckInPhase.morning.rawValue }
        return BaselineCalculator.assess(.zeppRMSSD, on: shownDay, values: QuestionnaireEntry.values(of: "hrv_rmssd_zepp", from: morning))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            DaySwitcher(day: shownDay, today: today, syncState: syncState, lastSync: lastSync,
                        changeDay: changeDay, goToToday: goToToday)

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
                    openSession(SessionDraft(day: shownDay, suggested: suggested, existing: pending.log))
                }
            }

            CheckInCard(now: now, day: shownDay, entries: entries.filter { $0.day == shownDay },
                        open: openCheckIn, answerMidday: answerMidday)

            ForEach(MetricTileModel.tiles(on: shownDay, from: days)) { model in
                switch model.metric {
                case .sleep:
                    SleepTile(assessment: model.assessment, night: dayMetrics)
                case .hrv:
                    MetricTile(model: model, detail: hrvDetail, secondary: zeppAssessment)
                default:
                    MetricTile(model: model)
                }
            }

            TrainingCard(title: isToday ? "Training heute" : "Training", rows: rows, now: now) { row in
                openSession(SessionDraft(day: shownDay, suggested: row.suggested, existing: row.log))
            } addManual: {
                openSession(SessionDraft(day: shownDay))
            } hide: { row in
                hideSession(row)
            } delete: { log in
                deleteLog(log)
            }

            HistoryCard(
                load: LoadMetrics.summary(TrainingData.loadEntries(workouts: workouts, logs: sessions), today: shownDay,
                                          firstDay: firstTrainingDay),
                weight: TrainingData.weightPoints(from: entries).filter { $0.day <= shownDay },
                open: openLink
            )

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

    private var firstTrainingDay: Date {
        (sessions.map(\.day) + workouts.map(\.day)).min() ?? shownDay
    }

    private var hrvDetail: String? {
        guard let count = dayMetrics?.hrvSamples.count, count > 0 else { return nil }
        return "SDNN aus Apple Health, Mittel aus \(count) \(count == 1 ? "Wert" : "Werten") der Nacht"
    }
}

/// "‹ Gestern, Montag 23. November ›" plus sync status.
private struct DaySwitcher: View {
    let day: Date
    let today: Date
    let syncState: HealthSync.State
    let lastSync: Date?
    let changeDay: (Int) -> Void
    let goToToday: () -> Void

    private var relative: String? {
        let offset = Calendar.current.dateComponents([.day], from: day, to: today).day ?? 0
        switch offset {
        case 0: return "Heute"
        case 1: return "Gestern"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { changeDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Vorheriger Tag")

            VStack(alignment: .leading, spacing: 0) {
                if let relative {
                    Text(relative)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ExplorerFormat.locale)))
                    .font(.subheadline.weight(.medium))
            }

            Button { changeDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .disabled(day >= today)
            .accessibilityLabel("Nächster Tag")

            Spacer()

            if day < today {
                Button("Heute", action: goToToday)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
            } else {
                SyncIndicator(state: syncState, lastSync: lastSync)
            }
        }
        .font(.body.weight(.semibold))
    }
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
    let day: Date
    let entries: [QuestionnaireEntry]
    let open: (CheckInPhase) -> Void
    let answerMidday: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.morning, systemImage: "sun.max.fill", tint: .orange)
            Divider()
                .padding(.leading, 48)
            middayRow
            Divider()
                .padding(.leading, 48)
            row(.evening, systemImage: "moon.stars.fill", tint: .indigo)
        }
        .card()
    }

    private func isAvailable(_ phase: CheckInPhase) -> Bool {
        let startHour = switch phase {
        case .morning: 0
        case .midday: CheckInPhase.middayStartHour
        case .evening: CheckInPhase.eveningStartHour
        }
        let start = Calendar.current.date(byAdding: .hour, value: startHour, to: day) ?? day
        return now >= start || entries.contains { $0.phase == phase.rawValue }
    }

    private var middayRow: some View {
        let value = entries.first { $0.phase == CheckInPhase.midday.rawValue }?.answers["energy_midday"]?.intValue
        let available = isAvailable(.midday)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "sun.haze.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(available ? Color.yellow : .secondary)
                    .frame(width: 36, height: 36)
                    .background((available ? Color.yellow : .secondary).opacity(0.16), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Energie am Mittag")
                        .font(.body.weight(.medium))
                    Text(available ? "1 = sehr müde, 5 = hellwach" : "Ab \(CheckInPhase.middayStartHour) Uhr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if value != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }
            if available {
                OptionButtons(options: (1...5).map(String.init), selection: Binding(
                    get: { value.map { $0 - 1 } },
                    set: { answerMidday($0.map { $0 + 1 }) }
                ), compact: true)
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 6)
    }

    private func row(_ phase: CheckInPhase, systemImage: String, tint: Color) -> some View {
        let entry = entries.first { $0.phase == phase.rawValue }
        let available = isAvailable(phase)

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
        case .midday:
            break
        case .evening:
            if case .choice(let options) = QuestionCatalog.question("food_amount")?.kind,
               let index = answers["food_amount"]?.intValue, options.indices.contains(index) {
                parts.append("Essen \(options[index])")
            }
            if let v = answers["alcohol_drinks"]?.intValue { parts.append(v == 0 ? "kein Alkohol" : "\(v) Drinks") }
        }
        for question in QuestionCatalog.questions(for: phase) where question.kind == .pain {
            if let v = answers[question.id]?.intValue, v > 0 {
                parts.append("\(question.title) \(v)")
            }
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

private struct TrainingCard: View {
    let title: String
    let rows: [TrainingRow]
    let now: Date
    let open: (TrainingRow) -> Void
    let addManual: () -> Void
    let hide: (TrainingRow) -> Void
    let delete: (CompletedSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "figure.run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            if rows.isEmpty {
                Text("Kein Workout in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                Button { open(row) } label: { rowView(row) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Bearbeiten", systemImage: "pencil") { open(row) }
                        if row.suggested != nil {
                            Button("Workout ausblenden", systemImage: "eye.slash", role: .destructive) { hide(row) }
                        }
                        if let log = row.log {
                            Button(row.suggested == nil ? "Einheit löschen" : "RPE-Eintrag löschen",
                                   systemImage: "trash", role: .destructive) { delete(log) }
                        }
                    }
            }

            HStack {
                Button(action: addManual) {
                    Label("Einheit ohne Uhr erfassen", systemImage: "plus")
                        .font(.subheadline)
                }
                Spacer()
                if !rows.isEmpty {
                    Text("Gedrückt halten für mehr")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
        switch row.log?.effectivePlanUnit {
        case "Spiel": "Handball · Spiel"
        case "Handball": "Handball · Training"
        case "Sonstiges", nil: row.kind.title
        case let unit?: "Gym · Einheit \(unit)"
        }
    }

    private func subtitle(_ row: TrainingRow) -> String {
        var parts = [MetricsFormat.timeRange(row.start, row.end), ExplorerFormat.duration(minutes: row.minutes)]
        if let count = row.suggested?.workoutIDs.count, count > 1 { parts.append("\(count) Teile") }
        if row.suggested == nil { parts.append("ohne Uhr") }
        return parts.joined(separator: " · ")
    }
}

/// Links to the load and weight history with a one-line summary each.
private struct HistoryCard: View {
    let load: LoadSummary
    let weight: [WeightPoint]
    let open: (DashboardLink) -> Void

    var body: some View {
        VStack(spacing: 0) {
            linkRow(.load, systemImage: "chart.bar.fill", tint: .green, title: "Belastung", subtitle: loadSubtitle)
            Divider()
                .padding(.leading, 48)
            linkRow(.weight, systemImage: "scalemass.fill", tint: .blue, title: "Gewicht", subtitle: weightSubtitle)
        }
        .card()
    }

    private var loadSubtitle: String {
        var text = "7 Tage: \(MetricsFormat.load(load.acute)) AU"
        if let ratio = load.ratio { text += " · Akut:Chronisch \(ExplorerFormat.number(ratio, digits: 2))" }
        if load.unrated > 0 { text += " · \(load.unrated) ohne RPE" }
        return text
    }

    private var weightSubtitle: String {
        guard let last = weight.last else { return "Noch keine Wiegung" }
        var text = "\(ExplorerFormat.number(last.kg)) kg am \(last.day.formatted(.dateTime.day().month(.twoDigits).locale(ExplorerFormat.locale)))"
        if let change = WeightTrend.weeklyChange(weight) {
            text += " · Trend \(change < 0 ? "−" : "+")\(ExplorerFormat.number(abs(change), digits: 1)) kg/Woche"
        }
        return text
    }

    private func linkRow(_ link: DashboardLink, systemImage: String, tint: Color, title: String, subtitle: String) -> some View {
        Button { open(link) } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
