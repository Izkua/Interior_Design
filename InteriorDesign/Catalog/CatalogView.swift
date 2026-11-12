import SwiftUI
import SwiftData

/// The shopping tab: set a budget, fill the gaps in a room, and search for
/// pieces that fit.
struct CatalogView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Room.updatedAt, order: .reverse) private var rooms: [Room]
    @Query(sort: \Product.fetchedAt, order: .reverse) private var wishlist: [Product]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue
    @AppStorage(SettingsKey.defaultBudget) private var defaultBudget: Double?
    @AppStorage(SettingsKey.preferredStyles) private var stylesCSV = ""
    @AppStorage(SettingsKey.preferredMaterials) private var materialsCSV = ""
    @AppStorage(SettingsKey.minimumRating) private var minimumRating: Double = 0
    @AppStorage(SettingsKey.matchRoomColors) private var matchRoomColors = true
    /// The room's colors and mood, worked out from its items' photos.
    @State private var vibe: RoomVibe?
    /// The Recommended section is closed until tapped.
    @State private var showRecommended = false

    @State private var store = CatalogStore()
    @State private var query = CatalogQuery()
    @State private var searchText = ""
    @State private var selectedRoomID: UUID?
    @State private var showFilters = false
    @State private var showBudget = false
    /// The screen pushed from the top bar. One destination for both: two
    /// separate ones on the same screen made SwiftUI rebuild them in a
    /// loop and froze the app.
    enum Route: Hashable { case wishlist, models }
    @State private var route: Route?

    private var unit: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .imperial }

    private var room: Room? { rooms.first { $0.uuid == selectedRoomID } ?? rooms.first }

    private var budget: ShoppingBudget {
        let prefs = room?.preferences
        var perItem: [ItemType: Double] = [:]
        for cap in prefs?.perItemBudgets ?? [] { perItem[cap.type] = cap.amount }
        return ShoppingBudget(
            total: prefs?.totalBudget ?? defaultBudget,
            perItem: perItem,
            committed: wishlist.map(\.price).reduce(0, +)
        )
    }

    private var preferences: ShoppingPreferences {
        func set(_ csv: String) -> Set<String> { Set(csv.split(separator: ",").map(String.init)) }
        return ShoppingPreferences(styles: set(stylesCSV), materials: set(materialsCSV), minRating: minimumRating,
                                   vibe: matchRoomColors ? vibe : nil)
    }

    private var snapshot: CatalogStore.RoomSnapshot? {
        room.map { CatalogStore.RoomSnapshot(room: $0.layoutRoom, items: $0.layoutItems, hasChosenLayout: $0.chosenLayout != nil, decor: $0.decorSpace) }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    budgetCard

                    if store.source == .curated {
                        Label("Showing sample products. The live catalog isn't connected yet.", systemImage: "info.circle")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let vibe {
                        vibeCard(vibe)
                    }

                    if !store.gaps.isEmpty {
                        recommendedSection
                    }

                    searchBar

                    CategoryFilterRow(selection: Binding(
                        get: { query.category },
                        set: { category in
                            query.category = category
                            if let type = query.type, type.category != category { query.type = nil }
                        }
                    ), padded: false)

                    if store.isLoading && store.results.isEmpty {
                        // Grey placeholder cards while searching.
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                ProductCard(product: .placeholder, fit: nil, unit: unit)
                            }
                        }
                        .redacted(reason: .placeholder)
                        .accessibilityLabel("Loading products")
                    } else if store.results.isEmpty {
                        Text("Nothing matches. Try fewer filters or a bigger budget.")
                            .font(Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        if let note = store.fitNote {
                            Text(note)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.results) { product in
                                NavigationLink {
                                    ProductDetailView(product: product, fit: store.fit[product.id], room: room)
                                } label: {
                                    ProductCard(product: product, fit: store.fit[product.id], unit: unit)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    AffiliateDisclosure()
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Catalog")
            .toolbar {
                // Left to right: 3D models, wishlist, profile (profile stays far right).
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ToolbarIconButton(systemName: SavedModels.shared.entries.isEmpty ? "cube" : "cube.fill", label: "Saved 3D models") {
                        route = .models
                    }
                    ToolbarIconButton(systemName: wishlist.isEmpty ? "heart" : "heart.fill", label: "Wishlist") {
                        route = .wishlist
                    }
                    ProfileButton()
                }
            }
            .sheet(isPresented: $showFilters) { CatalogFiltersSheet(query: $query) }
            .sheet(isPresented: $showBudget) {
                if let room { BudgetSheet(room: room) }
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .wishlist: WishlistView(room: room)
                case .models: SavedModelsView()
                }
            }
            .task(id: searchKey) {
                await store.search(query, budget: budget, preferences: preferences, room: snapshot)
            }
            .task(id: gapsKey) {
                guard let room else { store.gaps = []; return }
                let decor = Set(room.items(in: .wallDecor).map(\.type) + room.items(in: .smallDecor).map(\.type)
                                + room.wallDecor.map { $0.kind.itemType })
                await store.fillGaps(MissingPieces.suggest(for: room.layoutItems, decor: decor), budget: budget, preferences: preferences, room: snapshot)
            }
            .task(id: room?.decorSignature ?? "") {
                vibe = room?.vibe()
                try? context.save()
            }
        }
    }

    /// Re-search when any of these change.
    private var searchKey: String {
        "\(query.hashValue)|\(budget.total ?? -1)|\(budget.committed)|\(room?.decorSignature ?? "")|\(stylesCSV)|\(materialsCSV)|\(matchRoomColors)|\(vibe?.title ?? "")"
    }

    private var gapsKey: String {
        "\(room?.decorSignature ?? "")|\(budget.total ?? -1)|\(budget.committed)|\(matchRoomColors)|\(vibe?.title ?? "")"
    }

    // MARK: Budget

    private var budgetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    if rooms.count > 1, let room {
                        Menu {
                            ForEach(rooms) { option in
                                Button(option.name) { selectedRoomID = option.uuid }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(room.name)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                        }
                    } else {
                        Text(room?.name ?? "Shopping")
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Button("Edit budget") { showBudget = true }
                        .font(Typography.subheadline)
                        .frame(minHeight: Theme.minTap)
                        .disabled(room == nil)
                }
                if let total = budget.total {
                    Text("\(money(budget.remaining ?? 0)) left of \(money(total))")
                        .font(Typography.title)
                        .foregroundStyle(Theme.textPrimary)
                    if budget.committed > 0 {
                        Text("\(money(budget.committed)) is on your wishlist.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("Set a budget to see only what you can afford.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Room colors

    /// The room's mood and main colors, and a switch to rank by them.
    private func vibeCard(_ vibe: RoomVibe) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(room?.name ?? "Your room")'s vibe")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(vibe.title)
                            .font(Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    HStack(spacing: -6) {
                        ForEach(Array(vibe.swatches.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(Color(uiColor: color.uiColor))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                        }
                    }
                    .accessibilityHidden(true)
                }
                Toggle("Match my room's colors", isOn: $matchRoomColors)
                    .font(Typography.subheadline)
                    .tint(Theme.accent)
                Text("From the photos of your items: mostly \(vibe.colorNames.prefix(3).map { $0.lowercased() }.formatted(.list(type: .and))). Worked out on your phone.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Fill the gaps

    /// "Recommended": tap to open the suggestions (fill the gaps), tap
    /// again to close them. Stays on this page.
    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                withAnimation(.snappy) { showRecommended.toggle() }
            } label: {
                HStack {
                    Label("Recommended", systemImage: "sparkles")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(store.gaps.count)")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.surfaceAlt, in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(showRecommended ? 180 : 0))
                }
                .frame(minHeight: Theme.minTap)
                .padding(.horizontal, Theme.Space.md)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showRecommended ? "Hides the suggestions" : "Shows suggestions for this room")

            if showRecommended {
                gapsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var gapsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Fill the gaps")
            ForEach(store.gaps) { gap in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(gap.piece.name) · \(gap.piece.reason)")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if gap.products.isEmpty {
                        Text("Nothing in the catalog fits here within budget yet.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, 4)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(gap.products) { product in
                                    NavigationLink {
                                        ProductDetailView(product: product, fit: store.fit[product.id], room: room)
                                    } label: {
                                        ProductCard(product: product, fit: store.fit[product.id], unit: unit)
                                            .frame(width: 170)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search, like \"oak coffee table\"", text: $searchText)
                    .submitLabel(.search)
                    .onSubmit { query.text = searchText }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            IconButton(systemName: activeFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle", label: "Filters") {
                showFilters = true
            }
        }
    }

    private var activeFilters: Bool {
        query.type != nil || query.category != nil || query.minPrice != nil || query.maxPrice != nil || query.minRating > 0
            || !query.materials.isEmpty || !query.styles.isEmpty || !query.colors.isEmpty
    }
}

/// Shown near every shopping link, as the affiliate programs and the App
/// Store expect.
struct AffiliateDisclosure: View {
    var body: some View {
        Label("We may earn a commission when you buy through links in the app. It doesn't change the price you pay.", systemImage: "info.circle")
            .font(Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func money(_ amount: Double, currency: String = Locale.current.currency?.identifier ?? "USD") -> String {
    amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
}
