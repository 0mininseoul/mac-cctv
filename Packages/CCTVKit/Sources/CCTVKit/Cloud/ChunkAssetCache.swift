import Foundation

/// CKAsset.fileURL points at a temporary file CloudKit manages internally and can
/// reclaim once the originating CKRecord is gone — it's not safe to hand to AVPlayer
/// for anything beyond immediate use. This copies each chunk once into a stable,
/// per-app cache location keyed by chunk ID so replay keeps working after that happens.
public final class ChunkAssetCache: @unchecked Sendable {
    public static let shared = ChunkAssetCache()

    public static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CCTVChunkCache", isDirectory: true)
    }

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(cacheDirectory: URL = ChunkAssetCache.defaultCacheDirectory) {
        self.cacheDirectory = cacheDirectory
    }

    /// Local cached URL for a chunk if it's already on disk, without downloading or
    /// needing the CKAsset — lets replay skip re-downloading chunks it already has.
    public func cachedFileURL(chunkID: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let destinationURL = cacheDirectory.appendingPathComponent("\(chunkID).mp4")
        return fileManager.fileExists(atPath: destinationURL.path) ? destinationURL : nil
    }

    public func stableFileURL(chunkID: String, sourceURL: URL?) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let destinationURL = cacheDirectory.appendingPathComponent("\(chunkID).mp4")
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        guard let sourceURL, fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }
}
