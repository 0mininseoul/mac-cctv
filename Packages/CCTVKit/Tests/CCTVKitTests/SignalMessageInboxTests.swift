import XCTest
@testable import CCTVKit

final class SignalMessageInboxTests: XCTestCase {
    func testIncomingMessagesIgnoreOwnSenderOtherSessionsAndOldMessages() {
        let base = Date(timeIntervalSince1970: 1_000)
        let inbox = SignalMessageInbox(receiver: .mac)
        let messages = [
            signal(id: "old", sessionID: "s1", sender: .ios, createdAt: base.addingTimeInterval(-1)),
            signal(id: "own", sessionID: "s1", sender: .mac, createdAt: base.addingTimeInterval(1)),
            signal(id: "other-session", sessionID: "s2", sender: .ios, createdAt: base.addingTimeInterval(2)),
            signal(id: "newer", sessionID: "s1", sender: .ios, createdAt: base.addingTimeInterval(3)),
            signal(id: "new", sessionID: "s1", sender: .ios, createdAt: base.addingTimeInterval(1))
        ]

        let incoming = inbox.incoming(messages, sessionID: "s1", after: base)

        XCTAssertEqual(incoming.map(\.id), ["new", "newer"])
    }

    func testCursorAdvancesToLatestIncomingMessageDate() {
        let base = Date(timeIntervalSince1970: 1_000)
        let inbox = SignalMessageInbox(receiver: .ios)
        let messages = [
            signal(id: "first", sender: .mac, createdAt: base.addingTimeInterval(1)),
            signal(id: "second", sender: .mac, createdAt: base.addingTimeInterval(4))
        ]

        let cursor = inbox.nextCursor(after: base, processing: messages)

        XCTAssertEqual(cursor, base.addingTimeInterval(4))
    }

    func testCursorDoesNotMoveWhenNoIncomingMessagesWereProcessed() {
        let base = Date(timeIntervalSince1970: 1_000)
        let inbox = SignalMessageInbox(receiver: .ios)

        let cursor = inbox.nextCursor(after: base, processing: [])

        XCTAssertEqual(cursor, base)
    }

    private func signal(
        id: String,
        sessionID: String = "s1",
        sender: SignalSender,
        createdAt: Date
    ) -> SignalMessage {
        SignalMessage(
            id: id,
            sessionID: sessionID,
            kind: .offer,
            payload: "{}",
            sender: sender,
            createdAt: createdAt
        )
    }
}
