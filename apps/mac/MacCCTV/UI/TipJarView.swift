import CCTVKit
import StoreKit
import SwiftUI

struct TipJarView: View {
    @State private var isExpanded = false
    @State private var products: [String: Product] = [:]
    @State private var isLoadingProducts = false
    @State private var purchasingProductID: String?
    @State private var statusKey: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                Label("tip_jar_support_button", systemImage: "heart")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("tip_jar_subtitle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLoadingProducts && products.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("tip_jar_loading")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(TipJarProduct.allCases) { product in
                        tipButton(for: product)
                    }

                    if let statusKey {
                        Text(statusKey)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .task {
            await loadProducts()
        }
        .task {
            await observeTransactions()
        }
    }

    @ViewBuilder
    private func tipButton(for tip: TipJarProduct) -> some View {
        let product = products[tip.id]

        Button {
            guard let product else {
                return
            }
            Task {
                await purchase(product)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: tip))
                    .font(.title3)
                    .frame(width: 26)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey(for: tip))
                        .font(.caption.weight(.semibold))
                    Text(subtitleKey(for: tip))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if purchasingProductID == tip.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(product?.displayPrice ?? "...")
                        .font(.caption.weight(.semibold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(product == nil || purchasingProductID != nil)
        .padding(.vertical, 4)
    }

    @MainActor
    private func loadProducts() async {
        guard !isLoadingProducts else {
            return
        }

        isLoadingProducts = true
        defer {
            isLoadingProducts = false
        }

        do {
            let loadedProducts = try await Product.products(for: TipJarProduct.allCases.map(\.id))
            products = Dictionary(uniqueKeysWithValues: loadedProducts.map { ($0.id, $0) })
            if loadedProducts.isEmpty {
                statusKey = "tip_jar_unavailable"
            }
        } catch {
            statusKey = "tip_jar_unavailable"
        }
    }

    @MainActor
    private func purchase(_ product: Product) async {
        purchasingProductID = product.id
        defer {
            purchasingProductID = nil
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    statusKey = "tip_jar_thanks"
                case .unverified:
                    statusKey = "tip_jar_purchase_failed"
                }
            case .pending:
                statusKey = "tip_jar_purchase_pending"
            case .userCancelled:
                break
            @unknown default:
                statusKey = "tip_jar_purchase_failed"
            }
        } catch {
            statusKey = "tip_jar_purchase_failed"
        }
    }

    @MainActor
    private func observeTransactions() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update,
                  TipJarProduct.allCases.contains(where: { $0.id == transaction.productID }) else {
                continue
            }

            await transaction.finish()
            statusKey = "tip_jar_thanks"
        }
    }

    private func titleKey(for product: TipJarProduct) -> LocalizedStringKey {
        switch product {
        case .smallCoffee:
            "tip_jar_product_small_title"
        case .largeCoffee:
            "tip_jar_product_large_title"
        case .supporter:
            "tip_jar_product_supporter_title"
        }
    }

    private func subtitleKey(for product: TipJarProduct) -> LocalizedStringKey {
        switch product {
        case .smallCoffee:
            "tip_jar_product_small_subtitle"
        case .largeCoffee:
            "tip_jar_product_large_subtitle"
        case .supporter:
            "tip_jar_product_supporter_subtitle"
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
