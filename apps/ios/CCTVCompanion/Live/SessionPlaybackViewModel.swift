import AVFoundation
import CCTVKit
import Foundation

@MainActor
final class SessionPlaybackViewModel: ObservableObject {
    @Published private(set) var statusText = ""
    @Published private(set) var playlist = FallbackPlaylist()
    @Published private(set) var isSendingSirenCommand = false
    @Published private(set) var sirenCommandStatusText = ""
    @Published private(set) var isSendingEscalationDismiss = false
    @Published private(set) var escalationDismissStatusText = ""
    @Published private(set) var isEscalationPending = false
    @Published private(set) var escalationSecondsRemaining = 0
    @Published private(set) var isSirenActive = false
    @Published private(set) var isSendingSilenceSiren = false
    @Published private(set) var silenceSirenStatusText = ""
    @Published private(set) var isSendingEndSession = false
    @Published private(set) var endSessionStatusText = ""
    /// Flips true when the Mac reports the session ended while we were watching
    /// live, so the view can swap the black live surface for replay playback.
    @Published private(set) var endedRemotely = false
    @Published private(set) var isExportingVideo = false
    @Published private(set) var exportStatusText = ""
    @Published private(set) var exportedVideoURL: IdentifiableURL?
    /// True while an ended session's replay is still being fetched/composed and has
    /// nothing playable yet — drives a loading overlay so the wait isn't a blank screen.
    @Published private(set) var isPreparingReplay = false
    /// Whether the live delayed-playback queue currently has any footage. When the
    /// realtime stream has given up and this is still false, the Mac is unreachable
    /// (asleep / offline) rather than merely slow — the view says so.
    @Published private(set) var liveHasContent = false

    let player: AVQueuePlayer

    private let session: SurveillanceSession
    private let store = CloudKitStore()
    private let channel: SignalingChannel
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pollingTask: Task<Void, Never>?
    private var macStatePollTask: Task<Void, Never>?
    private var macStateCursor = Date.distantPast
    private var loadedLiveChunkIDs: [String] = []
    private var hasPlayableContent = false
    private var playbackActive = true
    private var replayComposition: AVComposition?
    private var escalationDeadline: Date?
    private var escalationTickTask: Task<Void, Never>?

    init(session: SurveillanceSession) {
        self.session = session
        self.player = AVQueuePlayer()
        self.channel = CloudKitSignalingChannel(sessionID: session.id, localSender: .ios, store: store)
    }

    /// Live only while the session record says recording *and* the Mac hasn't told
    /// us mid-stream that it ended.
    var isLive: Bool {
        session.status == .recording && !endedRemotely
    }

    var hasReplayableVideo: Bool {
        !isLive && replayComposition != nil
    }

    private var liveQueuePlayer: AVQueuePlayer {
        player
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            await self?.loadLoop()
        }

