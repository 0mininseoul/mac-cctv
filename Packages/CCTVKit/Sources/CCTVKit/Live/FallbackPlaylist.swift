import Foundation

public struct FallbackPlaylist: Equatable, Sendable {
    public var chunks: [VideoChunk]

    public init(chunks: [VideoChunk] = []) {
        self.chunks = chunks
    }
}
