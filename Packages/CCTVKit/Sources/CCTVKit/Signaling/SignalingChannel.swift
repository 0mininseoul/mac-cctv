import Foundation

public protocol SignalingChannel {
    func send(_ message: SignalMessage) async throws
    func receive(after date: Date) async throws -> [SignalMessage]
}

