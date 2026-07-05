import XCTest
@testable import CCTVKit

final class TipJarProductTests: XCTestCase {
    func testTipJarContainsThreeConsumableProductsInAscendingOrder() {
        XCTAssertEqual(
            TipJarProduct.allCases,
            [.smallCoffee, .largeCoffee, .supporter]
        )
    }

    func testTipJarProductIdentifiersUseAppNamespace() {
        XCTAssertEqual(TipJarProduct.smallCoffee.id, "com.youngminpark.maccctv.tip.small")
        XCTAssertEqual(TipJarProduct.largeCoffee.id, "com.youngminpark.maccctv.tip.large")
        XCTAssertEqual(TipJarProduct.supporter.id, "com.youngminpark.maccctv.tip.supporter")
    }
}
