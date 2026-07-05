import CCTVKit
import StoreKit
import XCTest

@MainActor
final class TipJarAppStoreConnectProductTests: XCTestCase {
    private let runMarkerPath = "/tmp/maccctv-run-asc-storekit-tests"

    func testAppStoreConnectProductsLoadFromSandbox() async throws {
        let isEnabled = ProcessInfo.processInfo.environment["MACCCTV_RUN_ASC_STOREKIT_TESTS"] == "1"
            || FileManager.default.fileExists(atPath: runMarkerPath)
        guard isEnabled else {
            throw XCTSkip("Set MACCCTV_RUN_ASC_STOREKIT_TESTS=1 or create \(runMarkerPath) to query App Store Connect StoreKit products.")
        }

        let expectedProductIDs = Set(TipJarProduct.allCases.map(\.id))
        let products = try await Product.products(for: Array(expectedProductIDs))

        XCTAssertEqual(Set(products.map(\.id)), expectedProductIDs)
        for product in products {
            XCTAssertFalse(product.displayName.isEmpty, "\(product.id) is missing a display name")
            XCTAssertFalse(product.displayPrice.isEmpty, "\(product.id) is missing a display price")
        }
    }
}
