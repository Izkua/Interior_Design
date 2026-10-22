import SwiftUI

/// Placeholder for recommended layouts. The layout engine arrives in a
/// later week.
struct RecommendedLayoutsView: View {
    var body: some View {
        EmptyState(
            systemImage: "square.split.2x2",
            title: "Layouts will appear here",
            message: "Add your room and your items, and you'll see different ways to arrange them."
        )
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Recommended Layouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }
    }
}
