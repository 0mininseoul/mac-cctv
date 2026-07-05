import CCTVKit
import Foundation

@MainActor
final class EventNavigationRouter: ObservableObject {
    static let shared = EventNavigationRouter()

    @Published var sessionPath: [String] = []

    private let store = CloudKitStore()

    private init() {}

    func open(eventRecordName: String) async {
        do {
            let event = try await store.fetchEvent(id: eventRecordName)
            sessionPath = [event.sessionID]
            UserDefaults.standard.removeObject(forKey: Self.pendingEventRecordNameKey)
            writeDiagnostic("M5_DEEPLINK_OPENED event=\(event.id) session=\(event.sessionID) type=\(event.type.rawValue)")
        } catch {
            UserDefaults.standard.set(eventRecordName, forKey: Self.pendingEventRecordNameKey)
            writeDiagnostic("M5_DEEPLINK_FAILED event=\(eventRecordName) error=\(error.localizedDescription)")
        }
    }

    func openPendingEventIfNeeded() async {
        guard let recordName = UserDefaults.standard.string(forKey: Self.pendingEventRecordNameKey) else {
            return
        }
        await open(eventRecordName: recordName)
    }

    static let pendingEventRecordNameKey = "lastOpenedEventRecordName"

    private func writeDiagnostic(_ line: String) {
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier
        ) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent("m5-event-result.txt")
        try? line.appending("\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }
}
