import CCTVKit
import Foundation

enum EscalationDismissSender {
    static func send(sessionID: String) async throws {
        let store = CloudKitStore()
        let channel = CloudKitSignalingChannel(sessionID: sessionID, localSender: .ios, store: store)
        let payload = DismissEscalationSignalPayload(requestedAt: Date())
        let data = try JSONEncoder().encode(payload)
        try await channel.send(
            SignalMessage(
                id: "\(sessionID)-ios-dismiss-escalation-\(UUID().uuidString)",
                sessionID: sessionID,
                kind: .dismissEscalation,
                payload: String(decoding: data, as: UTF8.self),
                sender: .ios,
                createdAt: Date()
            )
        )
    }
}
