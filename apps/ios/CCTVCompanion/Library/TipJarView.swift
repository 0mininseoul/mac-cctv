import CCTVKit
import StoreKit
import SwiftUI

struct TipJarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("tip_jar_title")
                    .font(.subheadline.weight(.semibold))
                Text("tip_jar_subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(TipJarProduct.allCases) { product in
                ProductView(id: product.id) {
                    Image(systemName: iconName(for: product))
                }
                .productViewStyle(.compact)
            }
        }
        .storeButton(.hidden, for: .restorePurchases)
    }

    private func iconName(for product: TipJarProduct) -> String {
        switch product {
        case .smallCoffee:
            "cup.and.saucer"
        case .largeCoffee:
            "cup.and.saucer.fill"
        case .supporter:
            "heart.fill"
        }
    }
}

struct HouseBannerSlot: View {
    private let isVisibleInV1 = false

    @ViewBuilder
    var body: some View {
        if isVisibleInV1 {
            EmptyView()
        }
    }
}
