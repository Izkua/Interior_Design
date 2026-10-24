import SwiftUI

/// Three short screens on first launch: what the app does, then the two
/// things to do first. Skippable; shown once.
struct OnboardingView: View {
    /// Where to go when onboarding ends.
    enum Next { case drawRoom, addItem, explore }

    let onFinish: (Next) -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page {
        var symbol: String
        var title: String
        var body: String
    }

    private let pages = [
        Page(symbol: "sofa",
             title: "Plan your room before you move a thing",
             body: "Draw your room, add the furniture you own, and see layouts that keep doors and walkways clear. Then shop for what's missing, within your budget."),
        Page(symbol: "square.dashed",
             title: "First, your room",
             body: "Type its width and length, or tap in each corner for L-shapes and angled walls. Add the doors, windows, and outlets. A tape measure helps."),
        Page(symbol: "ruler",
             title: "Then, your furniture",
             body: "Add each piece with its size, or take a photo and we'll guess the type and size for you to check. Everything stays on your phone; no account needed."),
    ]

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            HStack {
                Spacer()
                Button("Skip") { onFinish(.explore) }
                    .font(Typography.subheadline)
                    .frame(minWidth: Theme.minTap, minHeight: Theme.minTap)
                    .opacity(page < pages.count - 1 ? 1 : 0)
                    .accessibilityHidden(page == pages.count - 1)
            }

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page < pages.count - 1 {
                PrimaryButton(title: "Next") {
                    if reduceMotion { page += 1 } else { withAnimation { page += 1 } }
                }
            } else {
                VStack(spacing: Theme.Space.sm) {
                    PrimaryButton(title: "Draw my room", systemImage: "square.dashed") { onFinish(.drawRoom) }
                    PrimaryButton(title: "Add my furniture", systemImage: "plus", style: .tinted) { onFinish(.addItem) }
                    Button("Just look around") { onFinish(.explore) }
                        .font(Typography.subheadline)
                        .frame(minHeight: Theme.minTap)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.background.ignoresSafeArea())
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                Image(systemName: page.symbol)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 112, height: 112)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(page.body)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Space.xl)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.bottom, 48)   // room for the page dots
        }
    }
}
