import SwiftUI

/// Picks an item type in two steps: the kind (Furniture, Wall decor, Small
/// decor) and then the type, so the list of chips stays short.
struct ItemTypePicker: View {
    @Binding var selection: ItemType?
    /// Adds an "Anything" chip (for search filters) that clears the choice.
    var allowsAny = false
    /// Hides "Other", which means nothing as a search filter.
    var hidesOther = false
    var onPick: (ItemType) -> Void = { _ in }

    @State private var category: ItemCategory

    init(selection: Binding<ItemType?>, allowsAny: Bool = false, hidesOther: Bool = false, onPick: @escaping (ItemType) -> Void = { _ in }) {
        _selection = selection
        self.allowsAny = allowsAny
        self.hidesOther = hidesOther
        self.onPick = onPick
        _category = State(initialValue: selection.wrappedValue?.category ?? .furniture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm + 4) {
            Picker("Kind", selection: $category) {
                ForEach(ItemCategory.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            FlowLayout(spacing: Theme.Space.sm) {
                if allowsAny {
                    Chip(title: "Any \(category.title.lowercased())", isSelected: selection == nil) { selection = nil }
                }
                ForEach(category.types.filter { !(hidesOther && $0 == .other) }) { type in
                    Chip(title: type.displayName, systemImage: type.symbol, isSelected: selection == type) {
                        selection = type
                        onPick(type)
                    }
                }
            }
        }
        .onChange(of: selection) { _, new in
            if let new, new.category != category { category = new.category }
        }
        // Switching the kind picks its first type right away, so the
        // change is saved even if no chip is tapped after.
        .onChange(of: category) { _, kind in
            guard !allowsAny, selection?.category != kind, let first = kind.types.first else { return }
            selection = first
            onPick(first)
        }
    }
}

/// A row of chips: All, Furniture, Wall decor, Small decor. Used to filter
/// Current Items and the Catalog.
struct CategoryFilterRow: View {
    @Binding var selection: ItemCategory?
    /// Adds side padding for rows that scroll edge to edge.
    var padded = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                Chip(title: "All types", isSelected: selection == nil) { selection = nil }
                ForEach(ItemCategory.allCases) { category in
                    Chip(title: category.title, systemImage: category.symbol, isSelected: selection == category) {
                        selection = category
                    }
                }
            }
            .padding(.horizontal, padded ? Theme.Space.md : 0)
        }
        .accessibilityLabel("Show which kind of items")
    }
}
