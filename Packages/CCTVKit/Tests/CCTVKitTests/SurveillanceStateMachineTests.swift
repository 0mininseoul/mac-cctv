import XCTest
@testable import CCTVKit

final class SurveillanceStateMachineTests: XCTestCase {
    func testArmsFromIdleAndDisarmsBackToIdle() throws {
        let startedAt = Date(timeIntervalSince1970: 1_783_200_000)
        let endedAt = startedAt.addingTimeInterval(60)
        var machine = SurveillanceStateMachine()

        try machine.apply(.arm(startedAt: startedAt))
        XCTAssertEqual(machine.state, .armed(startedAt: startedAt))

        try machine.apply(.disarm(endedAt: endedAt))
        XCTAssertEqual(machine.state, .idle)
    }

    func testSirenCanOnlyBeTriggeredWhileArmedAndCanReturnToArmed() throws {
        let startedAt = Date(timeIntervalSince1970: 1_783_200_000)
        let triggeredAt = startedAt.addingTimeInterval(40)
        let silencedAt = triggeredAt.addingTimeInterval(3)
        var machine = SurveillanceStateMachine()

        XCTAssertThrowsError(try machine.apply(.triggerSiren(triggeredAt: triggeredAt))) { error in
            XCTAssertEqual(error as? SurveillanceStateTransitionError, .illegalTransition(from: .idle, event: .triggerSiren(triggeredAt: triggeredAt)))
        }

        try machine.apply(.arm(startedAt: startedAt))
        try machine.apply(.triggerSiren(triggeredAt: triggeredAt))
        XCTAssertEqual(machine.state, .siren(startedAt: startedAt, triggeredAt: triggeredAt))

        try machine.apply(.silenceSiren(silencedAt: silencedAt))
        XCTAssertEqual(machine.state, .armed(startedAt: startedAt))
    }

    func testRejectsDuplicateArmAndSilenceOutsideSiren() throws {
        let startedAt = Date(timeIntervalSince1970: 1_783_200_000)
        var machine = SurveillanceStateMachine()

        try machine.apply(.arm(startedAt: startedAt))

        XCTAssertThrowsError(try machine.apply(.arm(startedAt: startedAt))) { error in
            XCTAssertEqual(error as? SurveillanceStateTransitionError, .illegalTransition(from: .armed(startedAt: startedAt), event: .arm(startedAt: startedAt)))
        }
        XCTAssertThrowsError(try machine.apply(.silenceSiren(silencedAt: startedAt))) { error in
            XCTAssertEqual(error as? SurveillanceStateTransitionError, .illegalTransition(from: .armed(startedAt: startedAt), event: .silenceSiren(silencedAt: startedAt)))
        }
    }
}
