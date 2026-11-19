import Foundation
import SwiftData

/// Schema version 1. From here on every model change needs a new `VersionedSchema` and a migration stage,
/// because questionnaire answers and session RPE cannot be re-imported.
enum CockpitSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DailyMetrics.self, HealthWorkout.self, QuestionnaireEntry.self, CompletedSession.self]
    }
}

enum CockpitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CockpitSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum Persistence {
    private static let versionedKey = "storeIsVersioned"

    static let container: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: CockpitSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        do {
            let container = try open(schema: schema, configuration: configuration)
            UserDefaults.standard.set(true, forKey: versionedKey)
            return container
        } catch {
            // A store from before versioning only holds Apple Health data, which is re-imported automatically.
            // Once the store is versioned, data is never deleted automatically.
            guard !UserDefaults.standard.bool(forKey: versionedKey) else {
                fatalError("Die Datenbank konnte nicht geöffnet werden: \(error)")
            }
            removeStore(at: configuration.url)
            do {
                let container = try open(schema: schema, configuration: configuration)
                UserDefaults.standard.set(true, forKey: versionedKey)
                return container
            } catch {
                fatalError("Die Datenbank konnte nicht angelegt werden: \(error)")
            }
        }
    }

    private static func open(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: CockpitMigrationPlan.self, configurations: configuration)
    }

    private static func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
