import XCTest
@testable import CCTVKit

final class ChunkUploadPlannerTests: XCTestCase {
    func testReturnsOnlyChunksThatHaveNotAlreadyUploadedInIndexOrder() {
        let planner = ChunkUploadPlanner(uploadedIDs: ["session-chunk-0001"])
        let chunks = [
            PendingChunkUpload(id: "session-chunk-0002", sessionID: "session", index: 2, fileURL: URL(fileURLWithPath: "/tmp/2.mp4")),
            PendingChunkUpload(id: "session-chunk-0000", sessionID: "session", index: 0, fileURL: URL(fileURLWithPath: "/tmp/0.mp4")),
            PendingChunkUpload(id: "session-chunk-0001", sessionID: "session", index: 1, fileURL: URL(fileURLWithPath: "/tmp/1.mp4"))
        ]

        let pending = planner.pendingUploads(from: chunks)

        XCTAssertEqual(pending.map(\.id), ["session-chunk-0000", "session-chunk-0002"])
    }

    func testMarkUploadedPreventsSuccessfulChunksFromBeingReturnedAgain() {
        var planner = ChunkUploadPlanner()
        let chunks = [
            PendingChunkUpload(id: "session-chunk-0000", sessionID: "session", index: 0, fileURL: URL(fileURLWithPath: "/tmp/0.mp4")),
            PendingChunkUpload(id: "session-chunk-0001", sessionID: "session", index: 1, fileURL: URL(fileURLWithPath: "/tmp/1.mp4"))
        ]

        planner.markUploaded([chunks[0]])

        XCTAssertEqual(planner.pendingUploads(from: chunks).map(\.id), ["session-chunk-0001"])
    }
}
