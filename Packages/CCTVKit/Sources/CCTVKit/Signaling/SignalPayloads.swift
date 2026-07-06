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
