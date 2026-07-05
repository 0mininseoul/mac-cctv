import AVFoundation
import CCTVKit
import Darwin
import Foundation
import UIKit

enum M4PlaybackLaunchHandler {
    static let autoplayLatestArgument = "--m4-autoplay-latest"

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(autoplayLatestArgument) else {
            return
        }

        writeDiagnostic("M4_PLAYBACK_STARTED \(arguments.joined(separator: " "))")
        Task {
            do {
                let result = try await withTimeout(seconds: 60) {
                    try await run(arguments: arguments)
                }
                finish(result, exitCode: 0)
            } catch {
                finish("M4_PLAYBACK_FAILED \(error.localizedDescription)", exitCode: 2)
            }
        }
    }

    private static func run(arguments: [String]) async throws -> String {
        let store = CloudKitStore()
        _ = try? await store.sweepExpired()
        let sessions = try await store.fetchSessions(limit: 50)
        let session: SurveillanceSession

        if let sessionID = value(after: "--session-id", in: arguments) {
            session = try await store.fetchSession(id: sessionID)
        } else if let latest = sessions.first {
            session = latest
        } else {
            throw M4PlaybackError.noSessions
        }

        let chunks = try await store.fetchChunks(sessionID: session.id, limit: 800)
        let playlist = session.status == .recording
            ? FallbackPlaylist.live(chunks: chunks, now: Date(), targetLatency: 18)
            : FallbackPlaylist.replay(chunks: chunks)
        let playableCount = playlist.items.filter { $0.assetFileURL != nil }.count
        let playbackProbe = try await verifyPlayback(items: playlist.items)
        let latency = playlist.initialLatency.map { String(format: "%.1f", $0) } ?? "none"
        let mode = session.status == .recording ? "live" : "replay"

        return [
            "M4_PLAYBACK_OK",
            "session=\(session.id)",
            "status=\(session.status.rawValue)",
            "mode=\(mode)",
            "sessions=\(sessions.count)",
            "chunks=\(chunks.count)",
            "queued=\(playlist.items.count)",
            "playable=\(playableCount)",
            "decoded=\(playbackProbe.decodedCount)",
            "played=1",
            "advance=\(String(format: "%.2f", playbackProbe.advancedSeconds))",
            "missing=\(playlist.missingRanges.count)",
            "latency=\(latency)"
        ].joined(separator: " ")
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    @MainActor
    private static func verifyPlayback(items: [VideoChunk]) async throws -> PlaybackProbe {
        let assetURLs = Array(items.compactMap(\.assetFileURL).prefix(3))
        guard !assetURLs.isEmpty else {
            throw M4PlaybackError.noPlayableChunks
        }

        let urls = try stagedPlaybackURLs(for: assetURLs)
        let playerItems = urls.map { AVPlayerItem(url: $0) }

        let player = AVQueuePlayer(items: playerItems)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        let playbackWindow = makePlaybackWindow(player: player)
        player.play()
        defer {
            player.pause()
            playbackWindow?.isHidden = true
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let seconds = player.currentTime().seconds
            if seconds.isFinite, seconds >= 0.25 {
                return PlaybackProbe(decodedCount: playerItems.count, advancedSeconds: seconds)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw M4PlaybackError.playbackDidNotAdvance
    }

    private static func stagedPlaybackURLs(for assetURLs: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("M4Playback", isDirectory: true)
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var stagedURLs: [URL] = []
        for (index, assetURL) in assetURLs.enumerated() {
            guard fileManager.fileExists(atPath: assetURL.path) else {
                continue
            }
            let stagedURL = directory.appendingPathComponent(String(format: "chunk-%04d.mp4", index))
            try fileManager.copyItem(at: assetURL, to: stagedURL)
            stagedURLs.append(stagedURL)
        }

        guard !stagedURLs.isEmpty else {
            throw M4PlaybackError.noPlayableChunks
        }
        return stagedURLs
    }

    @MainActor
    private static func makePlaybackWindow(player: AVPlayer) -> UIWindow? {
        let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = windowScene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        viewController.view.layer.addSublayer(layer)
        window.rootViewController = viewController
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        return window
    }

    private static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw M4PlaybackError.timeout
            }
            guard let result = try await group.next() else {
                throw M4PlaybackError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private static func finish(_ line: String, exitCode: Int32) -> Never {
        print(line)
        fflush(stdout)
        writeDiagnostic(line)
        exit(exitCode)
    }

    private static func writeDiagnostic(_ line: String) {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent("m4-result.txt")
        try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private struct PlaybackProbe: Sendable {
        let decodedCount: Int
        let advancedSeconds: Double
    }

    private enum M4PlaybackError: LocalizedError {
        case noSessions
        case noPlayableChunks
        case playbackDidNotAdvance
        case timeout

        var errorDescription: String? {
            switch self {
            case .noSessions:
                "No surveillance sessions were found"
            case .noPlayableChunks:
                "No playable MP4 chunks were available"
            case .playbackDidNotAdvance:
                "AVQueuePlayer did not advance during playback verification"
            case .timeout:
                "Timed out waiting for M4 playback verification"
            }
        }
    }
}
