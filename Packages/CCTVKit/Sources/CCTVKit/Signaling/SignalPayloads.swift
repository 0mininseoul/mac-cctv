import Foundation

public struct SessionDescriptionSignalPayload: Codable, Equatable, Sendable {
    public var type: String
    public var sdp: String

    public init(type: String, sdp: String) {
        self.type = type
        self.sdp = sdp
    }
}

public struct IceCandidateSignalPayload: Codable, Equatable, Sendable {
    public var sdp: String
    public var sdpMLineIndex: Int32
    public var sdpMid: String?

    public init(sdp: String, sdpMLineIndex: Int32, sdpMid: String?) {
        self.sdp = sdp
        self.sdpMLineIndex = sdpMLineIndex
        self.sdpMid = sdpMid
    }
}

public struct SirenCommandSignalPayload: Codable, Equatable, Sendable {
    public var requestedAt: Date

    public init(requestedAt: Date) {
        self.requestedAt = requestedAt
    }
}

/// Sent by a viewer (iOS) whenever it opens or re-opens a live session, so the
/// broadcaster (Mac) knows to (re)negotiate a fresh WebRTC offer — covers both
/// the very first connection and reconnects after the viewer backgrounds/returns.
public struct ViewerReadySignalPayload: Codable, Equatable, Sendable {
    public var requestedAt: Date

    public init(requestedAt: Date) {
        self.requestedAt = requestedAt
    }
}

public struct DismissEscalationSignalPayload: Codable, Equatable, Sendable {
    public var requestedAt: Date

    public init(requestedAt: Date) {
        self.requestedAt = requestedAt
    }
}

/// iOS → Mac: silence an active siren while keeping surveillance armed.
public struct SilenceSirenSignalPayload: Codable, Equatable, Sendable {
    public var requestedAt: Date

    public init(requestedAt: Date) {
        self.requestedAt = requestedAt
    }
}

/// Mac → iOS: the Mac's transient live state, re-sent whenever it changes so the
/// phone can mirror the escalation countdown, siren on/off, and session-ended
/// transition. Carried over the existing Signal record's string columns, so it
/// needs no CloudKit schema change (unlike a new Session field, which production
/// rejects with "Cannot create or modify field ... in production schema").
public struct MacLiveStateSignalPayload: Codable, Equatable, Sendable {
    public var escalationDeadline: Date?
    public var sirenActive: Bool
    public var sessionEnded: Bool
    public var sentAt: Date

    public init(
        escalationDeadline: Date?,
        sirenActive: Bool,
        sessionEnded: Bool,
        sentAt: Date = Date()
    ) {
        self.escalationDeadline = escalationDeadline
        self.sirenActive = sirenActive
        self.sessionEnded = sessionEnded
        self.sentAt = sentAt
    }
}
