import SwiftUI

/// Daily card. Placeholder until the Health Explorer has verified which data arrives.
struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Noch keine Tageskarte", systemImage: "heart.text.square")
            } description: {
                Text("Zuerst prüft der Health Explorer, welche Werte dein Tracker an Apple Health liefert.")
            } actions: {
                NavigationLink("Health Explorer öffnen") {
                    HealthExplorerView()
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HealthExplorerView()
                    } label: {
                        Label("Health Explorer", systemImage: "stethoscope")
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
