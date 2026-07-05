import XCTest
@testable import CCTVKit

final class EventRateLimiterTests: XCTestCase {
    func testAllowsFirstEventImmediately() {
        var limiter = EventRateLimiter(cooldown: 30)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(limiter.shouldRecord(.personMotion, at: now))
    }

    func testSuppressesSameEventTypeInsideCooldown() {
        var limiter = EventRateLimiter(cooldown: 30)
        let first = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(limiter.shouldRecord(.personMotion, at: first))
        XCTAssertFalse(limiter.shouldRecord(.personMotion, at: first.addingTimeInterval(29)))
    }

    func testAllowsSameEventTypeAfterCooldown() {
        var limiter = EventRateLimiter(cooldown: 30)
        let first = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(limiter.shouldRecord(.personMotion, at: first))
        XCTAssertTrue(limiter.shouldRecord(.personMotion, at: first.addingTimeInterval(30)))
    }

    func testTracksEventTypesIndependently() {
        var limiter = EventRateLimiter(cooldown: 30)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(limiter.shouldRecord(.personMotion, at: now))
        XCTAssertTrue(limiter.shouldRecord(.inputTouch, at: now.addingTimeInterval(1)))
    }
}
