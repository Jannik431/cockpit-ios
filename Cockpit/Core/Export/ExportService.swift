import Foundation
import Observation
import SwiftData

/// Builds the CSV from the store and writes it into the file the user linked once (e.g. in Google Drive).
/// The file is opened via the Files app; the app keeps a bookmark and overwrites the same file afterwards.
@Observable
final class ExportService {
    static let shared = ExportService()

    private(set) var linkedFileName: String?
    private(set) var lastExport: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let bookmarkKey = "exportFileBookmark"
    @ObservationIgnored private let lastExportKey = "exportLastSuccess"

    init() {
        linkedFileName = UserDefaults.standard.string(forKey: bookmarkKey + ".name")
        let last = UserDefaults.standard.double(forKey: lastExportKey)
        lastExport = last > 0 ? Date(timeIntervalSince1970: last) : nil
    }

    var isLinked: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    // MARK: - Linking

    func link(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: bookmarkKey + ".name")
            linkedFileName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = "Datei konnte nicht verknüpft werden: \(error.localizedDescription)"
        }
    }

    func unlink() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: bookmarkKey + ".name")
        linkedFileName = nil
    }

    // MARK: - Export

    /// Rewrites the linked file with all days. Does nothing if no file is linked.
    func exportIfLinked(context: ModelContext, now: Date = .now) {
        guard isLinked else { return }
        do {
            try write(Data(csv(context: context, now: now).utf8))
            lastExport = now
            lastError = nil
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastExportKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The CSV as a temporary file, for sharing by hand.
    func temporaryFile(context: ModelContext, now: Date = .now) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(CSVExport.fileName)
        try Data(csv(context: context, now: now).utf8).write(to: url, options: .atomic)
        return url
    }

    func csv(context: ModelContext, now: Date = .now) -> String {
        CSVExport.csv(days: Self.exportDays(context: context, today: LocalDay.logicalToday(now)))
    }

    private func write(_ data: Data) throws {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var writeError: Error?
        // Write in place (not atomically) so the file provider keeps the same file and syncs it.
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }

        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
    }

    // MARK: - Collecting data

    /// One entry per day from the first day with any data until `today`.
    static func exportDays(context: ModelContext, today: Date, calendar: Calendar = .current) -> [ExportDay] {
        let metrics = (try? context.fetch(FetchDescriptor<DailyMetrics>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<QuestionnaireEntry>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<CompletedSession>())) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<HealthWorkout>())) ?? []

        let firstDay = (metrics.map(\.day) + entries.map(\.day) + sessions.map(\.day)).min() ?? today
        let count = (calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1
        let days = LocalDay.window(endingAt: today, count: max(count, 1), calendar: calendar)

        let metricsByDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let entriesByDay = Dictionary(grouping: entries, by: \.day)

        return days.map { day in
            var export = ExportDay(day: day)
            export.asleepMin = metricsByDay[day]?.asleepMin
            export.restingHR = metricsByDay[day]?.restingHR
            for entry in entriesByDay[day] ?? [] {
                switch entry.checkInPhase {
                case .morning: export.morning = entry.answers
                case .midday: export.midday = entry.answers
                case .evening: export.evening = entry.answers
                case nil: break
                }
                if let note = entry.note, let phase = entry.checkInPhase {
                    export.notes.append(phase == .evening ? "Abend: \(note)" : (phase == .morning ? "Morgen: \(note)" : note))
                }
            }
            // Logged sessions and Health sessions without a log (minutes only), hidden workouts excluded, by start.
            for row in TrainingData.rows(on: day, workouts: workouts, logs: sessions) {
                guard let session = row.log else {
                    export.sessions.append(ExportSession(kind: row.kind, durationMin: Int(row.minutes.rounded())))
                    continue
                }
                export.sessions.append(ExportSession(
                    kind: session.sessionKind,
                    rpe: session.sessionRPE,
                    durationMin: session.durationMin,
                    isMatch: session.isMatch,
                    throwVolume: session.throwVolume,
                    kneePainLeft: session.kneePainLeft,
                    kneePainRight: session.kneePainRight,
                    minutesPlayed: session.minutesPlayed,
                    planUnit: session.effectivePlanUnit
                ))
                if let note = session.note { export.notes.append("\(session.effectivePlanUnit ?? session.sessionKind.title): \(note)") }
            }
            return export
        }
    }
}
