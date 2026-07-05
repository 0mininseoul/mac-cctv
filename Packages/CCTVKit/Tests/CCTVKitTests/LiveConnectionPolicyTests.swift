import XCTest
@testable import CCTVKit

final class LiveConnectionPolicyTests: XCTestCase {
    func testKeepsConnectingBeforeTimeoutWithoutRemoteVideo() {
        let policy = LiveConnectionPolicy(timeout: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(9.9),
            hasReceivedRemoteVideo: false,
            peerConnectionFailed: false
        )

        guard case let .connecting(elapsed) = mode else {
            return XCTFail("Expected connecting mode, got \(mode)")
        }
        XCTAssertEqual(elapsed, 9.9, accuracy: 0.001)
    }

    func testUsesRealtimeOnceRemoteVideoArrivesEvenAfterTimeoutWindow() {
        let policy = LiveConnectionPolicy(timeout: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(11),
            hasReceivedRemoteVideo: true,
            peerConnectionFailed: false
        )

        XCTAssertEqual(mode, .realtime)
    }

    func testFallsBackToDelayedModeAtTimeout() {
        let policy = LiveConnectionPolicy(timeout: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(10),
            hasReceivedRemoteVideo: false,
            peerConnectionFailed: false
        )

        XCTAssertEqual(mode, .delayedFallback(reason: .timeout))
    }

    func testKeepsConnectingWhenPeerConnectionEstablishedNearTimeoutAndFrameGraceRemains() {
        let policy = LiveConnectionPolicy(timeout: 10, connectedFrameGrace: 5)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(10.2),
            hasReceivedRemoteVideo: false,
            peerConnectionConnectedAt: startedAt.addingTimeInterval(9.4),
            peerConnectionFailed: false
        )

        guard case let .connecting(elapsed) = mode else {
            return XCTFail("Expected connecting mode, got \(mode)")
        }
        XCTAssertEqual(elapsed, 10.2, accuracy: 0.001)
    }

    func testFallsBackWhenPeerConnectionEstablishedButNoFrameArrivesAfterGrace() {
        let policy = LiveConnectionPolicy(timeout: 10, connectedFrameGrace: 5)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(14.5),
            hasReceivedRemoteVideo: false,
            peerConnectionConnectedAt: startedAt.addingTimeInterval(9.4),
            peerConnectionFailed: false
        )

        XCTAssertEqual(mode, .delayedFallback(reason: .timeout))
    }

    func testFallsBackImmediatelyWhenPeerConnectionFails() {
        let policy = LiveConnectionPolicy(timeout: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(2),
            hasReceivedRemoteVideo: false,
            peerConnectionFailed: true
        )

        XCTAssertEqual(mode, .delayedFallback(reason: .connectionFailed))
    }

    func testConnectionFailureOverridesPreviouslyReceivedRemoteVideo() {
        let policy = LiveConnectionPolicy(timeout: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let mode = policy.mode(
            startedAt: startedAt,
            now: startedAt.addingTimeInterval(12),
            hasReceivedRemoteVideo: true,
            peerConnectionFailed: true
        )

        XCTAssertEqual(mode, .delayedFallback(reason: .connectionFailed))
    }
}
