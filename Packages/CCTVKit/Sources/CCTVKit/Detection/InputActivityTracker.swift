import Foundation

public struct InputActivityTracker: Equatable, Sendable {
    public var minimumActivityAdvance: TimeInterval
    private var lastActivityAt: Date?

    public init(minimumActivityAdvance: TimeInterval = 0.25) {
        self.minimumActivityAdvance = minimumActivityAdvance
    }

    public mutating func observe(now: Date, idleSeconds: TimeInterval) -> Bool {
        guard idleSeconds.isFinite, idleSeconds < .greatestFiniteMagnitude else {
            return false
        }

        let normalizedIdleSeconds = max(0, idleSeconds)
        let observedActivityAt = now.addingTimeInterval(-normalizedIdleSeconds)

        guard let lastActivityAt else {
            self.lastActivityAt = observedActivityAt
            return false
        }

        guard observedActivityAt.timeIntervalSince(lastActivityAt) >= minimumActivityAdvance else {
            return false
        }

        self.lastActivityAt = observedActivityAt
        return true
    }
}
