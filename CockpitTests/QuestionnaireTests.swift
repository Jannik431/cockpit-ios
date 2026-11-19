import Foundation
import SwiftData
import Testing
@testable import Cockpit

struct QuestionCatalogTests {
    @Test func idsAreUnique() {
        let ids = QuestionCatalog.questions.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func conditionsPointToYesNoQuestionsOfTheSamePhase() {
        for question in QuestionCatalog.questions {
            guard let parentID = question.shownIfYes else { continue }
            let parent = QuestionCatalog.question(parentID)
            #expect(parent?.kind == .yesNo)
            #expect(parent?.phase == question.phase)
        }
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
            "pain_knee_evening": .int(0), "food_amount": .int(1), "protein_ok": .bool(true),
            "caffeine_today": .bool(false), "alcohol_drinks": .int(0),
        ]
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
    @Test func versionedSchemaStoresEntriesAndSessions() throws {
        let schema = Schema(versionedSchema: CockpitSchemaV1.self)
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
