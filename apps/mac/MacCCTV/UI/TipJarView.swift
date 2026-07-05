import CCTVKit
import StoreKit
import SwiftUI

struct TipJarView: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 3) {
                Text("tip_jar_subtitle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                ForEach(TipJarProduct.allCases) { product in
                    ProductView(id: product.id) {
                        Image(systemName: iconName(for: product))
                    }
                    .productViewStyle(.compact)
                    .controlSize(.small)
                }
            }
            .storeButton(.hidden, for: .restorePurchases)
            .padding(.top, 8)
        } label: {
            Label("tip_jar_support_button", systemImage: "heart")
                .font(.caption.weight(.semibold))
        }
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