        // Mirror the Mac's live state (escalation countdown, siren on/off, session
        // ended) off the signaling channel. Polled fast and separately from the 3s
        // chunk loop because a 10s countdown would be mostly gone before that loop
        // gets to it.
        if isLive {
            macStatePollTask = Task { [weak self] in
                await self?.macStatePollLoop()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        macStatePollTask?.cancel()
        macStatePollTask = nil
        escalationTickTask?.cancel()
        escalationTickTask = nil
        player.pause()
    }

    func setPlaybackActive(_ active: Bool) {
        playbackActive = active
        if active {
            if hasPlayableContent {
                player.play()
            }
        } else {
            player.pause()
        }
    }

    func sendSirenCommand() {
        guard isLive, !isSendingSirenCommand else {
            return
        }

        isSendingSirenCommand = true
        sirenCommandStatusText = String(localized: "siren_command_sending")

        Task { [weak self] in
            await self?.sendSirenCommandNow()
        }
    }

    func markRealtimeSirenCommandSent() {
        sirenCommandStatusText = String(localized: "siren_command_sent")
    }

    func sendEscalationDismiss() {
        guard isLive, !isSendingEscalationDismiss else {
            return
        }

        isSendingEscalationDismiss = true
        escalationDismissStatusText = String(localized: "escalation_dismiss_sending")

        Task { [weak self] in
            await self?.sendEscalationDismissNow()
        }
    }

    func sendSilenceSiren() {
        guard isLive, !isSendingSilenceSiren else {
            return
        }

        isSendingSilenceSiren = true
        silenceSirenStatusText = String(localized: "silence_siren_sending")

        Task { [weak self] in
            await self?.sendSilenceSirenNow()
        }
    }

    func sendEndSession() {
        guard isLive, !isSendingEndSession else {
            return
        }

        isSendingEndSession = true
        endSessionStatusText = String(localized: "end_session_sending")

        Task { [weak self] in
            await self?.sendEndSessionNow()
        }
    }

    func exportVideoForSharing() {
        guard let replayComposition, !isExportingVideo else {
            return
        }

        isExportingVideo = true
        exportStatusText = String(localized: "export_video_in_progress")

        Task { [weak self] in
            await self?.performExport(composition: replayComposition)
        }
    }

    func dismissExportedVideo() {
        exportedVideoURL = nil
    }

    private func loadLoop() async {
        await refresh()

        guard isLive else {
            return
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refresh()
        }
    }

    private func macStatePollLoop() async {
        while !Task.isCancelled {
            await refreshMacState()
            if endedRemotely {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func refresh() async {
        if isLive {
            await refreshLive()
        } else {
            await refreshReplay()
        }
    }

    private func refreshLive() async {
        do {
            let chunks = try await store.fetchChunks(sessionID: session.id, limit: 800)
            let nextPlaylist = FallbackPlaylist.live(chunks: chunks, now: Date(), targetLatency: 18)
            let playableChunks = nextPlaylist.items.filter { $0.assetFileURL != nil }
            playlist = nextPlaylist
            applyLiveQueue(chunks: playableChunks)
            updateStatus(chunks: chunks, playableChunks: playableChunks)
        } catch {
            statusText = String(format: String(localized: "playback_status_failed_format"), error.localizedDescription)
        }
    }

    /// Ended-session replay. Instead of re-downloading every chunk's video on each
    /// open (the old path fetched all assets up front — ~seconds even for locally
    /// cached recordings), do a fast metadata query first, then download only the
    /// chunks not already in the local cache. A session watched live or re-opened
    /// plays effectively instantly; a first-time one downloads only what's missing.
    private func refreshReplay() async {
        // Show the loading overlay only on the first load (when nothing plays yet);
        // later refreshes (e.g. catching late-flushed chunks) shouldn't flash it.
        let showLoading = !hasPlayableContent
        if showLoading {
            isPreparingReplay = true
        }
        defer { isPreparingReplay = false }

        do {
            let metadata = try await store.fetchChunkMetadata(sessionID: session.id, limit: 800)
            let resolved = try await resolveReplayChunks(metadata)
            let nextPlaylist = FallbackPlaylist.replay(chunks: resolved)
            let playableChunks = nextPlaylist.items.filter { $0.assetFileURL != nil }
            playlist = nextPlaylist
            await loadReplayComposition(chunks: nextPlaylist.items)
            updateStatus(chunks: resolved, playableChunks: playableChunks)
        } catch {
            statusText = String(format: String(localized: "playback_status_failed_format"), error.localizedDescription)
        }
    }

    /// Merge freshly-downloaded video assets for the not-yet-cached chunks back into
    /// the ordered metadata list. Chunks already cached locally (assetFileURL set by
    /// the metadata fetch) need no network at all.
    private func resolveReplayChunks(_ metadata: [VideoChunk]) async throws -> [VideoChunk] {
        let uncachedIDs = metadata.filter { $0.assetFileURL == nil }.map(\.id)
        guard !uncachedIDs.isEmpty else {
            return metadata
        }
        let downloaded = try await store.fetchChunks(ids: uncachedIDs)
        let downloadedByID = Dictionary(downloaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return metadata.map { downloadedByID[$0.id] ?? $0 }
    }

    private func sendSirenCommandNow() async {
        defer {
            isSendingSirenCommand = false
        }

        do {
            let channel = CloudKitSignalingChannel(sessionID: session.id, localSender: .ios, store: store)
            let payload = SirenCommandSignalPayload(requestedAt: Date())
            let data = try encoder.encode(payload)
            try await channel.send(
                SignalMessage(
                    id: "\(session.id)-ios-siren-\(UUID().uuidString)",
                    sessionID: session.id,
                    kind: .sirenCommand,
                    payload: String(decoding: data, as: UTF8.self),
                    sender: .ios,
                    createdAt: Date()
                )
            )
            sirenCommandStatusText = String(localized: "siren_command_sent")
        } catch {
            sirenCommandStatusText = String(
                format: String(localized: "siren_command_failed_format"),
                error.localizedDescription
            )
        }
    }

    private func sendEscalationDismissNow() async {
        defer {
            isSendingEscalationDismiss = false
        }

        do {
            try await EscalationDismissSender.send(sessionID: session.id)
            escalationDismissStatusText = String(localized: "escalation_dismiss_sent")
        } catch {
            escalationDismissStatusText = String(
                format: String(localized: "escalation_dismiss_failed_format"),
                error.localizedDescription
            )
        }
    }

    private func sendSilenceSirenNow() async {
        defer {
            isSendingSilenceSiren = false
        }

        do {
            let payload = SilenceSirenSignalPayload(requestedAt: Date())
            let data = try encoder.encode(payload)
            try await channel.send(
                SignalMessage(
                    id: "\(session.id)-ios-silence-\(UUID().uuidString)",
                    sessionID: session.id,
                    kind: .silenceSiren,
                    payload: String(decoding: data, as: UTF8.self),
                    sender: .ios,
                    createdAt: Date()
                )
            )
            silenceSirenStatusText = String(localized: "silence_siren_sent")
        } catch {
            silenceSirenStatusText = String(
                format: String(localized: "silence_siren_failed_format"),
                error.localizedDescription
            )
        }
    }

    private func sendEndSessionNow() async {
        defer {
            isSendingEndSession = false
        }

        do {
            let payload = EndSessionSignalPayload(requestedAt: Date())
            let data = try encoder.encode(payload)
            try await channel.send(
                SignalMessage(
                    id: "\(session.id)-ios-end-\(UUID().uuidString)",
                    sessionID: session.id,
                    kind: .endSession,
                    payload: String(decoding: data, as: UTF8.self),
                    sender: .ios,
                    createdAt: Date()
                )
            )
            endSessionStatusText = String(localized: "end_session_sent")
        } catch {
            endSessionStatusText = String(
                format: String(localized: "end_session_failed_format"),
                error.localizedDescription
            )
        }
    }

    /// Reads the Mac's broadcast live state off the signaling channel (escalation
    /// countdown, siren on/off, session ended). Signals persist, so opening the
    /// view mid-event still catches the latest state from history via the
    /// distant-past initial cursor.
    private func refreshMacState() async {
        guard let messages = try? await channel.receive(after: macStateCursor) else {
            return
        }
        let macStates = messages.filter { $0.kind == .macState }
        if let latest = macStates.max(by: { $0.createdAt < $1.createdAt }),
           let payload = try? decoder.decode(MacLiveStateSignalPayload.self, from: Data(latest.payload.utf8)) {
            applyMacState(payload)
        }
        // Advance past everything seen so we don't reprocess (macState carries
        // absolute state, so skipping intermediate ones is fine).
        macStateCursor = messages.map(\.createdAt).max() ?? macStateCursor
    }

    private func applyMacState(_ state: MacLiveStateSignalPayload) {
        isSirenActive = state.sirenActive
        applyEscalationDeadline(state.escalationDeadline)
        if state.sessionEnded, !endedRemotely {
            handleSessionEndedRemotely()
        }
    }

    private func handleSessionEndedRemotely() {
        endedRemotely = true
        isEscalationPending = false
        isSirenActive = false
        escalationSecondsRemaining = 0
        escalationTickTask?.cancel()
        escalationTickTask = nil
        macStatePollTask?.cancel()
        macStatePollTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        loadedLiveChunkIDs = []
        player.removeAllItems()
        // The session just finished; load its recording as replay. The Mac may still
        // be flushing its last chunks, so refresh a few times to catch them rather
        // than freezing on a partial (missing-range) view.
        pollingTask = Task { [weak self] in
            for _ in 0..<8 {
                await self?.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func applyEscalationDeadline(_ deadline: Date?) {
        guard deadline != escalationDeadline else {
            return
        }
        escalationDeadline = deadline

        if let deadline, deadline > Date() {
            isEscalationPending = true
            startEscalationTicking()
        } else {
            isEscalationPending = false
            escalationSecondsRemaining = 0
            escalationTickTask?.cancel()
            escalationTickTask = nil
        }
    }

    private func startEscalationTicking() {
        escalationTickTask?.cancel()
        escalationTickTask = Task { [weak self] in
            while true {
                let shouldContinue = await self?.tickEscalationDisplay() ?? false
                guard shouldContinue else {
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickEscalationDisplay() -> Bool {
        guard let escalationDeadline else {
            return false
        }
        let remaining = Int(ceil(escalationDeadline.timeIntervalSinceNow))
        guard remaining > 0 else {
            isEscalationPending = false
            escalationSecondsRemaining = 0
            self.escalationDeadline = nil
            return false
        }
        escalationSecondsRemaining = remaining
        return true
    }

    /// Live/fallback playback keeps queueing individual chunk files as they arrive —
    /// the set of chunks keeps growing, so there's no fixed timeline to build a
    /// composition from yet. Replay (below) is the one-shot, fixed-timeline case.
    private func applyLiveQueue(chunks: [VideoChunk]) {
        let nextIDs = chunks.map(\.id)
        liveHasContent = !nextIDs.isEmpty
        guard nextIDs != loadedLiveChunkIDs else {
            if !nextIDs.isEmpty {
                liveQueuePlayer.play()
            }
            return
        }

        if nextIDs.starts(with: loadedLiveChunkIDs) {
            appendLive(chunks: Array(chunks.dropFirst(loadedLiveChunkIDs.count)), to: liveQueuePlayer)
        } else {
            liveQueuePlayer.removeAllItems()
            appendLive(chunks: chunks, to: liveQueuePlayer)
        }

        loadedLiveChunkIDs = nextIDs
        hasPlayableContent = !nextIDs.isEmpty
        if playbackActive, !nextIDs.isEmpty {
            liveQueuePlayer.play()
        }
    }

    private func appendLive(chunks: [VideoChunk], to queuePlayer: AVQueuePlayer) {
        for chunk in chunks {
            guard let fileURL = chunk.assetFileURL else {
                continue
            }
            queuePlayer.insert(AVPlayerItem(url: fileURL), after: nil)
        }
    }

    /// Builds one AVMutableComposition from the session's chunk files, time-ordered,
    /// so replay gets a single scrubbable timeline with correct total duration instead
    /// of the queue-of-separate-items behavior live playback uses. `insertTimeRange`
    /// references the original chunk files directly — no re-encoding, no merged file
    /// written to disk. Chunks that are missing or fail to load are skipped; whatever
    /// chunks do load are inserted back-to-back with no gap in the timeline.
    private func loadReplayComposition(chunks: [VideoChunk]) async {
        let playableChunks = chunks.filter { $0.assetFileURL != nil }
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return
        }

        var cursor = CMTime.zero
        var insertedCount = 0

        // Load each chunk's duration concurrently (the main per-chunk latency), then
        // stitch them into the composition in index order. Only Sendable values (URL,
        // CMTime) cross the task boundary; the actual track insert stays serial since
        // AVMutableComposition mutation must not run concurrently.
        let durations: [(index: Int, url: URL, duration: CMTime)] = await withTaskGroup(
            of: (Int, URL, CMTime)?.self
        ) { group in
            for (index, chunk) in playableChunks.enumerated() {
                guard let fileURL = chunk.assetFileURL else {
                    continue
                }
                group.addTask {
                    let asset = AVURLAsset(url: fileURL)
                    guard (try? await asset.loadTracks(withMediaType: .video))?.first != nil,
                          let duration = try? await asset.load(.duration) else {
                        return nil
                    }
                    return (index, fileURL, duration)
                }
            }
            var collected: [(index: Int, url: URL, duration: CMTime)] = []
            for await result in group {
                if let result {
                    collected.append((index: result.0, url: result.1, duration: result.2))
                }
            }
            return collected
        }
        .sorted { $0.index < $1.index }

        for item in durations {
            let asset = AVURLAsset(url: item.url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            do {
                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: item.duration),
                    of: assetTrack,
                    at: cursor
                )
                cursor = cursor + item.duration
                insertedCount += 1
            } catch {
                continue
            }
        }

        IOSDiagnostics.append(
            "M4_REPLAY session=\(session.id) chunks=\(chunks.count) playable=\(playableChunks.count) composed=\(insertedCount)",
            filename: "m4-replay-result.txt"
        )

        if insertedCount > 0 {
            hasPlayableContent = true
            replayComposition = composition
            player.removeAllItems()
            player.insert(AVPlayerItem(asset: composition), after: nil)
            if playbackActive {
                player.play()
            }
            return
        }

        // Composition produced nothing (e.g. chunk MP4s that AVComposition can't
        // stitch), but there may still be individually playable files — fall back to
        // queueing them directly, which is more lenient, so replay isn't just black.
        guard !playableChunks.isEmpty else {
            hasPlayableContent = false
            return
        }

        replayComposition = nil
        player.removeAllItems()
        for chunk in playableChunks {
            guard let fileURL = chunk.assetFileURL else {
                continue
            }
            player.insert(AVPlayerItem(url: fileURL), after: nil)
        }
        hasPlayableContent = true
        IOSDiagnostics.append(
            "M4_REPLAY_QUEUE_FALLBACK session=\(session.id) queued=\(playableChunks.count)",
            filename: "m4-replay-result.txt"
        )
        if playbackActive {
            player.play()
        }
    }

    /// The only place this feature re-encodes anything: a one-shot merged export
    /// for the share sheet, triggered explicitly by the user. Playback itself never
    /// re-encodes or writes a merged file (see loadReplayComposition).
    private func performExport(composition: AVComposition) async {
        defer {
            isExportingVideo = false
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            exportStatusText = String(localized: "export_video_failed")
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(session.id)-export.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exportSession.exportAsynchronously {
                    switch exportSession.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: ExportVideoError.cancelled)
                    default:
                        continuation.resume(throwing: exportSession.error ?? ExportVideoError.unknown)
                    }
                }
            }
            exportStatusText = ""
            exportedVideoURL = IdentifiableURL(url: outputURL)
        } catch {
            exportStatusText = String(
                format: String(localized: "export_video_failed_format"),
                error.localizedDescription
            )
        }
    }

    private func updateStatus(chunks: [VideoChunk], playableChunks: [VideoChunk]) {
        if chunks.isEmpty {
            statusText = String(localized: "playback_status_empty")
        } else if playableChunks.isEmpty {
            statusText = String(localized: "playback_status_waiting_for_assets")
        } else {
            statusText = ""
        }
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private enum ExportVideoError: LocalizedError {
    case unknown
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unknown:
            "Video export failed"
        case .cancelled:
            "Video export was cancelled"
        }
    }
}
