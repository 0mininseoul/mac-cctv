import AVFoundation
import CCTVKit
import Foundation

@MainActor
final class SessionPlaybackViewModel: ObservableObject {
    @Published private(set) var statusText = ""
    @Published private(set) var playlist = FallbackPlaylist()
    @Published private(set) var isSendingSirenCommand = false
    @Published private(set) var sirenCommandStatusText = ""

    let player = AVQueuePlayer()

    private let session: SurveillanceSession
    private let store = CloudKitStore()
    private let encoder = JSONEncoder()
    private var pollingTask: Task<Void, Never>?
    private var loadedChunkIDs: [String] = []
    private var playbackActive = true

    init(session: SurveillanceSession) {
        self.session = session
    }

    var isLive: Bool {
        session.status == .recording
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
            if !loadedChunkIDs.isEmpty {
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
            let nextPlaylist = isLive
                ? FallbackPlaylist.live(chunks: chunks, now: Date(), targetLatency: 18)
                : FallbackPlaylist.replay(chunks: chunks)
            let playableChunks = nextPlaylist.items.filter { $0.assetFileURL != nil }

            playlist = nextPlaylist
            applyQueue(chunks: playableChunks)
            updateStatus(chunks: chunks, playableChunks: playableChunks)
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

    private func applyQueue(chunks: [VideoChunk]) {
        let nextIDs = chunks.map(\.id)
        guard nextIDs != loadedChunkIDs else {
            if !nextIDs.isEmpty {
                player.play()
            }
            return
        }

        if nextIDs.starts(with: loadedChunkIDs) {
            append(chunks: Array(chunks.dropFirst(loadedChunkIDs.count)))
        } else {
            player.removeAllItems()
            append(chunks: chunks)
        }

        loadedChunkIDs = nextIDs
        if playbackActive, !nextIDs.isEmpty {
            player.play()
        }
    }

    private func append(chunks: [VideoChunk]) {
        for chunk in chunks {
            guard let fileURL = chunk.assetFileURL else {
                continue
            }
            player.insert(AVPlayerItem(url: fileURL), after: nil)
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
