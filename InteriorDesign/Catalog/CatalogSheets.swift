import SwiftUI
import SwiftData

// MARK: - Filters

/// Price range, rating, kind of item, material, style, and color.
struct CatalogFiltersSheet: View {
    @Binding var query: CatalogQuery
    @Environment(\.dismiss) private var dismiss

    @State private var draft = CatalogQuery()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                            SectionHeader(title: "What kind")
                            FlowLayout(spacing: Theme.Space.sm) {
                                Chip(title: "Anything", isSelected: draft.type == nil) { draft.type = nil }
                                ForEach(ItemType.allCases.filter { $0 != .other }) { type in
                                    Chip(title: type.displayName, systemImage: type.symbol, isSelected: draft.type == type) {
                                        draft.type = type
                                    }
                                }
                            }
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                            SectionHeader(title: "Price")
                            HStack(spacing: Theme.Space.sm) {
                                MoneyField(title: "From", value: $draft.minPrice)
                                MoneyField(title: "Up to", value: $draft.maxPrice)
                            }
                            SectionHeader(title: "Minimum rating")
                            Picker("Minimum rating", selection: $draft.minRating) {
                                ForEach(RatingOption.all, id: \.self) { Text(RatingOption.title($0)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    chipCard("Material", options: MaterialOption.all, selection: $draft.materials)
                    chipCard("Style", options: StyleOption.all, selection: $draft.styles)
                    chipCard("Color", options: ColorOption.all, selection: $draft.colors)
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { draft = CatalogQuery(text: query.text) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Show results") {
                        query = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { draft = query }
        .presentationDragIndicator(.visible)
    }

    private func chipCard(_ title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
                SectionHeader(title: title)
                FlowLayout(spacing: Theme.Space.sm) {
                    ForEach(options, id: \.self) { option in
                        Chip(title: option, isSelected: selection.wrappedValue.contains(option)) {
                            if selection.wrappedValue.contains(option) {
                                selection.wrappedValue.remove(option)
                            } else {
                                selection.wrappedValue.insert(option)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A currency text field for an optional amount.
struct MoneyField: View {
    let title: String
    @Binding var value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField("Any", value: $value, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
                .keyboardType(.decimalPad)
                .font(Typography.headline)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
    }
}

// MARK: - Budget

/// The total budget for a room and optional caps per kind of item.
struct BudgetSheet: View {
    @Bindable var room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var total: Double?
    @State private var caps: [ItemType: Double] = [:]

    private let types: [ItemType] = [.sofa, .bed, .table, .chair, .desk, .dresser, .shelf, .tvStand, .lamp, .rug]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            MoneyField(title: "Total budget for \(room.name)", value: $total)
                            Text("Products over the money left are hidden.")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    AppCard {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            SectionHeader(title: "Most per item (optional)")
                            ForEach(types) { type in
                                HStack {
                                    Label(type.displayName, systemImage: type.symbol)
                                        .font(Typography.subheadline)
                                    Spacer()
                                    MoneyField(title: "", value: Binding(get: { caps[type] }, set: { caps[type] = $0 }))
                                        .frame(width: 140)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save", action: save).fontWeight(.semibold) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
        .onAppear {
            total = room.preferences?.totalBudget
            for cap in room.preferences?.perItemBudgets ?? [] { caps[cap.type] = cap.amount }
        }
    }

    private func save() {
        hideKeyboard()
        let prefs = room.preferences ?? {
            let new = Preferences()
            context.insert(new)
            room.preferences = new
            return new
        }()
        prefs.totalBudget = total.flatMap { $0 > 0 ? $0 : nil }
        prefs.perItemBudgets = types.compactMap { type in
            caps[type].flatMap { $0 > 0 ? ItemBudget(type: type, amount: $0) : nil }
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Wishlist

struct WishlistView: View {
    let room: Room?

    @Environment(\.modelContext) private var context
    @Query(sort: \Product.fetchedAt, order: .reverse) private var products: [Product]

    @AppStorage(SettingsKey.unitSystem) private var unitRaw = UnitSystem.deviceDefault.rawValue

    var body: some View {
        Group {
            if products.isEmpty {
                EmptyState(
                    systemImage: "heart",
                    title: "Nothing saved yet",
                    message: "Tap the heart on a product to keep it here."
                )
            } else {
                List {
                    Section {
                        ForEach(products) { saved in
                            let product = saved.catalogProduct
                            NavigationLink {
                                ProductDetailView(product: product, fit: nil, room: room)
                            } label: {
                                HStack(spacing: Theme.Space.sm + 4) {
                                    ProductImage(product: product)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.name).font(Typography.subheadline).lineLimit(2)
                                        Text(money(product.price, currency: product.currency))
                                            .font(Typography.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(products[index]) }
                            try? context.save()
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text("Total \(money(products.map(\.price).reduce(0, +)))")
                                .font(Typography.headline)
                            AffiliateDisclosure()
                        }
                        .padding(.top, Theme.Space.sm)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
    }

}
