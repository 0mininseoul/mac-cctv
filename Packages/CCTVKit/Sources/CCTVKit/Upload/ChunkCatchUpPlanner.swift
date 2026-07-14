import Foundation

/// One local chunk file that still needs (re-)uploading to the cloud.
public struct PlannedCatchUpChunk: Equatable, Sendable {
    public let fileName: String
    public let index: Int
    public let chunkID: String

    public init(fileName: String, index: Int, chunkID: String) {
        self.fileName = fileName
        self.index = index
        self.chunkID = chunkID
    }
}

/// Pure decision logic for the startup catch-up path: given the chunk files sitting in
/// a session's local output directory and the chunk record IDs already in the cloud
/// for that session, works out which local files still need uploading. Kept free of
/// any I/O so it can be unit-tested; the surrounding uploader does the scanning,
/// network, and deletion.
public enum ChunkCatchUpPlanner {
    private static let fileNamePrefix = "chunk-"
    private static let fileNameSuffix = ".mp4"

    /// The cloud chunk record ID for a chunk at `index` of `sessionID`. Must match the
    /// live-upload id scheme (`SurveillanceController.makePendingChunks`) so a
    /// catch-up upload lands on the same record instead of creating a duplicate.
    public static func chunkID(sessionID: String, index: Int) -> String {
        "\(sessionID)-chunk-\(String(format: "%04d", index))"
    }

    /// Parses `chunk-0007.mp4` → `7`. Returns nil for anything that isn't a chunk file
    /// (diagnostics, hidden files, differently-named media, …).
    public static func chunkIndex(fileName: String) -> Int? {
        guard fileName.hasPrefix(fileNamePrefix), fileName.hasSuffix(fileNameSuffix) else {
            return nil
        }
        let digits = fileName.dropFirst(fileNamePrefix.count).dropLast(fileNameSuffix.count)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(digits)
    }

    /// Local chunk files that need (re-)uploading for `sessionID`: those whose derived
    /// chunk record ID isn't already present in `cloudChunkIDs`. Non-chunk file names
    /// are ignored, duplicate indexes are collapsed, and the result is ordered by index.
    public static func chunksNeedingUpload(
        sessionID: String,
        localFileNames: [String],
        cloudChunkIDs: Set<String>
    ) -> [PlannedCatchUpChunk] {
        var seenIndexes = Set<Int>()
        return localFileNames
            .compactMap { fileName -> PlannedCatchUpChunk? in
                guard let index = chunkIndex(fileName: fileName) else {
                    return nil
                }
                let id = chunkID(sessionID: sessionID, index: index)
                guard !cloudChunkIDs.contains(id), seenIndexes.insert(index).inserted else {
                    return nil
                }
                return PlannedCatchUpChunk(fileName: fileName, index: index, chunkID: id)
            }
            .sorted { $0.index < $1.index }
    }
}
