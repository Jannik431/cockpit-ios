import SwiftUI

/// Visual language of the daily card.
/// Deviations are coloured by their likely effect (`Impact`): green, yellow, orange.
enum Theme {
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 14
}

extension BaselineMetric {
    var systemImage: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .hrv: "waveform.path.ecg"
        case .restingHR: "heart.fill"
        }
    }

    var accent: Color {
        switch self {
        case .sleep: .indigo
        case .hrv: .teal
        case .restingHR: .pink
        }
    }

    /// Short title for the tile header (the full HRV title is too long there).
    var shortTitle: String {
        switch self {
        case .sleep: "Schlaf"
        case .hrv: "HRV"
        case .restingHR: "Ruhepuls"
        }
    }
}

extension Impact {
    var tint: Color {
        switch self {
        case .good: .green
        case .caution: .yellow
        case .warning: .orange
        case .unknown: .gray
        }
    }
}

extension SleepStage {
    /// Row in the hypnogram: awake on top, deep at the bottom.
    var level: Int {
        switch self {
        case .awake: 3
        case .asleepREM: 2
        case .asleepCore, .asleepUnspecified: 1
        case .asleepDeep: 0
        case .inBed: -1
        }
    }

    var color: Color {
        switch self {
        case .awake: Color(red: 1.0, green: 0.48, blue: 0.40)
        case .asleepREM: Color(red: 0.35, green: 0.78, blue: 0.98)
        case .asleepCore: Color(red: 0.22, green: 0.47, blue: 0.96)
        case .asleepUnspecified: Color(red: 0.40, green: 0.55, blue: 0.85)
        case .asleepDeep: Color(red: 0.37, green: 0.24, blue: 0.75)
        case .inBed: .gray
        }
    }

    var shortTitle: String {
        switch self {
        case .awake: "Wach"
        case .asleepREM: "REM"
        case .asleepCore: "Kern"
        case .asleepUnspecified: "Schlaf"
        case .asleepDeep: "Tief"
        case .inBed: "Im Bett"
        }
    }
}

extension DeviationBand {
    var shortTitle: String {
        switch self {
        case .withinNorm: "Normbereich"
        case .slightlyBelow: "leicht darunter"
        case .slightlyAbove: "leicht darüber"
        case .clearlyBelow: "deutlich darunter"
        case .clearlyAbove: "deutlich darüber"
        case .undetermined: "keine Streuung"
        }
    }
}

extension SessionKind {
    var systemImage: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .handball: "figure.handball"
        case .other: "figure.mixed.cardio"
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: .rect(cornerRadius: Theme.cardRadius))
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }
}

/// Small capsule with a coloured dot, e.g. "● Normbereich".
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.16), in: .capsule)
    }
}
