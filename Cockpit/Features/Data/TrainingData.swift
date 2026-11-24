import Foundation

/// A Health session (possibly merged from several workouts) or a manual log, with its RPE log if any.
struct TrainingRow: Identifiable {
    let suggested: SuggestedSession?
    let log: CompletedSession?

    var id: String { suggested.map { "\($0.start.timeIntervalSince1970)" } ?? log?.id.uuidString ?? "" }
    var kind: SessionKind { log?.sessionKind ?? suggested?.kind ?? .other }
    var start: Date { suggested?.start ?? log?.start ?? .distantPast }
    var end: Date { suggested?.end ?? log?.end ?? .distantPast }
    var minutes: Double { log.map { Double($0.durationMin) } ?? suggested?.activeMinutes ?? 0 }
    var workoutIDs: [UUID] { suggested?.workoutIDs ?? log?.workoutIDs ?? [] }
}

/// Shared derivations from stored workouts, session logs and check-ins. Hidden workouts are left out everywhere.
enum TrainingData {
    static func rows(on day: Date, workouts: [HealthWorkout], logs: [CompletedSession]) -> [TrainingRow] {
        let dayLogs = logs.filter { $0.day == day }
        let visible = workouts.filter { $0.day == day && !$0.isHidden }
        let suggested = WorkoutGrouping.sessions(from: visible.map(\.info))
        let fromHealth = suggested.map { session in TrainingRow(suggested: session, log: dayLogs.first { $0.matches(session) }) }
        let manual = dayLogs.filter { $0.workoutIDs.isEmpty }.map { TrainingRow(suggested: nil, log: $0) }
        return (fromHealth + manual).sorted { $0.start < $1.start }
    }

    /// All sessions for load monitoring: logged ones with their load, unlogged Health sessions as unrated.
    static func loadEntries(workouts: [HealthWorkout], logs: [CompletedSession]) -> [LoadEntry] {
        let hidden = Set(workouts.filter(\.isHidden).map(\.healthID))
        let visibleLogs = logs.filter { $0.workoutIDs.isEmpty || !Set($0.workoutIDs).isSubset(of: hidden) }
        var entries = visibleLogs.map { LoadEntry(day: $0.day, kind: $0.sessionKind, load: $0.load, throwVolume: $0.throwVolume) }

        let suggested = WorkoutGrouping.sessions(from: workouts.filter { !$0.isHidden }.map(\.info))
        for session in suggested where !visibleLogs.contains(where: { $0.matches(session) }) {
            entries.append(LoadEntry(day: LocalDay.start(of: session.start), kind: session.kind, load: nil))
        }
        return entries
    }

    static func weightPoints(from entries: [QuestionnaireEntry]) -> [WeightPoint] {
        entries.compactMap { entry in
            guard entry.phase == CheckInPhase.morning.rawValue, let kg = entry.answers["body_weight"]?.doubleValue else { return nil }
            return WeightPoint(day: entry.day, kg: kg)
        }
        .sorted { $0.day < $1.day }
    }
}
