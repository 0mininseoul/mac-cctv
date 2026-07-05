import CCTVKit
import SwiftUI

struct SessionRouteView: View {
    @StateObject private var viewModel: SessionRouteViewModel

    init(sessionID: String) {
        _viewModel = StateObject(wrappedValue: SessionRouteViewModel(sessionID: sessionID))
    }

    var body: some View {
        Group {
            if let session = viewModel.session {
                SessionPlaybackView(session: session)
            } else {
                List {
                    Section("playback_status_section") {
                        Text(viewModel.statusText)
                            .textSelection(.enabled)
                    }
                }
                .navigationTitle("library_title")
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

@MainActor
final class SessionRouteViewModel: ObservableObject {
    @Published private(set) var session: SurveillanceSession?
    @Published private(set) var statusText = String(localized: "playback_status_loading")

    private let sessionID: String
    private let store = CloudKitStore()

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func load() async {
        guard session == nil else {
            return
        }

        do {
            session = try await store.fetchSession(id: sessionID)
        } catch {
            statusText = String(format: String(localized: "library_status_failed_format"), error.localizedDescription)
        }
    }
}
