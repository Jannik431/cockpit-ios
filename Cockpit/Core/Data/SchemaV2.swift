import Foundation
import SwiftData

/// Schema version 2, frozen. Only `CompletedSession` changed in V3 and is copied here;
/// the other models are unchanged and shared with the current schema.
/// Never edit this copy: it must match stores that already exist on devices.
enum CockpitSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DailyMetrics.self, HealthWorkout.self, QuestionnaireEntry.self, CompletedSession.self]
    }

    @Model
    final class CompletedSession {
        var id: UUID
        var day: Date
        var start: Date
        var end: Date
        var kind: String
        var durationMin: Int
        var sessionRPE: Int?
        var isMatch: Bool?
        var throwVolume: Int?
        var note: String?
        var kneePainLeft: Int?
        var kneePainRight: Int?
        var minutesPlayed: Int?
        var workoutIDs: [UUID]
        var scalesVersion: Int
        var createdAt: Date
        var updatedAt: Date

        init(day: Date, start: Date, end: Date, kind: String, durationMin: Int, workoutIDs: [UUID], now: Date = .now) {
            self.id = UUID()
            self.day = day
            self.start = start
            self.end = end
            self.kind = kind
            self.durationMin = durationMin
            self.workoutIDs = workoutIDs
            self.scalesVersion = 2
            self.createdAt = now
            self.updatedAt = now
        }
    }
}
