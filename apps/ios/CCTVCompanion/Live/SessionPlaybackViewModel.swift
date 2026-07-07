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
    @Published private(set) var isExportingVideo = false
    @Published private(set) var exportStatusText = ""
    @Published private(set) var exportedVideoURL: IdentifiableURL?

    let player: AVPlayer

    private let session: SurveillanceSession
    private let store = CloudKitStore()
    private let encoder = JSONEncoder()
    private var pollingTask: Task<Void, Never>?
    private var loadedLiveChunkIDs: [String] = []
    private var hasPlayableContent = false
    private var playbackActive = true
    private var replayComposition: AVComposition?
    private var escalationDeadline: Date?
    private var escalationTickTask: Task<Void, Never>?

    init(session: SurveillanceSession) {
        self.session = session
        self.player = session.status == .recording ? AVQueuePlayer() : AVPlayer()
    }

    var isLive: Bool {
        session.status == .recording
    }

    var hasReplayableVideo: Bool {
        !isLive && replayComposition != nil
    }

    private var liveQueuePlayer: AVQueuePlayer? {
        player as? AVQueuePlayer
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            await self?.loadLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
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

    private func refresh() async {
        if isLive {
            await refreshEscalationState()
        }

        do {
            let chunks = try await store.fetchChunks(sessionID: session.id, limit: 800)

            if isLive {
                let nextPlaylist = FallbackPlaylist.live(chunks: chunks, now: Date(), targetLatency: 18)
                let playableChunks = nextPlaylist.items.filter { $0.assetFileURL != nil }
                playlist = nextPlaylist
                applyLiveQueue(chunks: playableChunks)
                updateStatus(chunks: chunks, playableChunks: playableChunks)
            } else {
                let nextPlaylist = FallbackPlaylist.replay(chunks: chunks)
                let playableChunks = nextPlaylist.items.filter { $0.assetFileURL != nil }
                playlist = nextPlaylist
                await loadReplayComposition(chunks: nextPlaylist.items)
                updateStatus(chunks: chunks, playableChunks: playableChunks)
            }
        } catch {
            statusText = String(format: String(localized: "playback_status_failed_format"), error.localizedDescription)
        }
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

    /// Polls the Mac's actual escalation state off the Session record (instead of
    /// assuming a dismiss always has an effect) so the cancel button only appears,
    /// and only claims to do something, while an escalation is really pending.
    private func refreshEscalationState() async {
        guard let latestSession = try? await store.fetchSession(id: session.id) else {
            return
        }
        applyEscalationDeadline(latestSession.escalationDeadline)
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
        guard let liveQueuePlayer else {
            return
        }

        let nextIDs = chunks.map(\.id)
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
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return
        }

        var cursor = CMTime.zero
        var insertedAny = false

        for chunk in chunks {
            guard let fileURL = chunk.assetFileURL else {
                continue
            }

            let asset = AVURLAsset(url: fileURL)
            do {
                guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    continue
                }
                let duration = try await asset.load(.duration)
                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: assetTrack,
                    at: cursor
                )
                cursor = cursor + duration
                insertedAny = true
            } catch {
                continue
            }
        }

        guard insertedAny else {
            hasPlayableContent = false
            return
        }

        hasPlayableContent = true
        replayComposition = composition
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
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
