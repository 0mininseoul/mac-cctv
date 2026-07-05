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
