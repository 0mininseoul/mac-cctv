import Foundation

public struct ChunkUploadPlanner: Sendable {
    private var uploadedIDs: Set<String>

    public init(uploadedIDs: Set<String> = []) {
        self.uploadedIDs = uploadedIDs
    }

    public func pendingUploads(from chunks: [PendingChunkUpload]) -> [PendingChunkUpload] {
        chunks
            .filter { !uploadedIDs.contains($0.id) }
            .sorted { first, second in
                if first.index == second.index {
                    return first.id < second.id
                }
                return first.index < second.index
            }
    }

    public mutating func markUploaded(_ chunks: [PendingChunkUpload]) {
        uploadedIDs.formUnion(chunks.map(\.id))
    }
}
