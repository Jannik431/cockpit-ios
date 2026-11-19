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
        let now = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now)!
        let view = DailyCardContent(
            now: now,
            days: PreviewData.days(endingAt: now),
            workouts: PreviewData.workouts(on: now),
            syncState: .idle,
            lastSync: Calendar.current.date(bySettingHour: 7, minute: 42, second: 0, of: now)
        )
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(width: 393)
        .background(Theme.screenBackground)
        .environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "de_DE"))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let data = try #require(renderer.uiImage?.pngData())
        let url = URL(fileURLWithPath: Self.directory!).appendingPathComponent("daily-card-\(scheme == .dark ? "dark" : "light").png")
        try data.write(to: url)
    }
}
