import CloudKit
import Foundation

public struct CloudKitChunkUploadClient: ChunkUploadClient {
    private let store: CloudKitStore

    public init(store: CloudKitStore = CloudKitStore()) {
        self.store = store
    }

    public func upload(_ chunk: PendingChunkUpload) async throws {
        do {
            _ = try await store.saveChunk(chunk)
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func mapCloudKitError(_ error: Error) -> ChunkUploadError {
        guard let ckError = error as? CKError else {
            return .transient(error.localizedDescription)
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .offline
        case .quotaExceeded, .invalidArguments, .permissionFailure:
            return .permanent(ckError.localizedDescription)
        default:
            return .transient(ckError.localizedDescription)
        }
    }
}
