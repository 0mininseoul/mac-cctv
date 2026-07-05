import SwiftUI

@main
struct CCTVCompanionApp: App {
    @StateObject private var eventNavigationRouter = EventNavigationRouter.shared

    init() {
        M0ProbeLaunchHandler.runIfRequested()
        M4PlaybackLaunchHandler.runIfRequested()
        if M6LiveLaunchHandler.runIfRequested() {
            return
        }
        if M5EventPollLaunchHandler.runIfRequested() {
            return
        }
        EventNotificationBootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $eventNavigationRouter.sessionPath) {
                SessionLibraryView()
                    .navigationDestination(for: String.self) { sessionID in
                        SessionRouteView(sessionID: sessionID)
                    }
            }
            .task {
                await eventNavigationRouter.openPendingEventIfNeeded()
            }
        }
    }
}
