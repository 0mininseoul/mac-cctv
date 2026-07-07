import CCTVKit
import Foundation

struct SessionListItem: Identifiable, Equatable {
    let session: SurveillanceSession
    let eventCount: Int

    var id: String {
        session.id
    }

    var isLive: Bool {
        session.status == .recording
    }

    var duration: TimeInterval? {
        guard let endedAt = session.endedAt else {
            return nil
        }
        return endedAt.timeIntervalSince(session.startedAt)
    }
}

@MainActor
final class SessionLibraryViewModel: ObservableObject {
    @Published private(set) var sessions: [SessionListItem] = []
    @Published private(set) var statusText = String(localized: "library_status_ready")
    @Published private(set) var isLoading = false

    private let store = CloudKitStore()

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        statusText = String(localized: "library_status_loading")
        defer { isLoading = false }

        // Retention cleanup doesn't need to block the list from appearing —
        // run it alongside instead of ahead of the fetch below.
        Task { _ = try? await store.sweepExpired() }

        do {
            let fetchedSessions = try await store.fetchSessions()
            let store = store
            let eventCounts = await withTaskGroup(of: (String, Int).self) { group in
                for session in fetchedSessions {
                    group.addTask {
                        let events = (try? await store.fetchEvents(sessionID: session.id, limit: 200)) ?? []
                        return (session.id, events.count)
                    }
                }
                var counts: [String: Int] = [:]
                for await (sessionID, count) in group {
                    counts[sessionID] = count
                }
                return counts
            }
            sessions = fetchedSessions.map { session in
                SessionListItem(session: session, eventCount: eventCounts[session.id] ?? 0)
            }
            statusText = sessions.isEmpty
                ? String(localized: "library_status_empty")
                : String(format: String(localized: "library_status_loaded_format"), sessions.count)
        } catch {
            statusText = String(format: String(localized: "library_status_failed_format"), error.localizedDescription)
        }
    }

    func delete(at offsets: IndexSet) {
        let targets = offsets.map { sessions[$0] }
        sessions.remove(atOffsets: offsets)

        Task {
            for target in targets {
                do {
                    try await store.deleteSession(id: target.id)
                } catch {
                    statusText = String(format: String(localized: "library_status_failed_format"), error.localizedDescription)
                }
            }
            await load()
        }
    }

    func durationText(for item: SessionListItem) -> String {
        guard let duration = item.duration else {
            return String(localized: "library_session_live")
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: String(localized: "library_duration_format"), minutes, seconds)
    }
}
