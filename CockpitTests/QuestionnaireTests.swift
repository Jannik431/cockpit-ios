import Foundation
import SwiftData
import Testing
@testable import Cockpit

struct QuestionCatalogTests {
    @Test func idsAreUnique() {
        let ids = QuestionCatalog.questions.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func painRegionsMorningAndEvening() {
        for region in QuestionCatalog.painRegions {
            #expect(QuestionCatalog.question("pain_\(region.id)_morning")?.kind == .pain)
        }
        // Evening: knee in everyday life instead of the v1 evening knee; other regions as before.
        #expect(QuestionCatalog.question("knee_daily_left")?.phase == .evening)
        #expect(QuestionCatalog.question("knee_daily_right")?.phase == .evening)
        #expect(QuestionCatalog.question("pain_knee_left_evening") == nil)
        #expect(QuestionCatalog.question("pain_shoulder_left_evening")?.kind == .pain)
    }

    @Test func retiredIDsAreNotReused() {
        let ids = Set(QuestionCatalog.questions.map(\.id))
        #expect(ids.isDisjoint(with: QuestionCatalog.retiredIDs))
    }

    @Test func conditionsPointToMatchingParentsOfTheSamePhase() {
        for question in QuestionCatalog.questions {
            guard let condition = question.shownIf else { continue }
            let parent = QuestionCatalog.question(condition.parentID)
            #expect(parent?.phase == question.phase)
            switch condition {
            case .yes: #expect(parent?.kind == .yesNo)
            case .choiceNot:
                guard case .choice = parent?.kind else {
                    Issue.record("\(question.id) depends on a non-choice question")
                    continue
                }
            }
        }
    }

    @Test func symptomsOnlyWhenIllAndKeptOtherwiseDropped() {
        let symptoms = QuestionCatalog.question("symptoms")!
        #expect(!QuestionCatalog.isVisible(symptoms, answers: [:]))
        #expect(!QuestionCatalog.isVisible(symptoms, answers: ["illness": .int(0)]))
        #expect(QuestionCatalog.isVisible(symptoms, answers: ["illness": .int(1)]))

        let cleaned = QuestionCatalog.cleaned(["illness": .int(0), "symptoms": .list([0, 2])], phase: .morning)
        #expect(cleaned["symptoms"] == nil)
    }

    @Test func answersOfOlderVersionsAreKeptWhenSaving() {
        let cleaned = QuestionCatalog.cleaned(["pain_knee_left_evening": .int(3), "alcohol_drinks": .int(0)], phase: .evening)
        #expect(cleaned["pain_knee_left_evening"] == .int(3))
    }

    @Test func followUpIsHiddenAndDroppedAfterNo() {
        var answers: [String: AnswerValue] = ["caffeine_today": .bool(true), "last_caffeine_time": .time(15 * 60)]
        let followUp = QuestionCatalog.question("last_caffeine_time")!
        #expect(QuestionCatalog.isVisible(followUp, answers: answers))

        answers["caffeine_today"] = .bool(false)
        #expect(!QuestionCatalog.isVisible(followUp, answers: answers))
        #expect(QuestionCatalog.cleaned(answers, phase: .evening)["last_caffeine_time"] == nil)
    }

    @Test func optionalQuestionsDoNotBlockCompletion() {
        var answers: [String: AnswerValue] = [:]
        for question in QuestionCatalog.questions(for: .morning) where !question.optional {
            answers[question.id] = .int(3)
        }
        #expect(QuestionCatalog.missing(answers, phase: .morning).isEmpty)
        #expect(answers["hrv_rmssd_zepp"] == nil)
    }

    @Test func caffeineTimeIsOnlyRequiredAfterYes() {
        var answers: [String: AnswerValue] = [
            "food_amount": .int(1), "protein_ok": .bool(true), "caffeine_today": .bool(false), "alcohol_drinks": .int(0),
        ]
        for question in QuestionCatalog.questions(for: .evening) where question.kind == .pain {
            answers[question.id] = .int(0)
        }
        #expect(QuestionCatalog.missing(answers, phase: .evening).isEmpty)
        answers["caffeine_today"] = .bool(true)
        #expect(QuestionCatalog.missing(answers, phase: .evening).map(\.id) == ["last_caffeine_time"])
    }
}

struct AnswerValueTests {
    @Test func encodesAsPlainJSONValues() throws {
        let answers: [String: AnswerValue] = ["a": .int(5), "b": .double(72.4), "c": .bool(false), "d": .time(15 * 60 + 5)]
        let json = String(decoding: try JSONEncoder().encode(answers), as: UTF8.self)
        #expect(json.contains("\"d\":\"15:05\""))
        #expect(json.contains("\"c\":false"))

        let decoded = try JSONDecoder().decode([String: AnswerValue].self, from: Data(json.utf8))
        #expect(decoded["a"]?.intValue == 5)
        #expect(decoded["b"]?.doubleValue == 72.4)
        #expect(decoded["c"]?.boolValue == false)
        #expect(decoded["d"]?.minutes == 905)
    }
}

@MainActor
struct QuestionnaireStoreTests {
    @Test func v1StoreMigratesToV2WithoutLosingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let day = Calendar.current.startOfDay(for: .now)
        let workoutID = UUID()

