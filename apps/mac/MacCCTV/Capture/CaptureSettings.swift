import Foundation

struct CaptureSettings: Sendable {
    var width: Int
    var height: Int
    var averageBitRate: Int
    var chunkDuration: TimeInterval
    var maxLocalBytes: Int64

    static let m1Default = CaptureSettings(
        width: 1280,
        height: 720,
        averageBitRate: 800_000,
        chunkDuration: 6,
        maxLocalBytes: 2_000_000_000
    )
}

struct CaptureChunk: Codable, Equatable, Sendable {
    var index: Int
    var path: String
    var sourceStartSeconds: Double
    var sourceEndSeconds: Double
    var duration: Double
    var byteCount: Int64
}

struct CaptureManifest: Codable, Equatable, Sendable {
    var sessionID: String
    var outputDirectory: String
    var requestedDuration: Double
    var settings: ManifestSettings
    var chunks: [CaptureChunk]

    struct ManifestSettings: Codable, Equatable, Sendable {
        var width: Int
        var height: Int
        var averageBitRate: Int
        var chunkDuration: Double
    }

    init(
        sessionID: String,
        outputDirectory: URL,
        requestedDuration: TimeInterval,
        settings: CaptureSettings,
        chunks: [CaptureChunk]
    ) {
        self.sessionID = sessionID
        self.outputDirectory = outputDirectory.path
        self.requestedDuration = requestedDuration
        self.settings = ManifestSettings(
            width: settings.width,
            height: settings.height,
            averageBitRate: settings.averageBitRate,
            chunkDuration: settings.chunkDuration
        )
        self.chunks = chunks
    }
}
