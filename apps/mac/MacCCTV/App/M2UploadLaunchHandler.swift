import CCTVKit
import Darwin
import Foundation

enum M2UploadLaunchHandler {
    static let captureUploadArgument = "--m2-capture-upload"
    static let uploadPendingArgument = "--m2-upload-pending"
    static let sweepArgument = "--m2-sweep"
    static let verifyArgument = "--m2-verify-upload"

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(captureUploadArgument)
            || arguments.contains(uploadPendingArgument)
            || arguments.contains(sweepArgument)
            || arguments.contains(verifyArgument) else {
            return
        }

        Task {
            do {
                let result = try await run(arguments: arguments)
                finish(result, exitCode: 0)
            } catch {
                finish("M2_FAILED \(error.localizedDescription)", exitCode: 2)
            }
        }
    }

    private static func run(arguments: [String]) async throws -> String {
        if arguments.contains(captureUploadArgument) {
            return try await captureAndUpload(arguments: arguments)
        }
        if arguments.contains(uploadPendingArgument) {
            return try await uploadPending(arguments: arguments)
        }
        if arguments.contains(sweepArgument) {
            return try await sweep(arguments: arguments)
        }
        if arguments.contains(verifyArgument) {
            return try await verifyUpload(arguments: arguments)
        }
        return "M2_NOOP"
    }

    private static func captureAndUpload(arguments: [String]) async throws -> String {
        let duration = value(after: "--duration", in: arguments).flatMap(TimeInterval.init) ?? 300
        let settings = CaptureSettings.m1Default
        let startedAt = Date()
        let sessionID = value(after: "--session-id", in: arguments) ?? "m2-\(Int(startedAt.timeIntervalSince1970))"
        let outputDirectory = try outputDirectory(for: sessionID, arguments: arguments)
        writeDiagnostic("M2_CAPTURE_STARTED session=\(sessionID) duration=\(duration) output=\(outputDirectory.path)")

        let engine = try CaptureEngine(outputDirectory: outputDirectory, settings: settings)
        try await engine.start()
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        let chunks = engine.stopAndWaitForChunks(timeout: 30)
        guard !chunks.isEmpty else {
            throw M2Error.noChunksWritten
        }

        let endedAt = Date()
        let session = SurveillanceSession(
            id: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            deviceName: Host.current().localizedName ?? "Mac",
            status: .ended
        )
        let pendingChunks = makePendingChunks(sessionID: sessionID, sessionStartedAt: startedAt, chunks: chunks)
        let manifest = M2UploadManifest(
            session: session,
            outputDirectory: outputDirectory,
            requestedDuration: duration,
            chunks: pendingChunks,
            uploadedChunkIDs: []
        )
        let manifestURL = try writePendingManifest(manifest)

        return try await uploadManifest(
            manifestURL: manifestURL,
            simulateOffline: arguments.contains("--simulate-offline")
        )
    }

    private static func uploadPending(arguments: [String]) async throws -> String {
        let manifestURLs: [URL]
        if let path = value(after: "--pending-file", in: arguments) {
            manifestURLs = [URL(fileURLWithPath: path)]
        } else {
            manifestURLs = try pendingManifestURLs()
        }

        guard !manifestURLs.isEmpty else {
            return "M2_PENDING_NONE"
        }

        var uploadedCount = 0
        var pendingCount = 0
        var sessions: [String] = []
        for manifestURL in manifestURLs {
            let line = try await uploadManifest(
                manifestURL: manifestURL,
                simulateOffline: arguments.contains("--simulate-offline")
            )
            sessions.append(line)
            if let count = countValue(named: "uploaded", in: line) {
                uploadedCount += count
            }
            if let count = countValue(named: "pending", in: line) {
                pendingCount += count
            }
        }

        return "M2_PENDING_UPLOAD_DONE files=\(manifestURLs.count) uploaded=\(uploadedCount) pending=\(pendingCount) details=\(sessions.joined(separator: ","))"
    }

    private static func sweep(arguments: [String]) async throws -> String {
        let now = sweepNow(arguments: arguments)
        let store = CloudKitStore()
        let plan = try await store.sweepExpired(now: now)
        return "M2_SWEEP_OK sessionsDeleted=\(plan.sessionsToDelete.count) chunksDeleted=\(plan.chunksToDelete.count) now=\(now.timeIntervalSince1970)"
    }

    private static func uploadManifest(manifestURL: URL, simulateOffline: Bool) async throws -> String {
        var manifest = try JSONDecoder.m2Manifest.decode(
            M2UploadManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let store = CloudKitStore()

        do {
            _ = try await store.saveSession(manifest.recordingSession)
        } catch {
            try writePendingManifest(manifest, to: manifestURL)
            return "M2_UPLOAD_PENDING session=\(manifest.session.id) uploaded=0 pending=\(manifest.chunks.count) manifest=\(manifestURL.path) reason=sessionSaveFailed"
        }

        let cloudClient = CloudKitChunkUploadClient(store: store)
        let client = ClosureChunkUploadClient { chunk in
            if simulateOffline {
                throw ChunkUploadError.offline
            }
            try await cloudClient.upload(chunk)
        }
        let uploader = ChunkUploader(client: client, sleeper: TaskChunkUploadSleeper())
        let result = await uploader.upload(manifest.chunks)
        manifest.uploadedChunkIDs.append(contentsOf: result.uploaded.map(\.id))
        manifest.chunks = result.remaining

        if result.remaining.isEmpty {
            _ = try await store.saveSession(manifest.session)
            try writePendingManifest(manifest, to: manifestURL)
            try? FileManager.default.removeItem(at: manifestURL)
            return "M2_UPLOAD_OK session=\(manifest.session.id) uploaded=\(manifest.uploadedChunkIDs.count) pending=0 output=\(manifest.outputDirectory) manifest=\(outputManifestURL(for: manifest).path)"
        }

        try writePendingManifest(manifest, to: manifestURL)
        return "M2_UPLOAD_PENDING session=\(manifest.session.id) uploaded=\(manifest.uploadedChunkIDs.count) pending=\(manifest.chunks.count) output=\(manifest.outputDirectory) manifest=\(manifestURL.path)"
    }

    private static func verifyUpload(arguments: [String]) async throws -> String {
        let manifestURL = try manifestURL(from: arguments)
        let manifest = try JSONDecoder.m2Manifest.decode(
            M2UploadManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let chunkIDs = Array(Set(manifest.uploadedChunkIDs + manifest.chunks.map(\.id))).sorted()
        let store = CloudKitStore()
        let session = try await store.fetchSession(id: manifest.session.id)
        let chunks = try await store.fetchChunks(ids: chunkIDs)

        return [
            "M2_VERIFY_OK",
            "session=\(session.id)",
            "status=\(session.status.rawValue)",
            "expectedChunks=\(chunkIDs.count)",
            "fetchedChunks=\(chunks.count)",
            "manifest=\(manifestURL.path)"
        ].joined(separator: " ")
    }

    private static func makePendingChunks(
        sessionID: String,
        sessionStartedAt: Date,
        chunks: [CaptureChunk]
    ) -> [PendingChunkUpload] {
        let firstSourceStart = chunks.first?.sourceStartSeconds ?? 0
        return chunks.map { chunk in
            PendingChunkUpload(
                id: "\(sessionID)-chunk-\(String(format: "%04d", chunk.index))",
                sessionID: sessionID,
                index: chunk.index,
                fileURL: URL(fileURLWithPath: chunk.path),
                startedAt: sessionStartedAt.addingTimeInterval(chunk.sourceStartSeconds - firstSourceStart),
                duration: chunk.duration,
                byteCount: chunk.byteCount
            )
        }
    }

    private static func outputDirectory(for sessionID: String, arguments: [String]) throws -> URL {
        if let path = value(after: "--output-dir", in: arguments) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            throw M2Error.appGroupUnavailable
        }
        return appGroupURL.appendingPathComponent("M2Chunks").appendingPathComponent(sessionID)
    }

    @discardableResult
    private static func writePendingManifest(_ manifest: M2UploadManifest) throws -> URL {
        let url = try pendingDirectory().appendingPathComponent("\(manifest.session.id).json")
        try writePendingManifest(manifest, to: url)
        return url
    }

    private static func writePendingManifest(_ manifest: M2UploadManifest, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.m2Manifest.encode(manifest)
        try data.write(to: url, options: .atomic)
        try? data.write(to: outputManifestURL(for: manifest), options: .atomic)
    }

    private static func outputManifestURL(for manifest: M2UploadManifest) -> URL {
        URL(fileURLWithPath: manifest.outputDirectory).appendingPathComponent("m2-upload-manifest.json")
    }

    private static func pendingManifestURLs() throws -> [URL] {
        let directory = try pendingDirectory()
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func pendingDirectory() throws -> URL {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            throw M2Error.appGroupUnavailable
        }
        let directory = appGroupURL.appendingPathComponent("M2Pending")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func manifestURL(from arguments: [String]) throws -> URL {
        if let path = value(after: "--manifest-file", in: arguments) {
            return URL(fileURLWithPath: path)
        }
        if let outputDirectory = value(after: "--output-dir", in: arguments) {
            return URL(fileURLWithPath: outputDirectory, isDirectory: true)
                .appendingPathComponent("m2-upload-manifest.json")
        }
        throw M2Error.manifestRequired
    }

    private static func countValue(named name: String, in line: String) -> Int? {
        line.split(separator: " ").compactMap { part -> Int? in
            let prefix = "\(name)="
            guard part.hasPrefix(prefix) else {
                return nil
            }
            return Int(part.dropFirst(prefix.count))
        }.first
    }

    private static func sweepNow(arguments: [String]) -> Date {
        if let timestamp = value(after: "--now", in: arguments).flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let days = value(after: "--now-offset-days", in: arguments).flatMap(Double.init) {
            return Date().addingTimeInterval(.days(days))
        }
        return Date()
    }

    private static func finish(_ line: String, exitCode: Int32) -> Never {
        print(line)
        fflush(stdout)
        if let outputPath = ProcessInfo.processInfo.environment["M2_RESULT_PATH"] {
            try? line.appending("\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
        }
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) {
            let resultURL = appGroupURL.appendingPathComponent("m2-result.txt")
            try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
        }
        exit(exitCode)
    }

    private static func writeDiagnostic(_ line: String) {
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) {
            let resultURL = appGroupURL.appendingPathComponent("m2-result.txt")
            try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
        }
    }
}

