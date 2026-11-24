import Foundation
import SwiftData

/// Schema version 1, frozen. Only the models that changed in V2 are copied here;
/// `DailyMetrics` and `QuestionnaireEntry` are unchanged and shared with the current schema.
/// Never edit these copies: they must match stores that already exist on devices.
enum CockpitSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DailyMetrics.self, HealthWorkout.self, QuestionnaireEntry.self, CompletedSession.self]
    }

    @Model
    final class HealthWorkout {
        @Attribute(.unique) var healthID: UUID
        var day: Date
        var start: Date
        var end: Date
        var activityTypeRaw: Int
        var activityTypeName: String?
        var sourceBundleID: String

        init(healthID: UUID, day: Date, start: Date, end: Date, activityTypeRaw: Int, activityTypeName: String?, sourceBundleID: String) {
            self.healthID = healthID
            self.day = day
            self.start = start
            self.end = end
            self.activityTypeRaw = activityTypeRaw
            self.activityTypeName = activityTypeName
            self.sourceBundleID = sourceBundleID
        }
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
            self.scalesVersion = 1
            self.createdAt = now
            self.updatedAt = now
        }
    }
}
