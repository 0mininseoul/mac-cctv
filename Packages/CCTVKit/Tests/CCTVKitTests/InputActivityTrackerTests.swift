import XCTest
@testable import CCTVKit

final class InputActivityTrackerTests: XCTestCase {
    func testFirstObservationEstablishesBaselineWithoutReportingInput() {
        var tracker = InputActivityTracker()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(tracker.observe(now: now, idleSeconds: 12))
    }

    func testIncreasingIdleTimeDoesNotReportNewInput() {
        var tracker = InputActivityTracker()
        let now = Date(timeIntervalSince1970: 1_000)

        _ = tracker.observe(now: now, idleSeconds: 12)
        let detected = tracker.observe(now: now.addingTimeInterval(1), idleSeconds: 13)

        XCTAssertFalse(detected)
    }

    func testIdleResetReportsNewInput() {
        var tracker = InputActivityTracker()
        let now = Date(timeIntervalSince1970: 1_000)

        _ = tracker.observe(now: now, idleSeconds: 12)
        let detected = tracker.observe(now: now.addingTimeInterval(1), idleSeconds: 0.1)

        XCTAssertTrue(detected)
    }

    func testSmallTimestampJitterDoesNotReportNewInput() {
        var tracker = InputActivityTracker(minimumActivityAdvance: 0.25)
        let now = Date(timeIntervalSince1970: 1_000)

        _ = tracker.observe(now: now, idleSeconds: 12)
        let detected = tracker.observe(now: now.addingTimeInterval(1), idleSeconds: 12.9)

        XCTAssertFalse(detected)
    }

    func testInvalidIdleObservationDoesNotBecomeBaseline() {
        var tracker = InputActivityTracker()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(tracker.observe(now: now, idleSeconds: .greatestFiniteMagnitude))
        XCTAssertFalse(tracker.observe(now: now.addingTimeInterval(1), idleSeconds: 0.1))
    }
}
