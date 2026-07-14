import AVFoundation
import CCTVKit
import Foundation

/// Re-uploads chunks that were written to disk but never made it to the cloud — e.g. a
/// session whose end-of-session upload failed, or one the app was force-quit during —
/// then deletes only the local copies that uploaded successfully. Runs once at app
/// start (PRD M4: "local buffering, then re-upload"). The which-chunks-need-uploading
/// decision is the pure `ChunkCatchUpPlanner`; this type does the scanning, network,
/// and deletion around it.
struct ChunkCatchUpUploader {
    let store: CloudKitStore
    let baseDirectory: URL

    func run() async {
        let fileManager = FileManager.default
        guard let sessionDirectories = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for sessionDirectory in sessionDirectories {
            let isDirectory = (try? sessionDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else {
                continue
            }
            await catchUp(sessionID: sessionDirectory.lastPathComponent, directory: sessionDirectory)
        }
    }

    private func catchUp(sessionID: String, directory: URL) async {
        // Only reconcile sessions that actually have a cloud record — a bare local dir
        // with no session record isn't something we can meaningfully catch up.
        guard let session = try? await store.fetchSession(id: sessionID) else {
            return
        }
        // If the cloud chunk list can't be read, bail rather than risk re-uploading
        // everything on a transient error.
        guard let cloudChunks = try? await store.fetchChunkMetadata(sessionID: sessionID) else {
            return
        }
        let cloudChunkIDs = Set(cloudChunks.map(\.id))

        let fileManager = FileManager.default
        guard let localFileNames = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }

        let planned = ChunkCatchUpPlanner.chunksNeedingUpload(
            sessionID: sessionID,
            localFileNames: localFileNames,
            cloudChunkIDs: cloudChunkIDs
        )
        guard !planned.isEmpty else {
            return
        }

        var pending: [PendingChunkUpload] = []
        for chunk in planned {
            let fileURL = directory.appendingPathComponent(chunk.fileName)
            guard let duration = await Self.assetDuration(fileURL), duration > 0 else {
                continue
            }
            let byteCount = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)??.int64Value ?? 0
            pending.append(
                PendingChunkUpload(
                    id: chunk.chunkID,
                    sessionID: sessionID,
                    index: chunk.index,
                    fileURL: fileURL,
                    // No source timestamps survive a restart; approximate ordering from
                    // the session start and per-chunk duration (index preserves order).
                    startedAt: session.startedAt.addingTimeInterval(Double(chunk.index) * duration),
                    duration: duration,
                    byteCount: byteCount
                )
            )
        }
        guard !pending.isEmpty else {
            return
        }

        let result = await ChunkUploader(client: CloudKitChunkUploadClient(store: store)).upload(pending)
        for uploaded in result.uploaded {
            try? fileManager.removeItem(at: uploaded.fileURL)
        }
        Self.appendDiagnostic(
            "M4_CATCHUP session=\(sessionID) needed=\(pending.count) uploaded=\(result.uploaded.count) remaining=\(result.remaining.count)"
        )
    }

    private static func assetDuration(_ url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else {
            return nil
        }
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : nil
    }

    private static func appendDiagnostic(_ line: String) {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent("m4-catchup-result.txt")
        let data = Data(line.appending("\n").utf8)
        if FileManager.default.fileExists(atPath: resultURL.path),
           let handle = try? FileHandle(forWritingTo: resultURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: resultURL, options: .atomic)
        }
    }
}
