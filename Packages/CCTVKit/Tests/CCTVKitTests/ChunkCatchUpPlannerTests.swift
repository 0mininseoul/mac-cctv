import XCTest
@testable import CCTVKit

final class ChunkCatchUpPlannerTests: XCTestCase {
    func testChunkIDMatchesLiveUploadScheme() {
        XCTAssertEqual(ChunkCatchUpPlanner.chunkID(sessionID: "m3-42", index: 9), "m3-42-chunk-0009")
        XCTAssertEqual(ChunkCatchUpPlanner.chunkID(sessionID: "m3-42", index: 0), "m3-42-chunk-0000")
        XCTAssertEqual(ChunkCatchUpPlanner.chunkID(sessionID: "m3-42", index: 1234), "m3-42-chunk-1234")
    }

    func testChunkIndexParsesOnlyChunkFiles() {
        XCTAssertEqual(ChunkCatchUpPlanner.chunkIndex(fileName: "chunk-0007.mp4"), 7)
        XCTAssertEqual(ChunkCatchUpPlanner.chunkIndex(fileName: "chunk-0000.mp4"), 0)
        XCTAssertNil(ChunkCatchUpPlanner.chunkIndex(fileName: "chunk-.mp4"))
        XCTAssertNil(ChunkCatchUpPlanner.chunkIndex(fileName: "chunk-0007.mov"))
        XCTAssertNil(ChunkCatchUpPlanner.chunkIndex(fileName: "chunk-12ab.mp4"))
        XCTAssertNil(ChunkCatchUpPlanner.chunkIndex(fileName: ".DS_Store"))
        XCTAssertNil(ChunkCatchUpPlanner.chunkIndex(fileName: "m5-event-result.txt"))
    }

    func testReturnsOnlyLocalChunksMissingFromCloudOrderedByIndex() {
        let planned = ChunkCatchUpPlanner.chunksNeedingUpload(
            sessionID: "m3-42",
            localFileNames: ["chunk-0002.mp4", "chunk-0000.mp4", "chunk-0001.mp4", ".DS_Store"],
            cloudChunkIDs: ["m3-42-chunk-0000"] // chunk 0 already uploaded
        )
        XCTAssertEqual(planned, [
            PlannedCatchUpChunk(fileName: "chunk-0001.mp4", index: 1, chunkID: "m3-42-chunk-0001"),
            PlannedCatchUpChunk(fileName: "chunk-0002.mp4", index: 2, chunkID: "m3-42-chunk-0002")
        ])
    }

    func testEmptyWhenEverythingAlreadyInCloud() {
        let planned = ChunkCatchUpPlanner.chunksNeedingUpload(
            sessionID: "m3-42",
            localFileNames: ["chunk-0000.mp4", "chunk-0001.mp4"],
            cloudChunkIDs: ["m3-42-chunk-0000", "m3-42-chunk-0001"]
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testAllLocalWhenCloudEmpty() {
        let planned = ChunkCatchUpPlanner.chunksNeedingUpload(
            sessionID: "s",
            localFileNames: ["chunk-0001.mp4", "chunk-0000.mp4"],
            cloudChunkIDs: []
        )
        XCTAssertEqual(planned.map(\.index), [0, 1])
    }

    func testIgnoresNonChunkFilesAndCollapsesDuplicateIndexes() {
        let planned = ChunkCatchUpPlanner.chunksNeedingUpload(
            sessionID: "s",
            localFileNames: ["chunk-0003.mp4", "notes.txt", "chunk-0003.mp4"],
            cloudChunkIDs: []
        )
        XCTAssertEqual(planned, [
            PlannedCatchUpChunk(fileName: "chunk-0003.mp4", index: 3, chunkID: "s-chunk-0003")
        ])
    }
}
