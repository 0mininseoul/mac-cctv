import Foundation

public enum SessionStatus: String, CaseIterable, Codable, Sendable {
    case recording
    case ended
    case interrupted
}

public struct SurveillanceSession: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var deviceName: String
    public var status: SessionStatus
    public var escalationDeadline: Date?

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date? = nil,
        deviceName: String,
        status: SessionStatus,
        escalationDeadline: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.deviceName = deviceName
        self.status = status
        self.escalationDeadline = escalationDeadline
    }
}

public struct VideoChunk: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var sessionID: String
    public var index: Int
    public var startedAt: Date
    public var duration: TimeInterval
    public var assetFileURL: URL?
    public var byteCount: Int64

    public init(
        id: String,
        sessionID: String,
        index: Int,
        startedAt: Date,
        duration: TimeInterval,
        assetFileURL: URL? = nil,
        byteCount: Int64 = 0
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.startedAt = startedAt
        self.duration = duration
        self.assetFileURL = assetFileURL
        self.byteCount = byteCount
    }
}

public enum SecurityEventType: String, CaseIterable, Sendable {
    case inputTouch
    case powerDisconnect
    case lidClose
    case personMotion
    case deviceMotion
    case sirenAuto
    case sirenManual
    case sirenEscalation
    case escalationDismissed
}

public struct SecurityEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public var sessionID: String
    public var type: SecurityEventType
    public var occurredAt: Date
    public var confidence: Double

    public init(id: String, sessionID: String, type: SecurityEventType, occurredAt: Date, confidence: Double) {
        self.id = id
        self.sessionID = sessionID
        self.type = type
        self.occurredAt = occurredAt
        self.confidence = confidence
    }
}

public enum SignalKind: String, CaseIterable, Sendable {
    case offer
    case answer
    case ice
    case sirenCommand
    case viewerReady
    case dismissEscalation
}

public enum SignalSender: String, CaseIterable, Sendable {
    case mac
    case ios
}

public struct SignalMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public var sessionID: String
    public var kind: SignalKind
    public var payload: String
    public var sender: SignalSender
    public var createdAt: Date

    public init(
        id: String,
        sessionID: String,
        kind: SignalKind,
        payload: String,
        sender: SignalSender,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.payload = payload
        self.sender = sender
        self.createdAt = createdAt
    }
}
