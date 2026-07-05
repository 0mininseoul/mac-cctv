import CCTVKit
import Foundation

final class LocalChunkStore {
    private let fileManager: FileManager
    private let policy: LocalRingBufferPolicy

    init(maxBytes: Int64, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.policy = LocalRingBufferPolicy(maxBytes: maxBytes)
    }

    func prepareDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func enforceLimit(in directory: URL) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "mp4" }
        .compactMap { url -> LocalRingBufferEntry? in
            let values = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }
            return LocalRingBufferEntry(
                id: url.lastPathComponent,
                byteCount: Int64(values.fileSize ?? 0),
                createdAt: values.creationDate ?? .distantPast
            )
        }

        for entry in policy.plan(for: entries).entriesToDelete {
            try fileManager.removeItem(at: directory.appendingPathComponent(entry.id))
        }
    }

    func byteCount(for url: URL) -> Int64 {
        let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(value ?? 0)
    }
}
