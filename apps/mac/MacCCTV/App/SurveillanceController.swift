import CCTVKit
import CloudKit
import Foundation

enum SurveillanceQuality: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var captureSettings: CaptureSettings {
        switch self {
        case .low:
            CaptureSettings(width: 854, height: 480, averageBitRate: 450_000, chunkDuration: 6, maxLocalBytes: 2_000_000_000)
        case .medium:
            .m1Default
        case .high:
            CaptureSettings(width: 1280, height: 720, averageBitRate: 1_300_000, chunkDuration: 6, maxLocalBytes: 2_000_000_000)
        }
    }
}

@MainActor
final class SurveillanceController: ObservableObject {
    @Published private(set) var machine = SurveillanceStateMachine()
    @Published private(set) var statusText = String(localized: "surveillance_status_idle")
    @Published private(set) var hotkeyStatusText = ""
    @Published var selectedShortcut = HotkeyShortcut.controlCommandC {
        didSet {
            registerHotkey()
        }
    }
    @Published var selectedQuality = SurveillanceQuality.medium
    @Published var notificationsEnabled = true

    private let hotkeyManager = HotkeyManager()
    private let sleepBlocker = SleepBlocker()
    private let store = CloudKitStore()
    private let eventDetector = EventDetector()
    private var captureEngine: CaptureEngine?
    private var activeSessionID: String?
    private var activeOutputDirectory: URL?
    private var activeStartedAt: Date?
    private var liveUploadTask: Task<Void, Never>?
    private var broadcastSession: BroadcastSession?
    private var uploadPlanner = ChunkUploadPlanner()
    private var eventRateLimiter = EventRateLimiter(cooldown: 30)
    private var isTransitioning = false

    var state: SurveillanceState {
        machine.state
    }

    var isArmed: Bool {
        if case .armed = machine.state {
            return true
        }
        return false
    }

    var isSirenActive: Bool {
        if case .siren = machine.state {
            return true
        }
        return false
    }

    var menuSystemImage: String {
        switch machine.state {
        case .idle:
            "video"
        case .armed:
            "video.fill"
        case .siren:
            "exclamationmark.triangle.fill"
        }
    }

