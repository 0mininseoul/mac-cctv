import Foundation

public struct EventRateLimiter: Sendable {
    private let cooldown: TimeInterval
    private var lastRecordedAt: [SecurityEventType: Date] = [:]

    public init(cooldown: TimeInterval = 30) {
        self.cooldown = cooldown
    }

    public mutating func shouldRecord(_ type: SecurityEventType, at date: Date = Date()) -> Bool {
        if let lastRecordedAt = lastRecordedAt[type],
           date.timeIntervalSince(lastRecordedAt) < cooldown {
            return false
        }

        lastRecordedAt[type] = date
        return true
    }

    public mutating func reset() {
        lastRecordedAt.removeAll()
    }
}
