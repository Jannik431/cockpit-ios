import Foundation
import SwiftData

/// A training session as confirmed by the user, with session RPE. Not re-importable: handle with care.
@Model
final class CompletedSession {
    var id: UUID
    var day: Date
    var start: Date
    var end: Date
    /// `SessionKind` raw value, confirmed by the user.
    var kind: String
    var durationMin: Int
    /// Borg CR10, 0–10.
    var sessionRPE: Int?
    /// Handball only: match (true) or practice (false).
    var isMatch: Bool?
    /// Handball only: index into `SessionScales.throwVolumes`.
    var throwVolume: Int?
    var note: String?
    /// Linked Apple Health workouts; empty for sessions logged without the watch.
    var workoutIDs: [UUID]
    var scalesVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(day: Date, start: Date, end: Date, kind: SessionKind, durationMin: Int, workoutIDs: [UUID], now: Date = .now) {
        self.id = UUID()
        self.day = day
        self.start = start
        self.end = end
        self.kind = kind.rawValue
        self.durationMin = durationMin
        self.workoutIDs = workoutIDs
        self.scalesVersion = SessionScales.version
        self.createdAt = now
        self.updatedAt = now
    }

    var sessionKind: SessionKind { SessionKind(rawValue: kind) ?? .other }

    /// Foster's session load: RPE × duration in minutes (arbitrary units).
    var load: Int? { sessionRPE.map { $0 * durationMin } }

    func matches(_ session: SuggestedSession) -> Bool {
        !Set(workoutIDs).isDisjoint(with: session.workoutIDs)
    }
}
