import Foundation

public struct SignalMessageInbox: Equatable, Sendable {
    public var receiver: SignalSender

    public init(receiver: SignalSender) {
        self.receiver = receiver
    }

    public func incoming(_ messages: [SignalMessage], sessionID: String, after cursor: Date) -> [SignalMessage] {
        messages
            .filter { message in
                message.sessionID == sessionID
                    && message.sender != receiver
                    && message.createdAt > cursor
            }
            .sorted { first, second in
                if first.createdAt == second.createdAt {
                    return first.id < second.id
                }
                return first.createdAt < second.createdAt
            }
    }

    public func nextCursor(after cursor: Date, processing messages: [SignalMessage]) -> Date {
        messages.map(\.createdAt).max() ?? cursor
    }
}
