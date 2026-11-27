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
    /// Knee pain during the session, 0–10. Added in schema V2 (scales version 2).
    var kneePainLeft: Int?
    var kneePainRight: Int?
    /// Handball match only: minutes on court. Added in schema V2.
    var minutesPlayed: Int?
    /// Unit from the training plan (`SessionScales.planUnits`), e.g. "A" or "Spiel". Added in schema V3.
    var planUnit: String?
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

    /// The plan unit, or for older logs the best guess from kind and match flag.
    var effectivePlanUnit: String? { planUnit ?? SessionScales.planUnit(kind: sessionKind, isMatch: isMatch) }

    /// Foster's session load: RPE × duration in minutes (arbitrary units).
    var load: Int? { sessionRPE.map { $0 * durationMin } }

    func matches(_ session: SuggestedSession) -> Bool {
        !Set(workoutIDs).isDisjoint(with: session.workoutIDs)
    }
}
