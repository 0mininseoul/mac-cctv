import Foundation

public struct RetentionSession: Equatable, Sendable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus

    public init(id: String, startedAt: Date, endedAt: Date?, status: SessionStatus) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }
}

public struct RetentionChunk: Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let startedAt: Date

    public init(id: String, sessionID: String, startedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
    }
}

public struct RetentionPlan: Equatable, Sendable {
    public let sessionsToDelete: [RetentionSession]
    public let chunksToDelete: [RetentionChunk]

    public init(sessionsToDelete: [RetentionSession], chunksToDelete: [RetentionChunk]) {
        self.sessionsToDelete = sessionsToDelete
        self.chunksToDelete = chunksToDelete
    }
}

public struct RetentionPolicy: Equatable, Sendable {
    public let retentionInterval: TimeInterval

    public init(retentionInterval: TimeInterval = .days(7)) {
        self.retentionInterval = retentionInterval
    }

    public func plan(sessions: [RetentionSession], chunks: [RetentionChunk], now: Date = Date()) -> RetentionPlan {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let expiredSessions = sessions.filter { session in
            guard session.status != .recording, let endedAt = session.endedAt else {
                return false
            }
            return endedAt <= cutoff
        }
        let expiredSessionIDs = Set(expiredSessions.map(\.id))
        let expiredChunks = chunks.filter { expiredSessionIDs.contains($0.sessionID) }

        return RetentionPlan(sessionsToDelete: expiredSessions, chunksToDelete: expiredChunks)
    }
}

public extension TimeInterval {
    static func days(_ count: Double) -> TimeInterval {
        count * 24 * 60 * 60
    }
}
