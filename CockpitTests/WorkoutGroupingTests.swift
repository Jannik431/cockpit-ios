import Foundation
import HealthKit
import Testing
@testable import Cockpit

/// All data here is synthetic.
struct WorkoutGroupingTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func workout(_ type: HKWorkoutActivityType, startMin: Double, durationMin: Double) -> WorkoutInfo {
        let start = base.addingTimeInterval(startMin * 60)
        return WorkoutInfo(id: UUID(), start: start, end: start.addingTimeInterval(durationMin * 60),
                           activityTypeRaw: Int(type.rawValue))
    }

    @Test func mappingFollowsPersonalUsage() {
        #expect(WorkoutMapping.suggestedKind(activityTypeRaw: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue)) == .gym)
        #expect(WorkoutMapping.suggestedKind(activityTypeRaw: Int(HKWorkoutActivityType.other.rawValue)) == .handball)
        #expect(WorkoutMapping.suggestedKind(activityTypeRaw: Int(HKWorkoutActivityType.handball.rawValue)) == .handball)
        #expect(WorkoutMapping.suggestedKind(activityTypeRaw: Int(HKWorkoutActivityType.surfingSports.rawValue)) == .other)
    }

    @Test func splitMatchIsMerged() {
        // Automatic detection: first half, 15 min break, second half.
        let parts = [workout(.other, startMin: 0, durationMin: 30), workout(.other, startMin: 45, durationMin: 30)]
        let sessions = WorkoutGrouping.sessions(from: parts.reversed())
        #expect(sessions.count == 1)
        #expect(sessions[0].kind == .handball)
        #expect(sessions[0].activeMinutes == 60)
        #expect(sessions[0].end == base.addingTimeInterval(75 * 60))
        #expect(sessions[0].workoutIDs == parts.map(\.id))
    }

    @Test func largeGapOrDifferentKindStaysSeparate() {
        let workouts = [
            workout(.traditionalStrengthTraining, startMin: 0, durationMin: 60),
            workout(.other, startMin: 70, durationMin: 60),   // different kind
            workout(.other, startMin: 170, durationMin: 30),  // 40 min gap
        ]
        let sessions = WorkoutGrouping.sessions(from: workouts)
        #expect(sessions.map(\.kind) == [.gym, .handball, .handball])
    }
}
