import Foundation
import XCTest
@testable import CCTVKit

final class TipJarStoreKitConfigurationTests: XCTestCase {
    func testLocalStoreKitConfigurationContainsAllTipJarProducts() throws {
        let configurationURL = try XCTUnwrap(Bundle.module.url(forResource: "MacCCTVTips", withExtension: "storekit"))
        let data = try Data(contentsOf: configurationURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(object["products"] as? [[String: Any]])
        let productIDs = Set(products.compactMap { $0["productID"] as? String })

        XCTAssertEqual(productIDs, Set(TipJarProduct.allCases.map(\.id)))
    }
}
