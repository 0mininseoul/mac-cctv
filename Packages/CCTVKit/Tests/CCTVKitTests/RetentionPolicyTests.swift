import XCTest
@testable import CCTVKit

final class RetentionPolicyTests: XCTestCase {
    func testExpiresEndedSessionAtExactlySevenDays() {
        let now = Date(timeIntervalSince1970: 1_783_200_000)
        let session = RetentionSession(
            id: "ended-seven-days",
            startedAt: now.addingTimeInterval(-7 * 24 * 60 * 60 - 60),
            endedAt: now.addingTimeInterval(-7 * 24 * 60 * 60),
            status: .ended
        )

        let plan = RetentionPolicy(retentionInterval: .days(7)).plan(
            sessions: [session],
            chunks: [RetentionChunk(id: "chunk-1", sessionID: session.id, startedAt: session.startedAt)],
            now: now
        )

        XCTAssertEqual(plan.sessionsToDelete.map(\.id), ["ended-seven-days"])
        XCTAssertEqual(plan.chunksToDelete.map(\.id), ["chunk-1"])
    }

    func testKeepsEndedSessionYoungerThanSevenDays() {
        let now = Date(timeIntervalSince1970: 1_783_200_000)
        let session = RetentionSession(
            id: "ended-six-point-nine-nine-days",
            startedAt: now.addingTimeInterval(-7 * 24 * 60 * 60),
            endedAt: now.addingTimeInterval(-6.99 * 24 * 60 * 60),
            status: .ended
        )

        let plan = RetentionPolicy(retentionInterval: .days(7)).plan(
            sessions: [session],
            chunks: [RetentionChunk(id: "chunk-1", sessionID: session.id, startedAt: session.startedAt)],
            now: now
        )

        XCTAssertTrue(plan.sessionsToDelete.isEmpty)
        XCTAssertTrue(plan.chunksToDelete.isEmpty)
    }

    func testProtectsRecordingSessionEvenWhenStartedMoreThanSevenDaysAgo() {
        let now = Date(timeIntervalSince1970: 1_783_200_000)
        let session = RetentionSession(
            id: "recording-old",
            startedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            endedAt: nil,
            status: .recording
        )

        let plan = RetentionPolicy(retentionInterval: .days(7)).plan(
            sessions: [session],
            chunks: [RetentionChunk(id: "chunk-1", sessionID: session.id, startedAt: session.startedAt)],
            now: now
        )

        XCTAssertTrue(plan.sessionsToDelete.isEmpty)
        XCTAssertTrue(plan.chunksToDelete.isEmpty)
    }
}