private struct M2UploadManifest: Codable, Equatable, Sendable {
    var session: SurveillanceSession
    var outputDirectory: String
    var requestedDuration: TimeInterval
    var chunks: [PendingChunkUpload]
    var uploadedChunkIDs: [String]

    var recordingSession: SurveillanceSession {
        SurveillanceSession(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: nil,
            deviceName: session.deviceName,
            status: .recording
        )
    }

    init(
        session: SurveillanceSession,
        outputDirectory: URL,
        requestedDuration: TimeInterval,
        chunks: [PendingChunkUpload],
        uploadedChunkIDs: [String]
    ) {
        self.session = session
        self.outputDirectory = outputDirectory.path
        self.requestedDuration = requestedDuration
        self.chunks = chunks
        self.uploadedChunkIDs = uploadedChunkIDs
    }
}

private struct ClosureChunkUploadClient: ChunkUploadClient {
    let uploadClosure: @Sendable (PendingChunkUpload) async throws -> Void

    func upload(_ chunk: PendingChunkUpload) async throws {
        try await uploadClosure(chunk)
    }
}

private enum M2Error: LocalizedError {
    case appGroupUnavailable
    case noChunksWritten
    case manifestRequired

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "App Group container is unavailable"
        case .noChunksWritten:
            "No MP4 chunks were written"
        case .manifestRequired:
            "Pass --manifest-file or --output-dir"
        }
    }
}

private extension JSONEncoder {
    static var m2Manifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var m2Manifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
