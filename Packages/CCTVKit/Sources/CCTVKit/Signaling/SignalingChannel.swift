import Foundation

public protocol SignalingChannel {
    func send(_ message: SignalMessage) async throws
    func receive(after date: Date) async throws -> [SignalMessage]
}

public final class CloudKitSignalingChannel: SignalingChannel, @unchecked Sendable {
    private let sessionID: String
    private let store: CloudKitStore
    private let inbox: SignalMessageInbox

    public init(sessionID: String, localSender: SignalSender, store: CloudKitStore = CloudKitStore()) {
        self.sessionID = sessionID
        self.store = store
        self.inbox = SignalMessageInbox(receiver: localSender)
    }

    public func send(_ message: SignalMessage) async throws {
        _ = try await store.saveSignal(message)
    }

    public func receive(after date: Date) async throws -> [SignalMessage] {
        let messages = try await store.fetchSignals(sessionID: sessionID, after: date)
        return inbox.incoming(messages, sessionID: sessionID, after: date)
    }
}