    init() {
        hotkeyManager.onPressed = { [weak self] in
            Task { @MainActor in
                self?.writeHotkeyDiagnostic("M3_HOTKEY_PRESSED shortcut=\(self?.selectedShortcut.display ?? "unknown")")
                await self?.toggleFromHotkey()
            }
        }
        eventDetector.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.recordSecurityEvent(type: event.type, confidence: event.confidence)
            }
        }
        eventDetector.onDiagnostic = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.writeDiagnostic(line, filename: "m5-detector.txt")
            }
        }
        registerHotkey()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            self?.registerHotkey()
        }
    }

    func toggleFromButton() {
        Task {
            await toggleFromHotkey()
        }
    }

    func registerHotkey() {
        do {
            try hotkeyManager.register(selectedShortcut)
            hotkeyStatusText = String(format: String(localized: "surveillance_hotkey_ready_format"), selectedShortcut.display)
            writeHotkeyDiagnostic("M3_HOTKEY_READY shortcut=\(selectedShortcut.display)")
        } catch {
            hotkeyStatusText = String(format: String(localized: "surveillance_hotkey_failed_format"), error.localizedDescription)
            writeHotkeyDiagnostic("M3_HOTKEY_FAILED shortcut=\(selectedShortcut.display) error=\(error.localizedDescription)")
        }
    }

    private func toggleFromHotkey() async {
        guard !isTransitioning else {
            return
        }

        switch machine.state {
        case .idle:
            await startSurveillance()
        case .armed, .siren:
            await stopSurveillance()
        }
    }

    private func startSurveillance() async {
        isTransitioning = true
        statusText = String(localized: "surveillance_status_starting")
        defer { isTransitioning = false }

        do {
            let accountStatus = try await store.accountStatus()
            guard accountStatus == .available else {
                statusText = String(localized: "surveillance_status_icloud_unavailable")
                return
            }

            let startedAt = Date()
            let sessionID = "m3-\(Int(startedAt.timeIntervalSince1970))"
            let outputDirectory = try Self.outputDirectory(for: sessionID)
            let settings = selectedQuality.captureSettings
            let engine = try CaptureEngine(outputDirectory: outputDirectory, settings: settings)
            engine.onMotionClassification = { [weak self] classification in
                Task { @MainActor [weak self] in
                    await self?.recordMotionClassification(classification)
                }
            }
            let deviceName = Host.current().localizedName ?? "Mac"
            let recordingSession = SurveillanceSession(
                id: sessionID,
                startedAt: startedAt,
                endedAt: nil,
                deviceName: deviceName,
                status: .recording
            )
            try sleepBlocker.start()
            try await engine.start()
            captureEngine = engine
            _ = try await store.saveSession(recordingSession)

            try machine.apply(.arm(startedAt: startedAt))
            activeSessionID = sessionID
            activeOutputDirectory = outputDirectory
            activeStartedAt = startedAt
            uploadPlanner = ChunkUploadPlanner()
            await startBroadcastSession(sessionID: sessionID, engine: engine)
            startLiveUploadLoop(sessionID: sessionID, sessionStartedAt: startedAt, engine: engine)
            eventDetector.start()
            statusText = String(localized: "surveillance_status_armed")
            writeDiagnostic("M3_ARMED session=\(sessionID) output=\(outputDirectory.path)")
        } catch {
            let broadcast = broadcastSession
            broadcastSession = nil
            await broadcast?.stop()
            _ = captureEngine?.stopAndWaitForChunks(timeout: 5)
            sleepBlocker.stop()
            captureEngine = nil
            if error.isCloudKitQuotaExceeded {
                selectedQuality = .low
                statusText = String(localized: "surveillance_status_icloud_quota_low")
            } else {
                statusText = String(format: String(localized: "surveillance_status_failed_format"), error.localizedDescription)
            }
            writeDiagnostic("M3_FAILED \(error.localizedDescription)")
        }
    }

    private func stopSurveillance() async {
        isTransitioning = true
        statusText = String(localized: "surveillance_status_stopping")
        defer { isTransitioning = false }

        guard
            let engine = captureEngine,
            let sessionID = activeSessionID,
            let outputDirectory = activeOutputDirectory,
            let startedAt = activeStartedAt
        else {
            resetToIdle()
            return
        }

        eventDetector.stop()
        await stopBroadcastSession()
        await stopLiveUploadLoop()
        let chunks = engine.stopAndWaitForChunks(timeout: 30)
        sleepBlocker.stop()
        captureEngine = nil
        let endedAt = Date()

        do {
            let session = SurveillanceSession(
                id: sessionID,
                startedAt: startedAt,
                endedAt: endedAt,
                deviceName: Host.current().localizedName ?? "Mac",
                status: .ended
            )
            let allPendingChunks = makePendingChunks(sessionID: sessionID, sessionStartedAt: startedAt, chunks: chunks)
            let pendingChunks = uploadPlanner.pendingUploads(from: allPendingChunks)
            let uploadResult = await ChunkUploader(client: CloudKitChunkUploadClient(store: store)).upload(pendingChunks)
            uploadPlanner.markUploaded(uploadResult.uploaded)
            let uploadedCount = allPendingChunks.count - uploadPlanner.pendingUploads(from: allPendingChunks).count
            _ = try await store.saveSession(session)
            try? LocalChunkStore(maxBytes: selectedQuality.captureSettings.maxLocalBytes).removeUntrackedMP4s(
                in: outputDirectory,
                keeping: Set(chunks.map { URL(fileURLWithPath: $0.path) })
            )
            try machine.apply(.disarm(endedAt: endedAt))
            statusText = String(format: String(localized: "surveillance_status_stopped_format"), chunks.count)
            writeDiagnostic(
                "M3_IDLE session=\(sessionID) chunks=\(chunks.count) uploaded=\(uploadedCount) pending=\(uploadResult.remaining.count) finalUploaded=\(uploadResult.uploaded.count) output=\(outputDirectory.path)"
            )
            clearActiveSession()
        } catch {
            resetToIdle()
            statusText = String(format: String(localized: "surveillance_status_failed_format"), error.localizedDescription)
            writeDiagnostic("M3_FAILED \(error.localizedDescription)")
        }
    }

    private func startBroadcastSession(sessionID: String, engine: CaptureEngine) async {
        let channel = CloudKitSignalingChannel(sessionID: sessionID, localSender: .mac, store: store)
        let broadcast = BroadcastSession(
            sessionID: sessionID,
            channel: channel,
            diagnostics: { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.appendDiagnostic(line, filename: "m6-result.txt")
                }
            }
        )
        broadcastSession = broadcast
        engine.onVideoSampleBuffer = { [weak broadcast] sampleBuffer in
            broadcast?.ingest(sampleBuffer: sampleBuffer)
        }

        do {
            try await broadcast.start()
            writeDiagnostic("M6_BROADCAST_STARTED session=\(sessionID)", filename: "m6-result.txt")
        } catch {
            writeDiagnostic(
                "M6_BROADCAST_FAILED session=\(sessionID) error=\(error.localizedDescription)",
                filename: "m6-result.txt"
            )
        }
    }

    private func stopBroadcastSession() async {
        captureEngine?.onVideoSampleBuffer = nil
        let broadcast = broadcastSession
        broadcastSession = nil
        await broadcast?.stop()
    }

    private func recordMotionClassification(_ classification: MotionClassification) async {
        switch classification {
        case .noMotion:
            return
        case let .personMotion(confidence):
            await recordSecurityEvent(type: .personMotion, confidence: confidence)
        case let .deviceMotion(confidence):
            await recordSecurityEvent(type: .deviceMotion, confidence: confidence)
        }
    }

    private func recordSecurityEvent(type: SecurityEventType, confidence: Double) async {
        guard notificationsEnabled,
              case .armed = machine.state,
              let sessionID = activeSessionID else {
            return
        }

        let occurredAt = Date()
        guard eventRateLimiter.shouldRecord(type, at: occurredAt) else {
            return
        }

        if type == .lidClose || type == .powerDisconnect {
            await flushCurrentChunkForEvent()
        }

        let event = SecurityEvent(
            id: "\(sessionID)-event-\(type.rawValue)-\(Int(occurredAt.timeIntervalSince1970 * 1000))",
            sessionID: sessionID,
            type: type,
            occurredAt: occurredAt,
            confidence: confidence
        )

        do {
            _ = try await store.saveEvent(event)
            writeDiagnostic(
                "M5_EVENT session=\(sessionID) type=\(type.rawValue) confidence=\(String(format: "%.2f", confidence)) occurredAt=\(Int(occurredAt.timeIntervalSince1970))",
                filename: "m5-event-result.txt"
            )
        } catch {
            writeDiagnostic(
                "M5_EVENT_FAILED session=\(sessionID) type=\(type.rawValue) error=\(error.localizedDescription)",
                filename: "m5-event-result.txt"
            )
        }
    }

    private func flushCurrentChunkForEvent() async {
        guard let engine = captureEngine,
              let sessionID = activeSessionID,
              let startedAt = activeStartedAt else {
            return
        }
        _ = engine.flushCurrentChunk(timeout: 5)
        await uploadFinishedChunks(sessionID: sessionID, sessionStartedAt: startedAt, engine: engine)
    }

    private func startLiveUploadLoop(sessionID: String, sessionStartedAt: Date, engine: CaptureEngine) {
        liveUploadTask?.cancel()
        liveUploadTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    break
                }
                guard !Task.isCancelled else {
                    break
                }
                await self?.uploadFinishedChunks(sessionID: sessionID, sessionStartedAt: sessionStartedAt, engine: engine)
            }
        }
    }

    private func stopLiveUploadLoop() async {
        guard let task = liveUploadTask else {
            return
        }
        liveUploadTask = nil
        task.cancel()
        await task.value
    }

    private func uploadFinishedChunks(sessionID: String, sessionStartedAt: Date, engine: CaptureEngine) async {
        let chunks = engine.finishedChunksSnapshot()
        guard !chunks.isEmpty else {
            return
        }

        let allPendingChunks = makePendingChunks(sessionID: sessionID, sessionStartedAt: sessionStartedAt, chunks: chunks)
        let pendingChunks = uploadPlanner.pendingUploads(from: allPendingChunks)
        guard !pendingChunks.isEmpty else {
            return
        }

        let uploadResult = await ChunkUploader(client: CloudKitChunkUploadClient(store: store)).upload(pendingChunks)
        uploadPlanner.markUploaded(uploadResult.uploaded)
        let uploadedCount = allPendingChunks.count - uploadPlanner.pendingUploads(from: allPendingChunks).count
        writeDiagnostic(
            "M4_LIVE_UPLOAD session=\(sessionID) finished=\(chunks.count) uploaded=\(uploadedCount) batch=\(uploadResult.uploaded.count) pending=\(uploadResult.remaining.count)"
        )
    }

    private func resetToIdle() {
        eventDetector.stop()
        captureEngine?.onVideoSampleBuffer = nil
        let broadcast = broadcastSession
        broadcastSession = nil
        Task {
            await broadcast?.stop()
        }
        liveUploadTask?.cancel()
        liveUploadTask = nil
        sleepBlocker.stop()
        captureEngine = nil
        clearActiveSession()
        uploadPlanner = ChunkUploadPlanner()
        eventRateLimiter.reset()
        machine = SurveillanceStateMachine()
        statusText = String(localized: "surveillance_status_idle")
    }

    private func clearActiveSession() {
        activeSessionID = nil
        activeOutputDirectory = nil
        activeStartedAt = nil
        eventRateLimiter.reset()
    }

    private static func outputDirectory(for sessionID: String) throws -> URL {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            throw SurveillanceControllerError.appGroupUnavailable
        }
        return appGroupURL.appendingPathComponent("M3Chunks").appendingPathComponent(sessionID)
    }

    private func makePendingChunks(
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

    private func writeDiagnostic(_ line: String) {
        writeDiagnostic(line, filename: "m3-result.txt")
    }

    private func writeHotkeyDiagnostic(_ line: String) {
        writeDiagnostic(line, filename: "m3-hotkey.txt")
    }

    private func writeDiagnostic(_ line: String, filename: String) {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent(filename)
        try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private func appendDiagnostic(_ line: String, filename: String) {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent(filename)
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

private enum SurveillanceControllerError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "App Group container is unavailable"
        }
    }
}

private extension Error {
    var isCloudKitQuotaExceeded: Bool {
        if let cloudKitError = self as? CKError {
            return cloudKitError.code == .quotaExceeded
        }

        let nsError = self as NSError
        return nsError.domain == CKError.errorDomain && nsError.code == CKError.Code.quotaExceeded.rawValue
    }
}
