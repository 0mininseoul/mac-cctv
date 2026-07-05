import XCTest
@testable import CCTVKit

final class FallbackPlaylistTests: XCTestCase {
    func testReplaySortsChunksByIndex() {
        let chunks = [
            chunk(index: 2),
            chunk(index: 0),
            chunk(index: 1)
        ]

        let playlist = FallbackPlaylist.replay(chunks: chunks)

        XCTAssertEqual(playlist.items.map(\.index), [0, 1, 2])
        XCTAssertTrue(playlist.missingRanges.isEmpty)
    }

    func testReplayReportsMissingIndexRangesWithoutDroppingPlayableChunks() {
        let chunks = [
            chunk(index: 0),
            chunk(index: 1),
            chunk(index: 4),
            chunk(index: 6)
        ]

        let playlist = FallbackPlaylist.replay(chunks: chunks)

        XCTAssertEqual(playlist.items.map(\.index), [0, 1, 4, 6])
        XCTAssertEqual(
            playlist.missingRanges,
            [
                FallbackPlaylist.MissingRange(startIndex: 2, endIndex: 3),
                FallbackPlaylist.MissingRange(startIndex: 5, endIndex: 5)
            ]
        )
    }

    func testLiveStartsNearTargetLatencyAndQueuesContiguousChunksFromThatPoint() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let chunks = (0...7).map { index in
            chunk(index: index, startedAt: startedAt.addingTimeInterval(Double(index) * 6))
        }
        let now = startedAt.addingTimeInterval(45)

        let playlist = FallbackPlaylist.live(chunks: chunks, now: now, targetLatency: 18)

        XCTAssertEqual(playlist.liveStartIndex, 4)
        XCTAssertEqual(playlist.items.map(\.index), [4, 5, 6, 7])
        XCTAssertEqual(playlist.initialLatency, 21)
    }

    func testLiveStartsAfterLatestGapBeforeTheTargetChunk() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let chunks = [0, 1, 4, 5, 6].map { index in
            chunk(index: index, startedAt: startedAt.addingTimeInterval(Double(index) * 6))
        }
        let now = startedAt.addingTimeInterval(42)

        let playlist = FallbackPlaylist.live(chunks: chunks, now: now, targetLatency: 18)

        XCTAssertEqual(playlist.liveStartIndex, 4)
        XCTAssertEqual(playlist.items.map(\.index), [4, 5, 6])
        XCTAssertEqual(
            playlist.missingRanges,
            [FallbackPlaylist.MissingRange(startIndex: 2, endIndex: 3)]
        )
    }

    private func chunk(
        index: Int,
        startedAt: Date = Date(timeIntervalSince1970: 1_000),
        duration: TimeInterval = 6
    ) -> VideoChunk {
        VideoChunk(
            id: "chunk-\(index)",
            sessionID: "session-1",
            index: index,
            startedAt: startedAt,
            duration: duration
        )
    }
}
