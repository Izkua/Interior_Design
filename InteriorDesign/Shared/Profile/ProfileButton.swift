import SwiftUI

/// The profile button that sits at the top right of every main screen.
/// Tapping it opens the profile sheet. Put it in a toolbar:
///
///     .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
struct ProfileButton: View {
    @State private var showProfile = false

    var body: some View {
        ToolbarIconButton(systemName: "person.crop.circle", label: "Profile") {
            showProfile = true
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
        }
    }
}
