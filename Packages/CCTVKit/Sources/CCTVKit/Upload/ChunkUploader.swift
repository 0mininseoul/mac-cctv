import Foundation

public struct PendingChunkUpload: Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let index: Int
    public let fileURL: URL

    public init(id: String, sessionID: String, index: Int, fileURL: URL) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.fileURL = fileURL
    }
}

public enum ChunkUploadError: Error, Equatable, Sendable {
    case offline
    case transient(String)
    case permanent(String)
}

public protocol ChunkUploadClient: Sendable {
    func upload(_ chunk: PendingChunkUpload) async throws
}

public protocol ChunkUploadSleeper: Sendable {
    func sleep(for delay: TimeInterval) async
}

public struct TaskChunkUploadSleeper: ChunkUploadSleeper {
    public init() {}

    public func sleep(for delay: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

public struct ChunkUploadResult: Equatable, Sendable {
    public let uploaded: [PendingChunkUpload]
    public let remaining: [PendingChunkUpload]

    public init(uploaded: [PendingChunkUpload], remaining: [PendingChunkUpload]) {
        self.uploaded = uploaded
        self.remaining = remaining
    }
}

public struct ChunkUploader<Client: ChunkUploadClient, Sleeper: ChunkUploadSleeper>: Sendable {
    private let client: Client
    private let sleeper: Sleeper
    private let maxAttempts: Int
    private let initialBackoff: TimeInterval

    public init(
        client: Client,
        sleeper: Sleeper = TaskChunkUploadSleeper(),
        maxAttempts: Int = 4,
        initialBackoff: TimeInterval = 1
    ) {
        self.client = client
        self.sleeper = sleeper
        self.maxAttempts = max(1, maxAttempts)
        self.initialBackoff = max(0, initialBackoff)
    }

    public func upload(_ chunks: [PendingChunkUpload]) async -> ChunkUploadResult {
        let orderedChunks = chunks.sorted { first, second in
            if first.index == second.index {
                return first.id < second.id
            }
            return first.index < second.index
        }
        var uploaded: [PendingChunkUpload] = []

        for (position, chunk) in orderedChunks.enumerated() {
            let outcome = await uploadWithRetry(chunk)
            switch outcome {
            case .uploaded:
                uploaded.append(chunk)
            case .deferRemaining:
                return ChunkUploadResult(
                    uploaded: uploaded,
                    remaining: Array(orderedChunks[position...])
                )
            case .drop:
                uploaded.append(chunk)
            }
        }

        return ChunkUploadResult(uploaded: uploaded, remaining: [])
    }

    private func uploadWithRetry(_ chunk: PendingChunkUpload) async -> UploadOutcome {
        var attempt = 1
        var nextBackoff = initialBackoff

        while true {
            do {
                try await client.upload(chunk)
                return .uploaded
            } catch let error as ChunkUploadError {
                switch error {
                case .offline:
                    return .deferRemaining
                case .permanent:
                    return .drop
                case .transient:
                    guard attempt < maxAttempts else {
                        return .deferRemaining
                    }
                    await sleeper.sleep(for: nextBackoff)
                    nextBackoff *= 2
                    attempt += 1
                }
            } catch {
                guard attempt < maxAttempts else {
                    return .deferRemaining
                }
                await sleeper.sleep(for: nextBackoff)
                nextBackoff *= 2
                attempt += 1
            }
        }
    }

    private enum UploadOutcome {
        case uploaded
        case deferRemaining
        case drop
    }
}
