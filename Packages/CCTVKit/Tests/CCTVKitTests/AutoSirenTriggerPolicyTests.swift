import XCTest
@testable import CCTVKit

final class AutoSirenTriggerPolicyTests: XCTestCase {
    func testTriggersAfterThreeSecondsOfDeviceMotionWithRecentInputAfterArmGrace() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-5), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-3), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-2), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-1), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .trigger)
    }

    func testDoesNotTriggerBeforeThreeSecondsOfContinuousDeviceMotion() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-5), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-2.9), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-1), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .notifyOnly)
    }

    func testDoesNotTriggerWithoutRecentReinforcingSignal() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-11), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-3), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-2), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-1), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .notifyOnly)
    }

    func testPowerDisconnectReinforcesWithinThirtySeconds() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .powerDisconnect, occurredAt: now.addingTimeInterval(-30), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-3), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-2), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-1), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .trigger)
    }

    func testDoesNotTriggerDuringFirstThirtySecondsAfterArming() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(29.9)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-5), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-3), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-2), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now.addingTimeInterval(-1), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .notifyOnly)
    }

    func testPersonMotionNeverTriggersSiren() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-5), confidence: 1),
                .init(type: .personMotion, occurredAt: now.addingTimeInterval(-3), confidence: 1),
                .init(type: .personMotion, occurredAt: now.addingTimeInterval(-2), confidence: 1),
                .init(type: .personMotion, occurredAt: now.addingTimeInterval(-1), confidence: 1),
                .init(type: .personMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .notifyOnly)
    }
}
