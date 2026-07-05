import XCTest
@testable import CCTVKit

final class ChunkUploaderTests: XCTestCase {
    func testRetriesTransientFailureWithExponentialBackoffThenContinuesInOrder() async {
        let client = MockChunkUploadClient(results: [
            .failure(.transient("network")),
            .success(()),
            .success(())
        ])
        let sleeper = RecordingSleeper()
        let uploader = ChunkUploader(client: client, sleeper: sleeper, maxAttempts: 3)
        let chunks = [
            PendingChunkUpload(id: "first", sessionID: "session", index: 0, fileURL: URL(fileURLWithPath: "/tmp/first.mp4")),
            PendingChunkUpload(id: "second", sessionID: "session", index: 1, fileURL: URL(fileURLWithPath: "/tmp/second.mp4"))
        ]

        let result = await uploader.upload(chunks)
        let uploadedIDs = await client.uploadedIDsSnapshot()
        let recordedDelays = await sleeper.recordedDelaysSnapshot()

        XCTAssertEqual(uploadedIDs, ["first", "first", "second"])
        XCTAssertEqual(recordedDelays, [1])
        XCTAssertEqual(result.uploaded.map(\.id), ["first", "second"])
        XCTAssertTrue(result.remaining.isEmpty)
    }

    func testStopsAtOfflineFailureAndKeepsCurrentAndLaterChunksPending() async {
        let client = MockChunkUploadClient(results: [
            .success(()),
            .failure(.offline)
        ])
        let uploader = ChunkUploader(client: client, sleeper: RecordingSleeper(), maxAttempts: 3)
        let chunks = [
            PendingChunkUpload(id: "uploaded", sessionID: "session", index: 0, fileURL: URL(fileURLWithPath: "/tmp/uploaded.mp4")),
            PendingChunkUpload(id: "offline", sessionID: "session", index: 1, fileURL: URL(fileURLWithPath: "/tmp/offline.mp4")),
            PendingChunkUpload(id: "later", sessionID: "session", index: 2, fileURL: URL(fileURLWithPath: "/tmp/later.mp4"))
        ]

        let result = await uploader.upload(chunks)
        let uploadedIDs = await client.uploadedIDsSnapshot()

        XCTAssertEqual(uploadedIDs, ["uploaded", "offline"])
        XCTAssertEqual(result.uploaded.map(\.id), ["uploaded"])
        XCTAssertEqual(result.remaining.map(\.id), ["offline", "later"])
    }
}

private actor MockChunkUploadClient: ChunkUploadClient {
    private var results: [Result<Void, ChunkUploadError>]
    private var uploadedIDs: [String] = []

    init(results: [Result<Void, ChunkUploadError>]) {
        self.results = results
    }

    func upload(_ chunk: PendingChunkUpload) async throws {
        uploadedIDs.append(chunk.id)
        guard !results.isEmpty else {
            return
        }
        switch results.removeFirst() {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    func uploadedIDsSnapshot() -> [String] {
        uploadedIDs
    }
}

private actor RecordingSleeper: ChunkUploadSleeper {
    private var recordedDelays: [TimeInterval] = []

    func sleep(for delay: TimeInterval) async {
        recordedDelays.append(delay)
    }

    func recordedDelaysSnapshot() -> [TimeInterval] {
        recordedDelays
    }
}
