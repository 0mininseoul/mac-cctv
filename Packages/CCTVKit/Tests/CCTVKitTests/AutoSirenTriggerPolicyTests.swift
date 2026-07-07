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

    func testEscalatesBeforeThreeSecondsOfContinuousDeviceMotion() {
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

        XCTAssertEqual(decision, .escalate)
    }

    func testEscalatesWithSingleQualifyingMotionSample() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-5), confidence: 1),
                .init(type: .deviceMotion, occurredAt: now, confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .escalate)
    }

    func testDoesNotEscalateWithTouchAndNoMotionAtAll() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(40)

        let decision = policy.decision(
            armedAt: armedAt,
            now: now,
            evidence: [
                .init(type: .inputTouch, occurredAt: now.addingTimeInterval(-5), confidence: 1)
            ]
        )

        XCTAssertEqual(decision, .notifyOnly)
    }

    func testTriggersWhenEscalatingMotionReachesThreeSeconds() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let laterNow = armedAt.addingTimeInterval(41)
        let touch = laterNow.addingTimeInterval(-5)
        let m1 = laterNow.addingTimeInterval(-3)
        let m2 = laterNow.addingTimeInterval(-2)
        let m3 = laterNow.addingTimeInterval(-1)

        let earlyNow = laterNow.addingTimeInterval(-0.1)
        let earlyDecision = policy.decision(
            armedAt: armedAt,
            now: earlyNow,
            evidence: [
                .init(type: .inputTouch, occurredAt: touch, confidence: 1),
                .init(type: .deviceMotion, occurredAt: m1, confidence: 1),
                .init(type: .deviceMotion, occurredAt: m2, confidence: 1),
                .init(type: .deviceMotion, occurredAt: m3, confidence: 1)
            ]
        )
        XCTAssertEqual(earlyDecision, .escalate)

        let laterDecision = policy.decision(
            armedAt: armedAt,
            now: laterNow,
            evidence: [
                .init(type: .inputTouch, occurredAt: touch, confidence: 1),
                .init(type: .deviceMotion, occurredAt: m1, confidence: 1),
                .init(type: .deviceMotion, occurredAt: m2, confidence: 1),
                .init(type: .deviceMotion, occurredAt: m3, confidence: 1),
                .init(type: .deviceMotion, occurredAt: laterNow, confidence: 1)
            ]
        )
        XCTAssertEqual(laterDecision, .trigger)
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

    func testDoesNotTriggerDuringFirstFifteenSecondsAfterArming() {
        let policy = AutoSirenTriggerPolicy()
        let armedAt = Date(timeIntervalSince1970: 1_000)
        let now = armedAt.addingTimeInterval(14.9)

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
