import Foundation

public struct LocalRingBufferEntry: Equatable, Sendable {
    public let id: String
    public let byteCount: Int64
    public let createdAt: Date

    public init(id: String, byteCount: Int64, createdAt: Date) {
        self.id = id
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}

public struct LocalRingBufferPlan: Equatable, Sendable {
    public let entriesToDelete: [LocalRingBufferEntry]
    public let retainedEntries: [LocalRingBufferEntry]

    public var retainedBytes: Int64 {
        retainedEntries.reduce(0) { $0 + $1.byteCount }
    }

    public init(entriesToDelete: [LocalRingBufferEntry], retainedEntries: [LocalRingBufferEntry]) {
        self.entriesToDelete = entriesToDelete
        self.retainedEntries = retainedEntries
    }
}

public struct LocalRingBufferPolicy: Equatable, Sendable {
    public let maxBytes: Int64

    public init(maxBytes: Int64) {
        self.maxBytes = max(0, maxBytes)
    }

    public func plan(for entries: [LocalRingBufferEntry]) -> LocalRingBufferPlan {
        var retainedEntries = entries.sorted { first, second in
            if first.createdAt == second.createdAt {
                return first.id < second.id
            }
            return first.createdAt < second.createdAt
        }
        var entriesToDelete: [LocalRingBufferEntry] = []
        var totalBytes = retainedEntries.reduce(Int64(0)) { $0 + $1.byteCount }

        while totalBytes > maxBytes, let entry = retainedEntries.first {
            entriesToDelete.append(entry)
            retainedEntries.removeFirst()
            totalBytes -= entry.byteCount
        }

        return LocalRingBufferPlan(entriesToDelete: entriesToDelete, retainedEntries: retainedEntries)
    }
}
