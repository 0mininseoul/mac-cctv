import AVFoundation
import CCTVKit
import Foundation

@MainActor
final class SessionPlaybackViewModel: ObservableObject {
    @Published private(set) var statusText = ""
    @Published private(set) var playlist = FallbackPlaylist()
    @Published private(set) var isSendingSirenCommand = false
    @Published private(set) var sirenCommandStatusText = ""

    let player: AVPlayer

    private let session: SurveillanceSession
    private let store = CloudKitStore()
    private let encoder = JSONEncoder()
    private var pollingTask: Task<Void, Never>?
    private var loadedLiveChunkIDs: [String] = []
    private var hasPlayableContent = false
    private var playbackActive = true

    init(session: SurveillanceSession) {
        self.session = session
        self.player = session.status == .recording ? AVQueuePlayer() : AVPlayer()
    }

    var isLive: Bool {
        session.status == .recording
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
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
        if playbackActive {
            player.play()
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
