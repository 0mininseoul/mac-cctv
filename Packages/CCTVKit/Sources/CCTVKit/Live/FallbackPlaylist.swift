import Foundation

public struct FallbackPlaylist: Equatable, Sendable {
    public struct MissingRange: Equatable, Sendable {
        public let startIndex: Int
        public let endIndex: Int

        public init(startIndex: Int, endIndex: Int) {
            self.startIndex = startIndex
            self.endIndex = endIndex
        }
    }

    public let items: [VideoChunk]
    public let missingRanges: [MissingRange]
    public let liveStartIndex: Int?
    public let initialLatency: TimeInterval?

    public init(
        items: [VideoChunk] = [],
        missingRanges: [MissingRange] = [],
        liveStartIndex: Int? = nil,
        initialLatency: TimeInterval? = nil
    ) {
        self.items = items
        self.missingRanges = missingRanges
        self.liveStartIndex = liveStartIndex
        self.initialLatency = initialLatency
    }

    public static func replay(chunks: [VideoChunk]) -> FallbackPlaylist {
        let sortedChunks = sortedUniqueChunks(chunks)
        return FallbackPlaylist(
            items: sortedChunks,
            missingRanges: missingRanges(in: sortedChunks)
        )
    }

    public static func live(
        chunks: [VideoChunk],
        now: Date = Date(),
        targetLatency: TimeInterval = 18
    ) -> FallbackPlaylist {
        let sortedChunks = sortedUniqueChunks(chunks)
        guard let startPosition = liveStartPosition(
            in: sortedChunks,
            targetDate: now.addingTimeInterval(-targetLatency)
        ) else {
            return FallbackPlaylist()
        }

        let contiguousItems = Array(contiguousSuffix(from: startPosition, in: sortedChunks))
        let startChunk = sortedChunks[startPosition]

        return FallbackPlaylist(
            items: contiguousItems,
            missingRanges: missingRanges(in: sortedChunks),
            liveStartIndex: startChunk.index,
            initialLatency: now.timeIntervalSince(startChunk.startedAt)
        )
    }

    private static func sortedUniqueChunks(_ chunks: [VideoChunk]) -> [VideoChunk] {
        let chunksByIndex = Dictionary(grouping: chunks, by: \.index).compactMapValues { duplicates in
            duplicates.min { first, second in
                if first.startedAt == second.startedAt {
                    return first.id < second.id
                }
                return first.startedAt < second.startedAt
            }
        }

        return chunksByIndex.values.sorted { first, second in
            if first.index == second.index {
                return first.id < second.id
            }
            return first.index < second.index
        }
    }

    private static func missingRanges(in chunks: [VideoChunk]) -> [MissingRange] {
        guard chunks.count > 1 else {
            return []
        }

        return zip(chunks, chunks.dropFirst()).compactMap { previous, next in
            let missingStart = previous.index + 1
            let missingEnd = next.index - 1
            guard missingStart <= missingEnd else {
                return nil
            }
            return MissingRange(startIndex: missingStart, endIndex: missingEnd)
        }
    }

    private static func liveStartPosition(in chunks: [VideoChunk], targetDate: Date) -> Int? {
        guard !chunks.isEmpty else {
            return nil
        }

        var position = 0
        for candidate in chunks.indices where chunks[candidate].startedAt <= targetDate {
            position = candidate
        }
        return position
    }

    private static func contiguousSuffix(from startPosition: Int, in chunks: [VideoChunk]) -> ArraySlice<VideoChunk> {
        var endPosition = startPosition
        while endPosition + 1 < chunks.count, chunks[endPosition + 1].index == chunks[endPosition].index + 1 {
            endPosition += 1
        }
        return chunks[startPosition...endPosition]
    }
}
