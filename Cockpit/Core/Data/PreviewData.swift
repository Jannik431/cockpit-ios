#if DEBUG
import Foundation

/// Synthetic, deterministic data for SwiftUI previews and screenshots. Not real health data.
enum PreviewData {
    static func days(endingAt now: Date, count: Int = 45, calendar: Calendar = .current) -> [DailyMetrics] {
        LocalDay.window(endingAt: now, count: count, calendar: calendar).enumerated().map { index, day in
            let i = Double(index)
            let isToday = index == count - 1
            let metrics = DailyMetrics(day: day, fetchedAt: now)

            // Two nights without data to show gaps.
            guard index != count - 12 && index != count - 11 else { return metrics }

            let sleep = isToday ? 412 : 452 + 28 * sin(i * 0.9) + (index % 7 == 5 ? -55 : 0)
            let inBedStart = calendar.date(byAdding: .minute, value: -(sleep.rounded() > 430 ? 85 : 55), to: day)!
            metrics.inBedStart = inBedStart
            metrics.inBedEnd = inBedStart.addingTimeInterval((sleep + 32) * 60)
            metrics.asleepMin = Int(sleep.rounded())
            metrics.deepMin = Int((sleep * 0.17).rounded())
            metrics.remMin = Int((sleep * 0.21).rounded())
            metrics.coreMin = Int(sleep.rounded()) - metrics.deepMin! - metrics.remMin!
            metrics.awakeMin = 24
            metrics.sleepSegmentsJSON = try? JSONEncoder().encode(segments(from: inBedStart, to: metrics.inBedEnd!))
            metrics.sleepSource = "com.example.tracker"

            let hrv = isToday ? 24.6 : 33 * exp(0.16 * sin(i * 1.3) + 0.05 * cos(i * 2.1))
            let samples = [0.92, 1.0, 1.08].enumerated().map { offset, factor in
                HRVSample(time: day.addingTimeInterval(Double(2 + offset * 2) * 3600), ms: hrv * factor)
            }
            metrics.hrvMetric = HRVMetric.id
            metrics.hrvSamplesJSON = try? JSONEncoder().encode(samples)
            metrics.hrvNightMeanMs = hrv
            metrics.hrvSource = "com.example.tracker"

            metrics.restingHR = isToday ? 61 : (58 + 2 * sin(i * 0.7)).rounded()
            metrics.restingHRSource = "com.example.tracker"
            return metrics
        }
    }

    /// Synthetic sleep cycles: deep sleep early in the night, longer REM phases towards the morning.
    static func segments(from start: Date, to end: Date) -> [SleepSegment] {
        var result: [SleepSegment] = []
        var time = start.addingTimeInterval(12 * 60)
        var cycle = 0
        while time < end.addingTimeInterval(-10 * 60) {
            let deep = max(40 - cycle * 10, 5)
            let rem = min(12 + cycle * 7, 38)
            let pattern: [(SleepStage, Int)] = [
                (.asleepCore, 22), (.asleepDeep, deep), (.asleepCore, 18), (.asleepREM, rem),
            ] + (cycle % 2 == 1 ? [(.awake, 4)] : [])
            for (stage, minutes) in pattern where time < end {
                let next = min(time.addingTimeInterval(Double(minutes) * 60), end)
                result.append(SleepSegment(start: time, end: next, stage: stage.rawValue))
                time = next
            }
            cycle += 1
        }
        return result
    }

    static func workouts(on now: Date, calendar: Calendar = .current) -> [HealthWorkout] {
        let day = LocalDay.start(of: now, calendar: calendar)
        let at: (Int, Int) -> Date = { hour, minute in
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        return [
            HealthWorkout(healthID: gymWorkoutID, day: day, start: at(12, 10), end: at(13, 15),
                          activityTypeRaw: 50, activityTypeName: "Krafttraining", sourceBundleID: "com.example.tracker"),
            HealthWorkout(healthID: UUID(), day: day, start: at(19, 0), end: at(19, 42),
                          activityTypeRaw: 3000, activityTypeName: "Andere", sourceBundleID: "com.example.tracker"),
            HealthWorkout(healthID: UUID(), day: day, start: at(19, 55), end: at(20, 35),
                          activityTypeRaw: 3000, activityTypeName: "Andere", sourceBundleID: "com.example.tracker"),
        ]
    }

    private static let gymWorkoutID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// The gym session already has an RPE; the handball session does not.
    static func sessions(on now: Date, calendar: Calendar = .current) -> [CompletedSession] {
        let gym = workouts(on: now, calendar: calendar)[0]
        let session = CompletedSession(day: gym.day, start: gym.start, end: gym.end, kind: .gym,
                                       durationMin: 65, workoutIDs: [gymWorkoutID])
        session.sessionRPE = 6
        return [session]
    }

    /// Morning check-ins with Zepp RMSSD for the last weeks; today's morning is complete.
    static func entries(endingAt now: Date, count: Int = 25, calendar: Calendar = .current) -> [QuestionnaireEntry] {
        LocalDay.window(endingAt: now, count: count, calendar: calendar).enumerated().map { index, day in
            let i = Double(index)
            let isToday = index == count - 1
            let entry = QuestionnaireEntry(day: day, phase: .morning, now: now)
            entry.save(answers: [
                "sleep_quality": .int(isToday ? 4 : 5),
                "energy": .int(isToday ? 4 : 5),
                "muscle_soreness": .int(5),
                "stress": .int(5),
                "training_motivation": .int(6),
                "illness": .int(0),
                "pain_knee_left_morning": .int(0),
                "pain_knee_right_morning": .int(isToday ? 2 : 1),
                "pain_shoulder_left_morning": .int(0),
                "pain_shoulder_right_morning": .int(0),
                "pain_back_morning": .int(0),
                "pain_elbow_morning": .int(0),
                "hrv_rmssd_zepp": .double(isToday ? 38 : (44 * exp(0.12 * sin(i * 1.1))).rounded()),
            ], note: nil, now: now)
            return entry
        }
    }
}
#endif
