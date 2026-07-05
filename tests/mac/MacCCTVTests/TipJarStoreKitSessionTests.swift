import CCTVKit
import StoreKit
import StoreKitTest
import XCTest

@MainActor
final class TipJarStoreKitSessionTests: XCTestCase {
    func testLocalStoreKitSessionLoadsAndPurchasesTipJarProduct() async throws {
        let configurationURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MacCCTVTips", withExtension: "storekit"))
        let writableConfigurationURL = FileManager.default.temporaryDirectory
            .appending(component: "MacCCTVTips-\(UUID().uuidString)")
            .appendingPathExtension("storekit")
        try FileManager.default.copyItem(at: configurationURL, to: writableConfigurationURL)
        defer {
            try? FileManager.default.removeItem(at: writableConfigurationURL)
        }

        let session = try SKTestSession(contentsOf: writableConfigurationURL)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()

        let products = try await Product.products(for: TipJarProduct.allCases.map(\.id))
        let productIDs = Set(products.map(\.id))
        XCTAssertEqual(productIDs, Set(TipJarProduct.allCases.map(\.id)))

        let transaction = try await session.buyProduct(identifier: TipJarProduct.smallCoffee.id)
        XCTAssertEqual(transaction.productID, TipJarProduct.smallCoffee.id)
    }
}
