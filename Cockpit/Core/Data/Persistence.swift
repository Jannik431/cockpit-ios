import Foundation
import SwiftData

/// Current schema. Every model change needs a new `VersionedSchema`, a frozen copy of the old models
/// (see `CockpitSchemaV1`) and a migration stage, because questionnaire answers and session RPE cannot be re-imported.
///
/// - V2: `HealthWorkout.isHidden`; `CompletedSession.kneePainLeft/Right`, `minutesPlayed`.
enum CockpitSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DailyMetrics.self, HealthWorkout.self, QuestionnaireEntry.self, CompletedSession.self]
    }
}

enum CockpitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CockpitSchemaV1.self, CockpitSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: CockpitSchemaV1.self, toVersion: CockpitSchemaV2.self)]
    }
}

enum Persistence {
    private static let versionedKey = "storeIsVersioned"

    static let container: ModelContainer = makeContainer()

    static var currentSchema: Schema { Schema(versionedSchema: CockpitSchemaV2.self) }

    private static func makeContainer() -> ModelContainer {
        let schema = currentSchema
        let configuration = ModelConfiguration(schema: schema)
        backUpBeforeMigration(storeURL: configuration.url)
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

    static func open(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: CockpitMigrationPlan.self, configurations: configuration)
    }

    /// Copies the existing store once per schema version before SwiftData migrates it,
    /// to `Application Support/Backups/before-schema-<version>/`. Never overwritten, never deleted automatically.
    private static func backUpBeforeMigration(storeURL: URL) {
        let version = CockpitSchemaV2.versionIdentifier
        let key = "backupBeforeSchema\(version.major)"
        let fileManager = FileManager.default
        guard !UserDefaults.standard.bool(forKey: key), fileManager.fileExists(atPath: storeURL.path) else { return }

        let folder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("before-schema-\(version.major)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                let target = folder.appendingPathComponent(source.lastPathComponent)
                if fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: source, to: target)
                }
            }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Without a backup the migration still runs; SwiftData leaves the store untouched if it fails.
        }
    }

    private static func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
