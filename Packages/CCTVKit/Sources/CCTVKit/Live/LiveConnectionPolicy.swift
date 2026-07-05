import Foundation

public enum LiveFallbackReason: Equatable, Sendable {
    case timeout
    case connectionFailed
}

public enum LiveViewingMode: Equatable, Sendable {
    case connecting(elapsed: TimeInterval)
    case realtime
    case delayedFallback(reason: LiveFallbackReason)
}

public struct LiveConnectionPolicy: Equatable, Sendable {
    public var timeout: TimeInterval
    public var connectedFrameGrace: TimeInterval

    public init(timeout: TimeInterval = 10, connectedFrameGrace: TimeInterval = 5) {
        self.timeout = timeout
        self.connectedFrameGrace = connectedFrameGrace
    }

    public func mode(
        startedAt: Date,
        now: Date,
        hasReceivedRemoteVideo: Bool,
        peerConnectionConnectedAt: Date? = nil,
        peerConnectionFailed: Bool
    ) -> LiveViewingMode {
        if peerConnectionFailed {
            return .delayedFallback(reason: .connectionFailed)
        }

        if hasReceivedRemoteVideo {
            return .realtime
        }

        let elapsed = max(0, now.timeIntervalSince(startedAt))
        if let peerConnectionConnectedAt {
            let frameWait = max(0, now.timeIntervalSince(peerConnectionConnectedAt))
            if frameWait < connectedFrameGrace {
                return .connecting(elapsed: elapsed)
            }
            return .delayedFallback(reason: .timeout)
        }

        if elapsed >= timeout {
            return .delayedFallback(reason: .timeout)
        }

        return .connecting(elapsed: elapsed)
    }
}
