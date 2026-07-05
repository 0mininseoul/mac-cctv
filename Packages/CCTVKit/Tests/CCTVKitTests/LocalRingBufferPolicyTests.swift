import XCTest
@testable import CCTVKit

final class LocalRingBufferPolicyTests: XCTestCase {
    func testDeletesOldestChunksUntilTotalSizeIsWithinLimit() {
        let baseDate = Date(timeIntervalSince1970: 1_783_200_000)
        let policy = LocalRingBufferPolicy(maxBytes: 1_000)
        let chunks = [
            LocalRingBufferEntry(id: "oldest", byteCount: 400, createdAt: baseDate),
            LocalRingBufferEntry(id: "middle", byteCount: 400, createdAt: baseDate.addingTimeInterval(1)),
            LocalRingBufferEntry(id: "newest", byteCount: 400, createdAt: baseDate.addingTimeInterval(2))
        ]

        let plan = policy.plan(for: chunks)

        XCTAssertEqual(plan.entriesToDelete.map(\.id), ["oldest"])
        XCTAssertEqual(plan.retainedEntries.map(\.id), ["middle", "newest"])
        XCTAssertEqual(plan.retainedBytes, 800)
    }

    func testKeepsChunksWhenTotalSizeIsAlreadyWithinLimit() {
        let baseDate = Date(timeIntervalSince1970: 1_783_200_000)
        let policy = LocalRingBufferPolicy(maxBytes: 1_000)
        let chunks = [
            LocalRingBufferEntry(id: "first", byteCount: 300, createdAt: baseDate),
            LocalRingBufferEntry(id: "second", byteCount: 500, createdAt: baseDate.addingTimeInterval(1))
        ]

        let plan = policy.plan(for: chunks)

        XCTAssertTrue(plan.entriesToDelete.isEmpty)
        XCTAssertEqual(plan.retainedEntries.map(\.id), ["first", "second"])
        XCTAssertEqual(plan.retainedBytes, 800)
    }
}
