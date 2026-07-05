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

    public init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    public func mode(
        startedAt: Date,
        now: Date,
        hasReceivedRemoteVideo: Bool,
        peerConnectionFailed: Bool
    ) -> LiveViewingMode {
        if peerConnectionFailed {
            return .delayedFallback(reason: .connectionFailed)
        }

        if hasReceivedRemoteVideo {
            return .realtime
        }

        let elapsed = max(0, now.timeIntervalSince(startedAt))
        if elapsed >= timeout {
            return .delayedFallback(reason: .timeout)
        }

        return .connecting(elapsed: elapsed)
    }
}
