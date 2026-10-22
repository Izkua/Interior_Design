import SwiftUI

/// Placeholder for the shopping tab. The real catalog arrives in a later week.
struct CatalogView: View {
    var body: some View {
        NavigationStack {
            EmptyState(
                systemImage: "bag",
                title: "Shopping is on its way",
                message: "Soon you'll set a budget and find pieces that fit your room."
            )
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Catalog")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
        }
    }
}
