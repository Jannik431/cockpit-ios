import HealthKit
import UIKit

/// Wakes the app when a new workout arrives in Apple Health (HealthKit background delivery),
/// imports it and schedules the RPE reminder. Must be started on every launch.
final class HealthBackgroundObserver {
    static let shared = HealthBackgroundObserver()

    private let store = HKHealthStore()
    private var started = false

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), !started else { return }
        started = true
        let type = HKObjectType.workoutType()
        store.execute(Self.makeQuery(for: type))
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// Built outside the main actor: HealthKit calls the handler on a background queue.
    nonisolated private static func makeQuery(for type: HKSampleType) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            let done = CompletionBox(completion)
            guard error == nil else {
                done.call()
                return
            }
            Task { @MainActor in
                await handleNewWorkouts()
                done.call()
            }
        }
    }

    private static func handleNewWorkouts() async {
        let context = Persistence.container.mainContext
        let inForeground = UIApplication.shared.applicationState == .active
        await HealthSync.shared.run(context: context)
        await ReminderCenter.shared.refresh(context: context, inForeground: inForeground)
    }
}

/// HealthKit's completion handler must be called exactly once, after the work is done.
nonisolated private struct CompletionBox: @unchecked Sendable {
    private let completion: () -> Void

    init(_ completion: @escaping () -> Void) {
        self.completion = completion
    }

    func call() {
        completion()
    }
}
