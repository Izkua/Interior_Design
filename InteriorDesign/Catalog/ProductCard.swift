import SwiftUI

/// One product in the grid: picture, price, rating, size, and whether it
/// fits the room.
struct ProductCard: View {
    let product: CatalogProduct
    let fit: FitResult?
    let unit: UnitSystem

    var body: some View {
        AppCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ProductImage(product: product)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

                Text(product.name)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(money(product.price, currency: product.currency))
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let rating = product.rating {
                        Text("★ \(String(format: "%.1f", rating))")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text(sizeText)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                FitBadge(fit: fit)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sizeText: String {
        guard product.hasDimensions, let w = product.widthCm, let d = product.depthCm, let h = product.heightCm else {
            return "Size not listed"
        }
        return Length.formatDimensions(width: w, depth: d, height: h, system: unit)
    }
}

/// "Fits your room", "Doesn't fit", or "Size unknown".
struct FitBadge: View {
    let fit: FitResult?

    var body: some View {
        switch fit {
        case .fits:
            label("Fits your room", "checkmark.circle.fill", Theme.accent)
        case .doesNotFit:
            label("Doesn't fit", "xmark.circle", Theme.danger)
        case .unknownSize:
            label("Size unknown", "questionmark.circle", Theme.textSecondary)
        case .none:
            Color.clear.frame(height: 18)
        }
    }

    private func label(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(Typography.caption)
            .foregroundStyle(color)
            .frame(height: 18)
    }
}

/// The product photo, or its furniture icon while loading or if there is
/// none. Sample products get a "Sample" tag.
struct ProductImage: View {
    let product: CatalogProduct

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.surfaceAlt
            AsyncImage(url: product.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: product.type?.symbol ?? "cube")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if product.isSample {
                Tag(text: "Sample").padding(6)
            }
        }
        .clipped()
    }
}
