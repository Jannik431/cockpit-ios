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

/// Grid for single choice with many short options, e.g. plan units. Tapping the selected option clears it.
struct ChoiceGrid: View {
    let options: [String]
    @Binding var selection: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let selected = selection == index
                Button {
                    selection = selected ? nil : index
                } label: {
                    Text(options[index])
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                                    in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Grid of toggles for multiple choice.
struct MultiChoiceButtons: View {
    let options: [String]
    @Binding var selection: Set<Int>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let selected = selection.contains(index)
                Button {
                    if selected { selection.remove(index) } else { selection.insert(index) }
                } label: {
                    Label(options[index], systemImage: selected ? "checkmark" : "plus")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                                    in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Integer scale as a slider: drag the thumb or tap anywhere on the track.
/// While unanswered (`nil`) the slider is dimmed, so nothing is stored by accident.
struct ScaleSlider: View {
    let range: ClosedRange<Int>
    @Binding var value: Int?
    let low: String
    let high: String

    /// UISlider keeps the thumb centre this far from the track ends.
    private let thumbInset: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    Slider(
                        value: Binding(
                            get: { Double(value ?? range.lowerBound) },
                            set: { value = Int($0.rounded()) }
                        ),
                        in: Double(range.lowerBound)...Double(range.upperBound),
                        step: 1
                    ) { editing in
                        if editing, value == nil { value = range.lowerBound }
                    }
                    .opacity(value == nil ? 0.35 : 1)
                    .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                        value = step(at: tap.location.x, width: width)
                    })

                    ForEach(Array(range), id: \.self) { step in
                        Text("\(step)")
                            .font(.caption2.weight(step == value ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(step == value ? Color.primary : Color.secondary)
                            .position(x: position(of: step, width: width), y: 42)
                            .onTapGesture { value = step }
                    }
                }
            }
            .frame(height: 52)

            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("\(low) bis \(high)")
        .accessibilityValue(value.map(String.init) ?? "nicht angegeben")
        .accessibilityAdjustableAction { direction in
            let current = value ?? range.lowerBound - 1
            switch direction {
            case .increment: value = min(current + 1, range.upperBound)
            case .decrement: value = max(current - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func position(of step: Int, width: CGFloat) -> CGFloat {
        let fraction = CGFloat(step - range.lowerBound) / CGFloat(max(range.count - 1, 1))
        return thumbInset + fraction * (width - 2 * thumbInset)
    }

    private func step(at x: CGFloat, width: CGFloat) -> Int {
        let fraction = min(max((x - thumbInset) / max(width - 2 * thumbInset, 1), 0), 1)
        return range.lowerBound + Int((fraction * CGFloat(range.count - 1)).rounded())
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
                if let valueText {
                    Text(valueText)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                } else if question.optional {
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

    /// Current value next to the title for slider questions.
    private var valueText: String? {
        guard let value = answer?.intValue else { return nil }
        switch question.kind {
        case .scale: return "\(value)"
        case .pain: return "\(value) · \(QuestionCatalog.painLabel(value))"
        default: return nil
        }
    }

    @ViewBuilder
    private var control: some View {
        switch question.kind {
        case .scale(let range, let low, let high):
            ScaleSlider(range: range, value: intBinding, low: low, high: high)

        case .pain:
            ScaleSlider(range: 0...10, value: intBinding, low: "keine", high: "stärkste vorstellbar")

        case .choice(let options):
            OptionButtons(options: options, selection: intBinding)

        case .multiChoice(let options):
            MultiChoiceButtons(options: options, selection: Binding(
                get: { Set(answer?.listValue ?? []) },
                set: { answer = $0.isEmpty ? nil : .list($0.sorted()) }
            ))

        case .yesNo:
            OptionButtons(options: ["Ja", "Nein"], selection: Binding(
                get: { answer?.boolValue.map { $0 ? 0 : 1 } },
                set: { answer = $0.map { .bool($0 == 0) } }
            ))

        case .number(let unit, let range):
            NumberField(unit: unit, range: range, answer: $answer)

        case .count(let one, let many, let range, let noneLabel, let someLabel):
            CountControl(one: one, many: many, range: range, noneLabel: noneLabel, someLabel: someLabel, answer: $answer)

        case .time:
            TimeMenu(answer: $answer)
        }
    }

    private var intBinding: Binding<Int?> {
        Binding(get: { answer?.intValue }, set: { answer = $0.map { .int($0) } })
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

/// "Kein Alkohol" / "Alkohol getrunken", then the number (from 1 up).
private struct CountControl: View {
    let one: String
    let many: String
    let range: ClosedRange<Int>
    let noneLabel: String
    let someLabel: String
    @Binding var answer: AnswerValue?

    var body: some View {
        OptionButtons(options: [noneLabel, someLabel], selection: Binding(
            get: { answer?.intValue.map { $0 == range.lowerBound ? 0 : 1 } },
            set: { choice in
                switch choice {
                case 0: answer = .int(range.lowerBound)
                case 1: answer = .int(max(answer?.intValue ?? 0, range.lowerBound + 1))
                default: answer = nil
                }
            }
        ))

        if let value = answer?.intValue, value > range.lowerBound {
            HStack(spacing: 16) {
                stepButton("minus", enabled: value > range.lowerBound + 1) { answer = .int(value - 1) }
                Text("\(value) \(value == 1 ? one : many)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                stepButton("plus", enabled: value < range.upperBound) { answer = .int(value + 1) }
            }
            .padding(.top, 4)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .tertiarySystemFill), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// One tap opens the list of times (30-minute steps), one tap picks.
private struct TimeMenu: View {
    @Binding var answer: AnswerValue?

    private static let slots = Array(stride(from: 5 * 60, through: 23 * 60 + 30, by: 30))

    var body: some View {
        HStack {
            Picker("Uhrzeit", selection: Binding(
                get: { answer?.minutes },
                set: { answer = $0.map { .time($0) } }
            )) {
                Text("Uhrzeit wählen").tag(Int?.none)
                ForEach(Self.slots, id: \.self) { minutes in
                    Text(String(format: "%02d:%02d Uhr", minutes / 60, minutes % 60)).tag(Int?.some(minutes))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
    }
}
