import SwiftUI
import UIKit

struct ItemCard: View {
    let item: Item
    let unit: UnitSystem

    var body: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Theme.surfaceAlt
                    if let data = item.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: item.type.symbol)
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(Length.formatDimensions(
                        width: item.widthCm,
                        depth: item.depthCm,
                        height: item.heightCm,
                        system: unit
                    ))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                if item.isEstimated || item.isFixed {
                    HStack(spacing: 6) {
                        if item.isEstimated { Tag(text: "Estimated") }
                        if item.isFixed { Tag(text: "Fixed") }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
