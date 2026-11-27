import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Link the export file once; afterwards the app keeps it up to date.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @State private var service = ExportService.shared
    @State private var picking = false
    @State private var shareURL: URL?
    @State private var preview = ""

    var body: some View {
        List {
            Section {
                if let name = service.linkedFileName {
                    LabeledContent("Verknüpfte Datei", value: name)
                    if let last = service.lastExport {
                        LabeledContent("Zuletzt geschrieben", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Jetzt aktualisieren", systemImage: "arrow.triangle.2.circlepath") {
                        service.exportIfLinked(context: context)
                        refreshPreview()
                    }
                    Button("Andere Datei verknüpfen", systemImage: "link") { picking = true }
                    Button("Verknüpfung lösen", systemImage: "link.badge.plus", role: .destructive) { service.unlink() }
                } else {
                    Button("Datei verknüpfen …", systemImage: "link") { picking = true }
                }
                if let error = service.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            } header: {
                Text("Automatischer Export")
            } footer: {
                Text("Die App überschreibt die verknüpfte Datei nach jedem gespeicherten Check-in, jeder erfassten Einheit und beim Öffnen. Sie enthält immer alle Tage.")
            }

            Section("Einrichten (einmalig)") {
                Label("Unten „Datei teilen“ → „In Dateien sichern“ → Google Drive → Ordner „Trainingsplanung“.", systemImage: "1.circle")
                Label("Oben „Datei verknüpfen“ und genau diese Datei auswählen.", systemImage: "2.circle")
                Label("Prüfen: In Google Drive muss sich die Datei nach „Jetzt aktualisieren“ ändern.", systemImage: "3.circle")
            }
            .font(.subheadline)

            Section {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Datei teilen …", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Von Hand")
            } footer: {
                Text("Exportdateien enthalten Gesundheitsdaten. Nur bewusst teilen.")
            }

            Section("Vorschau") {
                Text(preview.isEmpty ? "–" : preview)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Regeln") {
                Text("Leer = nicht erfasst, nie 0. Dezimalpunkt, Datum JJJJ-MM-TT, eine Zeile pro Tag.")
                Text("schlaf_h ist die Nacht, die am Morgen dieses Tages endet. hrv_rmssd_ms kommt nur aus dem Zepp-Feld (RMSSD), nie aus Apple Health.")
                Text("knie_belastung = höchster Wert der Einheiten des Tages. handball_belastung aus dem RPE: bis 4 leicht, 5–6 mittel, ab 7 hart. trainingslast_au = Summe RPE × Minuten der Einheiten mit RPE.")
                Text("krank = 1 schon bei leichten Anzeichen. kaffee = 0/1, die Uhrzeit nur bei 1.")
                Text("einheit_n/minuten_n/rpe_n = Einheiten des Tages nach Startzeit (ab der 4. Einheit hinten angehängt). muskelkater = 0–6, höher = stärker. fieber aus den Symptomen. kaffee_tassen = alle Koffein-Getränke.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Export")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            if case .success(let url) = result {
                service.link(url)
                service.exportIfLinked(context: context)
                refreshPreview()
            }
        }
        .onAppear(perform: refreshPreview)
    }

    private func refreshPreview() {
        let csv = service.csv(context: context)
        let lines = csv.split(separator: "\n")
        preview = ([lines.first].compactMap { $0 } + lines.suffix(3)).joined(separator: "\n")
        shareURL = try? service.temporaryFile(context: context)
    }
}
