import Foundation
import SwiftData

/// A workout as recorded in Apple Health. Session kind and RPE come from the user, not from here.
@Model
final class HealthWorkout {
    @Attribute(.unique) var healthID: UUID
    var day: Date
    var start: Date
    var end: Date
    var activityTypeRaw: Int
    var activityTypeName: String?
    var sourceBundleID: String
    /// Hidden by the user (e.g. wrongly detected). Hidden workouts count nowhere. Added in schema V2.
    var isHidden: Bool = false

    init(healthID: UUID, day: Date, start: Date, end: Date, activityTypeRaw: Int, activityTypeName: String?, sourceBundleID: String) {
        self.healthID = healthID
        self.day = day
        self.start = start
        self.end = end
        self.activityTypeRaw = activityTypeRaw
        self.activityTypeName = activityTypeName
        self.sourceBundleID = sourceBundleID
    }

    var info: WorkoutInfo {
        WorkoutInfo(id: healthID, start: start, end: end, activityTypeRaw: activityTypeRaw)
    }
}
