import SwiftUI

/// Row of tappable options. Tapping the selected option again clears it (unanswered stays `nil`).
struct OptionButtons: View {
    let options: [String]
    @Binding var selection: Int?
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(options.indices, id: \.self) { index in
                let selected = selection == index
                Button {
                    selection = selected ? nil : index
                } label: {
                    Text(options[index])
                        .font(compact ? .footnote.weight(.medium) : .subheadline.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: compact ? 32 : 38)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                                    in: .rect(cornerRadius: compact ? 8 : 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Renders one catalog question and edits its answer.
struct QuestionRow: View {
    let question: Question
    @Binding var answer: AnswerValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(question.title)
                    .font(.body.weight(.medium))
                Spacer()
                if question.optional {
                    Text("optional")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            control
            if let hint = question.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var control: some View {
        switch question.kind {
        case .scale(let range, let low, let high):
            OptionButtons(options: range.map(String.init), selection: indexBinding(offset: range.lowerBound))
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

        case .pain:
            OptionButtons(options: (0...10).map(String.init), selection: indexBinding(offset: 0), compact: true)
            HStack {
                Text("keine")
                Spacer()
                Text("stärkste vorstellbar")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

        case .choice(let options):
            OptionButtons(options: options, selection: indexBinding(offset: 0))

        case .yesNo:
            OptionButtons(options: ["Ja", "Nein"], selection: Binding(
                get: { answer?.boolValue.map { $0 ? 0 : 1 } },
                set: { answer = $0.map { .bool($0 == 0) } }
            ))

        case .number(let unit, let range):
            NumberField(unit: unit, range: range, answer: $answer)

        case .count(let unit, let range):
            CountControl(unit: unit, range: range, answer: $answer)

        case .time:
            TimeControl(answer: $answer)
        }
    }

    /// Maps stored integer values to option indices (scale 1–7 → index 0–6).
    private func indexBinding(offset: Int) -> Binding<Int?> {
        Binding(
            get: { answer?.intValue.map { $0 - offset } },
            set: { answer = $0.map { .int($0 + offset) } }
        )
    }
}

private struct NumberField: View {
    let unit: String
    let range: ClosedRange<Double>
    @Binding var answer: AnswerValue?
    @State private var text = ""

    var body: some View {
        HStack {
            TextField("–", text: $text)
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit())
            Text(unit)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            text = answer?.doubleValue.map { ExplorerFormat.number($0) } ?? ""
        }
        .onChange(of: text) { _, newValue in
            let normalized = newValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            if let value = Double(normalized), range.contains(value) {
                answer = .double(value)
            } else {
                answer = nil
            }
        }
        if !text.isEmpty, answer == nil {
            Text("Bitte einen Wert zwischen \(ExplorerFormat.number(range.lowerBound)) und \(ExplorerFormat.number(range.upperBound)) \(unit) eingeben.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

private struct CountControl: View {
    let unit: String
    let range: ClosedRange<Int>
    @Binding var answer: AnswerValue?

    var body: some View {
        HStack(spacing: 12) {
            if let value = answer?.intValue {
                stepButton("minus", enabled: value > range.lowerBound) { answer = .int(value - 1) }
                Text("\(value) \(unit)")
                    .font(.title3.monospacedDigit())
                    .frame(minWidth: 90)
                stepButton("plus", enabled: value < range.upperBound) { answer = .int(value + 1) }
                Spacer()
                Button("Zurücksetzen") { answer = nil }
                    .font(.caption)
            } else {
                Button("Keine") { answer = .int(range.lowerBound) }
                    .buttonStyle(.bordered)
                Button("1 oder mehr") { answer = .int(min(range.lowerBound + 1, range.upperBound)) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 36, height: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct TimeControl: View {
    @Binding var answer: AnswerValue?

    var body: some View {
        if let minutes = answer?.minutes {
            HStack {
                DatePicker("Uhrzeit", selection: Binding(
                    get: { Self.date(from: minutes) },
                    set: { answer = .time(Self.minutes(from: $0)) }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                Spacer()
                Button("Entfernen") { answer = nil }
                    .font(.caption)
            }
        } else {
            Button("Uhrzeit angeben") {
                let now = Self.minutes(from: .now)
                answer = .time(now - now % 15)
            }
            .buttonStyle(.bordered)
        }
    }

    private static func date(from minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
