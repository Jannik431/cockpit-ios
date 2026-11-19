import SwiftUI

/// Daily card. Placeholder until the Health Explorer has verified which data arrives.
struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Noch keine Daten",
                systemImage: "heart.text.square",
                description: Text("Als Nächstes kommt der Health Explorer. Er zeigt, welche Werte dein Tracker an Apple Health liefert.")
            )
            .navigationTitle("Heute")
        }
    }
}

#Preview {
    DashboardView()
}
