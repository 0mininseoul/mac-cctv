import AVFoundation
import Foundation

final class ChunkWriter {
    private struct ActiveChunk {
        var index: Int
        var url: URL
        var writer: AVAssetWriter
        var input: AVAssetWriterInput
        var sourceStartTime: CMTime
        var lastSourceTime: CMTime
    }

    private let outputDirectory: URL
    private let settings: CaptureSettings
    private let chunkDuration: CMTime
    private let store: LocalChunkStore
    private let finishGroup = DispatchGroup()
    private let lock = NSLock()
    private var activeChunk: ActiveChunk?
    private var nextIndex = 0
    private var completedChunks: [CaptureChunk] = []

    init(outputDirectory: URL, settings: CaptureSettings) throws {
        self.outputDirectory = outputDirectory
        self.settings = settings
        self.chunkDuration = CMTime(seconds: settings.chunkDuration, preferredTimescale: 600)
        self.store = LocalChunkStore(maxBytes: settings.maxLocalBytes)
        try store.prepareDirectory(outputDirectory)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if activeChunk == nil {
            startChunk(at: presentationTime)
        }

        if let activeChunk, presentationTime - activeChunk.sourceStartTime >= chunkDuration {
            finish(activeChunk, sourceEndTime: presentationTime)
            startChunk(at: presentationTime)
        }

        guard var activeChunk, activeChunk.input.isReadyForMoreMediaData else {
            return
        }
        if activeChunk.input.append(sampleBuffer) {
            activeChunk.lastSourceTime = presentationTime
            self.activeChunk = activeChunk
        }
    }

    func finishCurrentChunk() {
        guard let activeChunk else {
            return
        }
        let duration = max(0, activeChunk.lastSourceTime.seconds - activeChunk.sourceStartTime.seconds)
        guard duration >= 0.5 else {
            discard(activeChunk)
            return
        }
        finish(activeChunk, sourceEndTime: activeChunk.lastSourceTime)
    }

    func waitForFinishedChunks(timeout: TimeInterval) -> [CaptureChunk] {
        _ = finishGroup.wait(timeout: .now() + timeout)
        let chunks = finishedChunksSnapshot()
        let trackedURLs = Set(chunks.map { URL(fileURLWithPath: $0.path) })
        try? store.removeUntrackedMP4s(in: outputDirectory, keeping: trackedURLs)
        return chunks
    }

    func finishedChunksSnapshot() -> [CaptureChunk] {
        lock.lock()
        let chunks = completedChunks.sorted { $0.index < $1.index }
        lock.unlock()
        return chunks
    }

    private func startChunk(at sourceStartTime: CMTime) {
        let fileName = String(format: "chunk-%04d.mp4", nextIndex)
        let url = outputDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings())
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                return
            }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: sourceStartTime)

            activeChunk = ActiveChunk(
                index: nextIndex,
                url: url,
                writer: writer,
                input: input,
                sourceStartTime: sourceStartTime,
                lastSourceTime: sourceStartTime
            )
            nextIndex += 1
        } catch {
            activeChunk = nil
        }
    }

    private func finish(_ chunk: ActiveChunk, sourceEndTime: CMTime) {
        activeChunk = nil
        chunk.writer.endSession(atSourceTime: sourceEndTime)
        chunk.input.markAsFinished()

        finishGroup.enter()
        chunk.writer.finishWriting { [store, outputDirectory] in
            defer { self.finishGroup.leave() }
            guard chunk.writer.status == .completed else {
                try? FileManager.default.removeItem(at: chunk.url)
                return
            }

            let sourceStartSeconds = chunk.sourceStartTime.seconds
            let sourceEndSeconds = sourceEndTime.seconds
            let duration = max(0, sourceEndSeconds - sourceStartSeconds)
            guard duration >= 0.5 else {
                try? FileManager.default.removeItem(at: chunk.url)
                return
            }
            let completedChunk = CaptureChunk(
                index: chunk.index,
                path: chunk.url.path,
                sourceStartSeconds: sourceStartSeconds,
                sourceEndSeconds: sourceEndSeconds,
                duration: duration,
                byteCount: store.byteCount(for: chunk.url)
            )

            self.lock.lock()
            self.completedChunks.append(completedChunk)
            self.lock.unlock()
            try? store.enforceLimit(in: outputDirectory)
        }
    }

    private func discard(_ chunk: ActiveChunk) {
        activeChunk = nil
        chunk.input.markAsFinished()
        chunk.writer.cancelWriting()
        try? FileManager.default.removeItem(at: chunk.url)
    }

    private func videoOutputSettings() -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.averageBitRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
    }
}
