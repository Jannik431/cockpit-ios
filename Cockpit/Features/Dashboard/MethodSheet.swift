import SwiftUI

/// Explains how the norm and the bands are computed (spec: thresholds must be transparent).
struct MethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Deine Norm") {
                    Text("Median der \(BaselineCalculator.normWindowDays) Tage *vor* heute. Der heutige Wert zählt nicht mit. Eine Norm gibt es ab \(BaselineCalculator.minimumNormValues) Tagen mit Wert.")
                    Text("Das farbige Band in der 10-Tage-Grafik zeigt den Normbereich, die gestrichelte Linie den Median. Jeder Punkt ist gegen die Norm seines eigenen Tages eingeordnet.")
                }

                Section("Abweichung") {
                    Text("Robuster z-Wert: (Wert − Median) / (1,4826 × MAD). MAD ist die mittlere absolute Abweichung vom Median, einzelne Ausreißer verschieben sie kaum.")
                    Text("HRV wird logarithmiert verglichen, weil sie sich eher prozentual verändert.")
                    Text("„7 Tage“ ist der Median der letzten \(BaselineCalculator.shortWindowDays) Tage inklusive heute im Vergleich zur Norm.")
                }

                Section {
                    LabeledContent("im Normbereich", value: "|z| < 1")
                    LabeledContent("leicht darüber/darunter", value: "1 ≤ |z| < 2")
                    LabeledContent("deutlich darüber/darunter", value: "|z| ≥ 2")
                } header: {
                    Text("Einordnung")
                }

                Section {
                    bandRow("im Normbereich oder günstige Richtung", tint: Impact.good.tint)
                    bandRow("leicht ungünstig", tint: Impact.caution.tint)
                    bandRow("deutlich ungünstig", tint: Impact.warning.tint)
                } header: {
                    Text("Farben")
                } footer: {
                    Text("Als günstig gilt: mehr Schlaf, höhere HRV, niedrigerer Ruhepuls. Das ist eine Faustregel zur Orientierung, keine Bewertung deiner Gesundheit.")
                }

                Section {
                    Text("Fehlende Tage bleiben Lücken und werden nicht aufgefüllt.")
                    Text("Cockpit trifft keine medizinischen Aussagen. Bei starken oder anhaltenden Beschwerden: Arzt oder Physio, nicht die App.")
                }
            }
            .navigationTitle("So wird verglichen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bandRow(_ text: String, tint: Color) -> some View {
        StatusChip(text: text, tint: tint)
    }
}
