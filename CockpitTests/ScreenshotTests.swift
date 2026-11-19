import SwiftUI
import Testing
@testable import Cockpit

/// Renders the daily card with synthetic data to PNG files, e.g. for the README.
/// Only runs when a target directory is given:
/// `TEST_RUNNER_SCREENSHOT_DIR=/path xcodebuild test ...`
@MainActor
struct ScreenshotTests {
    nonisolated private static let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]

    @Test(.enabled(if: directory != nil), arguments: [ColorScheme.light, .dark])
    func dailyCard(scheme: ColorScheme) throws {
        let now = Calendar.current.date(bySettingHour: 21, minute: 15, second: 0, of: .now)!
        let view = DailyCardContent(
            now: now,
            days: PreviewData.days(endingAt: now),
            workouts: PreviewData.workouts(on: now),
            entries: PreviewData.entries(endingAt: now),
            sessions: PreviewData.sessions(on: now),
            syncState: .idle,
            lastSync: Calendar.current.date(bySettingHour: 7, minute: 42, second: 0, of: now)
        )
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(width: 393)
        .background(Theme.screenBackground)
        .environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "de_DE"))

        try render(view, name: "daily-card-\(scheme == .dark ? "dark" : "light")")
    }

    /// Answer controls of the morning check (the real sheet is a Form, which ImageRenderer cannot draw).
    @Test(.enabled(if: directory != nil))
    func morningCheckControls() throws {
        let answers: [String: AnswerValue] = [
            "sleep_quality": .int(5), "energy": .int(4), "illness": .int(0),
            "pain_knee_morning": .int(2), "hrv_rmssd_zepp": .double(42),
        ]
        let questions = QuestionCatalog.questions(for: .morning).filter {
            ["sleep_quality", "energy", "illness", "pain_knee_morning", "hrv_rmssd_zepp"].contains($0.id)
        }
        let view = VStack(spacing: 12) {
            ForEach(questions) { question in
                QuestionRow(question: question, answer: .constant(answers[question.id]))
                    .card()
            }
        }
        .padding()
        .frame(width: 393)
        .background(Theme.screenBackground)
        .environment(\.locale, Locale(identifier: "de_DE"))

        try render(view, name: "check-in-controls")
    }

    private func render(_ view: some View, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: Self.directory!).appendingPathComponent("\(name).png"))
    }
}
