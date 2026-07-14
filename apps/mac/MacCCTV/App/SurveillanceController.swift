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
    @Published var sirenWarningText = "" {
        didSet {
            UserDefaults.standard.set(sirenWarningText, forKey: Self.sirenWarningTextKey)
        }
    }
    @Published private(set) var isEscalationPending = false
    @Published private(set) var escalationSecondsRemaining = 0

    private let hotkeyManager = HotkeyManager()
    private let sleepBlocker = SleepBlocker()
    private let store = CloudKitStore()
    private let eventDetector = EventDetector()
    private let sirenController = SirenController()
    private let autoSirenPolicy = AutoSirenTriggerPolicy()
    private var captureEngine: CaptureEngine?
    private var activeSessionID: String?
    private var activeOutputDirectory: URL?
    private var activeStartedAt: Date?
    private var liveUploadTask: Task<Void, Never>?
    private var broadcastSession: BroadcastSession?
    private var uploadPlanner = ChunkUploadPlanner()
    private var eventRateLimiter = EventRateLimiter(cooldown: 30)
    private var autoSirenEvidence: [AutoSirenEvidence] = []
    private var autoSirenTriggered = false
    private var isTransitioning = false
    private var escalationTask: Task<Void, Never>?
    private var escalationActive = false
    private var escalationDeadline: Date?

    private static let sirenWarningTextKey = "siren.warningText"
    private static var defaultSirenWarningText: String {
        String(localized: "siren_warning_title")
    }

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
        sirenWarningText = UserDefaults.standard.string(forKey: Self.sirenWarningTextKey) ?? Self.defaultSirenWarningText
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
        eventDetector.onSystemWake = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleSystemWake()
            }
        }
        registerHotkey()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            self?.registerHotkey()
        }

        // Catch-up: re-upload chunks left on disk when a session's upload didn't finish
        // (failed end-of-session upload, or a force-quit), then delete only the local
        // copies that upload successfully — so no recorded evidence is lost (PRD M4).
        if let chunksBaseDirectory = try? Self.chunksBaseDirectory() {
            let store = store
            Task {
                await ChunkCatchUpUploader(store: store, baseDirectory: chunksBaseDirectory).run()
            }
        }

        // 7-day retention sweep on the normal launch path — previously only ran behind
        // the `--m2-sweep` flag. Fire-and-forget, matching iOS's library-load sweep
        // (PRD M5).
        let sweepStore = store
        Task {
            _ = try? await sweepStore.sweepExpired()
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

    func resetSirenWarningText() {
        sirenWarningText = Self.defaultSirenWarningText
    }

    private func toggleFromHotkey() async {
        guard !isTransitioning else {
            return
        }

        switch machine.state {
        case .idle:
            await startSurveillance()
        case .armed, .siren:
            await stopSurveillance(finalStatus: .ended)
        }
    }

    private func handleSystemWake() async {
        guard !isTransitioning, machine.state != .idle else {
            return
        }
        writeDiagnostic("M9_WAKE_AUTO_STOP session=\(activeSessionID ?? "unknown")")
        await stopSurveillance(finalStatus: .interrupted)
    }

    private func reconcileOrphanedSessions() async {
        do {
            let sessions = try await store.fetchSessions(limit: 20)
            for var session in sessions where session.status == .recording {
                session.status = .interrupted
                session.endedAt = session.endedAt ?? Date()
                _ = try? await store.saveSession(session)
                writeDiagnostic("M9_ORPHAN_SESSION_CLOSED session=\(session.id)")
            }
        } catch {
            writeDiagnostic("M9_ORPHAN_SESSION_CHECK_FAILED error=\(error.localizedDescription)")
        }
    }

    private func startSurveillance() async {
        isTransitioning = true
        statusText = String(localized: "surveillance_status_starting")
        defer { isTransitioning = false }

        do {
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
            // Kick the camera off immediately (the user has already committed to
            // arming) so its ~2s hardware warmup overlaps the iCloud readiness
            // round-trips below instead of stacking after them — the camera turns on
            // ~1-2s sooner. No pre-arm warmup: the camera only starts once armed.
            async let cameraStarted: Void = engine.start()

            let accountStatus = try await store.accountStatus()
            guard accountStatus == .available else {
                try? await cameraStarted
                _ = engine.stopAndWaitForChunks(timeout: 5)
                sleepBlocker.stop()
                statusText = String(localized: "surveillance_status_icloud_unavailable")
                return
            }

            await reconcileOrphanedSessions()

            try await cameraStarted
            captureEngine = engine
            _ = try await store.saveSession(recordingSession)

            try machine.apply(.arm(startedAt: startedAt))
            activeSessionID = sessionID
            activeOutputDirectory = outputDirectory
            activeStartedAt = startedAt
            uploadPlanner = ChunkUploadPlanner()
            autoSirenEvidence.removeAll()
            autoSirenTriggered = false
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

    private func stopSurveillance(finalStatus: SessionStatus) async {
        isTransitioning = true
        statusText = String(localized: "surveillance_status_stopping")
        defer { isTransitioning = false }
        resetEscalationState()
        stopSirenIfNeeded(reason: "stop")

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
        // Tell any watching phone the session is over *before* tearing down the
        // channel, so it switches to replay instead of sitting on a black live
        // surface with a "missing chunks" list.
        await broadcastMacState(sessionEnded: true)
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
                status: finalStatus
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
            },
            onSirenCommand: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.triggerSiren(source: .manual)
                }
            },
            onDismissEscalation: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.cancelEscalation(reason: "remote")
                }
            },
            onSilenceSiren: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.silenceSiren(reason: "remote")
                }
            },
            onEndSession: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.writeDiagnostic("M12_END_SESSION_APPLIED session=\(sessionID)", filename: "m6-result.txt")
                    await self?.stopSurveillance(finalStatus: .ended)
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
            let occurredAt = Date()
            rememberAutoSirenEvidence(type: .deviceMotion, confidence: confidence, occurredAt: occurredAt)
            if await evaluateAutoSiren(now: occurredAt) {
                return
            }
            await recordSecurityEvent(type: .deviceMotion, confidence: confidence, occurredAt: occurredAt)
        }
    }

    private func recordSecurityEvent(type: SecurityEventType, confidence: Double, occurredAt: Date = Date()) async {
        if type == .inputTouch || type == .powerDisconnect {
            rememberAutoSirenEvidence(type: type, confidence: confidence, occurredAt: occurredAt)
            _ = await evaluateAutoSiren(now: occurredAt)
        }

        // Evidence-preservation flush runs *before* the notification/rate-limit gates:
        // a lid close or power disconnect can immediately precede shutdown, so the
        // in-progress chunk must be finalized and pushed to the cloud right away even
        // if notifications are off or the event is rate-limited (PRD M8). Those gates
        // only affect the event *record* saved below. (flushCurrentChunkForEvent
        // self-guards on there being an active recording, so this no-ops when idle.)
        if type == .lidClose || type == .powerDisconnect {
            await flushCurrentChunkForEvent()
        }

        guard notificationsEnabled,
              isRecordingEventState,
              let sessionID = activeSessionID else {
            return
        }

        guard eventRateLimiter.shouldRecord(type, at: occurredAt) else {
            return
        }

        await saveSecurityEvent(type: type, confidence: confidence, occurredAt: occurredAt, sessionID: sessionID)
    }

    private var isRecordingEventState: Bool {
        switch machine.state {
        case .armed, .siren:
            return true
        case .idle:
            return false
        }
    }

    private func rememberAutoSirenEvidence(type: SecurityEventType, confidence: Double, occurredAt: Date) {
        guard case .armed = machine.state else {
            return
        }
        guard type == .deviceMotion || type == .inputTouch || type == .powerDisconnect else {
            return
        }

        autoSirenEvidence.append(
            AutoSirenEvidence(type: type, occurredAt: occurredAt, confidence: confidence)
        )
        let oldestAllowed = occurredAt.addingTimeInterval(-45)
        autoSirenEvidence.removeAll { $0.occurredAt < oldestAllowed }
    }

    private func evaluateAutoSiren(now: Date) async -> Bool {
        guard !autoSirenTriggered,
              case .armed = machine.state,
              let activeStartedAt else {
            return false
        }

        switch autoSirenPolicy.decision(armedAt: activeStartedAt, now: now, evidence: autoSirenEvidence) {
        case .trigger:
            resetEscalationState()
            autoSirenTriggered = true
            await triggerSiren(source: .automatic, triggeredAt: now)
            return true
        case .escalate:
            await beginEscalation(at: now)
            return false
        case .notifyOnly:
            return false
        }
    }

    private func beginEscalation(at occurredAt: Date) async {
        guard !escalationActive, let sessionID = activeSessionID else {
            return
        }

        escalationActive = true
        isEscalationPending = true
        escalationSecondsRemaining = Int(autoSirenPolicy.escalationTimeout)
        escalationDeadline = occurredAt.addingTimeInterval(autoSirenPolicy.escalationTimeout)
        statusText = String(localized: "surveillance_status_escalation_pending")
        appendDiagnostic("M10_ESCALATION_STARTED session=\(sessionID)", filename: "m10-escalation-result.txt")
        await saveSecurityEvent(type: .sirenEscalation, confidence: 1, occurredAt: occurredAt, sessionID: sessionID)
        startEscalationCountdown()
        await broadcastMacState()
    }

    private func startEscalationCountdown() {
        escalationTask?.cancel()
        escalationTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                let finished = await self?.tickEscalation() ?? true
                if finished {
                    return
                }
            }
        }
    }

    private func tickEscalation() async -> Bool {
        guard escalationActive else {
            return true
        }
        escalationSecondsRemaining -= 1
        guard escalationSecondsRemaining > 0 else {
            await escalationTimedOut()
            return true
        }
        return false
    }

    private func escalationTimedOut() async {
        guard escalationActive else {
            return
        }
        let sessionID = activeSessionID ?? "unknown"
        resetEscalationState()
        appendDiagnostic("M10_ESCALATION_TIMEOUT session=\(sessionID)", filename: "m10-escalation-result.txt")
        await triggerSiren(source: .automatic)
    }

    private func cancelEscalation(reason: String) async {
        guard resetEscalationState() else {
            return
        }
        await broadcastMacState()
        let sessionID = activeSessionID
        appendDiagnostic("M10_ESCALATION_DISMISSED session=\(sessionID ?? "unknown") reason=\(reason)", filename: "m10-escalation-result.txt")
        if case .armed = machine.state {
            statusText = String(localized: "surveillance_status_armed")
        }
        if let sessionID {
            await saveSecurityEvent(type: .escalationDismissed, confidence: 1, occurredAt: Date(), sessionID: sessionID)
        }
    }

    @discardableResult
    private func resetEscalationState() -> Bool {
        guard escalationActive else {
            return false
        }
        escalationTask?.cancel()
        escalationTask = nil
        escalationActive = false
        isEscalationPending = false
        escalationSecondsRemaining = 0
        escalationDeadline = nil
        return true
    }

    /// iOS-initiated remote silence: stops the alarm but keeps surveillance armed,
    /// unlike the hotkey/stop which ends the whole session. Clears accumulated
    /// evidence so a stale reading doesn't immediately re-trigger, while allowing a
    /// genuinely new event to escalate again.
    private func silenceSiren(reason: String) async {
        guard case .siren = machine.state else {
            return
        }
        do {
            try machine.apply(.silenceSiren(silencedAt: Date()))
        } catch {
            return
        }
        stopSirenIfNeeded(reason: reason)
        autoSirenTriggered = false
        autoSirenEvidence.removeAll()
        statusText = String(localized: "surveillance_status_armed")
        appendDiagnostic("M7_SIREN_SILENCED session=\(activeSessionID ?? "unknown") reason=\(reason)", filename: "m7-result.txt")
        await broadcastMacState()
    }

    /// Pushes the Mac's transient live state to any connected/upcoming viewer over
    /// the signaling channel. Replaces the earlier `Session.escalationDeadline`
    /// field approach, which failed in production because CloudKit rejects writes
    /// to fields not already deployed in the production schema. A new SignalKind
    /// value reuses the existing Signal `kind` column, so it needs no schema deploy.
    private func broadcastMacState(sessionEnded: Bool = false) async {
        await broadcastSession?.sendMacState(
            escalationDeadline: escalationDeadline,
            sirenActive: sirenController.isActive,
            sessionEnded: sessionEnded
        )
    }

    private func triggerSiren(source: SirenTriggerSource, triggeredAt: Date = Date()) async {
        guard case let .armed(startedAt) = machine.state,
              let sessionID = activeSessionID else {
            return
        }

        do {
            try machine.apply(.triggerSiren(triggeredAt: triggeredAt))
        } catch {
            writeDiagnostic(
                "M7_SIREN_FAILED session=\(sessionID) source=\(source.rawValue) error=\(error.localizedDescription)",
                filename: "m7-result.txt"
            )
            return
        }

        autoSirenTriggered = true
        sirenController.start(warningText: effectiveSirenWarningText)
        statusText = String(localized: "surveillance_status_siren")
        writeDiagnostic(
            "M7_SIREN_STARTED session=\(sessionID) source=\(source.rawValue) elapsed=\(String(format: "%.2f", triggeredAt.timeIntervalSince(startedAt)))",
            filename: "m7-result.txt"
        )
        await saveSecurityEvent(
            type: source.eventType,
            confidence: 1,
            occurredAt: triggeredAt,
            sessionID: sessionID
        )
        await broadcastMacState()
    }

    private func saveSecurityEvent(
        type: SecurityEventType,
        confidence: Double,
        occurredAt: Date,
        sessionID: String
    ) async {
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
        resetEscalationState()
        stopSirenIfNeeded(reason: "reset")
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
        autoSirenEvidence.removeAll()
        autoSirenTriggered = false
        machine = SurveillanceStateMachine()
        statusText = String(localized: "surveillance_status_idle")
    }

    private func clearActiveSession() {
        activeSessionID = nil
        activeOutputDirectory = nil
        activeStartedAt = nil
        eventRateLimiter.reset()
        autoSirenEvidence.removeAll()
        autoSirenTriggered = false
    }

    private var effectiveSirenWarningText: String {
        let trimmedText = sirenWarningText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? Self.defaultSirenWarningText : trimmedText
    }

    private func stopSirenIfNeeded(reason: String) {
        guard sirenController.isActive else {
            return
        }
        let sessionID = activeSessionID ?? "unknown"
        sirenController.stop()
        writeDiagnostic("M7_SIREN_STOPPED session=\(sessionID) reason=\(reason)", filename: "m7-result.txt")
    }

    private static func outputDirectory(for sessionID: String) throws -> URL {
        try chunksBaseDirectory().appendingPathComponent(sessionID)
    }

    private static func chunksBaseDirectory() throws -> URL {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            throw SurveillanceControllerError.appGroupUnavailable
        }
        return appGroupURL.appendingPathComponent("M3Chunks")
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

private enum SirenTriggerSource: String {
    case automatic = "auto"
    case manual

    var eventType: SecurityEventType {
        switch self {
        case .automatic:
            .sirenAuto
        case .manual:
            .sirenManual
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
