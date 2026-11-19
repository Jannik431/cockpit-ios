import Foundation
import Observation
import SwiftData

/// Runs the Apple Health import when the app starts or comes back to the foreground.
@Observable
final class HealthSync {
    enum State: Equatable {
        case idle
        case unavailable
        case needsAuthorization
        case importing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastRun: Date?
    private(set) var lastResult: HealthImporter.Result?

    @ObservationIgnored private let reader: HealthKitReader
    @ObservationIgnored private let importer: HealthImporter

    init(reader: HealthKitReader = HealthKitReader()) {
        self.reader = reader
        self.importer = HealthImporter(reader: reader)
    }

    /// Set before the first `await`, so overlapping triggers (launch + foreground) cannot start two imports.
    @ObservationIgnored private var isRunning = false

    func run(context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        guard HealthKitReader.isAvailable else {
            state = .unavailable
            return
        }
        do {
            if try await reader.needsAuthorizationRequest() {
                state = .needsAuthorization
                return
            }
            state = .importing
            lastResult = try await importer.importRecent(into: context)
            lastRun = .now
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestAccess(context: ModelContext) async {
        do {
            try await reader.requestAuthorization()
            state = .idle
            isRunning = false
            await run(context: context)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
