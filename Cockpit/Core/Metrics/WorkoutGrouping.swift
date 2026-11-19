import Foundation
import HealthKit

nonisolated enum SessionKind: String, Codable, CaseIterable, Sendable {
    case gym
    case handball
    case other

    var title: String {
        switch self {
        case .gym: "Gym"
        case .handball: "Handball"
        case .other: "Sonstiges"
        }
    }
}

/// Maps Apple Health workout types to session kinds. This is only a suggestion; the user confirms it.
/// Handball is usually recorded via automatic activity detection, which arrives as "other".
nonisolated enum WorkoutMapping {
    static func suggestedKind(activityTypeRaw: Int) -> SessionKind {
        switch HKWorkoutActivityType(rawValue: UInt(max(activityTypeRaw, 0))) {
        case .traditionalStrengthTraining, .functionalStrengthTraining: .gym
        case .handball, .other: .handball
        default: .other
        }
    }
}

nonisolated struct WorkoutInfo: Sendable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let activityTypeRaw: Int

    var durationMinutes: Double { end.timeIntervalSince(start) / 60 }
}

nonisolated struct SuggestedSession: Sendable, Equatable {
    let kind: SessionKind
    let start: Date
    let end: Date
    let workoutIDs: [UUID]
    /// Sum of the recorded workout durations (pauses between merged parts excluded).
    let activeMinutes: Double
}

nonisolated enum WorkoutGrouping {
    /// Consecutive workouts of the same kind with a smaller gap are one session
    /// (automatic detection sometimes splits a match into several workouts).
    static let maxGap: TimeInterval = 30 * 60

    static func sessions(from workouts: [WorkoutInfo]) -> [SuggestedSession] {
        var result: [SuggestedSession] = []
        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            let kind = WorkoutMapping.suggestedKind(activityTypeRaw: workout.activityTypeRaw)
            if let last = result.last, last.kind == kind, workout.start.timeIntervalSince(last.end) < maxGap {
                result[result.count - 1] = SuggestedSession(
                    kind: kind,
                    start: last.start,
                    end: max(last.end, workout.end),
                    workoutIDs: last.workoutIDs + [workout.id],
                    activeMinutes: last.activeMinutes + workout.durationMinutes
                )
            } else {
                result.append(SuggestedSession(
                    kind: kind,
                    start: workout.start,
                    end: workout.end,
                    workoutIDs: [workout.id],
                    activeMinutes: workout.durationMinutes
                ))
            }
        }
        return result
    }
}