        do {
            let v1 = Schema(versionedSchema: CockpitSchemaV1.self)
            let container = try ModelContainer(for: v1, configurations: ModelConfiguration(schema: v1, url: url))
            let context = ModelContext(container)
            context.insert(CockpitSchemaV1.HealthWorkout(healthID: workoutID, day: day, start: day, end: day.addingTimeInterval(3600),
                                                         activityTypeRaw: 3000, activityTypeName: "Andere", sourceBundleID: "com.example"))
            let session = CockpitSchemaV1.CompletedSession(day: day, start: day, end: day.addingTimeInterval(3600),
                                                           kind: "handball", durationMin: 60, workoutIDs: [workoutID])
            session.sessionRPE = 7
            session.throwVolume = 2
            context.insert(session)
            let entry = QuestionnaireEntry(day: day, phase: .evening)
            entry.save(answers: ["pain_knee_left_evening": .int(3)], note: "alt")
            context.insert(entry)
            try context.save()
        }

        let v2 = Persistence.currentSchema
        let migrated = try Persistence.open(schema: v2, configuration: ModelConfiguration(schema: v2, url: url))
        let context = ModelContext(migrated)

        let workout = try #require(try context.fetch(FetchDescriptor<HealthWorkout>()).first)
        #expect(workout.healthID == workoutID)
        #expect(workout.isHidden == false)

        let session = try #require(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        #expect(session.sessionRPE == 7)
        #expect(session.throwVolume == 2)
        #expect(session.kneePainLeft == nil)
        #expect(session.minutesPlayed == nil)

        let entry = try #require(try context.fetch(FetchDescriptor<QuestionnaireEntry>()).first)
        #expect(entry.answers["pain_knee_left_evening"] == .int(3))
        #expect(entry.note == "alt")
    }

    @Test func versionedSchemaStoresEntriesAndSessions() throws {
        let schema = Persistence.currentSchema
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CockpitMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: .now)

        let entry = QuestionnaireEntry(day: day, phase: .evening)
        entry.save(answers: ["caffeine_today": .bool(false), "last_caffeine_time": .time(600)], note: "  ")
        context.insert(entry)

        let workoutID = UUID()
        let session = CompletedSession(day: day, start: day, end: day.addingTimeInterval(3600), kind: .handball,
                                       durationMin: 60, workoutIDs: [workoutID])
        session.sessionRPE = 7
        context.insert(session)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<QuestionnaireEntry>()).first)
        #expect(stored.answers == ["caffeine_today": .bool(false)])
        #expect(stored.note == nil)
        #expect(stored.catalogVersion == QuestionCatalog.version)

        let storedSession = try #require(try context.fetch(FetchDescriptor<CompletedSession>()).first)
        #expect(storedSession.load == 420)
        #expect(storedSession.matches(SuggestedSession(kind: .handball, start: day, end: day, workoutIDs: [workoutID], activeMinutes: 60)))
    }
}
