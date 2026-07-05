import SwiftUI

@main
struct CCTVCompanionApp: App {
    init() {
        M0ProbeLaunchHandler.runIfRequested()
        M4PlaybackLaunchHandler.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SessionLibraryView()
            }
        }
    }
}
